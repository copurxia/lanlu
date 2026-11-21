package lanlu_client_next.ui

import cui.*

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

@Test
func webtoonGeometryMatchesContinuousColumn(): Unit {
    @Expect(webtoonContentWidth(1200.0), 800.0)
    @Expect(webtoonContentWidth(400.0), 368.0)
    @Expect(webtoonEstimatedHeight(800.0, 1000.0), 700.0)
    @Expect(webtoonImageHeight(400.0, 800.0, 800.0, 700.0), 1600.0)
    @Expect(webtoonImageHeight(0.0, 800.0, 800.0, 700.0), 700.0)
}

@Test
func webtoonIndexUsesThirtyPercentThresholdOffset(): Unit {
    let heights: Array<Float32> = [300.0, 500.0, 200.0]
    @Expect(webtoonContentHeight(heights), 1000.0)
    @Expect(webtoonOffsetBefore(heights, 0), 0.0)
    @Expect(webtoonOffsetBefore(heights, 2), 800.0)
    @Expect(webtoonIndexAtOffset(heights, 0.0), 0)
    @Expect(webtoonIndexAtOffset(heights, 299.0), 0)
    @Expect(webtoonIndexAtOffset(heights, 300.0), 1)
    @Expect(webtoonIndexAtOffset(heights, 999.0), 2)
    @Expect(webtoonIndexAtOffset(heights, 1200.0), 2)
}

@Test
func webtoonLazyRangeDoesNotLoadWholeArchive(): Unit {
    let heights = Array<Float32>(100, {_ => 100.0})
    let (firstAtTop, lastAtTop) = webtoonLazyRange(heights, 0.0, 500.0)
    @Expect(firstAtTop, 0)
    @Expect(lastAtTop, 24)

    let (firstAtMiddle, lastAtMiddle) = webtoonLazyRange(heights, 4000.0, 500.0)
    @Expect(firstAtMiddle, 21)
    @Expect(lastAtMiddle, 64)
    @Expect(lastAtMiddle - firstAtMiddle + 1 < heights.size, true)
}

@Test
func htmlOverflowCooldownAllowsAfterWindow(): Unit {
    // 距上次外溢 149ms：吞掉；150ms（含）：放行（150ms 冷却窗，防连续滚轮误翻）。
    @Expect(htmlOverflowTurnAllowed(0, 149, 150), false)
    @Expect(htmlOverflowTurnAllowed(0, 150, 150), true)
    @Expect(htmlOverflowTurnAllowed(0, 500, 150), true)
    // 从未外溢（lastMs 远负）：直接放行。
    @Expect(htmlOverflowTurnAllowed(-10000, 0, 150), true)
}

@Test
func htmlPaperFrameReservesChromeAndLaneSafeArea(): Unit {
    // 顶栏可见时 readerBody 已把舞台下推 52vp；HTML 自身再留纸面顶距，并在
    // 底部避开 48vp lane + 20vp bottom + 12vp 间隙。
    let visible = htmlPaperFrame(Rect(0.0, 52.0, 1440.0, 848.0), true)
    @Expect(visible.x, 0.0)
    @Expect(visible.y, 72.0)
    @Expect(visible.w, 1440.0)
    @Expect(visible.h, 748.0)
    // chrome 隐藏后顶栏与 lane 都退出，只保留上下普通页边距并吃回高度。
    let hidden = htmlPaperFrame(Rect(0.0, 0.0, 1440.0, 900.0), false)
    @Expect(hidden.x, 0.0)
    @Expect(hidden.y, 20.0)
    @Expect(hidden.w, 1440.0)
    @Expect(hidden.h, 860.0)
}

@Test
func htmlDockTypographyTierMappings(): Unit {
    @Expect(htmlFontTierIndex(13), 0)
    @Expect(htmlFontTierIndex(16), 1)
    @Expect(htmlFontTierIndex(19), 2)
    @Expect(htmlFontTierIndex(22), 3)
    @Expect(htmlFontTierPx(-1), 13)
    @Expect(htmlFontTierPx(4), 22)

    @Expect(htmlMarginTierIndex(24), 0)
    @Expect(htmlMarginTierIndex(48), 1)
    @Expect(htmlMarginTierIndex(72), 2)
    @Expect(htmlMarginTierPx(-1), 24)
    @Expect(htmlMarginTierPx(3), 72)
}
