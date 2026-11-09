package lgpu

// L 层渲染器的 Cangjie 绑定：wgpu(Vulkan, VK_OHOS_surface) 的 C ABI 包装。
//
// 设计：面向上层（cui 的 Renderer 适配层）暴露的是**安全、带单位**的句柄类型，
// 原生指针不外泄；错误统一转成异常（CuiException 风格），调用方不必查错误码。

import std.collection.ArrayList

foreign {
    func lgpu_version(): CString
    func lgpu_last_error(): CString
    func lgpu_init(): Int32
    func lgpu_self_check(): Int32
    func lgpu_adapter_summary(out: CPointer<UInt8>, outLen: Int64): Int32

    func lgpu_surface_create(nativeWindow: CPointer<UInt8>): CPointer<UInt8>
    func lgpu_surface_init(surface: CPointer<UInt8>, width: UInt32, height: UInt32): Int32
    func lgpu_surface_resize(surface: CPointer<UInt8>, width: UInt32, height: UInt32): Int32
    func lgpu_surface_destroy(surface: CPointer<UInt8>): Unit

    func lgpu_pipeline_init(surface: CPointer<UInt8>): Int32
    func lgpu_frame_begin(surface: CPointer<UInt8>, r: Float32, g: Float32, b: Float32, a: Float32): Int32
    func lgpu_draw_rect(surface: CPointer<UInt8>, x: Float32, y: Float32, w: Float32, h: Float32,
        radius: Float32, stroke: Float32, r: Float32, g: Float32, b: Float32, a: Float32): Int32
    func lgpu_frame_end(surface: CPointer<UInt8>): Int32
    func lgpu_set_clip(surface: CPointer<UInt8>, x: Float32, y: Float32, w: Float32, h: Float32): Int32
    func lgpu_set_transform(surface: CPointer<UInt8>, sx: Float32, sy: Float32, ox: Float32, oy: Float32): Int32

    func lgpu_texture_create(surface: CPointer<UInt8>, width: UInt32, height: UInt32): CPointer<UInt8>
    func lgpu_texture_upload(surface: CPointer<UInt8>, tex: CPointer<UInt8>, x: UInt32, y: UInt32,
        width: UInt32, height: UInt32, pixels: CPointer<UInt8>, stride: UInt32): Int32
    func lgpu_draw_texture(surface: CPointer<UInt8>, tex: CPointer<UInt8>,
        dx: Float32, dy: Float32, dw: Float32, dh: Float32,
        u0: Float32, v0: Float32, u1: Float32, v1: Float32,
        r: Float32, g: Float32, b: Float32, a: Float32): Int32
    func lgpu_texture_destroy(tex: CPointer<UInt8>): Unit
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

    /// 建 device/queue 并配置 swapchain（尺寸为物理像素）。
    public func configure(width: Int64, height: Int64): Unit {
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

    /// 结束一帧：提交并 present。
    public func endFrame(): Unit {
        checkRc(unsafe { lgpu_frame_end(handle) }, "lgpu_frame_end")
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
