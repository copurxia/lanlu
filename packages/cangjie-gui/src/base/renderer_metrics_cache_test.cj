package cui.base

/*
 * #3: the text-metrics cache key is the quantized rasterization size, so the scaled text-pass
 * path (every draw under supersampling) is cached exactly like the unscaled layout path, and
 * each distinct scale gets its own bucket. Headless the estimator is scale-independent, but the
 * compute counter still proves which path recomputed.
 */
@Test
func textMetricsCacheCoversScaledMeasurement(): Unit {
    let renderer = Renderer.headless()
    renderer.resetTextMeasureCount()
    renderer.setScale(2.0)
    let first = renderer.textWidth("缓存探头 probe", pointSize: 15.0)
    let second = renderer.textWidth("缓存探头 probe", pointSize: 15.0)
    @Expect(first, second) // 同一量化桶，读数一致（无布局抖动）
    @Expect(renderer.textMeasureCount(), UInt64(2))
    @Expect(renderer.textComputeCount(), UInt64(1)) // 第二次命中缓存——scaled 路径同样走缓存

    renderer.setScale(1.0)
    let _ = renderer.textWidth("缓存探头 probe", pointSize: 15.0)
    @Expect(renderer.textComputeCount(), UInt64(2)) // 不同缩放各有缓存桶，互不污染

    renderer.setScale(2.0)
    let _ = renderer.textWidth("缓存探头 probe", pointSize: 15.0)
    @Expect(renderer.textComputeCount(), UInt64(2)) // 回到 2x 仍然命中
}

/*
 * #16: AUTO_SUPERSAMPLE (0) adapts to the render driver — 1x on SDL's software renderer, the
 * hardware default (2x) elsewhere; an explicit factor always overrides the adaptation.
 */
@Test
func supersampleAdaptsToSoftwareDriverUnlessOverridden(): Unit {
    @Expect(resolveSupersample(AUTO_SUPERSAMPLE, "software"), Int32(1))
    @Expect(resolveSupersample(AUTO_SUPERSAMPLE, "opengl"), Int32(2))
    @Expect(resolveSupersample(AUTO_SUPERSAMPLE, "vulkan"), Int32(2))
    @Expect(resolveSupersample(AUTO_SUPERSAMPLE, "headless"), Int32(2))
    @Expect(resolveSupersample(Int32(2), "software"), Int32(2)) // 显式覆盖优先
    @Expect(resolveSupersample(Int32(1), "opengl"), Int32(1))
    @Expect(resolveSupersample(Int32(-3), "software"), Int32(1)) // 非法值钳到 1x
}
