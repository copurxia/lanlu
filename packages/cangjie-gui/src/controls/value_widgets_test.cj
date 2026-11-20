package cui.controls

import cui.core.State

@Test
func sliderBufferedDefaultsToZero(): Unit {
    let slider = Slider(State<Float32>(50.0), key: "buf-default", lower: 0.0, upper: 100.0)
    @Expect(slider.bufferedValue, Float32(0.0))
}

@Test
func sliderBufferedClamped(): Unit {
    let high = Slider(State<Float32>(50.0), key: "buf-high", lower: 0.0, upper: 100.0).buffered(1.5)
    @Expect(high.bufferedValue, Float32(1.0))

    let low = Slider(State<Float32>(50.0), key: "buf-low", lower: 0.0, upper: 100.0).buffered(-0.25)
    @Expect(low.bufferedValue, Float32(0.0))

    let mid = Slider(State<Float32>(50.0), key: "buf-mid", lower: 0.0, upper: 100.0).buffered(0.62)
    @Expect(mid.bufferedValue, Float32(0.62))
}

@Test
func sliderBufferedDoesNotAffectValue(): Unit {
    let value = State<Float32>(40.0)
    Slider(value, key: "buf-value", lower: 0.0, upper: 100.0).buffered(0.8)
    @Expect(value.value, Float32(40.0))
}
