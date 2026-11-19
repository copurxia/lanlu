package lanlu_client_next.ui

// P4 对照：CN_UI_BACKEND=lgpu 时，把整棵 UI 树的绘制交给 lgpu（wgpu/Vulkan）。
//
// 工作方式：cui.Renderer 内部有一个可选后端（Canvas）；这里造一个 LgpuCanvas 装上，
// 于是所有图元/文本都走 lgpu，SDL 只保留事件循环与窗口管理。
// 预览缩放：把逻辑尺寸的 UI 缩到小窗口里（LANLU_LGPU_SCALE 覆盖，默认 0.25）。

import std.collection.ArrayList
import std.convert.*
import std.env.getVariable
import std.fs.{exists as fsExists, Path as FsPath, File as FsFile, OpenMode}
import lwindow.backend
import lwindow
import lwindow.{LWindowEventType}
import lwindow.{lwpLog}
import cui.controls.{modalDiagSink}
import cui.desktop.{renderDiagHook}
import cui.{Canvas, Key, MouseButton, SdlWindow, UiEvent, WindowSpec}
import cui
import cui.{ClipboardBackend, clipboardBackend}
import cui.input.{SystemCursor, cursorSink, cursorsEnabled}
import cui.dialogs.{dialogDispatcher, FileDialogOptions, FileDialogRequest, FileDialogResult, resolveDialogBySerial}
import cui.input

/// 上次发给壳的光标形状（255 = 还没决定过），避免每次鼠标移动都发协议
var g_lastCursorShape: UInt32 = 255
/// 当前窗口逻辑尺寸（configure 时更新；边缘热区判定用）
var g_win_w: Int64 = 0
var g_win_h: Int64 = 0
/// 壳上报的系统 UI 缩放（window.created.scale）。逻辑坐标 × 它 = 物理像素。
/// 之前硬编码 1.0，在 PC 模式 200% 缩放下内容只铺满左上 1/4（第 116 轮真机症状）。
var g_ui_scale: Float32 = 1.0
/// 平台三键矩形（物理 px；width=0 表示平台未上报）。docs/lwindow-title-buttons-plan.md
var g_title_btn_right_px: Int64 = 0
var g_title_btn_top_px: Int64 = 0
var g_title_btn_width_px: Int64 = 0
var g_title_btn_height_px: Int64 = 0
var g_title_btn_visible: Bool = false
/// 是否收到过 title_buttons_rect（区分"还没到"和"到了但不可见"）
var g_title_btn_rect_arrived: Bool = false
/// 上次打印的"平台三键宽度"（只在变化时打点，避免每帧刷屏）
var g_title_btn_logged_w: Float32 = -1.0
/// 平台三键默认配置是否已下发（只发一次）
var g_title_btn_cfg_sent: Bool = false
/// 平台三键期望明暗（0=跟随系统 1=light 2=dark）。main.cj 按业务主题写入，
/// 主题切换时重发配置（docs/lwindow-title-buttons-plan.md §2.3 主题联动）。
var g_title_btn_color_mode: UInt32 = 0

public func setPlatformTitleButtonsColorMode(cm: UInt32): Unit {
    g_title_btn_color_mode = cm
}

/// 平台三键占用的逻辑宽度（vp）。>0 表示三键由平台绘制，业务层**不再自绘**、
/// 并在标题栏右侧留出这段宽度。返回 0 = 平台没有三键（Wayland/无装饰平台 → 自绘回退）。
/// 能力位已宣告但矩形还没到时给文档默认宽度（140vp + 8 间距），避免启动期闪一下自绘三键。
public func platformTitleButtonsWidth(): Float32 {
    // 首帧布局时补发默认配置：能力位要到 hello 处理后才可用，
    // 后端安装期可能还没握手完成（install-time 发送只作兜底）。
    if (!g_title_btn_cfg_sent && lwindow.lwpShellProvidesTitleButtons()) {
        g_title_btn_cfg_sent = lwindow.lwpSetTitleButtons(7, 0, 16, 12, 28, g_title_btn_color_mode)
        probeTrace("ui title buttons cfg sent=" + g_title_btn_cfg_sent.toString() +
            " colorMode=" + g_title_btn_color_mode.toString())
    }
    let w = platformTitleButtonsWidthRaw()
    if (w != g_title_btn_logged_w) {
        g_title_btn_logged_w = w
        probeTrace("ui title buttons width=" + w.toString() + "vp selfDrawn=" + (w <= 0.0).toString())
    }
    w
}

/// 三键宽度的决策表（纯函数，可单测）：
///   - 平台不提供三键（能力位未宣告）→ 0 = 业务层自绘回退；
///   - 提供了但 rect 还没到 → 文档默认 148vp（140 三键 + 8 间距），避免启动期闪自绘三键；
///   - rect 已到 → 物理宽 / 密度（缩放用壳上报值，g_ui_scale 启动期可能未初始化）。
public func titleButtonsWidthFor(platformProvides: Bool, rectVisible: Bool, rectWidthPx: Int64,
    scale: Float32, rectArrived!: Bool = true): Float32 {
    if (!platformProvides) {
        return 0.0
    }
    if (rectVisible && rectWidthPx > 0) {
        if (scale > 0.0) {
            return Float32(rectWidthPx) / scale
        }
        return Float32(rectWidthPx)
    }
    // rect 已到但壳明示"不可见"（本应用隐藏了系统装饰条，平台根本画不出三键）：
    // 必须让引擎自绘，否则右侧会留白 148vp 却没有任何按钮（真机表现：右上角空白、
    // 关不掉窗口）。只有"能力已宣告、rect 还没到"才用默认宽度占位。
    if (rectArrived) {
        return 0.0
    }
    return 148.0
}

private func platformTitleButtonsWidthRaw(): Float32 {
    titleButtonsWidthFor(lwindow.lwpShellProvidesTitleButtons(), g_title_btn_visible,
        g_title_btn_width_px, lwindow.lwpReportedScale(), rectArrived: g_title_btn_rect_arrived)
}
/// 最近一次安装的后端画布（联调/抓帧用）。
public var lastCanvas: ?Canvas = None

// ── 对话框桥（P6）：cui.dialogs 的派发钩子 → lw_dialog 协议 ──────────────
// cui.dialogs 侧持有 serial→请求登记；这里只做协议收发，不持状态。
// filters 格式：OHOS DocumentViewPicker 不吃过滤器，原样透传空串即可。
/// 协议暂不支持的对话框 kind（folder）：dispatch 时 pending 尚未登记，
/// 只能把 serial 记下、下一帧（登记完成后）统一回取消。
var g_dialogCancelSerials: ArrayList<UInt32> = ArrayList<UInt32>()

func dispatchDialog(request: FileDialogRequest, kind: String, options: FileDialogOptions): ?UInt32 {
    if (!lwindow.lwpInputEnabled()) {
        return None   // 无壳：回落文件桥
    }
    match (kind) {
        case "open" =>
            // filters 原样透传（OHOS DocumentViewPicker 不消费过滤器；桌面 portal 自行解析）
            Some(UInt32(lwindow.dialogOpenFile(filters: joinFilters(options))))
        case "save" =>
            let suggested = match (options.defaultLocation) {
                case Some(v) => v
                case None => ""
            }
            Some(UInt32(lwindow.dialogSaveFile(suggested)))
        case "folder" =>
            // 协议 v1 没有 folder opcode（core.toml 只有 file_dialog_folder 能力位、无消息），
            // 且 OHOS 壳的文件桥轮询已删（Index.ets M6 第 3 步）——回落文件桥会永久 pending。
            // 预留 serial、下一帧补"取消"回执：UI 表现为用户取消，不卡死。
            // TODO(lwp v2)：补 lw_dialog.open_folder，接壳侧已有的 DocumentSelectMode.FOLDER。
            let serial = lwindow.reserveDialogSerial()
            if (serial == 0) {
                None
            } else {
                g_dialogCancelSerials.add(serial)
                Some(serial)
            }
        case _ =>
            None
    }
}

internal func joinFilters(options: FileDialogOptions): String {
    var joined = ""
    var first = true
    for (filter in options.filters) {
        if (!first) {
            joined = joined + ";"
        }
        first = false
        joined = joined + filter.pattern
    }
    joined
}

/// 交换链当前配置的物理尺寸（px）。surface.changed 只在与它不同时才 resize。
var g_swap_w: Int64 = 0
var g_swap_h: Int64 = 0
/// 已作为 UiEvent.WindowResized 交给 UI 的物理尺寸（px）。0 = 还没发过：
/// 首次取事件时一定发一次，让 UI 视口以**真实 surface 尺寸**为准，
/// 而不是启动期 configure 给的窗口矩形（两者不一定相等，评审 W3）。
var g_ui_size_w: Int64 = 0
var g_ui_size_h: Int64 = 0

/// 诊断开关在启动时读一次（之前每个指针事件做 3~4 次 getVariable）。
let g_probeCursorDbg: Bool = getVariable("LANLU_PROBE_CURSOR_DBG") == Some("1")
let g_probeFocusDbg: Bool = getVariable("LANLU_PROBE_FOCUS_DBG") == Some("1")
let g_probeLgpu: Bool = (getVariable("LANLU_PROBE_LGPU") ?? "0") == "1"
let g_releaseBuild: Bool = (getVariable("LANLU_DEBUGGABLE") ?? "") == "0"

/// 逻辑尺寸 = 物理 / 缩放（统一一处，评审 W5：之前一处存逻辑、一处存物理）
func logicalOf(px: Int64): Int64 {
    let sc = if (g_ui_scale > 0.0) { g_ui_scale } else { 1.0f32 }
    Int64(Float32(px) / sc + 0.5)
}

/// 每次取事件时调用：壳报告的 surface 尺寸与交换链 / UI 视口不一致就同步。
/// 返回需要交给 UI 的 WindowResized（物理 px；DesktopApp 按 window.scale 换算逻辑尺寸）。
func syncSurfaceSize(): ?UiEvent {
    let (sw, sh) = lwindow.lwpSurfaceSize()
    let w = Int64(sw)
    let h = Int64(sh)
    if (w <= 0 || h <= 0) {
        return None
    }
    if (w != g_swap_w || h != g_swap_h) {
        // 只重配 swapchain（resize），**不要**走 configure（会重建 device/pipeline，
        // 真机 20 次 resize 压测第 13 轮后引擎线程卡死，第 53 轮）。
        if (!backend.resizeShellCanvas(w, h)) {
            return None
        }
        g_swap_w = w
        g_swap_h = h
    }
    g_win_w = logicalOf(w)
    g_win_h = logicalOf(h)
    if (w != g_ui_size_w || h != g_ui_size_h) {
        g_ui_size_w = w
        g_ui_size_h = h
        probeTrace("ui viewport <- surface ${w}x${h} px (logical ${g_win_w}x${g_win_h} @${g_ui_scale})")
        return Some(UiEvent.WindowResized(Int32(w), Int32(h)))
    }
    None
}

/// 光标诊断计数（LANLU_PROBE_CURSOR_DBG=1 时限频打点）
var g_cursorDbgCount: Int64 = 0
/// 已打印的事件诊断条数（LANLU_PROBE_FOCUS_DBG=1 时打印前 30 条）
var g_evDbg: Int64 = 0

/// 事件源被调用次数（诊断用）
var g_srcCalls: Int64 = 0

/// 事件类型名（诊断用）
func kindName(k: lwindow.LWindowEventType): String {
    match (k) {
        case lwindow.LWindowEventType.PointerDown => "down"
        case lwindow.LWindowEventType.PointerMove => "move"
        case lwindow.LWindowEventType.PointerUp => "up"
        case lwindow.LWindowEventType.PointerAxis => "axis"
        case lwindow.LWindowEventType.Key => "key"
        case _ => "other"
    }
}

/// LWP 轮询计数（限频打通道统计日志用；必须在首次使用前声明）
private var lwpPollCount: Int64 = 0

/// 壳请求关闭窗口（window.close_request）→ 下一次取事件时返回 UiEvent.Quit
private var lwpQuitRequested: Bool = false



/// 待投递的合成事件（按键自带文本时，先插入文本再处理按键）。
private let g_uiPending = ArrayList<UiEvent>()
/// 输入法组合中（收到过 preedit 且尚未 commit/清空）：此时键事件不再产生文本，
/// 文本一律由输入法的 commit_string 提供（否则拼音期间按字母会直接落字）。
private var g_preeditActive: Bool = false

/// 键事件的修饰键位里"命令键"的掩码（LWP_KEY_MODIFIERS_*，与 SDL_KMOD_* 同值）：
/// 这些按下时按键是快捷键而不是文本。
private let KEY_MOD_COMMAND_MASK: UInt16 = 0x0FC0   // LCTRL|RCTRL|LALT|RALT|LGUI|RGUI = 4032

/// 取出一条待投递的合成事件。
/// 组合态事件：更新标志位并返回事件（match 分支里不能直接赋值）。
private func preeditUi(text: String, cursor: Int64): UiEvent {
    g_preeditActive = text.size > 0
    UiEvent.TextEditing(text, cursor)
}

/// 上屏事件：组合态结束。
private func commitUi(text: String): UiEvent {
    g_preeditActive = false
    UiEvent.TextInput(text)
}

private func takePendingUi(): ?UiEvent {
    if (g_uiPending.size == 0) {
        return None
    }
    let e = g_uiPending[0]
    g_uiPending.remove(at: 0)
    Some(e)
}


public func probeTrace(line: String): Unit {
    // LANLU_LWP=1：日志走协议（壳转 hilog）。联调期（LANLU_PROBE_LGPU=1）**同时**落文件，
    // 因为壳侧 stderr 未必进 hilog —— 不能把唯一的诊断手段押在一条未验证的通道上。
    let sent = lwpLog(1, line)
    if (sent && !g_probeLgpu) {
        return
    }
    // release 构建（ArkTS 注入 LANLU_DEBUGGABLE=0）不落探针文件：
    // 与 lanlu_env.txt 同一条门禁（计划 §11 风险记录）。未设置时按开发环境处理。
    if (g_releaseBuild || !g_probeLgpu) {
        return
    }
    let home = getVariable("HOME") ?? "."
    let path = FsPath(home + "/probe_trace.txt")
    // 追加写：之前每行都把整个文件读出再整体写回（O(n²)，渲染线程上越跑越慢）
    try {
        let f = FsFile(path, OpenMode.Append)
        f.write((line + String.fromUtf8(Array<UInt8>(1, repeat: 10))).toArray())
        f.close()
    } catch (_) {}
}


public func installLgpuBackendIfRequested(apply: (Canvas) -> Unit): Bool {
    // P5：引擎现在由壳层在 libmain 加载时自启动，可能早于 ArkTS 设置环境变量。
    // 这里最多等 5 秒让 CN_UI_BACKEND 就绪（onCreate 里设置，通常 <1 秒）。
    // 后端默认就是 lgpu：SDL 壳已删除，`CN_UI_BACKEND` 不再由任何一侧设置。
    // 保留读取只是为了兼容旧脚本显式指定；空值时不再空转等 5 秒。
    var backend = getVariable("CN_UI_BACKEND") ?? ""
    if (backend.size == 0) {
        backend = "lgpu"
    }
    let envWait = 0
    // P6：对话框平台派发（lw_dialog 协议）。必须先于任何 return 注册：
    // 对话框不依赖渲染后端，LWP 未启用时派发器内部回落文件桥。
    dialogDispatcher = Some(dispatchDialog)
    probeTrace("backend mode=" + backend + " waited=" + envWait.toString())
    probeTrace("lwp trace env=" + (getVariable("LANLU_LWP_TRACE") ?? "<unset>"))
    if (backend != "lgpu") {
        return false
    }
    // LANLU_LWP=1：surface 句柄与尺寸由协议下发（surface.available），
    // 不再轮询环境变量。有界等待（3s）：壳没起来就回落到旧路径。
    if (lwindow.lwpInputEnabled()) {
        match (lwindow.lwpAwaitSurface(3000)) {
            case Some((handle, w, h)) =>
                probeTrace("lwp surface from protocol handle=${handle} ${w}x${h}")
                g_swap_w = w
                g_swap_h = h
                // lgpu 细节（Surface/字体/缩放）收敛在 lwindow.backend（全仓唯一 lgpu 消费方）
                match (backend.createSurfaceCanvas(handle, w, h, lwindow.lwpReportedScale())) {
                    case Some(canvasL) =>
                        // 协议路径同样要同步 g_ui_scale：否则逻辑尺寸/边缘热区按 1x 计算
                        // （真机 probe：uiScale=1.0 logical=2090x1394）
                        if (lwindow.lwpReportedScale() > 0.0) {
                            g_ui_scale = lwindow.lwpReportedScale()
                        }
                        probeTrace("lwp canvas scale=${lwindow.lwpReportedScale()} (物理 ${w}x${h})")
                        lastCanvas = Some(canvasL)
                        // 与 env 路径同样要把 canvas 交给 UI 层并挂上纹理回调；
                        // 少这一步的表现是 beginScene 抛「需要渲染后端」并崩进程。
                        cui.texturePixelsSink = {id, w, h, pixels => canvasL.uploadTexture(id, w, h, pixels)}
                        // R4：纹理关闭时真正回收 lgpu 侧纹理（显存预算生效的前提）
                        cui.textureReleaseSink = {id => canvasL.releaseTexture(id)}
                        apply(canvasL)
                        probeTrace("lwp canvas 已安装 ${w}x${h}")
                        return true
                    case None =>
                        probeTrace("lwp surface: 没有可用字体，回落到旧路径")
                }
            case None =>
                probeTrace("lwp surface 未在 3s 内到达，回落环境变量路径")
        }
    }
    // 等 ArkTS 把整窗 surfaceId 写进进程环境（最多 15 秒）。
    // 必须优先等 LANLU_MAIN_SURFACE_ID：测试小窗（LANLU_SURFACE_ID）会先就绪，
    // 过早回退会导致后端画到 240x160 的小窗上。
    var sidText = getVariable("LANLU_MAIN_SURFACE_ID") ?? ""
    var waited = 0
    while (sidText.size == 0 && waited < 150) {
        sleep(Duration.millisecond * 100)
        waited++
        sidText = getVariable("LANLU_MAIN_SURFACE_ID") ?? ""
    }
    if (sidText.size == 0) {
        // 兜底：没有整窗时用测试小窗（仅调试）
        sidText = getVariable("LANLU_SURFACE_ID") ?? ""
    }
    if (sidText.size == 0) {
        return false
    }
    var sid: Int64 = 0
    try {
        sid = Int64.parse(sidText)
    } catch (_) {
        return false
    }
    let isMain = (getVariable("LANLU_MAIN_SURFACE_ID") ?? "").size > 0
    var surfW: Int64 = 240
    var surfH: Int64 = 160
    if (isMain) {
        try { surfW = Int64.parse(getVariable("LANLU_MAIN_W") ?? "0") } catch (_) {}
        try { surfH = Int64.parse(getVariable("LANLU_MAIN_H") ?? "0") } catch (_) {}
        if (surfW <= 0 || surfH <= 0) {
            surfW = 2090
            surfH = 1394
        }
    }
    // lgpu 细节（Surface/字体/缩放）收敛在 lwindow.backend（全仓唯一 lgpu 消费方）
    let scale0: Float32 = if (isMain) { lwindow.lwpReportedScale() } else { 0.25 }
    let canvasOpt = backend.createSurfaceCanvas(sid, surfW, surfH, scale0)
    g_swap_w = surfW
    g_swap_h = surfH
    // 文本垂直居中口径校准探针的字体度量改由 backend 持有（g_fontForMetrics 移除）。
    probeTrace("install main=" + isMain.toString() + " sid=" + sid.toString() + " " + surfW.toString() + "x" + surfH.toString())
    match (canvasOpt) {
        case Some(canvas) =>
    // 缩放优先级：LANLU_LGPU_SCALE（调试）> 壳上报的 density > 1.0
    var scale = scale0
    // g_ui_scale 只由 WindowCreated 事件更新，而该事件可能在启动期被 lwpAwait* 消费；
    // 这里用客户端上报值兜底，避免边缘热区/三键宽度按 1x 计算（第 116 轮同类问题）。
    if (isMain && scale > 0.0) {
        g_ui_scale = scale
    }
    match (getVariable("LANLU_LGPU_SCALE")) {
        case Some(v) =>
            try {
                scale = Float32.parse(v)
            } catch (_) {}
        case None => ()
    }
    backend.setShellCanvasScale(scale)
    if ((getVariable("LANLU_MAIN_PROBE_FILL") ?? "0") == "1") {
        backend.setShellCanvasForceClearRed(true)
    }
    // 纹理委派：SDL 纹理创建/更新时把 RGBA 像素送给 lgpu 后端
    cui.texturePixelsSink = {id, w, h, pixels => canvas.uploadTexture(id, w, h, pixels)}
    // R4：纹理关闭时真正回收 lgpu 侧纹理（显存预算生效的前提）
    cui.textureReleaseSink = {id => canvas.releaseTexture(id)}
    apply(canvas)
    lastCanvas = Some(canvas)
    return true
        case None =>
            probeTrace("backend: 没有可用字体，安装失败")
            return false
    }
}

/// P5：用 L 层窗口 + lgpu 后端替代 SDL 窗口。
/// 返回 null 表示未启用（CN_WINDOW != lgpu）。
public func makeHeadlessWindow(spec: WindowSpec): ?SdlWindow {
    if ((getVariable("CN_WINDOW") ?? "sdl") != "lgpu") {
        return None
    }
    let window = SdlWindow.headless(spec)
    // 事件源：L 层输入桥（文件通道）→ UiEvent
    // 光标形状：cui 决定「要什么形状」-> 平台层（LWP lw_seat.set_cursor）
    if (lwindow.lwpInputEnabled()) {
        cursorSink = { kind =>
            let code: UInt32 = match (kind) {
                case SystemCursor.Default => 0
                case SystemCursor.Text => 1
                case SystemCursor.Pointer => 2
                case SystemCursor.Wait => 3
                case SystemCursor.Progress => 3
                case SystemCursor.Crosshair => 4
                case SystemCursor.Move => 5
                case SystemCursor.NotAllowed => 6
                case SystemCursor.EwResize => 7
                case SystemCursor.NsResize => 8
                case SystemCursor.NwseResize => 9
                case SystemCursor.NeswResize => 10
                case SystemCursor.NwResize => 9
                case SystemCursor.SeResize => 9
                case SystemCursor.NeResize => 10
                case SystemCursor.SwResize => 10
                case SystemCursor.EResize => 7
                case SystemCursor.WResize => 7
                case SystemCursor.NResize => 8
                case SystemCursor.SResize => 8
                case _ => 0
            }
            let _ = lwindow.lwpSetCursorShape(code)
        }
    }

    // 联调探针：直接发一次 IME 光标矩形，验证编码与通道（LANLU_PROBE_IMERECT=1）
    if (getVariable("LANLU_PROBE_IMERECT") == Some("1")) {
        try {
            let ok = lwindow.lwpImeSetCursorRect(10, 20, 2, 18)
            probeTrace("probe ime rect -> " + ok.toString())
        } catch (e: Exception) {
            probeTrace("probe ime rect threw: " + e.message)
        }
    }

    // Modal 遮罩诊断：把遮罩尺寸交给 probe_trace（排查"弹窗背景缺失/错位"）
    if (getVariable("LANLU_PROBE_MODAL") == Some("1")) {
        modalDiagSink = { line => probeTrace(line) }
    }

    // 联调探针：强制设一次光标形状，用来验证「引擎 -> 壳 -> 系统光标」整条链路
    if (getVariable("LANLU_PROBE_CURSOR") == Some("1")) {
        let ok = lwindow.lwpSetCursorShape(1)   // 1 = 文本光标
        probeTrace("probe cursor shape=1 -> " + ok.toString())
    }

    // IME 候选框定位：cui 算出光标矩形 -> 平台层（LWP text_input.set_cursor_rect）
    // 光标周围文本（text-input-v3 set_surrounding）：输入法联想/删除上下文。
    // 只在框架报告时转发（Frame 里判重由 sink 自身频率决定，框架每帧一次）。
    if (lwindow.lwpInputEnabled()) {
        cui.textSurroundingSink = { value: String, caret: Int64, anchor: Int64 =>
            let _ = lwindow.lwpImeSetSurrounding(value, UInt32(max(0, caret)), UInt32(max(0, anchor)))
        }
    }
    if (lwindow.lwpInputEnabled()) {
        cui.textInputAreaSink = { rect =>
            let ok = lwindow.lwpImeSetCursorRect(
                Int32(rect.x), Int32(rect.y), Int32(rect.w), Int32(rect.h))
            if (g_probeFocusDbg) {
                probeTrace("ime sink rect=" + Int64(rect.x).toString() + "," + Int64(rect.y).toString() +
                    " " + Int64(rect.w).toString() + "x" + Int64(rect.h).toString() + " ok=" + ok.toString())
            }
        }
    }

    // 空闲渲染诊断（LANLU_PROBE_IDLE=1 时引擎把"为什么还要画"写进 probe_trace）
    renderDiagHook = { line => probeTrace(line) }
    // R6：空闲等待改阻塞在 LWP 通道上（空闲零唤醒，替代 4ms 忙轮询）。
    // 只有协议通道可用时才注入：否则 wait 会立即返回 false，等于把忙轮询换成空转。
    if (lwindow.lwpInputEnabled()) {
        cui.eventWaitSource = Some({ms => lwindow.lwpWaitForEvents(ms)})
        cui.eventWakeSink = Some({=> lwindow.lwpWakeEventWaiter()})
    }
    cui.headlessEventSource = Some({ =>
        // 输入源二选一（过渡期）：LANLU_LWP=1 走协议通道，否则走文件桥
        if (lwindow.lwpInputEnabled()) {
            g_srcCalls++
            match (lwindow.nextLwpEvent()) {
                case Some(ev) =>
                    if (g_probeCursorDbg && g_srcCalls % 50 == 1) {
                        probeTrace("src call=" + g_srcCalls.toString() + " kind=" + kindName(ev.kind))
                    }
                    // 诊断（LANLU_PROBE_FOCUS_DBG=1）：按下时打点命中与焦点，定位"搜索框拿不到焦点"
                    if (g_probeFocusDbg && g_evDbg < 30) {
                        g_evDbg++
                        probeTrace("ev dbg kind=" + kindName(ev.kind) + " x=" + Int64(ev.x).toString() +
                            " y=" + Int64(ev.y).toString() + " focus=" + cui.debugFocusId)
                    }
                    if (ev.kind == lwindow.LWindowEventType.PointerDown &&
                        g_probeFocusDbg) {
                        probeTrace("focus dbg down=" + Int64(ev.x).toString() + "," +
                            Int64(ev.y).toString() + " focusId=" + cui.debugFocusId)
                    }
                    // 指针形状：移动时判断是否落在文本框内，变了才发（不刷协议）
                    if (ev.kind == lwindow.LWindowEventType.PointerMove) {
                        // 诊断（LANLU_PROBE_CURSOR_DBG=1）：确认分支执行与发送结果
                        if (g_probeCursorDbg) {
                            g_cursorDbgCount++
                            if (g_cursorDbgCount % 30 == 1) {
                                let hit = match (cui.lastTextInputRect) {
                                    case Some(r) => "rect"
                                    case None => "none"
                                }
                                probeTrace("cursor dbg #\${g_cursorDbgCount} move=\${Int64(ev.x)},\${Int64(ev.y)} text=\${hit}")
                            }
                        }
                        match (cui.lastTextInputRect) {
                            case Some(r) =>
                                let want = lwindow.lwpCursorShapeForPoint(
                                    r.x, r.y, r.w, r.h, ev.x, ev.y, true)
                                if (want != g_lastCursorShape) {
                                    g_lastCursorShape = want
                                    let _ = lwindow.lwpSetCursorShape(want)
                                }
                            case None =>
                                if (g_lastCursorShape != 0) {
                                    g_lastCursorShape = 0
                                    let _ = lwindow.lwpSetCursorShape(0)
                                }
                        }
                    }
                    return Some(lwpEventToUi(ev))
                case None => return None
            }
        }
        // M6 第 1 步：文件桥输入已删除；协议不可用时没有输入源，直接返回空。
        None
    })
    return window
}
/// P5：headless 窗口的输入源——把 L 层事件桥映射成 UiEvent。
/// 必须在创建 headless 窗口之前调用（DesktopApp 内部读 CN_WINDOW）。
public func installHeadlessInputSource(): Unit {
    // 窗口控制：headless 下交给平台层（写命令文件，ArkTS 轮询执行）
    cui.headlessWindowCommand = Some({command => lwindow.requestWindowCommand(command)})
    // 剪贴板：SDL 在真机读不到系统剪贴板，改走 L 层（文件通道 + ArkTS pasteboard）
    clipboardBackend = LWindowClipboard()

    // 无 SDL 窗口：鼠标样式由 L 层负责
    cursorsEnabled = false
    let windowMode = if (lwindow.lwpInputEnabled()) { "lgpu" } else { getVariable("CN_WINDOW") ?? "sdl" }
    if (windowMode != "lgpu") {
        return
    }
    // LANLU_LWP=1：先初始化通道（含与壳的握手），失败则退回文件桥
    if (lwindow.lwpInputEnabled()) {
        if (!lwindow.initLwpInput()) {
            probeTrace("lwp: init 失败，回退文件桥")
        } else {
            probeTrace("lwp: 通道已就绪 " + lwindow.lwpStatsLine())
            // 告知壳引擎已就绪：之后壳可经 lw_test 注入测试动作/抓帧（计划 §16）
            let _ = lwindow.lwpSendTestReady()

        }
    }
    // 光标形状：cui 决定「要什么形状」-> 平台层（LWP lw_seat.set_cursor）
    if (lwindow.lwpInputEnabled()) {
        cursorSink = { kind =>
            let code: UInt32 = match (kind) {
                case SystemCursor.Default => 0
                case SystemCursor.Text => 1
                case SystemCursor.Pointer => 2
                case SystemCursor.Wait => 3
                case SystemCursor.Progress => 3
                case SystemCursor.Crosshair => 4
                case SystemCursor.Move => 5
                case SystemCursor.NotAllowed => 6
                case SystemCursor.EwResize => 7
                case SystemCursor.NsResize => 8
                case SystemCursor.NwseResize => 9
                case SystemCursor.NeswResize => 10
                case SystemCursor.NwResize => 9
                case SystemCursor.SeResize => 9
                case SystemCursor.NeResize => 10
                case SystemCursor.SwResize => 10
                case SystemCursor.EResize => 7
                case SystemCursor.WResize => 7
                case SystemCursor.NResize => 8
                case SystemCursor.SResize => 8
                case _ => 0
            }
            let _ = lwindow.lwpSetCursorShape(code)
        }
    }

    // 联调探针：直接发一次 IME 光标矩形，验证编码与通道（LANLU_PROBE_IMERECT=1）
    if (getVariable("LANLU_PROBE_IMERECT") == Some("1")) {
        try {
            let ok = lwindow.lwpImeSetCursorRect(10, 20, 2, 18)
            probeTrace("probe ime rect -> " + ok.toString())
        } catch (e: Exception) {
            probeTrace("probe ime rect threw: " + e.message)
        }
    }

    // Modal 遮罩诊断：把遮罩尺寸交给 probe_trace（排查"弹窗背景缺失/错位"）
    if (getVariable("LANLU_PROBE_MODAL") == Some("1")) {
        modalDiagSink = { line => probeTrace(line) }
    }

    // 联调探针：强制设一次光标形状，用来验证「引擎 -> 壳 -> 系统光标」整条链路
    if (getVariable("LANLU_PROBE_CURSOR") == Some("1")) {
        let ok = lwindow.lwpSetCursorShape(1)   // 1 = 文本光标
        probeTrace("probe cursor shape=1 -> " + ok.toString())
    }

    // IME 候选框定位：cui 算出光标矩形 -> 平台层（LWP text_input.set_cursor_rect）
    if (lwindow.lwpInputEnabled()) {
        cui.textInputAreaSink = { rect =>
            let ok = lwindow.lwpImeSetCursorRect(
                Int32(rect.x), Int32(rect.y), Int32(rect.w), Int32(rect.h))
            if (g_probeFocusDbg) {
                probeTrace("ime sink rect=" + Int64(rect.x).toString() + "," + Int64(rect.y).toString() +
                    " " + Int64(rect.w).toString() + "x" + Int64(rect.h).toString() + " ok=" + ok.toString())
            }
        }
    }

    // R6：空闲等待改阻塞在 LWP 通道上（空闲零唤醒，替代 4ms 忙轮询）。
    // 只有协议通道可用时才注入：否则 wait 会立即返回 false，等于把忙轮询换成空转。
    if (lwindow.lwpInputEnabled()) {
        cui.eventWaitSource = Some({ms => lwindow.lwpWaitForEvents(ms)})
        cui.eventWakeSink = Some({=> lwindow.lwpWakeEventWaiter()})
    }
    cui.headlessEventSource = Some({ =>
        if (lwindow.lwpInputEnabled()) {
            // 0) 协议不支持的对话框（folder）：dispatch 时 pending 尚未登记，
            //    这里（登记完成后）补一条取消回执，避免调用方永久 pending。
            if (g_dialogCancelSerials.size > 0) {
                for (s in g_dialogCancelSerials) {
                    let _ = resolveDialogBySerial(s, FileDialogResult.FileDialogCanceled)
                    probeTrace("dialog unsupported kind -> canceled serial=${s}")
                }
                g_dialogCancelSerials.clear()
            }
            // 1) 生命周期事件：必须用 lwindow 内部的**同一个**客户端消费，
            //    否则两个客户端会抢同一条队列（configure 可能被另一个吃掉）。
            for (ev in lwindow.lwpDrainLifecycle()) {
                match (ev) {
                    case lwindow.LWindowLifecycleEvent.Configure(w, h, _) =>
                        probeTrace("lwp configure ${w}x${h} (已自动 ack)")
                    case lwindow.LWindowLifecycleEvent.WindowCreated(id, scale, _) =>
                        probeTrace("lwp window created id=${id} scale=${scale}")
                        if (scale > 0.0 && scale != g_ui_scale) {
                            g_ui_scale = scale
                            g_ui_size_w = 0   // 缩放变了：强制重发一次视口
                            // canvas 可能已建好：立刻用新 scale（下一帧起生效）
                            backend.setShellCanvasScale(scale)
                        }
                    case lwindow.LWindowLifecycleEvent.DialogResult(serial, path) =>
                        // P6 对话框结果：OHOS 壳 picker 完成/取消后经协议回填
                        let value: FileDialogResult = if (path.isEmpty()) {
                            FileDialogResult.FileDialogCanceled
                        } else {
                            // 多路径分隔符以壳为准：OHOS ArkTS 用 ';'（Index.ets: split('\n').join(';')），
                            // 兼容历史 '\n' 拼法 —— 先归一再拆；单选 = 单路径。
                            let paths = path.replace("\n", ";").split(";")
                            FileDialogResult.FileDialogSelected(paths, Some(0))
                        }
                        let matched = resolveDialogBySerial(serial, value)
                        probeTrace("lw dialog result serial=${serial} matched=${matched} path=${path}")
                    case lwindow.LWindowLifecycleEvent.TitleButtonsRect(right, top, w, hh, vis) =>
                        // 平台三键矩形（窗口局部 px）：业务层据此避让，不再自绘三键
                        g_title_btn_right_px = Int64(right)
                        g_title_btn_top_px = Int64(top)
                        g_title_btn_width_px = Int64(w)
                        g_title_btn_height_px = Int64(hh)
                        g_title_btn_visible = vis
                        g_title_btn_rect_arrived = true
                        probeTrace("lwp title buttons " + Int64(w).toString() + "x" + Int64(hh).toString() + "px right=" + Int64(right).toString() + " top=" + Int64(top).toString() + " visible=" + vis.toString())
                    case lwindow.LWindowLifecycleEvent.CloseRequest =>
                        // 对应 xdg_toplevel.close：引擎可以拒绝（这里按桌面应用的默认行为退出）
                        probeTrace("lwp close request -> quit")
                        lwpQuitRequested = true
                    case lwindow.LWindowLifecycleEvent.SurfaceAvailable(h, w, hh) =>
                        // 平台三键默认配置（只在首次发一次）：全显、右上、margin/spacing/size
                        // 取 OHOS 合法区间内的值；壳按能力位自行 clamp/忽略。
                        if (!g_title_btn_cfg_sent && lwindow.lwpShellProvidesTitleButtons()) {
                            g_title_btn_cfg_sent = lwindow.lwpSetTitleButtons(7, 0, 16, 12, 28, 0)
                        }
                        // 启动时的初始尺寸也要记下来：边缘热区判定依赖 g_win_w/g_win_h，
                        // 之前只在 surface.changed（resize）里赋值 → 拖边永远判定失败（第 116 轮修）
                        // 边缘热区用**逻辑**尺寸（指针坐标已转逻辑，见 backend_lwp 解码）
                        g_win_w = logicalOf(Int64(w))
                        g_win_h = logicalOf(Int64(hh))
                        probeTrace("lwp surface available handle=${h} ${w}x${hh} uiScale=${g_ui_scale} logical=${Int64(Float32(w) / g_ui_scale)}x${Int64(Float32(hh) / g_ui_scale)}")
                    case lwindow.LWindowLifecycleEvent.SurfaceChanged(w, hh) =>
                        // 真正的同步在下面 syncSurfaceSize()：以客户端记录的 surface 尺寸为准，
                        // 同时重配交换链**并**把 WindowResized 交给 UI（之前只 resize 交换链，
                        // UI 视口停在启动尺寸 —— 缩放后画面裁切/留黑的根因，评审 W1）。
                        probeTrace("lwp surface changed ${w}x${hh}")
                    // 拖放：壳已解码 uri 为本地路径。业务语义（拖到书库=导入？）待产品决定，
                    // 这里只做接收与打点，避免"协议通了但没人接"的老问题。
                    case lwindow.LWindowLifecycleEvent.DragEnter(x, y, uris) =>
                        probeTrace("dnd enter " + Int64(x).toString() + "," + Int64(y).toString() +
                            " uris=" + uris)
                    case lwindow.LWindowLifecycleEvent.DragMotion(x, y) =>
                        discardMotionForDnd(x, y)
                    case lwindow.LWindowLifecycleEvent.DragLeave =>
                        probeTrace("dnd leave")
                    case lwindow.LWindowLifecycleEvent.DragDrop(x, y, uris) =>
                        probeTrace("dnd drop " + Int64(x).toString() + "," + Int64(y).toString() +
                            " uris=" + uris)
                    case lwindow.LWindowLifecycleEvent.FrameDone(serial, _) =>
                        // 壳的 vsync 会合并请求；记账后 pending 才能正确清零
                        lwindow.lwpNoteFrameDone(serial)
                    case lwindow.LWindowLifecycleEvent.SurfaceWillDestroy =>
                        probeTrace("lwp surface will_destroy")
                    case lwindow.LWindowLifecycleEvent.SurfaceHidden =>
                        probeTrace("lwp surface hidden")
                    case lwindow.LWindowLifecycleEvent.SystemInfo(tz, lang, fonts, home, api) =>
                        probeTrace("lwp system tz=${tz} lang=${lang} api=${api} fonts=${fonts} home=${home}")
                    case lwindow.LWindowLifecycleEvent.TestInject(k, a, bb) =>
                        probeTrace("lwp test inject kind=${k} a=${a} b=${bb}")
                    case lwindow.LWindowLifecycleEvent.TestReplay(path) =>
                        // 回放：把录制里的壳侧消息重新入队（liblwp 的 lwp_trace_replay）
                        let n = lwindow.lwpReplayTrace(path)
                        probeTrace("lwp test replay " + path + " -> " + n.toString() + " 条")
                    case lwindow.LWindowLifecycleEvent.TestCapture(path) =>
                        // 壳要求抓帧（真机无 ADB 时用）：直接走已有抓帧能力
                        match (lastCanvas) {
                            case Some(c) =>
                                let rc = c.captureTo(path)
                                probeTrace("lwp test capture -> " + path + " rc=" + rc.toString())
                            case None => probeTrace("lwp test capture: 没有 canvas")
                        }
                    case lwindow.LWindowLifecycleEvent.Focus(f) =>
                        // 焦点目前只做记录：窗口焦点由 XComponent 的 onFocus 提供，
                        // 协议事件是给未来“多窗口/浮层”用的信息来源（计划 §7）
                        probeTrace("lwp focus=${f}")
                    case _ => ()
                }
            }
            match (takePendingUi()) {
                case Some(pending) => return Some(pending)
                case None => ()
            }
            if (lwpQuitRequested) {
                lwpQuitRequested = false
                return Some(UiEvent.Quit)
            }
            match (syncSurfaceSize()) {
                case Some(resized) => return Some(resized)
                case None => ()
            }
            let _ = lwindow.lwpCheckConfigureTimeout()
            lwpPollCount++
            // 每 300 次取事件打一行通道统计（真机排障用，计划 §16.7）
            if (lwpPollCount % 300 == 0) {
                let line = lwindow.lwpStatsLine()
                if (line.size > 0) {
                    probeTrace("lwp stats " + line)
                }
            }
            g_srcCalls++
            match (lwindow.nextLwpEvent()) {
                case Some(ev) =>
                    if (g_probeCursorDbg && g_srcCalls % 50 == 1) {
                        probeTrace("src call=" + g_srcCalls.toString() + " kind=" + kindName(ev.kind))
                    }
                    // 诊断（LANLU_PROBE_FOCUS_DBG=1）：按下时打点命中与焦点，定位"搜索框拿不到焦点"
                    if (g_probeFocusDbg && g_evDbg < 30) {
                        g_evDbg++
                        probeTrace("ev dbg kind=" + kindName(ev.kind) + " x=" + Int64(ev.x).toString() +
                            " y=" + Int64(ev.y).toString() + " focus=" + cui.debugFocusId)
                    }
                    if (ev.kind == lwindow.LWindowEventType.PointerDown &&
                        g_probeFocusDbg) {
                        probeTrace("focus dbg down=" + Int64(ev.x).toString() + "," +
                            Int64(ev.y).toString() + " focusId=" + cui.debugFocusId)
                    }
                    // 边缘按下 = 开始缩放（无边框窗口没有系统装饰，必须自己给热区）
                    // 只有左键拖边才缩放（右键/中键按在边缘不应进入缩放会话）
                    if (ev.kind == lwindow.LWindowEventType.PointerDown && ev.key == 0 && g_win_w > 0) {
                        const EDGE: Float32 = 8.0
                        var edges: UInt32 = 0
                        if (ev.y <= EDGE) { edges = edges | 1 }
                        if (ev.y >= Float32(g_win_h) - EDGE) { edges = edges | 2 }
                        if (ev.x <= EDGE) { edges = edges | 4 }
                        if (ev.x >= Float32(g_win_w) - EDGE) { edges = edges | 8 }
                        if (edges != 0) {
                            let _ = lwindow.lwpBeginResize(edges)
                        }
                    }
                    // 指针形状：移动时判断是否落在文本框内，变了才发（不刷协议）
                    if (ev.kind == lwindow.LWindowEventType.PointerMove) {
                        // 诊断（LANLU_PROBE_CURSOR_DBG=1）：确认分支执行与发送结果
                        if (g_probeCursorDbg) {
                            g_cursorDbgCount++
                            if (g_cursorDbgCount % 30 == 1) {
                                let hit = match (cui.lastTextInputRect) {
                                    case Some(r) => "rect"
                                    case None => "none"
                                }
                                probeTrace("cursor dbg #\${g_cursorDbgCount} move=\${Int64(ev.x)},\${Int64(ev.y)} text=\${hit}")
                            }
                        }
                        match (cui.lastTextInputRect) {
                            case Some(r) =>
                                let want = lwindow.lwpCursorShapeForPoint(
                                    r.x, r.y, r.w, r.h, ev.x, ev.y, true)
                                if (want != g_lastCursorShape) {
                                    g_lastCursorShape = want
                                    let _ = lwindow.lwpSetCursorShape(want)
                                }
                            case None =>
                                if (g_lastCursorShape != 0) {
                                    g_lastCursorShape = 0
                                    let _ = lwindow.lwpSetCursorShape(0)
                                }
                        }
                    }
                    return Some(lwpEventToUi(ev))
                case None => return None
            }
        }
        // M6 第 1 步：文件桥输入已删除，这里不再有回落路径。
        // LANLU_LWP=0 只影响渲染（走环境变量 surface），输入已无退路 —— 协议是唯一入口。
        None
    })
}

/// 联调：延迟 5 秒触发一次窗口命令（验证 L 层窗口控制通道）。
public func installLgpuProbeWindowCommand(command: String): Unit {
    spawn {
        sleep(Duration.second * 5)
        lwindow.requestWindowCommand(command)
    }
}

/// 壳层传来的按键名 → Key 枚举。
func keyFromName(name: String): Key {
    match (name) {
        case "Escape" => Key.Escape
        case "Backspace" => Key.Backspace
        case "Enter" => Key.Enter
        case "Tab" => Key.Tab
        case "Delete" => Key.Delete
        case "Space" => Key.Space
        case "Home" => Key.Home
        case "End" => Key.End
        case "Left" => Key.Left
        case "Right" => Key.Right
        case "Up" => Key.Up
        case "Down" => Key.Down
        case _ =>
            if (name.size == 1) {
                Key.Letter(UInt8(name.toArray()[0]))
            } else {
                Key.RawScancode(0)
            }
    }
}

/// L 层剪贴板后端（引擎 → ArkTS → OHOS pasteboard）。
class LWindowClipboard <: ClipboardBackend {
    public func setText(text: String): Unit {
        lwindow.clipboardSetText(text)
    }

    public func getText(): String {
        lwindow.clipboardGetText()
    }

    public func hasText(): Bool {
        lwindow.clipboardHasText()
    }
}

/// 协议键码 -> Key 枚举。
/// 计划 §6.1 要求「单表键码」：这里先用 Linux evdev 码（与 wayland/xkb 一致），
/// 鸿蒙侧由壳负责把 HarmonyOS keyCode 映射到同一张表；未覆盖的落到 RawScancode。
/// evdev 键码 -> cui Key。**全仓唯一**的键码表（计划 §6.1）：壳只发 evdev，
/// 引擎不猜字符——字符走键事件自带的 utf8。字母用大写 ASCII（与 LETTER_A=65、SDL 路径一致）。
public func keyFromCode(code: Int32): Key {
    match (code) {
        case 1 => Key.Escape
        case 14 => Key.Backspace
        case 15 => Key.Tab
        case 28 => Key.Enter
        case 57 => Key.Space
        case 102 => Key.Home
        case 107 => Key.End
        case 111 => Key.Delete
        case 103 => Key.Up
        case 105 => Key.Left
        case 106 => Key.Right
        case 108 => Key.Down
        case _ =>
            if (code >= 2 && code <= 11) {
                // evdev 2..10 = 1..9，11 = 0
                Key.Digit(UInt8(UInt32(48) + UInt32((code + 8) % 10)))   // 0x30 = '0'
            } else if (code >= 16 && code <= 25) {
                Key.Letter(UInt8(UInt32(65) + UInt32(evdevLetterIndex(code))))
            } else if (code >= 30 && code <= 38) {
                // evdev 30..38 = A S D F G H J K L
                Key.Letter(UInt8(UInt32(65) + UInt32(code - 30 + 8)))
            } else if (code >= 44 && code <= 50) {
                // evdev 44..50 = Z X C V B N M
                Key.Letter(UInt8(UInt32(65) + UInt32(code - 44 + 17)))
            } else {
                Key.RawScancode(code)
            }
    }
}

/// QWERTY 上排（Q..P）的字母序号：evdev 16..25 与字母表顺序不同，
/// 直接 code-16 会把 W/E/R/T 变成 B/C/D/E。返回值是 0=A 的序号。
func evdevLetterIndex(code: Int32): Int64 {
    match (code) {
        case 16 => 16   // Q
        case 17 => 22   // W
        case 18 => 4    // E
        case 19 => 17   // R
        case 20 => 19   // T
        case 21 => 24   // Y
        case 22 => 20   // U
        case 23 => 8    // I
        case 24 => 14   // O
        case _ => 15    // P
    }
}

/// L 层事件 -> UiEvent（LWP 模式的唯一映射点；指针/滚轮/按键/文本都在这里收口）
public /// 拖放移动高频事件：不逐条打点（只在收尾事件里记录），保持 trace 干净。
func discardMotionForDnd(x: UInt32, y: UInt32): Unit {
    let _ = x
    let _ = y
}

/// 协议按键号 -> MouseButton（0=左 1=右 2=中，lwp_protocol.h；之前一律当左键，评审 M2）
public func mouseButtonOf(code: Int32): MouseButton {
    match (code) {
        case 0 => MouseButton.Left
        case 1 => MouseButton.Right
        case 2 => MouseButton.Middle
        case _ => MouseButton.RawCode(UInt8(code & 0xFF))
    }
}

func lwpEventToUi(ev: lwindow.LWindowEvent): UiEvent {
    // 按键自带文本（壳按当前键盘布局算好）：先投递文本插入，再投递按键本身。
    // 输入框只从 TextInput 插入（不猜键码），控件快捷键仍能收到 KeyDown。
    if (ev.kind == lwindow.LWindowEventType.Key && ev.pressed && ev.text.size > 0 &&
        !g_preeditActive && (ev.modifiers & KEY_MOD_COMMAND_MASK) == 0) {
        g_uiPending.add(UiEvent.TextInput(ev.text))
    }
    // 诊断：按下时打印 UI 实际收到的逻辑坐标（与期望位置对比可算出偏移）
    if (ev.kind == lwindow.LWindowEventType.PointerDown && g_probeFocusDbg) {
        probeTrace("ui down logical=${Int64(ev.x)},${Int64(ev.y)} uiScale=${g_ui_scale} winLogical=${g_win_w}x${g_win_h}")
    }
    match (ev.kind) {
        case lwindow.LWindowEventType.PointerDown => UiEvent.MouseDown(mouseButtonOf(ev.key), ev.x, ev.y)
        case lwindow.LWindowEventType.PointerMove => UiEvent.MouseMove(ev.x, ev.y)
        case lwindow.LWindowEventType.PointerUp => UiEvent.MouseUp(mouseButtonOf(ev.key), ev.x, ev.y)
        case lwindow.LWindowEventType.PointerAxis => UiEvent.MouseWheel(ev.x, ev.y, 0.0f32, 0.0f32)
        // commit 之后组合态结束
        case lwindow.LWindowEventType.TextInput => commitUi(ev.text)
        // 输入法组合态：只影响显示（LWindowEvent.key 里装着组合串内的光标字节偏移）
        case lwindow.LWindowEventType.Preedit =>
            preeditUi(ev.text, Int64(ev.key))
        case lwindow.LWindowEventType.DeleteSurrounding =>
            UiEvent.DeleteSurrounding(Int64(ev.key), Int64(ev.x))
        case lwindow.LWindowEventType.Key =>
            if (ev.pressed) { UiEvent.KeyDown(keyFromCode(ev.key), false) } else { UiEvent.KeyUp(keyFromCode(ev.key)) }
        case _ => UiEvent.Unknown(0)
    }
}

/// 把字体度量写进 probe_trace（文本垂直居中口径对账；LANLU_PROBE_LGPU=1 时落盘）
public func probeFontMetrics(): Unit {
    let sizes: Array<Float32> = [10.5, 12.0, 12.5, 13.0, 15.0]
    for (sz in sizes) {
        match (backend.shellFontMetrics(sz)) {
            case Some((a, d, g, u)) =>
                probeTrace("font metrics size=" + sz.toString() + " a=" + a.toString() +
                    " d=" + d.toString() + " gap=" + g.toString() + " upem=" + u.toString())
            case None => ()
        }
    }
}
