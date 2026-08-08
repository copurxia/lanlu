package webview

import std.collection.ArrayList

// webview_native(Blitz 离屏 HTML → RGBA)的安全仓颉封装。
// 契约(与 native/src/lib.rs 头注释一致):
// - 单线程使用(UI 线程),会话句柄不跨线程;
// - 帧经 takeFrame 拷贝进成员数组(尺寸不变时原地覆写),借用语义同
//   libvlc_ffi VideoFrame:跨帧持久持有需调用方自行拷贝;
// - Rust 侧不碰网络,子资源经 pendingResources/provideResource 外部供数。

foreign func lanlu_wv_create(width: UInt32, height: UInt32, scale: Float32): CPointer<Unit>
foreign func lanlu_wv_destroy(s: CPointer<Unit>): Unit
foreign func lanlu_wv_warmup(): Int32
foreign func lanlu_wv_load_html(s: CPointer<Unit>, html: CPointer<UInt8>, htmlLen: UIntNative, baseUrl: CString): Int32
foreign func lanlu_wv_resize(s: CPointer<Unit>, width: UInt32, height: UInt32, scale: Float32): Unit
foreign func lanlu_wv_scroll_by(s: CPointer<Unit>, dy: Float32): Int32
foreign func lanlu_wv_scroll_to(s: CPointer<Unit>, y: Float32): Unit
foreign func lanlu_wv_scroll_to_page(s: CPointer<Unit>, y: Float32): Unit
foreign func lanlu_wv_scroll_y(s: CPointer<Unit>): Float32
foreign func lanlu_wv_content_height(s: CPointer<Unit>): Float32
foreign func lanlu_wv_set_theme_css(s: CPointer<Unit>, css: CString, cssLen: UIntNative): Unit
foreign func lanlu_wv_provide_resource(s: CPointer<Unit>, url: CString, bytes: CPointer<UInt8>, bytesLen: UIntNative): Int32
foreign func lanlu_wv_pending_count(s: CPointer<Unit>): UIntNative
foreign func lanlu_wv_pending_url(s: CPointer<Unit>, index: UIntNative): CString
foreign func lanlu_wv_render(s: CPointer<Unit>): UInt64
foreign func lanlu_wv_frame_ptr(s: CPointer<Unit>): CPointer<UInt8>
foreign func lanlu_wv_frame_width(s: CPointer<Unit>): UInt32
foreign func lanlu_wv_frame_height(s: CPointer<Unit>): UInt32

foreign func memcpy(destination: CPointer<Unit>, source: CPointer<Unit>, count: UIntNative): CPointer<Unit>

/** 离屏渲染产出的一帧 RGBA 图像。 */
public class HtmlFrame {
    public let width: Int32
    public let height: Int32
    public let generation: UInt64
    // 借用语义:该数组由 WebviewSession 持有并在下次 takeFrame 返回新帧时原地覆写
    // (尺寸变化才重新分配)。需要跨帧持久持有的调用方必须自行拷贝;
    // client-next 的用法(当帧同步上传纹理)不受此限制。
    public let rgba: Array<UInt8>

    init(width: Int32, height: Int32, generation: UInt64, rgba: Array<UInt8>) {
        this.width = width
        this.height = height
        this.generation = generation
        this.rgba = rgba
    }
}

/**
 * 预热进程级共享字体上下文（幂等；应用启动早期调用一次）。
 * 把 fontique 系统字体扫描提前到 GC 未活跃、栈浅的启动阶段，
 * 消除 loadHtml 时的长原生停留窗口（Cangjie GC 栈扫描崩溃风险）。
 */
public func warmup(): Unit {
    unsafe { let _ = lanlu_wv_warmup() }
}

/** Blitz 离屏 HTML 渲染会话(单线程使用)。 */
public class WebviewSession <: Resource {
    private var handle = CPointer<Unit>()
    private var lastFrameGeneration: UInt64 = 0
    // takeFrame 复用的出帧数组:尺寸不变时原地覆写,避免每帧分配。
    private var framePixels = Array<UInt8>(0, repeat: 0u8)

    public init(width: Int32, height: Int32, scale: Float32) {
        let raw = unsafe { lanlu_wv_create(UInt32(width), UInt32(height), scale) }
        if (raw.isNull()) {
            throw Exception("webview session creation failed")
        }
        this.handle = raw
    }

    public func isClosed(): Bool {
        handle.isNull()
    }

    /** 加载 HTML 字节(替换已有文档);baseUrl 用于相对路径解析。 */
    public func loadHtml(html: Array<UInt8>, baseUrl: String): Unit {
        ensureOpen()
        let cbase = unsafe { LibC.mallocCString(baseUrl) }
        try {
            unsafe {
                let data = acquireArrayRawData(html)
                let rc = lanlu_wv_load_html(handle, data.pointer, UIntNative(html.size), cbase)
                releaseArrayRawData(data)
                if (rc != 0) {
                    throw Exception("webview loadHtml failed")
                }
            }
        } finally {
            unsafe { LibC.free(cbase) }
        }
    }

    /** 调整视口(物理像素)与 DPI scale。 */
    public func resize(width: Int32, height: Int32, scale: Float32): Unit {
        ensureOpen()
        unsafe { lanlu_wv_resize(handle, UInt32(width), UInt32(height), scale) }
    }

    /** 向下滚动 dy 像素;返回 false 表示已到边界(调用方可外溢给翻页)。 */
    public func scrollBy(dy: Float32): Bool {
        if (handle.isNull()) { return false }
        unsafe { lanlu_wv_scroll_by(handle, dy) == 1 }
    }

    /** 绝对滚动到 y(内部 clamp)。 */
    public func scrollTo(y: Float32): Unit {
        ensureOpen()
        unsafe { lanlu_wv_scroll_to(handle, y) }
    }

    /** 分页副视口定位；允许末页越过普通滚动上界并以空白补足。 */
    public func scrollToPage(y: Float32): Unit {
        ensureOpen()
        unsafe { lanlu_wv_scroll_to_page(handle, y) }
    }

    public func scrollY(): Float32 {
        if (handle.isNull()) { return 0.0 }
        unsafe { lanlu_wv_scroll_y(handle) }
    }

    /** 内容总高(逻辑像素)。 */
    public func contentHeight(): Float32 {
        if (handle.isNull()) { return 0.0 }
        unsafe { lanlu_wv_content_height(handle) }
    }

    /** 注入/替换 UA 级主题 CSS(深浅色)。 */
    public func setThemeCss(css: String): Unit {
        ensureOpen()
        // String 内部即 UTF-8,size 为字节长度;mallocCString 产出同内容 C 串。
        let cptr = unsafe { LibC.mallocCString(css) }
        try {
            unsafe { lanlu_wv_set_theme_css(handle, cptr, UIntNative(css.size)) }
        } finally {
            unsafe { LibC.free(cptr) }
        }
    }

    /** 待供数子资源 URL 列表(外部需拉取后经 provideResource 回填)。 */
    public func pendingResources(): ArrayList<String> {
        let list = ArrayList<String>()
        if (handle.isNull()) { return list }
        unsafe {
            let count = lanlu_wv_pending_count(handle)
            for (i in 0..Int64(count)) {
                let url = lanlu_wv_pending_url(handle, UIntNative(i))
                if (!url.isNull()) {
                    list.add(url.toString())
                }
            }
        }
        list
    }

    /** 回填子资源字节;URL 不在待供数队列时忽略。返回是否命中。 */
    public func provideResource(url: String, bytes: Array<UInt8>): Bool {
        ensureOpen()
        let curl = unsafe { LibC.mallocCString(url) }
        try {
            unsafe {
                let data = acquireArrayRawData(bytes)
                let rc = lanlu_wv_provide_resource(handle, curl, data.pointer, UIntNative(bytes.size))
                releaseArrayRawData(data)
                rc == 1
            }
        } finally {
            unsafe { LibC.free(curl) }
        }
    }

    /**
     * 取最新一帧。无新帧(代际未前进)返回 None;
     * 有则把帧拷贝进复用数组后返回。
     */
    public func takeFrame(): ?HtmlFrame {
        ensureOpen()
        unsafe {
            let generation = lanlu_wv_render(handle)
            if (generation == 0 || generation == lastFrameGeneration) {
                return None
            }
            let ptr = lanlu_wv_frame_ptr(handle)
            if (ptr.isNull()) {
                return None
            }
            let width = Int32(lanlu_wv_frame_width(handle))
            let height = Int32(lanlu_wv_frame_height(handle))
            let need = Int64(width) * Int64(height) * 4
            if (need <= 0) {
                return None
            }
            // 复用上帧数组:尺寸不变(同视口连续帧)时原地覆写,
            // 视口切换(resize)才重新分配。
            if (Int64(framePixels.size) != need) {
                framePixels = Array<UInt8>(need, repeat: 0u8)
            }
            let dst = acquireArrayRawData(framePixels)
            let _ = memcpy(CPointer<Unit>(dst.pointer), CPointer<Unit>(ptr), UIntNative(need))
            releaseArrayRawData(dst)
            lastFrameGeneration = generation
            Some(HtmlFrame(width, height, generation, framePixels))
        }
    }

    public func close(): Unit {
        if (!handle.isNull()) {
            unsafe { lanlu_wv_destroy(handle) }
            handle = CPointer<Unit>()
        }
    }

    private func ensureOpen(): Unit {
        if (handle.isNull()) {
            throw Exception("webview session is closed")
        }
    }
}
