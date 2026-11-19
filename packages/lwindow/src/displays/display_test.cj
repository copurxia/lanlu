package lwindow.displays

// P6 自 lgui.displays 迁入：删除了引用 P5 已去 SDL 化死辅助函数
// （displayModeFromRaw/displayModesFromPointers 等）的陈旧用例，保留仍有效的行为测试。

@Test
func fullscreenModeRequestKeepsSafeDefaults(): Unit {
    let request = FullscreenModeRequest(1280, 720)

    @Expect(request.width, 1280)
    @Expect(request.height, 720)
    @Expect(request.refreshRate, 0.0)
    @Expect(request.includeHighDensityModes)
}

@Test
func displayIdsKeepsSingleLogicalScreen(): Unit {
    // OHOS 单逻辑屏（= 窗口）：id 恒为 0
    let ids = displayIds()
    @Expect(ids.size, Int64(1))
    @Expect(ids[0], UInt32(0))
}

@Test
func displayInfoRejectsUnknownId(): Unit {
    var threw = false
    try {
        let _ = displayInfo(7)
    } catch (_: Exception) {
        threw = true
    }
    @Expect(threw)
}
