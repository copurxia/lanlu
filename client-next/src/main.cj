package lanlu_client_next

import cui.*
import cui.desktop.{frameProbeHook, lastRenderDiag, renderDiagHook}
import cui.{FileDialogResult, FileDialogs}
import lgpu.{captureRequest, captureSize, captureWriteTo, statsLine}
import lanlu_client_next.app.*
import lanlu_client_next.net.{OfflineCache, defaultOfflineCacheRoot}
import lanlu_client_next.ui.*
import lanlu_client_next.ui.{lastCanvas, probeFontMetrics, probeTrace}
import lwindow.{clipboardSetText, clipboardGetText, lwpInputEnabled}
import lgui.{debugFocusId, lastTextInputRect}
import lwindow.{lwpAwaitSystemInfo, lwpCursorShapeForPoint, lwpCursorShapeSent, lwpFrameTick, lwpImeEnable, lwpLastPointer, lwpLog, lwpRequestCapture, lwpSetCursorShape, lwpSetWindowMinMax, lwpSetTitleButtons, lwpReportedScale, lwpSetWindowTitle, lwpViolations, requestWindowCommand}
import std.convert.*
import std.env.{getVariable, setVariable}
import std.fs.{canonicalize, exists as fsExists, Path as FsPath, File as FsFile}
import std.time.MonoTime
import webview.warmup
import lwindow.{initialize as lwindowInitialize, preferredWindowGeometry, prepareDesktopIntegration,
    prepareRendererHints, systemSansFontPath}
import qwest.ClientBuilder
import lgui.input.{Clipboard}
import portcheck.runIfEnabled

/// 上一次的焦点控件 id（用于"文本输入开始/结束"的通知去抖）
var g_lastFocusId: String = ""

// G4 度量状态（UI 线程独占，同 g_lastFocusId 惯例；仓颉闭包不能捕获可变局部变量）。
// first_cover：首个封面就绪打点的自拆标志与扫描对象（仅 LANLU_PERF=1 时挂引用）。
private var g_firstCoverFound = false
private var g_firstCoverModel: ?AppModel = None
// 扫描上限：约 15s@60fps。离线/无服务时不会一直扫（超过即放弃本进程的 first_cover）。
private let g_firstCoverScanFrameLimit: Int64 = 900

/// M0 性能打点开关（只读一次环境变量）：LANLU_PERF=1 或 LANLU_PROBE_LGPU=1。
/// 之前每帧都会被反复 getVariable，这里缓存成一次性判定。
private var g_perfStatsOn: ?Bool = None

func perfStatsEnabled(): Bool {
    match (g_perfStatsOn) {
        case Some(v) => v
        case None =>
            let on = (getVariable("LANLU_PERF") ?? "0") == "1" ||
                (getVariable("LANLU_PROBE_LGPU") ?? "0") == "1"
            g_perfStatsOn = Some(on)
            on
    }
}

// 联调 trace：追加一行到 $HOME/probe_trace.txt（LANLU_PROBE_LGPU=1 时）。
/// 每帧探针日志开关（LANLU_PROBE_LGPU=1 / LANLU_PROBE_CURSOR_DBG=1）。启动时读一次。
let g_probeFrameLog: Bool = (getVariable("LANLU_PROBE_LGPU") ?? "0") == "1" ||
    getVariable("LANLU_PROBE_CURSOR_DBG") == Some("1")

func probeTraceLine(line: String): Unit {
    // 与 ui.probeTrace 是同一份逻辑（第 26 轮欠的合并）：委托过去，避免两处漂移。
    probeTrace(line)
}

// 根路由：按 model.page 切页（无路由框架，状态驱动）。
func rootView(model: AppModel): Unit {
    match (model.page.value) {
        case Page.Login => loginView(model)
        case Page.Library => libraryView(model) // Task 8 提供
        case Page.Shelf => shelfView(model)
        case Page.Detail(_) => detailView(model) // Task 11：档案详情（共用骨架）
        case Page.Tank(_) => tankView(model) // Task 11：合集详情（共用骨架）
        case Page.Reader(_, _) => readerView(model)
        case Page.Settings => settingsView(model)
    }
}

// 标题栏拖动区：titleBarDragRects/readerBarDragRects 给出顶栏死区矩形（DRAGGABLE 内
// 鼠标事件不投递给应用，交互控件必须全部落在矩形之外；几何预算与取舍见 ui/titlebar.cj、
// ui/reader_bar.cj 注释）。坐标为逻辑 vp，内部已处理 scale；阅读器换用专用顶栏且
// chrome 隐藏或阅读器抽屉打开时清空拖动区（顶部恢复点击翻页/抽屉标签点击），故按
//（宽度, 页型, chrome 可见性, 抽屉可见性, 返回钮）复查；任一变化时经 onTick 重注册。
private var dragRegionWidth: Int32 = -1
private var dragRegionReader = false
private var dragRegionChrome = true
private var dragRegionReaderPanel = false
private var dragRegionUploadDrawer = false
// 上一次实际注册的顶栏拖动矩形：控件占位随布局/动画逐帧变化，逐帧对比矩形集，
// 有变化才重注册（FFI + HashMap 写入），无变化零成本。
private var dragRegionApplied = Array<(Int32, Int32, Int32, Int32)>(0, repeat: (0, 0, 0, 0))

private func dragRectsEqual(a: Array<(Int32, Int32, Int32, Int32)>, b: Array<(Int32, Int32, Int32, Int32)>): Bool {
    if (a.size != b.size) {
        return false
    }
    for (i in 0..a.size) {
        if (a[i] != b[i]) {
            return false
        }
    }
    true
}

private func syncTitleBarDragRegion(window: SdlWindow, model: AppModel): Unit {
    let w = window.width
    let isReader = match (model.page.value) {
        case Page.Reader(_, _) => true
        case _ => false
    }
    let chrome = !isReader || model.reader.chromeVisible
    let readerPanelOpen = isReader && (model.readerSidebarOpen.value || model.readerSettingsOpen.value)
    let uploadPanelOpen = model.uploadDrawerOpen.value
    // 顶栏交互控件在 layout 时上报实际占位（见 titlebar.cj noteTitleBarControl），
    // 拖动矩形 = 顶栏横向对占位的互补集——搜索框展开动画、返回/筛选钮出现、用户名
    // 长度变化都被自然覆盖，无需手工几何估算。
    let rects = if (uploadPanelOpen || (isReader && (!chrome || readerPanelOpen))) {
        Array<(Int32, Int32, Int32, Int32)>(0, repeat: (0, 0, 0, 0))
    } else if (isReader) {
        readerBarDragRects(w)
    } else {
        titleBarDragRects(w, titleBarDragExclusionRects())
    }
    if (w == dragRegionWidth && isReader == dragRegionReader && chrome == dragRegionChrome && readerPanelOpen ==
        dragRegionReaderPanel && uploadPanelOpen == dragRegionUploadDrawer && dragRectsEqual(rects, dragRegionApplied)) {
        return
    }
    dragRegionWidth = w
    dragRegionReader = isReader
    dragRegionChrome = chrome
    dragRegionReaderPanel = readerPanelOpen
    dragRegionUploadDrawer = uploadPanelOpen
    dragRegionApplied = rects
    // 不支持 hit-test 的视频驱动（如快照装置的 dummy）会拒绝注册：忽略即可，窗口照常
    // 可用，只是没有 OS 托管拖动（与 desktop_app 忽略光标/IME 锚点拒绝同一惯例）。
    try {
        window.setDragRegions(rects)
    } catch (_: Exception) {
        ()
    }
}

public func runApp(): Int64 {
    // 启动计时基准（LANLU_PERF 评估用）：各 [boot] 行尾部为距进程入口的累计毫秒。
    let bootT0 = MonoTime.now()
    // G4 度量：boot_to_first_frame / first_cover 终点打点。
    // 仅 LANLU_PERF=1 时安装（默认零开销）；装在所有既有钩子之前，后续安装点
    // （LANLU_PROBE_CAPTURE / lwp frame tick）会把它作为 prevHook 串联，互不覆盖。
    // first_cover 借既有逐帧钩子顺带检查 imageStates 首个 "ready"，命中或超过
    // g_firstCoverScanFrameLimit 帧即自拆——无新增线程/定时器；理想事件点是 model
    // dispatch 的 "img:" ready 分支（本轮文件独占范围外，接入点见 exec/G4-metrics.md）。
    if (SubtitlePerf.enabled()) {
        let prevFrameHook = frameProbeHook
        frameProbeHook = { frame: Int64 =>
            match (prevFrameHook) {
                case Some(h) => h(frame)
                case None => ()
            }
            if (frame == 1) {
                SubtitlePerf.emit("boot_to_first_frame_ms",
                    (MonoTime.now() - bootT0).toMilliseconds(), "ms")
            }
            if (!g_firstCoverFound && frame <= g_firstCoverScanFrameLimit) {
                match (g_firstCoverModel) {
                    case Some(m) =>
                        for ((_, st) in m.imageStates) {
                            if (st.value == "ready") {
                                g_firstCoverFound = true
                                SubtitlePerf.emit("first_cover_ms",
                                    (MonoTime.now() - bootT0).toMilliseconds(), "ms")
                                break
                            }
                        }
                    case None => ()
                }
            }
        }
    }
    // G5：离线缓存预热上移到设置库打开之前，与 initializeSettingsStore 并行。
    // 依赖核实（读码）：OfflineCache.open 只用 HOME 派生的 defaultOfflineCacheRoot()
    // + rocksdb_ffi 自身；offline_cache.cj / PageStore / SearchStore / TankoubonStore /
    // TagTranslationStore / BlobCacheStore / ObjectStore / DbSchema 全文件无
    // loadSettings / settingsStore / defaultSettingsRoot / AppSettings 引用 → 不依赖设置。
    // HOME 由 lwindowInitialize() 的 initPlatformOhos 提前 setVariable 就绪（runApp 之前）。
    // seed 模式不预热（隔离 HOME 的快照路径不应触碰真实缓存目录）；harnessSeedMode()
    // 只解析命令行、无依赖，可在此提前判定（下方 seedMode 处会再取一次，同一实现幂等）。
    let offlineCachePrewarm: ?Future<?OfflineCache> = if (harnessSeedMode().size == 0) {
        Some(spawn {OfflineCache.open(defaultOfflineCacheRoot())})
    } else {
        None
    }
    // 临时启动诊断（定位 Windows 启动即崩的访问违规，查到后可删）：
    // 分段打印启动进度，崩溃前最后一条即崩溃所在阶段。
    println("[boot] 0 settings-store root=${defaultSettingsRoot()} t=0ms")
    initializeSettingsStore()
    println("[boot] 1 settings-store initialized t=${(MonoTime.now() - bootT0).toMilliseconds()}ms")
    // 启动后端策略（2026-07-19 Task E2 实测，详见 .superpowers/sdd/task-e2-report.md）：
    // 原生 Wayland 启动崩溃根因 = libdecor 的 GTK 插件在窗口创建时初始化 GTK3，
    // 触发 glycin（本体经 libvips→librsvg→gdk_pixbuf 常驻进程，无法移除）的
    // 初始化竞态 SIGSEGV。对策：把 LIBDECOR_PLUGIN_DIR 指向随仓库发布的
    // libdecor-cairo 插件（无 GTK 依赖，装饰照常绘制），GTK 插件不再加载，
    // 原生 Wayland 20/20 启动 0 SIGSEGV。渲染驱动优先级见下方独立段落。
    // 用户显式设置 LIBDECOR_PLUGIN_DIR / SDL_VIDEODRIVER / SDL_RENDER_DRIVER 时不覆盖。
    // 平台启动准备（Wayland libdecor 插件目录等）由 lwindow 适配层负责。
    prepareDesktopIntegration()
    // 渲染驱动优先级策略：D3D/Metal > vulkan > opengl > software。
    // Windows/macOS 不动——SDL 内置顺序里 D3D11/12、Metal 本来就在最前，自动选择即正确；
    // 但 SDL3 内置顺序把 opengl 排在 vulkan 之前（SDL_render.c），故 Linux 桌面会话
    // （wayland/x11）下显式指定 "vulkan,opengl"：SDL3 的 SDL_RENDER_DRIVER hint 支持逗号
    // 分隔回退列表（SDL_render.c 逐 token 尝试），vulkan 创建失败自动回退 opengl。
    // LANLU_SOFTWARE_RENDER=1 强制 software 兜底；用户显式 SDL_RENDER_DRIVER 永远优先。
    // 渲染驱动优先级由 lwindow 按平台决定（Linux 桌面 vulkan>opengl；Win/mac 交给 SDL 内置顺序）。
    prepareRendererHints()
    // Wayland 下任务栏/应用菜单的图标按 app_id 匹配同名 .desktop 文件（CI 打包安装
    // lanlu.desktop）；X11/Windows 的任务栏图标由下方 setIcon 直接生效。
    // 用户显式设置 SDL_APP_ID 时不覆盖。
    if (SdlHints.get(SdlHint.AppId).isNone()) {
        SdlHints.set(SdlHint.AppId, "lanlu")
    }

    // ── 临时快照装置（验证专用，用后逐字还原）：--seed-browse/--seed-search/
    // --seed-detail/--seed-tank/--seed-settings
    // 离线播种假数据，跳过磁盘配置与会话恢复；--width N 覆盖窗口宽（默认 1440）。
    let seedMode = harnessSeedMode()
    let settings = if (seedMode.size > 0) {
        let s = AppSettings()
        s.serverUrl = "https://demo.lanlu.local"
        // 亮主题快照：种子模式跳过磁盘配置，唯独 theme 取自磁盘——隔离 HOME 预置
        // 设置库中 theme=light 即可拍亮主题快照，其余字段保持离线默认。
        s.theme = loadSettings().theme
        s
    } else {
        loadSettings()
    }
    println("[boot] 2 settings loaded, seedMode=${seedMode} t=${(MonoTime.now() - bootT0).toMilliseconds()}ms")
    // G5：离线缓存预热已上移到设置库打开之前（见 runApp 开头），此处不再 spawn；
    // offlineCachePrewarm 变量在那里的作用域覆盖本函数余下部分。
    // webview 字体预热：fontique 系统字体扫描（FcConfigBuildFonts）是 loadHtml
    // 崩溃窗口的主要来源，提前到 GC 未活跃、主线程浅栈的启动阶段完成一次；
    // 进程级共享，后续 loadHtml 复用不再重建（见 webview_native session.rs）。
    // G4 度量：warmup 单独计时（只加计时，不改调用时机——惰性化有 GC 栈扫描崩溃窗口）。
    let warmupT0 = MonoTime.now()
    warmup()
    let warmupMs = (MonoTime.now() - warmupT0).toMilliseconds()
    println("[boot] 2.1 webview fonts warmed t=${(MonoTime.now() - bootT0).toMilliseconds()}ms (warmup=${warmupMs}ms)")
    SubtitlePerf.gauge("webview_warmup_ms", warmupMs)
    SubtitlePerf.emit("webview_warmup_ms", warmupMs, "ms")
    let model = AppModel(settings, persistSettings: {s => saveSettings(s)}, offlineCachePrewarm: offlineCachePrewarm)
    // G4：first_cover 扫描对象（仅 LANLU_PERF=1 挂引用，默认不留任何状态）。
    if (SubtitlePerf.enabled()) {
        g_firstCoverModel = Some(model)
    }
    if (seedMode.size > 0) {
        seedLibrarySnapshot(model, seedMode)
    } else {
        model.tryResumeSession()
    }
    // LANLU_PERF 打点：会话恢复与首批浏览行的端到端起点（终点在 model dispatch 的
    // "me"/"row:" 分支，emit session_resume_ms / first_rows_ms）。
    SubtitlePerf.spanStart("session_resume")
    SubtitlePerf.spanStart("first_rows")
    // 窗口创建段与 first_rows 同起点（终点在 [boot] 5 进主循环处）。
    SubtitlePerf.spanStart("boot_to_loop")
    println("[boot] 3 model ready, creating DesktopApp t=${(MonoTime.now() - bootT0).toMilliseconds()}ms")
    // 脚本化字幕性能基准（LANLU_BENCH_ARCID 设置时启用）：复用真实 AppModel/PlaybackModel/
    // libVLC/libass 全链路，按阶段状态机驱动冷扫描→播放→切换→seek→缓存命中并输出 @@RESULT。
    let bench = SubtitleBench()
    let benchEnabled = bench.isEnabled()
    println("[boot] 3.4 SubtitleBench ready (enabled=${benchEnabled}) t=${(MonoTime.now() - bootT0).toMilliseconds()}ms")
    // 启动时一次性缩放适配（ADR：不做运行时动态缩放）：seedMode 钉死 1.0 保证
    // CI 快照像素确定性；正常启动取主显示器 contentScale（Windows 高 DPI 下 >1，
    // primaryDisplayInfo 内部自带 SDL_Init(VIDEO) 引用计数，建窗前调用安全），
    // 查询失败回退 1.0。逻辑尺寸按可用桌面区钳制：默认 1440×900 在 150% 缩放的
    // 1080p 屏上物理 2160×1350 超界，收缩逻辑尺寸使 逻辑×scale ≤ usableBounds；
    // 钳制结果低于 960×640 最小窗口时不再收缩（宁可超界也保住最小可用布局）。
    // 窗口几何/缩放策略在 lwindow（平台层）；seedMode 钉死 1.0 以保 CI 快照像素确定性。
    let geom = preferredWindowGeometry(harnessWindowWidth(), harnessWindowHeight(), pinScale: seedMode.size > 0)
    probeTraceLine("geometry ${geom.width}x${geom.height} scale=${geom.scale} reportedScale=${lwpReportedScale()}")
    // 协议开启（默认）时：系统事实（时区/语言/字体目录）由壳下发，不再靠环境变量猜。
    // 有界等待：壳没起来就保持旧行为。
    // 注意：这里必须用 lwpInputEnabled()，不能写死 LANLU_LWP=="1" ——
    // 默认开启后 env 是空的，写死会让整段逻辑静默失效（第 70 轮踩过）。
    if (lwpInputEnabled()) {
        // G4 度量：有界等待的实际耗时（最坏 300ms 全暴露在 boot→首帧路径上，见 R-data §S3）。
        // G5：上限 300→100ms；不改回退逻辑（systemSansFontPath 候选路径照旧），回退时打 fallback=true。
        let lwpWaitT0 = MonoTime.now()
        let gotInfo = lwpAwaitSystemInfo(100)
        let lwpWaitMs = (MonoTime.now() - lwpWaitT0).toMilliseconds()
        probeTraceLine("lwp system.info ready=" + gotInfo.toString() + " waitMs=" + lwpWaitMs.toString() +
            (if (gotInfo) { "" } else { " fallback=true" }))
        SubtitlePerf.gauge("lwp_system_info_wait_ms", lwpWaitMs)
        SubtitlePerf.emit("lwp_system_info_wait_ms", lwpWaitMs, "ms")
    }
    let uiScale: Float32 = geom.scale
    let winW: Int32 = geom.width
    let winH: Int32 = geom.height
    println("[boot] 3.5 uiScale=${uiScale} window=${winW}x${winH} t=${(MonoTime.now() - bootT0).toMilliseconds()}ms")
    // 超采样档位：默认 AUTO（GPU 渲染 2x，software 回退 1x）。LANLU_PERF 实测 2x 超采样
    // 是帧成本大头（阅读页 present 15ms/帧），LANLU_SUPERSAMPLE=1 可关到 1x（文字边缘
    // 锐度略降换帧成本减半）；用户显式设置时优先，未设置保持默认行为不变。
    let supersample: Int32 = if (getVariable("LANLU_SUPERSAMPLE") == Some("1")) {
        1
    } else {
        AUTO_SUPERSAMPLE
    }
    // P5：headless 窗口的输入源（必须在建窗口之前挂上）
    installHeadlessInputSource()
    // 文本垂直居中口径：把字体真实度量留档（LANLU_PROBE_LGPU=1 时写 probe_trace）
    if ((getVariable("LANLU_PROBE_LGPU") ?? "0") == "1") {
        probeFontMetrics()
    }
    // 空闲渲染诊断：引擎帧钩子里直接读 cui 的决策标志（每 120 帧一条）
    let prevHook = frameProbeHook
    frameProbeHook = { frame: Int64 =>
        match (prevHook) {
            case Some(h) => h(frame)
            case None => ()
        }
        if (frame % 120 == 0) {
            probeTraceLine("idle " + lastRenderDiag)
        }
    }
    // 联调：LANLU_PROBE_CAPTURE=1 —— 在渲染循环内按帧触发 GPU 抓帧并写文件
    if ((getVariable("LANLU_PROBE_CAPTURE") ?? "0") == "1") {
        // 第 1 帧太早（封面尚未解码）；120 帧后再抓一张用于比对封面区域像素。
        frameProbeHook = { frame: Int64 =>
            let want = if (frame == 1 || (frame % 40 == 0 && frame <= 200)) {
                "cap_f${frame}.rgba"
            } else {
                ""
            }
            if (want.size > 0) {
                let home = getVariable("HOME") ?? "."
                match (lastCanvas) {
                    case Some(c) =>
                        let rc = c.captureTo(home + "/" + want)
                        probeTraceLine("capture ${want} rc=" + rc.toString())
                    case None => probeTraceLine("capture off: no canvas")
                }
            }
        }
    }
    // 运行期窗口标题与尺寸约束（验证 set_title / set_min_max 两条协议真的在发）
    if (lwpInputEnabled()) {
        let _ = lwpSetWindowTitle("Lanlu")
        let _ = lwpSetWindowMinMax(960, 640, 0, 0)
        probeTraceLine("lwp title/limits sent")
    }

    // 协议开启（默认）时：每帧走一次 tick（frame.request + 生命周期 + 超时检查）。
    // 与已有的抓帧钩子**串联**，不覆盖它。同样必须用 lwpInputEnabled()。
    if (lwpInputEnabled()) {
        let prevHook = frameProbeHook
        frameProbeHook = { frame: Int64 =>
            match (prevHook) {
                case Some(h) => h(frame)
                case None => ()
            }
            let _ = lwpFrameTick()
            // 光标形状：每 8 帧按「指针是否在文本框内」决定，变了才发。
            // 放在 frame tick 而不是事件源里：事件源只在有输入时被调用，
            // 焦点刚变化那一拍未必有指针事件（第 89 轮踩过）。
            if (frame % 8 == 0) {
                let (px, py) = lwpLastPointer()
                // 每 16 帧一条 LWP 日志在真机上会持续占用渲染线程与 hilog：只在探针开关下输出
                if (g_probeFrameLog && frame % 16 == 0) {   // 只在 frame%8==0 的帧里，所以取 16 的倍数才能命中
                    probeTraceLine("cursor frame=" + frame.toString() + " ptr=" +
                        Int64(px).toString() + "," + Int64(py).toString() +
                        " sent=" + lwpCursorShapeSent().toString() +
                        " hasRect=" + (match (lastTextInputRect) { case Some(_) => "1"; case None => "0" }))
                }
                if (px >= 0.0) {
                    let (tx, ty, tw, th, hasRect) = match (lastTextInputRect) {
                        case Some(r) => (r.x, r.y, r.w, r.h, true)
                        case None => (0.0f32, 0.0f32, 0.0f32, 0.0f32, false)
                    }
                    let want = lwpCursorShapeForPoint(tx, ty, tw, th, px, py, hasRect)
                    if (want != lwpCursorShapeSent()) {
                        let _ = lwpSetCursorShape(want)
                    }
                }
            }
            // 文本输入焦点变化 -> 通知壳（显示/隐藏软键盘）
            let focusId = debugFocusId
            if (focusId != g_lastFocusId) {
                g_lastFocusId = focusId
                let hasText = focusId.size > 0
                let imeOk = lwpImeEnable(hasText)
                probeTraceLine("ime enable focus=" + focusId + " -> " + imeOk.toString())
            }
            if (g_probeFrameLog && frame % 30 == 0) {
                probeTraceLine("lwp violations " + lwpViolations())
            }
            // M0 渲染统计：每 120 帧（约 2s）打一行 lgpu 计数与文字测量命中率。
            // 只在探针/性能开关打开时输出，release 默认不产生任何字符串。
            if (frame % 120 == 0 && perfStatsEnabled()) {
                probeTraceLine("lgpu stats " + statsLine() + " measure=" +
                    (match (lastCanvas) {
                        case Some(c) =>
                            let (hits, misses, entries) = c.measureStats()
                            "hits=${hits} miss=${misses} entries=${entries}"
                        case None => "n/a"
                    }))
            }
        }
    }
    // 诊断：State 实例 id -> 模型字段名（配合 probe 的 ids=… 定位空转渲染的写入方）
    probeTraceLine("state ids " + debugStateIdMap(model))
    let app = DesktopApp(
        WindowSpec("lanlu", winW, winH, scale: uiScale, supersample: supersample,
            // 无边框窗口：创建时即无 OS 装饰；标题栏由 ui/titlebar.cj 自绘。
            borderless: true,
            fontPath: if (settings.fontPath.size > 0) {
                Some(settings.fontPath)
            } else {
                systemSansFontPath()
            }), theme: lanluThemeFor(settings.theme),
    )
    // 联调：LANLU_PROBE_CLIP=1 各发一次 clipboard.set / get（验 M6 第 2 步双向通路）
    if ((getVariable("LANLU_PROBE_CLIP") ?? "0") == "1") {
        spawn {
            sleep(Duration.second * 5)
            clipboardSetText("m6-clip-probe")
            // 剪贴板读是异步的（get -> 壳读系统剪贴板 -> clipboard.text 事件 -> 缓存）
            sleep(Duration.millisecond * 500)
            var v = ""
            var tries = 0
            while (tries < 20) {
                v = clipboardGetText()
                if (v.size > 0) {
                    break
                }
                sleep(Duration.millisecond * 100)
                tries++
            }
            probeTraceLine("clip probe get='" + v + "' tries=" + tries.toString())
        }
    }

    // 联调：LANLU_PROBE_RESIZE=N 反复「最大化/还原」N 轮，压测窗口尺寸变化路径
    // （§7.1：Maleoon swapchain 反复重建是已知崩溃风险；这里走 window.set_state 让壳真的改窗口尺寸）
    match (getVariable("LANLU_PROBE_RESIZE")) {
        case Some(v) =>
            var parsed: Int64 = 0
            try { parsed = Int64.parse(v) } catch (_) { parsed = 0 }
            let rounds = parsed
            if (rounds > 0) {
                spawn {
                    sleep(Duration.second * 6)
                    var i = 0
                    while (i < rounds) {
                        let st = if (i % 2 == 0) { "maximize" } else { "restore" }
                        requestWindowCommand(st)
                        probeTraceLine("resize round " + (i + 1).toString() + " -> " + st)
                        sleep(Duration.millisecond * 900)
                        i++
                    }
                    probeTraceLine("resize rounds done " + rounds.toString())
                }
            }
        case None => ()
    }

    // 联调：LANLU_PROBE_SNAPSHOT=1 启动后请求一次页面抓帧（验证抓帧桥）
    if ((getVariable("LANLU_PROBE_SNAPSHOT") ?? "0") == "1") {
        spawn {
            sleep(Duration.second * 4)
            // LANLU_LWP=1：抓帧请求走 lw_test.capture（壳收到后调 componentSnapshot）；
            // 否则回落文件桥（LANLU_LWP=0 的调试路径）。
            // 注意运算符优先级：`a ?? "." + "/x"` 会被解析成 `a ?? ("." + "/x")`，
            // 传进去的就成了目录本身（真机上表现为「抓帧路径=目录」）。
            let snapPath = (getVariable("HOME") ?? ".") + "/snap_shell.rgba"
            if (lwpRequestCapture(snapPath)) {
                probeTraceLine("snapshot requested via lwp test.capture")
                return
            }
            probeTraceLine("snapshot request dropped: LWP 不可用（文件桥已删除）")
        }
    }
    println("[boot] 4 DesktopApp created (window+renderer ok) t=${(MonoTime.now() - bootT0).toMilliseconds()}ms")
    // 联调：LANLU_PROBE_CLIP=1 启动后写一次剪贴板并读回（验证 L 层剪贴板通路）
    if ((getVariable("LANLU_PROBE_CLIP") ?? "0") == "1") {
        spawn {
            sleep(Duration.second * 3)
            try {
                Clipboard.setText("probe-clip-测试")
                probeTraceLine("clip set ok")
                sleep(Duration.millisecond * 600)
                let back = Clipboard.getText()
                probeTraceLine("clip read=[" + back + "]")
            } catch (e: Exception) {
                probeTraceLine("clip failed: " + e.toString())
            }
        }
    }
    // 联调：LANLU_PROBE_DIALOG=1 —— 验证文件对话框文件桥（引擎 → 壳层 picker → 结果 → 回调）
    if ((getVariable("LANLU_PROBE_DIALOG") ?? "0") == "1") {
        spawn {
            sleep(Duration.second * 3)
            try {
                let request = FileDialogs.openFile()
                probeTraceLine("dialog req submitted")
                var waited = 0
                while (waited < 200) {
                    sleep(Duration.millisecond * 500)
                    waited += 1
                    if (request.isDone()) {
                        match (request.result()) {
                            case FileDialogResult.FileDialogSelected(paths, _) =>
                                probeTraceLine("dialog result selected count=" + paths.size.toString() + " first=" + (if (paths.size > 0) { paths[0] } else { "" }))
                            case FileDialogResult.FileDialogCanceled =>
                                probeTraceLine("dialog result canceled")
                            case FileDialogResult.FileDialogFailed(msg) =>
                                probeTraceLine("dialog result failed=" + msg)
                            case FileDialogResult.FileDialogPending =>
                                probeTraceLine("dialog result still pending")
                        }
                        break
                    }
                }
            } catch (e: Exception) {
                probeTraceLine("dialog probe failed: " + e.toString())
            }
        }
    }
    // 联调：LANLU_PROBE_WINCMD=minimize|maximize|restore 启动后触发一次窗口命令
    let probeCmd = getVariable("LANLU_PROBE_WINCMD") ?? ""
    if (probeCmd.size > 0) {
        installLgpuProbeWindowCommand(probeCmd)
    }
    // P4 对照开关：CN_UI_BACKEND=lgpu 时整棵 UI 交给 lgpu 绘制
    var lgpuBackend = false
    try {
        lgpuBackend = installLgpuBackendIfRequested({canvas => app.useCanvasBackend(canvas)})
    } catch (e: Exception) {
        println("[boot] lgpu backend install failed: " + e.toString())
    }
    probeTraceLine("backend installed=" + lgpuBackend.toString())
    if (lgpuBackend) {
        println("[boot] UI backend = lgpu (wgpu/Vulkan)")
        // 纹理路径自检：LANLU_PROBE_TEX=1 时从 /data/local/tmp/probe.png 加载一张纹理，
        // 验证 PNG → 后端纹理上传这条链路（结果写在 lgpu_textures.txt）。
        // 纹理路径自检（HTTP 版）：LANLU_PROBE_TEX_URL=<png url> 时抓取并创建纹理。
        let texUrl = getVariable("LANLU_PROBE_TEX_URL") ?? ""
        if (texUrl.size > 0) {
            try {
                let client = ClientBuilder().build()
                let resp = client.get(texUrl).send()
                probeTraceLine("http status=" + resp.status.toString() + " url=" + texUrl)
                if (resp.status == 200) {
                    let bytes = resp.bytes()
                    let id = app.probeLoadPngBytes(bytes)
                    probeTraceLine("probeLoadPngBytes id=" + id.toString() + " bytes=" + bytes.size.toString())
                    println("[boot] probe texture (http) id=" + id.toString() + " bytes=" + bytes.size.toString())
                }
            } catch (e: Exception) {
                probeTraceLine("http failed: " + e.toString())
                println("[boot] probe texture http failed: " + e.toString())
            }
        }
        if ((getVariable("LANLU_PROBE_TEX") ?? "0") == "1") {
            let home = getVariable("HOME") ?? "."
            let id = app.probeLoadPngTexture(home + "/probe.png")
            println("[boot] probe texture id=" + id.toString())
        }
    }
    // worker 结果/SSE 到货唤醒：结果一进信箱即推 SDL 用户事件，把可能正阻塞在
    // SDL_WaitEventTimeout 的主循环立即唤醒；醒后那次迭代的 onTick/pump 正常 drain，
    // 图片到货/UI 更新不再等下一个输入事件。
    model.worker.onResult = { => app.requestWake() }
    // 设置页主题切换的应用路径：model.setTheme 落盘后回调这里，运行时替换主题即切即生效。
    // 三键平台化：平台三键的明暗跟随业务主题（壳未宣告 title_buttons 能力时是空操作）。
    model.themeChangeHandler = {mode =>
        app.setTheme(lanluThemeFor(mode))
        let cm: UInt32 = if (mode == "light") { 1 } else { 2 }
        setPlatformTitleButtonsColorMode(cm)
        let _ = lwpSetTitleButtons(7, 0, 16, 12, 28, cm)
    }
    // 启动时的初值也按已保存的主题来（避免首帧平台三键按系统明暗闪一下）。
    setPlatformTitleButtonsColorMode(if (model.isLight()) { 1 } else { 2 })
    try { app.setMinimumSize(960, 640) } catch (_: Exception) {}  // OHOS: SDL_SetWindowMinimumSize 不支持
    // 窗口图标（任务栏/窗口切换器）：logo 字节内嵌在二进制里（build.cj 生成），
    // 解码失败说明构建产物损坏，与旧"logo 文件缺失即报错"同一口径。
    // Wayland 无窗口图标协议（图标靠上方 app_id 匹配 .desktop），SDL 会返回
    // unsupported——忽略即可，不影响 X11/Windows 的设置效果。
    // P5：窗口图标由 ArkTS/module.json 提供，SDL 的 Surface/setIcon 通道已移除。
    let _ = EMBEDDED_LOGO_PNG
    // 无边框已在 WindowSpec(borderless: true) 创建时生效（见上方 WindowSpec 注释）。
    syncTitleBarDragRegion(app.sdlWindow, model)
    println("[boot] 5 entering main loop t=${(MonoTime.now() - bootT0).toMilliseconds()}ms")
    // LANLU_PERF 打点：窗口创建段（model ready→主循环入口，与 first_rows 同起点；
    // first_rows ≈ boot_to_loop + me 等待 + rows_fetch，把窗口创建段从首屏耗时中切出）。
    if (SubtitlePerf.enabled()) {
        SubtitlePerf.spanEnd("boot_to_loop")
        SubtitlePerf.emit("boot_to_loop_ms", SubtitlePerf.getGauge("boot_to_loop"), "ms")
    }
    // 空转零渲染：主循环每次迭代泵回工作线程结果（drain 为空时不写任何 State，
    // dirty-frame skipping 使该迭代不重建/不绘制）；不能用 FrameHandler 做这件事——
    // 它必须每帧 requestFrame 才能持续触发，会强制 60fps 全量重建+绘制。
    // pump 的周期定时器（chrome 自动隐藏/自动翻页/进度防抖尾巴）注册为定时帧请求：
    // 循环空转等待（SDL_WaitEventTimeout）时在最近到期时刻唤醒，醒后本次迭代已正常 pump。
    app.onTick = {
        =>
            model.pump()
            match (model.nextPumpTimerMs()) {
                case Some(ms) => app.requestFrameAfter(UInt64(ms))
                case None => ()
            }
            let ww = Int64(app.sdlWindow.width)
            if (ww != model.windowWidth.value) {
                model.windowWidth.value = ww
            }
            syncTitleBarDragRegion(app.sdlWindow, model)
            if (benchEnabled) {
                let _ = bench.step(model)
            }
    }
    app.run {
        ZStack {
            // 根布局：常规页面 = 顶部通用 titleBar（品牌/搜索/导航/用户芯片）+ 页面区（VStack）；
            // 阅读器页 = 舞台恒全高 + 顶栏浮层（ZStack 叠层，原型 #topbar 浮于 stage 之上），
            // chrome 显隐动画在 readerTopBarChrome 内（上滑/下滑 Spring，见 ui/reader_bar.cj）。
            // readerVersion 订阅由 readerView/reader_bar 内部读取完成，这里无需再读。
            match (model.page.value) {
                case Page.Reader(_, _) => ZStack {
                    readerView(model)
                    readerTopBarChrome(app.sdlWindow, model)
                }.alignment(Alignment.TopLeading)
                case _ => VStack {
                    titleBar(app.sdlWindow, model)
                    rootView(model)
                }.spacing(0.0)
            }
            // 页面切换交叉淡化：navigate() 推迟切页，本层在旧页留存的那一帧捕获
            // GPU 快照，提交切页后旧帧 200ms 淡出。置于页面内容之上、浮层之下，
            // 快照只含页面主体（titlebar+页区），抽屉/Toast 不受影响。
            PageTransition(model)
            uploadDrawer(app.sdlWindow, model)
            metadataEditOverlay(model)
            ThemeRipple(model)
            ToastLayer(model.toaster)
        }
    }
    model.close()
    // G2 交接：perf_log 改为 500ms 周期 flush + 8KB 缓冲，退出零丢失需在此手动落一次。
    perfLogFlush()
    closeSettingsStore()
    return 0
}

// 平台入口（SDLT3 libmain 的 SDL_main 经 Cangjie runtime 调用）。
// 业务层不含任何平台差异：平台环境准备由 lwindow 适配层负责，移植自检由 portcheck 负责。
@C
public func cj_app_main(): Int64 {
    lwindowInitialize()
    runIfEnabled()
    return runApp()
}
// 桌面入口（Linux/Windows/macOS）：同样只调平台无关 API。
main(): Int64 {
    lwindowInitialize()
    runIfEnabled()
    return runApp()
}
