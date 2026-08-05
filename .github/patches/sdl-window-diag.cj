package sdl

import std.env.getVariable

// 临时诊断（定位 Windows 启动即崩的运行时检查失败，查到后可删）：
// LANLU_NO_VULKAN=1 时建窗不带 SDL_WINDOW_VULKAN flag，用于对照实验——
// 若置 1 后不再崩，则根因在 Vulkan 建窗/渲染路径。
private func vulkanDisabled(): Bool {
    match (getVariable("LANLU_NO_VULKAN")) {
        case Some(v) => v == "1" || v == "true"
        case None => false
    }
}

public struct WindowSpec {
    public let title: String
    public let width: Int32
    public let height: Int32
    public let resizable: Bool
    public let highDpi: Bool
    public let scale: Float32
    // Whether the renderer waits for the vertical blank on present. On (the default) prevents
    // tearing and is the right choice for real applications. Off lets the frame loop run
    // uncapped, which is how a benchmark measures true per-frame work: with vsync on, every
    // frame period snaps to a refresh multiple (16.7/33.3/50 ms at 60 Hz), so any improvement
    // smaller than a whole refresh interval is invisible.
    public let vsync: Bool
    // Supersample factor per axis (1 = off, 2 = 4x-samples anti-aliasing). Higher is smoother but
    // pays for that many times the pixels every frame; lower trades edge smoothness for fill cost.
    // The default AUTO_SUPERSAMPLE (0) adapts to the render driver: 1x on SDL's "software"
    // renderer, where supersampling's fill cost is pure CPU, 2x on hardware. Pass an explicit
    // value (>= 1) to override the adaptation — 2 suits a hardware renderer.
    public let supersample: Int32
    // Optional path to a .ttf/.ttc/.otf font file. When set, the renderer loads this font
    // instead of scanning platform system-font candidates. Changes take effect on next launch.
    public let fontPath: ?String

    public init(
        title: String,
        width: Int32,
        height: Int32,
        resizable!: Bool = true,
        highDpi!: Bool = true,
        scale!: Float32 = 1.0,
        vsync!: Bool = true,
        supersample!: Int32 = AUTO_SUPERSAMPLE,
        fontPath!: ?String = None
    ) {
        this.title = title
        this.width = width
        this.height = height
        this.resizable = resizable
        this.highDpi = highDpi
        this.scale = normalizedScale(scale)
        this.vsync = vsync
        this.supersample = supersample
        this.fontPath = fontPath
    }
}

public class SdlWindow <: Resource {
    internal let windowPtr: CPointer<Unit>
    private let rendererPtr: CPointer<Unit>
    private var closed = false

    public var width: Int32
    public var height: Int32
    public let scale: Float32
    // Whether present blocks to the vertical blank (from WindowSpec). The frame loop reads
    // this for pacing: with vsync the present is the throttle and no extra sleep is needed;
    // without it the loop pads each frame to its budget from the frame-start timestamp.
    public let vsync: Bool
    public let renderer: Renderer

    /**
     * Throws `CuiException` when SDL cannot create or initialize the window, renderer, or text input.
     */
    public init(spec: WindowSpec) {
        this.width = spec.width
        this.height = spec.height
        this.scale = spec.scale
        this.vsync = spec.vsync

        // 临时启动诊断（与 main.cj 的 [boot] 打印配套，查到后可删）：
        // 崩溃前最后一条 [win] 打印即崩溃所在的 SDL 调用阶段。
        if (!unsafe { SDL_Init(SDL_INIT_VIDEO) }) {
            throw CuiException("SDL_Init failed: ${lastSdlError()}")
        }
        println("[win] 3.1 SDL_Init ok")

        var flags = UInt64(0)
        // Allow SDL's auto-selected renderer to use Vulkan; without this flag the
        // Vulkan render driver is skipped and selection falls back to OpenGL.
        if (!vulkanDisabled()) {
            flags = flags | SDL_WINDOW_VULKAN
        }
        if (spec.resizable) {
            flags = flags | SDL_WINDOW_RESIZABLE
        }
        if (spec.highDpi) {
            flags = flags | SDL_WINDOW_HIGH_PIXEL_DENSITY
        }
        println("[win] 3.2 flags ready, vulkan=${!vulkanDisabled()}")

        var window = CPointer<Unit>()
        var createdRenderer = CPointer<Unit>()
        let titleText = unsafe { LibC.mallocCString(spec.title) }
        try (titleResource = titleText.asResource()) {
            let pixelWidth = scaledDimension(spec.width, spec.scale)
            let pixelHeight = scaledDimension(spec.height, spec.scale)
            let ok = unsafe {
                SDL_CreateWindowAndRenderer(titleResource.value, pixelWidth, pixelHeight, flags, inout window,
                    inout createdRenderer)
            }
            if (!ok || window.isNull() || createdRenderer.isNull()) {
                destroyCreatedResources(window, createdRenderer)
                throw CuiException("SDL_CreateWindowAndRenderer failed: ${lastSdlError()}")
            }
            println("[win] 3.3 window+renderer created")
            configureRenderer(window, createdRenderer, spec.scale, spec.vsync)
            println("[win] 3.4 renderer configured")
            if (!unsafe { SDL_StartTextInput(window) }) {
                destroyCreatedResources(window, createdRenderer)
                throw CuiException("SDL_StartTextInput failed: ${lastSdlError()}")
            }
            println("[win] 3.5 text input started")
        }

        this.windowPtr = window
        this.rendererPtr = createdRenderer
        this.renderer = Renderer(createdRenderer, contentScale: spec.scale, supersample: spec.supersample,
            fontPath: spec.fontPath)
        println("[win] 3.6 Renderer(font) ready")
    }

    public func setTitle(title: String): Unit {
        let cTitle = unsafe { LibC.mallocCString(title) }
        try (titleResource = cTitle.asResource()) {
            ensureSdl(unsafe { SDL_SetWindowTitle(windowPtr, titleResource.value) }, "SDL_SetWindowTitle")
        }
    }

    public func setSize(width: Int32, height: Int32): Unit {
        let pixelWidth = scaledDimension(width, scale)
        let pixelHeight = scaledDimension(height, scale)
        ensureSdl(unsafe { SDL_SetWindowSize(windowPtr, pixelWidth, pixelHeight) }, "SDL_SetWindowSize")
        this.width = width
        this.height = height
    }

    public func refreshSize(): Size {
        var w: Int32 = 0
        var h: Int32 = 0
        ensureSdl(unsafe { SDL_GetWindowSize(windowPtr, inout w, inout h) }, "SDL_GetWindowSize")
        width = Int32(Float32(w) / scale)
        height = Int32(Float32(h) / scale)
        Size(Float32(width), Float32(height))
    }

    /**
     * Tells the OS where the text caret is, in the window's logical pixels (the same space
     * as events and drawing), so IME composition UI — the candidate window — appears at the
     * caret instead of a screen corner. The conversion to window pixels happens here.
     */
    public func setTextInputArea(rect: Rect): Unit {
        var raw = Rect(rect.x * scale, rect.y * scale, rect.w * scale, rect.h * scale).toSdlRect()
        ensureSdl(unsafe { SDL_SetTextInputArea(windowPtr, inout raw, 0) }, "SDL_SetTextInputArea")
    }

    public func pollEvent(): ?UiEvent {
        var raw = SdlEvent()
        if (!unsafe { SDL_PollEvent(inout raw) }) {
            return None
        }
        return Some(scaleEventCoordinates(decodeEvent(raw), scale))
    }

    /**
     * Blocks until an event arrives or `timeoutMs` elapses, whichever comes first; returns
     * `None` on timeout. This is the idle path of the deadline-driven frame loop: it sleeps
     * inside SDL instead of polling, so an idle window costs no CPU. SDL keeps pumping its
     * event loop internally while waiting, so OS-level callbacks (file dialogs) still fire.
     */
    public func waitEventTimeout(timeoutMs: Int32): ?UiEvent {
        var raw = SdlEvent()
        if (!unsafe { SDL_WaitEventTimeout(inout raw, timeoutMs) }) {
            return None
        }
        return Some(scaleEventCoordinates(decodeEvent(raw), scale))
    }

    /**
     * Wakes a loop blocked in `waitEventTimeout` by queueing an SDL user event. Safe to call
     * from any thread (worker completion, SSE arrival): SDL_PushEvent locks the event queue
     * internally, and the queued event decodes as `Unknown`, which simply marks the next
     * iteration non-idle. A burst of calls may queue a few extra wake events; each costs one
     * cheap no-render iteration, so no deduplication is needed.
     */
    public func pushWakeEvent(): Unit {
        let eventPtr = unsafe { LibC.malloc<SdlEvent>() }
        try (eventResource = eventPtr.asResource()) {
            // SDL_PushEvent copies the whole SDL_Event union into the queue: zero-initialise
            // it first so the bytes beyond the common type field are not heap garbage.
            unsafe { CPointer<SdlEvent>(eventResource.value).write(SdlEvent()) }
            var common = SdlCommonEvent()
            common.eventType = SDL_EVENT_USER
            unsafe { CPointer<SdlCommonEvent>(eventResource.value).write(common) }
            let _ = unsafe { SDL_PushEvent(eventResource.value) }
        }
    }

    public func ticks(): UInt64 {
        unsafe { SDL_GetTicks() }
    }

    public func delay(ms: UInt32): Unit {
        unsafe { SDL_Delay(ms) }
    }

    public func isClosed(): Bool {
        closed
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        renderer.releaseResources()
        unsafe {
            if (windowPtr.isNotNull()) {
                let _ = SDL_StopTextInput(windowPtr)
            }
            if (rendererPtr.isNotNull()) {
                SDL_DestroyRenderer(rendererPtr)
            }
            if (windowPtr.isNotNull()) {
                SDL_DestroyWindow(windowPtr)
            }
            SDL_Quit()
        }
    }
}
