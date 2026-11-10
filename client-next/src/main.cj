package lanlu_client_next

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.{OfflineCache, defaultOfflineCacheRoot}
import lanlu_client_next.ui.*
import std.env.{getVariable, setVariable}
import std.fs.{canonicalize, exists as fsExists, Path as FsPath, File as FsFile}
import std.time.MonoTime
import webview.warmup
import lwindow.{initialize as lwindowInitialize, preferredWindowGeometry, prepareDesktopIntegration,
    prepareRendererHints, systemSansFontPath}
import qwest.ClientBuilder
import sdl.input.{Clipboard}
import portcheck.runIfEnabled

// 联调 trace：追加一行到 $HOME/probe_trace.txt（LANLU_PROBE_LGPU=1 时）。
func probeTraceLine(line: String): Unit {
    if ((getVariable("LANLU_PROBE_LGPU") ?? "0") != "1") {
        return
    }
    let home = getVariable("HOME") ?? "."
    let path = FsPath(home + "/probe_trace.txt")
    try {
        let old = if (fsExists(path)) { String.fromUtf8(FsFile.readFrom(path)) } else { "" }
        FsFile.writeTo(path, (old + line + String.fromUtf8(Array<UInt8>(1, repeat: 10))).toArray())
    } catch (_) {}
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
    // 离线缓存预热：RocksDB open（session_resume 302ms 的主要构成）与 webview 字体预热、
    // AppModel 构造并行，首次用缓存（resumeProfile）时由 offlineCacheFor join。seed 模式
    // 不预热——隔离 HOME 的快照路径不应触碰真实缓存目录。
    let offlineCachePrewarm: ?Future<?OfflineCache> = if (seedMode.size == 0) {
        Some(spawn {OfflineCache.open(defaultOfflineCacheRoot())})
    } else {
        None
    }
    // webview 字体预热：fontique 系统字体扫描（FcConfigBuildFonts）是 loadHtml
    // 崩溃窗口的主要来源，提前到 GC 未活跃、主线程浅栈的启动阶段完成一次；
    // 进程级共享，后续 loadHtml 复用不再重建（见 webview_native session.rs）。
    warmup()
    println("[boot] 2.1 webview fonts warmed t=${(MonoTime.now() - bootT0).toMilliseconds()}ms")
    let model = AppModel(settings, persistSettings: {s => saveSettings(s)}, offlineCachePrewarm: offlineCachePrewarm)
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
    let app = DesktopApp(
        WindowSpec("lanlu", winW, winH, scale: uiScale, supersample: supersample,
            // 无边框窗口：创建时即无 OS 装饰（替代旧的事后 setBordered(false)），
            // Wayland 下 libdecor-cairo 不再先栅格化一遍随即摘除的标题栏装饰；
            // 标题栏由 ui/titlebar.cj 自绘（Task 8），阅读器页换用专用顶栏
            // ui/reader_bar.cj（T13）。
            borderless: true,
            // 用户设置优先；否则取平台层的系统无衬线字体（无 fontconfig 平台才有，找不到则 None）。
            fontPath: if (settings.fontPath.size > 0) {
                Some(settings.fontPath)
            } else {
                systemSansFontPath()
            }), theme: lanluThemeFor(settings.theme),
    )
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
    model.themeChangeHandler = {mode => app.setTheme(lanluThemeFor(mode))}
    try { app.setMinimumSize(960, 640) } catch (_: Exception) {}  // OHOS: SDL_SetWindowMinimumSize 不支持
    // 窗口图标（任务栏/窗口切换器）：logo 字节内嵌在二进制里（build.cj 生成），
    // 解码失败说明构建产物损坏，与旧"logo 文件缺失即报错"同一口径。
    // Wayland 无窗口图标协议（图标靠上方 app_id 匹配 .desktop），SDL 会返回
    // unsupported——忽略即可，不影响 X11/Windows 的设置效果。
    let iconSurface = Surface.loadPngFromMemory(EMBEDDED_LOGO_PNG)
    app.manage(iconSurface)
    try {
        app.sdlWindow.setIcon(iconSurface)
    } catch (_: Exception) {
        ()
    }
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
