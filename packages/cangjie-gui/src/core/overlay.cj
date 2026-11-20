package cui.core

import cui.base.UiEvent
/*
 * An interactive overlay — a dropdown, menu popup, or dialog — that floats above the whole
 * tree. The shell gives the open overlays events *before* the tree, so their clicks and keys
 * are not stolen by controls underneath, and paints them *last*, on top. A control registers
 * one during its draw (via `UiContext.setOverlay`) for as long as it is open; the shell clears
 * the stack at the start of each frame, so a control that stops registering (closes) removes
 * its overlay. Contrast the tooltip, which is a simpler draw-only overlay.
 *
 * Overlays stack: registration order is z-order, events walk the stack top-down and drawing
 * bottom-up, so a popup opened inside a dialog floats above it and sees events first. `owner`
 * identifies who registered the overlay across frames (controls are rebuilt every frame);
 * a closing control removes exactly its own registration with `UiContext.removeOverlay`.
 */
public class Overlay {
    private let onEvent: (UiContext, UiEvent) -> Bool
    private let onRender: (UiContext) -> Unit
    let owner: String

    public init(handleEvent!: (UiContext, UiEvent) -> Bool, render!: (UiContext) -> Unit, owner!: String = "") {
        this.onEvent = handleEvent
        this.onRender = render
        this.owner = owner
    }

    func dispatch(ctx: UiContext, event: UiEvent): Bool {
        onEvent(ctx, event)
    }

    func render(ctx: UiContext): Unit {
        onRender(ctx)
    }
}
