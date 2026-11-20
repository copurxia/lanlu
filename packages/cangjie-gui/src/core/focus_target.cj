package cui.core

import lbase.{Rect, Size}
import cui.base.{Key, MouseButton, UiEvent}
import std.collection.ArrayList

public func registerFocusStop(id: String): Unit {
    registerFocusable(id)
}

public func reregisterFocusStop(previousId: String, id: String): Unit {
    reregisterFocusable(previousId, id)
}

public class FocusTarget <: Widget {
    private let id: String
    private let child: Widget
    private let onClick: () -> Unit
    private var frame = Rect.zero()

    public init(onClick!: () -> Unit, key!: ?String = None, body!: () -> Unit) {
        this.id = resolveControlKey(key, "FocusTarget")
        this.onClick = onClick
        this.child = buildChild(body)
        registerFocusable(this.id)
        emit(this)
    }

    public func key(value: String): FocusTarget {
        requireControlId(value, "FocusTarget")
        reregisterFocusable(id, value)
        this
    }

    public func measure(ctx: UiContext, available: Size): Size {
        child.measure(ctx, available)
    }

    public func layout(ctx: UiContext, rect: Rect): Unit {
        frame = rect
        child.layout(ctx, rect)
    }

    public func draw(ctx: UiContext): Unit {
        child.draw(ctx)
        if (ctx.showFocusRing(id)) {
            drawFocusRing(ctx, frame, ctx.theme.controlRadius)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        claimHoverIfInside(ctx, event, frame, id, CursorShape.Interactive)
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    ctx.focus(id)
                    ctx.press(id)
                    return true
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (ctx.isPressed(id)) {
                    if (frame.contains(x, y)) {
                        onClick()
                    }
                    return true
                }
            case UiEvent.KeyDown(Key.Enter, _) => return activateIfFocused(ctx)
            case UiEvent.KeyDown(Key.Space, _) => return activateIfFocused(ctx)
            case _ => ()
        }
        child.handle(ctx, event)
    }

    private func activateIfFocused(ctx: UiContext): Bool {
        if (ctx.hasFocus(id)) {
            onClick()
            true
        } else {
            false
        }
    }

    public func focusableId(): ?String {
        Some(id)
    }

    public func focusableIds(): Array<String> {
        let ids = ArrayList<String>()
        ids.add(id)
        for (stop in child.focusableIds()) {
            ids.add(stop)
        }
        ids.toArray()
    }

    public func isFlexible(): Bool {
        child.isFlexible()
    }

    public func flexWeight(): Float32 {
        child.flexWeight()
    }

    public func acceptsStretch(axis: Axis): Bool {
        child.acceptsStretch(axis)
    }

    public func participatesInLayout(): Bool {
        child.participatesInLayout()
    }
}
