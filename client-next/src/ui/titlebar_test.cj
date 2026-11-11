package lanlu_client_next.ui

import cui.*

private func expectRect(rect: (Int32, Int32, Int32, Int32), x: Int32, w: Int32): Unit {
    @Expect(rect[0], x)
    @Expect(rect[1], 0)
    @Expect(rect[2], w)
    @Expect(rect[3], TITLEBAR_HEIGHT)
}

@Test
func titleBarDragRectsFullWidthWithoutExclusions(): Unit {
    let rects = titleBarDragRects(1600, [])
    @Expect(rects.size, 1)
    expectRect(rects[0], 0, 1600)
}

@Test
func titleBarDragRectsIgnoreBelowBand(): Unit {
    // 正文区控件（y ≥ 顶栏高）不影响顶栏拖动区。
    let below = Rect(400.0, 200.0, 100.0, 40.0)
    let rects = titleBarDragRects(1600, [below])
    @Expect(rects.size, 1)
    expectRect(rects[0], 0, 1600)
}

@Test
func titleBarDragRectsComplementOfControls(): Unit {
    // 搜索框 [460, 920) + 右侧窗口控制簇 [1300, 1420)：空隙 = 左/中/右三块。
    let search = Rect(460.0, 11.0, 460.0, 34.0)
    let controls = Rect(1300.0, 13.0, 120.0, 30.0)
    let rects = titleBarDragRects(1440, [search, controls])

    @Expect(rects.size, 3)
    expectRect(rects[0], 0, 460)
    expectRect(rects[1], 920, 380)
    expectRect(rects[2], 1420, 20)
}

@Test
func titleBarDragRectsMergeOverlappingAndClip(): Unit {
    // 重叠区间合并；越出窗口右缘的占位按窗口宽裁剪。
    let a = Rect(100.0, 10.0, 200.0, 30.0)
    let b = Rect(250.0, 12.0, 200.0, 30.0)
    let c = Rect(900.0, 10.0, 200.0, 30.0) // 右端 1100 超出窗口宽 1000
    let rects = titleBarDragRects(1000, [a, b, c])

    @Expect(rects.size, 2)
    expectRect(rects[0], 0, 100)
    expectRect(rects[1], 450, 450)
}

@Test
func titleBarDragRectsDropSlivers(): Unit {
    // 两端各留 5vp 缝隙（< MIN_DRAG_GAP 8）：不注册细碎命中区，整段并入避让。
    let mid = Rect(5.0, 10.0, 990.0, 30.0)
    let rects = titleBarDragRects(1000, [mid])
    @Expect(rects.size, 0)
}


// ── 三键平台化（docs/lwindow-title-buttons-plan.md）───────────────────────
// platformTitleButtonsWidth 的决策表：能力位未宣告 → 0（自绘回退）；
// 宣告 + rect 到达 → 物理宽 / 密度；宣告 + rect 未到 → 文档默认 140vp + 8。

@Test
func platformTitleButtonsWidthZeroWithoutCapability(): Unit {
    // 宿主（无 LWP 通道）：能力位必然未宣告 → 业务层应自绘三键
    @Expect(platformTitleButtonsWidth(), 0.0)
}

@Test
func platformTitleButtonsWidthFallbackUsesDocumentedDefault(): Unit {
    // 能力位已宣告但 rect 未到时给文档默认值（140vp + 8 间距），
    // 避免启动期闪现自绘三键再消失。
    g_title_btn_visible = true
    g_title_btn_width_px = 0
    @Expect(platformTitleButtonsWidth(), 148.0)
    g_title_btn_visible = false
    g_title_btn_width_px = 0
}

@Test
func platformTitleButtonsWidthScalesReportedPixels(): Unit {
    // 真机实测：266px / 1.9 密度 = 140vp（官方文档三键区 140x37vp）
    g_title_btn_visible = true
    g_title_btn_width_px = 266
    let w = platformTitleButtonsWidth()
    @Expect(w > 139.0 && w < 141.0, true)
    // 壳应用配置后回报 256px → 134.7vp（避让随真实 rect 收紧）
    g_title_btn_width_px = 256
    let w2 = platformTitleButtonsWidth()
    @Expect(w2 > 134.0 && w2 < 135.5, true)
    g_title_btn_visible = false
    g_title_btn_width_px = 0
}

