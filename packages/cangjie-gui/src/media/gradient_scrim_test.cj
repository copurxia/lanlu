package cui.media

import lbase.{Color, Rect}
import cui.base.{Renderer, UiEvent}
import cui.core.{Theme, UiContext}

// 插值：中点取两色平均（含 alpha 通道）。
@Test
func gradientColorLerpsBetweenStops(): Unit {
    let stops = [(0.0f32, Color.rgba(0, 0, 0, 0)), (1.0f32, Color.rgba(100, 200, 255, 200))]
    let mid = gradientColorAt(stops, 0.5)
    @Expect(Int64(mid.r), 50)
    @Expect(Int64(mid.g), 100)
    @Expect(Int64(mid.b), 127) // 255*0.5 截断
    @Expect(Int64(mid.a), 100)
}

// 端点之外钳制到首/尾 stop 的颜色；多段时按所在段插值。
@Test
func gradientColorClampsOutsideStops(): Unit {
    let stops = [(0.2f32, Color.rgb(255, 0, 0)), (0.4f32, Color.rgb(0, 255, 0)), (0.8f32, Color.rgb(0, 0, 255))]
    @Expect(Int64(gradientColorAt(stops, 0.0).r), 255) // 首 stop 之前
    @Expect(Int64(gradientColorAt(stops, 1.0).b), 255) // 尾 stop 之后
    @Expect(Int64(gradientColorAt(stops, 0.3).r), 127) // 红→绿段中点
    @Expect(Int64(gradientColorAt(stops, 0.3).g), 127)
}

// 空 stops 全透明；单 stop 恒为该色。
@Test
func gradientColorDegenerateStops(): Unit {
    @Expect(Int64(gradientColorAt([], 0.5).a), 0)
    let single = [(0.3f32, Color.rgb(9, 8, 7))]
    @Expect(Int64(gradientColorAt(single, 0.0).g), 8)
    @Expect(Int64(gradientColorAt(single, 1.0).g), 8)
}

// 乱序 stops 构造时排序；控件不消费事件、可弹性填充。
@Test
func scrimSortsStopsAndIgnoresEvents(): Unit {
    let ctx = UiContext(Renderer.headless(), Theme.light())
    let scrim = GradientScrim(direction: GradientDirection.Bottom, stops: [
        (1.0f32, Color.rgba(0, 0, 0, 255)),
        (0.0f32, Color.rgba(0, 0, 0, 0))
    ])
    scrim.layout(ctx, Rect(0.0, 0.0, 100.0, 50.0))
    @Expect(scrim.handle(ctx, UiEvent.MouseMove(10.0, 10.0)), false)
    @Expect(scrim.isFlexible(), true)
    scrim.draw(ctx) // headless 渲染器：验证不抛异常即可
}
