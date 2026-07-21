package lanlu_client_next.ui

// 长图滚动纯函数用例（reader_stage.cj 的宽适配高/最大偏移；滚动钳制在舞台内联，
// 边界语义 = maxOffset 处继续下滚翻页、0 处继续上滚翻页）。

@Test
func longPageFittedHeightCases(): Unit {
    // 1:3 长图按 800 宽适配 → 高 2400（溢出舞台）。
    @Expect(longPageFittedHeight(100.0, 300.0, 800.0), 2400.0)
    // 4:3 普通图按 800 宽适配 → 高 600。
    @Expect(longPageFittedHeight(400.0, 300.0, 800.0), 600.0)
    // 防御：零宽图/零宽舞台 → 0（调用方回落 contain）。
    @Expect(longPageFittedHeight(0.0, 300.0, 800.0), 0.0)
    @Expect(longPageFittedHeight(100.0, 300.0, 0.0), 0.0)
}

@Test
func longPageMaxOffsetCases(): Unit {
    // 溢出 1700 → 可滚 1700。
    @Expect(longPageMaxOffset(2400.0, 700.0), 1700.0)
    // 不溢出 → 0（不启用长图滚动，走 contain）。
    @Expect(longPageMaxOffset(600.0, 700.0), 0.0)
    @Expect(longPageMaxOffset(700.0, 700.0), 0.0)
}
