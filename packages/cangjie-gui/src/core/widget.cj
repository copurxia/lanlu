package cui.core

import lbase.{Color, Rect, Size}
import cui.base.{SurfaceStyle, UiEvent}

protected let CUI_CONTROL_H: Float32 = 38.0
protected let CUI_SMALL_H: Float32 = 28.0
protected let CUI_GAP: Float32 = 8.0

public interface Widget {
    func measure(ctx: UiContext, available: Size): Size
    func layout(ctx: UiContext, rect: Rect): Unit
    func draw(ctx: UiContext): Unit
    func handle(ctx: UiContext, event: UiEvent): Bool

    /**
     * A flexible widget receives a share of its stack's leftover space instead of the
     * size it measured; non-flexible widgets hug their content. `flexWeight` sets the
     * relative share — wrap any widget in `Flexible(weight: ...)` to opt it in.
     */
    func isFlexible(): Bool {
        false
    }

    func flexWeight(): Float32 {
        1.0
    }

    /** Whether a stack may stretch this widget on `axis` beyond its measured size. */
    func acceptsStretch(_: Axis): Bool {
        true
    }

    /** Whether this node occupies a position in its parent layout. */
    func participatesInLayout(): Bool {
        true
    }

    /*
     * The keyboard-focus id this widget registered during construction, or `None` for
     * non-focusable widgets and multi-control containers. Single-child wrappers forward
     * their child's id; `.enabled(false)` uses it to take the control out of Tab traversal.
     */
    func focusableId(): ?String {
        None
    }

    /*
     * Every keyboard-focus id this widget's subtree registered during construction, in
     * declaration order. The default covers leaf controls (their single `focusableId`);
     * containers concatenate their children's and wrappers forward. `.enabled(false)`
     * uses it to take a whole disabled subtree out of Tab traversal.
     */
    func focusableIds(): Array<String> {
        match (focusableId()) {
            case Some(id) => [id]
            case None => []
        }
    }

    /** Constrains this widget to an exact width, e.g. `.width(160.vp)`. */
    func width(value: Length): Widget {
        applyModifier(this, WidgetModifier.Width(value))
    }

    /** Constrains this widget to an exact width in virtual pixels. */
    func width(value: Float32): Widget {
        width(vpLength(value))
    }

    /** Constrains this widget to an exact height, e.g. `.height(48.vp)`. */
    func height(value: Length): Widget {
        applyModifier(this, WidgetModifier.Height(value))
    }

    /** Constrains this widget to an exact height in virtual pixels. */
    func height(value: Float32): Widget {
        height(vpLength(value))
    }

    /** Prevents this widget from measuring narrower than `value`. */
    func minWidth(value: Length): Widget {
        applyModifier(this, WidgetModifier.MinWidth(value))
    }

    /** Prevents this widget from measuring narrower than `value` virtual pixels. */
    func minWidth(value: Float32): Widget {
        minWidth(vpLength(value))
    }

    /** Prevents this widget from measuring wider than `value`. */
    func maxWidth(value: Length): Widget {
        applyModifier(this, WidgetModifier.MaxWidth(value))
    }

    /** Prevents this widget from measuring wider than `value` virtual pixels. */
    func maxWidth(value: Float32): Widget {
        maxWidth(vpLength(value))
    }

    /** Prevents this widget from measuring shorter than `value`. */
    func minHeight(value: Length): Widget {
        applyModifier(this, WidgetModifier.MinHeight(value))
    }

    /** Prevents this widget from measuring shorter than `value` virtual pixels. */
    func minHeight(value: Float32): Widget {
        minHeight(vpLength(value))
    }

    /** Prevents this widget from measuring taller than `value`. */
    func maxHeight(value: Length): Widget {
        applyModifier(this, WidgetModifier.MaxHeight(value))
    }

    /** Prevents this widget from measuring taller than `value` virtual pixels. */
    func maxHeight(value: Float32): Widget {
        maxHeight(vpLength(value))
    }

    /** Makes this widget consume all width offered by its parent. */
    func fillWidth(): Widget {
        applyModifier(this, WidgetModifier.FillWidth)
    }

    /** Makes this widget consume all height offered by its parent. */
    func fillHeight(): Widget {
        applyModifier(this, WidgetModifier.FillHeight)
    }

    /** Adds equal space around this widget, e.g. `.padding(16.vp)`. Order is significant. */
    func padding(all: Length): Widget {
        applyModifier(this, WidgetModifier.Padding(LengthInsets(all)))
    }

    /** Adds equal space around this widget in virtual pixels. */
    func padding(all: Float32): Widget {
        padding(vpLength(all))
    }

    /** Adds horizontal and vertical space around this widget. */
    func padding(horizontal: Length, vertical: Length): Widget {
        applyModifier(this, WidgetModifier.Padding(LengthInsets(horizontal, vertical)))
    }

    /** Adds horizontal and vertical space around this widget in virtual pixels. */
    func padding(horizontal: Float32, vertical: Float32): Widget {
        padding(vpLength(horizontal), vpLength(vertical))
    }

    /** Adds independently configurable space around all four edges. */
    func padding(left: Length, top: Length, right: Length, bottom: Length): Widget {
        applyModifier(this, WidgetModifier.Padding(LengthInsets(top: top, right: right, bottom: bottom, left: left)))
    }

    /** Adds independently configurable space around all four edges in virtual pixels. */
    func padding(left: Float32, top: Float32, right: Float32, bottom: Float32): Widget {
        padding(vpLength(left), vpLength(top), vpLength(right), vpLength(bottom))
    }

    /** Paints a solid rounded background behind this widget. */
    func background(color: Color): Widget {
        applyModifier(this, WidgetModifier.Surface(SurfaceStyle(color)))
    }

    /** Paints a solid background with the requested corner radius. */
    func background(color: Color, radius: Length): Widget {
        applyModifier(this, WidgetModifier.Background(color, radius))
    }

    /** Paints a solid background with the corner radius in virtual pixels. */
    func background(color: Color, radius: Float32): Widget {
        background(color, vpLength(radius))
    }

    /** Paints a complete surface style behind this widget. */
    func surface(style: SurfaceStyle): Widget {
        applyModifier(this, WidgetModifier.Surface(style))
    }

    /** Gives this widget a relative share of an enclosing stack's remaining space. */
    func flex(): Widget {
        applyModifier(this, WidgetModifier.Flex(1.0))
    }

    /** Gives this widget `weight` shares of an enclosing stack's remaining space. */
    func flex(weight: Float32): Widget {
        applyModifier(this, WidgetModifier.Flex(max(0.0, weight)))
    }

    /** Includes or removes this widget from layout, drawing, and event dispatch. */
    func visible(isVisible: Bool): Widget {
        applyModifier(this, WidgetModifier.Visible(isVisible))
    }

    /*
     * Keeps this widget in layout and drawing while suppressing input events. A disabled
     * subtree also leaves keyboard Tab traversal — a stop that ignores Enter/Space would
     * be a dead end. Works at any granularity: on a single control or on a container
     * (an HStack form row, a whole panel), whose focus stops are removed via
     * `focusableIds()`.
     */
    func enabled(isEnabled: Bool): Widget {
        if (!isEnabled) {
            for (id in focusableIds()) {
                unregisterFocusable(id)
            }
        }
        applyModifier(this, WidgetModifier.Enabled(isEnabled))
    }

    /*
     * Shifts where this widget is laid out (and therefore drawn) by (x, y) logical pixels.
     * Measurement is unchanged; the child's frame is translated at layout time, so hit testing
     * follows the shifted position — chrome slid off-screen is not clickable.
     */
    func offset(x!: Float32, y!: Float32): Widget {
        applyModifier(this, WidgetModifier.Offset(x, y))
    }

    /*
     * Fades this widget's subtree by `value`, clamped to [0, 1]; 0 skips drawing entirely.
     * The renderer has no global alpha, so the fade is carried on the context and honoured by
     * the surface/background fills drawn inside (fill, border and shadow — wrap the modifier
     * outside the surfaces it should fade); text and shapes drawn straight through the renderer
     * are not faded.
     */
    func opacity(value: Float32): Widget {
        applyModifier(this, WidgetModifier.Opacity(value))
    }
}

public enum Axis {
    | Horizontal
    | Vertical
}

public enum ButtonRole {
    | Normal
    | Primary
    | Danger
}

public enum TextAlign {
    | Leading
    | Center
    | Trailing
}

/** Controls how a stack positions children along its main axis. */
public enum MainAxisAlignment {
    | Start
    | Center
    | End
    | SpaceBetween
    | SpaceAround
    | SpaceEvenly
}

/** Controls how a stack positions children across its main axis. */
public enum CrossAxisAlignment {
    | Start
    | Center
    | End
    | Stretch
}

/** A two-dimensional alignment used by overlay-style containers. */
public enum Alignment {
    | TopLeading
    | Top
    | TopTrailing
    | Leading
    | Center
    | Trailing
    | BottomLeading
    | Bottom
    | BottomTrailing
}
