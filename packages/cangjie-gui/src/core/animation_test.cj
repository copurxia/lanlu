package cui.core

import std.math.abs
import lbase.{Rect, Size}
import cui.base.{FrameInfo, UiEvent}

/*
 * The spring eases toward its target across ticks and settles exactly onto it, so an idle
 * spring is free and a static first frame (target == start) never animates. A clamped
 * timestep keeps a long frame hitch from diverging.
 */
@Test
func springEasesTowardTargetAndSettles(): Unit {
    let spring = Spring(0.0)
    @Expect(spring.settled()) // starts at its target

    spring.target(1.0)
    @Expect(!spring.settled())

    var i = 0
    while (i < 400 && !spring.settled()) {
        spring.tick(UInt64(16))
        i += 1
    }
    @Expect(spring.settled())
    @Expect(spring.value, Float32(1.0))
    @Expect(i < 400) // converged well within the budget
}

@Test
func springRetargetsMidFlight(): Unit {
    let spring = Spring(0.0)
    spring.target(1.0)
    spring.tick(UInt64(16))
    spring.tick(UInt64(16))
    let mid = spring.value
    @Expect(mid > Float32(0.0))
    @Expect(mid < Float32(1.0))

    spring.target(0.0)
    var i = 0
    while (i < 400 && !spring.settled()) {
        spring.tick(UInt64(16))
        i += 1
    }
    @Expect(spring.value, Float32(0.0))
}

@Test
func springResetSnapsWithoutAnimating(): Unit {
    let spring = Spring(0.0)
    spring.target(1.0)
    spring.reset(0.5)
    @Expect(spring.settled())
    @Expect(spring.value, Float32(0.5))
}

// The draw-time convenience retargets and advances in one call, returning the new value; over
// enough frames it reaches the target and settles.
@Test
func springAnimateRetargetsAdvancesAndReturnsValue(): Unit {
    let spring = Spring(0.0)
    // A fresh spring starts settled; animate itself sets the target, so drive a fixed number of
    // frames rather than guarding on settled().
    let first = spring.animate(target: 1.0, deltaMs: UInt64(16))
    @Expect(first > Float32(0.0)) // moved off the start on the first frame
    @Expect(first < Float32(1.0))

    var v: Float32 = first
    for (_ in 0..400) {
        v = spring.animate(target: 1.0, deltaMs: UInt64(16))
    }
    @Expect(spring.settled())
    @Expect(v, Float32(1.0))
    @Expect(spring.value, Float32(1.0))
}

// animate(target, deltaMs) is exactly target(goal) + tick(delta) + read value — the same
// trajectory, just folded into one call.
@Test
func springAnimateMatchesTargetThenTick(): Unit {
    let viaAnimate = Spring(0.0)
    let viaSteps = Spring(0.0)
    var i = 0
    while (i < 30) {
        let a = viaAnimate.animate(target: 1.0, deltaMs: UInt64(16))
        viaSteps.target(1.0)
        viaSteps.tick(UInt64(16))
        @Expect(a, viaSteps.value)
        i += 1
    }
}

@Test
func springClampsHugeTimestepInsteadOfDiverging(): Unit {
    let spring = Spring(0.0)
    spring.target(1.0)
    spring.tick(UInt64(100000)) // a 100-second hitch
    @Expect(spring.value >= Float32(0.0))
    @Expect(spring.value <= Float32(2.0)) // bounded: the clamp prevented a blow-up
}

// The ctx form keeps frames coming while the spring is in motion, so the dirty-frame loop (档 0) does
// not idle mid-transition and freeze a switch/radio/progress animation; a settled spring asks for
// nothing, so an idle control still costs no frames.
@Test
func springCtxAnimateRequestsFrameWhileMoving(): Unit {
    let ctx = testContext()
    ctx.frame = FrameInfo(UInt64(16), UInt64(16)) // deltaMs = 16
    let spring = Spring(0.0)

    // Already at its target: no motion, no request.
    let _ = ctx.takeFrameRequest()
    let _ = spring.animate(ctx, target: 0.0)
    @Expect(!ctx.takeFrameRequest())

    // Retargeted away: now moving, so it must ask for the next frame.
    let _ = ctx.takeFrameRequest()
    let _ = spring.animate(ctx, target: 1.0)
    @Expect(!spring.settled())
    @Expect(ctx.takeFrameRequest())

    // Drive it to rest, then it stops asking.
    var i = 0
    while (i < 400 && !spring.settled()) {
        let _ = spring.animate(ctx, target: 1.0)
        i += 1
    }
    @Expect(spring.settled())
    let _ = ctx.takeFrameRequest()
    let _ = spring.animate(ctx, target: 1.0)
    @Expect(!ctx.takeFrameRequest())
}

/*
 * A tween runs a fixed-duration eased interpolation on the frame clock: `start` arms the leg's
 * zero time, ticks advance toward a target, and the value snaps exactly onto the target at the
 * end so an idle tween is settled. Unlike the spring there is no overshoot — the easing curve
 * shapes the whole leg — which is what reader lane/page transitions want.
 */
@Test
func tweenProgressesAndSettles(): Unit {
    let tw = Tween(100, Easing.linear)
    tw.start(atMs: UInt64(0))
    let _ = tw.tick(atMs: UInt64(50), target: 1.0)
    @Expect(abs(tw.value - Float32(0.5)) < Float32(0.01))
    let _ = tw.tick(atMs: UInt64(120), target: 1.0)
    @Expect(tw.settled())
    @Expect(tw.value, Float32(1.0))
}

// The easing curve shapes the leg: easeOutCubic(0.5) = 1 - 0.5^3 = 0.875.
@Test
func tweenAppliesEasingCurve(): Unit {
    let tw = Tween(100, Easing.easeOutCubic)
    tw.start(atMs: UInt64(0))
    let _ = tw.tick(atMs: UInt64(50), target: 1.0)
    @Expect(abs(tw.value - Float32(0.875)) < Float32(0.001))
}

// A new target mid-flight starts a fresh leg from the current value at the retarget time, so a
// reversed transition eases back from wherever it had reached instead of jumping.
@Test
func tweenRetargetStartsNewLegFromCurrentValue(): Unit {
    let tw = Tween(100, Easing.linear)
    tw.start(atMs: UInt64(0))
    let _ = tw.tick(atMs: UInt64(50), target: 1.0) // 0.5
    let _ = tw.tick(atMs: UInt64(60), target: 0.0) // reverse: leg 0.5 -> 0.0 from t=60
    let _ = tw.tick(atMs: UInt64(110), target: 0.0) // halfway back
    @Expect(abs(tw.value - Float32(0.25)) < Float32(0.01))
    let _ = tw.tick(atMs: UInt64(200), target: 0.0)
    @Expect(tw.settled())
    @Expect(tw.value, Float32(0.0))
}

@Test
func tweenResetSnapsWithoutAnimating(): Unit {
    let tw = Tween(100, Easing.linear)
    tw.reset(1.0)
    @Expect(tw.settled())
    @Expect(tw.value, Float32(1.0))
}

// Every easing pins the endpoints exactly (a completed transition lands precisely) and
// easeInOutCubic is symmetric through the midpoint.
@Test
func easingEndpointsStayPinned(): Unit {
    let curves: Array<(Float32) -> Float32> = [Easing.linear, Easing.easeOutCubic, Easing.easeInOutCubic]
    for (e in curves) {
        @Expect(e(Float32(0.0)), Float32(0.0))
        @Expect(e(Float32(1.0)), Float32(1.0))
    }
    @Expect(Easing.easeInOutCubic(Float32(0.5)), Float32(0.5))
}

// The ctx form keeps frames coming while a leg is in flight (dirty-frame loop 档 0 must not idle
// mid-transition); a settled tween asks for nothing, so an idle control costs no frames.
@Test
func tweenCtxAnimateRequestsFrameWhileRunning(): Unit {
    let ctx = testContext()
    ctx.frame = FrameInfo(UInt64(0), UInt64(16))
    let tw = Tween(100, Easing.linear)

    // At its target from the start: no motion, no request.
    let _ = ctx.takeFrameRequest()
    let _ = tw.animate(ctx, target: 0.0)
    @Expect(!ctx.takeFrameRequest())

    // A new target starts a leg at the current frame time and keeps frames coming.
    let _ = ctx.takeFrameRequest()
    let v0 = tw.animate(ctx, target: 1.0)
    @Expect(v0, Float32(0.0))
    @Expect(!tw.settled())
    @Expect(ctx.takeFrameRequest())

    ctx.frame = FrameInfo(UInt64(50), UInt64(50))
    let v1 = tw.animate(ctx, target: 1.0)
    @Expect(abs(v1 - Float32(0.5)) < Float32(0.01))
    @Expect(ctx.takeFrameRequest())

    // Past the duration it lands exactly on the target and stops asking.
    ctx.frame = FrameInfo(UInt64(200), UInt64(150))
    let _ = ctx.takeFrameRequest()
    let v2 = tw.animate(ctx, target: 1.0)
    @Expect(tw.settled())
    @Expect(v2, Float32(1.0))
    @Expect(!ctx.takeFrameRequest())
}

// Offset shifts the laid-out child without changing measurement; the modifier keeps its own rect
// unshifted, but the child's frame is translated, so hit testing follows the shifted position —
// chrome slid off-screen is not clickable.
@Test
func offsetModifierShiftsLayoutButNotMeasure(): Unit {
    let ctx = testContext()
    let child = SizedLayoutProbe(Size(40.0, 20.0))
    let decorated = child.offset(x: 12.0, y: -4.0)
    let measured = decorated.measure(ctx, Size(200.0, 100.0))
    @Expect(measured.w, Float32(40.0))
    @Expect(measured.h, Float32(20.0))

    decorated.layout(ctx, Rect(10.0, 20.0, 40.0, 20.0))
    @Expect(child.rect.x, Float32(22.0))
    @Expect(child.rect.y, Float32(16.0))
    @Expect(child.rect.w, Float32(40.0))
    @Expect(child.rect.h, Float32(20.0))
}

// Records the combined draw alpha it sees while drawing.
class DrawAlphaProbe <: Widget {
    var seen: Float32 = -1.0
    public func measure(_: UiContext, available: Size): Size {
        available
    }
    public func layout(_: UiContext, _: Rect): Unit {}
    public func draw(ctx: UiContext): Unit {
        seen = ctx.drawAlpha()
    }
    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// The renderer has no global alpha, so .opacity carries a multiplicative draw alpha on the
// context (honoured by surface/background fills); nested modifiers multiply, out-of-range values
// clamp, and a fully transparent subtree is skipped entirely.
@Test
func opacityModifierStacksClampsAndSkips(): Unit {
    let ctx = testContext()

    let nested = DrawAlphaProbe()
    nested.opacity(0.5).opacity(0.5).draw(ctx)
    @Expect(abs(nested.seen - Float32(0.25)) < Float32(0.001))

    let clamped = DrawAlphaProbe()
    clamped.opacity(2.0).draw(ctx)
    @Expect(clamped.seen, Float32(1.0))

    // Fully transparent: the subtree never draws.
    let hidden = DrawAlphaProbe()
    hidden.opacity(0.0).draw(ctx)
    @Expect(hidden.seen, Float32(-1.0))

    // Outside any opacity modifier the draw alpha is back at 1.
    let plain = DrawAlphaProbe()
    plain.draw(ctx)
    @Expect(plain.seen, Float32(1.0))
}
