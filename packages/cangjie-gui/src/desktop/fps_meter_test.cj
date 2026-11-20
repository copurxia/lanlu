package cui.desktop

import std.collection.ArrayList
import cui.base.UiEvent
// 帧率统计（FpsMeter）：60Hz 稳态读数 ≈ 60fps / 16.7ms；从空闲恢复的长间隔不计入帧时间。
@Test
func fpsMeterSteady60(): Unit {
    let m = FpsMeter()
    var t: UInt64 = 1_000_000_000
    for (_ in 0..180) {
        t += 16_666_667
        m.record(t, 4_000_000, 10_000_000)
    }
    let r = m.reading()
    @Expect(r.fps >= 58 && r.fps <= 61)
    @Expect(r.frameMs > 16.0 && r.frameMs < 17.5)
    @Expect(r.cpuMs > 3.9 && r.cpuMs < 4.1)
    @Expect(r.minFps >= 58)
}

@Test
func fpsMeterIgnoresIdleGap(): Unit {
    let m = FpsMeter()
    var t: UInt64 = 1_000_000_000
    for (_ in 0..30) {
        t += 16_666_667
        m.record(t, 1, 1)
    }
    t += 3_000_000_000   // 3s 空闲（零渲染）
    for (_ in 0..90) {
        t += 16_666_667
        m.record(t, 1, 1)
    }
    let r = m.reading()
    // 空闲间隔不应把平均/最大帧时间拉到秒级
    @Expect(r.maxFrameMs < 20.0)
}

@Test
func fpsTextFormatting(): Unit {
    @Expect(fmtMs(16.666), "16.7")
    @Expect(fmtMs(0.04), "0.0")
}
