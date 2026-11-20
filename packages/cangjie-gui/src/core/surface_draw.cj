package cui.core

import lbase.{Color, Pen, Rect, clampF32}
import cui.base.{SurfaceStyle}

/*
 * How far a surface's soft shadow can paint beyond the surface bounds: the widest halo is
 * spread * 0.3 (ambient inset) + spread / 2 (feather fade) with spread capped at 13, plus a few
 * pixels of shadow offset — under 16 in every style the framework draws. Containers that clip
 * children defensively (per-row, per-column, viewport cross-axis) widen their clip by this
 * clearance so a child card's halo wraps its rounded corners instead of being sliced into
 * hard-edged bands at the clip boundary; pushClip intersects with the enclosing clip, so the
 * scroll axis stays exactly bounded by the ancestor that owns it.
 */
protected let CUI_SHADOW_CLEARANCE: Float32 = 16.0

/*
 * Paints a themed surface (shadow, border, rounded fill) for a widget. It lives in the
 * GUI layer rather than with the SurfaceStyle value type because it needs the render
 * context (UiContext.renderer); the plain SurfaceStyle data stays in the SDL layer.
 */
protected func drawSurface(ctx: UiContext, rect: Rect, style: SurfaceStyle): Unit {
    // The `.opacity(v)` modifier's draw alpha: fades fill, border and shadow together. (The
    // renderer has no global alpha, so this is where the fade lands.)
    let fade = ctx.drawAlpha()
    if (Int64(Float32(Int64(style.shadow.a)) * fade) > 0) {
        drawSoftShadow(ctx, rect, style, fade)
    }
    ctx.renderer.fillRoundedRect(rect, style.radius, faded(style.fill, fade))
    if (style.borderWidth > 0.0 && Int64(Float32(Int64(style.border.a)) * fade) > 0) {
        let bw = style.borderWidth
        ctx
            .renderer
            .strokeRoundedRect(rect.inset(bw / 2.0), max(0.0, style.radius - bw / 2.0),
                Pen(width: bw, color: faded(style.border, fade)))
    }
}

/** Multiplies a colour's alpha by the enclosing `.opacity` fade. */
private func faded(color: Color, fade: Float32): Color {
    if (fade >= 1.0) {
        return color
    }
    color.withAlpha(Int64(Float32(Int64(color.a)) * fade))
}

/*
 * A keyboard focus ring: an accent rounded outline hugging the control, drawn a couple of pixels
 * outside its bounds so it reads as a halo distinct from the control's own edge. Every focusable
 * control paints one (gated on `showFocusRing`, so it shows for keyboard focus only), giving Tab
 * navigation a uniform, visible indicator across buttons, toggles and fields alike.
 */
public func drawFocusRing(ctx: UiContext, rect: Rect, radius: Float32): Unit {
    ctx.renderer.strokeRoundedRect(rect.inset(-2.0), radius + 2.0, Pen(width: 1.6, color: ctx.theme.accent))
}

/*
 * A soft drop shadow drawn as two single-pass gradient halos: each layer is a rounded rect
 * whose edge fades across a wide feather, so the falloff is a smooth ramp with no banding.
 * The wide layer is the ambient penumbra, the tight one the contact darkening; the card is
 * painted on top afterwards, so only the fading halo around it stays visible.
 */
private func drawSoftShadow(ctx: UiContext, rect: Rect, style: SurfaceStyle, fade: Float32): Unit {
    let alpha = Int64(Float32(Int64(style.shadow.a)) * fade)
    let spread = clampF32(4.0 + style.radius * 0.5, 5.0, 13.0)
    let base = rect.shift(0.0, style.shadowOffsetY)
    ctx
        .renderer
        .fillRoundedRectSoft(base.inset(-spread * 0.3), style.radius + spread * 0.3, style
            .shadow
            .withAlpha(alpha * 3 / 5), feather: spread)
    ctx.renderer.fillRoundedRectSoft(base, style.radius, style.shadow.withAlpha(alpha / 2), feather: spread * 0.5)
}
