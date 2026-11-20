package cui.desktop

import std.collection.ArrayList
import cui.core.{lastStateWriteName, recentStateWriteIds, recentStateWriteNames, stateWakeSink, stateWriteCount}
import std.sort.sort
import std.env.getCommandLine
import std.env.getVariable
import std.fs.{File, Path}
import lbase.{Canvas, Color, Rect}
import cui.base.{FrameInfo, Key, MouseButton, SdlWindow, UiEvent, WindowSpec, debugFocusId, lastTextInputRect}
import cui.input.{Cursor, Keyboard, SystemCursor}
import cui.dialogs.FileDialogOptions
import cui.dialogs.FileDialogRequest
import cui.dialogs.FileDialogs
import cui.system.AppMetadata
import cui.system.ApplicationMetadata
import cui.system.SdlHintSetting
import cui.system.SdlHints
import cui.core.{CursorShape, StateStore, Theme, UiContext, Widget, buildRoot, currentStateGeneration, drawTooltip}

// Long enough for the first paint to settle and for background work started at launch
// (dialog-free examples fetch data on worker threads) to land in the frame.
private let SNAPSHOT_SETTLE_FRAMES: UInt64 = 48

/// 每帧回调（联调/抓帧用）：参数是自增帧号。渲染循环内调用，故一定执行。
public var frameProbeHook: ?(Int64) -> Unit = None

/// 空闲渲染诊断出口：每秒把"为什么还要画"的各位标志交给注册方（引擎写 probe_trace）。
/// cui 自己不能落文件、真机 stdout 也看不到，所以走这个 sink（LANLU_PROBE_IDLE=1 时接上）。
public var renderDiagHook: ?(String) -> Unit = None

/// 最近一次渲染决策的各位标志（每 120 帧刷新）。引擎的帧钩子直接读它写 probe_trace ——
/// 跨包给函数类型 var 赋值在真机上不可靠（实测钩子没被调用），纯字符串最稳。
public var lastRenderDiag: String = ""
private var frameProbeSeq: Int64 = 0

public class DesktopApp {
    private let window: SdlWindow
    private let ctx: UiContext
    private let frameDelay: UInt32
    /**
     * Called once per loop iteration on the UI thread, BEFORE the render decision,
     * whether or not a frame ends up being drawn. Use it to pump background results
     * into State: writes bump the state generation, which the dirty-frame skipping
     * below already treats as a reason to render. Unlike a per-frame FrameHandler
     * (which must call requestFrame to keep firing and therefore forces a full
     * rebuild + draw + present at 60fps), an onTick that changes nothing leaves the
     * loop idle and costs nothing.
     */
    public var onTick: () -> Unit = { => }
    /**
     * 可选：每帧在所有 overlay 绘制完成后调用，用于全局过渡动画
     *（如主题切换涟漪），保证绘制在最顶层。
     */
    public var postOverlayDraw: ?(UiContext) -> Unit = None
    private let resources = ArrayList<Resource>()
    private let stateStore = StateStore()
    private let snapshotPath: ?String
    // Per-phase frame timing, enabled with `--profile`; None (and zero cost) in a normal run.
    // 保留字段以便将来按需关闭；当前无条件限频输出（60 帧一次），否则定位不了空转渲染
    private let idleProbe: Bool = getVariable("LANLU_PROBE_IDLE") != Some("0")
    private let profiler: ?FrameProfiler
    private var frames: UInt64 = 0
    // 帧率叠层（LANLU_FPS=1；对齐 horizon perf_overlay）：present 之后打点，
    // 统计真实上屏节拍而不是"提交了多少帧"。
    private let fpsMeter: FpsMeter = FpsMeter()
    private let fpsOverlay: Bool = getVariable("LANLU_FPS") == Some("1")
    private var lastCpuNs: UInt64 = 0
    private var baseCursor: ?Cursor = None
    private var pointerCursor: ?Cursor = None
    private var textCursor: ?Cursor = None
    private var resizeHCursor: ?Cursor = None
    private var resizeVCursor: ?Cursor = None
    private var appliedShape: ?CursorShape = None
    // The caret rectangle last forwarded to the OS for IME anchoring (logical pixels).
    private var appliedInputAnchor: ?Rect = None

    /**
     * The widget tree from the most recent frame. Read-only for snapshot/offscreen use;
     * re-built every frame by the run loop so valid only for the current frame.
     */
    public var lastWidget: ?Widget = None

    public init(
        spec: WindowSpec,
        theme!: Theme = Theme.light(),
        frameDelay!: UInt32 = UInt32(16),
        fontScale!: Float32 = 1.0,
        fontPath!: ?String = None,
        metadata!: ?AppMetadata = None,
        hints!: Array<SdlHintSetting> = [],
    ) {
        // P5：CN_WINDOW=lgpu 时不建 SDL 窗口，改由 L 层窗口 + lgpu 后端承担
        let useLWindow = (getVariable("CN_WINDOW") ?? "sdl") == "lgpu"
        this.window = if (useLWindow) {
            SdlWindow.headless(spec)
        } else {
            configuredWindow(spec, metadata, hints)
        }
        this.ctx = UiContext(window.renderer, theme)
        this.ctx.displayScale = window.scale
        this.ctx.fontScale = max(0.1, fontScale)
        this.frameDelay = frameDelay
        this.snapshotPath = snapshotArgument()
        this.profiler = if (profileEnabled()) {
            Some(FrameProfiler(60))
        } else {
            None
        }
    }

    /// 让整棵 UI 树改用替代绘制后端（P4 迁移/对照用）。传 None 恢复 SDL。
    public func useCanvasBackend(canvas: ?Canvas): Unit {
        ctx.renderer.useBackend(canvas)
    }

    /// 联调探针：从文件加载一张图片纹理（触发"lcodec 解码 → 后端纹理上传"整条链路）。
    /// 返回纹理 id（>0 成功），失败返回 0。诊断结论写 $HOME/probe_read.txt。
    public func probeLoadPngTexture(path: String): Int64 {
        let report = {status: String =>
            let home = getVariable("HOME") ?? "."
            try {
                File.writeTo(Path(home + "/probe_read.txt"), status.toArray())
            } catch (_) {}
        }
        try {
            let tex = ctx.renderer.loadTexture(path)
            report("ok id=" + tex.id.toString() + " (" + Int32(tex.width).toString() + "x" +
                Int32(tex.height).toString() + ")")
            tex.id
        } catch (e: Exception) {
            report("texture failed: " + e.toString())
            0
        }
    }

    /// 联调探针：用内存里的图片字节创建纹理（验证字节解码入口与后端纹理上传链路）。
    public func probeLoadPngBytes(bytes: Array<UInt8>): Int64 {
        try {
            ctx.renderer.loadTextureFromBytes(bytes).id
        } catch (_: Exception) {
            0
        }
    }

    /// 当前是否使用替代后端。
    public func canvasBackendActive(): Bool {
        ctx.renderer.backendActive()
    }
    public func manage(resource: Resource): Unit {
        resources.add(resource)
    }

    /**
     * Prevents the user from shrinking the window below `width` x `height` logical
     * pixels. Layouts do not reflow below their design minimum, so resizable windows
     * should set one to keep content from being squeezed off screen.
     */
    public func setMinimumSize(width: Int32, height: Int32): Unit {
        window.setMinimumSize(width, height)
    }

    /**
     * The window this app is running in, exposed for shell-level window management that
     * widgets cannot reach through `UiContext`: dropping the OS frame (`setBordered`),
     * registering a custom title bar's drag region (`setDragRegion`), and
     * minimizing/maximizing from custom window controls. Prefer the dedicated methods
     * above when one fits.
     */
    public prop sdlWindow: SdlWindow {
        get() {
            window
        }
    }

    /**
     * Sets the window's resting cursor — the shape shown wherever no control asks for a
     * different one. Applications wanting a themed base pointer (for example a crosshair
     * over a drawing canvas) call this instead of activating a cursor directly, so the
     * hover-driven shapes (a hand over buttons, an I-beam over text) still layer on top.
     */
    public func useBaseCursor(kind: SystemCursor): Unit {
        match (baseCursor) {
            case Some(existing) => existing.close()
            case None => ()
        }
        baseCursor = createCursor(kind)
        appliedShape = None
        applyDesiredCursor()
    }

    /** Drops all local values created by `rememberState` before the next rebuild. */
    public func clearRememberedState(): Unit {
        stateStore.clear()
    }

    /**
     * Swaps the active theme at runtime and requests a repaint. The next frame is drawn
     * with the new theme even if no input or widget state change would otherwise wake
     * the loop (the dirty-frame skipping in `run` honours `requestFrame`).
     */
    public func setTheme(theme: Theme): Unit {
        ctx.theme = theme
        ctx.requestFrame()
    }

    public func openFileDialog(options!: FileDialogOptions = FileDialogOptions()): FileDialogRequest {
        FileDialogs.openFile(options: options, window: Some(window))
    }

    public func saveFileDialog(options!: FileDialogOptions = FileDialogOptions()): FileDialogRequest {
        FileDialogs.saveFile(options: options, window: Some(window))
    }

    public func openFolderDialog(options!: FileDialogOptions = FileDialogOptions()): FileDialogRequest {
        FileDialogs.openFolder(options: options, window: Some(window))
    }

    public func run(body: () -> Unit): Unit {
        // The finally block keeps shutdown deterministic even when a widget throws out of
        // the frame loop: managed resources close in reverse order, then the window.
        try {
            match (profiler) {
                case Some(_) =>
                    println("[profile] 渲染后端 ${ctx.renderer.driverName()}｜超采样 ${ctx.renderer.supersampleFactor()}x｜视口 ${window.width}x${window.height} @ ${window.scale}x")
                case None => ()
            }
            var previousTick = window.ticks()
            // Dirty-frame skipping (档 0): a frame is built, laid out, and drawn only when something can
            // have changed — the first frame, pending input, a state write since the last render, a
            // resize, an expired timed-frame deadline, or a continuous-frame request (a running
            // animation, a per-frame FrameHandler). Otherwise the loop blocks in idle wait
            // until input arrives, requestWake() pushes a user event (worker/SSE completion), or the
            // next timed deadline (caret blink, tooltip reveal, app timer) expires — an idle window
            // costs no CPU at all. State is snapshotted at the TOP of each rendered frame, so a write
            // made during that frame's layout/dispatch/draw reliably triggers the reflecting render next.
            var lastRenderedGen = currentStateGeneration()
            var continuousRequested = true // force the first frame
            // Earliest pending timed-frame deadline on the frame clock; refreshed from the widgets'
            // requestFrameAfter registrations each rendered frame, merged with onTick registrations
            // while idle.
            var nextTimedFrameMs: ?UInt64 = None
            var renderedWidth: Int32 = -1
            var renderedHeight: Int32 = -1
            // Snapshot capture and the profiler need every frame, so only a plain run may block.
            let mayIdleWait = snapshotPath.isNone() && profiler.isNone()
            // 空闲循环阻塞在事件等待上：后台线程写 State 时靠这个出口唤醒
            stateWakeSink = { => requestWake() }
            while (!ctx.shouldClose) {
                let iterationStartMs = window.ticks()
                var timedDue = isDeadlineDue(nextTimedFrameMs, iterationStartMs)
                // Idle path: nothing animates and no deadline has expired, so block on the event
                // queue. The wait returns on input, on a requestWake() user event, or when the next
                // timed deadline expires (idle wait's timeout).
                var waitedEvent: ?UiEvent = None
                if (mayIdleWait && !continuousRequested && !timedDue) {
                    waitedEvent = window.waitEventTimeout(idleWaitTimeoutMs(nextTimedFrameMs, iterationStartMs))
                    // The deadline may have expired while blocked: recompute against the
                    // post-wait clock, otherwise a due timed frame is only picked up next
                    // iteration and renders systematically one frame period (~16ms) late.
                    timedDue = isDeadlineDue(nextTimedFrameMs, window.ticks())
                }
                let frame = nextFrame(previousTick)
                previousTick = frame.elapsedMs
                ctx.frame = frame
                let viewportW = window.width
                let viewportH = window.height
                ctx.viewportWidth = Float32(viewportW)
                ctx.viewportHeight = Float32(viewportH)

                onTick()
                let events = coalesceMoves(collectPendingEvents(waitedEvent))
                let stateGen = currentStateGeneration()
                let mustRender = continuousRequested || timedDue || !events.isEmpty() || stateGen != lastRenderedGen ||
                    viewportW != renderedWidth || viewportH != renderedHeight || snapshotPath.isSome() ||
                    profiler.isSome()
                // 空闲功耗诊断（LANLU_PROBE_IDLE=1）：每秒打一次"为什么还要画"的各位标志，
                // 用来定位"空闲仍 60fps"（附录 C 基线是 0）到底是谁在请求帧。
                if (mustRender && frames % 120 == 0) {
                    let line = "continuous=" + continuousRequested.toString() + " timed=" + timedDue.toString() +
                        " events=" + events.size.toString() + " stateGen=" + (stateGen != lastRenderedGen).toString() +
                        " viewport=" + (viewportW != renderedWidth || viewportH != renderedHeight).toString() +
                        " snapshot=" + snapshotPath.isSome().toString() + " profiler=" + profiler.isSome().toString() +
                        " writes=" + stateWriteCount.toString() + " ids=" + recentStateWriteIds[0].toString() +
                        "," + recentStateWriteIds[1].toString() + "," + recentStateWriteIds[2].toString() +
                        "," + recentStateWriteIds[3].toString() + " names=[" + recentStateWriteNames[0] +
                        "|" + recentStateWriteNames[1] + "|" + recentStateWriteNames[2] + "|" +
                        recentStateWriteNames[3] + "]"
                    lastRenderDiag = line
                    match (renderDiagHook) {
                        case Some(h) => h("idle " + line)
                        case None => ()
                    }
                }

                var rendered = false
                if (mustRender) {
                    let tBuild = FrameProfiler.now()
                    let widget = buildRoot(body, stateStore)
                    lastWidget = Some(widget)
                    let tLayout = FrameProfiler.now()
                    ctx.adoptFocusRing(stateStore.focusRing())
                    widget.layout(ctx, Rect(0.0, 0.0, Float32(viewportW), Float32(viewportH)))
                    let tEvents = FrameProfiler.now()
                    dispatchCollectedEvents(widget, events)
                    dispatchEvent(widget, UiEvent.Frame(frame))
                    let tDraw = FrameProfiler.now()
                    frames += 1
                    lastCpuNs = FrameProfiler.now() - tBuild
                    let (beginNs, treeNs, resolveNs, presentNs) = draw(widget)
                    fpsMeter.record(FrameProfiler.now(), lastCpuNs + beginNs + treeNs + resolveNs, presentNs)
                    lastRenderedGen = stateGen
                    continuousRequested = ctx.takeFrameRequest()
                    // Widgets re-register their deadlines during this frame's draw, replacing the
                    // (possibly just expired) previous one.
                    nextTimedFrameMs = ctx.takeTimedFrameRequest()
                    renderedWidth = viewportW
                    renderedHeight = viewportH
                    rendered = true
                    match (profiler) {
                        case Some(p) => p.record(tLayout - tBuild, tEvents - tLayout, tDraw - tEvents, beginNs, treeNs,
                            resolveNs, presentNs)
                        case None => ()
                    }
                } else {
                    continuousRequested = ctx.takeFrameRequest()
                    // No draw this iteration, but onTick (application timers) may have registered
                    // a deadline; keep the earliest pending one.
                    nextTimedFrameMs = earliestDeadline(nextTimedFrameMs, ctx.takeTimedFrameRequest())
                }
                paceFrame(iterationStartMs, rendered)
            }
        } finally {
            closeManagedResources()
            window.close()
        }
    }

    /**
     * Wakes the run loop from any thread. While idle the loop blocks in idle wait;
     * this queues an SDL user event so the wait returns immediately and the next iteration runs
     * onTick (pumping worker results into State) instead of sleeping until the next input event
     * or timed deadline. Cheap to call liberally: a burst queues a few extra user events, each
     * costing one no-render iteration.
     */
    public func requestWake(): Unit {
        window.pushWakeEvent()
    }

    /**
     * Registers a timed frame request from application code — the loop renders a frame when the
     * deadline expires even if no input arrives. This is the onTick-facing twin of
     * UiContext.requestFrameAfter, for app-level timers (auto-hide, auto-play, debounce flushes)
     * that must fire while the window is otherwise idle. Call it from onTick (the UI thread).
     */
    public func requestFrameAfter(delayMs: UInt64): Unit {
        ctx.requestFrameAfter(delayMs)
    }

    // Polls every event SDL has queued into a buffer, so the render decision can tell whether any input
    // arrived before deciding whether to build a frame at all. Dispatch is deferred (see below). An
    // event already dequeued by the idle wait (`waitEventTimeout`) is prepended to keep arrival order.
    private func collectPendingEvents(waitedEvent: ?UiEvent): ArrayList<UiEvent> {
        let events = ArrayList<UiEvent>()
        match (waitedEvent) {
            case Some(event) => events.add(event)
            case None => ()
        }
        var current = window.pollEvent()
        while (let Some(event) <- current) {
            events.add(event)
            current = window.pollEvent()
        }
        events
    }

    /*
     * Frame pacing (#1). With vsync the present is already the throttle — sleeping a fixed
     * frameDelay after it would double the frame period and pin continuous animation at ~30fps —
     * so a rendered frame sleeps nothing. Without vsync the iteration is padded to frameDelay
     * measured from its start, never below zero, so the loop neither free-runs nor drifts into a
     * "work + delay" period. An iteration that rendered nothing has no present to throttle it
     * (snapshot/profile modes skip the idle wait), so it falls back to the fixed delay.
     */
    private func paceFrame(iterationStartMs: UInt64, rendered: Bool): Unit {
        if (window.vsync) {
            if (!rendered) {
                window.delay(frameDelay)
            }
            return
        }
        let elapsedMs = tickDelta(iterationStartMs, window.ticks())
        if (elapsedMs < UInt64(frameDelay)) {
            window.delay(frameDelay - UInt32(elapsedMs))
        }
    }

    /*
     * 合并连续的指针移动（评审 P1）。鼠标/触控板以 120Hz+ 产生 motion，一帧内常有十几条；
     * 每条都要对整棵树做一次命中测试 + 悬停结算，而只有最后一条的位置会被画出来。
     * 只合并**相邻**的 MouseMove：按下/抬起/滚轮/键盘之间的移动保持原样，
     * 拖拽、点击计数等依赖顺序的语义不变（按钮事件自带坐标）。
     */
    private func coalesceMoves(events: ArrayList<UiEvent>): ArrayList<UiEvent> {
        if (events.size < 2) {
            return events
        }
        let out = ArrayList<UiEvent>()
        var i = 0
        while (i < events.size) {
            let ev = events[i]
            match (ev) {
                case UiEvent.MouseMove(_, _) =>
                    let isLastMove = i + 1 >= events.size || (match (events[i + 1]) {
                        case UiEvent.MouseMove(_, _) => false
                        case _ => true
                    })
                    if (isLastMove) {
                        out.add(ev)
                    }
                case _ => out.add(ev)
            }
            i++
        }
        out
    }

    // 帧率叠层：右上角 fps / 帧间隔 / CPU / present 阻塞（ms），在所有浮层之上、endScene 之前绘制。
    private func drawFpsOverlay(): Unit {
        let r = fpsMeter.reading()
        let lines = [
            "${r.fps} fps  min ${r.minFps}  1%low ${r.lowFps}",
            "frame ${fmtMs(r.frameMs)}  max ${fmtMs(r.maxFrameMs)} ms",
            "cpu ${fmtMs(r.cpuMs)}  present ${fmtMs(r.presentMs)} ms"
        ]
        let pt: Float32 = 12.0
        var w: Float32 = 0.0
        for (l in lines) {
            w = max(w, ctx.renderer.textWidth(l, pointSize: pt))
        }
        let lh = ctx.renderer.textHeight(pointSize: pt)
        let pad: Float32 = 6.0
        let bw = w + pad * 2.0
        let bh = lh * Float32(lines.size) + pad * 2.0
        let x = Float32(window.width) - bw - 8.0
        let y: Float32 = 48.0
        ctx.renderer.fillRoundedRect(Rect(x, y, bw, bh), 4.0, Color(0, 0, 0, 160))
        var ly = y + pad
        var idx = 0
        for (l in lines) {
            let c = if (idx == 0) { fpsColor(r.fps) } else { Color(220, 220, 220, 255) }
            ctx.renderer.text(l, x + pad, ly, c, pointSize: pt)
            ly += lh
            idx++
        }
    }

    // Dispatches the collected events in arrival order against the freshly built tree, bracketing each
    // with the same pointer bookkeeping the loop used to do inline — the per-event sequence
    // (prepare, route, complete) is unchanged, only deferred past the render decision.
    private func dispatchCollectedEvents(widget: Widget, events: ArrayList<UiEvent>): Unit {
        for (event in events) {
            preparePointer(event)
            routeEvent(widget, event)
            completePointer(event)
        }
    }

    /*
     * Routes one input event. Window-level events belong to the shell and are handled
     * before the overlays, so a modal dialog can neither swallow a quit request nor keep
     * the logical size stale through a resize. The open overlays (dropdowns, menus,
     * dialogs) then see the event before the tree, top-most first — a click inside a
     * popup is not stolen by the dialog or control drawn underneath it, and a dialog
     * consumes whatever its popups decline, protecting the backdrop tree. Pointer
     * bookkeeping brackets BOTH paths: click counting and hover resolution run for
     * overlay-hosted controls (a Modal's fields) exactly as for tree controls, keeping
     * double-clicks and cursor shapes alive there.
     */
    private func routeEvent(widget: Widget, event: UiEvent): Unit {
        match (event) {
            case UiEvent.Quit => ctx.requestClose()
            case UiEvent.WindowResized(w, h) =>
                window.width = Int32(Float32(w) / window.scale)
                window.height = Int32(Float32(h) / window.scale)
                // 本帧已按旧尺寸 build/layout（视口在事件分发前读取），必须再渲一帧按新尺寸
                // 重排：否则下一循环直接进入 idle 等待，UI 会一直停留在旧布局（被新渲染
                // 视口裁剪/留白），直到某个无关输入事件碰巧唤醒。
                ctx.requestFrame()
            case UiEvent.MouseMove(_, _) =>
                // Resolve which control the pointer is over, then reflect its requested
                // shape in the system cursor. Bracketing keeps hover single-winner.
                ctx.beginHoverTest()
                if (!ctx.dispatchOverlay(event)) {
                    dispatchEvent(widget, event)
                }
                ctx.settleHover()
                applyDesiredCursor()
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                // Click counting runs before any dispatch so controls can read it while
                // handling the press, wherever the press lands.
                ctx.recordPress(x, y)
                if (ctx.dispatchOverlay(event)) {
                    return // popups and dialogs manage focus themselves
                }
                // A primary press in the tree either moves focus to the claiming control
                // or blurs the current one, matching desktop conventions.
                ctx.beginPointerPress()
                dispatchEvent(widget, event)
                ctx.settleFocusAfterPress()
            case UiEvent.KeyDown(Key.Tab, _) =>
                if (ctx.dispatchOverlay(event)) {
                    return
                }
                // Tab traversal is a shell responsibility: it walks the build-order
                // focus ring and is not forwarded to the focused control, so a text
                // field cannot swallow it. Shift reverses direction.
                if (Keyboard.modifiers().shift) {
                    ctx.focusPrevious()
                } else {
                    ctx.focusNext()
                }
            case _ =>
                if (!ctx.dispatchOverlay(event)) {
                    dispatchEvent(widget, event)
                }
        }
    }

    // Draws one frame, returning the nanosecond durations of its sub-phases (scene begin, tree draw,
    // supersample resolve, present) for the profiler. The timestamps are a handful of clock reads —
    // negligible against a frame — so they run unconditionally and only the profiler, when enabled,
    // records them.
    private func draw(widget: Widget): (UInt64, UInt64, UInt64, UInt64) {
        let t0 = FrameProfiler.now()
        ctx.renderer.beginScene(Float32(window.width), Float32(window.height), ctx.theme.bg)
        let t1 = FrameProfiler.now()
        // Cleared before the tree so only a control hovered this frame shows a tooltip; the
        // tree registers into the slot during draw, and the overlay is painted last, on top.
        ctx.clearTooltip()
        // Cleared before the tree so a closed popup leaves no overlay; each open control
        // re-registers during draw, and the stack is painted last, above the tree —
        // bottom-up, so a popup opened inside a dialog paints above the dialog.
        ctx.clearActiveOverlay()
        // Cleared before the tree so only this frame's focused caret (re-reported during
        // draw, including inside dialog overlays) anchors the IME candidate window.
        ctx.clearTextInputAnchor()
        // 容错：单个 widget 的绘制异常不应该让整个应用终止（真机曾因一次 lgpu 异常整进程 abort）。
        // 记录到 $HOME/draw_error.txt 便于定位，然后继续本帧其余绘制。
        try {
            widget.draw(ctx)
        } catch (e: Exception) {
            let home = getVariable("HOME") ?? "."
            try {
                File.writeTo(Path(home + "/draw_error.txt"), (e.toString() + "\n").toArray())
            } catch (_) {}
        }
        // Tooltips yield to an open popup or dialog — standard desktop behaviour, and it
        // stops a background control's bubble from ghosting through the modal backdrop.
        if (!ctx.hasOverlay()) {
            drawTooltip(ctx, Float32(window.width), Float32(window.height))
        }
        // 层断点（lgpu 后端）：浮层（Modal/Drawer/菜单/Toast）在树绘制结束后才注册并绘制，
        // 而后端"每段先矩形后纹理"的合批顺序会把浮层里的全屏纹理（模糊遮罩/背景快照）排到
        // 树的矩形下面 —— 真机表现为"弹窗没有遮罩背景"。断点让此后录制的浮层图元整体
        // 画在树内容之上；SDL/无后端路径该调用是空操作，无行为变化。
        ctx.renderer.layerMark()
        ctx.drawActiveOverlay()
        applyTextInputAnchor()
        // 后覆盖层绘制（在全部 overlay 之上，用于主题涟漪等全局过渡动画）
        ctx.renderer.clearClipStack()
        // ThemeRipple 自身的 discardRecorded/texture/layerMark 依赖"断点前录制"的语义：
        // discard 清空全部录制并连带清空断点，随后快照纹理+辉光环重新落段（见 theme_ripple.cj）。
        match (postOverlayDraw) {
            case Some(drawFn) => drawFn(ctx)
            case None => ()
        }
        if (fpsOverlay) {
            ctx.renderer.clearClipStack()
            drawFpsOverlay()
        }
        let t2 = FrameProfiler.now()
        ctx.renderer.endScene()
        let t3 = FrameProfiler.now()
        maybeSnapshot()
        // 联调钩子：渲染循环内执行（spawn/定时器在该运行时里不保证被调度）
        frameProbeSeq++
        match (frameProbeHook) {
            case Some(hook) =>
                hook(frameProbeSeq)
            case None => ()
        }
        ctx.renderer.present()
        let t4 = FrameProfiler.now()
        (t1 - t0, t2 - t1, t3 - t2, t4 - t3)
    }

    /*
     * Forwards the focused caret rectangle to the OS whenever it moves, so the IME
     * composition UI (candidate window) follows typing instead of sitting in a screen
     * corner. Unchanged rectangles are skipped to avoid a per-frame system call, and a
     * platform refusal is ignored — IME anchoring is polish, not frame-critical.
     */
    private func applyTextInputAnchor(): Unit {
        // 暴露给平台层：平台层据此决定光标形状（悬停在文本框上给 I 形）
        lastTextInputRect = ctx.textInputAnchorRect()
        debugFocusId = ctx.focusId
        match (ctx.textInputAnchorRect()) {
            case Some(anchor) =>
                if (!sameAnchorRect(appliedInputAnchor, anchor)) {
                    appliedInputAnchor = Some(anchor)
                    try {
                        window.setTextInputArea(anchor)
                    } catch (_: Exception) {
                        ()
                    }
                }
            case None => ()
        }
    }

    // Snapshot mode: `main.exe --snapshot <path.bmp>` renders a few frames so the UI
    // settles, writes the frame to a BMP, then quits. Handy for visual tests and docs.
    private func maybeSnapshot(): Unit {
        match (snapshotPath) {
            case Some(path) where frames >= SNAPSHOT_SETTLE_FRAMES =>
                ctx.renderer.captureBmp(path)
                ctx.requestClose()
            case _ => ()
        }
    }

    private func dispatchEvent(widget: Widget, event: UiEvent): Unit {
        let _ = widget.handle(ctx, event)
    }

    // Applies the hovered control's requested shape, skipping the SDL call when it is
    // already active. Cursor feedback is non-critical polish: a platform that refuses a
    // shape simply keeps the current cursor rather than failing the frame.
    private func applyDesiredCursor(): Unit {
        let shape = ctx.desiredCursor()
        match (appliedShape) {
            case Some(current) where current == shape => return
            case _ => ()
        }
        appliedShape = Some(shape)
        match (cursorForShape(shape)) {
            case Some(cursor) => try {
                cursor.setActive()
            } catch (_: Exception) {
                ()
            }
            case None => ()
        }
    }

    private func cursorForShape(shape: CursorShape): ?Cursor {
        match (shape) {
            case CursorShape.Default => ensureCursor(SystemCursor.Default)
            case CursorShape.Interactive => ensurePointerCursor()
            case CursorShape.Text => ensureTextCursor()
            case CursorShape.ResizeH => ensureResizeHCursor()
            case CursorShape.ResizeV => ensureResizeVCursor()
        }
    }

    private func ensureCursor(kind: SystemCursor): ?Cursor {
        match (baseCursor) {
            case Some(cursor) => Some(cursor)
            case None =>
                baseCursor = createCursor(kind)
                baseCursor
        }
    }

    private func ensurePointerCursor(): ?Cursor {
        match (pointerCursor) {
            case Some(cursor) => Some(cursor)
            case None =>
                pointerCursor = createCursor(SystemCursor.Pointer)
                pointerCursor
        }
    }

    private func ensureTextCursor(): ?Cursor {
        match (textCursor) {
            case Some(cursor) => Some(cursor)
            case None =>
                textCursor = createCursor(SystemCursor.Text)
                textCursor
        }
    }

    private func ensureResizeHCursor(): ?Cursor {
        match (resizeHCursor) {
            case Some(cursor) => Some(cursor)
            case None =>
                resizeHCursor = createCursor(SystemCursor.EwResize)
                resizeHCursor
        }
    }

    private func ensureResizeVCursor(): ?Cursor {
        match (resizeVCursor) {
            case Some(cursor) => Some(cursor)
            case None =>
                resizeVCursor = createCursor(SystemCursor.NsResize)
                resizeVCursor
        }
    }

    private func createCursor(kind: SystemCursor): ?Cursor {
        try {
            let cursor = Cursor.system(kind)
            resources.add(cursor)
            Some(cursor)
        } catch (_: Exception) {
            None
        }
    }

    private func nextFrame(previousTick: UInt64): FrameInfo {
        let currentTick = window.ticks()
        FrameInfo(currentTick, tickDelta(previousTick, currentTick))
    }

    private func preparePointer(event: UiEvent): Unit {
        match (event) {
            case UiEvent.MouseMove(x, y) => rememberMouse(x, y)
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                rememberMouse(x, y)
                ctx.leftMouseDown = true
            case UiEvent.MouseUp(MouseButton.Left, x, y) => rememberMouse(x, y)
            case UiEvent.DropFile(_, x, y) => rememberMouse(x, y)
            case UiEvent.DropText(_, x, y) => rememberMouse(x, y)
            case UiEvent.DropPosition(x, y) => rememberMouse(x, y)
            case _ => ()
        }
    }

    private func completePointer(event: UiEvent): Unit {
        match (event) {
            case UiEvent.MouseUp(MouseButton.Left, _, _) =>
                ctx.leftMouseDown = false
                ctx.clearDrag()
                ctx.clearPress()
            case _ => ()
        }
    }

    private func rememberMouse(x: Float32, y: Float32): Unit {
        ctx.mouseX = x
        ctx.mouseY = y
    }

    private func closeManagedResources(): Unit {
        var i = resources.size - 1
        while (i >= 0) {
            resources[i].close()
            i -= 1
        }
    }
}

private func sameAnchorRect(applied: ?Rect, next: Rect): Bool {
    match (applied) {
        case Some(rect) => rect.x == next.x && rect.y == next.y && rect.w == next.w && rect.h == next.h
        case None => false
    }
}

internal func tickDelta(previousTick: UInt64, currentTick: UInt64): UInt64 {
    if (currentTick >= previousTick) {
        currentTick - previousTick
    } else {
        UInt64(0)
    }
}

/* True when a timed-frame deadline exists and has been reached. */
internal func isDeadlineDue(deadline: ?UInt64, nowMs: UInt64): Bool {
    match (deadline) {
        case Some(d) => nowMs >= d
        case None => false
    }
}

/*
 * The timeout handed to idle wait on the idle path: exactly the distance to the
 * next timed-frame deadline, clamped to Int32. With no deadline the loop waits (practically)
 * forever — input and requestWake() user events are the only wake sources. Int32.Max is ~24.8
 * days; a spurious wake that far out would simply re-enter the wait.
 */
internal func idleWaitTimeoutMs(deadline: ?UInt64, nowMs: UInt64): Int32 {
    match (deadline) {
        case Some(d) =>
            if (d <= nowMs) {
                return Int32(0)
            }
            let remaining = d - nowMs
            if (remaining >= UInt64(Int32.Max)) {
                Int32.Max
            } else {
                Int32(remaining)
            }
        case None =>
            // 兜底上限 1s：没有待办期限时不要一睡就是 24.8 天。万一某条唤醒链路漏了
            // （输入/后台状态/定时器），最多晚 1s 处理，而不是整个界面"卡死"。
            // 代价是空闲时每秒一次空唤醒（不渲染，mustRender 仍为 false）。
            Int32(1000)
    }
}

/* Keeps the earlier of two optional deadlines, either side possibly absent. */
internal func earliestDeadline(a: ?UInt64, b: ?UInt64): ?UInt64 {
    match ((a, b)) {
        case (Some(x), Some(y)) => Some(min(x, y))
        case (Some(x), None) => Some(x)
        case (None, Some(y)) => Some(y)
        case (None, None) => None
    }
}

private func snapshotArgument(): ?String {
    let args = getCommandLine()
    var i = 0
    while (i < args.size - 1) {
        if (args[i] == "--snapshot") {
            return Some(args[i + 1])
        }
        i += 1
    }
    None
}

// True when `--profile` is on the command line, turning on per-phase frame timing.
private func profileEnabled(): Bool {
    for (arg in getCommandLine()) {
        if (arg == "--profile") {
            return true
        }
    }
    false
}

private func configuredWindow(spec: WindowSpec, metadata: ?AppMetadata, hints: Array<SdlHintSetting>): SdlWindow {
    match (metadata) {
        case Some(value) => ApplicationMetadata.apply(value)
        case None => ()
    }
    SdlHints.apply(hints)
    SdlWindow(spec)
}

/* ── 帧率统计（对齐 horizon extras.rs FpsCounter + perf_overlay.rs）──────────────
 * fps    = 最近 1 秒内上屏的帧数；
 * min    = 最近 5 秒内每秒帧数的最小值（按 1s 桶）；
 * 1%low  = 最近 5 秒最慢 1% 帧间隔对应的 fps；
 * frame  = 相邻两次 present 结束的平均间隔；cpu = build+layout+draw+提交；
 * present= present 调用阻塞时长（FIFO 下≈等 vsync，可区分"CPU 忙"与"在等屏"）。
 * 读数每 0.5s 刷新一次，避免数字抖动。空闲（零渲染）时读数保持最后一次的值。 */
public struct FpsReading {
    public let fps: Int64
    public let minFps: Int64
    public let lowFps: Int64
    public let frameMs: Float64
    public let maxFrameMs: Float64
    public let cpuMs: Float64
    public let presentMs: Float64

    public init(fps: Int64, minFps: Int64, lowFps: Int64, frameMs: Float64, maxFrameMs: Float64,
        cpuMs: Float64, presentMs: Float64) {
        this.fps = fps
        this.minFps = minFps
        this.lowFps = lowFps
        this.frameMs = frameMs
        this.maxFrameMs = maxFrameMs
        this.cpuMs = cpuMs
        this.presentMs = presentMs
    }
}

let FPS_WINDOW_NS: UInt64 = 5_000_000_000
let FPS_REFRESH_NS: UInt64 = 500_000_000
let NS_PER_SEC: UInt64 = 1_000_000_000

public class FpsMeter {
    // (present 结束时间, 帧间隔, cpu, present)，单位 ns，最旧在前
    private let ends = ArrayList<UInt64>()
    private let gaps = ArrayList<UInt64>()
    private let cpus = ArrayList<UInt64>()
    private let presents = ArrayList<UInt64>()
    private var head: Int64 = 0
    private var lastEnd: UInt64 = 0
    private var computedAt: UInt64 = 0
    private var shown: FpsReading = FpsReading(0, 0, 0, 0.0, 0.0, 0.0, 0.0)

    public init() {}

    public func record(nowNs: UInt64, cpuNs: UInt64, presentNs: UInt64): Unit {
        let gap = if (lastEnd == 0 || nowNs < lastEnd) { UInt64(0) } else { nowNs - lastEnd }
        lastEnd = nowNs
        ends.add(nowNs)
        gaps.add(gap)
        cpus.add(cpuNs)
        presents.add(presentNs)
        while (head < ends.size && nowNs - ends[head] > FPS_WINDOW_NS) {
            head++
        }
        // 游标前的死元素过多时整体压缩一次（摊还 O(1)）
        if (head > 512 && head * 2 > ends.size) {
            compact()
        }
        if (nowNs - computedAt >= FPS_REFRESH_NS) {
            computedAt = nowNs
            shown = compute(nowNs)
        }
    }

    public func reading(): FpsReading {
        shown
    }

    private func compact(): Unit {
        let n = ends.size - head
        let e = ArrayList<UInt64>()
        let g = ArrayList<UInt64>()
        let c = ArrayList<UInt64>()
        let p = ArrayList<UInt64>()
        for (i in head..ends.size) {
            e.add(ends[i])
            g.add(gaps[i])
            c.add(cpus[i])
            p.add(presents[i])
        }
        ends.clear()
        gaps.clear()
        cpus.clear()
        presents.clear()
        for (i in 0..n) {
            ends.add(e[i])
            gaps.add(g[i])
            cpus.add(c[i])
            presents.add(p[i])
        }
        head = 0
    }

    private func compute(nowNs: UInt64): FpsReading {
        var fps: Int64 = 0
        var sumGap: UInt64 = 0
        var nGap: Int64 = 0
        var maxGap: UInt64 = 0
        var sumCpu: UInt64 = 0
        var sumPresent: UInt64 = 0
        var nRecent: Int64 = 0
        let buckets = Array<Int64>(5, repeat: 0)
        let sorted = ArrayList<UInt64>()
        for (i in head..ends.size) {
            let age = nowNs - ends[i]
            let b = Int64(age / NS_PER_SEC)
            if (b < 5) {
                buckets[b] += 1
            }
            if (age < NS_PER_SEC) {
                fps++
                sumCpu += cpus[i]
                sumPresent += presents[i]
                nRecent++
                // 间隔只统计连续渲染中的帧：>250ms 视为从空闲恢复，不计入帧时间
                let g = gaps[i]
                if (g > 0 && g < 250_000_000) {
                    sumGap += g
                    nGap++
                    if (g > maxGap) {
                        maxGap = g
                    }
                }
            }
            let g5 = gaps[i]
            if (g5 > 0 && g5 < 250_000_000) {
                sorted.add(g5)
            }
        }
        // 只有窗口内已覆盖的完整秒桶参与 min（启动/刚从空闲恢复时不把空桶算成 0）
        var minFps = fps
        let span = if (head < ends.size) { nowNs - ends[head] } else { UInt64(0) }
        let fullBuckets = Int64(span / NS_PER_SEC)
        for (b in 1..min(fullBuckets + 1, 5)) {
            if (buckets[b] < minFps) {
                minFps = buckets[b]
            }
        }
        var lowFps = fps
        if (sorted.size > 0) {
            let arr = sorted.toArray()
            sort(arr)
            // 最慢 1% 的平均间隔
            let k = max(1, arr.size / 100)
            var sum: UInt64 = 0
            for (i in (arr.size - k)..arr.size) {
                sum += arr[i]
            }
            let avg = sum / UInt64(k)
            if (avg > 0) {
                lowFps = Int64(NS_PER_SEC / avg)
            }
        }
        let toMs = {ns: UInt64, n: Int64 => if (n > 0) { Float64(ns) / Float64(n) / 1.0e6 } else { 0.0 }}
        FpsReading(fps, minFps, lowFps, toMs(sumGap, nGap), Float64(maxGap) / 1.0e6,
            toMs(sumCpu, nRecent), toMs(sumPresent, nRecent))
    }
}

func fmtMs(v: Float64): String {
    let tenths = Int64(v * 10.0 + 0.5)
    "${tenths / 10}.${tenths % 10}"
}

// 60 档绿、30~59 黄、<30 红（与 horizon 柱状图同一阈值）
func fpsColor(fps: Int64): Color {
    if (fps >= 55) {
        Color(110, 210, 120, 255)
    } else if (fps >= 30) {
        Color(240, 200, 90, 255)
    } else {
        Color(240, 90, 80, 255)
    }
}
