package cui.core

import cui.base.FrameInfo
/*
 * Timed frame requests (requestFrameAfter): the signal the deadline-driven idle path waits on.
 * Widgets with a known next-visible-moment (caret blink toggle, tooltip reveal) register that
 * deadline instead of requesting every frame, and the loop blocks on the event queue until it.
 */

@Test
func timedFrameRequestKeepsEarliestDeadlineAndClears(): Unit {
    let ctx = testContext()
    ctx.frame = FrameInfo(UInt64(1000), UInt64(0))

    @Expect(ctx.takeTimedFrameRequest().isNone()) // nothing registered yet

    ctx.requestFrameAfter(UInt64(500))
    ctx.requestFrameAfter(UInt64(200)) // earlier wins
    ctx.requestFrameAfter(UInt64(900))
    @Expect(ctx.takeTimedFrameRequest().getOrThrow(), UInt64(1200)) // 1000 + 200
    // The take cleared the registration; a frame that re-registers starts fresh.
    @Expect(ctx.takeTimedFrameRequest().isNone())
}

@Test
func timedFrameRequestIsSeparateFromContinuousRequest(): Unit {
    let ctx = testContext()
    ctx.frame = FrameInfo(UInt64(0), UInt64(0))

    // A timed request alone must not keep frames flowing continuously, and vice versa.
    ctx.requestFrameAfter(UInt64(100))
    @Expect(!ctx.takeFrameRequest())
    @Expect(ctx.takeTimedFrameRequest().isSome()) // drain the timed registration

    ctx.requestFrame()
    @Expect(ctx.takeTimedFrameRequest().isNone())
    @Expect(ctx.takeFrameRequest()) // drain the continuous registration
}
