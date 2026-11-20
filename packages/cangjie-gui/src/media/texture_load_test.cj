package cui.media

import cui.base.*
import cui.core.{Length, LengthUnit, Theme, UiContext}
import lbase.{Canvas, Color, Pen, Rect, Size}

/*
 * 图片加载回归（2026-11-17）：纹理尺寸必须来自解码结果。
 *
 * 历史缺陷：lgui 把图片当 PNG 交给 lgpu 的 Rust png 库解码，纹理宽高写死 0×0，
 * ImageView 按 Texture.width/height 算 fittedRect → 得到空矩形 → 整张图不画
 * （真机表现为顶栏 / 登录卡 logo 空白，且没有任何报错）。现在两条入口都经 lcodec
 * 解码，尺寸即解码尺寸；这几个用例把这个契约钉死。
 */

// 4×3 纯色 PNG（内联字节，测试不依赖外部文件/资源）。
private let TINY_PNG: Array<UInt8> = [
    137u8, 80u8, 78u8, 71u8, 13u8, 10u8, 26u8, 10u8, 0u8, 0u8, 0u8, 13u8,
    73u8, 72u8, 68u8, 82u8, 0u8, 0u8, 0u8, 4u8, 0u8, 0u8, 0u8, 3u8,
    8u8, 2u8, 0u8, 0u8, 0u8, 59u8, 150u8, 57u8, 145u8, 0u8, 0u8, 0u8,
    16u8, 73u8, 68u8, 65u8, 84u8, 120u8, 156u8, 99u8, 56u8, 97u8, 99u8, 3u8,
    71u8, 12u8, 56u8, 57u8, 0u8, 43u8, 70u8, 15u8, 1u8, 115u8, 122u8, 12u8,
    12u8, 0u8, 0u8, 0u8, 0u8, 73u8, 69u8, 78u8, 68u8, 174u8, 66u8, 96u8,
    130u8,
]

// 宿主单测的 SDL/vips 桩库（tools/verify-cui-interactions.sh）里 libvips 是"符号齐全、
// 恒失败返回"的桩，解码必然失败。此时本用例只验证"失败要明确抛出"，不验证具体尺寸；
// 有真解码后端（开发机 / 带 libvips 的 CI）时才跑尺寸断言。
private func decoderWorks(renderer: Renderer): Bool {
    texturePixelsSink = {
        _, _, _, _ => ()
    }
    try {
        let _ = renderer.loadTextureFromBytes(TINY_PNG)
        true
    } catch (_: Exception) {
        false
    } finally {
        texturePixelsSink = None
    }
}

@Test
func loadTextureFromBytesUsesDecodedSize(): Unit {
    let renderer = Renderer.headless()
    if (!decoderWorks(renderer)) {
        // 桩后端：能明确抛错（不是静默空白）即符合契约。
        var threw = false
        try {
            let _ = renderer.loadTextureFromBytes(TINY_PNG)
        } catch (_: Exception) {
            threw = true
        }
        @Expect(threw, true)
        return
    }
    // 回调里不能捕获可变局部量：用一个数组承接（w, h, 字节数）。
    let cap = Array<Int64>(3, repeat: 0)
    texturePixelsSink = {
        _, w, h, pixels =>
        cap[0] = Int64(w)
        cap[1] = Int64(h)
        cap[2] = pixels.size
    }
    try {
        let tex = renderer.loadTextureFromBytes(TINY_PNG)
        // 关键断言：纹理尺寸 == 解码尺寸（历史缺陷这里是 0×0）。
        @Expect(Int32(tex.width), 4i32)
        @Expect(Int32(tex.height), 3i32)
        @Expect(cap[0], 4i64)
        @Expect(cap[1], 3i64)
        @Expect(cap[2], Int64(4 * 3 * 4))
    } finally {
        texturePixelsSink = None
    }
}

@Test
func undecodableBytesThrowInsteadOfSilentBlank(): Unit {
    let renderer = Renderer.headless()
    var threw = false
    try {
        renderer.loadTextureFromBytes(Array<UInt8>(8, repeat: 0xffu8))
    } catch (_: Exception) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
func registeredEmbeddedBytesProduceDecodedSizeTexture(): Unit {
    // 顶栏 logo 的真实路径：registerImageBytes(内嵌字节) → texture_cache.sharedTexture
    // → lcodec 解码 → 纹理。headless 没有绘制后端，所以这里断言"纹理尺寸"而不是去 draw
    // （fittedRect 用的是同一对 width/height，尺寸正确几何就非空）。
    let renderer = Renderer.headless()
    if (!decoderWorks(renderer)) {
        return
    }
    let cap = Array<Int64>(2, repeat: 0)
    texturePixelsSink = {
        _, w, h, _ =>
        cap[0] = Int64(w)
        cap[1] = Int64(h)
    }
    try {
        registerImageBytes("test:embedded-logo", TINY_PNG)
        let tex = match (sharedTexture(renderer, "test:embedded-logo")) {
            case Some(t) => t
            case None =>
                // 解码失败走缓存 None：明确断言失败，避免"静默空白"再次溜过去。
                @Expect(false, true)
                return
        }
        // 关键断言：纹理宽高来自解码结果（历史缺陷这里是 0×0）。
        @Expect(Int32(tex.width), 4i32)
        @Expect(Int32(tex.height), 3i32)
        @Expect(cap[0], 4i64)
        @Expect(cap[1], 3i64)
    } finally {
        texturePixelsSink = None
        invalidateImage("test:embedded-logo")
    }
}

// 记录型后端：让 headless Renderer 也能"画"，用于断言绘制真的发生了、目标矩形非空。
private class RecordingCanvas <: Canvas {
    public var draws: Int64 = 0
    public var lastDst: Rect = Rect.zero()
    public var uploads: Int64 = 0
    public var lastUploadW: Int32 = 0
    public var lastUploadH: Int32 = 0

    public func beginFrame(clear: Color): Unit {}
    public func present(): Unit {}
    public func captureTo(path: String): Int32 {
        0
    }

    public func fill(rect: Rect, color: Color): Unit {}
    public func fillRoundedRect(rect: Rect, radius: Float32, color: Color): Unit {}
    public func fillRectGradient(rect: Rect, from: Color, to: Color, vertical: Bool): Unit {}
    public func drawTextureRounded(id: Int64, destination: Rect, source: ?Rect, radius: Float32,
        alpha: Float32): Unit {
        drawTexture(id, destination, source, alpha)
    }

    public func fillRoundedRectSoft(rect: Rect, radius: Float32, color: Color, feather!: Float32): Unit {}
    public func strokeRect(rect: Rect, pen: Pen): Unit {}
    public func strokeRoundedRect(rect: Rect, radius: Float32, pen: Pen): Unit {}
    public func strokeLine(x1: Float32, y1: Float32, x2: Float32, y2: Float32, pen: Pen): Unit {}
    public func line(x1: Float32, y1: Float32, x2: Float32, y2: Float32, color: Color): Unit {}
    public func fillCircle(cx: Float32, cy: Float32, radius: Float32, color: Color): Unit {}
    public func strokeCircle(cx: Float32, cy: Float32, radius: Float32, pen: Pen, segments!: Int64): Unit {}

    public func drawTexture(id: Int64, destination: Rect, source: ?Rect, alpha: Float32): Unit {
        draws++
        lastDst = destination
    }

    public func uploadTexture(id: Int64, width: Int32, height: Int32, pixels: Array<UInt8>): Unit {
        uploads++
        lastUploadW = width
        lastUploadH = height
    }

    public func releaseTexture(id: Int64): Unit {}
    public func pushClip(rect: Rect): Unit {}
    public func popClip(): Unit {}
    public func text(text: String, x: Float32, y: Float32, color: Color, pointSize!: Float32): Unit {}
    public func textWidth(text: String, pointSize!: Float32): Float32 {
        8.0
    }

    public func textHeight(pointSize!: Float32): Float32 {
        pointSize
    }

    public func textCenter(text: String, rect: Rect, color: Color, pointSize!: Float32): Unit {}
}

@Test
func brandLogoActuallyDrawsWithNonEmptyRect(): Unit {
    // 顶栏 logo 的"看得见"回归：测量 → 布局 → 绘制必须真的发出一次 drawTexture，
    // 且目标矩形非空（0 宽/0 高就是"看不到"的那种形状）。
    let renderer = Renderer.headless()
    if (!decoderWorks(renderer)) {
        return
    }
    let canvas = RecordingCanvas()
    renderer.useBackend(canvas)
    let ctx = UiContext(renderer, Theme.light())
    try {
        registerImageBytes("test:titlebar-logo", TINY_PNG)
        let logo = ImageView("test:titlebar-logo", preferredWidth: Some(Length(28.0, LengthUnit.Vp)),
            preferredHeight: Length(28.0, LengthUnit.Vp))
        let measured = logo.measure(ctx, Size(2000.0, 40.0))
        logo.layout(ctx, Rect(16.0, 6.0, measured.w, measured.h))
        logo.draw(ctx)
        logo.close()
        @Expect(measured.w > 1.0, true)
        @Expect(measured.h > 1.0, true)
        @Expect(canvas.draws, 1i64)
        @Expect(canvas.lastDst.w > 1.0, true)
        @Expect(canvas.lastDst.h > 1.0, true)
        // 上传的纹理像素必须是解码后的真实尺寸（4×3），而不是 0×0。
        @Expect(canvas.lastUploadW, 4i32)
        @Expect(canvas.lastUploadH, 3i32)
    } finally {
        invalidateImage("test:titlebar-logo")
    }
}
