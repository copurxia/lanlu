package cui.controls

import lbase.{Color, Rect, Size}
import cui.base.{Key, SurfaceStyle, UiEvent}
import cui.core.{Bindable, Overlay, Spring, UiContext, Widget, buildChild, controlIdentity, drawSurface, emit,
    localState}

private let DRAWER_SCRIM_ALPHA: Float32 = 130.0

/** The window edge a `Drawer` anchors to. */
public enum DrawerEdge {
    | Left
    | Right
}

/*
 * A non-modal, edge-anchored panel — a navigation drawer or a side settings sheet. While
 * presented it floats a full-height panel against the left or right window edge via the
 * interactive overlay; like `Modal` it hosts a real widget subtree (the `body` widgets are
 * laid out inside the panel and receive events routed through the overlay, so a drawer can
 * hold buttons, sliders, or text fields with normal state — including controls that open
 * popups of their own, which register above it on the overlay stack).
 *
 * Being non-modal, it claims only what it owns: a press inside the panel goes to the content,
 * a press on the dimming scrim and Escape dismiss, and pointer traffic over the panel is
 * routed to the content; every event the content does not handle (reader paging keys, wheel
 * or moves outside the panel) falls through to the tree underneath, and there is no focus
 * trap. The slide is driven by a spring ticked on the frame clock: opening eases the panel in
 * from off-edge, closing eases it back out, and the body stays built — and the overlay
 * registered — until the closing slide has fully left the screen, so the exit plays out
 * instead of the panel vanishing mid-slide. The scrim fades with the same spring value.
 *
 * It takes no space in the tree — place it anywhere (a `ZStack` at the root is typical) and it
 * anchors itself against the viewport. The panel is laid out flush to the edge with no
 * padding; pad the body content as needed.
 */
public class Drawer <: Widget {
    private let presented: Bindable<Bool>
    private let edge: DrawerEdge
    private let panelWidth: Float32
    private let content: ?Widget
    private let onDismiss: ?() -> Unit
    // Identifies this drawer's overlay registration across per-frame rebuilds, so dismissing
    // removes exactly this drawer from the overlay stack (never a popup opened above it).
    private let overlayOwner: String
    private let slideSpring: Spring
    private var panelRect = Rect.zero()
    private var panelT: Float32 = 0.0

    public init(presented: Bindable<Bool>, edge!: DrawerEdge = DrawerEdge.Left, width!: Float32 = 320.0,
        onDismiss!: ?() -> Unit = None, body!: () -> Unit) {
        this.presented = presented
        this.edge = edge
        this.panelWidth = width
        this.onDismiss = onDismiss
        this.overlayOwner = controlIdentity("Drawer")
        // Retained so the slide survives per-frame rebuilds; started at the current state so a
        // statically first-rendered open drawer is already settled (snapshot-stable).
        let start: Float32 = if (presented.value) {
            1.0
        } else {
            0.0
        }
        this.slideSpring = localState<Spring>("${this.overlayOwner}:slide") {
            Spring(start, stiffness: 260.0, damping: 26.0)
        }.value
        // The body is built while presented and kept through the closing slide; a hidden,
        // settled drawer builds nothing and registers no focusables.
        if (presented.value || slideSpring.value > 0.0 || !slideSpring.settled()) {
            this.content = Some(buildChild(body))
        } else {
            this.content = None
        }
        emit(this)
    }

    /** Whether the drawer is presented (the closing slide may still be on screen). */
    public prop isOpen: Bool {
        get() {
            presented.value
        }
    }

    /** Presents the drawer, sliding the panel in. */
    public func open(): Unit {
        presented.value = true
    }

    /** Dismisses the drawer, sliding the panel out. */
    public func close(): Unit {
        presented.value = false
    }

    /** Flips the presented state. */
    public func toggle(): Unit {
        presented.value = !presented.value
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(ctx: UiContext, _: Rect): Unit {
        match (content) {
            case Some(body) =>
                // The spring is advanced here rather than in draw so the content layout and the
                // overlay paint of this same frame agree on the panel position.
                let goal: Float32 = if (presented.value) {
                    1.0
                } else {
                    0.0
                }
                let t = slideSpring.animate(ctx, target: goal)
                panelT = t
                let w = max(0.0, min(panelWidth, ctx.viewportWidth))
                let x = match (edge) {
                    case DrawerEdge.Left => -w * (1.0 - t)
                    case DrawerEdge.Right => ctx.viewportWidth - w * t
                }
                panelRect = Rect(x, 0.0, w, ctx.viewportHeight)
                body.layout(ctx, panelRect)
            case None => ()
        }
    }

    public func draw(ctx: UiContext): Unit {
        // Stay registered until the closing slide has fully left the screen; registration
        // then lapses on its own (the shell clears the stack at the start of each frame).
        if (presented.value || panelT > 0.0) {
            match (content) {
                case Some(_) =>
                    ctx.setOverlay(Overlay(handleEvent: {c, e => handleDrawer(c, e)}, render: {c => drawDrawer(c)},
                        owner: overlayOwner))
                case None => ()
            }
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        // Input reaches the drawer subtree through the overlay (`handleDrawer`); only the
        // per-frame tick is dispatched to the tree directly, so it is forwarded by hand —
        // otherwise timed behaviours inside the drawer (a field's autofocus, an application
        // Frame hook) would never run.
        match (event) {
            case UiEvent.Frame(_) => routeToContent(ctx, event)
            case _ => ()
        }
        false
    }

    private func handleDrawer(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.KeyDown(Key.Escape, _) =>
                if (presented.value) {
                    dismiss(ctx)
                    true
                } else {
                    false
                }
            case UiEvent.MouseDown(_, x, y) =>
                if (panelRect.contains(x, y)) {
                    routeToContent(ctx, event)
                } else {
                    dismiss(ctx) // a press on the scrim dismisses
                }
                true
            case UiEvent.MouseUp(_, x, y) =>
                if (panelRect.contains(x, y)) {
                    routeToContent(ctx, event)
                    true
                } else {
                    false
                }
            case UiEvent.MouseMove(x, y) =>
                if (panelRect.contains(x, y)) {
                    routeToContent(ctx, event)
                    true
                } else {
                    false
                }
            case UiEvent.MouseWheel(_, _, x, y) =>
                if (panelRect.contains(x, y)) {
                    routeToContent(ctx, event)
                    true
                } else {
                    false
                }
            // Keys, text input, drops: offered to the content first (a focused field inside
            // the drawer keeps working); whatever it ignores falls through to the tree.
            case _ => routeToContent(ctx, event)
        }
    }

    private func routeToContent(ctx: UiContext, event: UiEvent): Bool {
        match (content) {
            case Some(body) => body.handle(ctx, event)
            case None => false
        }
    }

    private func drawDrawer(ctx: UiContext): Unit {
        // The panel itself may overshoot slightly past the edge on the spring; the scrim fade
        // is clamped so overshoot never brightens it past the target alpha.
        let t = max(0.0, min(1.0, panelT))
        if (t <= 0.0) {
            return
        }
        ctx.renderer.fill(Rect(0.0, 0.0, ctx.viewportWidth, ctx.viewportHeight),
            Color.rgba(12, 14, 20, Int64(DRAWER_SCRIM_ALPHA * t)))
        drawSurface(ctx, panelRect, drawerSurface(ctx))
        match (content) {
            case Some(body) => body.draw(ctx)
            case None => ()
        }
    }

    private func dismiss(_: UiContext): Unit {
        if (!presented.value) {
            return
        }
        presented.value = false
        match (onDismiss) {
            case Some(callback) => callback()
            case None => ()
        }
    }

    private func drawerSurface(ctx: UiContext): SurfaceStyle {
        SurfaceStyle(ctx.theme.panelRaised, border: ctx.theme.panelEdge, radius: 0.0, borderWidth: 1.0,
            shadow: ctx.theme.shadow)
    }
}
