package cui.controls

import lbase.{Color, Pen, Rect, Size, clampF32}
import cui.base.{FontSizes, Key, MouseButton, SurfaceStyle, UiEvent}
import cui.core.{Bindable, CUI_CONTROL_H, CUI_SMALL_H, CursorShape, Easing, Overlay, ScrollBar, SmoothScroll, State, 
    Tween, UiContext, Widget, resolveControlKey, claimHoverIfInside, clampScrollOffset, drawSurface, 
    drawVerticalScrollBar, emit, localState, registerFocusable, scrollBarGutter}

private let DROPDOWN_DEFAULT_W: Float32 = 190.0
private let DROPDOWN_POPUP_PAD: Float32 = 5.0
private let DROPDOWN_MARGIN: Float32 = 4.0
private let DROPDOWN_ANIMATION_MS: Int64 = 180
private let DROPDOWN_BACKGROUND = Color.rgb(255, 255, 255)

/*
 * A dropdown select: a closed box showing the current item, and, when opened, a popup list
 * floated above the tree via the interactive overlay. The popup grows out of the closed field
 * with the selected row pinned to the field's text baseline, then follows the same geometry back
 * when dismissed. Clicking an item selects and closes;
 * clicking outside or pressing Escape dismisses; arrows move the highlight while open. Because
 * the popup is an overlay, its clicks are never stolen by whatever is drawn beneath it.
 *
 * A list taller than the space around the control scrolls inside the popup: mouse wheel, a
 * draggable scrollbar in the standard lane, and arrow keys that keep the highlight in view.
 * The popup expands above and below the selected row. Near a viewport edge it clips only the
 * overflowing part into an internal scroll window, so the selected row stays visually anchored.
 */
public class Dropdown <: Widget {
    private let id: String
    private let items: Array<String>
    private let selected: Bindable<Int64>
    private let open: State<Bool>
    // Identifies this control's popup on the overlay stack across per-frame rebuilds, so
    // closing removes exactly its own registration (a dialog beneath it stays open).
    private let overlayOwner: String
    // Scroll offset of the popup list, retained across the per-frame rebuild while open.
    private let popupScroll: State<Float32>
    private let popupMotion: SmoothScroll
    private let popupBar: ScrollBar
    // The row that was selected when this opening leg began. Keeping it stable prevents the
    // popup itself from jumping when arrow keys move the live selection.
    private let anchorIndex: State<Int64>
    // One progress value drives both legs of the matched-geometry transition: 0 is the closed
    // field, 1 is the full menu. Retargeting while closing reverses without a discontinuity.
    private let popupAnim: Tween
    private var frame = Rect.zero()

    public init(items: Array<String>, selected: Bindable<Int64>, key!: ?String = None) {
        let ident = resolveControlKey(key, "Dropdown")
        this.id = ident
        this.items = items
        this.selected = selected
        this.overlayOwner = "Dropdown:${ident}"
        this.open = localState<Bool>("Dropdown:${ident}:open") {false}
        let initialPopupScroll = localState<Float32>("Dropdown:${ident}:popupScroll") {0.0}
        this.popupScroll = initialPopupScroll
        this.popupMotion = localState<SmoothScroll>("Dropdown:${ident}:popupMotion") {
            SmoothScroll(initialPopupScroll.value)
        }.value
        this.popupBar = ScrollBar("Dropdown:${ident}:popupBar")
        this.anchorIndex = localState<Int64>("Dropdown:${ident}:anchor") {0}
        this.popupAnim = localState<Tween>("Dropdown:${ident}:anim") {
            Tween(DROPDOWN_ANIMATION_MS, {t => Easing.easeOutCubic(t)})
        }.value
        registerFocusable(ident)
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(min(available.w, DROPDOWN_DEFAULT_W), CUI_CONTROL_H)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        drawSurface(ctx, frame, closedSurface(ctx, ctx.showFocusRing(id) || open.value))
        let labelArea = Rect(frame.x + 10.0, frame.y, max(0.0, frame.w - 40.0), frame.h)
        ctx.renderer.pushClip(labelArea)
        let textY = frame.centerY() - ctx.renderer.textHeight(pointSize: FontSizes.CONTROL) * 0.3519
        ctx.renderer.text(currentLabel(), labelArea.x, textY, ctx.theme.text, pointSize: FontSizes.CONTROL)
        ctx.renderer.popClip()
        drawChevron(ctx, ctx.theme.mutedText)

        // While open, register the popup as the interactive overlay: it is drawn on top and
        // gets events before the tree (see the shell's dispatch order).
        if (open.value || popupAnim.value > 0.0) {
            let popup = popupRect(ctx)
            ctx.setOverlay(Overlay(handleEvent: {
                c, e => if (open.value) {
                    handleOverlay(c, e, popup)
                } else {
                    handleClosingOverlay(c, e)
                }
            }, render: {c => drawPopup(c, popup)}, owner: overlayOwner))
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        claimHoverIfInside(ctx, event, frame, id, CursorShape.Interactive)
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    ctx.focus(id)
                    openPopup(ctx) // when already open the overlay handles the click, not this
                    return true
                }
            case UiEvent.KeyDown(Key.Enter, _) => return openIfFocused(ctx)
            case UiEvent.KeyDown(Key.Space, _) => return openIfFocused(ctx)
            case UiEvent.KeyDown(Key.Down, _) => return openIfFocused(ctx)
            case _ => ()
        }
        false
    }

    public func focusableId(): ?String {
        Some(id)
    }

    private func openIfFocused(ctx: UiContext): Bool {
        if (ctx.hasFocus(id)) {
            openPopup(ctx)
            return true
        }
        false
    }

    // Opens the popup with the selected row pinned to the closed field's text position.
    private func openPopup(ctx: UiContext): Unit {
        open.value = true
        anchorIndex.value = clampDropdownIndex(selected.value, items.size)
        let popup = popupRect(ctx)
        // The visible top is the amount clipped from the ideal full menu. Using that exact
        // amount as scroll offset leaves the anchor row at the same screen y as the closed label.
        popupScroll.value = initialScrollOffset(popup)
        ctx.requestFrame()
    }

    private func contentHeight(): Float32 {
        Float32(items.size) * CUI_SMALL_H
    }

    private func listHeight(popup: Rect): Float32 {
        max(0.0, popup.h - DROPDOWN_POPUP_PAD * 2.0)
    }

    /** The inner list area: the popup minus its top and bottom padding strips. */
    private func listRect(popup: Rect): Rect {
        Rect(popup.x, popup.y + DROPDOWN_POPUP_PAD, popup.w, listHeight(popup))
    }

    // The overlay event handler while the popup is open. Runs before the tree, so it can claim
    // clicks that land on the popup and dismiss on clicks that land elsewhere.
    private func handleOverlay(ctx: UiContext, event: UiEvent, popup: Rect): Bool {
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (popup.contains(x, y)) {
                    if (popupBar.press(ctx, listRect(popup), popupScroll, contentHeight(), listHeight(popup), x, y)) {
                        return true // the press grabbed the scrollbar; the popup stays open
                    }
                    let index = itemIndexAt(popup, y)
                    if (index >= 0 && index < items.size) {
                        selected.value = index
                    }
                }
                close(ctx) // select-and-close, or dismiss on an outside click
                true
            case UiEvent.MouseMove(x, y) =>
                // While the thumb is grabbed the move scrolls the list; hover falls through, though the
                // popup still claims the default cursor so a control beneath cannot set its shape through it.
                if (popup.contains(x, y)) {
                    ctx.claimHover(overlayOwner, CursorShape.Default)
                }
                popupBar.drag(ctx, listRect(popup), popupScroll, contentHeight(), listHeight(popup), y)
            case UiEvent.MouseWheel(_, wheelY, x, y) =>
                if (popup.contains(x, y)) {
                    return popupMotion.wheel(ctx, popupScroll, wheelY, contentHeight(), listHeight(popup))
                }
                false
            case UiEvent.KeyDown(Key.Escape, _) =>
                close(ctx)
                true
            case UiEvent.KeyDown(Key.Enter, _) =>
                close(ctx)
                true
            case UiEvent.KeyDown(Key.Space, _) =>
                close(ctx)
                true
            case UiEvent.KeyDown(Key.Down, _) =>
                moveHighlight(1, popup)
                true
            case UiEvent.KeyDown(Key.Up, _) =>
                moveHighlight(-1, popup)
                true
            case UiEvent.KeyDown(Key.Tab, _) =>
                close(ctx) // commit and let the shell's Tab traversal move focus on
                false
            case _ => false
        }
    }

    private func close(ctx: UiContext): Unit {
        open.value = false
        // Retarget from the current progress. Tween preserves the in-flight value, so a fast
        // open/close gesture reverses along the same path instead of snapping.
        let _ = popupAnim.animate(ctx, target: 0.0)
        ctx.removeOverlay(overlayOwner)
    }

    // A closing surface remains above the field for the return leg. It consumes input so controls
    // underneath cannot be activated through it; pressing the original field reverses the leg.
    private func handleClosingOverlay(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    openPopup(ctx)
                }
                true
            case _ => true
        }
    }

    private func moveHighlight(delta: Int64, popup: Rect): Unit {
        if (items.isEmpty()) {
            return
        }
        // Clamp the current index into range before stepping (matching SegmentedControl/TabView),
        // so the move is relative to the displayed selection and the addition cannot overflow.
        selected.value = clampDropdownIndex(clampDropdownIndex(selected.value, items.size) + delta, items.size)
        revealRow(selected.value, popup)
    }

    // Scrolls just enough to keep the highlighted row visible — the reveal convention
    // shared with ListView and Table keyboard navigation.
    private func revealRow(index: Int64, popup: Rect): Unit {
        let listH = listHeight(popup)
        let rowTop = Float32(index) * CUI_SMALL_H
        var next = popupScroll.value
        if (rowTop < next) {
            next = rowTop
        }
        if (rowTop + CUI_SMALL_H > next + listH) {
            next = rowTop + CUI_SMALL_H - listH
        }
        let clamped = clampScrollOffset(next, contentHeight(), listH)
        if (clamped != popupScroll.value) {
            popupScroll.value = clamped
        }
    }

    // Maps a pointer y inside the popup to an item index, honouring the scroll offset.
    // The padding strips above and below the list hit nothing (-1).
    private func itemIndexAt(popup: Rect, y: Float32): Int64 {
        if (y < popup.y + DROPDOWN_POPUP_PAD || y >= popup.bottom() - DROPDOWN_POPUP_PAD) {
            return -1
        }
        Int64((y - popup.y - DROPDOWN_POPUP_PAD + popupMotion.value) / CUI_SMALL_H)
    }

    /*
     * Places the ideal, unbounded menu so the opening selection's row centre equals the closed
     * field's centre. Intersecting only its vertical ends with the viewport gives a SwiftUI-style
     * continuous expansion while preserving the selected row's screen position. The clipped
     * amount becomes the initial list scroll (see initialScrollOffset).
     */
    private func popupRect(ctx: UiContext): Rect {
        let fullHeight = contentHeight() + DROPDOWN_POPUP_PAD * 2.0
        let idealTop = idealPopupTop()
        if (ctx.viewportHeight <= DROPDOWN_MARGIN * 2.0) {
            return Rect(frame.x, idealTop, frame.w, fullHeight)
        }
        let top = max(DROPDOWN_MARGIN, idealTop)
        let bottom = min(ctx.viewportHeight - DROPDOWN_MARGIN, idealTop + fullHeight)
        Rect(frame.x, top, frame.w, max(0.0, bottom - top))
    }

    private func idealPopupTop(): Float32 {
        frame.centerY() - DROPDOWN_POPUP_PAD - Float32(anchorIndex.value) * CUI_SMALL_H - CUI_SMALL_H / 2.0
    }

    private func initialScrollOffset(popup: Rect): Float32 {
        clampScrollOffset(popup.y - idealPopupTop(), contentHeight(), listHeight(popup))
    }

    private func drawPopup(ctx: UiContext, popup: Rect): Unit {
        let target: Float32 = if (open.value) {
            1.0
        } else {
            0.0
        }
        let p = popupAnim.animate(ctx, target: target)
        let shell = morphRect(frame, popup, p)
        drawSurface(ctx, shell, morphSurface(ctx, p))
        let contentH = contentHeight()
        let listH = listHeight(popup)
        let list = listRect(popup)
        // The item set can change while open; keep the retained offset within range.
        let offset = clampScrollOffset(popupScroll.value, contentH, listH)
        if (offset != popupScroll.value) {
            popupScroll.value = offset
        }
        let visibleOffset = popupMotion.animate(ctx, popupScroll, contentH, listH)
        let gutter: Float32 = if (contentH > listH) {
            scrollBarGutter()
        } else {
            0.0
        }
        let rowW = max(0.0, popup.w - 8.0 - gutter)
        // Rows keep their final coordinates while the shell reveals them. The opening row is
        // already centred on the closed label, producing one continuous shot rather than a field
        // and a detached popup sliding between two unrelated positions.
        ctx.renderer.pushClip(shell)
        ctx.renderer.pushClip(list)
        var i = Int64(visibleOffset / CUI_SMALL_H)
        var y = list.y - (visibleOffset - Float32(i) * CUI_SMALL_H)
        while (i < items.size && y < list.bottom()) {
            let row = Rect(popup.x + 4.0, y, rowW, CUI_SMALL_H)
            if (i == selected.value) {
                // When a different row is chosen, carry that row into the field during the
                // return leg. At p=1 it is still where the user clicked; at p=0 its centre and
                // label baseline exactly match the closed control's new value.
                let selectedRow = if (open.value) {
                    row
                } else {
                    Rect(row.x, mixFloat(frame.centerY() - CUI_SMALL_H / 2.0, row.y, p), row.w, row.h)
                }
                ctx.renderer.fillRoundedRect(selectedRow, ctx.theme.smallRadius, scaledAlpha(ctx.theme.accent, p))
                drawRowLabel(ctx, items[i], selectedRow, ctx.theme.text.lerp(ctx.theme.accentText, p))
                drawCheckmark(ctx, selectedRow, scaledAlpha(ctx.theme.accentText, p))
            } else if (row.contains(ctx.mouseX, ctx.mouseY)) {
                ctx.renderer.fillRoundedRect(row, ctx.theme.smallRadius, scaledAlpha(ctx.theme.fieldActive, p))
                drawRowLabel(ctx, items[i], row, scaledAlpha(ctx.theme.text, p))
            } else {
                drawRowLabel(ctx, items[i], row, scaledAlpha(ctx.theme.text, p))
            }
            y += CUI_SMALL_H
            i += 1
        }
        ctx.renderer.popClip()
        drawVerticalScrollBar(ctx, list, visibleOffset, contentH, listH, active: popupBar.dragging(ctx), reveal: p)
        // The trigger chevron belongs to the collapsed endpoint; it cross-fades into the selected
        // row's checkmark while staying at exactly the same coordinates.
        drawChevron(ctx, scaledAlpha(ctx.theme.mutedText, 1.0 - p))
        ctx.renderer.popClip()
        if (!open.value && p <= 0.0) {
            // The shell clears overlay registrations at the start of a frame. Ask for that final
            // cleanup frame after the tween has settled so no stale invisible layer can eat input.
            ctx.requestFrame()
        }
    }

    // A down chevron drawn as two strokes, so it never depends on a font glyph.
    private func drawChevron(ctx: UiContext, color: Color): Unit {
        let cx = frame.right() - 18.0
        let cy = frame.centerY()
        let pen = Pen(width: 1.6, color: color)
        ctx.renderer.strokeLine(cx - 4.0, cy - 2.0, cx, cy + 2.5, pen)
        ctx.renderer.strokeLine(cx, cy + 2.5, cx + 4.0, cy - 2.0, pen)
    }

    private func drawCheckmark(ctx: UiContext, row: Rect, color: Color): Unit {
        let cx = frame.right() - 18.0
        let cy = row.centerY()
        let pen = Pen(width: 1.8, color: color)
        ctx.renderer.strokeLine(cx - 4.5, cy, cx - 1.0, cy + 3.5, pen)
        ctx.renderer.strokeLine(cx - 1.0, cy + 3.5, cx + 5.0, cy - 3.5, pen)
    }

    private func drawRowLabel(ctx: UiContext, text: String, row: Rect, color: Color): Unit {
        let textY = row.centerY() - ctx.renderer.textHeight(pointSize: FontSizes.CONTROL) * 0.3519
        let label = Rect(row.x + 6.0, row.y, max(0.0, row.w - 34.0), row.h)
        ctx.renderer.pushClip(label)
        ctx.renderer.text(text, label.x, textY, color, pointSize: FontSizes.CONTROL)
        ctx.renderer.popClip()
    }

    private func closedSurface(ctx: UiContext, active: Bool): SurfaceStyle {
        if (!isLightTheme(ctx)) {
            return ctx.theme.fieldSurface(active)
        }
        SurfaceStyle(
            DROPDOWN_BACKGROUND,
            border: if (active) {
                ctx.theme.accent
            } else {
                ctx.theme.panelEdge
            },
            radius: ctx.theme.controlRadius,
            borderWidth: ctx.theme.borderWidth,
            shadow: if (active) {
                ctx.theme.accent.withAlpha(34)
            } else {
                Color.rgba(0, 0, 0, 0)
            },
            shadowOffsetY: 1.0
        )
    }

    private func morphSurface(ctx: UiContext, progress: Float32): SurfaceStyle {
        let collapsed = closedSurface(ctx, open.value || ctx.showFocusRing(id))
        let expanded = popupSurface(ctx)
        SurfaceStyle(
            collapsed.fill.lerp(expanded.fill, progress),
            border: collapsed.border.lerp(expanded.border, progress),
            radius: mixFloat(collapsed.radius, expanded.radius, progress),
            borderWidth: mixFloat(collapsed.borderWidth, expanded.borderWidth, progress),
            shadow: collapsed.shadow.lerp(expanded.shadow, progress),
            shadowOffsetY: mixFloat(collapsed.shadowOffsetY, expanded.shadowOffsetY, progress)
        )
    }

    private func popupSurface(ctx: UiContext): SurfaceStyle {
        let background = if (isLightTheme(ctx)) {
            DROPDOWN_BACKGROUND
        } else {
            ctx.theme.panelRaised
        }
        SurfaceStyle(background, border: ctx.theme.panelEdge, radius: ctx.theme.controlRadius, borderWidth: 1.0,
            shadow: ctx.theme.shadow, shadowOffsetY: 4.0)
    }

    private func currentLabel(): String {
        if (items.isEmpty()) {
            "—"
        } else {
            items[clampDropdownIndex(selected.value, items.size)]
        }
    }

    public func isFlexible(): Bool {
        false
    }
}

private func isLightTheme(ctx: UiContext): Bool {
    let bg = ctx.theme.bg
    Int64(bg.r) * 299 + Int64(bg.g) * 587 + Int64(bg.b) * 114 >= 128000
}

private func morphRect(from: Rect, to: Rect, progress: Float32): Rect {
    let p = clampF32(progress, 0.0, 1.0)
    let top = mixFloat(from.y, to.y, p)
    let bottom = mixFloat(from.bottom(), to.bottom(), p)
    Rect(mixFloat(from.x, to.x, p), top, mixFloat(from.w, to.w, p), max(0.0, bottom - top))
}

private func mixFloat(from: Float32, to: Float32, progress: Float32): Float32 {
    from + (to - from) * clampF32(progress, 0.0, 1.0)
}

private func scaledAlpha(color: Color, progress: Float32): Color {
    color.withAlpha(Int64(Float32(Int64(color.a)) * clampF32(progress, 0.0, 1.0)))
}

private func clampDropdownIndex(index: Int64, count: Int64): Int64 {
    if (count <= 0) {
        0
    } else if (index < 0) {
        0
    } else if (index >= count) {
        count - 1
    } else {
        index
    }
}
