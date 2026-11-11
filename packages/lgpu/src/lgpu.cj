package lgpu

// L 层渲染器的 Cangjie 绑定：wgpu(Vulkan, VK_OHOS_surface) 的 C ABI 包装。
//
// 设计：面向上层（cui 的 Renderer 适配层）暴露的是**安全、带单位**的句柄类型，
// 原生指针不外泄；错误统一转成异常（CuiException 风格），调用方不必查错误码。

import std.collection.ArrayList

foreign {
    func lgpu_capture_offscreen(surface: CPointer<UInt8>, path: CPointer<UInt8>, len: Int64): Int32
    func lgpu_capture_request(): Int32
    func lgpu_capture_size(outW: CPointer<UInt32>, outH: CPointer<UInt32>): Int32
    func lgpu_capture_write(path: CPointer<UInt8>, len: UIntNative): Int32
    func lgpu_version(): CString
    func lgpu_last_error(): CString
    func lgpu_init(): Int32
    func lgpu_self_check(): Int32
    func lgpu_adapter_summary(out: CPointer<UInt8>, outLen: Int64): Int32

    func lgpu_surface_create(nativeWindow: CPointer<UInt8>): CPointer<UInt8>
    func lgpu_native_window_set_geometry(surfaceId: UInt64, width: UInt32, height: UInt32): Int32
    func lgpu_surface_create_from_id(surfaceId: UInt64): CPointer<UInt8>
    func lgpu_surface_init(surface: CPointer<UInt8>, width: UInt32, height: UInt32): Int32
    func lgpu_surface_resize(surface: CPointer<UInt8>, width: UInt32, height: UInt32): Int32
    func lgpu_surface_destroy(surface: CPointer<UInt8>): Unit

    func lgpu_pipeline_init(surface: CPointer<UInt8>): Int32
    func lgpu_frame_begin(surface: CPointer<UInt8>, r: Float32, g: Float32, b: Float32, a: Float32): Int32
    func lgpu_draw_rect(surface: CPointer<UInt8>, x: Float32, y: Float32, w: Float32, h: Float32,
        radius: Float32, stroke: Float32, r: Float32, g: Float32, b: Float32, a: Float32): Int32
    func lgpu_frame_end(surface: CPointer<UInt8>): Int32
    func lgpu_draw_line(surface: CPointer<UInt8>, x1: Float32, y1: Float32, x2: Float32, y2: Float32,
        width: Float32, r: Float32, g: Float32, b: Float32, a: Float32): Int32
    func lgpu_draw_texture_rounded(surface: CPointer<UInt8>, tex: CPointer<UInt8>, dx: Float32, dy: Float32,
        dw: Float32, dh: Float32, u0: Float32, v0: Float32, u1: Float32, v1: Float32, radius: Float32,
        a: Float32): Int32

    func lgpu_draw_rect_gradient(surface: CPointer<UInt8>, x: Float32, y: Float32, w: Float32, h: Float32,
        radius: Float32, stroke: Float32, mode: Float32,
        r1: Float32, g1: Float32, b1: Float32, a1: Float32,
        r2: Float32, g2: Float32, b2: Float32, a2: Float32): Int32
    func lgpu_font_metrics(font: CPointer<UInt8>, pxSize: Float32, out: CPointer<Float32>): Int32
    func lgpu_font_load_path(path: CPointer<UInt8>, pathLen: Int64): CPointer<UInt8>
    func lgpu_font_destroy(font: CPointer<UInt8>): Unit
    func lgpu_text_measure(font: CPointer<UInt8>, utf8: CPointer<UInt8>, len: Int64, pxSize: Float32): Float32
    func lgpu_text_draw(surface: CPointer<UInt8>, font: CPointer<UInt8>, utf8: CPointer<UInt8>, len: Int64,
        x: Float32, y: Float32, pxSize: Float32, r: Float32, g: Float32, b: Float32, a: Float32): Float32
    func lgpu_set_clip(surface: CPointer<UInt8>, x: Float32, y: Float32, w: Float32, h: Float32): Int32
    func lgpu_set_transform(surface: CPointer<UInt8>, sx: Float32, sy: Float32, ox: Float32, oy: Float32): Int32

    func lgpu_texture_create(surface: CPointer<UInt8>, width: UInt32, height: UInt32): CPointer<UInt8>
    func lgpu_texture_create_from_png(surface: CPointer<UInt8>, bytes: CPointer<UInt8>, len: Int64,
        outW: CPointer<UInt32>, outH: CPointer<UInt32>): CPointer<UInt8>
    func lgpu_texture_upload(surface: CPointer<UInt8>, tex: CPointer<UInt8>, x: UInt32, y: UInt32,
        width: UInt32, height: UInt32, pixels: CPointer<UInt8>, stride: UInt32): Int32
    func lgpu_draw_texture(surface: CPointer<UInt8>, tex: CPointer<UInt8>,
        dx: Float32, dy: Float32, dw: Float32, dh: Float32,
        u0: Float32, v0: Float32, u1: Float32, v1: Float32,
        r: Float32, g: Float32, b: Float32, a: Float32): Int32
    func lgpu_texture_destroy(tex: CPointer<UInt8>): Unit
    func lgpu_snapshot_texture(surface: CPointer<UInt8>, outW: CPointer<UInt32>, outH: CPointer<UInt32>): CPointer<UInt8>
    func lgpu_layer_mark(surface: CPointer<UInt8>): Int32
    func lgpu_discard_recorded(surface: CPointer<UInt8>): Int32
    func lgpu_draw_glow_ring(surface: CPointer<UInt8>, cx: Float32, cy: Float32, ringR: Float32, stroke: Float32,
        outer: Float32, inner: Float32, glow: Float32, r: Float32, g: Float32, b: Float32, a: Float32): Int32
    func lgpu_stats_line(out: CPointer<UInt8>, outLen: Int64): Int32
    func lgpu_stats_reset(): Unit
}

public class LgpuException <: Exception {
    public init(message: String) {
        super(message)
    }
}

private func checkRc(rc: Int32, what: String): Unit {
    if (rc < 0) {
        let detail = unsafe { lgpu_last_error().toString() }
        throw LgpuException("${what} failed (rc=${rc}): ${detail}")
    }
}

/// 库版本（用于启动日志/自检）。
public func version(): String {
    unsafe { lgpu_version().toString() }
}

/// 初始化进程级 Vulkan 实例；重复调用无副作用。
public func initialize(): Unit {
    checkRc(unsafe { lgpu_init() }, "lgpu_init")
}

/// 自检：实例可建、能枚举适配器时返回 true。
public func selfCheck(): Bool {
    unsafe { lgpu_self_check() == 0 }
}

// ---- 帧统计（M0 度量）------------------------------------------------------

/// 读取自上次 reset 以来的累计统计行："draws=… rects=… texs=… runs=… uploads=…"
/// "up_bytes=… measures=… tex_create=… tex_destroy=… tex_alive=… frames=…"。
public func statsLine(): String {
    let buf = Array<UInt8>(512, repeat: 0)
    let h = unsafe { acquireArrayRawData(buf) }
    try {
        unsafe { lgpu_stats_line(h.pointer, Int64(buf.size)) }
    } finally {
        unsafe { releaseArrayRawData(h) }
    }
    // NUL 结尾的 C 字符串 → 取到第一个 0 为止
    var len = 0
    while (len < buf.size && buf[len] != 0) {
        len += 1
    }
    return String.fromUtf8(buf[0..len].toArray())
}

/// 清零全部计数（配合窗口采样：reset → 渲染 N 帧 → statsLine）。
public func statsReset(): Unit {
    unsafe { lgpu_stats_reset() }
}

/// 枚举到的适配器摘要（每行 name|backend|type），用于真机诊断。
public func adapterSummary(): String {
    let buf = Array<UInt8>(4096, repeat: 0u8)
    let handle = unsafe { acquireArrayRawData(buf) }
    let n = unsafe { lgpu_adapter_summary(handle.pointer, 4096) }
    unsafe { releaseArrayRawData(handle) }
    if (n < 0) {
        return ""
    }
    let text = String.fromUtf8(buf)
    let end = text.indexOf("\u{0}") ?? text.size
    return text[0..end]
}

/// 呈现场（一个 XComponent 原生窗口对应一个 Surface）。
public class Surface <: Resource {
    private var handle: CPointer<UInt8>
    /// 创建来源的 surfaceId（0 = 非 surfaceId 创建）
    public var surfaceId: Int64 = 0

    private init(handle: CPointer<UInt8>) {
        this.handle = handle
    }

    /// Resource 要求：句柄已释放即视为关闭。
    public func isClosed(): Bool {
        handle.isNull()
    }

    /// 用 XComponent 的 OHNativeWindow* 建 surface。nativeWindow 必须是有效指针。
    public static func create(nativeWindow: CPointer<UInt8>): Surface {
        initialize()
        let h = unsafe { lgpu_surface_create(nativeWindow) }
        if (h.isNull()) {
            let detail = unsafe { lgpu_last_error().toString() }
            throw LgpuException("lgpu_surface_create failed: ${detail}")
        }
        return Surface(h)
    }

    /// 接管一个**已经存在**的 surface 句柄（由原生侧创建，例如窗口后端）。
    /// 只包装指针，不负责释放底层窗口。
    public static func adopt(raw: CPointer<UInt8>): Surface {
        if (raw.isNull()) {
            throw LgpuException("adopt: null surface handle")
        }
        return Surface(raw)
    }

    /// 由 XComponent 的 surfaceId 直接建 surface（lwindow 自建窗口用：
    /// 全程在本线程完成，不跨边界传窗口指针）。
    public static func fromSurfaceId(surfaceId: Int64): Surface {
        initialize()
        let h = unsafe { lgpu_surface_create_from_id(UInt64(surfaceId)) }
        if (h.isNull()) {
            let detail = unsafe { lgpu_last_error().toString() }
            throw LgpuException("lgpu_surface_create_from_id failed: " + detail)
        }
        let s = Surface(h)
        s.surfaceId = surfaceId
        return s
    }

    /// 建 device/queue 并配置 swapchain（尺寸为物理像素）。
    public func configure(width: Int64, height: Int64): Unit {
        // 先给 native window 设缓冲几何/格式，再建 swapchain：XComponent 的 surface
        // 在 attach 前几何量可能为 0，直接建 swapchain 会导致 present 后不可见。
        if (surfaceId > 0) {
            let _ = unsafe { lgpu_native_window_set_geometry(UInt64(surfaceId), UInt32(width), UInt32(height)) }
        }
        checkRc(unsafe { lgpu_surface_init(handle, UInt32(width), UInt32(height)) }, "lgpu_surface_init")
        checkRc(unsafe { lgpu_pipeline_init(handle) }, "lgpu_pipeline_init")
    }

    /// 尺寸变化后重配 swapchain。
    public func resize(width: Int64, height: Int64): Unit {
        checkRc(unsafe { lgpu_surface_resize(handle, UInt32(width), UInt32(height)) }, "lgpu_surface_resize")
    }

    /// 开始一帧：清屏色 + 清空绘制列表。
    public func beginFrame(r: Float32, g: Float32, b: Float32, a: Float32): Unit {
        checkRc(unsafe { lgpu_frame_begin(handle, r, g, b, a) }, "lgpu_frame_begin")
    }

    /// 设置当前裁剪矩形（像素）；w/h <= 0 取消裁剪。
    public func setClip(x: Float32, y: Float32, w: Float32, h: Float32): Unit {
        checkRc(unsafe { lgpu_set_clip(handle, x, y, w, h) }, "lgpu_set_clip")
    }

    /// 设置全局变换 p' = p * (sx,sy) + (ox,oy)；(1,1,0,0) 复位。
    public func setTransform(sx: Float32, sy: Float32, ox: Float32, oy: Float32): Unit {
        checkRc(unsafe { lgpu_set_transform(handle, sx, sy, ox, oy) }, "lgpu_set_transform")
    }

    /// 推一个矩形（radius > 0 圆角，stroke > 0 描边）。
    public func rect(x: Float32, y: Float32, w: Float32, h: Float32, radius: Float32, stroke: Float32,
        r: Float32, g: Float32, b: Float32, a: Float32): Unit {
        checkRc(unsafe { lgpu_draw_rect(handle, x, y, w, h, radius, stroke, r, g, b, a) }, "lgpu_draw_rect")
    }

    /// 推一个纹理绘制（UV 子区 + tint）。
    public func texture(tex: Texture, dx: Float32, dy: Float32, dw: Float32, dh: Float32,
        u0: Float32, v0: Float32, u1: Float32, v1: Float32,
        r: Float32, g: Float32, b: Float32, a: Float32): Unit {
        checkRc(unsafe { lgpu_draw_texture(handle, tex.raw(), dx, dy, dw, dh, u0, v0, u1, v1, r, g, b, a) },
            "lgpu_draw_texture")
    }

    /// 离屏抓帧：把当前已录制的一帧重绘到离屏纹理并写出原始 RGBA。
    /// 返回值：>0 表示成功（w*1e6+h），<0 为错误码。
    public func captureTo(path: String): Int32 {
        let bytes = path.toArray()
        let handleArr = unsafe { acquireArrayRawData(bytes) }
        let rc = unsafe { lgpu_capture_offscreen(handle, handleArr.pointer, Int64(bytes.size)) }
        unsafe { releaseArrayRawData(handleArr) }
        rc
    }

    /// 同 texture()，但返回 rc 而不是抛异常（供容错路径使用）。
    public func textureRc(tex: Texture, dx: Float32, dy: Float32, dw: Float32, dh: Float32,
        u0: Float32, v0: Float32, u1: Float32, v1: Float32,
        r: Float32, g: Float32, b: Float32, a: Float32): Int32 {
        unsafe { lgpu_draw_texture(handle, tex.raw(), dx, dy, dw, dh, u0, v0, u1, v1, r, g, b, a) }
    }

    /// 画线段（旋转矩形实现）。
    public func line(x1: Float32, y1: Float32, x2: Float32, y2: Float32, width: Float32,
        r: Float32, g: Float32, b: Float32, a: Float32): Unit {
        checkRc(unsafe { lgpu_draw_line(handle, x1, y1, x2, y2, width, r, g, b, a) }, "lgpu_draw_line")
    }

    /// 填充矩形（无圆角、无描边）。
    public func fill(x: Float32, y: Float32, w: Float32, h: Float32,
        r: Float32, g: Float32, b: Float32, a: Float32): Unit {
        rect(x, y, w, h, 0.0, 0.0, r, g, b, a)
    }

    /// 水平/垂直渐变（mode=1 横向，mode=2 纵向）。
    /// 绘制带圆角裁剪的纹理（radius 为像素半径，0 = 普通绘制）。
    public func textureRoundedRc(tex: Texture, dx: Float32, dy: Float32, dw: Float32, dh: Float32,
        u0: Float32, v0: Float32, u1: Float32, v1: Float32, radius: Float32, a: Float32): Int32 {
        unsafe {
            lgpu_draw_texture_rounded(handle, tex.raw(), dx, dy, dw, dh, u0, v0, u1, v1, radius, a)
        }
    }

    public func gradient(x: Float32, y: Float32, w: Float32, h: Float32, mode: Int64,
        r1: Float32, g1: Float32, b1: Float32, a1: Float32,
        r2: Float32, g2: Float32, b2: Float32, a2: Float32): Unit {
        checkRc(unsafe { lgpu_draw_rect_gradient(handle, x, y, w, h, 0.0, 0.0, Float32(mode),
            r1, g1, b1, a1, r2, g2, b2, a2) }, "lgpu_draw_rect_gradient")
    }

    /// 圆（SDF：等价于半径 = 半边的圆角矩形）。
    public func circle(cx: Float32, cy: Float32, radius: Float32,
        r: Float32, g: Float32, b: Float32, a: Float32): Unit {
        this.rect(cx - radius, cy - radius, radius * 2.0, radius * 2.0, radius, 0.0, r, g, b, a)
    }

    /// 圆描边。
    public func strokeCircle(cx: Float32, cy: Float32, radius: Float32, pen: Float32,
        r: Float32, g: Float32, b: Float32, a: Float32): Unit {
        this.rect(cx - radius, cy - radius, radius * 2.0, radius * 2.0, radius, pen, r, g, b, a)
    }

    /// 绘制一段文本（UTF-8），返回前进宽度。
    public func text(font: Font, content: String, x: Float32, y: Float32, pxSize: Float32,
        r: Float32, g: Float32, b: Float32, a: Float32): Float32 {
        let bytes = content.toArray()
        let h = unsafe { acquireArrayRawData(bytes) }
        try {
            unsafe { lgpu_text_draw(handle, font.raw(), h.pointer, Int64(bytes.size), x, y, pxSize, r, g, b, a) }
        } finally {
            unsafe { releaseArrayRawData(h) }
        }
    }

    /// 结束一帧：提交并 present。
    public func endFrame(): Unit {
        checkRc(unsafe { lgpu_frame_end(handle) }, "lgpu_frame_end")
    }

    /// 直接从 PNG 字节创建纹理（解码在 lgpu 内完成）。
    public func createTextureFromPng(bytes: Array<UInt8>): ?Texture {
        let h = unsafe { acquireArrayRawData(bytes) }
        let tex = try {
            unsafe { lgpu_texture_create_from_png(handle, h.pointer, Int64(bytes.size), CPointer<UInt32>(), CPointer<UInt32>()) }
        } finally {
            unsafe { releaseArrayRawData(h) }
        }
        if (tex.isNull()) {
            return None
        }
        return Texture(this, tex)
    }

    /// GPU 快照：把本帧已录制的图元渲染进一张可采样纹理（不读回 CPU、不阻塞）。
    /// 返回 (纹理, 物理宽, 物理高)；失败返回 None。
    public func snapshotTexture(): ?(Texture, UInt32, UInt32) {
        let pw = unsafe { LibC.malloc<UInt32>() }
        let ph = unsafe { LibC.malloc<UInt32>() }
        let tex = unsafe { lgpu_snapshot_texture(handle, pw, ph) }
        let (w, h) = unsafe { (pw.read(), ph.read()) }
        unsafe {
            LibC.free(pw)
            LibC.free(ph)
        }
        if (tex.isNull()) {
            return None
        }
        Some((Texture(this, tex), w, h))
    }

    /// 层断点：此后录制的图元整体画在此前所有图元（含纹理）之上。
    public func layerMark(): Unit {
        unsafe { lgpu_layer_mark(handle) }
    }

    /// 丢弃本帧已录制的全部图元（全屏不透明遮罩覆盖下层时用）。
    public func discardRecorded(): Unit {
        unsafe { lgpu_discard_recorded(handle) }
    }

    /// 单实例 SDF 辉光环（实线 + 内外二次衰减辉光）。
    public func glowRing(cx: Float32, cy: Float32, ringR: Float32, stroke: Float32, outer: Float32,
            inner: Float32, glow: Float32, r: Float32, g: Float32, b: Float32, a: Float32): Unit {
        unsafe { lgpu_draw_glow_ring(handle, cx, cy, ringR, stroke, outer, inner, glow, r, g, b, a) }
    }

    /// 创建一张 RGBA8 纹理。
    public func createTexture(width: Int64, height: Int64): Texture {
        let h = unsafe { lgpu_texture_create(handle, UInt32(width), UInt32(height)) }
        if (h.isNull()) {
            let detail = unsafe { lgpu_last_error().toString() }
            throw LgpuException("lgpu_texture_create failed: ${detail}")
        }
        return Texture(this, h)
    }

    internal func upload(tex: CPointer<UInt8>, x: Int64, y: Int64, w: Int64, h: Int64,
        pixels: CPointer<UInt8>, stride: Int64): Unit {
        checkRc(unsafe { lgpu_texture_upload(handle, tex, UInt32(x), UInt32(y), UInt32(w), UInt32(h), pixels, UInt32(stride)) },
            "lgpu_texture_upload")
    }

    internal func destroyTexture(tex: CPointer<UInt8>): Unit {
        unsafe { lgpu_texture_destroy(tex) }
    }

    public func close(): Unit {
        if (!handle.isNull()) {
            unsafe { lgpu_surface_destroy(handle) }
            handle = CPointer<UInt8>()
        }
    }
}

/// GPU 纹理句柄（RGBA8）。随 Surface 关闭而失效。
public class Texture {
    private let owner: Surface
    private var handle: CPointer<UInt8>

    internal init(owner: Surface, handle: CPointer<UInt8>) {
        this.owner = owner
        this.handle = handle
    }

    internal func raw(): CPointer<UInt8> {
        handle
    }

    /// 上传 RGBA8 像素（支持子区域；stride 为每行字节数）。
    public func upload(rgba: Array<UInt8>, x: Int64, y: Int64, w: Int64, h: Int64, stride: Int64): Unit {
        let handlePtr = unsafe { acquireArrayRawData(rgba) }
        try {
            owner.upload(handle, x, y, w, h, handlePtr.pointer, stride)
        } finally {
            unsafe { releaseArrayRawData(handlePtr) }
        }
    }

    public func close(): Unit {
        if (!handle.isNull()) {
            owner.destroyTexture(handle)
            handle = CPointer<UInt8>()
        }
    }
}

/// 字体句柄（由文件加载）。
public class Font {
    private var handle: CPointer<UInt8>

    private init(handle: CPointer<UInt8>) {
        this.handle = handle
    }

    /// 从字体文件加载。
    public static func load(path: String): Font {
        let bytes = path.toArray()
        let bh = unsafe { acquireArrayRawData(bytes) }
        let h = try {
            unsafe { lgpu_font_load_path(bh.pointer, Int64(bytes.size)) }
        } finally {
            unsafe { releaseArrayRawData(bh) }
        }
        if (h.isNull()) {
            let detail = unsafe { lgpu_last_error().toString() }
            throw LgpuException("lgpu_font_load_path failed: ${detail}")
        }
        return Font(h)
    }

    internal func raw(): CPointer<UInt8> {
        handle
    }

    /// 字体度量：返回 (ascent, descent, lineGap, unitsPerEm)，均已按 pxSize 缩放。
    public func metrics(pxSize: Float32): (Float32, Float32, Float32, Float32) {
        let buf = Array<Float32>(4, repeat: 0.0f32)
        let h = unsafe { acquireArrayRawData(buf) }
        try {
            checkRc(unsafe { lgpu_font_metrics(handle, pxSize, h.pointer) }, "lgpu_font_metrics")
        } finally {
            unsafe { releaseArrayRawData(h) }
        }
        (buf[0], buf[1], buf[2], buf[3])
    }

    /// 字符串宽度（像素）。
    public func measure(content: String, pxSize: Float32): Float32 {
        let bytes = content.toArray()
        let h = unsafe { acquireArrayRawData(bytes) }
        try {
            unsafe { lgpu_text_measure(handle, h.pointer, Int64(bytes.size), pxSize) }
        } finally {
            unsafe { releaseArrayRawData(h) }
        }
    }

    public func close(): Unit {
        if (!handle.isNull()) {
            unsafe { lgpu_font_destroy(handle) }
            handle = CPointer<UInt8>()
        }
    }
}

// ---- 抓帧（Modal 模糊 / 页面转场快照）----------------------------------

/// 请求下一帧结束后抓帧（一次性）。
public func captureRequest(): Unit {
    unsafe { lgpu_capture_request() }
}

/// 最近一次抓帧的尺寸；没有抓帧数据时返回 (0, 0)。
public func captureSize(): (UInt32, UInt32) {
    let pw = unsafe { LibC.malloc<UInt32>() }
    let ph = unsafe { LibC.malloc<UInt32>() }
    var w: UInt32 = 0
    var h: UInt32 = 0
    unsafe { lgpu_capture_size(pw, ph) }
    unsafe {
        w = pw.read()
        h = ph.read()
        LibC.free(pw)
        LibC.free(ph)
    }
    (w, h)
}

/// 把最近一次抓帧写为原始 RGBA 文件（无头部）。成功返回 0。
public func captureWriteTo(path: String): Int32 {
    let bytes = path.toArray()
    let handle = unsafe { acquireArrayRawData(bytes) }
    let rc = unsafe { lgpu_capture_write(handle.pointer, UIntNative(bytes.size)) }
    unsafe { releaseArrayRawData(handle) }
    rc
}
