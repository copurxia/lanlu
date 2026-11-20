package cui.base

// P5：窗口状态查询改为 L 层自身状态（无 SDL 窗口可查）。
// 只保留实际被调用的 API；未使用的查询/抓取类接口已随 SDL 窗口一起移除。

extend SdlWindow {
    public func title(): String {
        titleValue()
    }

    /// L 层窗口恒为「无系统装饰 + 可缩放」，不再查 SDL 标志位。
    public func windowFlags(): WindowFlags {
        windowFlagsFromRaw(0)   // L 层窗口无 SDL 标志位
    }
}
