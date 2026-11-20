/*
 * 系统信息文案：把 CPU/显示器/电源查询结果压成概览页的一行行事实。
 * 除 systemFacts() 外全部是纯格式化函数，与渲染解耦，可独立替换或测试。
 */
package cui_process_manager

import cui.{DisplayInfo, DisplayMode, PowerInfo, PowerState, allDisplayInfos, cpuInfo, platformName, powerInfo}

/* 概览页一张事实卡片的标题与内容。 */
struct SystemFact {
    let title: String
    let value: String

    init(title: String, value: String) {
        this.title = title
        this.value = value
    }
}

// 硬件与电源查询的调用点集中在此，卡片顺序即页面展示顺序。
func systemFacts(): Array<SystemFact> {
    [
        SystemFact("系统", systemLine()),
        SystemFact("显示器", displayLine(allDisplayInfos())),
        SystemFact("电源", powerSummary(powerInfo()))
    ]
}

func systemLine(): String {
    let cpu = cpuInfo()
    "${platformName()} | ${cpu.logicalCores} 个逻辑核心 | ${cpu.systemRamMb} MiB 内存"
}

// 无头环境或驱动异常时可能一台显示器都枚举不到；与 modeLabel 一样给出兜底文案，
// 而不是让空数组下标越界拖垮整个应用。
func displayLine(displays: Array<DisplayInfo>): String {
    if (displays.isEmpty()) {
        return "未检测到显示器"
    }
    let display = displays[0]
    "${displays.size} 台显示器 | ${display.name} ${modeLabel(display.modes.current)} | 缩放 ${display.geometry.contentScale}"
}

func modeLabel(mode: ?DisplayMode): String {
    match (mode) {
        case Some(value) => "${value.width}x${value.height} @ ${Int64(value.refreshRate)} Hz"
        case None => "显示模式未知"
    }
}

func powerSummary(info: PowerInfo): String {
    "${powerStateLabel(info.state)} | ${percentLabel(info.percent)}"
}

func powerStateLabel(state: PowerState): String {
    match (state) {
        case PowerState.Error => "不可用"
        case PowerState.Unknown => "未知"
        case PowerState.OnBattery => "使用电池"
        case PowerState.NoBattery => "已接通电源"
        case PowerState.Charging => "充电中"
        case PowerState.Charged => "已充满"
    }
}

func percentLabel(percent: ?Int32): String {
    match (percent) {
        case Some(value) => "${value}%"
        case None => "电量未知"
    }
}
