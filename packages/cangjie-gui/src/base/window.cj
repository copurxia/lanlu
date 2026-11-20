package cui.base

import lbase.{Canvas, Color, Insets, Pen, Point, Rect, Size, clampF32}

// P5：窗口已全部由 L 层承担（OHOS 上不再创建 SDL 窗口、不再初始化 SDL 视频子系统）。
// 这个文件保留 SdlWindow 的公开 API（视图/业务代码零改动），内部是纯状态 + L 层事件桥。

import std.time.MonoTime

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
    // Create the window without OS decorations (SDL_WINDOW_BORDERLESS) instead of mapping it
    // decorated and dropping the frame afterwards with `setBordered(false)`. For a window the
    // app always wants borderless this is the cheaper path with the same end state: on Wayland
    // libdecor never rasterises title-bar decorations that would be removed a moment later.
    public let borderless: Bool

    public init(
        title: String,
        width: Int32,
        height: Int32,
        resizable!: Bool = true,
        highDpi!: Bool = true,
        scale!: Float32 = 1.0,
        vsync!: Bool = true,
        supersample!: Int32 = AUTO_SUPERSAMPLE,
        fontPath!: ?String = None,
        borderless!: Bool = false
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
        this.borderless = borderless
    }
}

// L 层事件源：上层把输入桥接成 UiEvent（None = 无事件）。
public var headlessEventSource: Option<() -> Option<UiEvent>> = None

// 光标周围文本（平台层据此告知输入法做联想/删除上下文）。
// 参数：(文本, 光标字节偏移, 选区锚点字节偏移)。只在文本/光标变化时调用，避免每帧刷协议。
public var textSurroundingSink: ?((String, Int64, Int64) -> Unit) = None

// R6：空闲等待的阻塞原语（宿主注入；lgui 不依赖平台层）。
// wait 返回 true 表示有事件可取；wake 打断正在进行的 wait。
public var eventWaitSource: ?((Int32) -> Bool) = None
public var eventWakeSink: ?() -> Unit = None

let g_monoStart: MonoTime = MonoTime.now()

func monoMillis(): Int64 {
    (MonoTime.now() - g_monoStart).toMilliseconds()
}

/// 当前焦点控件 id（诊断用；每帧由 DesktopApp 刷新）。
public var debugFocusId: String = ""

/// 最近一次文本框光标矩形（窗口坐标）。没有焦点文本框时为 None。
/// 平台层用它决定光标形状：指针落在框内就给文本光标。
public var lastTextInputRect: Option<Rect> = None

/// 平台层注册的「光标矩形」出口：lgui 只负责算，怎么用由 L 层决定。
public var textInputAreaSink: Option<(Rect) -> Unit> = None

public class SdlWindow <: Resource {
    // 保留指针字段以兼容 extend（值恒为空指针：没有 SDL 窗口）。
    // P6 拆 base 包后 dialogs 等兄弟子包也要读它，故 public（值恒空，无风险）。
    public let windowPtr: CPointer<Unit> = CPointer<Unit>()
    private let rendererPtr: CPointer<Unit> = CPointer<Unit>()
    private var closed = false

    public var width: Int32
    public var height: Int32
    private var titleText: String = ""
    public let scale: Float32
    public let vsync: Bool
    public let renderer: Renderer

    /// L 层窗口：尺寸/缩放来自调用方（从系统窗口查询），绘制由替代后端承担。
    public init(spec: WindowSpec) {
        this.width = spec.width
        this.height = spec.height
        this.titleText = spec.title
        this.scale = spec.scale
        this.vsync = spec.vsync
        this.renderer = Renderer.headless()
    }

    public static func headless(spec: WindowSpec): SdlWindow {
        SdlWindow(spec)
    }

    public func setTitle(title: String): Unit {
        this.titleText = title
    }

    /// 当前标题（window_runtime 的 title() 读它）。
    internal func titleValue(): String {
        titleText
    }

    public func setSize(width: Int32, height: Int32): Unit {
        // L 层窗口尺寸由系统决定，应用侧不改（保留接口以兼容视图代码）
    }

    public func refreshSize(): Size {
        Size(Float32(width), Float32(height))
    }

    public func setTextInputArea(rect: Rect): Unit {
        // 平台层通过 textInputAreaSink 接管（Wayland 走 text-input，OHOS 给 IME 面板用）
        match (textInputAreaSink) {
            case Some(sink) => sink(rect)
            case None => ()
        }
    }

    public func pollEvent(): ?UiEvent {
        match (headlessEventSource) {
            case Some(source) => source()
            case None => None
        }
    }

    /// R6：空闲阻塞等待（不再 4ms 忙轮询）。
    /// 阻塞原语由宿主注入（lgui 不依赖具体平台层）：
    ///   lgui.eventWaitSource = Some({ms => lwindow.lwpWaitForEvents(ms)})
    /// 未注入时回退旧的短轮询（单元测试/无平台场景行为不变）。
    /// 空闲时阻塞在通道上，事件到达 / wake / 超时三者任一唤醒，零忙轮询。
    public func waitEventTimeout(timeoutMs: Int32): ?UiEvent {
        // 先试一次非阻塞取事件（常见路径：事件已在队列里）
        match (pollEvent()) {
            case Some(event) => return Some(event)
            case None => ()
        }
        match (eventWaitSource) {
            case Some(wait) =>
                if (wait(timeoutMs)) {
                    return pollEvent()
                }
                // 兜底：注入的等待方若立即返回 false（例如通道未就绪），
                // 至少让出 1ms，避免退化成 100% CPU 空转。
                if (timeoutMs > 0) {
                    sleep(Duration.millisecond * 1)
                }
                None
            case None =>
                // 回退：旧的短轮询（无阻塞原语可用）
                let start = monoMillis()
                while (true) {
                    match (pollEvent()) {
                        case Some(event) => return Some(event)
                        case None => ()
                    }
                    if (monoMillis() - start >= Int64(timeoutMs)) {
                        return None
                    }
                    sleep(Duration.millisecond * 4)
                }
                None
        }
    }

    public func pushWakeEvent(): Unit {
        match (eventWakeSink) {
            case Some(wake) => wake()
            case None => ()
        }
    }

    public func ticks(): UInt64 {
        UInt64(monoMillis())
    }

    public func delay(ms: UInt32): Unit {
        if (ms > 0) {
            sleep(Duration.millisecond * Int64(ms))
        }
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
    }
}
