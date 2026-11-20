package cui.controls

import std.collection.ArrayList
import lbase.{Rect, Size}
import cui.base.{MouseButton, Renderer, UiEvent}
import cui.core.{Theme, UiContext}

private func wordCloudTestContext(): UiContext {
    let ctx = UiContext(Renderer.headless(), Theme.light())
    ctx.viewportWidth = 800.0
    ctx.viewportHeight = 600.0
    ctx
}

@Test
func wordCloudPacksWeightedWordsWithoutDroppingTheLargest(): Unit {
    let ctx = wordCloudTestContext()
    let cloud = WordCloud(
        [
            WordCloudItem("a", "仓颉", 100.0),
            WordCloudItem("b", "图形界面", 50.0),
            WordCloudItem("c", "词云", 20.0)
        ]
    )
    let measured = cloud.measure(ctx, Size(640.0, 500.0))
    @Expect(measured.w, 640.0)
    @Expect(measured.h, 420.0)
    cloud.layout(ctx, Rect(0.0, 0.0, measured.w, measured.h))
    @Expect(cloud.visibleWordCount(), 3)
    cloud.draw(ctx)
}

@Test
func wordCloudIgnoresEmptyAndZeroWeightEntries(): Unit {
    let ctx = wordCloudTestContext()
    let cloud = WordCloud(
        [
            WordCloudItem("empty", "", 10.0),
            WordCloudItem("zero", "不可见", 0.0),
            WordCloudItem("valid", "可见", 1.0)
        ]
    )
    cloud.layout(ctx, Rect(0.0, 0.0, 400.0, 240.0))
    @Expect(cloud.visibleWordCount(), 1)
}

@Test
func wordCloudDispatchesClickForTheCentralLargestWord(): Unit {
    let ctx = wordCloudTestContext()
    let clicked = ArrayList<String>()
    let cloud = WordCloud([WordCloudItem("largest", "中心词", 10.0)], onClick: {item => clicked.add(item.key)})
    cloud.layout(ctx, Rect(0.0, 0.0, 400.0, 240.0))
    @Expect(cloud.handle(ctx, UiEvent.MouseDown(MouseButton.Left, 200.0, 120.0)))
    @Expect(clicked.size, 1)
    @Expect(clicked[0], "largest")
}

@Test
func wordCloudLargeInputCompletesAndRespectsDisplayLimit(): Unit {
    let ctx = wordCloudTestContext()
    let items = Array<WordCloudItem>(200, {
        i => WordCloudItem("tag-${i}", "标签${i}", Float64(200 - i))
    })
    let cloud = WordCloud(items)
    cloud.layout(ctx, Rect(0.0, 0.0, 1200.0, 480.0))
    @Expect(cloud.visibleWordCount() > 10)
    @Expect(cloud.visibleWordCount() <= 100)
}
