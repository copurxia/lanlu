package lwindow

// 窗口/显示相关的平台策略（对标 Chromium ozone 的 PlatformWindow 初始化决策）。
//
// 业务层只拿到“最终几何 + 是否已就绪”，不关心是哪个平台、用哪个渲染后端。
// 目前收敛：窗口初始几何与缩放、渲染驱动优先级、桌面集成（libdecor 插件）、系统字体。

import std.env.{getVariable, setVariable}
import std.fs.{canonicalize, exists, Path}
import sdl.displays.{DisplayInfo, primaryDisplayInfo}
import sdl.system.{SdlHint, SdlHints}

// 窗口初始几何（逻辑尺寸 + 缩放因子）。
public struct WindowGeometry {
    public let width: Int32
    public let height: Int32
    public let scale: Float32

    public init(width: Int32, height: Int32, scale: Float32) {
        this.width = width
        this.height = height
        this.scale = scale
    }
}

// 最小可用布局（低于此值不再按屏幕钳制，宁可超界也保住布局）。
let MIN_USABLE_W: Int32 = 960
let MIN_USABLE_H: Int32 = 640

// 启动时一次性缩放适配（ADR：不做运行时动态缩放）。
// pinScale=true 时不读取显示器缩放（CI 快照需要像素确定性）。
public func preferredWindowGeometry(defaultW: Int32, defaultH: Int32, pinScale!: Bool = false): WindowGeometry {
    if (pinScale) {
        return WindowGeometry(defaultW, defaultH, 1.0)
    }
    try {
        let geo = primaryDisplayInfo().geometry
        let scale = geo.contentScale
        // 逻辑尺寸钳制：保证 逻辑×scale ≤ 可用桌面区（150% 缩放的 1080p 上 1440×900 会超界）。
        let maxW = Int32(geo.usableBounds.w / scale)
        let maxH = Int32(geo.usableBounds.h / scale)
        let w = if (maxW >= MIN_USABLE_W && defaultW > maxW) { maxW } else { defaultW }
        let h = if (maxH >= MIN_USABLE_H && defaultH > maxH) { maxH } else { defaultH }
        return WindowGeometry(w, h, scale)
    } catch (_: Exception) {
        return WindowGeometry(defaultW, defaultH, 1.0)
    }
}

// 渲染驱动优先级：D3D/Metal（Windows/macOS 由 SDL 内置顺序保证）> vulkan > opengl > software。
// SDL3 内置把 opengl 排在 vulkan 前，故 Linux 桌面会话显式指定回退列表；用户显式设置永远优先。
public func prepareRendererHints(): Unit {
    let session = getVariable("XDG_SESSION_TYPE")
    let isDesktopLinux = session == Some("wayland") || session == Some("x11")
    if (!isDesktopLinux) {
        return
    }
    if (SdlHints.get(SdlHint.CustomHint("SDL_RENDER_DRIVER")).isSome()) {
        return
    }
    let driver = if (getVariable("LANLU_SOFTWARE_RENDER") == Some("1")) {
        "software"
    } else {
        "vulkan,opengl"
    }
    SdlHints.set(SdlHint.CustomHint("SDL_RENDER_DRIVER"), driver)
}

// 桌面集成：无边框窗口在 Wayland 下靠 libdecor 插件绘制装饰；
// 以可执行文件位置推导随仓库插件目录（不依赖启动目录），插件缺失则回退系统插件。
public func prepareDesktopIntegration(): Unit {
    match (LWINDOW_PLATFORM) {
        case LWindowPlatform.Ohos => return
        case LWindowPlatform.Desktop => ()
    }
    try {
        let exeDir = canonicalize(Path("/proc/self/exe")).parent.toString()
        let pluginDir = "${exeDir}/../../../../packages/cangjie-gui/sdl/libdecor-plugins"
        if (exists(Path("${pluginDir}/libdecor-cairo.so"))) {
            setVariable("LIBDECOR_PLUGIN_DIR", pluginDir)
        }
    } catch (_: Exception) {}
}

// 系统无 fontconfig 平台（OHOS）的默认无衬线字体；找不到返回 None，由 cui 走字体库回退。
public func systemSansFontPath(): Option<String> {
    let candidates = ["/system/fonts/HarmonyOS_Sans_SC.ttf"]
    for (p in candidates) {
        if (exists(Path(p))) {
            return Some(p)
        }
    }
    return None
}
