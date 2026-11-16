package lwindow

// 窗口生命周期客户端（计划 §7）：把 lw_app / lw_window / lw_surface / lw_frame / lw_display
// 的消息翻译成 LWindowLifecycleEvent，并维护「configure 必须 ack」的状态机。
//
// 为什么 ack 规则放在这一层而不是 liblwp：liblwp 只管线上格式，窗口语义属于 L 层。
// 超时判定用可注入的时钟，测试里不依赖真实时间。

import lwp.*
import std.collection.ArrayList

/// 窗口/应用生命周期事件（与输入事件分开：输入走 LWindowEvent，生命周期走这里）。
public enum LWindowLifecycleEvent {
    | AppStarted(UInt32)
    | AppResumed
    | AppPaused
    | WindowCreated(UInt32, Float32, Bool)      // id, scale, serverSideDecorations
    | Configure(UInt32, UInt32, UInt32)        // width, height, state
    | CloseRequest
    | Focus(Bool)
    | FrameDone(UInt32, UInt64)                // serial, timeNs
    | DisplayInfo(UInt32, UInt32, Float32, UInt32)
    | SurfaceAvailable(UInt64, UInt32, UInt32)   // native window 句柄 + 尺寸
    | SurfaceChanged(UInt32, UInt32)
    | SurfaceWillDestroy
    | SurfaceHidden
    | SystemInfo(String, String, String, String, UInt32)  // 时区/语言/字体目录/家目录/API 级别
    | TestInject(UInt32, Int32, Int32)                    // 壳注入的测试动作（计划 §16）
    | TestCapture(String)                                // 壳要求抓一帧到指定路径
    | TestReplay(String)                                 // 壳要求回放一段 .lwtrace
    | ClipboardText(UInt32, String, String)             // serial, mime, text
    | DragEnter(UInt32, UInt32, String)                  // x, y, uris(\n 分隔，可能为空)
    | DragMotion(UInt32, UInt32)                         // x, y
    | DragLeave
    | DragDrop(UInt32, UInt32, String)                   // x, y, uris(已解码为本地路径)
    | DialogResult(UInt32, String)                      // serial, path（空=取消）
    | TitleButtonsRect(Int32, Int32, UInt32, UInt32, Bool) // right, top, width, height, visible（窗口局部 px）
}

/// configure 超时（毫秒）。壳下发 configure 后引擎必须在这个时间内 ack。
let LWP_CONFIGURE_TIMEOUT_MS: Int64 = 500
/// frame.request 到 frame.done 的超时（毫秒）。超过说明壳没在呈现，应告警。
let LWP_FRAME_TIMEOUT_MS: Int64 = 200

public class LwpWindowClient {
    private let ch: LwpChannel
    private var pendingConfigureSerial: UInt32 = 0
    private var pendingDeadlineNs: Int64 = 0
    private var serialSeq: UInt32 = 1
    private var windowId: UInt32 = 0
    private let autoAck: Bool

    /// 协议违规计数（诊断用；非严格模式下只统计不阻断）
    public var unackedConfigure: Int64 = 0
    public var frameTimeout: Int64 = 0          // frame.request 后没等到 frame.done
    public var lastAckSerial: Int64 = 0         // frame.done 的已回执水位（允许合并）
    public var attachOutOfOrder: Int64 = 0      // attach 序列号倒退
    public var attachAfterDestroy: Int64 = 0    // will_destroy 之后仍在 attach
    public var frameWhileHidden: Int64 = 0      // hidden 期间仍在请求帧
    private var surfaceHiddenFlag: Bool = false
    private var pendingFrameSerial: UInt32 = 0
    private var pendingFrameDeadlineNs: Int64 = 0
    private var lastAttachSerial: UInt32 = 0
    /// 最近一次 system.info（壳下发）；None 表示还没收到
    public var systemInfo: ?(String, String, String, String, UInt32) = None
    /// 最近一次 surface 状态（诊断/渲染器用）
    public var surfaceHandle: UInt64 = 0
    /// 壳上报的 UI 缩放（`window.created.scale`）；默认 1.0。
    /// 物理像素 = 逻辑坐标 × reportedScale。
    public var reportedScale: Float32 = 1.0
    public var surfaceWidth: UInt32 = 0
    public var surfaceHeight: UInt32 = 0
    public var surfaceAlive: Bool = false
    /// 壳在 core.hello 里宣告的能力位（0 = 什么都没宣告，引擎应走最保守路径）
    public var shellCapabilities: UInt64 = 0
    /// 壳在 lw_seat.capabilities 里宣告的输入设备能力位
    public var seatCapabilities: UInt64 = 0
    /// 平台三键矩形快照（窗口局部 px；width=0 表示平台没有三键/未上报）。
    /// 由 lw_window.title_buttons_rect 事件更新；业务层据此做右侧/顶部避让。
    public var titleBtnRight: Int32 = 0
    public var titleBtnTop: Int32 = 0
    public var titleBtnWidth: UInt32 = 0
    public var titleBtnHeight: UInt32 = 0
    public var titleBtnVisible: Bool = false

    /// autoAck：收到 configure 后自动 ack（引擎默认 true；测试里可关掉以验证超时路径）
    public init(ch: LwpChannel, autoAck!: Bool = true) {
        this.ch = ch
        this.autoAck = autoAck
    }

    /// 请求壳创建窗口（plan §7：引擎发起，壳分配 id 并回 created）。
    public func create(title: String, width: UInt32, height: UInt32, resizable!: Bool = true): Bool {
        let flags: UInt32 = if (resizable) { 1 } else { 0 }
        ch.send(LWP_REQUEST, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_CREATE_OPCODE,
            encodeLwWindowCreate(title, width, height, flags), flags: 0) == 0
    }

    /// 取一条生命周期事件（队列空则 None）。遇到 configure 会记录待 ack 状态。
    ///
    /// 注意：不能把「队列空」和「不认识的消息」都返回 None —— 否则 pollAll 遇到
    /// 第一条 hello/输入事件就会停下（这正是本函数第一版的 bug，被测试抓到）。
    /// 不认识的消息在这里跳过，继续取下一条。
    public func poll(nowNs!: Int64 = -1): ?LWindowLifecycleEvent {
        while (true) {
            match (ch.recv(LWP_EVENT)) {
                case Some(msg) =>
                    match (decode(msg, nowNs)) {
                        case Some(ev) => return ev
                        // 不是生命周期事件（而是输入事件）：放回暂存区，别丢！
                        case None =>
                            pushBackLwpMessage(msg)
                            continue
                    }
                case None => return None
            }
        }
        None
    }

    /// 排空并返回所有生命周期事件。
    public func pollAll(nowNs!: Int64 = -1): ArrayList<LWindowLifecycleEvent> {
        let out = ArrayList<LWindowLifecycleEvent>()
        while (true) {
            match (poll(nowNs: nowNs)) {
                case Some(ev) => out.add(ev)
                case None => break
            }
        }
        out
    }

    /// 接受壳下发的 configure（必须调用，否则壳会按超时回退）。
    public func ackConfigure(): Bool {
        if (pendingConfigureSerial == 0) {
            return false
        }
        let ok = ch.send(LWP_REQUEST, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_ACK_CONFIGURE_OPCODE,
            encodeLwWindowAckConfigure(pendingConfigureSerial)) == 0
        if (ok) {
            pendingConfigureSerial = 0
            pendingDeadlineNs = 0
        }
        ok
    }

    /// 告知壳「引擎已就绪，可以注入测试动作」（计划 §16：自检由壳触发，不再靠引擎读环境变量）。
    public func sendTestReady(engineVersion!: UInt32 = 1): Bool {
        ch.send(LWP_REQUEST, LWP_IFACE_LW_TEST, LWP_LW_TEST_READY_OPCODE,
            encodeLwTestReady(engineVersion)) == 0
    }

    // ── 剪贴板 / 对话框（引擎 -> 壳的请求；结果经事件回来）──────────────────
    private var clipboardSerial: UInt32 = 100
    private var dialogSerial: UInt32 = 200

    /// 写剪贴板。结果没有回执（壳尽力而为）。
    public func clipboardSet(text: String): Bool {
        ch.send(LWP_REQUEST, LWP_IFACE_LW_CLIPBOARD, LWP_LW_CLIPBOARD_SET_OPCODE,
            encodeLwClipboardSet("text/plain", text)) == 0
    }

    /// 读剪贴板（异步）：发出请求，稍后事件 `clipboard.text(serial)` 回来。
    /// 返回本次 serial，调用方在 pollAll 里等 ClipboardText。
    public func clipboardGet(): UInt32 {
        clipboardSerial = clipboardSerial + 1
        let _ = ch.send(LWP_REQUEST, LWP_IFACE_LW_CLIPBOARD, LWP_LW_CLIPBOARD_GET_OPCODE,
            encodeLwClipboardGet(clipboardSerial))
        clipboardSerial
    }

    /// 打开文件选择器。返回 serial。
    public func dialogOpenFile(filters!: String = ""): UInt32 {
        dialogSerial = dialogSerial + 1
        let _ = ch.send(LWP_REQUEST, LWP_IFACE_LW_DIALOG, LWP_LW_DIALOG_OPEN_FILE_OPCODE,
            encodeLwDialogOpenFile(dialogSerial, filters))
        dialogSerial
    }

    /// 保存对话框。返回 serial。
    public func dialogSaveFile(suggested: String): UInt32 {
        dialogSerial = dialogSerial + 1
        let _ = ch.send(LWP_REQUEST, LWP_IFACE_LW_DIALOG, LWP_LW_DIALOG_SAVE_FILE_OPCODE,
            encodeLwDialogSaveFile(dialogSerial, suggested))
        dialogSerial
    }

    /// 请壳抓一帧到指定路径（`lw_test.capture`，壳用 componentSnapshot）。
    public func captureTo(path: String): Bool {
        ch.send(LWP_REQUEST, LWP_IFACE_LW_TEST, LWP_LW_TEST_REQUEST_CAPTURE_OPCODE,
            encodeLwTestCapture(path)) == 0
    }

    /// 把一行日志交给壳输出（hilog）。返回是否已发出。
    /// 计划 §16：两个通道的日志要能对齐时间线，所以不各写各的文件。
    public func log(text: String, level!: UInt8 = 1): Bool {
        ch.send(LWP_REQUEST, LWP_IFACE_LW_SYSTEM, LWP_LW_SYSTEM_LOG_OPCODE,
            encodeLwSystemLog(level, text)) == 0
    }

    // ── IME（计划 §6.4 / text-input-v3 子集）───────────────────────────────
    /// 获得焦点时开启输入法；失去焦点时关闭。
    /// inputType/enterKey 见 LWP_IME_TEXT_INPUT_*/LWP_IME_ENTER_KEY_*（壳用来选输入法模式）。
    public func imeEnable(enabled: Bool, inputType!: UInt32 = UInt32(LWP_IME_TEXT_INPUT_TYPE_TEXT),
        enterKey!: UInt32 = UInt32(LWP_IME_ENTER_KEY_DONE)): Bool {
        if (enabled) {
            ch.send(LWP_REQUEST, LWP_IFACE_LW_TEXT_INPUT, LWP_LW_TEXT_INPUT_ENABLE_OPCODE,
                encodeLwTextInputEnable(inputType, enterKey)) == 0
        } else {
            ch.send(LWP_REQUEST, LWP_IFACE_LW_TEXT_INPUT, LWP_LW_TEXT_INPUT_DISABLE_OPCODE,
                encodeLwTextInputToggle()) == 0
        }
    }

    /// 告知输入法光标周围的文本（联想/纠错用）。
    public func imeSetSurrounding(text: String, cursor: UInt32, anchor: UInt32): Bool {
        ch.send(LWP_REQUEST, LWP_IFACE_LW_TEXT_INPUT, LWP_LW_TEXT_INPUT_SET_SURROUNDING_OPCODE,
            encodeLwTextInputSetSurrounding(text, cursor, anchor)) == 0
    }

    /// 光标矩形（窗口坐标）：输入法据此定位候选框。
    public func imeSetCursorRect(x: Int32, y: Int32, w: Int32, h: Int32): Bool {
        ch.send(LWP_REQUEST, LWP_IFACE_LW_TEXT_INPUT, LWP_LW_TEXT_INPUT_SET_CURSOR_RECT_OPCODE,
            encodeLwTextInputCursorRect(x, y, w, h)) == 0
    }

    // ── 窗口状态与退出（引擎 -> 壳；替代 window_cmd.txt / appExited 轮询）──────
    /// 请求窗口状态：1=普通 2=最大化 4=全屏 8=沉浸式（与 configure 的 state 位一致）
    public func requestState(state: UInt32): Bool {
        ch.send(LWP_REQUEST, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_SET_STATE_OPCODE,
            encodeLwWindowSetState(state)) == 0
    }

    public func requestCloseWindow(): Bool {
        ch.send(LWP_REQUEST, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_CLOSE_OPCODE,
            encodeLwWindowClose()) == 0
    }

    /// 运行期设置最小/最大尺寸（0 = 不限）。
    public func setMinMax(minW: UInt32, minH: UInt32, maxW: UInt32, maxH: UInt32): Bool {
        ch.send(LWP_REQUEST, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_SET_MIN_MAX_OPCODE,
            encodeLwWindowSetMinMax(minW, minH, maxW, maxH)) == 0
    }

    // ── 平台三键（引擎 -> 壳；docs/lwindow-title-buttons-plan.md）─────────────
    /// 配置平台侧三键（可见性/位置/尺寸/明暗）。壳按平台能力 best-effort 应用。
    /// visible 位掩码：1=max 2=min 4=close；side：0=右上 1=左上；
    /// closeMargin/spacing/buttonSize 单位 vp；colorMode：0=跟随系统 1=light 2=dark。
    /// 壳未宣告 title_buttons 能力时返回 false 且不发送（引擎应走自绘回退）。
    public func setTitleButtons(visible: UInt32, side!: UInt32 = 0, closeMargin!: UInt32 = 16,
        spacing!: UInt32 = 12, buttonSize!: UInt32 = 28, colorMode!: UInt32 = 0): Bool {
        if (!hasCapability(LWP_CORE_CAPABILITIES_TITLE_BUTTONS)) {
            return false
        }
        ch.send(LWP_REQUEST, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_SET_TITLE_BUTTONS_OPCODE,
            encodeLwWindowSetTitleButtons(visible, side, closeMargin, spacing, buttonSize, colorMode)) == 0
    }

    /// 开始交互式移动（标题栏按下时由引擎发起；壳用最近一次输入 serial 调 xdg_toplevel.move）。
    public func beginMove(): Bool {
        ch.send(LWP_REQUEST, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_BEGIN_MOVE_OPCODE,
            encodeLwWindowBeginMove()) == 0
    }

    /// 开始交互式缩放。edges 位与 xdg-shell 一致：1=上 2=下 4=左 8=右。
    public func beginResize(edges: UInt32): Bool {
        ch.send(LWP_REQUEST, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_BEGIN_RESIZE_OPCODE,
            encodeLwWindowBeginResize(edges)) == 0
    }

    public func requestExit(code: Int32): Bool {
        ch.send(LWP_REQUEST, LWP_IFACE_LW_APP, LWP_LW_APP_EXIT_OPCODE,
            encodeLwAppExit(code)) == 0
    }

    /// 设置光标形状（对应 lw_seat.set_cursor）。
    /// 形状编号见文档 §7.5：0=默认 1=文本 2=手型 3=等待 4=十字 5=移动
    /// 6=禁止 7=水平调整 8=垂直调整 9=对角调整(↘) 10=对角调整(↗)
    public func setCursorShape(shape: UInt32): Bool {
        if (!hasCapability(LWP_CORE_CAPABILITIES_CURSOR_SHAPES)) {
            return false   // 壳不支持就别发，省得白跑
        }
        ch.send(LWP_REQUEST, LWP_IFACE_LW_SEAT, LWP_LW_SEAT_SET_CURSOR_OPCODE,
            encodeLwSeatSetCursor(shape)) == 0
    }

    /// 提交一帧（buffer 句柄由 lgpu 分配）。serial 必须单调递增，倒退会计数。
    public func attach(buffer: UInt64, width: UInt32, height: UInt32): Bool {
        // 检查器规则（§7.1）：will_destroy 之后不得再提交帧
        if (!surfaceAlive && surfaceHandle != 0) {
            attachAfterDestroy = attachAfterDestroy + 1
        }
        serialSeq = serialSeq + 1
        if (serialSeq <= lastAttachSerial) {
            attachOutOfOrder = attachOutOfOrder + 1
        }
        lastAttachSerial = serialSeq
        ch.send(LWP_REQUEST, LWP_IFACE_LW_SURFACE, LWP_LW_SURFACE_ATTACH_OPCODE,
            encodeLwSurfaceAttach(buffer, width, height, serialSeq)) == 0
    }

    /// 请求下一帧回调。返回本次 serial；同时记录等待截止时间（超时会记 frameTimeout）。
    public func requestFrame(nowNs!: Int64 = -1): UInt32 {
        // 检查器规则（§7.1）：hidden 期间不应请求帧（引擎应停帧但保留 surface）
        if (surfaceHiddenFlag) {
            frameWhileHidden = frameWhileHidden + 1
        }
        serialSeq = serialSeq + 1
        pendingFrameSerial = serialSeq
        let now = if (nowNs >= 0) { nowNs } else { Int64(LwpChannel.nowNs()) }
        pendingFrameDeadlineNs = now + LWP_FRAME_TIMEOUT_MS * 1000000
        let _ = ch.send(LWP_REQUEST, LWP_IFACE_LW_FRAME, LWP_LW_FRAME_REQUEST_OPCODE,
            encodeLwFrameRequest(serialSeq))
        serialSeq
    }

    /// frame.request 是否超时无 frame.done。返回 true 表示本次新发现一次。
    /// 收到 frame.done：更新已回执水位。壳的 vsync 可能**合并**请求
    /// （两次 request 之间只回一次 done，ack 的是最新的），所以超时判定要看水位，
    /// 不能只看"这一条 serial 有没有被单独回执"。
    public func noteFrameDone(serial: UInt32): Unit {
        if (Int64(serial) > lastAckSerial) {
            lastAckSerial = Int64(serial)
        }
        if (Int64(serial) >= Int64(pendingFrameSerial)) {
            pendingFrameSerial = 0
            pendingFrameDeadlineNs = 0
        }
    }

    public func checkFrameTimeout(nowNs: Int64): Bool {
        if (pendingFrameSerial == 0 || nowNs < pendingFrameDeadlineNs) {
            return false
        }
        // 合并回执：只要已回执水位追上了最新请求，就不算超时
        if (lastAckSerial >= Int64(pendingFrameSerial)) {
            pendingFrameSerial = 0
            pendingFrameDeadlineNs = 0
            return false
        }
        frameTimeout = frameTimeout + 1
        pendingFrameSerial = 0
        pendingFrameDeadlineNs = 0
        true
    }

    /// 现在允许提交帧吗（surface 可用且未 hidden）
    public func canPresent(): Bool {
        surfaceAlive && !surfaceHiddenFlag
    }

    /// 壳是否提供 vsync 回调。false 时引擎不该每帧请求（壳回不了 frame.done，
    /// 只会积压请求并触发 frameTimeout 假告警）。§7.3 记录过 horizon 的实测：
    /// 外来渲染管线的 XComponent 收不到系统 vsync。
    public func shellProvidesVsync(): Bool {
        (shellCapabilities & LWP_CORE_CAPABILITIES_VSYNC) != 0
    }

    /// 壳是否宣告了某项能力（位定义见 IDL 的 core_capabilities）。
    public func hasCapability(bit: UInt64): Bool {
        (shellCapabilities & bit) != 0
    }

    public func hasPendingFrame(): Bool {
        pendingFrameSerial != 0
    }

    public func setTitle(title: String): Bool {
        ch.send(LWP_REQUEST, LWP_IFACE_LW_WINDOW, LWP_LW_WINDOW_SET_TITLE_OPCODE,
            encodeLwWindowSetTitle(title)) == 0
    }

    /// 检查 configure 是否超时未 ack。返回 true 表示本次新发现一次违规。
    public func checkConfigureTimeout(nowNs: Int64): Bool {
        if (pendingConfigureSerial == 0 || nowNs < pendingDeadlineNs) {
            return false
        }
        unackedConfigure = unackedConfigure + 1
        pendingConfigureSerial = 0   // 只报一次，避免每帧重复计数
        pendingDeadlineNs = 0
        true
    }

    /// 阻塞等待第一次 configure（建窗前的初始尺寸），超时返回 None。
    /// 只用于启动阶段的一次性握手；运行期用 poll/pollAll。
    public func awaitConfigure(timeoutMs: Int64): ?(Int64, Int64) {
        let deadline = Int64(LwpChannel.nowNs()) + timeoutMs * 1000000
        while (Int64(LwpChannel.nowNs()) < deadline) {
            match (ch.recv(LWP_EVENT)) {
                case Some(msg) =>
                    match (decode(msg, -1)) {
                        case Some(LWindowLifecycleEvent.Configure(w, h, _)) => return Some((Int64(w), Int64(h)))
                        // 启动期等待 configure 时同样不能吞掉输入/其它消息（第 90 轮的教训）
                        case _ =>
                            pushBackLwpMessage(msg)
                            continue
                    }
                case None =>
                    let left = (deadline - Int64(LwpChannel.nowNs())) / 1000000
                    if (left <= 0) { break }
                    let _ = ch.wait(LWP_EVENT, Int32(left))
            }
        }
        None
    }

    public func hasPendingConfigure(): Bool {
        pendingConfigureSerial != 0
    }

    public func currentWindowId(): UInt32 {
        windowId
    }

    // ── 解码 ────────────────────────────────────────────────────────────────
    private func decode(m: LwpMessage, nowNs: Int64): ?LWindowLifecycleEvent {
        let b = m.body
        // 注意：match 的 case 常量在仓颉里是绑定模式，必须用 if/else 判等
        if (m.iface == LWP_IFACE_LW_CORE && m.opcode == LWP_LW_CORE_HELLO_OPCODE) {
            // 握手里的能力位只记录状态，不产生事件：引擎不需要「能力变了」的事件，
            // 它在 init 之后直接读 shellCapabilities（否则 pollAll 的调用方都要多处理一条）。
            shellCapabilities = u64at(b, 20)
            return None
        }
        if (m.iface == LWP_IFACE_LW_SEAT && m.opcode == LWP_LW_SEAT_CAPABILITIES_OPCODE) {
            // 与 core 能力位是两套（输入设备 vs 壳功能），分开存
            seatCapabilities = u64at(b, 4)
            return None
        }
        if (m.iface == LWP_IFACE_LW_APP) {
            if (m.opcode == LWP_LW_APP_STARTED_OPCODE) {
                return Some(LWindowLifecycleEvent.AppStarted(u32at(b, 4)))
            }
            if (m.opcode == LWP_LW_APP_RESUMED_OPCODE) { return Some(LWindowLifecycleEvent.AppResumed) }
            if (m.opcode == LWP_LW_APP_PAUSED_OPCODE) { return Some(LWindowLifecycleEvent.AppPaused) }
            return None
        }
        if (m.iface == LWP_IFACE_LW_WINDOW) {
            if (m.opcode == LWP_LW_WINDOW_CREATED_OPCODE) {
                windowId = u32at(b, 4)
                let sc = f32at(b, 8)
                if (sc > 0.0) {
                    reportedScale = sc      // 供 preferredWindowGeometry 换算逻辑尺寸
                }
                return Some(LWindowLifecycleEvent.WindowCreated(windowId, sc, b[12] != 0))
            }
            if (m.opcode == LWP_LW_WINDOW_DRAG_ENTER_OPCODE) {
                let uris = strAt(b, 12)
                return Some(LWindowLifecycleEvent.DragEnter(u32at(b, 4), u32at(b, 8), uris))
            }
            if (m.opcode == LWP_LW_WINDOW_DRAG_MOTION_OPCODE) {
                return Some(LWindowLifecycleEvent.DragMotion(u32at(b, 4), u32at(b, 8)))
            }
            if (m.opcode == LWP_LW_WINDOW_DRAG_LEAVE_OPCODE) {
                return Some(LWindowLifecycleEvent.DragLeave)
            }
            if (m.opcode == LWP_LW_WINDOW_DROP_OPCODE) {
                let uris = strAt(b, 12)
                return Some(LWindowLifecycleEvent.DragDrop(u32at(b, 4), u32at(b, 8), uris))
            }
            if (m.opcode == LWP_LW_WINDOW_CONFIGURE_OPCODE) {
                let w = u32at(b, 4)
                let h = u32at(b, 8)
                let state = u32at(b, 12)
                // configure 必须 ack：记录待确认与截止时间，并**立即自动 ack**
                // （引擎没有“稍后应用尺寸”的需求；延迟 ack 只会让壳回退）
                pendingConfigureSerial = serialSeq
                let now = if (nowNs >= 0) { nowNs } else { Int64(LwpChannel.nowNs()) }
                pendingDeadlineNs = now + LWP_CONFIGURE_TIMEOUT_MS * 1000000
                if (autoAck) {
                    let _ = ackConfigure()
                }
                return Some(LWindowLifecycleEvent.Configure(w, h, state))
            }
            if (m.opcode == LWP_LW_WINDOW_TITLE_BUTTONS_RECT_OPCODE) {
                titleBtnRight = i32at(b, 4)
                titleBtnTop = i32at(b, 8)
                titleBtnWidth = u32at(b, 12)
                titleBtnHeight = u32at(b, 16)
                titleBtnVisible = b[20] != 0
                return Some(LWindowLifecycleEvent.TitleButtonsRect(
                    titleBtnRight, titleBtnTop, titleBtnWidth, titleBtnHeight, titleBtnVisible))
            }
            if (m.opcode == LWP_LW_WINDOW_CLOSE_REQUEST_OPCODE) { return Some(LWindowLifecycleEvent.CloseRequest) }
            if (m.opcode == LWP_LW_WINDOW_FOCUS_OPCODE) { return Some(LWindowLifecycleEvent.Focus(b[4] != 0)) }
            return None
        }
        if (m.iface == LWP_IFACE_LW_FRAME && m.opcode == LWP_LW_FRAME_DONE_OPCODE) {
            pendingFrameSerial = 0   // 收到回调，帧请求闭环
            pendingFrameDeadlineNs = 0
            return Some(LWindowLifecycleEvent.FrameDone(u32at(b, 4), u64at(b, 8)))
        }
        if (m.iface == LWP_IFACE_LW_SURFACE && m.opcode == LWP_LW_SURFACE_FRAME_DONE_OPCODE) {
            pendingFrameSerial = 0
            pendingFrameDeadlineNs = 0
            return Some(LWindowLifecycleEvent.FrameDone(u32at(b, 4), u64at(b, 8)))
        }
        if (m.iface == LWP_IFACE_LW_SURFACE) {
            if (m.opcode == LWP_LW_SURFACE_AVAILABLE_OPCODE) {
                surfaceHandle = u64at(b, 4)
                surfaceWidth = u32at(b, 12)
                surfaceHeight = u32at(b, 16)
                surfaceAlive = true
                surfaceHiddenFlag = false
                return Some(LWindowLifecycleEvent.SurfaceAvailable(surfaceHandle, surfaceWidth, surfaceHeight))
            }
            if (m.opcode == LWP_LW_SURFACE_CHANGED_OPCODE) {
                surfaceWidth = u32at(b, 4)
                surfaceHeight = u32at(b, 8)
                return Some(LWindowLifecycleEvent.SurfaceChanged(surfaceWidth, surfaceHeight))
            }
            if (m.opcode == LWP_LW_SURFACE_WILL_DESTROY_OPCODE) {
                surfaceAlive = false   // 之后不得再 attach / requestFrame（检查器规则）
                surfaceHiddenFlag = false
                return Some(LWindowLifecycleEvent.SurfaceWillDestroy)
            }
            if (m.opcode == LWP_LW_SURFACE_HIDDEN_OPCODE) {
                surfaceHiddenFlag = true
                return Some(LWindowLifecycleEvent.SurfaceHidden)
            }
            return None
        }
        if (m.iface == LWP_IFACE_LW_SYSTEM && m.opcode == LWP_LW_SYSTEM_INFO_OPCODE) {
            let info = (strAt(b, 4), strAt(b, 8), strAt(b, 12), strAt(b, 16), u32at(b, 20))
            systemInfo = info
            return Some(LWindowLifecycleEvent.SystemInfo(info[0], info[1], info[2], info[3], info[4]))
        }
        if (m.iface == LWP_IFACE_LW_TEST) {
            if (m.opcode == LWP_LW_TEST_INJECT_OPCODE) {
                return Some(LWindowLifecycleEvent.TestInject(u32at(b, 4), Int32(u32at(b, 8)), Int32(u32at(b, 12))))
            }
            if (m.opcode == LWP_LW_TEST_CAPTURE_OPCODE) {
                return Some(LWindowLifecycleEvent.TestCapture(strAt(b, 4)))
            }
            if (m.opcode == LWP_LW_TEST_REPLAY_OPCODE) {
                return Some(LWindowLifecycleEvent.TestReplay(strAt(b, 4)))
            }
            return None
        }
        if (m.iface == LWP_IFACE_LW_CLIPBOARD && m.opcode == LWP_LW_CLIPBOARD_TEXT_OPCODE) {
            return Some(LWindowLifecycleEvent.ClipboardText(u32at(b, 4), strAt(b, 8), strAt(b, 12)))
        }
        if (m.iface == LWP_IFACE_LW_DIALOG && m.opcode == LWP_LW_DIALOG_RESULT_OPCODE) {
            return Some(LWindowLifecycleEvent.DialogResult(u32at(b, 4), strAt(b, 8)))
        }
        if (m.iface == LWP_IFACE_LW_DISPLAY && m.opcode == LWP_LW_DISPLAY_INFO_OPCODE) {
            return Some(LWindowLifecycleEvent.DisplayInfo(u32at(b, 4), u32at(b, 8), f32at(b, 12), u32at(b, 16)))
        }
        None
    }
}

/// 读消息体里的 string 字段（u16 off + u16 len，off 相对消息体起点）。
func strAt(b: Array<UInt8>, off: Int64): String {
    let so = Int64(u16at(b, off))
    let sl = Int64(u16at(b, off + 2))
    if (sl <= 0 || so + sl > b.size) {
        return ""
    }
    String.fromUtf8(b[so..so + sl])
}

// ── 小端读取 ────────────────────────────────────────────────────────────────
func i32at(b: Array<UInt8>, off: Int64): Int32 {
    Int32(u32at(b, off))
}

func u64at(b: Array<UInt8>, off: Int64): UInt64 {
    UInt64(u32at(b, off)) | (UInt64(u32at(b, off + 4)) << 32)
}
