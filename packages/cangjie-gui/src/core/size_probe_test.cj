package cui.core

import lbase.Rect
// 布局后宽度写入 State；未变化时不重复推进（setIfChanged 返回 false）。
@Test
func sizeProbeReportsLayoutWidth(): Unit {
    let ctx = testContext()
    let w = State<Float32>(0.0)
    let probe = SizeProbe(width: w) {
        emit(Spacer())
    }
    probe.layout(ctx, Rect(0.0, 0.0, 640.0, 480.0))
    @Expect(w.value, Float32(640.0))
    @Expect(w.setIfChanged(640.0), false) // 同值不再写入
    probe.layout(ctx, Rect(0.0, 0.0, 800.0, 480.0))
    @Expect(w.value, Float32(800.0))
}

// 可选高度 State 同步上报；子视图按同一矩形布局（透传不改布局）。
@Test
func sizeProbeReportsHeightAndLaysOutChild(): Unit {
    let ctx = testContext()
    let w = State<Float32>(0.0)
    let h = State<Float32>(0.0)
    let child = LayoutProbe()
    let probe = SizeProbe(width: w, height: h) {
        emit(child)
    }
    probe.layout(ctx, Rect(10.0, 20.0, 300.0, 200.0))
    @Expect(w.value, Float32(300.0))
    @Expect(h.value, Float32(200.0))
    @Expect(child.rect.x, Float32(10.0))
    @Expect(child.rect.w, Float32(300.0))
}
