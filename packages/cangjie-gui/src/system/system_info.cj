package cui.system

import lbase.CuiException

import cui.base.{ensureSdl}

public enum PowerState {
    | Error
    | Unknown
    | OnBattery
    | NoBattery
    | Charging
    | Charged
}

public struct PowerInfo {
    public let state: PowerState
    public let seconds: ?Int32
    public let percent: ?Int32

    public init(state: PowerState, seconds: ?Int32, percent: ?Int32) {
        this.state = state
        this.seconds = seconds
        this.percent = percent
    }
}

public struct CpuInfo {
    public var logicalCores: Int32 = 0
    public var cacheLineBytes: Int32 = 0
    public var systemRamMb: Int32 = 0
    public var pageBytes: Int32 = 0
    public var hasAltiVec: Bool = false
    public var hasMmx: Bool = false
    public var hasSse: Bool = false
    public var hasSse2: Bool = false
    public var hasSse3: Bool = false
    public var hasSse41: Bool = false
    public var hasSse42: Bool = false
    public var hasAvx: Bool = false
    public var hasAvx2: Bool = false
    public var hasAvx512F: Bool = false
    public var hasArmSimd: Bool = false
    public var hasNeon: Bool = false
    public var hasLsx: Bool = false
    public var hasLasx: Bool = false
}

public func platformName(): String {
    "OHOS"   // P5：无 SDL
}

public func cpuInfo(): CpuInfo {
    // P5：无 SDL。当前功能未使用该信息；需要时接 OHOS 系统参数。
    var info = CpuInfo()
    info.logicalCores = 8
    info.cacheLineBytes = 64
    info.systemRamMb = 0
    info.pageBytes = 4096
    info.hasNeon = true
    info.hasArmSimd = true
    info
}

public func powerInfo(): PowerInfo {
    // P5：无 SDL；电源信息未使用（需要时接 OHOS batteryInfo）
    PowerInfo(PowerState.Unknown, 0, 0)
}

/**
 * Throws `CuiException` when SDL cannot ask the operating system to open a URL handler.
 */
public func openUrl(url: String): Unit {
    // P5：无 SDL；打开链接应由 L 层（ArkTS openLink）实现
    throw CuiException("openUrl 未在 L 层实现: ${url}")
}

internal func powerStateFromCode(code: Int32): PowerState {
    match (code) {
        case -1 => PowerState.Error
        case 1 => PowerState.OnBattery
        case 2 => PowerState.NoBattery
        case 3 => PowerState.Charging
        case 4 => PowerState.Charged
        case _ => PowerState.Unknown
    }
}

private func nonNegative(value: Int32): ?Int32 {
    if (value >= 0) {
        Some(value)
    } else {
        None
    }
}
