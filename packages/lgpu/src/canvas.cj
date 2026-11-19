package lgpu

import std.env.getVariable
import std.fs.{File, OpenMode, Path, exists}
import std.collection.{ArrayList, HashMap, HashSet}
import std.sync.Mutex
import lbase.{Canvas, Color, Pen, Rect}

// lgpu（wgpu）实现的 Canvas：把视图图元映射到 L 层的 SDF/纹理管线。
//
// 与 lgui.Renderer 的差异（迁移期可见）：
// - 文本度量来自 lgpu 自己的字形光栅化（ab_glyph），与 fontkit 的度量在极端字号下
//   可能差 1px；切换后如需完全一致，再把 fontkit 的度量接进来。
// - 柔和圆角（feather）走解析高斯阴影（lgpu_draw_shadow，gpu.rs mode 4）。

// 颜色空间：UI 画进 Rgba8Unorm 离屏目标（gamma 空间混合），blit 转线性上屏。
// （方案C，真机逐字节验证：深色底 (11,11,13)、面板 (22,22,26) 等于设计值。
// 旧的 CPU 侧 sRGB→linear 预解码与 blit 二选一——预解码会让 blit 版二次变暗。）

/// alpha 是线性量，不走 sRGB 解码。
func alphaChannel(v: UInt8): Float32 {
    Float32(v) / 255.0
}

/// 颜色通道：直传（gamma 空间）。离屏目标是 Unorm，混合与设计稿同空间；
/// 上屏时由 blit 转线性、硬件编码还原。
func channel(v: UInt8): Float32 {
    Float32(v) / 255.0
}

// 联调 trace：把关键步骤追加到 $HOME/probe_trace.txt（LANLU_PROBE_LGPU=1 时）。
// G2：环境变量改为启动期读取一次（probeTrace 在 uploadTexture/releaseTexture 等每次
// 调用的路径上都会被调到）；落盘改成 open-append-close，去掉旧的整文件读改写。
private let PROBE_LGPU_ENABLED: Bool = (getVariable("LANLU_PROBE_LGPU") ?? "0") == "1"
private let DIAG_HOME_DIR: String = getVariable("HOME") ?? "."
private let NO_CLIP_FORCED: Bool = (getVariable("LANLU_NO_CLIP") ?? "0") == "1"

func probeTrace(line: String): Unit {
    if (!PROBE_LGPU_ENABLED) {
        return
    }
    let path = Path(DIAG_HOME_DIR + "/probe_trace.txt")
    try {
        let f = File(path, OpenMode.Append)
        f.write((line + nline()).toArray())
        f.close()
    } catch (_) {}
}

func lastErrorText(): String {
    unsafe { lgpu_last_error().toString() }
}

func nline(): String {
    String.fromUtf8(Array<UInt8>(1, repeat: 10))
}

// ===== 图像诊断环形缓冲（G2）=====
// 旧实现：uploadTexture / drawTexture / drawTextureRounded 每次调用都同步读写
// $HOME/img_diag.txt（exists + 整文件 readFrom + UTF-8 解码 + contains 线性扫描，
// 实测 340~440µs/次，PixelImageView 路径每图每帧 3 次），且 img_diag.txt 随新纹理
// id 单调变大、读代价线性恶化。现在：绘制/上传路径只做内存 append（环形 200 条），
// LANLU_IMG_DIAG=1 时经 LgpuCanvas.present 周期性落盘（append，不整文件重写），
// 也可随时手动调用 dumpImageDiag()。渲染路径上不再有任何文件系统调用。
private const IMG_DIAG_CAP: Int64 = 200
private const IMG_DIAG_SEEN_CAP: Int64 = 4096
private let IMG_DIAG_ENABLED: Bool = (getVariable("LANLU_IMG_DIAG") ?? "0") == "1"
private let IMG_DIAG_MUTEX = Mutex()
private let IMG_DIAG_LINES = ArrayList<String>()
// 幂等去重：保持旧语义"同一 id/key 只记首条"（如 upload id=7、pivDraw asset:42）。
private let IMG_DIAG_SEEN = HashSet<String>()

/// 追加一条诊断（不去重，失败类逐条记录；缓冲满丢最旧）。
/// 关闭（LANLU_IMG_DIAG≠1）时为空操作——热路径调用方无须自行判断。
func imgDiagPush(line: String): Unit {
    if (!IMG_DIAG_ENABLED) {
        return
    }
    synchronized(IMG_DIAG_MUTEX) {
        IMG_DIAG_LINES.add(line)
        if (IMG_DIAG_LINES.size > IMG_DIAG_CAP) {
            IMG_DIAG_LINES.remove(at: 0)
        }
    }
}

/// 查重并在未见过时登记 tag（返回 false = 调用方应记录该条）。
/// 仓颉 lambda 捕获可变局部变量后不能作为值传递，故"惰性构造"由调用方按
/// `imgDiagSeen(tag)` + `imgDiagPush(line)` 两步展开。
func imgDiagSeen(tag: String): Bool {
    synchronized(IMG_DIAG_MUTEX) {
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

/// 把环形缓冲落盘一次（append，不整文件重写）。渲染路径不要调用；
/// 由 present() 在 LANLU_IMG_DIAG=1 时限频调用，或联调时手动触发。
public func dumpImageDiag(force!: Bool = false): Unit {
    if (!IMG_DIAG_ENABLED && !force) {
        return
    }
    let snapshot: Array<String>
    synchronized(IMG_DIAG_MUTEX) {
        snapshot = IMG_DIAG_LINES.toArray()
    }
    if (snapshot.size == 0) {
        return
    }
    let builder = StringBuilder()
    builder.append("==== img diag dump ====")
    builder.append(nline())
    for (line in snapshot) {
        builder.append(line)
        builder.append(nline())
    }
    try {
        let f = File(Path(DIAG_HOME_DIR + "/img_diag.txt"), OpenMode.Append)
        f.write(builder.toString().toArray())
        f.close()
    } catch (_) {}
}

// G3：测量缓存键改为复合 struct——省掉每次 textWidth 的 "text\0size" 拼接 String
//（每 Label 每帧 1~3 个，命中路径也要先拼 key）。量化口径不变（1/4 pt，与 Rust 侧一致）；
// 哈希以 String.hashCode 为主、sizeQ 参与混合。
private struct TextMeasureKey <: Hashable & Equatable<TextMeasureKey> {
    let text: String
    let sizeQ: Int64

    init(text: String, sizeQ: Int64) {
        this.text = text
        this.sizeQ = sizeQ
    }

    public func hashCode(): Int64 {
        // 异或混合：Int64 乘法溢出会抛 OverflowException（真机首帧 Label::measure 实测
        // text.hashCode()*31 溢出直接 SIGABRT）。碰撞由 == 兜底，哈希质量足够。
        text.hashCode() ^ sizeQ
    }

    public operator func ==(rhs: TextMeasureKey): Bool {
        text == rhs.text && sizeQ == rhs.sizeQ
    }

    public operator func !=(rhs: TextMeasureKey): Bool {
        !(this == rhs)
    }
}

public class LgpuCanvas <: Canvas {
    // R5.1：文本测量缓存——宽度只取决于 (text, pointSize)，跨帧安全复用。
    // 之前每次 textWidth 都是一次 FFI（含 UTF-8 转换与逐字符 advance 求和），
    // 即时模式下每帧每个 Label 至少测一次；缓存命中率目标是 >95%。
    // 超过容量时整体清空（简单且足够：文本集合在稳态下远小于上限）。
    private static let MEASURE_CAP: Int64 = 8192
    private var measureCache: HashMap<TextMeasureKey, Float32> = HashMap<TextMeasureKey, Float32>()
    // 行高按字号缓存（q4 量化，同一把尺子；真实字体度量而非经验值）
    private let lineHeightCache: HashMap<Int64, Float32> = HashMap<Int64, Float32>()
    private var measureHits: Int64 = 0
    private var measureMisses: Int64 = 0

    /// 测量缓存统计 (hits, misses, entries)，供 M0 打点。
    public func measureStats(): (Int64, Int64, Int64) {
        (measureHits, measureMisses, measureCache.size)
    }

    /// 清空测量缓存（字体更换/内存压力时调用）。
    public func clearMeasureCache(): Unit {
        measureCache.clear()
        lineHeightCache.clear()
    }

    private let surface: Surface
    private let font: Font

    /// surface 由 lwindow 的窗口持有；font 用系统字体文件加载。
    public init(surface: Surface, font: Font) {
        this.surface = surface
        this.font = font
    }

    /// 离屏抓帧：把当前已录制的一帧重绘到离屏纹理并写出原始 RGBA（w*h*4）。
    /// 返回 >0 成功（w*1e6+h），<0 为错误码。
    public func captureTo(path: String): Int32 {
        this.surface.captureTo(path)
    }

    /// 供上层在尺寸变化时 reconfigure（**复用 swapchain，不要重建**，见计划 §7.1）。
    /// 用法：`surfaceRef().resize(w, h)`；**不要**调用 `configure`（那会重建 device/pipeline）。
    public func surfaceRef(): Surface {
        this.surface
    }

    /// 开始一帧：清屏 + 可选的整体缩放（用于把逻辑尺寸的 UI 画进小窗口预览）。
    public var scale: Float32 = 1.0
    // 联调：把每帧清屏色强制成不透明红，用于判断"surface 能否上屏"（与 UI 绘制无关）。
    public var forceClearRed: Bool = false

    private var firstFrame = true

    public func beginFrame(clear: Color): Unit {
        if (forceClearRed) {
            surface.beginFrame(1.0, 0.0, 0.0, 1.0)
            if (firstFrame) {
                firstFrame = false
                probeTrace("first frame RED clear scale=" + scale.toString())
            }
            return
        }
        if (firstFrame) {
            firstFrame = false
            probeTrace("first frame begin scale=" + scale.toString())
        }
        // 每帧重置裁剪栈：Renderer.beginScene 只清它自己的栈（SDL 侧），
        // 后端栈不清会跨帧累积，表现为"越画越少"（只剩顶部一条）。
        clipStack.clear()
        surface.setClip(0.0, 0.0, 0.0, 0.0)
        if (scale != 1.0) {
            surface.setTransform(scale, scale, 0.0, 0.0)
        }
        surface.beginFrame(channel(clear.r), channel(clear.g), channel(clear.b), alphaChannel(clear.a))
    }

    private var firstPresent = true
    // G2：LANLU_IMG_DIAG=1 时周期性把诊断环形缓冲落盘（首帧一次，之后每 300 帧 ≈5s@60fps）。
    private var presentCount: Int64 = 0

    public func present(): Unit {
        surface.endFrame()
        if (firstPresent) {
            firstPresent = false
            probeTrace("first frame present err=[" + lastErrorText() + "]")
        }
        presentCount += 1
        if (IMG_DIAG_ENABLED && (presentCount == 1 || presentCount % 300 == 0)) {
            dumpImageDiag()
        }
    }

    // 裁剪栈：保存逻辑坐标，应用到 surface 时按 scale 换算成世界像素。
    private var clipStack: ArrayList<Rect> = ArrayList<Rect>()

    public func pushClip(rect: Rect): Unit {
        let effective = if (clipStack.isEmpty()) {
            rect
        } else {
            clipStack[clipStack.size - 1].intersection(rect)
        }
        clipStack.add(effective)
        applyClip()
    }

    public func popClip(): Unit {
        if (!clipStack.isEmpty()) {
            clipStack.remove(at: clipStack.size - 1)
        }
        applyClip()
    }

    private func applyClip(): Unit {
        // 真机排查开关：LANLU_NO_CLIP=1 时忽略裁剪，用于判断"被裁剪掉的纹理"是否
        // 因 scissor 坐标空间不一致而整块不可见。
        // G2：pushClip/popClip 每帧多次进入，环境变量改为启动期读取一次。
        if (NO_CLIP_FORCED || clipStack.isEmpty()) {
            surface.setClip(0.0, 0.0, 0.0, 0.0)
            return
        }
        if (clipStack.isEmpty()) {
            surface.setClip(0.0, 0.0, 0.0, 0.0)
        } else {
            let top = clipStack[clipStack.size - 1]
            surface.setClip(top.x * scale, top.y * scale, top.w * scale, top.h * scale)
        }
    }

    // 纹理缓存：lgui.Texture.id → lgpu 纹理（像素经 texturePixelsSink 注册进来）。
    private var textures: HashMap<Int64, Texture> = HashMap<Int64, Texture>()
    // 纹理尺寸（用于把 source 矩形换算成 UV）
    private var textureSizes: HashMap<Int64, (Float32, Float32)> = HashMap<Int64, (Float32, Float32)>()

    /// 注册/更新一张后端纹理（由 lgui.texturePixelsSink 调用）。
    public func uploadTexture(id: Int64, width: Int32, height: Int32, pixels: Array<UInt8>): Unit {
        // 诊断（G2）：改为内存环形缓冲 + LANLU_IMG_DIAG=1 时经 present 周期性落盘。
        // 旧实现每次上传都同步读写 img_diag.txt（每次上传都读、首见该 id 才写），
        // 视频逐帧上传时等于每帧一次整文件读。语义保留：同一 id 只记首条（含像素均值）。
        // 采样像素均值（R/G/B/A）——区分「解码出来就是黑的」与「画不出来」。
        // 代价 ~1024 次采样（step = size/1024），远低于旧实现的整文件读写。
        // 整段采样只在 LANLU_IMG_DIAG=1 时执行（G2 修订：关闭时连采样都不做）。
        if (IMG_DIAG_ENABLED) {
            var diagSum: Int64 = 0
            let diagStep = max(1, pixels.size / 1024)
            var diagI: Int64 = 0
            var diagN: Int64 = 0
            while (diagI < pixels.size) {
                diagSum += Int64(pixels[diagI])
                diagN++
                diagI += diagStep
            }
            let diagAvg = if (diagN > 0) { diagSum / diagN } else { -1 }
            imgDiagPushNew("upload id=${id}",
                "[diag] upload id=${id} ${width}x${height} bytes=${pixels.size} avgByte=${diagAvg}")
        }
        if (width <= 0 || height <= 0) {
            return
        }
        let tex = match (textures.get(id)) {
            case Some(existing) => existing
            case None =>
                let created = surface.createTexture(Int64(width), Int64(height))
                textures[id] = created
                if (IMG_DIAG_ENABLED) {
                    try {
                        let p = Path(DIAG_HOME_DIR + "/map_diag.txt")
                        let prev = if (exists(p)) { String.fromUtf8(File.readFrom(p)) } else { "" }
                        let mark = if (created.debugHandle().isNull()) { "null" } else { "ptr" }
                        File.writeTo(p, (prev + "SET id=${id} tex=${mark} ${width}x${height}\n").toArray())
                    } catch (_: Exception) {}
                }
                created
        }
        textureSizes[id] = (Float32(width), Float32(height))
        probeTrace("pixels id=" + id.toString() + " " + width.toString() + "x" + height.toString())
        // 真机验证用：记录纹理上传（LANLU_PROBE_LGPU=1 时）
        if (PROBE_LGPU_ENABLED) {
            try {
                let path = Path(DIAG_HOME_DIR + "/lgpu_textures.txt")
                let f = File(path, OpenMode.Append)
                f.write(("id=" + id.toString() + " " + width.toString() + "x" + height.toString() + nline()).toArray())
                f.close()
            } catch (_) {}
        }
        tex.upload(pixels, 0, 0, Int64(width), Int64(height), Int64(width) * 4)
    }

    // 后端只收 RGBA 像素（uploadTexture）。PNG 字节入口已删除：解码归 lcodec，
    // 渲染器不再持有任何图片解码器。

    /// 释放一张后端纹理（R4：Texture.close → Canvas.releaseTexture）。
    /// 幂等：id 不存在时为空操作；释放后同 id 重新 uploadTexture 会创建新纹理。
    /// 注意：lgpu 侧纹理在本帧 draw 之后才会真正 drop（tex_instances 持有裸指针，
    /// Rust 侧 lgpu_texture_destroy 直接 free——同一帧内先画后关的顺序由 cui 的
    /// "close 发生在帧间"保证；帧内 close+draw 混用的场景由 LgpuCanvas 的 map
    /// 移除兜底：draw 找不到纹理直接跳过）。
    public func releaseTexture(id: Int64): Unit {
        match (textures.remove(id)) {
            case Some(tex) =>
                textureSizes.remove(id)
                tex.close()
                probeTrace("release tex id=" + id.toString())
            case None => ()
        }
    }

    public func drawTextureRounded(id: Int64, destination: Rect, source: ?Rect, radius: Float32,
        alpha: Float32): Unit {
        // 诊断（G2）：改内存环形缓冲（首见该 id 记一条，含当前裁剪栈快照）。
        // G2 修订：仅在 LANLU_IMG_DIAG=1 时构造字符串/查重，关闭时零成本。
        if (IMG_DIAG_ENABLED) {
            let diagTag = "drawRound id=${id}"
            if (!imgDiagSeen(diagTag)) {
                let clipTxt = if (clipStack.isEmpty()) {
                    "none"
                } else {
                    let c0 = clipStack[clipStack.size - 1]
                    "(${c0.x},${c0.y},${c0.w},${c0.h})*${scale}"
                }
                imgDiagPush("[diag] drawRound id=${id} dst=(${destination.x},${destination.y},${destination.w},${destination.h}) radius=${radius} scale=${scale} clip=${clipTxt}")
            }
        }
        let tex = match (textures.get(id)) {
            case Some(t) => t
            case None =>
                if (IMG_DIAG_ENABLED) {
                    try {
                        let p2 = Path(DIAG_HOME_DIR + "/map_diag.txt")
                        let prev2 = if (exists(p2)) { String.fromUtf8(File.readFrom(p2)) } else { "" }
                        if (!prev2.contains("MISS id=${id}")) {
                            File.writeTo(p2, (prev2 + "MISS id=${id} (draw before create!)\n").toArray())
        
                        }
                    } catch (_: Exception) {}
                }
                return
        }
        if (destination.w <= 0.0 || destination.h <= 0.0) {
            return
        }
        var u0 = 0.0f32
        var v0 = 0.0f32
        var u1 = 1.0f32
        var v1 = 1.0f32
        match (source) {
            case Some(src) =>
                match (textureSizes.get(id)) {
                    case Some(size) =>
                        let tw = size[0]
                        let th = size[1]
                        if (tw > 0.0 && th > 0.0) {
                            u0 = src.x / tw
                            v0 = src.y / th
                            u1 = (src.x + src.w) / tw
                            v1 = (src.y + src.h) / th
                        }
                    case None => ()
                }
            case None => ()
        }
        // 同 textureRc：transform 已含 scale，勿再预乘（双乘曾把封面挤出屏幕）。
        let rc = surface.textureRoundedRc(tex, destination.x, destination.y,
            destination.w, destination.h, u0, v0, u1, v1, radius, alpha)
        if (rc != 0 && IMG_DIAG_ENABLED) {
            // 失败诊断（G2）：改环形缓冲，不再写 draw_skip.txt。
            imgDiagPush("drawTextureRounded rc=" + rc.toString() + " id=" + id.toString())
        }
    }

    public func drawTexture(id: Int64, destination: Rect, source: ?Rect, alpha: Float32): Unit {
        let tex = match (textures.get(id)) {
            case Some(t) => t
            case None =>
                // 真机诊断（G2）：绘制未命中纹理表（上传丢失的最直接证据），改环形缓冲。
                if (IMG_DIAG_ENABLED) {
                    imgDiagPushNew("drawMiss id=${id}", "[diag] drawMiss id=${id} (not in map)")
                }
                return
        }
        // UV 子区：source 为空表示整张纹理
        var u0 = 0.0f32
        var v0 = 0.0f32
        var u1 = 1.0f32
        var v1 = 1.0f32
        match (source) {
            case Some(src) =>
                match (textureSizes.get(id)) {
                    case Some(size) =>
                        let tw = size[0]
                        let th = size[1]
                        if (tw > 0.0 && th > 0.0) {
                            u0 = src.x / tw
                            v0 = src.y / th
                            u1 = (src.x + src.w) / tw
                            v1 = (src.y + src.h) / th
                        }
                    case None => ()
                }
            case None => ()
        }
        // 退化矩形（宽或高 <= 0）直接跳过：lgpu 会返回 E_BAD_ARG(-5) 并抛异常。
        // 布局尚未稳定时（如 0 高度的占位图）这种情况是正常的，不该报错。
        if (destination.w <= 0.0 || destination.h <= 0.0) {
            return
        }
        // 诊断（G2）：改内存环形缓冲（首见该 id 记一条），LANLU_IMG_DIAG=1 时周期落盘。
        // G2 修订：关闭时零成本（不拼字符串、不进锁）。
        if (IMG_DIAG_ENABLED) {
            imgDiagPushNew("draw id=${id}",
                "[diag] draw id=${id} dst=(${destination.x},${destination.y},${destination.w},${destination.h}) uv=(${u0},${v0},${u1},${v1}) alpha=${alpha}")
        }
        // 注意：begin 时已 setTransform(scale,scale)，shader 会把 dst 再乘 scale。
        // 这里不得再预乘 —— 旧代码双乘导致封面被画到屏幕外（真机表现为封面全空白）。
        let rc = surface.textureRc(tex, destination.x, destination.y,
            destination.w, destination.h, u0, v0, u1, v1, 1.0, 1.0, 1.0, alpha)
        if (rc != 0 && IMG_DIAG_ENABLED) {
            // 失败诊断（G2）：改环形缓冲，不再写 draw_skip.txt（不抛异常：单张纹理失败不应中断整帧绘制）。
            imgDiagPush("drawTexture rc=" + rc.toString() + " id=" + id.toString() +
                " dst=" + destination.w.toString() + "x" + destination.h.toString())
        }
    }

    /// GPU 快照注册为 lgui 纹理 id（替代 captureTo 的读回 + 写文件 + 再上传）。
    public func snapshotTexture(id: Int64, logicalW: Float32, logicalH: Float32): ?(Int32, Int32) {
        let (tex, w, h) = match (surface.snapshotTexture()) {
            case Some(v) => v
            case None => return None
        }
        match (textures.remove(id)) {
            case Some(old) => old.close()
            case None => ()
        }
        textures[id] = tex
        // UV 按逻辑尺寸换算：调用方的 source 矩形用屏幕逻辑坐标即可精确裁剪。
        let lw = if (logicalW > 0.0) { logicalW } else { Float32(w) }
        let lh = if (logicalH > 0.0) { logicalH } else { Float32(h) }
        textureSizes[id] = (lw, lh)
        Some((Int32(w), Int32(h)))
    }

    public func layerMark(): Unit {
        surface.layerMark()
    }

    public func discardRecorded(): Unit {
        surface.discardRecorded()
    }

    public func glowRing(cx: Float32, cy: Float32, radius: Float32, stroke: Float32, outer: Float32,
            inner: Float32, color: Color, glow: Float32): Bool {
        // 矩形管线在着色器里统一乘全局变换（同 fillCircle），这里传逻辑坐标。
        surface.glowRing(cx, cy, radius, stroke, outer, inner, glow, channel(color.r), channel(color.g),
            channel(color.b), alphaChannel(color.a))
        true
    }

    public func fill(rect: Rect, color: Color): Unit {
        surface.rect(rect.x, rect.y, rect.w, rect.h, 0.0, 0.0,
            channel(color.r), channel(color.g), channel(color.b), alphaChannel(color.a))
    }

    public func fillRectGradient(rect: Rect, from: Color, to: Color, vertical: Bool): Unit {
        // 渐变直接推给 lgpu（mode 1=横向，2=纵向）
        let mode = if (vertical) { Int64(2) } else { Int64(1) }
        surface.gradient(rect.x, rect.y, rect.w, rect.h, mode, Float32(from.r) / 255.0,
            Float32(from.g) / 255.0, Float32(from.b) / 255.0, Float32(from.a) / 255.0,
            Float32(to.r) / 255.0, Float32(to.g) / 255.0, Float32(to.b) / 255.0, Float32(to.a) / 255.0)
    }

    public func fillRoundedRect(rect: Rect, radius: Float32, color: Color): Unit {
        surface.rect(rect.x, rect.y, rect.w, rect.h, radius, 0.0,
            channel(color.r), channel(color.g), channel(color.b), alphaChannel(color.a))
    }

    public func fillRoundedRectSoft(rect: Rect, radius: Float32, color: Color, feather!: Float32): Unit {
        // 柔和边缘：语义是"不透明核心 rect，边缘在 feather 宽度内淡出"（cui 的阴影两层都靠它）。
        // 之前直接忽略 feather 画实心圆角 —— 阴影变成两块叠在卡片下的灰色实体板（真机截图）。
        // 用 lgpu 的解析高斯阴影：feather ≈ 2σ 的淡出带（erf 曲线 ±σ 内完成 68% 过渡）。
        if (feather <= 0.5) {
            fillRoundedRect(rect, radius, color)
            return
        }
        let sigma = feather * 0.5
        surface.shadow(rect.x, rect.y, rect.w, rect.h, radius, sigma,
            channel(color.r), channel(color.g), channel(color.b), alphaChannel(color.a))
    }

    public func strokeRect(rect: Rect, pen: Pen): Unit {
        surface.rect(rect.x, rect.y, rect.w, rect.h, 0.0, pen.width,
            channel(pen.color.r), channel(pen.color.g), channel(pen.color.b), alphaChannel(pen.color.a))
    }

    public func strokeRoundedRect(rect: Rect, radius: Float32, pen: Pen): Unit {
        surface.rect(rect.x, rect.y, rect.w, rect.h, radius, pen.width,
            channel(pen.color.r), channel(pen.color.g), channel(pen.color.b), alphaChannel(pen.color.a))
    }

    public func strokeLine(x1: Float32, y1: Float32, x2: Float32, y2: Float32, pen: Pen): Unit {
        surface.line(x1, y1, x2, y2, pen.width,
            channel(pen.color.r), channel(pen.color.g), channel(pen.color.b), alphaChannel(pen.color.a))
    }

    public func line(x1: Float32, y1: Float32, x2: Float32, y2: Float32, color: Color): Unit {
        surface.line(x1, y1, x2, y2, 1.0,
            channel(color.r), channel(color.g), channel(color.b), alphaChannel(color.a))
    }

    public func fillCircle(cx: Float32, cy: Float32, radius: Float32, color: Color): Unit {
        surface.circle(cx, cy, radius,
            channel(color.r), channel(color.g), channel(color.b), alphaChannel(color.a))
    }

    public func strokeCircle(cx: Float32, cy: Float32, radius: Float32, pen: Pen, segments!: Int64 = 0): Unit {
        surface.strokeCircle(cx, cy, radius, pen.width,
            channel(pen.color.r), channel(pen.color.g), channel(pen.color.b), alphaChannel(pen.color.a))
    }

    public func text(text: String, x: Float32, y: Float32, color: Color, pointSize!: Float32 = 15.0): Unit {
        // 文字按物理像素光栅化：scale 交给 native 侧换算物理字号并整像素吸附
        // （几何图元继续走 setTransform 的逻辑→物理变换，见 begin）。
        let _ = surface.text(font, text, x, y, pointSize, scale,
            channel(color.r), channel(color.g), channel(color.b), alphaChannel(color.a))
    }

    public func textWidth(text: String, pointSize!: Float32 = 15.0): Float32 {
        // 缓存键带字号（q4 量化与 Rust 侧一致），命中即免 FFI。
        // G3：键改为复合 struct（不再拼接字符串）。
        let key = TextMeasureKey(text, Int64(pointSize * 4.0))
        match (measureCache.get(key)) {
            case Some(w) =>
                measureHits += 1
                w
            case None =>
                measureMisses += 1
                if (measureCache.size >= MEASURE_CAP) {
                    measureCache.clear()
                }
                let w = font.measure(text, pointSize)
                measureCache[key] = w
                w
        }
    }

    /// 行高（布局用：行距/多行文本块）。沿用 1.35×字号的经验值。
    ///
    /// 注意：这个值**不是**墨迹框。所有"y = centerY − textHeight/2"的居中调用因此会把
    /// 文字画高约 0.2×字号（真机像素实测：标题栏 15fp 文字墨迹中心比 56vp 栏中心高 3vp，
    /// 换算系数 k ≈ 0.475×字号 = 墨迹中心到盒顶的距离）。要做到墨迹精确居中应改用
    /// textInkCenterY()（见下），而不是继续调 textHeight —— 改它会同时压缩列表行距。
    public func textHeight(pointSize!: Float32 = 15.0): Float32 {
        pointSize * 1.35
    }

    /// 墨迹中心对齐用的 y（把"墨迹中心"落在 centerY 上）。
    ///
    /// 由实测反推：墨迹中心 ≈ 盒顶 + 0.475×字号（本机 HarmonyOS Sans，密度 1.9）。
    /// 与 textHeight 解耦，避免影响行距。
    public func textInkTop(text: String, centerY: Float32, pointSize!: Float32 = 15.0): Float32 {
        let _ = text
        centerY - pointSize * 0.475
    }

    public func textCenter(text: String, rect: Rect, color: Color, pointSize!: Float32 = 15.0): Unit {
        let w = textWidth(text, pointSize: pointSize)
        // 墨迹居中：行盒高度 textHeight 比墨迹框大，按它居中会把文字整体画高约 0.2em。
        this.text(text, rect.x + (rect.w - w) * 0.5, textInkTop(text, rect.centerY(), pointSize: pointSize),
            color, pointSize: pointSize)
    }
}
