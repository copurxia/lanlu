package lanlu_client_next.ui

@Test
func titleBarDragRectsReserveFilterButtonSlot(): Unit {
    let withoutFilter = titleBarDragRects(1600, false, false)
    let withFilter = titleBarDragRects(1600, false, true)

    @Expect(withoutFilter.size, 3)
    @Expect(withFilter.size, 3)
    @Expect(withoutFilter[1][2], 90)
    @Expect(withoutFilter[2][0], 870)
    @Expect(withFilter[1][2], 68)
    @Expect(withFilter[2][0], 892)
}

@Test
func titleBarDragRectsDoNotCoverFilterAtMinimumWidth(): Unit {
    let rects = titleBarDragRects(960, false, true)
    @Expect(rects.size, 1)
}
