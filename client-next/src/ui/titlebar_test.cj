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
// 决策表：平台不提供 → 0（自绘回退）；提供但 rect 未到 → 文档默认 148vp；
// rect 已到 → 物理宽 / 密度。

@Test
func titleButtonsWidthFallbackToSelfDrawn(): Unit {
    // 能力位未宣告（Wayland/宿主）→ 0，业务层自绘三键
    @Expect(titleButtonsWidthFor(false, false, 0, 1.0), 0.0)
    @Expect(titleButtonsWidthFor(false, true, 266, 1.9), 0.0)
}

@Test
func titleButtonsWidthUsesDocumentedDefaultBeforeRect(): Unit {
    // 平台提供三键但 rect 还没到：给 140vp + 8 间距，避免启动期闪一下自绘三键
    // （rectArrived 默认 true 表示「已收到壳的矩形回执」，此场景必须显式传 false）
    @Expect(titleButtonsWidthFor(true, false, 0, 1.9, rectArrived: false), 148.0)
    @Expect(titleButtonsWidthFor(true, true, 0, 1.9, rectArrived: false), 148.0)
}

@Test
func titleButtonsWidthScalesReportedPixels(): Unit {
    // 真机实测：266px @1.9 密度 = 140vp（官方文档三键区 140x37vp）
    let w1 = titleButtonsWidthFor(true, true, 266, 1.9)
    @Expect(w1 > 139.9 && w1 < 140.1, true)
    // 壳应用配置（margin 16/spacing 12/size 28）后回报 256px → 134.7vp
    let w2 = titleButtonsWidthFor(true, true, 256, 1.9)
    @Expect(w2 > 134.6 && w2 < 134.9, true)
    // 缩放缺失（0）时按 1x 兜底，不能除零
    @Expect(titleButtonsWidthFor(true, true, 140, 0.0), 140.0)
}

