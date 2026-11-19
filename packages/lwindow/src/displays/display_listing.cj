package lwindow.displays

// P5：显示器枚举已去 SDL。OHOS 上应用只有一块逻辑屏幕（= 窗口），
// 这里保留 API 形状，返回合成数据；真正的窗口尺寸由 L 层提供。

import std.collection.ArrayList
import lbase.{Point, Rect}

public struct FullscreenModeRequest {
    public let width: Int32
    public let height: Int32
    public let refreshRate: Float32
    public let includeHighDensityModes: Bool

    public init(
        width: Int32,
        height: Int32,
        refreshRate!: Float32 = 0.0,
        includeHighDensityModes!: Bool = true
    ) {
        this.width = width
        this.height = height
        this.refreshRate = refreshRate
        this.includeHighDensityModes = includeHighDensityModes
    }
}

/// 唯一显示器（OHOS 单屏）。
public func displayIds(): Array<UInt32> {
    [UInt32(0)]
}

public func allDisplayInfos(): Array<DisplayInfo> {
    let list = ArrayList<DisplayInfo>(1)
    list.add(displayInfo(0))
    list.toArray()
}

public func fullscreenDisplayModes(id: UInt32): Array<DisplayMode> {
    Array<DisplayMode>()
}

public func closestFullscreenDisplayMode(id: UInt32, request: FullscreenModeRequest): ?DisplayMode {
    None
}

public func displayInfoForPoint(point: Point): DisplayInfo {
    displayInfo(0)
}

public func displayInfoForRect(rect: Rect): DisplayInfo {
    displayInfo(0)
}
