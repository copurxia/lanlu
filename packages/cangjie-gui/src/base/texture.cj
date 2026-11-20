package cui.base

import lbase.{Canvas, CuiException, Color, Insets, Pen, Point, Rect, Size, clampF32}

import std.env.getVariable
import std.fs.{File, Path, exists}
import lcodec.{NativeDecodedImage, blurRgba, decodeBytesToRgba, decodeFileToRgba}

foreign func memcpy(dest: CPointer<UInt8>, src: CPointer<UInt8>, n: UIntNative): CPointer<Unit>

public enum TextureBlendMode {
    | None
    | Blend
    | Add
    | Mod
    | Mul
}

// 纹理缩放采样方式：Nearest 邻近像素（像素风锐利），Linear 线性插值（缩放平滑）。
public enum TextureScaleMode {
    | Nearest
    | Linear
}

public enum TextureFlip {
    | None
    | Horizontal
    | Vertical
    | Both
}

public struct TextureRenderOptions {
    public let source: ?Rect
    public let center: ?Point
    public let flip: TextureFlip

    public init(source!: ?Rect = None, center!: ?Point = None, flip!: TextureFlip = TextureFlip.None) {
        this.source = source
        this.center = center
        this.flip = flip
    }
}

// 每张纹理一个稳定 id（替代后端用它做键；SDL 指针不跨后端稳定）。
private var nextTextureId: Int64 = 1

// 像素上传回调：替代后端（lgpu）在纹理创建/更新时接收 RGBA 像素。
// 由上层在启用替代后端时设置；未设置时（纯 SDL 路径）零开销。
// 只传 RGBA——不存在"后端自己解 PNG"的回调（解码归 lcodec）。
public var texturePixelsSink: ?(Int64, Int32, Int32, Array<UInt8>) -> Unit = None

// R4：纹理释放回调——Texture.close 时通知后端回收（lgpu 侧销毁 wgpu 纹理并清 map）。
// 幂等：id 不存在时后端为空操作。未设置时 close 不再额外通知（测试环境）。
public var textureReleaseSink: ?(Int64) -> Unit = None

public class Texture <: Resource {
    /// 纹理的稳定 id，用于跨后端引用。
    public let id: Int64
    /// 后端（lgpu）独占纹理：ptr 为空，绘制/更新都走替代后端。
    public let backendOnly: Bool

    internal let ptr: CPointer<Unit>
    private var closed = false
    // P5：后端模式下纹理状态只在应用侧记录（lgpu 绘制时按需使用）
    private var alpha: Int64 = 255
    private var blendMode: TextureBlendMode = TextureBlendMode.Blend
    private var scaleMode: TextureScaleMode = TextureScaleMode.Linear

    public let width: Float32
    public let height: Float32

    /// 后端独占纹理：不创建 SDL 纹理，只有 id/尺寸（绘制由 Canvas 后端负责）。
    internal init(backendW: Float32, backendH: Float32, backendTag: Int32) {
        this.ptr = CPointer<Unit>()
        this.id = nextTextureId
        nextTextureId++
        // 真机诊断（LANLU_IMG_DIAG=1）：记录每次分配的 id 与尺寸，排查 id 撞号。
        if ((getVariable("LANLU_IMG_DIAG") ?? "0") == "1") {
            try {
                let home = getVariable("HOME") ?? "."
                let p = Path(home + "/tex_ids.txt")
                let prev = if (exists(p)) { String.fromUtf8(File.readFrom(p)) } else { "" }
                File.writeTo(p, (prev + "id=${this.id} ${backendW}x${backendH}\n").toArray())
            } catch (_: Exception) {}
        }
        this.backendOnly = true
        this.width = backendW
        this.height = backendH
        this.closed = false
    }

    /// 由已有 id 构造（PNG 等后端自建纹理在用）。
    internal init(existingId: Int64, backendW: Float32, backendH: Float32, backendTag: Int32) {
        this.ptr = CPointer<Unit>()
        this.id = existingId
        // 关键：复用外部 id 时必须把计数器推过它，否则后续 Texture(w,h,1) 会分到同号 id，
        // 造成「封面纹理 id 与 logo 相同」→ 上传互相覆盖 → 封面画出来是 logo 的透明像素（真机表现为空白封面）。
        if (existingId >= nextTextureId) {
            nextTextureId = existingId + 1
        }
        this.backendOnly = true
        this.width = backendW
        this.height = backendH
        this.closed = false
    }

    internal init(ptr: CPointer<Unit>) {
        this.ptr = ptr
        this.backendOnly = false
        this.id = nextTextureId
        nextTextureId++
        var w: Float32 = 0.0
        var h: Float32 = 0.0
        ensureSdl(unsafe { SDL_GetTextureSize(ptr, inout w, inout h) }, "SDL_GetTextureSize")
        this.width = w
        this.height = h
    }

    public func size(): Size {
        Size(width, height)
    }


    /// 当前绘制透明度（0..1），由 setAlpha 设置；Renderer.texture 绘制时带入后端。
    public func alphaFactor(): Float32 {
        Float32(max(Int64(0), min(Int64(255), alpha))) / 255.0
    }

    public func setAlpha(alpha: Int64): Unit {
        ensureOpen()
        // P5：lgpu 后端在 drawTexture 时带 alpha，这里不需要改纹理状态
        this.alpha = alpha
    }

    public func setBlendMode(mode: TextureBlendMode): Unit {
        ensureOpen()
        // P5：lgpu 后端固定 alpha 混合，记录模式即可
        this.blendMode = mode
    }

    public func setScaleMode(mode: TextureScaleMode): Unit {
        ensureOpen()
        // P5：lgpu 后端由采样器决定（线性），记录模式即可
        this.scaleMode = mode
    }

    public func isClosed(): Bool {
        closed
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        // R4：后端独占纹理也必须真正回收（之前 lgpu 侧纹理永不释放，显存无界增长）。
        // 通过 textureReleaseSink 通知后端（幂等：id 不存在时为空操作）；
        // 关闭后同 id 重新上传会重建纹理。
        if (backendOnly) {
            match (textureReleaseSink) {
                case Some(release) => release(id)
                case None => ()
            }
        }
    }

    /**
     * Throws `CuiException` when a closed texture is reused.
     */
    private func ensureOpen(): Unit {
        if (closed) {
            throw CuiException("Texture is already closed.")
        }
    }
}

extend Renderer {
    /*
     * 回读当前渲染目标，降采样后通过 libvips 执行真正的高斯模糊，再生成纹理。
     * 中间图保留足够分辨率，避免仅靠线性放大产生的块状、混叠和脏边。用于 Modal
     * 的模糊遮罩。
     * 注意：渲染批次未 flush 的几何不在回读里，捕捉到的可能是上一帧内容——
     * 静态遮罩场景（弹窗打开期间背景惰性）不可感知。
     * headless（ptr 空）或回读失败返回 None；调用方负责 close() 返回的纹理。
     */
    /*
     * 回读当前渲染目标，降采样后通过 libvips 执行真正的高斯模糊，再生成纹理。
     * 中间图保留足够分辨率，避免仅靠线性放大产生的块状、混叠和脏边。用于 Modal
     * 的模糊遮罩。
     * 降采样优先走 GPU：把当前目标以最近邻采样渲染进 dw×dh 小纹理再回读，回读量
     * 为全目标的 1/f²（f=4 时 ÷16）；最近邻下目标像素 (x,y) 取自源 ((x+0.5)*f) =
     * x*f+f/2（尺寸整除时），与旧 CPU 逐点抽样同一公式，视觉效果不变。无离屏目标
     * （超采样关闭直接画窗口）或 GPU 路径失败时回退全量回读 + 按 pitch 直接抽点
     * （公式相同，但去掉逐像素 SDL_ReadSurfacePixel 调用）。
     * 注意：渲染批次未 flush 的几何不在回读里，捕捉到的可能是上一帧内容——
     * 静态遮罩场景（弹窗打开期间背景惰性）不可感知。
     * headless（ptr 空）或回读失败返回 None；调用方负责 close() 返回的纹理。
     */
    public func captureBlurredTexture(factor: Int32, sigma!: Float64 = 4.0): ?Texture {
        // P5：改用 L 层离屏抓帧（不再用 SDL 渲染目标 + 逐像素读回）。
        // 步骤：抓整帧 RGBA → 按 factor 最近邻降采样 → 高斯模糊 → 上传纹理。
        let canvas = match (backendCanvas()) {
            case Some(c) => c
            case None => return None
        }
        let f = if (factor < Int32(1)) { Int32(1) } else { factor }
        let home = getVariable("HOME") ?? "."
        let path = home + "/.lgui_capture.rgba"
        let rc = canvas.captureTo(path)
        if (rc <= 0) {
            return None
        }
        let tw = rc / 1000000
        let th = rc % 1000000
        if (tw <= 0 || th <= 0) {
            return None
        }
        let src = try {
            File.readFrom(Path(path))
        } catch (_: Exception) {
            return None
        }
        if (src.size != Int64(tw) * Int64(th) * 4) {
            return None
        }
        let dw = if (tw / f < Int32(1)) { Int32(1) } else { tw / f }
        let dh = if (th / f < Int32(1)) { Int32(1) } else { th / f }
        // 最近邻降采样（与旧的 CPU 抽点公式一致：目标 (x,y) 取源 (x*f+f/2)）
        let small = Array<UInt8>(Int64(dw) * Int64(dh) * 4, repeat: 0)
        for (dy in 0..dh) {
            for (dx in 0..dw) {
                let sxRaw = dx * f + f / 2
                let sx = if (sxRaw > tw - 1) { tw - 1 } else { sxRaw }
                let syRaw = dy * f + f / 2
                let sy = if (syRaw > th - 1) { th - 1 } else { syRaw }
                let si = (Int64(sy) * Int64(tw) + Int64(sx)) * 4
                let di = (Int64(dy) * Int64(dw) + Int64(dx)) * 4
                for (k in 0..4) {
                    small[di + Int64(k)] = src[si + Int64(k)]
                }
            }
        }
        match (blurRgbaImpl(dw, dh, small, sigma)) {
            case Some(blurred) =>
                let tex = Texture(Float32(dw), Float32(dh), 1)
                canvas.uploadTexture(tex.id, dw, dh, blurred)
                Some(tex)
            case None => None
        }
    }

    /*
     * 高斯模糊：把 RGBA 像素交给 libvips 做真正的卷积（Modal 背景模糊用）。
     */

    // libvips owns a copy of the source pixels, so the Cangjie array only needs to stay pinned
    // across image construction. All failure paths release native images and memory.
        private func blurRgbaImpl(width: Int32, height: Int32, pixels: Array<UInt8>,
        sigma: Float64): ?Array<UInt8> {
        // 解码统合后由 lcodec 负责后端（运行时装载 libvips），UI 框架不再 import vips_ffi。
        blurRgba(pixels, width, height, sigma: sigma)
    }   /*
     * 用内存中的 RGBA 像素数组一步创建纹理。像素按 R,G,B,A 字节序排列，
     * 每行 pitch = width * 4 字节，与 vips 等解码器的 RGBA 输出一致。
     *
     * SDL_CreateSurfaceFrom 不拷贝像素内存，真正的读取发生在 SDL_CreateTextureFromSurface
     * （纹理同步拷贝像素），因此钉扎必须横跨这两个 C 调用：std.core 约定 acquire 与
     * release 之间只允许纯 foreign C 调用，不得构造仓颉对象（含异常与 Texture 包装类），
     * 否则移动 GC 可能在 SDL 读取前搬走像素数组。故空指针判断与抛异常都放在释放钉扎
     * 之后，Texture 包装类同样在释放后才构造。
     *
     * Throws `CuiException`：pixels.size 不等于 width*height*4，或 SDL 创建失败。
     */
    public func textureFromPixelsRgba(width: Int32, height: Int32, pixels: Array<UInt8>): Texture {
        let expected = Int64(width) * Int64(height) * 4
        if (pixels.size != expected) {
            throw CuiException(
                "textureFromPixelsRgba: pixel buffer size ${pixels.size} does not match ${width}x${height}x4 = ${expected}.")
        }
        // P5：无 SDL —— 纹理由 lgpu 持有
        // R3：backendCanvas() 与 texturePixelsSink 都指向同一张 lgpu 纹理时只上传一次。
        // 之前两条路径各传一份完整 RGBA（2× 带宽 + 2× write_texture），上传预算统计也失真。
        let tex = Texture(Float32(width), Float32(height), 1)
        match (backendCanvas()) {
            case Some(canvas) =>
                canvas.uploadTexture(tex.id, width, height, pixels)
                tex
            case None =>
                // 无后端（理论不可达：SDL 路径已移除）保持旧行为走 sink
                match (texturePixelsSink) {
                    case Some(sink) =>
                        sink(tex.id, width, height, pixels)
                        tex
                    case None =>
                        throw CuiException("textureFromPixelsRgba: 无渲染后端（SDL 路径已移除）")
                }
        }
    }

    /*
     * 创建一张 RGBA32 streaming 纹理并写入初始像素，供同尺寸帧序列（视频帧）经
     * updateStreamingTextureRgba 原地更新，避免每帧销毁重建纹理。像素布局同
     * textureFromPixelsRgba。
     *
     * Throws `CuiException`：pixels.size 不等于 width*height*4，或 SDL 创建/写入失败。
     */
    public func streamingTextureFromPixelsRgba(width: Int32, height: Int32, pixels: Array<UInt8>): Texture {
        // P5：无 SDL —— 后端纹理 + 每次 updateStreamingTextureRgba 重传像素
        let tex = Texture(Float32(width), Float32(height), 1)
        match (backendCanvas()) {
            case Some(canvas) => canvas.uploadTexture(tex.id, width, height, pixels)
            case None => throw CuiException("streamingTextureFromPixelsRgba: 无渲染后端（SDL 路径已移除）")
        }
        tex
    }

    /*
     * 把一帧同尺寸 RGBA 像素原地写入 streaming 纹理（SDL_UpdateTexture 全图更新）。
     * 钉扎规则同 textureFromPixelsRgba：acquire 与 release 之间只有纯 foreign C 调用，
     * 空指针判断与抛异常都放在释放钉扎之后。
     *
     * Throws `CuiException`：纹理已关闭、尺寸与纹理不符、像素长度不符或 SDL 更新失败。
     */
    public func updateStreamingTextureRgba(texture: Texture, width: Int32, height: Int32, pixels: Array<UInt8>): Unit {
        if (texture.isClosed()) {
            throw CuiException("Cannot update a closed texture.")
        }
        let expected = Int64(width) * Int64(height) * 4
        if (pixels.size != expected) {
            throw CuiException(
                "updateStreamingTextureRgba: pixel buffer size ${pixels.size} does not match ${width}x${height}x4 = ${expected}.")
        }
        if (Int32(texture.width) != width || Int32(texture.height) != height) {
            throw CuiException(
                "updateStreamingTextureRgba: texture is ${Int32(texture.width)}x${Int32(texture.height)}, not ${width}x${height}.")
        }
        // P5：无 SDL —— 每帧重传像素到 lgpu 纹理
        // R3：与 textureFromPixelsRgba 同理，后端路径只上传一次（视频帧逐帧 2× 上传最伤）。
        match (backendCanvas()) {
            case Some(canvas) =>
                canvas.uploadTexture(texture.id, width, height, pixels)
            case None =>
                match (texturePixelsSink) {
                    case Some(sink) => sink(texture.id, width, height, pixels)
                    case None => throw CuiException("updateStreamingTextureRgba: 无渲染后端（SDL 路径已移除）")
                }
        }
    }

    /*
     * 用 libvips 等产出的原生 RGBA 指针一步创建纹理（不经仓颉 Array<UInt8>）。
     * 像素按 R,G,B,A 字节序排列，每行 pitch = width * 4 字节。
     *
     * SDL_CreateSurfaceFrom 不拷贝像素内存，真正的读取发生在 SDL_CreateTextureFromSurface
     * （纹理同步拷贝像素）——因此本调用返回后即可安全释放原生指针（所有权仍在调用方）。
     *
     * Throws `CuiException`：指针为空或 SDL 创建失败。
     */
    public func textureFromNativeRgba(width: Int32, height: Int32, pointer: CPointer<UInt8>): Texture {
        if (pointer.isNull()) {
            throw CuiException("textureFromNativeRgba: null pixel pointer.")
        }
        // P5：无 SDL —— 原生指针先拷进数组，再走后端上传
        let size = Int64(width) * Int64(height) * 4
        let buf = Array<UInt8>(size, repeat: 0)
        let handle = unsafe { acquireArrayRawData(buf) }
        unsafe {
            memcpy(handle.pointer, pointer, UIntNative(size))
            releaseArrayRawData(handle)
        }
        textureFromPixelsRgba(width, height, buf)
    }

    /*
     * 把原生 RGBA 像素原地写入 streaming 纹理（SDL_UpdateTexture 全图更新）。
     * 返回后即可安全释放原生指针（SDL 同步拷贝）。
     *
     * Throws `CuiException`：纹理已关闭、尺寸与纹理不符、指针为空或 SDL 更新失败。
     */
    public func updateStreamingTextureNativeRgba(texture: Texture, width: Int32, height: Int32,
        pointer: CPointer<UInt8>): Unit {
        if (texture.isClosed()) {
            throw CuiException("Cannot update a closed texture.")
        }
        if (pointer.isNull()) {
            throw CuiException("updateStreamingTextureNativeRgba: null pixel pointer.")
        }
        // P5：无 SDL —— 原生指针先拷进数组，再走后端重传
        let size = Int64(width) * Int64(height) * 4
        let buf = Array<UInt8>(size, repeat: 0)
        let handle = unsafe { acquireArrayRawData(buf) }
        unsafe {
            memcpy(handle.pointer, pointer, UIntNative(size))
            releaseArrayRawData(handle)
        }
        updateStreamingTextureRgba(texture, width, height, buf)
    }

    /**
     * 从文件加载图片为纹理（PNG/JPEG/WebP/GIF/BMP/AVIF… 凡 lcodec 支持的格式）。
     *
     * **解码只经 lcodec**（设备：系统 ImageSource；桌面：系统 libvips）。lgui 自身不含
     * 任何图片解码器——历史上这里曾把文件当 PNG 交给 lgpu 的 Rust `png` 库解，形成
     * 第二条解码路径：只认 PNG、尺寸回传丢失（纹理恒为 0×0，`ImageView` 按
     * `Texture.width/height` 算 `fittedRect` 后整张图消失），且失败完全无声。
     *
     * Throws `CuiException` when decoding fails or no backend canvas is attached.
     */
    public func loadTexture(path: String): Texture {
        uploadDecodedImage(decodeFileToRgba(path))
    }

    /**
     * 从内存字节创建纹理（内嵌资源：顶栏 / 登录卡的品牌 logo）。
     * 与 `loadTexture` 共用同一条 lcodec 解码路径，不读盘。
     */
    public func loadTextureFromBytes(bytes: Array<UInt8>): Texture {
        uploadDecodedImage(decodeBytesToRgba(bytes))
    }

    // 解码结果 → 纹理。宽高取自解码结果（真实像素），像素上传后立刻释放原生缓冲；
    // 异常路径同样释放，保证所有权唯一、不泄漏。
    private func uploadDecodedImage(image: NativeDecodedImage): Texture {
        if (image.pointer().isNull()) {
            image.close()
            throw CuiException("loadTexture: 解码结果为空（像素指针为空）")
        }
        try {
            textureFromNativeRgba(image.width, image.height, image.pointer())
        } finally {
            image.close()
        }
    }

    /**
     * Throws `CuiException` when the texture is closed or SDL cannot render it.
     */
    public func texture(texture: Texture, destination: Rect, source!: ?Rect = None): Unit {
        if (texture.isClosed()) {
            throw CuiException("Cannot render a closed texture.")
        }
        match (backendCanvas()) {
            case Some(b) =>
                // setAlpha 记录的透明度此前从未传给后端（淡出/纵深效果失效）。
                b.drawTexture(texture.id, destination, source, texture.alphaFactor())
            case None =>
                // 真机诊断：纹理绘制走到的 Renderer 没有后端画布（封面画不出来的直接原因）。
                try {
                    let home = getVariable("HOME") ?? "."
                    let p = Path(home + "/img_diag.txt")
                    let prev = if (exists(p)) { String.fromUtf8(File.readFrom(p)) } else { "" }
                    if (!prev.contains("noBackend texId=${texture.id}")) {
                        File.writeTo(p, (prev + "[lgui] noBackend texId=${texture.id} dst=${destination.w}x${destination.h}\n").toArray())
                    }
                } catch (_: Exception) {}
                throw CuiException("texture(): 无渲染后端（SDL 路径已移除）")
        }
    }

}

// 返回 (可用的 RGBA32 表面, 需要调用方销毁的转换副本；无转换时为空指针)。
// 已是 RGBA32 时原样返回；转换失败返回两个空指针。

/*
 * 把 surface 的像素按 RGBA32 字节序完整拷出（行距取 surface 的 pitch）。非 RGBA32
 * 的表面先经 SDL_ConvertSurface 转换；失败返回 None。internal：模糊回读与测试共用。
 */

/*
 * 按 pitch 从 RGBA32 像素内存抽点：目标像素 (x,y) 取源 (x*f+f/2, y*f+f/2)（块中心，
 * 边缘夹到最后一像素）——与旧实现的 SDL_ReadSurfacePixel 循环同一公式、同一结果。
 * internal：抽点公式由测试逐字节钉住。
 */
internal func pointSamplePixels(base: CPointer<UInt8>, pitch: Int32, tw: Int32, th: Int32, dw: Int32, dh: Int32,
    f: Int32): Array<UInt8> {
    let out = Array<UInt8>(Int64(dw) * Int64(dh) * 4, repeat: 0u8)
    unsafe {
        let handle = acquireArrayRawData(out)
        try {
            var y: Int32 = 0
            while (y < dh) {
                let sy = min(y * f + f / 2, th - 1)
                let srcRow = base + Int64(sy) * Int64(pitch)
                var x: Int32 = 0
                while (x < dw) {
                    let sx = min(x * f + f / 2, tw - 1)
                    let srcPx = srcRow + Int64(sx) * 4
                    let dstPx = handle.pointer + (Int64(y) * Int64(dw) + Int64(x)) * 4
                    var c: Int64 = 0
                    while (c < 4) {
                        (dstPx + c).write((srcPx + c).read())
                        c++
                    }
                    x++
                }
                y++
            }
        } finally {
            releaseArrayRawData(handle)
        }
    }
    out
}

private func blendModeCode(mode: TextureBlendMode): UInt32 {
    match (mode) {
        case TextureBlendMode.None => UInt32(0)
        case TextureBlendMode.Blend => UInt32(1)
        case TextureBlendMode.Add => UInt32(2)
        case TextureBlendMode.Mod => UInt32(4)
        case TextureBlendMode.Mul => UInt32(8)
    }
}

private func scaleModeCode(mode: TextureScaleMode): Int32 {
    match (mode) {
        case TextureScaleMode.Nearest => 0
        case TextureScaleMode.Linear => 1
    }
}

private func flipCode(flip: TextureFlip): Int32 {
    match (flip) {
        case TextureFlip.None => 0
        case TextureFlip.Horizontal => 1
        case TextureFlip.Vertical => 2
        case TextureFlip.Both => 3
    }
}

private func toChannel(value: Int64): UInt8 {
    if (value < 0) {
        UInt8(0)
    } else if (value > 255) {
        UInt8(255)
    } else {
        UInt8(value)
    }
}
