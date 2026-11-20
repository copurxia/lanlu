package cui.base

import lbase.{Canvas, CuiException, Color, Insets, Pen, Point, Rect, Size, clampF32}

import std.collection.{ArrayList, HashMap}
import std.env.getVariable
import std.fs.{File, Path}
import cui.textkit.{NativeTextColor, NativeTextException, NativeTextMetrics, NativeTextRenderer}
import sdl_stub_ffi.SDL_STUB_LINK_MARKER

// 引用桩依赖包的标记常量：保持 sdl_stub_ffi 出现在本包的链接闭包里，让
// 「cjpm test」把 -lSDL3/-lSDL3_ttf 透传给测试可执行文件（本机桩库由
// tools/verify-cui-interactions.sh 提供；SDL 后端路径运行期不会被触达）。
private let sdlStubLinkMarker: UInt8 = SDL_STUB_LINK_MARKER

/**
 * Standard text sizes shared by the renderer, widgets, and applications.
 */
public struct FontSizes {
    public static let CAPTION: Float32 = 13.0
    public static let BODY: Float32 = 15.0
    public static let CONTROL: Float32 = 15.0
    public static let TITLE: Float32 = 20.0
    public static let DISPLAY: Float32 = 32.0
}

/*
 * Default supersampling factor. The whole frame is drawn into an offscreen target this many times
 * larger than the window in each axis, then linearly downscaled on present. That single step
 * anti-aliases every primitive — rounded corners, diagonal strokes, circles — on the GPU, with no
 * per-widget cost. 2x (4 samples per pixel) is the sweet spot for desktop UI, but it also makes every
 * frame pay for 4x the pixels; an application (or a benchmark isolating that cost) can lower it.
 */
private let DEFAULT_SUPERSAMPLE: Int32 = 2

/*
 * Sentinel for `Renderer`/`WindowSpec.supersample`: resolve the factor from the render driver at
 * startup — 1x (off) when SDL picked the "software" renderer, where every supersampled pixel is
 * CPU fill work and dominates the frame; the hardware default (2x) otherwise. Any explicit value
 * >= 1 overrides the adaptation.
 */
public let AUTO_SUPERSAMPLE: Int32 = 0

/*
 * Resolves the effective supersample factor (#16). AUTO_SUPERSAMPLE adapts to the render
 * driver: 1x (off) when SDL picked "software", where every supersampled pixel is CPU fill
 * work and dominates the frame; the hardware default (2x) otherwise. An explicit value
 * (>= 1) always wins over the adaptation; anything lower clamps to 1x.
 */
internal func resolveSupersample(requested: Int32, driver: String): Int32 {
    if (requested == AUTO_SUPERSAMPLE) {
        if (driver == "software") {
            Int32(1)
        } else {
            DEFAULT_SUPERSAMPLE
        }
    } else if (requested < Int32(1)) {
        Int32(1)
    } else {
        requested
    }
}

// The driver name for a raw renderer pointer ("headless" without a device) — the init-time
// twin of `Renderer.driverName`, callable before the instance's members all exist.
private func rendererDriverName(ptr: CPointer<Unit>): String {
    // P5：渲染一律由 L 层 lgpu 后端承担，没有 SDL 驱动名可查
    "lgpu"
}

// Per-point-size capacity for the text-metrics cache before a generation is retired. A handful of
// sizes each hold up to this many distinct strings — ample for a dense UI while staying bounded
// against pathological churn (for example a log of unique lines every frame).
private let TEXT_METRICS_CAP_PER_SIZE: Int64 = 1024

/*
 * A per-point-size text-measurement cache. The UI tree is rebuilt every frame, so the same string
 * is measured over and over; caching (point size, text) -> metrics across frames turns those
 * repeats into a hash lookup instead of an SDL_ttf shaping call. Keyed size-first so the string is
 * used directly as the inner key with no per-lookup allocation — an earlier `"${size}#${text}"` key
 * was measured too costly (its float-to-string build dominated) and reverted. Bounded by a
 * two-generation eviction per size: when the active generation fills it is retired and a cleared one
 * takes over; a hit in the retired generation is promoted back, so hot strings survive a rotation.
 */
private class MetricsGeneration {
    private let capacity: Int64
    private var active = HashMap<String, NativeTextMetrics>()
    private var retired = HashMap<String, NativeTextMetrics>()

    init(capacity: Int64) {
        this.capacity = if (capacity < 1) {
            1
        } else {
            capacity
        }
    }

    func get(text: String): ?NativeTextMetrics {
        match (active.get(text)) {
            case Some(value) => return Some(value)
            case None => ()
        }
        match (retired.get(text)) {
            case Some(value) =>
                put(text, value)
                Some(value)
            case None => None
        }
    }

    func put(text: String, value: NativeTextMetrics): Unit {
        if (active.size >= capacity) {
            let recycled = retired
            recycled.clear()
            retired = active
            active = recycled
        }
        active[text] = value
    }
}

private class TextMetricsCache {
    private let capacityPerSize: Int64
    private var bySize = HashMap<Int64, MetricsGeneration>()

    init(capacityPerSize: Int64) {
        this.capacityPerSize = capacityPerSize
    }

    func get(sizeKey: Int64, text: String): ?NativeTextMetrics {
        match (bySize.get(sizeKey)) {
            case Some(generation) => generation.get(text)
            case None => None
        }
    }

    func put(sizeKey: Int64, text: String, value: NativeTextMetrics): Unit {
        let generation = match (bySize.get(sizeKey)) {
            case Some(existing) => existing
            case None =>
                let created = MetricsGeneration(capacityPerSize)
                bySize[sizeKey] = created
                created
        }
        generation.put(text, value)
    }
}

public class Renderer <: Canvas {
    // 可选的后端（P4 迁移用）：设置后所有图元改由它绘制（当前用于 lgpu/wgpu 验证）。
    // 纹理创建/离屏目标仍走 SDL，切到 lgpu 的页面暂时不要用纹理。
    private var backend: ?Canvas = None

    /// 切换底层绘制后端；传 None 恢复 SDL。
    public func useBackend(canvas: ?Canvas): Unit {
        backend = canvas
    }

    /// 当前后端（供本包其它文件的扩展方法使用；private 字段跨文件不可见）。
    public func backendCanvas(): ?Canvas {
        backend
    }

    /// 当前是否由替代后端绘制（调试/自检用）。
    public func backendActive(): Bool {
        match (backend) {
            case Some(_) => true
            case None => false
        }
    }

    internal let ptr: CPointer<Unit>
    private let contentScale: Float32
    private var ssTarget: CPointer<Unit> = CPointer<Unit>()
    private var ssWidth: Int32 = 0
    private var ssHeight: Int32 = 0
    // Supersample factor per axis (1 = off). Fixed for the renderer's life.
    private let ssFactor: Int32
    private var ssEnabled: Bool
    // The live drawing scale (render coordinates -> target pixels), mirrored from every
    // SDL_SetRenderScale call. Geometry draws through the GPU scale; TEXT rasterizes at
    // this scale and draws 1:1 on the pixel grid instead (see `text`), because stretching
    // small glyph bitmaps through the render scale is what blurs it.
    private var scaleX: Float32 = 1.0
    private var scaleY: Float32 = 1.0
    private let geometry = GeometryBatch()
    private let textBackend: ?NativeTextRenderer
    private let clipStack = ArrayList<Rect>()
    // Cache of the scale last handed to SDL_SetRenderScale. Distinct from `scaleX`/`scaleY`,
    // which mirror the LOGICAL scale callers draw at: the text pass temporarily applies 1:1,
    // so SDL's applied value can differ inside `text`. Every scale write goes through
    // `applyRenderScale`, which skips the SDL call when the request repeats — each
    // SDL_SetRenderScale flushes SDL's queued draw commands, so a redundant one is never
    // free. The valid bits drop on every render-target switch, since SDL does not document
    // scale/clip as surviving one; the next setter then re-issues the real call.
    private var appliedScaleX: Float32 = 1.0
    private var appliedScaleY: Float32 = 1.0
    private var appliedScaleValid = false
    // The clip rect last handed to SDL_SetRenderClipRect, in whatever coordinate space that
    // call used (logical for geometry, target pixels inside the text pass); None = clip
    // disabled. Repeats skip the SDL call — for example the text pass re-clears an
    // already-clear clip after every unclipped draw.
    private var appliedClip: ?Rect = None
    private var appliedClipValid = false
    // Counts text measurements since the last reset — a per-frame cost probe. Text measurement is a
    // per-frame choke point (each measure shapes the string and, with a real backend, calls
    // SDL_ttf), so benchmarks reset this at a frame boundary to see how many a tree performs.
    // `measureCount` is total requests; `computeCount` is cache misses (the actual SDL_ttf calls).
    private var measureCount: UInt64 = 0
    private var computeCount: UInt64 = 0
    // Counts text draws (each re-shapes the string via TTF_SetTextString and rasterizes it) since the
    // last reset — the other per-frame text choke point, separate from measurement.
    private var drawTextCount: UInt64 = 0
    private let metricsCache = TextMetricsCache(TEXT_METRICS_CAP_PER_SIZE)

    internal init(ptr: CPointer<Unit>, contentScale!: Float32 = 1.0, supersample!: Int32 = DEFAULT_SUPERSAMPLE,
        fontPath!: ?String = None) {
        this.ptr = ptr
        this.contentScale = contentScale
        this.ssFactor = resolveSupersample(supersample, rendererDriverName(ptr))
        this.ssEnabled = ptr.isNotNull() && this.ssFactor > Int32(1)
        this.textBackend = createTextBackend(ptr, fontPath)
    }

    /**
     * A renderer backed by no SDL device. Drawing becomes a no-op, which makes it useful
     * for headless widget tests that exercise layout and event handling without a window.
     */
    public static func headless(): Renderer {
        Renderer(CPointer<Unit>())
    }

    /**
     * The SDL render backend actually chosen (for example "direct3d11", "direct3d12", "opengl",
     * "vulkan", or "software"). A hardware/software tell: "software" means every pixel is drawn on
     * the CPU, which dominates a supersampled frame. "headless" when there is no device.
     */
    public func driverName(): String {
        rendererDriverName(ptr)
    }

    /** The active supersample factor per axis (1 = off). */
    public func supersampleFactor(): Int32 {
        ssFactor
    }

    /** Size of the current render target in pixels (supersampled); (0,0) before the first frame. */
    public func targetPixelSize(): Size {
        Size(Float32(ssWidth), Float32(ssHeight))
    }

    /**
     * Begins a frame. When supersampling is available the scene is redirected into a
     * high-resolution offscreen target sized to `logicalWidth`/`logicalHeight`; otherwise
     * it draws straight to the window. Either way the target is cleared to `clearColor`.
     */
    public func beginScene(logicalWidth: Float32, logicalHeight: Float32, clearColor: Color): Unit {
        // Balanced pushClip/popClip pairs leave the stack empty between frames; clearing
        // here keeps one leaked push from clipping every later frame.
        clipStack.clear()
        // P5：渲染全部交给 L 层后端（lgpu）。SDL 的 SSAA/超采样路径已移除：
        // 它依赖 SDL 渲染目标与渲染缩放，而 lgpu 自己管理缩放与呈现。
        match (backend) {
            case Some(b) => b.beginFrame(clearColor)
            case None => throw CuiException("beginScene: 需要渲染后端（SDL 路径已移除）")
        }
    }

    /**
     * Ends a frame. With supersampling active this resolves the offscreen target back onto
     * the window with linear filtering (the actual anti-aliasing step); otherwise a no-op.
     */
    public func endScene(): Unit {
        // P5：后端自己处理呈现（present 里会 endFrame），这里无需任何 SDL 操作。
        ()
    }


    // Routes every SDL_SetRenderScale through the applied-state cache, skipping the SDL call
    // (and its draw-queue flush) when the request repeats the value SDL already has. Returns
    // SDL's result so callers keep their existing error handling; the cache only updates on
    // success. Never call SDL_SetRenderScale directly outside this helper.

    private func applyRenderScale(x: Float32, y: Float32): Bool {
        // P5：缩放由后端 canvas 管理
        true
    }

    // SDL does not document the render scale or clip as surviving a target switch, so every
    // SDL_SetRenderTarget invalidates both caches; the next setter re-issues the real call.
    private func invalidateAppliedRenderState(): Unit {
        appliedScaleValid = false
        appliedClipValid = false
    }

    /**
     * Releases resources the renderer owns beyond the SDL renderer itself — the
     * supersampling target and the geometry buffers. The owning window calls this on
     * close, just before destroying the SDL renderer; safe to call more than once.
     */

    internal func releaseResources() {
        // P5：SDL 资源已不存在，只需要关闭后端资源
        match (textBackend) {
            case Some(value) => value.close()
            case None => ()
        }
    }


    /**
     * Throws `CuiException` when SDL rejects the renderer draw color update.
     */

    public func setColor(color: Color): Unit {
        // P5：颜色由后端 canvas 的绘制调用直接携带，无需在这里保存 SDL 绘制色
        ()
    }

    /**
     * Throws `CuiException` when SDL cannot clear the current render target.
     */
    public func clear(color: Color): Unit {
        // Headless renderers no-op like every other draw entry point, so canvas or shell
        // code that clears explicitly stays testable off-screen.
        if (ptr.isNull()) {
            return
        }
        setColor(color)
        if (!unsafe { SDL_RenderClear(ptr) }) {
            throw CuiException("SDL_RenderClear failed: ${lastSdlError()}")
        }
    }

    public func beginFrame(clear: Color): Unit {
        match (backend) {
            case Some(b) => b.beginFrame(clear)
            case None => clearTarget(clear)
        }
    }

    public func present(): Unit {
        match (backend) {
            case Some(b) => b.present()
            case None => ()   // headless：没有可呈现的目标
        }
    }

    /**
     * Throws `CuiException` when the scale is invalid or SDL rejects the renderer scale.
     * Headless: the logical scale is still recorded, so text metrics stay consistent.
     */
    public func setScale(scale: Float32): Unit {
        if (scale <= 0.0) {
            throw CuiException("Renderer scale must be greater than 0.")
        }
        if (!ptr.isNull()) {
            ensureSdl(applyRenderScale(scale, scale), "SDL_SetRenderScale")
        }
        scaleX = scale
        scaleY = scale
    }


    public func setVSync(vsync: Int32): Unit {
        // P5：lgpu 后端固定 vsync，由 wgpu present 决定
        ()
    }


    public func vsync(): Int32 {
        1
    }


    public func setViewport(rect: Rect): Unit {
        // P5：lgpu 后端不需要 SDL 视口
        ()
    }


    public func resetViewport(): Unit {
        // P5：lgpu 后端不需要 SDL 视口
        ()
    }


    public func viewport(): Rect {
        Rect(0.0, 0.0, 0.0, 0.0)   // P5：视口由后端 canvas 管理
    }

    /**
     * Narrows the active clip to the intersection of `rect` and the current clip, so nested
     * scrollports and fields clip within their ancestors. Pair every call with `popClip`.
     */
    public func pushClip(rect: Rect): Unit {
        let effective = match (currentClip()) {
            case Some(top) => top.intersection(rect)
            case None => rect
        }
        clipStack.add(effective)
        match (backend) {
            case Some(b) => b.pushClip(effective)
            case None => applyClip()
        }
    }

    /** Restores the clip that was active before the matching `pushClip`. */
    public func popClip(): Unit {
        if (!clipStack.isEmpty()) {
            clipStack.remove(at: clipStack.size - 1)
            match (backend) {
                case Some(b) => b.popClip()
                case None => ()
            }
        }
        applyClip()
    }

    /** The clip in effect right now, or `None` when drawing is unclipped. */
    public func currentClip(): ?Rect {
        if (clipStack.isEmpty()) {
            None
        } else {
            Some(clipStack[clipStack.size - 1])
        }
    }

    /** Removes every pending clip — the equivalent of popping back to the window. */
    public func clearClipStack(): Unit {
        clipStack.clear()
        applyClip()
    }

    private func applyClip(): Unit {
        if (ptr.isNull()) {
            return
        }
        match (currentClip()) {
            case Some(rect) => setClip(rect)
            case None => resetClip()
        }
    }


    private func setClip(rect: Rect): Unit {
        // P5：裁剪由后端 canvas 的 pushClip/popClip 负责
        ()
    }


    private func resetClip(): Unit {
        // P5：裁剪由后端 canvas 负责
        ()
    }

    // Headless, the logical clip stack still answers: the top entry (or a zero rect).

    public func clipRect(): Rect {
        match (currentClip()) {
            case Some(rect) => rect
            case None => Rect(0.0, 0.0, 0.0, 0.0)
        }
    }


    public func clipEnabled(): Bool {
        currentClip().isSome()
    }


    public func setColorScale(scale: Float32): Unit {
        // P5：无 SDL 颜色缩放
        ()
    }


    public func colorScale(): Float32 {
        1.0
    }


    public func setColorFloat(r: Float32, g: Float32, b: Float32, a: Float32): Unit {
        // P5：同上，SDL 绘制色已移除
        ()
    }


    public func point(x: Float32, y: Float32, color: Color): Unit {
        // P5：点绘制走后端 canvas
        match (backendCanvas()) {
            case Some(b) => b.fill(Rect(x, y, 1.0, 1.0), color)
            case None => ()
        }
    }

    public func line(x1: Float32, y1: Float32, x2: Float32, y2: Float32, color: Color): Unit {
        match (backend) {
            case Some(b) => b.line(x1, y1, x2, y2, color)
            case None => throw CuiException("line(): 无渲染后端（SDL 路径已移除）")
        }
    }

    public func rect(rect: Rect, color: Color): Unit {
        match (backend) {
            case Some(b) => b.strokeRect(rect, Pen(color: color, width: 1.0))
            case None => throw CuiException("rect(): 无渲染后端（SDL 路径已移除）")
        }
    }

    /// 纹理上传（实现 Canvas）：SDL 前端不持有纹素，转发给替代后端。
    public func uploadTexture(id: Int64, width: Int32, height: Int32, pixels: Array<UInt8>): Unit {
        match (backend) {
            case Some(b) => b.uploadTexture(id, width, height, pixels)
            case None => ()
        }
    }

    // PNG 字节上传已删除：解码归 lcodec，后端只收 RGBA 像素（uploadTexture）。

    /// 后端纹理释放（实现 Canvas；R4：Texture.close 调用）。
    public func releaseTexture(id: Int64): Unit {
        match (backend) {
            case Some(b) => b.releaseTexture(id)
            case None => ()
        }
    }

    /// 后端纹理绘制（实现 Canvas）。
    public func drawTexture(id: Int64, destination: Rect, source: ?Rect, alpha: Float32): Unit {
        match (backend) {
            case Some(b) => b.drawTexture(id, destination, source, alpha)
            case None => ()
        }
    }

    public func fill(rect: Rect, color: Color): Unit {
        match (backend) {
            case Some(b) => b.fill(rect, color)
            case None => throw CuiException("fill(): 无渲染后端（SDL 路径已移除）")
        }
    }

    /** 单次 GPU 绘制的水平线性渐变。 */
    /// Canvas 接口：线性渐变（后端绘制）。
    public func fillRectGradient(rect: Rect, from: Color, to: Color, vertical: Bool): Unit {
        match (backend) {
            case Some(b) => b.fillRectGradient(rect, from, to, vertical)
            case None => throw CuiException("fillRectGradient(): 无渲染后端（SDL 路径已移除）")
        }
    }

    public func fillHorizontalGradient(rect: Rect, left: Color, right: Color): Unit {
        match (backend) {
            case Some(b) => b.fillRectGradient(rect, left, right, false)
            case None => throw CuiException("fillHorizontalGradient(): 无渲染后端（SDL 路径已移除）")
        }
    }

    /** 单次 GPU 绘制的纵向线性渐变。 */
    public func fillVerticalGradient(rect: Rect, top: Color, bottom: Color): Unit {
        match (backend) {
            case Some(b) => b.fillRectGradient(rect, top, bottom, true)
            case None => throw CuiException("fillVerticalGradient(): 无渲染后端（SDL 路径已移除）")
        }
    }

    /**
     * A thick, round-capped line drawn as one anti-aliased stadium mesh, so strokes stay
     * smooth at any angle and consecutive polyline segments join without notches.
     */
    public func strokeLine(x1: Float32, y1: Float32, x2: Float32, y2: Float32, pen: Pen): Unit {
        match (backend) { case Some(b) => b.strokeLine(x1, y1, x2, y2, pen); return; case None => () }
        geometry.strokeSegment(ptr, Point(x1, y1), Point(x2, y2), pen)
    }

    /**
     * A rectangle outline with lightly rounded joins, stroked as one anti-aliased ring.
     */
    public func strokeRect(rect: Rect, pen: Pen): Unit {
        match (backend) { case Some(b) => b.strokeRect(rect, pen); return; case None => () }
        strokeRoundedRect(rect, pen.width * 0.6, pen)
    }

    /**
     * A rounded-rectangle outline stroked as one anti-aliased ring centred on the path.
     */
    public func strokeRoundedRect(rect: Rect, radius: Float32, pen: Pen): Unit {
        match (backend) { case Some(b) => b.strokeRoundedRect(rect, radius, pen); return; case None => () }
        geometry.strokeRoundedRect(ptr, rect, roundedRadius(rect, radius), pen)
    }

    public func fillRoundedRect(rect: Rect, radius: Float32, color: Color): Unit {
        match (backend) { case Some(b) => b.fillRoundedRect(rect, radius, color); return; case None => () }
        let r = roundedRadius(rect, radius)
        if (r <= 0.5) {
            fill(rect, color)
            return
        }
        geometry.fillRoundedRect(ptr, rect, r, color)
    }

    /**
     * A rounded rectangle whose edge fades out across `feather` pixels — a single-pass
     * gradient halo, which is how soft drop shadows and focus glows are drawn banding-free.
     */
    public func fillRoundedRectSoft(rect: Rect, radius: Float32, color: Color, feather!: Float32): Unit {
        match (backend) {
            case Some(b) => b.fillRoundedRectSoft(rect, radius, color, feather: feather)
            case None => throw CuiException("fillRoundedRectSoft(): 无渲染后端（SDL 路径已移除）")
        }
    }

    public func circle(cx: Float32, cy: Float32, radius: Float32, color: Color, segments!: Int64 = 0): Unit {
        match (backend) {
            case Some(b) => b.strokeCircle(cx, cy, radius, Pen(width: 1.0, color: color), segments: segments)
            case None => throw CuiException("circle(): 无渲染后端（SDL 路径已移除）")
        }
    }

    /**
     * A circle outline drawn with the given pen. `segments` is a minimum tessellation
     * hint; arcs are always sampled finely enough to stay smooth for their radius.
     */
    public func strokeCircle(cx: Float32, cy: Float32, radius: Float32, pen: Pen, segments!: Int64 = 0): Unit {
        match (backend) {
            case Some(b) => b.strokeCircle(cx, cy, radius, pen, segments: segments)
            case None => throw CuiException("strokeCircle(): 无渲染后端（SDL 路径已移除）")
        }
    }

    public func fillCircle(cx: Float32, cy: Float32, radius: Float32, color: Color): Unit {
        match (backend) { case Some(b) => b.fillCircle(cx, cy, radius, color); return; case None => () }
        geometry.fillCircle(ptr, Point(cx, cy), radius, color)
    }

    /**
     * 纹理实心圆：用纹理填充的圆形扇形网格。中心映射到纹理中 (cx,cy) 对应坐标，
     * 圆周映射到纹理对应坐标，GPU 自动插值。用于剪切蒙版、纹理揭示等过渡效果。
     * 纹理需预先设置为 SDL_BLENDMODE_BLEND 以保证与已有画面正确合成。
     */
    public func fillTexturedCircle(cx: Float32, cy: Float32, radius: Float32, texture: Texture): Unit {
        match (backend) {
            case Some(b) =>
                let d = Rect(cx - radius, cy - radius, radius * 2.0, radius * 2.0)
                b.drawTextureRounded(texture.id, d, Option<Rect>.None, radius, 1.0)
            case None => throw CuiException("fillTexturedCircle(): 无渲染后端（SDL 路径已移除）")
        }
    }

    /** Draws the texture at its original screen mapping, clipped to a circle. */
    public func textureClippedCircle(cx: Float32, cy: Float32, radius: Float32, texture: Texture): Unit {
        // 用圆角=半径的方框做圆形裁剪（SDF 覆盖）。source 必须等于目标框本身（纹理按屏幕
        // 坐标 1:1 映射）；之前传 None 会把整张纹理压进圆的外接框——揭示出的新主题画面
        // 被缩放变形。快照纹理按视口逻辑尺寸注册 UV，越界部分落在屏幕外。
        match (backend) {
            case Some(b) =>
                let d = Rect(cx - radius, cy - radius, radius * 2.0, radius * 2.0)
                b.drawTextureRounded(texture.id, d, Some(d), radius, texture.alphaFactor())
            case None => throw CuiException("textureClippedCircle(): 无渲染后端（SDL 路径已移除）")
        }
    }

    /** Draws a texture with its existing mapping clipped to a rounded on-screen frame. */
    public func textureRoundedRect(texture: Texture, destination: Rect, frame: Rect, radius: Float32): Unit {
        match (backend) {
            case Some(b) =>
                // UV 按整张纹理映射（frame 是屏幕坐标，当纹理子区会算出 uv>1 → 采到透明像素）。
                // 几何用 frame（Cover 适配的 destination 可能横向溢出 frame，SDF 圆角与
                // 可见区域都应以 frame 为准 —— 真机曾表现为相邻封面连成一条色带）。
                b.drawTextureRounded(texture.id, frame, Option<Rect>.None, roundedRadius(frame, radius), 1.0)
            case None => throw CuiException("textureRoundedRect(): 无渲染后端（SDL 路径已移除）")
        }
    }

    /// Canvas 接口：圆角纹理绘制。
    public func drawTextureRounded(id: Int64, destination: Rect, source: ?Rect, radius: Float32,
        alpha: Float32): Unit {
        match (backend) {
            case Some(b) => b.drawTextureRounded(id, destination, source, radius, alpha)
            case None => throw CuiException("drawTextureRounded(): 无渲染后端（SDL 路径已移除）")
        }
    }

    /**
     * Copies the live supersampled frame into a logical-size GPU texture without a CPU
     * readback. This must run on the render thread; callers own and close the texture.
     * Direct-render backends return None so callers can choose a slower fallback.
     */
    public func captureTextureGpu(width: Float32, height: Float32): ?Texture {
        let canvas = match (backendCanvas()) {
            case Some(c) => c
            case None => return None
        }
        // 首选后端 GPU 快照：纹理直接在显存里生成并注册到 id，无读回/写文件/再上传。
        let tex = Texture(width, height, 1)
        match (canvas.snapshotTexture(tex.id, width, height)) {
            case Some(_) => return Some(tex)
            case None => tex.close()
        }
        // 退路：L 层离屏抓帧（读回 CPU + 再上传，慢，仅后端不支持快照时使用）。
        match (captureFramePixels()) {
            case Some(frame) =>
                let (fw, fh, pixels) = frame
                let fallback = Texture(Float32(fw), Float32(fh), 1)
                canvas.uploadTexture(fallback.id, fw, fh, pixels)
                Some(fallback)
            case None => None
        }
    }

    /// 层断点：此后录制的图元整体画在此前所有图元（含纹理）之上。
    public func layerMark(): Unit {
        match (backend) { case Some(b) => b.layerMark(); case None => () }
    }

    /// 丢弃本帧已录制的全部图元（全屏不透明遮罩已覆盖下层时调用）。
    public func discardRecorded(): Unit {
        match (backend) { case Some(b) => b.discardRecorded(); case None => () }
    }

    /// 单实例辉光环；后端不支持时返回 false。
    public func glowRing(cx: Float32, cy: Float32, radius: Float32, stroke: Float32, outer: Float32,
            inner: Float32, color: Color, glow: Float32): Bool {
        match (backend) {
            case Some(b) => b.glowRing(cx, cy, radius, stroke, outer, inner, color, glow)
            case None => false
        }
    }

    /// Canvas 接口实现：把当前帧抓到文件（委托给后端画布）。
    public func captureTo(path: String): Int32 {
        match (backendCanvas()) {
            case Some(c) => c.captureTo(path)
            case None => -1
        }
    }

    /// 抓取当前帧的原始 RGBA（借助 L 层离屏抓帧）。返回 (w, h, pixels)。
    public func captureFramePixels(): ?(Int32, Int32, Array<UInt8>) {
        let canvas = match (backendCanvas()) {
            case Some(c) => c
            case None => return None
        }
        let home = getVariable("HOME") ?? "."
        let path = home + "/.lgui_capture.rgba"
        let rc = canvas.captureTo(path)
        if (rc <= 0) {
            return None
        }
        let w = rc / 1000000
        let h = rc % 1000000
        if (w <= 0 || h <= 0) {
            return None
        }
        let bytes = try {
            File.readFrom(Path(path))
        } catch (_: Exception) {
            return None
        }
        if (bytes.size != Int64(w) * Int64(h) * 4) {
            return None
        }
        Some((Int32(w), Int32(h), bytes))
    }

    /**
     * Creates a GPU texture suitable as an off-screen render target, with BLEND mode
     * so it composites correctly when drawn on top of existing content.
     */

    public func createTargetTexture(width: Float32, height: Float32): Texture {
        // P5：离屏渲染目标改由 L 层离屏抓帧承担
        throw CuiException("createTargetTexture: 已由 L 层离屏抓帧取代")
    }

    // Saved render-target state for beginOffscreen/endOffscreen.
    private var savedScaleX: Float32 = 1.0
    private var savedScaleY: Float32 = 1.0
    private var onOffscreen = false

    /**
     * Switches rendering to the given texture, setting scale to 1:1 so logical
     * coordinates map 1:1 to texture pixels (the texture is created at logical size).
     * Pair with `endOffscreen` which always restores to the window target.
     */

    public func beginOffscreen(texture: Texture) {
        // P5：离屏渲染不再通过 SDL 渲染目标实现
        ()
    }

    /** Restores rendering to the window target and the scale saved by `beginOffscreen`. */

    public func endOffscreen() {
        // P5：同上
        ()
    }

    /** Clears the current render target without the supersampling setup of beginScene. */

    public func clearTarget(color: Color) {
        match (backendCanvas()) {
            case Some(b) => b.beginFrame(color)
            case None => ()
        }
    }

    /**
     * Draws a textured triangle strip for skinned or deformable sprites: `points` holds
     * consecutive (left, right) vertex pairs along the strip in draw coordinates, and
     * `texPoints` holds matching texture coordinates in source-image pixels. `alphas`
     * optionally gives one opacity per vertex, letting overlapping parts cross-fade.
     * All provided lists need the same even size of at least four; invalid sizes draw
     * nothing.
     *
     * Throws `CuiException` when the texture is closed.
     */
    public func texturedStrip(
        texture: Texture,
        points: ArrayList<Point>,
        texPoints: ArrayList<Point>,
        alphas!: ?ArrayList<Float32> = None
    ): Unit {
        if (texture.isClosed()) {
            throw CuiException("Cannot render a closed texture.")
        }
        geometry.texturedStrip(ptr, texture.ptr, points, texPoints, alphas, texture.width, texture.height)
    }

    /**
     * Draws UTF-8 text with the platform UI font through SDL3_ttf.
     *
     * Text takes a dedicated path through the render scale: glyphs are rasterized by
     * FreeType at the EFFECTIVE pixel size (`pointSize` x the live scale) and drawn with
     * the GPU scale reset to 1:1 at snapped target-pixel positions. Rasterizing at the
     * logical size and letting the render scale stretch the small bitmaps — as geometry
     * does — resamples every glyph twice and is what made text visibly softer and fainter
     * than the vector primitives around it. Under supersampling, positions snap to
     * multiples of `SUPERSAMPLE` so the resolve lands glyph origins on whole physical
     * pixels.
     */
    public func text(
        text: String,
        x: Float32,
        y: Float32,
        color: Color,
        pointSize!: Float32 = FontSizes.BODY
    ): Unit {
        match (backend) { case Some(b) => b.text(text, x, y, color, pointSize: pointSize); return; case None => () }
        drawTextCount += 1
        // Empty strings draw nothing (the native backend early-returns on them too); bail
        // before the scale/clip toggle so they cost no SDL state churn. The draw counter
        // above still counts the request, keeping the probe comparable across frames.
        if (text.isEmpty()) {
            return
        }
        match (textBackend) {
            case Some(value) =>
                let native = NativeTextColor(color.r, color.g, color.b, color.a)
                if (scaleX == 1.0 && scaleY == 1.0) {
                    value.draw(text, snapPixel(x, 1.0), snapPixel(y, 1.0), pointSize, native)
                    return
                }
                let step: Float32 = if (ssEnabled) {
                    Float32(ssFactor)
                } else {
                    1.0
                }
                let px = snapPixel(x * scaleX, step)
                let py = snapPixel(y * scaleY, step)
                // Both scale writes and the clip restore go through the applied-state cache,
                // so a repeat of the value SDL already holds (e.g. re-clearing an unset clip
                // after an unclipped draw) costs no SDL call.
                let _ = applyRenderScale(1.0, 1.0)
                applyClipForTextPass()
                value.draw(text, px, py, pointSize * scaleY, native)
                let _ = applyRenderScale(scaleX, scaleY)
                applyClip()
            case None => ()
        }
    }

    /**
     * Measures UTF-8 text using the same font and point size used for drawing.
     */
    public func textWidth(text: String, pointSize!: Float32 = FontSizes.BODY): Float32 {
        match (backend) { case Some(b) => return b.textWidth(text, pointSize: pointSize); case None => () }
        textMetrics(text, pointSize).width
    }

    /**
     * Returns the standard line height for the requested point size.
     */
    public func textHeight(pointSize!: Float32 = FontSizes.BODY): Float32 {
        match (backend) { case Some(b) => return b.textHeight(pointSize: pointSize); case None => () }
        textMetrics("国Ag", pointSize).height
    }

    /**
     * Draws UTF-8 text centered within a rectangle.
     */
    public func textCenter(
        text: String,
        rect: Rect,
        color: Color,
        pointSize!: Float32 = FontSizes.BODY
    ): Unit {
        match (backend) { case Some(b) => b.textCenter(text, rect, color, pointSize: pointSize); return; case None => () }
        let metrics = textMetrics(text, pointSize)
        let tx = rect.centerX() - metrics.width / 2.0
        let ty = rect.centerY() - metrics.height / 2.0
        this.text(text, tx, ty, color, pointSize: pointSize)
    }

    /** Text measurements requested since the last reset — a per-frame text-cost probe. */
    public func textMeasureCount(): UInt64 {
        measureCount
    }

    /** Actual measurement computations (cache misses) since the last reset — SDL_ttf calls on a real backend. */
    public func textComputeCount(): UInt64 {
        computeCount
    }

    /** Text draws issued since the last reset — each rasterizes a (cached, already-shaped) string on a real backend. */
    public func textDrawCount(): UInt64 {
        drawTextCount
    }

    /**
     * Shaping operations (shaped-text cache misses) since the last reset — the real TTF_CreateText
     * calls on a display backend, 0 when headless. On a warm cache during a scroll this stays flat
     * while `textDrawCount` scales with frames, which is the shaped-text cache working.
     */
    public func textShapeCount(): UInt64 {
        match (textBackend) {
            case Some(value) => value.shapeCount()
            case None => 0
        }
    }

    /** Resets the text measurement, compute, draw, and shape counters; call at a frame boundary to sample one frame. */
    public func resetTextMeasureCount(): Unit {
        measureCount = 0
        computeCount = 0
        drawTextCount = 0
        match (textBackend) {
            case Some(value) => value.resetShapeCount()
            case None => ()
        }
    }

    private func textMetrics(text: String, pointSize: Float32): NativeTextMetrics {
        measureCount += 1
        // The cache key is the quantized rasterization size at 1/256pt granularity, so the
        // scaled text-pass path (scaleX/scaleY != 1, e.g. every draw under 2x supersampling)
        // is cached exactly like the unscaled layout-time path — each distinct scale gets its
        // own entries. Quantization only picks the cache bucket: the stored metrics are
        // measured at full float precision, and two sizes must agree to within 1/256pt to
        // share a bucket — far below any visible layout difference. scaleX folds in because
        // logical width divides by it, so equal scaleY at different scaleX must not share.
        // The cache sits above the backend/estimate split, so it serves both the real font
        // backend (skipping SDL_ttf) and the headless estimate, and `computeCount` tracks
        // the misses in either mode.
        let sizeKey = (Int64(pointSize * scaleY * Float32(256.0)) << 20) | (Int64(scaleX * Float32(256.0)) &
            Int64(0xFFFFF))
        match (metricsCache.get(sizeKey, text)) {
            case Some(cached) => return cached
            case None => ()
        }
        computeCount += 1
        let computed = if (scaleX == 1.0 && scaleY == 1.0) {
            computeMetrics(text, pointSize)
        } else {
            match (textBackend) {
                case Some(value) =>
                    // Measure the same scaled rasterization the text pass draws, mapped back to
                    // logical units — carets, selection bands and ellipsis decisions computed
                    // from these metrics then line up with the pixels actually painted.
                    let scaled = value.measure(text, pointSize * scaleY)
                    NativeTextMetrics(scaled.width / scaleX, scaled.height / scaleY)
                case None => NativeTextMetrics(Float32(text.size) * pointSize * 0.55, pointSize * 1.3)
            }
        }
        metricsCache.put(sizeKey, text, computed)
        computed
    }

    // The uncached measurement: the real font backend, or a proportional estimate when headless.
    private func computeMetrics(text: String, pointSize: Float32): NativeTextMetrics {
        match (textBackend) {
            case Some(value) => value.measure(text, pointSize)
            case None => NativeTextMetrics(Float32(text.size) * pointSize * 0.55, pointSize * 1.3)
        }
    }

    // While the text pass draws with the GPU scale reset to 1:1, the active clip must be
    // re-expressed in target pixels: SDL clip rectangles live in the current scaled space.
    private func applyClipForTextPass(): Unit {
        match (currentClip()) {
            case Some(rect) => setClip(Rect(rect.x * scaleX, rect.y * scaleY, rect.w * scaleX, rect.h * scaleY))
            case None => ()
        }
    }

    /**
     * Reads back the current render target and writes it to a BMP file. Useful for
     * automated visual snapshots and documentation thumbnails. Headless it is a no-op —
     * there are no pixels to read.
     *
     * Throws `CuiException` when SDL cannot read the pixels or save the file.
     */
    public func captureBmp(path: String): Unit {
        // P5：改用 L 层离屏抓帧 + 自写 BMP（24 位 BGR，自下而上），不再经 SDL 读像素/SaveBMP。
        let frame = match (captureFramePixels()) {
            case Some(f) => f
            case None => throw CuiException("captureBmp: 抓帧失败")
        }
        let (w, h, rgba) = frame
        writeBmp24(path, w, h, rgba)
    }
}

private func rectFromSdl(raw: SdlRect): Rect {
    Rect(Float32(raw.x), Float32(raw.y), Float32(raw.w), Float32(raw.h))
}

/*
 * Rounds a target-pixel coordinate to the nearest multiple of `step` (1 = whole pixels;
 * the supersample factor = positions that resolve onto whole physical pixels). Glyphs
 * drawn between pixels get smeared across two columns by the linear filter, which reads
 * as blur — snapping is what keeps stems solid.
 */
private func snapPixel(value: Float32, step: Float32): Float32 {
    let units = value / step
    let snapped = if (units >= 0.0) {
        Float32(Int64(units + 0.5))
    } else {
        -Float32(Int64(-units + 0.5))
    }
    snapped * step
}

private func clamp01(value: Float32): Float32 {
    clampF32(value, 0.0, 1.0)
}

private func roundedRadius(rect: Rect, radius: Float32): Float32 {
    clampF32(radius, 0.0, min(rect.w, rect.h) / 2.0)
}

/**
 * Throws `CuiException` when the system-font backend cannot initialize.
 */
private func createTextBackend(renderer: CPointer<Unit>, fontPath: ?String): ?NativeTextRenderer {
    if (renderer.isNull()) {
        return None
    }
    try {
        Some(NativeTextRenderer(renderer, fontPath: fontPath))
    } catch (error: NativeTextException) {
        throw CuiException("System UI font initialization failed: ${error.message}")
    }
}

/// 写 24 位 BMP（BGR，自下而上，行按 4 字节对齐）。rgba 为 w*h*4。
private func writeBmp24(path: String, w: Int32, h: Int32, rgba: Array<UInt8>): Unit {
    let rowBytes = ((Int64(w) * 3 + 3) / 4) * 4
    let pixelBytes = rowBytes * Int64(h)
    let headerSize = Int64(54)
    let total = headerSize + pixelBytes
    let out = Array<UInt8>(total, repeat: 0)
    out[0] = 0x42
    out[1] = 0x4D
    writeI32Le(out, 2, Int32(total))
    writeI32Le(out, 10, Int32(headerSize))
    writeI32Le(out, 14, 40)
    writeI32Le(out, 18, w)
    writeI32Le(out, 22, h)
    out[26] = 1
    out[28] = 24
    writeI32Le(out, 34, Int32(pixelBytes))
    for (y in 0..h) {
        let srcRow = Int64(h - 1 - y) * Int64(w) * 4
        let dstRow = headerSize + Int64(y) * rowBytes
        for (x in 0..w) {
            let src = srcRow + Int64(x) * 4
            let dst = dstRow + Int64(x) * 3
            out[dst] = rgba[src + 2]
            out[dst + 1] = rgba[src + 1]
            out[dst + 2] = rgba[src]
        }
    }
    try {
        File.writeTo(Path(path), out)
    } catch (e: Exception) {
        throw CuiException("captureBmp: 写入失败 ${e}")
    }
}

private func writeI32Le(buf: Array<UInt8>, offset: Int64, value: Int32): Unit {
    let v = Int64(value)
    buf[offset] = UInt8((v >> 0) & 0xFF)
    buf[offset + 1] = UInt8((v >> 8) & 0xFF)
    buf[offset + 2] = UInt8((v >> 16) & 0xFF)
    buf[offset + 3] = UInt8((v >> 24) & 0xFF)
}
