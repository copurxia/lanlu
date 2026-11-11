package lwindow

// 输入源选择（过渡期）：`LANLU_LWP=1` 时走 LWP 通道，否则走原有文件桥。
// 计划 §11 的删除清单里，文件桥在 M6 退役；在那之前两套并存，但**出口只有一个**——
// 都产出 LWindowEvent，业务层不感知来源差异。

import lwp.*
import std.collection.ArrayList
import std.env.getVariable

// 进程内唯一的输入通道 + 待消费队列（引擎每帧取一条）
private var g_lwpChannel: ?LwpChannel = None
private var g_lwpWindow: ?LwpWindowClient = None
private var g_backlog: ArrayList<LWindowEvent> = ArrayList<LWindowEvent>()

/// 是否启用 LWP 输入。
/// **默认开启**（协议已是唯一主路径，真机验收通过后翻转）；`LANLU_LWP=0` 显式回退到文件桥，
/// 只作为排障退路 —— M6 删除文件桥后这个开关一并消失。
public func lwpInputEnabled(): Bool {
    (getVariable("LANLU_LWP") ?? "1") != "0"
}

/// 打开输入通道（幂等）。名字必须与壳侧一致，否则会各建一条通道。
public func initLwpInput(name!: String = "lanlu"): Bool {
    if (g_lwpChannel.isSome()) {
        return true
    }
    try {
        let ch = LwpChannel.open(name)
        // 检查器保持非严格：真机上宁可能用，违规只计数（由 statsSummary 上报）。
        // 必须先开检查器再发 hello_ack：检查器只在**发送**路径上记录握手完成，
        // 顺序反了会导致 hello_ack 不被记账，后续每条消息都被判 notHandshaked。
        ch.enableChecker(strict: false)
        // 录制：LANLU_LWP_TRACE=<path>（真机取证，计划 §16.3）。引擎侧打开最可靠：
        // 壳侧 C 的 lanlu_lwp_ready 有进程级缓存，env 时序容易错过。
        println("[lwp] env LANLU_LWP_TRACE=" + (getVariable("LANLU_LWP_TRACE") ?? "<unset>"))
        match (getVariable("LANLU_LWP_TRACE")) {
            case Some(p) =>
                if (p.size > 0) {
                    let ok = ch.traceOpen(p)
                    println("[lwp] trace " + p + " -> " + ok.toString())
                }
            case None => ()
        }
        // 握手：回 hello_ack（壳的 hello 由 lwp_client 在首次使用时发出）。
        let _ = ch.sendHelloAck()
        g_lwpChannel = ch
        g_lwpWindow = LwpWindowClient(ch)
        true
    } catch (_) {
        false
    }
}

/// 取一条输入事件（LWP 模式）；队列空返回 None。
/// 一次把通道里的事件全部搬进本地位列，避免每帧只取一条造成积压。
private var g_lastPtrX: Float32 = -1.0
private var g_lastPtrY: Float32 = -1.0

/// 记录指针位置（解码时调用；frame tick 里据此决定光标形状）。
public func lwpNotePointer(x: Float32, y: Float32): Unit {
    g_lastPtrX = x
    g_lastPtrY = y
}

public func nextLwpEvent(): ?LWindowEvent {
    // 先看 poll() 暂存的消息（每帧 tick 会先跑，容易把输入抢走）。
    // 暂存区里也可能有 hello 之类非输入消息，跳过继续取。
    while (true) {
        match (takeBacklogLwpMessage()) {
            case Some(msg) =>
                match (decodeLwpEvent(msg)) {
                    case Some(ev) => return Some(ev)
                    case None => continue
                }
            case None => break
        }
    }
    if (g_backlog.size == 0) {
        match (g_lwpChannel) {
            case Some(ch) =>
                for (ev in pollLwpEvents(ch)) {
                    g_backlog.add(ev)
                }
            case None => return None
        }
    }
    if (g_backlog.size == 0) {
        return None
    }
    let ev = g_backlog.remove(at: 0)
    Some(ev)
}

/// 启动时等待壳下发的初始 configure（毫秒）。返回 (宽, 高) 或 None。
/// 只有 LANLU_LWP=1 时才有意义；超时即回退到本地几何策略。
public func lwpAwaitInitialConfigure(timeoutMs: Int64): ?(Int64, Int64) {
    if (!lwpInputEnabled()) {
        return None
    }
    if (g_lwpChannel.isNone()) {
        if (!initLwpInput()) {
            return None
        }
    }
    match (g_lwpWindow) {
        case Some(w) => w.awaitConfigure(timeoutMs)
        case None => None
    }
}

/// 启动时等待壳下发 system.info（毫秒）。拿到就缓存下来，供字体/时区/语言使用。
public func lwpAwaitSystemInfo(timeoutMs: Int64): Bool {
    if (!lwpInputEnabled()) {
        return false
    }
    if (g_lwpChannel.isNone() && !initLwpInput()) {
        return false
    }
    match (g_lwpWindow) {
        case Some(w) =>
            if (w.systemInfo.isSome()) {
                return true
            }
            let deadline = lwpNowNs() + timeoutMs * 1000000
            while (lwpNowNs() < deadline) {
                let evs = w.pollAll()
                var got = false
                for (ev in evs) {
                    match (ev) {
                        case LWindowLifecycleEvent.SystemInfo(_, _, _, _, _) => got = true
                        case _ => ()
                    }
                }
                if (got || w.systemInfo.isSome()) {
                    return true
                }
                let left = (deadline - lwpNowNs()) / 1000000
                if (left <= 0) {
                    break
                }
                let _ = g_lwpChannel.getOrThrow().wait(LWP_EVENT, Int32(left))
            }
            false
        case None => false
    }
}

/// 有界等待壳下发 surface.available（毫秒）。返回 (handle, w, h) 或 None。
/// 取代“轮询环境变量等 surface id”的老做法（计划 §7：尺寸/句柄都由协议给）。
public func lwpAwaitSurface(timeoutMs: Int64): ?(Int64, Int64, Int64) {
    if (!lwpInputEnabled()) {
        return None
    }
    if (g_lwpChannel.isNone() && !initLwpInput()) {
        return None
    }
    match (g_lwpWindow) {
        case Some(w) =>
            let deadline = lwpNowNs() + timeoutMs * 1000000
            while (true) {
                if (w.surfaceAlive && w.surfaceHandle != 0) {
                    return Some((Int64(w.surfaceHandle), Int64(w.surfaceWidth), Int64(w.surfaceHeight)))
                }
                if (lwpNowNs() >= deadline) {
                    return None
                }
                let evs = w.pollAll()
                for (ev in evs) {
                    match (ev) {
                        case LWindowLifecycleEvent.SurfaceAvailable(_, _, _) => ()
                        case _ => ()
                    }
                }
                let left = (deadline - lwpNowNs()) / 1000000
                if (left > 0) {
                    let _ = g_lwpChannel.getOrThrow().wait(LWP_EVENT, Int32(left))
                }
            }
            None
        case None => None
    }
}

/// 告知壳「引擎已就绪」：之后壳可经 lw_test 注入测试动作。
public func lwpSendTestReady(): Bool {
    match (g_lwpWindow) {
        case Some(w) => w.sendTestReady()
        case None => false
    }
}

// 剪贴板异步读的缓存：clipboard.text 事件到达时填充
private var g_clipboardCache: String = ""

/// 协议版写剪贴板。通道不可用时返回 None（调用方回落文件桥）。
public func lwpClipboardSetText(text: String): ?Bool {
    match (g_lwpWindow) {
        case Some(w) => Some(w.clipboardSet(text))
        case None => None
    }
}

/// 协议版读剪贴板：发出 get 请求并返回缓存的最近值（可能为空）。
/// 与文件桥的同步语义不同：这是**异步**的，第一次调用大概率拿到空串。
public func lwpClipboardGetText(): ?String {
    match (g_lwpWindow) {
        case Some(w) =>
            // 壳没宣告 clipboard_read_async 就不要发 get：异步读没有回执，
            // 只会让缓存永远是空的，调用方还以为「剪贴板是空的」。
            if (!w.hasCapability(LWP_CORE_CAPABILITIES_CLIPBOARD_READ_ASYNC)) {
                return None   // 让调用方回落文件桥
            }
            let _ = w.clipboardGet()
            Some(g_clipboardCache)
        case None => None
    }
}

/// 引擎日志出口：LANLU_LWP=1 且通道就绪时发 system.log（壳转 hilog）。
/// 返回 true 表示已通过协议发出；调用方否则自行回落文件输出。
public func lwpLog(level: UInt8, text: String): Bool {
    match (g_lwpWindow) {
        case Some(w) => w.log(text, level: level)
        case None => false
    }
}

/// 窗口状态/退出请求的协议出口。通道不可用返回 None（调用方回落 window_cmd.txt）。
public func lwpWindowCommand(command: String): ?Bool {
    match (g_lwpWindow) {
        case Some(w) =>
            match (command) {
                case "minimize" => Some(w.requestState(8))     // 沉浸式/最小化由壳解释
                case "maximize" => Some(w.requestState(2))
                case "restore" => Some(w.requestState(1))
                case "fullscreen" => Some(w.requestState(4))
                case "close" => Some(w.requestCloseWindow())
                case "exit" => Some(w.requestExit(0))
                case _ => None
            }
        case None => None
    }
}

/// 请求壳抓一帧（lw_test.capture）。协议不可用返回 false，调用方回落文件桥。
public func lwpRequestCapture(path: String): Bool {
    match (g_lwpWindow) {
        case Some(w) =>
            w.captureTo(path)
        case None => false
    }
}

/// 壳是否提供 vsync（决定引擎是「请求帧」还是「自驱节拍」）。
public func lwpShellProvidesVsync(): Bool {
    match (g_lwpWindow) {
        case Some(w) => w.shellProvidesVsync()
        case None => false
    }
}

/// 壳是否宣告「平台三键」能力（title_buttons，docs/lwindow-title-buttons-plan.md）。
/// 未宣告（或协议不可用）= 平台没有三键 → 业务层自绘回退。
public func lwpShellProvidesTitleButtons(): Bool {
    match (g_lwpWindow) {
        case Some(w) => w.hasCapability(LWP_CORE_CAPABILITIES_TITLE_BUTTONS)
        case None => false
    }
}

/// 配置平台三键（docs/lwindow-title-buttons-plan.md）。
/// 壳未宣告 title_buttons 能力时返回 false（调用方走自绘回退）。
public func lwpSetTitleButtons(visible: UInt32, side: UInt32, closeMargin: UInt32,
    spacing: UInt32, buttonSize: UInt32, colorMode: UInt32): Bool {
    match (g_lwpWindow) {
        case Some(w) => w.setTitleButtons(visible, side: side, closeMargin: closeMargin,
            spacing: spacing, buttonSize: buttonSize, colorMode: colorMode)
        case None => false
    }
}

/// 回放一份 .lwtrace（计划 §16.3）：把录制里的壳侧消息重新入队。返回条数，失败 -1。
public func lwpReplayTrace(path: String): Int64 {
    match (g_lwpChannel) {
        case Some(ch) => Int64(ch.replay(path))
        case None => -1
    }
}

/// 壳下发的系统信息（字体目录/语言/时区）；未启用或未收到时返回 None。
public func lwpSystemInfo(): ?(String, String, String, String, UInt32) {
    match (g_lwpWindow) {
        case Some(w) => w.systemInfo
        case None => None
    }
}

/// 排空生命周期事件（运行期每帧调用；configure 已在客户端内自动 ack）。
public func lwpDrainLifecycle(): ArrayList<LWindowLifecycleEvent> {
    match (g_lwpWindow) {
        case Some(w) => w.pollAll()
        case None =>
            let empty = ArrayList<LWindowLifecycleEvent>()
            empty
    }
}

/// 每帧调用：请求下一帧回调 + 排空生命周期 + 检查 configure/frame 超时。
/// LANLU_LWP 未开时是空操作。返回本次是否有新的事件被处理（诊断用）。
public func lwpFrameTick(): Bool {
    match (g_lwpWindow) {
        case Some(win) =>
            // 帧提交：attach(buffer=0) 表达"本帧已画完"（§7.3.1）。
            // OHOS 直渲染不需要壳搬像素，但协议要有这条消息，否则
            // 壳的帧统计与检查器的 attach 计数永远是 0。
            if (win.canPresent() && win.surfaceWidth > 0) {
                let _ = win.attach(0, win.surfaceWidth, win.surfaceHeight)
            }
            // 只有壳宣告了 vsync 才每帧请求；否则退回自驱节拍（不请求、也不判超时）
            if (win.shellProvidesVsync()) {
                let _ = win.requestFrame()
            }
            let evs = win.pollAll()
            // 剪贴板异步读的回执在这里落地（clipboard.get 是异步的）
            for (ev in evs) {
                match (ev) {
                    case LWindowLifecycleEvent.ClipboardText(_, _, text) => g_clipboardCache = text
                    case _ => ()
                }
            }
            let _ = win.checkConfigureTimeout(lwpNowNs())
            if (win.shellProvidesVsync()) {
                let _ = win.checkFrameTimeout(lwpNowNs())
            }
            evs.size > 0
        case None => false
    }
}

/// 协议违规汇总（诊断；0 表示健康）。
public func lwpViolations(): String {
    match (g_lwpWindow) {
        case Some(win) => "unackedConfigure=${win.unackedConfigure} frameTimeout=${win.frameTimeout} attachOutOfOrder=${win.attachOutOfOrder}"
        case None => ""
    }
}

private var g_cursorShapeSent: UInt32 = 255

/// 已经发给壳的光标形状（255 = 还没发过）。frame tick 用它去抖。
public func lwpCursorShapeSent(): UInt32 {
    g_cursorShapeSent
}

/// 最近一次指针位置（窗口逻辑坐标）；没有移动过则为 (-1,-1)。
public func lwpLastPointer(): (Float32, Float32) {
    (g_lastPtrX, g_lastPtrY)
}

/// 指针形状决策：落在文本框矩形内给「文本」光标（1），否则「默认」（0）。
/// 抽成纯函数便于单测；坐标系与矩形都必须是**窗口逻辑坐标**。
public func lwpCursorShapeForPoint(tx: Float32, ty: Float32, tw: Float32, th: Float32,
                                  x: Float32, y: Float32, hasTextInput: Bool): UInt32 {
    if (!hasTextInput || tw <= 0.0 || th <= 0.0) { return 0 }
    if (x >= tx && x <= tx + tw && y >= ty && y <= ty + th) { return 1 }
    0
}

/// 开始拖动窗口 / 缩放（引擎标题栏用）。
public func lwpBeginMove(): Bool {
    match (g_lwpWindow) {
        case Some(w) => w.beginMove()
        case None => false
    }
}

public func lwpBeginResize(edges: UInt32): Bool {
    match (g_lwpWindow) {
        case Some(w) => w.beginResize(edges)
        case None => false
    }
}

/// 壳上报的 UI 缩放（无壳时 1.0）。窗口逻辑尺寸 = 物理尺寸 / 它。
public func lwpReportedScale(): Float32 {
    match (g_lwpWindow) {
        case Some(w) => if (w.reportedScale > 0.0) { w.reportedScale } else { 1.0 }
        case None => 1.0
    }
}

/// 告知壳"文本输入开始/结束"（壳据此显示/隐藏软键盘、attach/detach 输入法）。
public func lwpImeEnable(enabled: Bool): Bool {
    match (g_lwpWindow) {
        case Some(w) => w.imeEnable(enabled)
        case None => false
    }
}

/// 运行期改窗口标题（壳侧 OHOS: setWindowTitle / Wayland: xdg_toplevel.set_title）。
public func lwpSetWindowTitle(title: String): Bool {
    match (g_lwpWindow) {
        case Some(w) => w.setTitle(title)
        case None => false
    }
}

/// 运行期设置最小/最大尺寸（0 表示不限）。
public func lwpSetWindowMinMax(minW: UInt32, minH: UInt32, maxW: UInt32, maxH: UInt32): Bool {
    match (g_lwpWindow) {
        case Some(w) => w.setMinMax(minW, minH, maxW, maxH)
        case None => false
    }
}

/// 提交一帧（buffer=0 表示引擎已直接渲染进壳提供的 surface，见计划 §7.3.1）。
/// OHOS 走直渲染，attach 只表达"帧已提交 + 节拍"，但**必须真的发**，
/// 否则检查器的 attach 计数与壳的帧统计永远是 0（第 110 轮发现）。
public func lwpNotePresented(w: UInt32, h: UInt32): Bool {
    match (g_lwpWindow) {
        case Some(win) => win.attach(0, w, h)
        case None => false
    }
}

/// 光标形状交给壳（0=默认 1=文本 2=手型 …，见文档 §7.5）。
public func lwpSetCursorShape(shape: UInt32): Bool {
    let ok = match (g_lwpWindow) {
        case Some(w) => w.setCursorShape(shape)
        case None => false
    }
    if (ok) { g_cursorShapeSent = shape }
    ok
}

/// 光标矩形（窗口坐标）交给壳：IME 候选框据此定位（OHOS 给 IME 面板，Wayland 走 text-input）。
public func lwpImeSetCursorRect(x: Int32, y: Int32, w: Int32, h: Int32): Bool {
    match (g_lwpWindow) {
        case Some(win) => win.imeSetCursorRect(x, y, w, h)
        case None => false
    }
}

/// 把 frame.done 交给客户端记账（更新已回执水位，避免合并回执被误判为超时）。
public func lwpNoteFrameDone(serial: UInt32): Unit {
    match (g_lwpWindow) {
        case Some(w) => w.noteFrameDone(serial)
        case None => ()
    }
}

/// configure 超时检查（诊断计数）。
public func lwpCheckConfigureTimeout(): Bool {
    match (g_lwpWindow) {
        case Some(w) => w.checkConfigureTimeout(lwpNowNs())
        case None => false
    }
}

/// 输入通道句柄（窗口客户端与输入共用同一条通道）。未初始化时抛异常。
public func lwpInputChannel(): LwpChannel {
    match (g_lwpChannel) {
        case Some(ch) => ch
        case None => throw LwpException("lwp 通道未初始化")
    }
}

/// 单调时钟（毫秒无关，纳秒）：引擎判 configure 超时用，避免直接依赖 lwp 包类型。
public func lwpNowNs(): Int64 {
    Int64(LwpChannel.nowNs())
}

/// 通道统计摘要（诊断用；未开启 LWP 或未初始化时返回空串）。
/// 通道统计 + 违规计数（一行）。违规必须和 stats 一起看，否则容易只盯着不涨的那个。
public func lwpStatsLine(): String {
    match (g_lwpChannel) {
        case Some(ch) =>
            let base = ch.statsSummary()
            if (base.size == 0) {
                return base
            }
            base + " " + lwpViolations()
        case None => ""
    }
}

/// 测试专用：清空进程内的通道状态（让每个测试从干净状态开始）。
/// 生产代码不应调用——它会让引擎与壳的通道实例失去同步。
public func lwpResetForTest(): Unit {
    g_lwpChannel = None
    g_lwpWindow = None
    g_backlog = ArrayList<LWindowEvent>()
    g_clipboardCache = ""
}

/// 测试/诊断用：当前 backlog 深度。
public func lwpBacklogSize(): Int64 {
    g_backlog.size
}
