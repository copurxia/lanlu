package cui.core

import lbase.{Color, Rect, Size, clampF32}
import cui.base.{SurfaceStyle, UiEvent}

/**
 * Internal modifier vocabulary. Each chained call wraps the previous node, so modifier
 * order stays observable and predictable, matching the layout tree shown in source.
 * Sizes are stored as unit-carrying `Length` values and resolved against the active
 * `UiContext` scales during measure/layout, never at construction time.
 */
protected enum WidgetModifier {
    | Width(Length)
    | Height(Length)
    | MinWidth(Length)
    | MaxWidth(Length)
    | MinHeight(Length)
    | MaxHeight(Length)
    | FillWidth
    | FillHeight
    | Padding(LengthInsets)
    | Surface(SurfaceStyle)
    | Background(Color, Length)
    | Flex(Float32)
    | Visible(Bool)
    | Enabled(Bool)
    | Offset(Float32, Float32)
    | Opacity(Float32)
}

class ModifiedWidget <: Widget {
    private let child: Widget
    private let modifier: WidgetModifier
    private var frame = Rect.zero()

    init(child: Widget, modifier: WidgetModifier) {
        this.child = child
        this.modifier = modifier
    }

    public func measure(ctx: UiContext, available: Size): Size {
        match (modifier) {
            case WidgetModifier.Width(length) =>
                let value = exact(ctx, length)
                let childSize = child.measure(ctx, Size(min(value, available.w), available.h))
                Size(min(value, available.w), childSize.h)
            case WidgetModifier.Height(length) =>
                let value = exact(ctx, length)
                let childSize = child.measure(ctx, Size(available.w, min(value, available.h)))
                Size(childSize.w, min(value, available.h))
            case WidgetModifier.MinWidth(length) =>
                let childSize = child.measure(ctx, available)
                Size(min(available.w, max(exact(ctx, length), childSize.w)), childSize.h)
            case WidgetModifier.MaxWidth(length) =>
                let limit = min(exact(ctx, length), available.w)
                let childSize = child.measure(ctx, Size(limit, available.h))
                Size(min(limit, childSize.w), childSize.h)
            case WidgetModifier.MinHeight(length) =>
                let childSize = child.measure(ctx, available)
                Size(childSize.w, min(available.h, max(exact(ctx, length), childSize.h)))
            case WidgetModifier.MaxHeight(length) =>
                let limit = min(exact(ctx, length), available.h)
                let childSize = child.measure(ctx, Size(available.w, limit))
                Size(childSize.w, min(limit, childSize.h))
            case WidgetModifier.FillWidth =>
                let childSize = child.measure(ctx, available)
                Size(available.w, childSize.h)
            case WidgetModifier.FillHeight =>
                let childSize = child.measure(ctx, available)
                Size(childSize.w, available.h)
            case WidgetModifier.Padding(edges) => measurePadding(ctx, available, edges)
            case WidgetModifier.Visible(isVisible) =>
                if (isVisible) {
                    child.measure(ctx, available)
                } else {
                    Size.zero()
                }
            case _ => child.measure(ctx, available)
        }
    }

    public func layout(ctx: UiContext, rect: Rect): Unit {
        frame = rect
        match (modifier) {
            case WidgetModifier.Width(length) =>
                child.layout(ctx, Rect(rect.x, rect.y, min(exact(ctx, length), rect.w), rect.h))
            case WidgetModifier.Height(length) =>
                child.layout(ctx, Rect(rect.x, rect.y, rect.w, min(exact(ctx, length), rect.h)))
            case WidgetModifier.MaxWidth(length) =>
                child.layout(ctx, Rect(rect.x, rect.y, min(exact(ctx, length), rect.w), rect.h))
            case WidgetModifier.MaxHeight(length) =>
                child.layout(ctx, Rect(rect.x, rect.y, rect.w, min(exact(ctx, length), rect.h)))
            case WidgetModifier.Padding(edges) => child.layout(ctx, rect.inset(ctx.resolve(edges)))
            case WidgetModifier.Visible(isVisible) =>
                if (isVisible) {
                    child.layout(ctx, rect)
                }
            case WidgetModifier.Offset(dx, dy) =>
                // Shifts where the child is laid out (and drawn); the modifier's own rect stays
                // unshifted, but the child's frame is translated, so hit testing follows the
                // shifted position — chrome slid off-screen is not clickable.
                child.layout(ctx, rect.shift(dx, dy))
            case _ => child.layout(ctx, rect)
        }
    }

    public func draw(ctx: UiContext): Unit {
        match (modifier) {
            case WidgetModifier.Surface(style) =>
                drawSurface(ctx, frame, style)
                child.draw(ctx)
            case WidgetModifier.Background(color, radius) =>
                drawSurface(ctx, frame, SurfaceStyle(color, radius: max(0.0, ctx.resolve(radius))))
                child.draw(ctx)
            case WidgetModifier.Visible(isVisible) =>
                if (isVisible) {
                    child.draw(ctx)
                }
            case WidgetModifier.Enabled(isEnabled) =>
                child.draw(ctx)
                if (!isEnabled) {
                    ctx.renderer.fill(frame, ctx.theme.bg.withAlpha(96))
                }
            case WidgetModifier.Opacity(value) =>
                let alpha = clampF32(value, 0.0, 1.0)
                // Fully transparent: skip drawing the subtree entirely (layout and hit testing
                // are unaffected). Otherwise push a multiplicative draw alpha — the renderer has
                // no global alpha, so only drawing code that reads ctx.drawAlpha() fades: the
                // surface/background fills in drawSurface (fill, border, shadow). Text and
                // shapes controls draw straight through the renderer are not faded.
                if (alpha <= 0.0) {
                    return
                }
                ctx.pushDrawAlpha(alpha)
                child.draw(ctx)
                ctx.popDrawAlpha()
            case _ => child.draw(ctx)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (modifier) {
            case WidgetModifier.Visible(isVisible) => isVisible && child.handle(ctx, event)
            case WidgetModifier.Enabled(isEnabled) =>
                // Disabled suppresses input, not time: the per-frame tick still flows, so a
                // wrapped Frame hook (e.g. dialog polling) keeps running while greyed out.
                match (event) {
                    case UiEvent.Frame(_) => child.handle(ctx, event)
                    case _ => isEnabled && child.handle(ctx, event)
                }
            case _ => child.handle(ctx, event)
        }
    }

    public func isFlexible(): Bool {
        match (modifier) {
            case WidgetModifier.Flex(_) => true
            case WidgetModifier.Visible(isVisible) => isVisible && child.isFlexible()
            case _ => child.isFlexible()
        }
    }

    public func flexWeight(): Float32 {
        match (modifier) {
            case WidgetModifier.Flex(weight) => weight
            case _ => child.flexWeight()
        }
    }

    public func acceptsStretch(axis: Axis): Bool {
        match (modifier) {
            case WidgetModifier.Width(_) => match (axis) {
                case Axis.Horizontal => false
                case Axis.Vertical => true
            }
            case WidgetModifier.MaxWidth(_) => match (axis) {
                case Axis.Horizontal => false
                case Axis.Vertical => true
            }
            case WidgetModifier.Height(_) => match (axis) {
                case Axis.Horizontal => true
                case Axis.Vertical => false
            }
            case WidgetModifier.MaxHeight(_) => match (axis) {
                case Axis.Horizontal => true
                case Axis.Vertical => false
            }
            case WidgetModifier.FillWidth => match (axis) {
                case Axis.Horizontal => true
                case Axis.Vertical => child.acceptsStretch(axis)
            }
            case WidgetModifier.FillHeight => match (axis) {
                case Axis.Horizontal => child.acceptsStretch(axis)
                case Axis.Vertical => true
            }
            case _ => child.acceptsStretch(axis)
        }
    }

    public func participatesInLayout(): Bool {
        match (modifier) {
            case WidgetModifier.Visible(isVisible) => isVisible && child.participatesInLayout()
            case _ => child.participatesInLayout()
        }
    }

    public func focusableId(): ?String {
        child.focusableId()
    }

    public func focusableIds(): Array<String> {
        child.focusableIds()
    }

    /** Resolves an exact-size length, clamped to non-negative logical pixels. */
    private func exact(ctx: UiContext, length: Length): Float32 {
        max(0.0, ctx.resolve(length))
    }

    private func measurePadding(ctx: UiContext, available: Size, edges: LengthInsets): Size {
        let resolved = ctx.resolve(edges)
        let inner = Size(
            max(0.0, available.w - resolved.horizontal()),
            max(0.0, available.h - resolved.vertical())
        )
        let childSize = child.measure(ctx, inner)
        Size(
            min(available.w, childSize.w + resolved.horizontal()),
            min(available.h, childSize.h + resolved.vertical())
        )
    }
}

protected func applyModifier(widget: Widget, modifier: WidgetModifier): Widget {
    let modified = ModifiedWidget(widget, modifier)
    replaceLastEmission(widget, modified)
    modified
}
