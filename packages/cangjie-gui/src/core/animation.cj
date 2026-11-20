package cui.core

import lbase.clampF32
// Clamp the timestep so a frame hitch (a long pause between frames) cannot inject a huge
// impulse and make the integration diverge; motion just proceeds at up to this step.
private let SPRING_MAX_STEP_MS: Float32 = 40.0
private let SPRING_SETTLE_POS: Float32 = 0.0005
private let SPRING_SETTLE_VEL: Float32 = 0.001

/*
 * A spring-damper that eases a value toward a target across frames. CUI redraws every frame,
 * so a widget ticks one in `draw` with the frame delta and reads `value` — smooth state
 * transitions with no separate animation timer. Integration is semi-implicit Euler with a
 * clamped timestep for stability, and it settles exactly onto the target so an idle spring
 * costs nothing.
 *
 * Defaults are tuned for UI toggles: snappy, with a barely-perceptible settle. Because a
 * spring initialised at its target is immediately settled, a control that starts a spring at
 * its current state animates only on later changes — static renders (snapshots) are unchanged.
 */
public class Spring {
    private var current: Float32
    private var velocity: Float32 = 0.0
    private var goal: Float32
    private let stiffness: Float32
    private let damping: Float32

    public init(value: Float32, stiffness!: Float32 = 210.0, damping!: Float32 = 24.0) {
        this.current = value
        this.goal = value
        this.stiffness = stiffness
        this.damping = damping
    }

    /** The current animated value. */
    public prop value: Float32 {
        get() {
            current
        }
    }

    /** Sets the value the spring eases toward. */
    public func target(value: Float32): Unit {
        goal = value
    }

    /** Snaps immediately to `value` with no animation (initial placement, or a hard reset). */
    public func reset(value: Float32): Unit {
        current = value
        goal = value
        velocity = 0.0
    }

    /** Whether the spring has reached its target and stopped. */
    public func settled(): Bool {
        current == goal && velocity == 0.0
    }

    /*
     * The widget draw-time step: retarget, advance by this frame's delta, and — while still in
     * motion — request the next frame so the dirty-frame loop (档 0) keeps rendering instead of idling
     * mid-transition and freezing the animation. This is the form controls use; a settled spring asks
     * for nothing, so an idle control still costs no frames. Returns the new value.
     */
    public func animate(ctx: UiContext, target!: Float32): Float32 {
        goal = target
        tick(ctx.frame.deltaMs)
        if (!settled()) {
            ctx.requestFrame()
        }
        current
    }

    /*
     * The raw step: retarget, advance by an explicit delta, and read the new value, with no frame
     * request. For tests and non-draw callers that drive time themselves; widgets rendering under the
     * dirty-frame loop want `animate(ctx, target:)` so the transition is not frozen.
     */
    public func animate(target!: Float32, deltaMs!: UInt64): Float32 {
        goal = target
        tick(deltaMs)
        current
    }

    /** Advances the spring by `deltaMs` milliseconds toward the target. */
    public func tick(deltaMs: UInt64): Unit {
        if (settled()) {
            return
        }
        let dt = min(Float32(Int64(deltaMs)), SPRING_MAX_STEP_MS) / 1000.0
        if (dt <= 0.0) {
            return
        }
        let force = -stiffness * (current - goal) - damping * velocity
        velocity += force * dt
        current += velocity * dt
        if (springMagnitude(current - goal) < SPRING_SETTLE_POS && springMagnitude(velocity) < SPRING_SETTLE_VEL) {
            current = goal
            velocity = 0.0
        }
    }
}

private func springMagnitude(value: Float32): Float32 {
    if (value < 0.0) {
        -value
    } else {
        value
    }
}
/*
 * Easing curves for `Tween`: each maps linear progress t in [0, 1] to eased progress, with the
 * endpoints pinned exactly so a completed transition lands precisely on its target. Out-of-range
 * input is clamped, so a tick past the duration never overshoots.
 */
public class Easing {
    private init() {}

    /** Constant speed from start to target. */
    public static func linear(t: Float32): Float32 {
        clampF32(t, 0.0, 1.0)
    }

    /** Fast start, gentle arrival: 1 - (1 - t)^3. The reader's default transition feel. */
    public static func easeOutCubic(t: Float32): Float32 {
        let u = 1.0 - clampF32(t, 0.0, 1.0)
        1.0 - u * u * u
    }

    /** Slow start and end, fast middle — symmetric through t = 0.5. */
    public static func easeInOutCubic(t: Float32): Float32 {
        let k = clampF32(t, 0.0, 1.0)
        if (k < 0.5) {
            4.0 * k * k * k
        } else {
            let u = -2.0 * k + 2.0
            1.0 - u * u * u / 2.0
        }
    }
}

/*
 * A fixed-duration eased interpolation, for transitions that must complete in a known time
 * (reader lane expansion, page turns) rather than spring to a natural rest. Like `Spring`, a
 * widget ticks one in `draw` via `animate(ctx, target:)`, which advances on the frame clock and
 * requests the next frame while a leg is in flight, so the dirty-frame loop (档 0) does not idle
 * mid-transition; a settled tween asks for nothing.
 *
 * A tween starts settled at 0.0 targeting 0.0. Retargeting — a tick or animate whose target
 * differs from the current goal — begins a fresh leg from the current value, easing it to the
 * new target over the full duration; there is no overshoot. `start(atMs:)` arms the zero time
 * consumed by the next retarget, so a caller driving time manually can say exactly when the leg
 * began; `reset(value)` snaps without animating.
 */
public class Tween {
    private let durationMs: Int64
    private let easing: (Float32) -> Float32
    private var current: Float32 = 0.0
    private var startValue: Float32 = 0.0
    private var goal: Float32 = 0.0
    private var legStartMs: UInt64 = 0
    private var armedMs: UInt64 = 0
    private var armed = false

    public init(durationMs: Int64, easing: (Float32) -> Float32) {
        this.durationMs = max(Int64(0), durationMs)
        this.easing = easing
    }

    /** The current animated value. */
    public prop value: Float32 {
        get() {
            current
        }
    }

    /** Whether the tween has reached its target; a settled tween requests no frames. */
    public func settled(): Bool {
        current == goal
    }

    /** Arms the zero time the next retarget starts its leg from. For manual-clock drivers. */
    public func start(atMs!: UInt64): Unit {
        armedMs = atMs
        armed = true
    }

    /** Snaps immediately to `value` with no animation (initial placement, or a hard reset). */
    public func reset(value: Float32): Unit {
        current = value
        startValue = value
        goal = value
        armed = false
    }

    /*
     * The widget draw-time step: retarget, advance to the frame time, and — while a leg is still
     * in flight — request the next frame so the transition is not frozen (same dirty-frame
     * convention as Spring.animate). Returns the new value.
     */
    public func animate(ctx: UiContext, target!: Float32): Float32 {
        let value = tick(atMs: ctx.frame.elapsedMs, target: target)
        if (!settled()) {
            ctx.requestFrame()
        }
        value
    }

    /*
     * The raw step: retarget, advance to an explicit time, and read the new value, with no frame
     * request. For tests and non-draw callers that drive time themselves; widgets rendering under
     * the dirty-frame loop want `animate(ctx, target:)`.
     */
    public func tick(atMs!: UInt64, target!: Float32): Float32 {
        if (target != goal) {
            startValue = current
            legStartMs = if (armed) {
                armedMs
            } else {
                atMs
            }
            armed = false
            goal = target
        }
        advance(atMs)
        current
    }

    /** Evaluates the eased position at `atMs`, snapping exactly onto the target at the end. */
    private func advance(atMs: UInt64): Unit {
        if (current == goal) {
            return
        }
        if (durationMs <= 0) {
            current = goal
            return
        }
        let elapsed = if (atMs > legStartMs) {
            atMs - legStartMs
        } else {
            UInt64(0)
        }
        let progress = clampF32(Float32(Int64(elapsed)) / Float32(durationMs), 0.0, 1.0)
        current = startValue + (goal - startValue) * easing(progress)
        if (progress >= 1.0) {
            current = goal
        }
    }
}
