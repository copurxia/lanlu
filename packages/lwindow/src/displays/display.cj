package lwindow.displays

// 显示器信息（P6 自 lgui.displays 迁入：平台事实归平台层）。
// P5 已去 SDL：OHOS 单逻辑屏（= 窗口），尺寸/缩放由 L 层窗口提供，这里返回占位信息。

import lbase.{CuiException, Rect}

public enum DisplayOrientation {
    | Unknown
    | Landscape
    | LandscapeFlipped
    | Portrait
    | PortraitFlipped
}

public struct DisplayMode {
    public let width: Int32
    public let height: Int32
    public let pixelDensity: Float32
    public let refreshRate: Float32

    public init(width: Int32, height: Int32, pixelDensity: Float32, refreshRate: Float32) {
        this.width = width
        this.height = height
        this.pixelDensity = pixelDensity
        this.refreshRate = refreshRate
    }
}

public struct DisplayGeometry {
    public let bounds: Rect
    public let usableBounds: Rect
    public let contentScale: Float32

    public init(bounds: Rect, usableBounds: Rect, contentScale: Float32) {
        this.bounds = bounds
        this.usableBounds = usableBounds
        this.contentScale = contentScale
    }
}

public struct DisplayOrientations {
    public let natural: DisplayOrientation
    public let current: DisplayOrientation

    public init(natural: DisplayOrientation, current: DisplayOrientation) {
        this.natural = natural
        this.current = current
    }
}

public struct DisplayModes {
    public let desktop: ?DisplayMode
    public let current: ?DisplayMode

    public init(desktop: ?DisplayMode, current: ?DisplayMode) {
        this.desktop = desktop
        this.current = current
    }
}

public struct DisplayInfo {
    public let id: UInt32
    public let name: String
    public let geometry: DisplayGeometry
    public let orientations: DisplayOrientations
    public let modes: DisplayModes

    public init(
        id: UInt32,
        name: String,
        geometry: DisplayGeometry,
        orientations: DisplayOrientations,
        modes: DisplayModes
    ) {
        this.id = id
        this.name = name
        this.geometry = geometry
        this.orientations = orientations
        this.modes = modes
    }
}

/**
 * Throws `CuiException` when the requested display does not exist.
 */
public func primaryDisplayInfo(): DisplayInfo {
    // P5：无 SDL —— OHOS 只有一块逻辑屏幕
    displayInfo(0)
}

/**
 * Throws `CuiException` when the requested display does not exist.
 */
public func displayInfo(id: UInt32): DisplayInfo {
    ensureDisplayId(id)
    // P5：无 SDL。屏幕尺寸/缩放由 L 层窗口提供；这里返回占位信息（当前无人消费）。
    let name = "ohos"
    let geometry = DisplayGeometry(Rect(0.0, 0.0, 0.0, 0.0), Rect(0.0, 0.0, 0.0, 0.0), 1.0)
    let orientations = DisplayOrientations(DisplayOrientation.Landscape, DisplayOrientation.Landscape)
    let modes = DisplayModes(None, None)
    DisplayInfo(id, name, geometry, orientations, modes)
}

// P5：原本校验 SDL 显示器 id，现在只有一块逻辑屏幕。
internal func ensureDisplayId(id: UInt32): Unit {
    if (id != 0) {
        throw CuiException("display id 不存在: ${id}")
    }
}
