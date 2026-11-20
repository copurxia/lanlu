package cui.desktop

import std.env.{getVariable, setVariable}
import cui.base.{SdlWindow, WindowSpec}

// Headless CI has no display; fall back to SDL's offscreen video driver (the same one the
// snapshot harness uses — "dummy" cannot create a renderer) so window creation works.
// A real session keeps its own driver.
private func ensureVideoDriver(): Unit {
    if (getVariable("LGUI_VIDEODRIVER").isNone() && getVariable("WAYLAND_DISPLAY").isNone() &&
        getVariable("DISPLAY").isNone()) {
        setVariable("LGUI_VIDEODRIVER", "offscreen")
    }
}

// Window creation leaves shown/resized/focus events in the SDL queue; tests that assert on
// the NEXT event must drain them first.
private func drainQueuedEvents(window: SdlWindow): Unit {
    while (window.pollEvent().isSome()) {
        ()
    }
}

/*
 * Deadline-driven idle wait (档 0 的事件化): the run loop blocks in SDL_WaitEventTimeout
 * when nothing animates and no timed-frame deadline has expired. These tests cover the pure
 * timeout arithmetic and — with a real window and a second thread — the wake path that
 * DesktopApp.requestWake relies on: a pushed user event must end the wait promptly, not at
 * the full timeout, or worker results (image arrivals) would stall until the next input.
 */

@Test
func idleWaitTimeoutTracksDeadline(): Unit {
    // No deadline: 1s safety cap（空闲等待的漏唤醒兜底，见 fd257e2），
    // 输入与 requestWake 仍是主要唤醒源。
    @Expect(idleWaitTimeoutMs(None, UInt64(1000)), Int32(1000))
    // A future deadline caps the wait at its exact distance.
    @Expect(idleWaitTimeoutMs(Some(UInt64(1600)), UInt64(1000)), Int32(600))
    @Expect(idleWaitTimeoutMs(Some(UInt64(1000)), UInt64(999)), Int32(1))
    // A reached/passed deadline must not wait at all.
    @Expect(idleWaitTimeoutMs(Some(UInt64(1000)), UInt64(1000)), Int32(0))
    @Expect(idleWaitTimeoutMs(Some(UInt64(900)), UInt64(1000)), Int32(0))
    // Far-future deadlines clamp to Int32.Max instead of overflowing the SDL signature.
    @Expect(idleWaitTimeoutMs(Some(UInt64.Max), UInt64(0)), Int32.Max)
}

@Test
func deadlineDueOnlyAtOrAfterExpiry(): Unit {
    @Expect(!isDeadlineDue(None, UInt64(100)))
    @Expect(!isDeadlineDue(Some(UInt64(530)), UInt64(529)))
    @Expect(isDeadlineDue(Some(UInt64(530)), UInt64(530)))
    @Expect(isDeadlineDue(Some(UInt64(530)), UInt64(531)))
}

@Test
func earliestDeadlineKeepsSoonest(): Unit {
    @Expect(earliestDeadline(None, None).isNone())
    @Expect(earliestDeadline(Some(UInt64(10)), None).getOrThrow(), UInt64(10))
    @Expect(earliestDeadline(None, Some(UInt64(20))).getOrThrow(), UInt64(20))
    @Expect(earliestDeadline(Some(UInt64(10)), Some(UInt64(20))).getOrThrow(), UInt64(10))
    @Expect(earliestDeadline(Some(UInt64(20)), Some(UInt64(10))).getOrThrow(), UInt64(10))
}

@Test
func waitEventTimeoutExpiresWithNoEvent(): Unit {
    ensureVideoDriver()
    let window = SdlWindow(WindowSpec("wait test", 100, 100))
    try {
        drainQueuedEvents(window) // window creation queues shown/resized events
        let start = window.ticks()
        let event = window.waitEventTimeout(Int32(150))
        let elapsed = window.ticks() - start
        @Expect(event.isNone())
        // Actually blocked for the timeout instead of returning instantly (busy poll).
        @Expect(elapsed >= UInt64(100))
    } finally {
        window.close()
    }
}

@Test
func pushWakeEventWakesWaitingLoopFromAnotherThread(): Unit {
    ensureVideoDriver()
    let window = SdlWindow(WindowSpec("wake test", 100, 100))
    try {
        drainQueuedEvents(window) // afterwards the pushed wake event is the only event source
        // Simulate a worker thread completing while the UI thread is parked in the wait.
        let worker = spawn {
            sleep(200 * Duration.millisecond)
            window.pushWakeEvent()
        }
        let start = window.ticks()
        let event = window.waitEventTimeout(Int32(10000))
        let elapsed = window.ticks() - start
        worker.get()
        @Expect(event.isSome()) // the queued user event (decodes as Unknown)
        // Woke at the push (~200ms), not at the 10s timeout — generous bound for loaded CI.
        @Expect(elapsed < UInt64(5000))
    } finally {
        window.close()
    }
}
