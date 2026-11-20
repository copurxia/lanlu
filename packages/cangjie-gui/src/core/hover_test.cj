package cui.core

import lbase.{Rect}
import cui.base.{UiEvent}

/*
 * Hover is resolved once per pointer move: the shell brackets a MouseMove with
 * beginHoverTest / settleHover and each control the pointer is inside calls claimHover.
 * The first claim of a move wins (dispatch visits the top-most control first), and the
 * settled shape drives the system cursor.
 */
@Test
func hoverResolvesToFirstClaimAndReportsItsShape(): Unit {
    let ctx = testContext()

    ctx.beginHoverTest()
    ctx.claimHover("top", CursorShape.Interactive) // top-most is dispatched first
    ctx.claimHover("bottom", CursorShape.Text) // a later claim in the same move is ignored
    ctx.settleHover()

    @Expect(ctx.hoverId, "top")
    @Expect(ctx.isHovered("top"))
    @Expect(!ctx.isHovered("bottom"))
    @Expect(ctx.desiredCursor() == CursorShape.Interactive)
}

@Test
func noClaimSettlesToNoHoverAndDefaultCursor(): Unit {
    let ctx = testContext()
    ctx.claimHover("stale", CursorShape.Interactive)
    ctx.beginHoverTest()
    ctx.settleHover()

    @Expect(ctx.hoverId, "")
    @Expect(ctx.desiredCursor() == CursorShape.Default)
}

@Test
func buttonClaimsInteractiveCursorOnlyWhenPointerInside(): Unit {
    let ctx = testContext()
    let button = Button("A", {=>})
    button.layout(ctx, Rect(0.0, 0.0, 100.0, 40.0))

    ctx.beginHoverTest()
    let _ = button.handle(ctx, UiEvent.MouseMove(20.0, 20.0))
    ctx.settleHover()
    @Expect(ctx.desiredCursor() == CursorShape.Interactive)
    @Expect(ctx.hoverId != "")

    ctx.beginHoverTest()
    let _ = button.handle(ctx, UiEvent.MouseMove(200.0, 200.0))
    ctx.settleHover()
    @Expect(ctx.desiredCursor() == CursorShape.Default)
    @Expect(ctx.hoverId, "")
}

@Test
func hoverClaimDoesNotConsumeTheMoveEvent(): Unit {
    let ctx = testContext()
    let button = Button("A", {=>})
    button.layout(ctx, Rect(0.0, 0.0, 100.0, 40.0))

    // Claiming hover must leave the event unconsumed so sibling layers still see the move.
    @Expect(!button.handle(ctx, UiEvent.MouseMove(20.0, 20.0)))
}

@Test
func cursorShapeEqualityDistinguishesShapes(): Unit {
    @Expect(CursorShape.Interactive == CursorShape.Interactive)
    @Expect(CursorShape.Interactive != CursorShape.Text)
    @Expect(CursorShape.Default != CursorShape.Interactive)
}
