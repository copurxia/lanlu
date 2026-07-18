package lanlu_client_next

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.ui.*
import std.env.getVariable

// 根路由：按 model.page 切页（无路由框架，状态驱动）。
func rootView(model: AppModel): Unit {
    match (model.page.value) {
        case Page.Login => loginView(model)
        case Page.Library => libraryView(model)      // Task 8 提供
        case Page.Detail(_) => detailView(model)     // Task 9 提供
        case Page.Reader(_, _) => readerView(model)  // Task 10 提供
        case Page.Settings => settingsView(model)    // Task 11 提供
    }
}

main(): Int64 {
    // 在 Wayland 会话下，当前系统上的 SDL3 + libglycin/libdecor 初始化路径
    // 会在 SDL_CreateWindowAndRenderer 时触发 SIGSEGV。强制回退到 X11/XWayland
    // 可稳定启动；若用户已显式设置 SDL_VIDEODRIVER 则不覆盖其选择。
    if (getVariable("XDG_SESSION_TYPE") == "wayland" && SdlHints.get(SdlHint.VideoDriver).isNone()) {
        SdlHints.set(SdlHint.VideoDriver, "x11")
    }

    let settings = loadSettingsFrom(defaultSettingsPath())
    let model = AppModel(settings)
    model.tryResumeSession()
    let app = DesktopApp(WindowSpec("lanlu", 1440, 900), theme: lanluTheme())
    app.setMinimumSize(960, 640)
    app.run {
        FrameHandler(onFrame: { _ => model.pump() }) {
            ZStack {
                rootView(model)
                ToastLayer(model.toaster)
            }
        }
    }
    return 0
}
