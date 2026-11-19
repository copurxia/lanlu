package lwindow

// 窗口/显示相关的平台策略（对标 Chromium ozone 的 PlatformWindow 初始化决策）。
//
// 业务层只拿到“最终几何 + 是否已就绪”，不关心是哪个平台、用哪个渲染后端。
// 目前收敛：窗口初始几何与缩放、桌面集成（libdecor 插件）、系统字体。（渲染驱动 hint 随 P5 删除 SDL 壳一并移除：SDL 渲染器已无运行时初始化路径。）

import std.fs.{exists, Path}
import lwindow.displays.{DisplayInfo, primaryDisplayInfo}

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
    // LANLU_LWP=1：窗口尺寸由壳的 window.configure 决定（计划 §7：configure 是唯一尺寸来源）。
    // 有界等待（300ms）：壳还没起来时保持旧行为，绝不无限等——这是 M0-4 教训的直接应用。
    let cfg = lwpAwaitInitialConfigure(300)
    match (cfg) {
        case Some((w, h)) =>
            if (w > 0 && h > 0) {
                // 壳给的尺寸是**物理像素**；逻辑尺寸 = 物理 / scale。
                // 不做这个除法时，PC 模式 150%/200% 缩放下内容只铺满左上角（第 116 轮真机症状）。
                let sc = lwpReportedScale()
                let lw = Int32(Float64(w) / Float64(sc))
                let lh = Int32(Float64(h) / Float64(sc))
                return WindowGeometry(if (lw > 0) { lw } else { Int32(w) },
                    if (lh > 0) { lh } else { Int32(h) }, sc)
            }
            ()   // 收到但无效：继续走本地策略
        case None => ()
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

// 桌面集成：历史遗留 —— 曾从仓库内 packages/cangjie-gui/sdl/libdecor-plugins 注入
// LIBDECOR_PLUGIN_DIR。P6 吸收后该目录已删除（exists 分支永远不成立），且桌面壳现在走
// lplatform-wayland 自己的 xdg-shell 路径、不链接 libdecor。保留空实现供调用方兼容，
// 回退系统插件的行为不变。
public func prepareDesktopIntegration(): Unit {
    ()
}

// 系统无 fontconfig 平台（OHOS）的默认无衬线字体；找不到返回 None，由 cui 走字体库回退。
public func systemSansFontPath(): Option<String> {
    // 1) 壳通过 lw_system.info 下发的字体目录（计划 §8：系统事实由平台层提供，引擎不猜路径）
    match (lwpSystemInfo()) {
        case Some((_, _, fontDir, _, _)) =>
            if (fontDir.size > 0) {
                for (name in ["HarmonyOS_Sans_SC.ttf", "HarmonyOS_Sans.ttf", "NotoSansCJK-Regular.ttc"]) {
                    let p = fontDir + "/" + name
                    if (exists(Path(p))) {
                        return Some(p)
                    }
                }
            }
        case None => ()
    }
    // 2) 回落：已知候选路径
    let candidates = ["/system/fonts/HarmonyOS_Sans_SC.ttf"]
    for (p in candidates) {
        if (exists(Path(p))) {
            return Some(p)
        }
    }
    return None
}
