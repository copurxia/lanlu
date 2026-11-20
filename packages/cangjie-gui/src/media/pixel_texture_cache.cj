package cui.media

import std.collection.{ArrayList, HashMap, HashSet}
import std.env.getVariable
import std.fs.{File, OpenMode, Path}
import std.time.MonoTime
import cui.base.{Renderer, Texture, TextureBlendMode, TextureScaleMode}

/*
 * 进程级像素纹理缓存：按调用方给的 key 键控，绑定单一渲染器（DesktopApp 驱动的唯一窗口）。
 * 与按文件路径键控的 texture_cache 不同，这里的像素直接来自内存（例如 vips 解码出的
 * RGBA 数组）。支持两阶段用法：stagePixelImage 只登记像素（不需要渲染器，UI 线程任意
 * 时机可调），pixelTexture 在首次绘制时才用当前渲染器把 staged 像素上传成纹理（惰性
 * 创建，与 sharedTexture 哲学一致）；registerPixelImage 保留一步到位注册的能力。
 * registerPixelImage 上传失败缓存 None（与 texture_cache 的失败语义一致），修正后用
 * 同 key 重新注册即可；staged 像素惰性上传失败则保留像素逐帧重试（见 pixelTexture）。
 * 仅 UI 线程使用，与框架其余部分一致。
 */
private var pixelCacheRenderer: ?Renderer = None
private let pixelTextures = HashMap<String, ?Texture>()

// ===== 图像诊断环形缓冲（G2）=====
// 旧实现：pixelTexture / PixelImageView.draw 每次调用都同步读写 $HOME/img_diag.txt
// （exists + 整文件 readFrom + UTF-8 解码 + contains 线性扫描）。PixelImageView 一帧内
// 串起 3 处（本函数 + pivDraw + lgpu 侧 drawTexture/drawTextureRounded），真机上
// 340~440µs/次 × 每图每帧 3 次，直接吃掉半个帧预算；img_diag.txt 还随新 key 单调变大。
// 现在：绘制路径只做内存 append（环形 200 条，同一 tag 只记首条，保持旧"首见即记"
// 语义）；LANLU_IMG_DIAG=1 时按调用次数限频（每 300 次 ≈5s）append 落盘一次，
// 也可随时手动 dumpImgDiag()。渲染路径上不再有任何文件系统调用。
// 本包约定仅 UI 线程使用（见文件头），故缓冲不加锁。
private const IMG_DIAG_CAP: Int64 = 200
private const IMG_DIAG_SEEN_CAP: Int64 = 4096
private const IMG_DIAG_DUMP_EVERY: Int64 = 300
private let IMG_DIAG_ENABLED: Bool = (getVariable("LANLU_IMG_DIAG") ?? "0") == "1"
private let IMG_DIAG_HOME: String = getVariable("HOME") ?? "."
private let IMG_DIAG_LINES = ArrayList<String>()
private let IMG_DIAG_SEEN = HashSet<String>()
private var imgDiagCallCount: Int64 = 0

/// 追加一条诊断（不去重，失败类逐条记录；缓冲满丢最旧）。仅 UI 线程调用。
func imgDiagPush(line: String): Unit {
    if (!IMG_DIAG_ENABLED) {
        return
    }
    IMG_DIAG_LINES.add(line)
    if (IMG_DIAG_LINES.size > IMG_DIAG_CAP) {
        IMG_DIAG_LINES.remove(at: 0)
    }
}

/// 查重并在未见过时登记 tag（返回 false = 调用方应记录该条）。
/// 仓颉 lambda 捕获可变局部变量后不能作为值传递，故"惰性构造"由调用方按
/// `imgDiagSeen(tag)` + `imgDiagPush(line)` 两步展开。
func imgDiagSeen(tag: String): Bool {
    if (IMG_DIAG_SEEN.contains(tag)) {
        return true
    }
    if (IMG_DIAG_SEEN.size >= IMG_DIAG_SEEN_CAP) {
        // 满员后不再登记新 tag（视作已见过）：避免 clear 后重新记账的风暴。
        return true
    }
    IMG_DIAG_SEEN.add(tag)
    return false
}

/// seen 未命中时记一条。
func imgDiagPushNew(tag: String, line: String): Unit {
    if (!IMG_DIAG_ENABLED) {
        return
    }
    if (imgDiagSeen(tag)) {
        return
    }
    imgDiagPush(line)
}

/// 把环形缓冲落盘一次（append，不整文件重写）。渲染路径不要调用。
public func dumpImgDiag(force!: Bool = false): Unit {
    if (!IMG_DIAG_ENABLED && !force) {
        return
    }
    if (IMG_DIAG_LINES.size == 0) {
        return
    }
    let builder = StringBuilder()
    builder.append("==== img diag dump ====")
    builder.append("\n")
    for (line in IMG_DIAG_LINES) {
        builder.append(line)
        builder.append("\n")
    }
    try {
        let f = File(Path(IMG_DIAG_HOME + "/img_diag.txt"), OpenMode.Append)
        f.write(builder.toString().toArray())
        f.close()
    } catch (_) {}
}

// pixelTexture 的调用频率就是绘制频率，借它做限频 dump（仅在开关打开时有额外成本）。
func imgDiagMaybeDump(): Unit {
    if (!IMG_DIAG_ENABLED) {
        return
    }
    imgDiagCallCount++
    if (imgDiagCallCount == 1 || imgDiagCallCount % IMG_DIAG_DUMP_EVERY == 0) {
        dumpImgDiag()
    }
}

// LANLU_PERF=1 纹理上传打点（client-next 性能评估用，默认关闭零开销）：staged 像素的
// 惰性上传发生在 UI 线程绘制路径上，是帧成本热点之一。这里只累计次数/总耗时/最大单次，
// 由调用方（client-next pump）周期拉取并复位，避免框架直接打印。
private let pixelPerfEnabled = getVariable("LANLU_PERF") == Some("1")
private var pixelUploadCount: Int64 = 0
private var pixelUploadTotalUs: Int64 = 0
private var pixelUploadMaxUs: Int64 = 0

// 返回 (上传次数, 总耗时us, 最大单次us)。
public func pixelUploadPerfStats(): (Int64, Int64, Int64) {
    (pixelUploadCount, pixelUploadTotalUs, pixelUploadMaxUs)
}

public func pixelUploadPerfReset(): Unit {
    pixelUploadCount = 0
    pixelUploadTotalUs = 0
    pixelUploadMaxUs = 0
}

private func pixelUploadPerfMark(t0: MonoTime): Unit {
    if (!pixelPerfEnabled) {
        return
    }
    let us = (MonoTime.now() - t0).toMicroseconds()
    pixelUploadCount++
    pixelUploadTotalUs += us
    if (us > pixelUploadMaxUs) {
        pixelUploadMaxUs = us
    }
}

// 已登记未上屏的像素：纹理惰性创建的原料。纯 CPU 侧数据，不随渲染器换绑失效。
// 两种形态：Array<UInt8>（旧路径，registerPixelImage 等）或原生指针（libvips 输出，
// stageNativePixelImage）。原生形态持有唯一所有权，释放经 releaser（唯一所有者），
// 覆盖被替换/淘汰/上传完成/清缓存等全部路径；上传失败按冷却重试（见 pixelTexture）。
private class StagedPixels {
    let width: Int32
    let height: Int32
    let pixels: Array<UInt8>
    let nativePtr: ?CPointer<UInt8>
    let releaser: ?PixelReleaser
    var nextRetryAt: ?MonoTime

    init(width: Int32, height: Int32, pixels: Array<UInt8>) {
        this.width = width
        this.height = height
        this.pixels = pixels
        this.nativePtr = None
        this.releaser = None
        this.nextRetryAt = None
    }

    init(width: Int32, height: Int32, pointer: CPointer<UInt8>, releaser: PixelReleaser) {
        this.width = width
        this.height = height
        this.pixels = Array<UInt8>(0, repeat: 0)
        this.nativePtr = Some(pointer)
        this.releaser = Some(releaser)
        this.nextRetryAt = None
    }
}
private let stagedPixels = HashMap<String, StagedPixels>()

// 原生 staged 像素的释放回调（接口而非闭包：避免仓颉 1.1.3 闭包跨线程/参数传递时
// 写捕获字段触发 GC WriteStaticRef 屏障 SIGSEGV；类方法调用不触发）。
public interface PixelReleaser {
    func release(): Unit
}

/*
 * 已上传纹理的记账元数据：尺寸（字节预算按 width*height*4 记账）与是否 streaming。
 * streaming 纹理在同 key 同尺寸的重复 register 时走 SDL_UpdateTexture 原地更新，
 * 不再 close+重建（视频播放每帧 register 的场景，见 #5）。
 */
private class PixelTextureMeta {
    let width: Int32
    let height: Int32
    let streaming: Bool

    init(width: Int32, height: Int32, streaming: Bool) {
        this.width = width
        this.height = height
        this.streaming = streaming
    }
}
private let pixelTextureMeta = HashMap<String, PixelTextureMeta>()

/*
 * LRU 淘汰：按字节预算（总预算默认 256MB，先基准 192/256 两档后定值；CPU staged/native
 * 与 GPU texture 分开记账和限额）而非条数——一张 2000×3000 RGBA 页面约 24MB，按条数
 * 淘汰在长阅读会话中会膨胀到 GB 级（见 #6）。staged 像素与已上传纹理统一按 width*height*4
 * 记账，任一预算超限时按最久未使用逐出：关闭 SDL 纹理、丢弃像素内存（原生像素经
 * releaser 释放）。仅 UI 线程访问，与框架其余部分一致无需加锁。
 * 被逐出的 key 经 onPixelImageEvicted 回调通知应用层：应用把对应加载状态复位后，
 * 仍在屏的旧 widget 下帧重建时重新请求/显示占位，而不是对着已逐出的纹理绘制空白。
 */
public var pixelCacheMaxBytes: Int64 = 256 * 1024 * 1024 // 总预算（原 512MB 下调，见 #6 基准）
public var pixelCacheStagedMaxBytes: Int64 = 96 * 1024 * 1024 // CPU staged/native 分项限额
public var pixelCacheTextureMaxBytes: Int64 = 256 * 1024 * 1024 // GPU texture 分项限额
private var stagedBytes: Int64 = 0
private var textureBytes: Int64 = 0
private var evictCount: Int64 = 0 // 诊断：累计淘汰次数（区分重解码抖动的依据）
// LRU 双向链 + 哈希索引：队首最久未用，队尾最新。触碰/逐出/失效都经索引 O(1) 定位节点，
// 替代原 ArrayList 线性扫描（每帧每张在屏图都触碰，条目数百时扫描本身是帧成本热点）。
private class PixelLruNode {
    let key: String
    var prev: ?PixelLruNode = None
    var next: ?PixelLruNode = None

    init(key: String) {
        this.key = key
    }
}
private var pixelLruHead: ?PixelLruNode = None
private var pixelLruTail: ?PixelLruNode = None
private var pixelLruSize: Int64 = 0
private let pixelLruIndex = HashMap<String, PixelLruNode>()
public var onPixelImageEvicted: ?(String) -> Unit = None

// UI 每帧纹理上传预算（P1.6 流水线第 3 级）：以 16ms 时间窗近似一帧，超预算的上传
// 顺延下一帧，避免多张图同时到货在同一帧集中上传导致卡顿。0 = 不限额。
public var pixelUploadBudgetBytes: Int64 = 16 * 1024 * 1024
private var uploadedThisWindow: Int64 = 0
private var uploadWindowStart = MonoTime.now()

// pixelTexture 上传前的帧预算检查：超预算返回 false（调用方顺延到下一帧）。
private func pixelUploadAllowed(bytes: Int64): Bool {
    if (pixelUploadBudgetBytes <= 0) {
        return true
    }
    let now = MonoTime.now()
    if ((now - uploadWindowStart).toMilliseconds() >= 16) {
        uploadWindowStart = now
        uploadedThisWindow = 0
    }
    if (uploadedThisWindow + bytes > pixelUploadBudgetBytes) {
        return false
    }
    uploadedThisWindow += bytes
    true
}

private func pixelBytesOf(width: Int32, height: Int32): Int64 {
    Int64(width) * Int64(height) * 4
}

// 测试与诊断用：当前纳入预算的 (staged 字节, 纹理字节, 条目数, 淘汰次数)。
internal func pixelCacheTrackedBytes(): (Int64, Int64) {
    (stagedBytes, textureBytes)
}

// 诊断：CPU staged/native 字节、GPU 纹理字节、条目数、累计淘汰次数。
internal func pixelCacheDiagnostics(): (Int64, Int64, Int64, Int64) {
    (stagedBytes, textureBytes, pixelLruSize, evictCount)
}

// 公开导出（性能诊断用）：外部包（client-next 基准）经 cui 引用读取。
public func pixelCacheDiagnosticsPublic(): (Int64, Int64, Int64, Int64) {
    pixelCacheDiagnostics()
}

// 摘出链中节点（不动索引；调用方随后决定复接或移除）。节点必须在链上。
private func unlinkPixelLruNode(node: PixelLruNode): Unit {
    match (node.prev) {
        case Some(prev) => prev.next = node.next
        case None => pixelLruHead = node.next
    }
    match (node.next) {
        case Some(next) => next.prev = node.prev
        case None => pixelLruTail = node.prev
    }
    node.prev = None
    node.next = None
    pixelLruSize--
}

// 把 key 作为新节点接到队尾并登记索引。
private func appendPixelLruNode(key: String): Unit {
    let node = PixelLruNode(key)
    match (pixelLruTail) {
        case Some(tail) =>
            tail.next = node
            node.prev = tail
        case None => pixelLruHead = node
    }
    pixelLruTail = node
    pixelLruIndex[key] = node
    pixelLruSize++
}

// LRU 触碰：移到队尾（哈希索引定位 + 摘接，O(1)；顺序语义与原线性扫描逐字节一致）。
private func touchPixelKey(key: String): Unit {
    match (pixelLruIndex.get(key)) {
        case Some(node) => unlinkPixelLruNode(node)
        case None => ()
    }
    appendPixelLruNode(key)
}

// 移除 key 的 staged 像素并记账（原生形态同时释放指针所有权）；不存在则无操作。返回是否存在过。
private func removeStagedEntry(key: String): Unit {
    match (stagedPixels.get(key)) {
        case Some(staged) =>
            stagedBytes -= pixelBytesOf(staged.width, staged.height)
            let _ = stagedPixels.remove(key)
            match (staged.releaser) {
                case Some(r) => r.release()
                case None => ()
            }
        case None => ()
    }
}

// 关闭并移除 key 的纹理条目（含 None 失败条目）并记账；不存在则无操作。
private func removeTextureEntry(key: String): Unit {
    match (pixelTextures.get(key)) {
        case Some(Some(texture)) => texture.close()
        case _ => ()
    }
    let _ = pixelTextures.remove(key)
    match (pixelTextureMeta.get(key)) {
        case Some(meta) =>
            textureBytes -= pixelBytesOf(meta.width, meta.height)
            let _ = pixelTextureMeta.remove(key)
        case None => ()
    }
}

private func removeLruKey(key: String): Unit {
    match (pixelLruIndex.remove(key)) {
        case Some(node) => unlinkPixelLruNode(node)
        case None => ()
    }
}

// 逐出一个 key：关纹理、弃像素、移出 LRU 并通知应用层。
private func evictPixelKey(key: String): Unit {
    removeTextureEntry(key)
    removeStagedEntry(key)
    removeLruKey(key)
    evictCount++
    match (onPixelImageEvicted) {
        case Some(hook) => hook(key)
        case None => ()
    }
}

// 新增条目后调用：总预算或任一 CPU/GPU 分项预算超限则从队首（最久未用）逐个逐出。
// 队尾（最新登记/触碰的一张）始终保留——单张图大于预算时不会把它自己逐出去
//（那会导致每帧重上传的抖动）。
private func evictPixelLruIfNeeded(): Unit {
    let total = max(pixelCacheMaxBytes, Int64(0))
    let stagedCap = max(pixelCacheStagedMaxBytes, Int64(0))
    let textureCap = max(pixelCacheTextureMaxBytes, Int64(0))
    while (pixelLruSize > 1 &&
        (stagedBytes + textureBytes > total || stagedBytes > stagedCap || textureBytes > textureCap)) {
        match (pixelLruHead) {
            case Some(head) => evictPixelKey(head.key)
            case None => break // 防御：size > 1 时队首必在
        }
    }
}

/*
 * 登记一张待显示的内存像素图：只存像素，不碰渲染器与纹理。
 * pixels 按 R,G,B,A 字节序排列，长度应为 width*height*4（不符时惰性上传阶段失败，
 * staged 像素保留并逐帧重试，见 pixelTexture）。同 key 重复登记以最后一次为准
 * （字节记账随之替换，旧 staged 占用立即释放）。
 */
public func stagePixelImage(key: String, width: Int32, height: Int32, pixels: Array<UInt8>): Unit {
    // 同 key 已有纹理时先关闭并移除：否则 pixelTexture 会优先返回旧纹理，新 staged
    // 像素永远得不到上传（切服后同 asset id 串图场景）。新像素下帧经 staged 重新上传。
    removeTextureEntry(key)
    removeStagedEntry(key)
    stagedPixels[key] = StagedPixels(width, height, pixels)
    stagedBytes += pixelBytesOf(width, height)
    touchPixelKey(key)
    evictPixelLruIfNeeded()
}

/*
 * 登记一张待显示的 libvips 原生 RGBA 像素图：staged 条目接管指针所有权，释放经
 * releaser.release()（必须幂等，见 NativeDecodedImage.close）。同 key 重复登记以最后一次
 * 为准：旧条目（含其原生指针）立即释放。仅 UI 线程调用（同 stagePixelImage）。
 * 指针字节序 R,G,B,A，长度应为 width*height*4（不符时惰性上传阶段失败并冷却重试）。
 */
public func stageNativePixelImage(key: String, width: Int32, height: Int32, pointer: CPointer<UInt8>,
    releaser: PixelReleaser): Unit {
    removeTextureEntry(key)
    removeStagedEntry(key)
    stagedPixels[key] = StagedPixels(width, height, pointer, releaser)
    stagedBytes += pixelBytesOf(width, height)
    touchPixelKey(key)
    evictPixelLruIfNeeded()
}

/*
 * 注册（或替换）一张内存像素图：pixels 按 R,G,B,A 字节序排列，长度必须为 width*height*4。
 * 渲染器取自调用方当前帧。同 key 同尺寸的重复注册复用既有 streaming 纹理走
 * SDL_UpdateTexture 原地更新（视频帧场景，免去每帧纹理分配/销毁）；尺寸变化或首次
 * 注册时才重建纹理。纹理创建/更新失败（含像素长度不符）时缓存 None 而不是抛出，
 * 避免一次坏数据打死帧循环。
 */
public func registerPixelImage(renderer: Renderer, key: String, width: Int32, height: Int32,
    pixels: Array<UInt8>): Unit {
    adoptPixelRenderer(renderer)
    // 一步注册顶替两阶段登记：清掉同 key 可能残留的 staged 像素，防止日后被误上传。
    removeStagedEntry(key)
    // streaming 原地更新：同 key、同尺寸、纹理未关闭——像素换新而纹理句柄不变，
    // 调用方持有的 Texture 引用（pixelTexture 的返回值）继续有效。
    match ((pixelTextures.get(key), pixelTextureMeta.get(key))) {
        case (Some(Some(existing)), Some(meta)) where meta.streaming && meta.width == width && meta.height == height &&
            !existing.isClosed() =>
            try {
                renderer.updateStreamingTextureRgba(existing, width, height, pixels)
                touchPixelKey(key)
                evictPixelLruIfNeeded()
                return
            } catch (_: Exception) {
                () // 原地更新失败：落到下面的重建路径（坏数据按旧语义缓存 None）。
            }
        case _ => ()
    }
    // 替换同 key 旧纹理前先 close，避免泄漏显存。
    removeTextureEntry(key)
    match (uploadStreamingPixelTexture(renderer, width, height, pixels)) {
        case Some(texture) =>
            pixelTextures[key] = Some(texture)
            pixelTextureMeta[key] = PixelTextureMeta(width, height, true)
            textureBytes += pixelBytesOf(width, height)
        case None => pixelTextures[key] = Option<Texture>.None
    }
    touchPixelKey(key)
    evictPixelLruIfNeeded()
}

/** 关闭并移除 key 对应的像素纹理与 staged 像素；不存在的 key 直接忽略。 */
public func invalidatePixelImage(key: String): Unit {
    removeTextureEntry(key)
    removeStagedEntry(key)
    removeLruKey(key)
}

/** 清空像素纹理缓存与 staged 像素，关闭其中所有纹理。 */
public func clearPixelImages(): Unit {
    for ((_, entry) in pixelTextures) {
        match (entry) {
            case Some(texture) => texture.close()
            case None => ()
        }
    }
    pixelTextures.clear()
    pixelTextureMeta.clear()
    stagedPixels.clear()
    stagedBytes = 0
    textureBytes = 0
    evictCount = 0
    pixelLruHead = None
    pixelLruTail = None
    pixelLruSize = 0
    pixelLruIndex.clear()
}

// 查询 key 对应的像素纹理（不触发加载），供 PixelImageView 每帧绘制时调用。
// 已有纹理直接返回；只有 staged 像素时当场用当前渲染器尝试上传建纹理——成功则缓存纹理
// 并清掉 staged，失败则保留 staged 像素且不落 None 条目（下一帧绘制自动重试上传，
// 避免一次瞬时失败把图片永久卡在“ready 但绘制空白”）；两者皆无返回 None。
// public（原 protected）：阅读器自绘舞台（翻页滑动/双页并排/中心缩放）需要直接取纹理
// 自绘，PixelImageView 的固定绘制路径表达不了位移动画。调用方注意：纹理跨 widget 共享，
// setAlpha 等状态改动后必须复原。
public func pixelTexture(renderer: Renderer, key: String): ?Texture {
    adoptPixelRenderer(renderer)
    // 真机诊断（G2）：改内存环形缓冲，首见 key 记一条；不再每次调用读写 img_diag.txt。
    imgDiagPushNew("pixelTexture ${key}", "[diag] pixelTexture key=${key}")
    imgDiagMaybeDump()
    match (pixelTextures.get(key)) {
        case Some(entry) =>
            touchPixelKey(key)
            return entry
        case None => ()
    }
    if (!stagedPixels.contains(key)) {
        // 诊断（G2）：既无纹理也无 staged（stageNativePixelImage 未生效或被逐出），改环形缓冲。
        imgDiagPushNew("noStaged ${key}", "[diag] noStaged ${key}")
    }
    match (stagedPixels.get(key)) {
        case Some(staged) =>
            // 帧上传预算：超限顺延下一帧（先于两种上传路径统一检查）。
            let bytes = pixelBytesOf(staged.width, staged.height)
            if (!pixelUploadAllowed(bytes)) {
                // 诊断（G2）：改环形缓冲（超预算期间逐帧进入，旧实现等于逐帧整文件读写）。
                imgDiagPushNew("budgetDeny ${key}",
                    "[diag] budgetDeny key=${key} bytes=${bytes} window=${uploadedThisWindow} budget=${pixelUploadBudgetBytes}")
                return None
            }
            // 原生形态：从指针直接建纹理（SDL 同步拷贝像素），成功即释放 staged 所有权；
            // 失败保留像素并按冷却期重试（持续失败只是每帧多一次时间比较，不打死帧循环）。
            match (staged.nativePtr) {
                case Some(ptr) =>
                    match (staged.nextRetryAt) {
                        case Some(at) =>
                            if (MonoTime.now() < at) {
                                // 诊断（G2）：改环形缓冲（冷却期内逐帧进入）。
                                imgDiagPushNew("cooldown ${key}", "[diag] cooldown key=${key}")
                                return None
                            }
                        case None => ()
                    }
                    let upT0 = MonoTime.now()
                    let uploadedNative = uploadNativePixelTexture(renderer, staged.width, staged.height, ptr)
                    pixelUploadPerfMark(upT0)
                    match (uploadedNative) {
                        case Some(texture) =>
                            removeStagedEntry(key)
                            pixelTextures[key] = Some(texture)
                            pixelTextureMeta[key] = PixelTextureMeta(staged.width, staged.height, false)
                            textureBytes += pixelBytesOf(staged.width, staged.height)
                            touchPixelKey(key)
                            // 诊断（G2）：改环形缓冲（每 key 一次）。
                            imgDiagPushNew("uploadedOK ${key}",
                                "[diag] uploadedOK key=${key} ${staged.width}x${staged.height} texId=${texture.id}")
                            return Some(texture)
                        case None =>
                            // 冷却重试：避免坏数据每帧无限高速重试（SDL 建纹理/拷贝开销）。
                            staged.nextRetryAt = Some(MonoTime.now() + Duration.millisecond * 500)
                            return None
                    }
                case None => ()
            }
            let upT0 = MonoTime.now()
            let uploadedArr = uploadPixelTexture(renderer, staged.width, staged.height, staged.pixels)
            pixelUploadPerfMark(upT0)
            match (uploadedArr) {
                case Some(texture) =>
                    // 上传成功：像素已固化进 GPU 纹理，staged 原料可以丢弃。
                    removeStagedEntry(key)
                    pixelTextures[key] = Some(texture)
                    pixelTextureMeta[key] = PixelTextureMeta(staged.width, staged.height, false)
                    textureBytes += pixelBytesOf(staged.width, staged.height)
                    touchPixelKey(key)
                    return Some(texture)
                case None =>
                    // 上传失败：保留 staged 像素、不缓存 None，下一帧用同一渲染器重试。
                    // 持续性失败（如像素长度非法）只是每帧多试一次，绘制保持空白，不打死帧循环。
                    return None
            }
        case None => return None
    }
}

// 纹理只在创建它的渲染器上有效。渲染器换绑（窗口重建）时丢弃旧纹理条目且不 close：
// SDL 已随渲染器销毁了它们，再 close 会访问已释放的句柄。
// staged 像素是 CPU 侧数据，与渲染器无关，换绑后保留，下次绘制在新渲染器上重建纹理。
private func adoptPixelRenderer(renderer: Renderer): Unit {
    match (pixelCacheRenderer) {
        case Some(existing) =>
            if (!refEq(existing, renderer)) {
                pixelTextures.clear()
                pixelTextureMeta.clear()
                textureBytes = 0
                // 纹理条目随渲染器失效，LRU 里对应记录也一并清掉（staged 像素保留，
                // 下次绘制在新渲染器上重建纹理时重新入列）。保序过滤：留在链上的相对顺序不变。
                var node = pixelLruHead
                while (let Some(current) <- node) {
                    let next = current.next
                    if (!stagedPixels.contains(current.key)) {
                        let _ = pixelLruIndex.remove(current.key)
                        unlinkPixelLruNode(current)
                    }
                    node = next
                }
                pixelCacheRenderer = Some(renderer)
            }
        case None => pixelCacheRenderer = Some(renderer)
    }
}

private func uploadPixelTexture(renderer: Renderer, width: Int32, height: Int32, pixels: Array<UInt8>): ?Texture {
    // textureFromPixelsRgba 在同一次钉扎内完成 surface→texture（纹理同步拷贝像素），
    // 不存在表面引用未钉扎内存的窗口。
    try {
        let texture = renderer.textureFromPixelsRgba(width, height, pixels)
        texture.setBlendMode(TextureBlendMode.Blend)
        texture.setScaleMode(TextureScaleMode.Linear)
        Some(texture)
    } catch (_: Exception) {
        None
    }
}

// 原生指针上传：textureFromNativeRgba（STATIC 纹理，SDL 同步拷贝），失败返回 None。
private func uploadNativePixelTexture(renderer: Renderer, width: Int32, height: Int32,
    pointer: CPointer<UInt8>): ?Texture {
    try {
        let texture = renderer.textureFromNativeRgba(width, height, pointer)
        texture.setBlendMode(TextureBlendMode.Blend)
        texture.setScaleMode(TextureScaleMode.Linear)
        Some(texture)
    } catch (e: Exception) {
        // 真机诊断（G2）：改环形缓冲（每 尺寸 一次），不再同步读写 img_diag.txt。
        imgDiagPushNew("uploadNative ${width}x${height}",
            "[diag] uploadNative FAIL ${width}x${height}: ${e.message}")
        None
    }
}

// register 路径的上传：streaming 纹理（可经 SDL_UpdateTexture 原地更新）+ 初始像素写入。
private func uploadStreamingPixelTexture(renderer: Renderer, width: Int32, height: Int32,
    pixels: Array<UInt8>): ?Texture {
    try {
        let texture = renderer.streamingTextureFromPixelsRgba(width, height, pixels)
        texture.setBlendMode(TextureBlendMode.Blend)
        texture.setScaleMode(TextureScaleMode.Linear)
        Some(texture)
    } catch (_: Exception) {
        None
    }
}
