package lanlu_client_next

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.ui.*
import std.env.{getVariable, setVariable}
import std.fs.{canonicalize, exists, Path}

// 根路由：按 model.page 切页（无路由框架，状态驱动）。
func rootView(model: AppModel): Unit {
    match (model.page.value) {
        case Page.Login => loginView(model)
        case Page.Library => libraryView(model) // Task 8 提供
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
private var dragRegionHasBack = false

private func syncTitleBarDragRegion(window: SdlWindow, model: AppModel): Unit {
    let w = window.width
    let isReader = match (model.page.value) {
        case Page.Reader(_, _) => true
        case _ => false
    }
    let hasBack = match (model.page.value) {
        case Page.Detail(_) | Page.Tank(_) | Page.Settings => true
        case _ => false
    }
    let chrome = !isReader || model.reader.chromeVisible
    let readerPanelOpen = isReader && (model.readerSidebarOpen.value || model.readerSettingsOpen.value)
    if (w == dragRegionWidth && isReader == dragRegionReader && chrome == dragRegionChrome && readerPanelOpen ==
        dragRegionReaderPanel && hasBack == dragRegionHasBack) {
        return
    }
    dragRegionWidth = w
    dragRegionReader = isReader
    dragRegionChrome = chrome
    dragRegionReaderPanel = readerPanelOpen
    dragRegionHasBack = hasBack
    // 不支持 hit-test 的视频驱动（如快照装置的 dummy）会拒绝注册：忽略即可，窗口照常
    // 可用，只是没有 OS 托管拖动（与 desktop_app 忽略光标/IME 锚点拒绝同一惯例）。
    try {
        if (isReader) {
            if (chrome && !readerPanelOpen) {
                window.setDragRegions(readerBarDragRects(w))
            } else {
                window.setDragRegions(Array<(Int32, Int32, Int32, Int32)>(0, repeat: (0, 0, 0, 0)))
            }
        } else {
            window.setDragRegions(titleBarDragRects(w, hasBack))
        }
    } catch (_: Exception) {
        ()
    }
}

main(): Int64 {
    initializeSettingsStore()
    // 启动后端策略（2026-07-19 Task E2 实测，详见 .superpowers/sdd/task-e2-report.md）：
    // 原生 Wayland 启动崩溃根因 = libdecor 的 GTK 插件在窗口创建时初始化 GTK3，
    // 触发 glycin（本体经 libvips→librsvg→gdk_pixbuf 常驻进程，无法移除）的
    // 初始化竞态 SIGSEGV。对策：把 LIBDECOR_PLUGIN_DIR 指向随仓库发布的
    // libdecor-cairo 插件（无 GTK 依赖，装饰照常绘制），GTK 插件不再加载，
    // 原生 Wayland 20/20 启动 0 SIGSEGV。渲染驱动优先级见下方独立段落。
    // 用户显式设置 LIBDECOR_PLUGIN_DIR / SDL_VIDEODRIVER / SDL_RENDER_DRIVER 时不覆盖。
    if (getVariable("XDG_SESSION_TYPE") == "wayland") {
        if (getVariable("LIBDECOR_PLUGIN_DIR").isNone()) {
            // 以 /proc/self/exe 定位可执行文件再推导随仓库插件目录（不依赖启动目录），
            // 检查到具体 .so 文件才设置——目录在而插件缺失时回退系统插件，避免无装饰窗口。
            // 可执行文件位于 client-next/target/release/bin/，向上四级即仓库根。
            let exeDir = canonicalize(Path("/proc/self/exe")).parent.toString()
            let pluginDir = "${exeDir}/../../../../packages/cangjie-gui/sdl/libdecor-plugins"
            if (exists(Path("${pluginDir}/libdecor-cairo.so"))) {
                setVariable("LIBDECOR_PLUGIN_DIR", pluginDir)
            }
        }
    }
    // 渲染驱动优先级策略：D3D/Metal > vulkan > opengl > software。
    // Windows/macOS 不动——SDL 内置顺序里 D3D11/12、Metal 本来就在最前，自动选择即正确；
    // 但 SDL3 内置顺序把 opengl 排在 vulkan 之前（SDL_render.c），故 Linux 桌面会话
    // （wayland/x11）下显式默认 vulkan；创建失败 SDL 自动回退 opengl → software。
    // LANLU_SOFTWARE_RENDER=1 强制 software 兜底；用户显式 SDL_RENDER_DRIVER 永远优先。
    if ((getVariable("XDG_SESSION_TYPE") == "wayland" || getVariable("XDG_SESSION_TYPE") == "x11") &&
        SdlHints.get(SdlHint.CustomHint("SDL_RENDER_DRIVER")).isNone()) {
        let driver = if (getVariable("LANLU_SOFTWARE_RENDER") == Some("1")) {
            "software"
        } else {
            "vulkan"
        }
        SdlHints.set(SdlHint.CustomHint("SDL_RENDER_DRIVER"), driver)
    }

    // ── 临时快照装置（验证专用，用后逐字还原）：--seed-browse/--seed-search/
    // --seed-detail/--seed-tank/--seed-settings
    // 离线播种假数据，跳过磁盘配置与会话恢复；--width N 覆盖窗口宽（默认 1440）。
    let seedMode = harnessSeedMode()
    let settings = if (seedMode.size > 0) {
        let s = AppSettings()
        s.serverUrl = "https://demo.lanlu.local"
        // 亮主题快照：种子模式跳过磁盘配置，唯独 theme 取自磁盘——隔离 HOME 预置
        // MMKV 中 theme=light 即可拍亮主题快照，其余字段保持离线默认。
        s.theme = loadSettings().theme
        s
    } else {
        loadSettings()
    }
    let model = AppModel(settings, persistSettings: {s => saveSettings(s)})
    if (seedMode.size > 0) {
        seedLibrarySnapshot(model, seedMode)
    } else {
        model.tryResumeSession()
    }
    let app = DesktopApp(WindowSpec("lanlu", harnessWindowWidth(), harnessWindowHeight()),
        theme: lanluThemeFor(settings.theme))
    // 设置页主题切换的应用路径：model.setTheme 落盘后回调这里，运行时替换主题即切即生效。
    model.themeChangeHandler = {mode => app.setTheme(lanluThemeFor(mode))}
    app.setMinimumSize(960, 640)
    // 无边框窗口：移除 OS 装饰，标题栏由 ui/titlebar.cj 自绘（Task 8）；
    // 阅读器页换用专用顶栏 ui/reader_bar.cj（T13）。
    app.sdlWindow.setBordered(false)
    syncTitleBarDragRegion(app.sdlWindow, model)
    // 空转零渲染：主循环每次迭代泵回工作线程结果（drain 为空时不写任何 State，
    // dirty-frame skipping 使该迭代不重建/不绘制）；不能用 FrameHandler 做这件事——
    // 它必须每帧 requestFrame 才能持续触发，会强制 60fps 全量重建+绘制。
    app.onTick = {
        =>
            model.pump()
            let ww = Int64(app.sdlWindow.width)
            if (ww != model.windowWidth.value) {
                model.windowWidth.value = ww
            }
            syncTitleBarDragRegion(app.sdlWindow, model)
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
            ToastLayer(model.toaster)
        }
    }
    model.close()
    closeSettingsStore()
    return 0
}
