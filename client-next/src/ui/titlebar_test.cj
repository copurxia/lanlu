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
