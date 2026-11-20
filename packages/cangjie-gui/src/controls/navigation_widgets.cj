package cui.controls

import std.collection.ArrayList
import lbase.{Rect, Size, clampF32}
import cui.base.{Key, MouseButton, UiEvent}
import cui.core.{Bindable, CUI_CONTROL_H, CUI_GAP, CursorShape, Spring, UiContext, Widget, buildChildren,
    buildKeyedChild, claimHoverIfInside, drawFocusRing, drawSurface, emit, focusableControlIdentity, localState,
    requireControlId, unregisterFocusable}

public class SegmentedControl <: Widget {
    private let items: Array<String>
    private let selected: Bindable<Int64>
    private let controlId: String
    // The selection pill slides between segments. Retained across rebuilds and started at the
    // current selection, so a static first frame is settled (snapshot-stable).
    private let indicatorSpring: Spring
    private var frame = Rect.zero()

    public init(items: Array<String>, selected: Bindable<Int64>, key!: ?String = None) {
        this.items = items
        this.selected = selected
        // A focus stop: Tab reaches the control, Left/Right switch the selected segment. Identity is
        // optional and auto-derived by build order; pass `key` for a stable, addressable one.
        let base = match (key) {
            case Some(value) =>
                requireControlId(value, "SegmentedControl")
                value
            case None => "SegmentedControl"
        }
        let cid = focusableControlIdentity(base)
        this.controlId = cid
        let start = Float32(clampIndex(selected.value, items.size))
        this.indicatorSpring = localState<Spring>("${cid}:indicator") {Spring(start)}.value
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        let desired = max(96.0, Float32(items.size) * 96.0)
        Size(min(available.w, desired), CUI_CONTROL_H)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        if (items.size == 0) {
            return
        }
        drawSurface(ctx, frame, ctx.theme.fieldSurface(false))
        let target = Float32(clampIndex(selected.value, items.size))
        drawSlidingSegments(ctx, frame, items, indicatorSpring.animate(ctx, target: target))
        if (ctx.showFocusRing(controlId)) {
            drawFocusRing(ctx, frame, ctx.theme.controlRadius)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        claimHoverIfInside(ctx, event, frame, controlId, CursorShape.Interactive)
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (frame.contains(x, y) && items.size > 0) {
                    ctx.focus(controlId)
                    let segmentW = frame.w / Float32(items.size)
                    selected.value = clampIndex(Int64((x - frame.x) / segmentW), items.size)
                    return true
                }
            case UiEvent.KeyDown(Key.Left, _) => return stepSelection(ctx, -1)
            case UiEvent.KeyDown(Key.Right, _) => return stepSelection(ctx, 1)
            case _ => ()
        }
        false
    }

    public func focusableId(): ?String {
        Some(controlId)
    }

    private func stepSelection(ctx: UiContext, delta: Int64): Bool {
        if (!ctx.hasFocus(controlId) || items.size == 0) {
            return false
        }
        selected.value = clampIndex(clampIndex(selected.value, items.size) + delta, items.size)
        true
    }
}

public class TabView <: Widget {
    private let labels: Array<String>
    private let selected: Bindable<Int64>
    // Eager mode (the `body!` init): every declared page, built every frame. Empty in lazy mode.
    private let pages: Array<Widget>
    // Lazy mode (the `page!` init): the single built page and the tab index it was built for.
    // Hidden pages are never constructed, so they cost no build and register no focus stops.
    private var lazyPage: ?Widget = None
    private var lazyIndex: Int64 = -1
    private let controlId: String
    private let indicatorSpring: Spring
    private var frame = Rect.zero()
    private var laidOutPage: Int64 = -1

    public init(labels: Array<String>, selected: Bindable<Int64>, key!: ?String = None, body!: () -> Unit) {
        this.labels = labels
        this.selected = selected
        // A focus stop: Tab reaches the strip, Left/Right switch the selected tab. Registered
        // before the pages build, so Tab lands on the strip before the controls inside a page —
        // matching the visual order (strip above content).
        let base = match (key) {
            case Some(value) =>
                requireControlId(value, "TabView")
                value
            case None => "TabView"
        }
        let cid = focusableControlIdentity(base)
        this.controlId = cid
        this.pages = buildChildren(body)
        // Only the active page can receive events, so stops on hidden pages would be dead
        // ends for Tab: building registers every page's controls, then the inactive pages'
        // stops are taken out again. Switching tabs re-registers on the next frame's rebuild.
        let active = clampIndex(selected.value, this.pages.size)
        var i = 0
        while (i < this.pages.size) {
            if (i != active) {
                for (id in this.pages[i].focusableIds()) {
                    unregisterFocusable(id)
                }
            }
            i += 1
        }
        // The active-tab indicator slides between tabs; started at the current tab so a static
        // first frame is settled (snapshot-stable).
        let start = Float32(clampIndex(selected.value, labels.size))
        this.indicatorSpring = localState<Spring>("${cid}:indicator") {Spring(start)}.value
        emit(this)
    }

    /*
     * Lazy variant (#28): `page` is the per-tab builder and is invoked ONLY for the active
     * tab, so a multi-page TabView pays 1/N of the per-frame build cost. A hidden page is
     * absent from the build entirely — it registers no focus stops, so there is nothing to
     * unregister per frame — and is first constructed on the rebuild after it becomes active.
     *
     * Each page builds inside its own keyed scope (`<id>:tab:<index>`), giving its localState
     * a stable per-tab identity independent of which sibling pages are built. As with other
     * lazily built content (LazyGrid cells), a page's remembered state follows unmount
     * semantics: released while the page is hidden, recreated on activation. Views that need
     * cross-tab state should hoist it into the model, not `rememberState`.
     */
    public init(labels: Array<String>, selected: Bindable<Int64>, key!: ?String = None, page!: (Int64) -> Unit) {
        this.labels = labels
        this.selected = selected
        this.pages = []
        let base = match (key) {
            case Some(value) =>
                requireControlId(value, "TabView")
                value
            case None => "TabView"
        }
        // Same focus-stop ordering as the eager init: the strip registers before page content.
        let cid = focusableControlIdentity(base)
        this.controlId = cid
        // labels 为空时不构建任何页面：clampIndex 会把下标钳到 0，若不守卫就会对
        // 不存在的第 0 页调用 page(0)，凭空构建一页幻影内容。
        if (labels.size > 0) {
            let active = clampIndex(selected.value, labels.size)
            this.lazyPage = Some(buildKeyedChild("${cid}:tab:${active}") {
                page(active)
            })
            this.lazyIndex = active
        }
        let start = Float32(clampIndex(selected.value, labels.size))
        this.indicatorSpring = localState<Spring>("${cid}:indicator") {Spring(start)}.value
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, available.h)
    }

    public func layout(ctx: UiContext, rect: Rect): Unit {
        frame = rect
        layoutActivePage(ctx)
    }

    public func draw(ctx: UiContext): Unit {
        drawTabs(ctx)
        match (shownPage()) {
            case Some(page) =>
                ensureActivePageLayout(ctx)
                page.draw(ctx)
            case None => ()
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        // Only the tab strip is a click target; pages claim their own hover shapes.
        claimHoverIfInside(ctx, event, Rect(frame.x, frame.y, frame.w, CUI_CONTROL_H), controlId,
            CursorShape.Interactive)
        if (handleTabs(ctx, event)) {
            ensureActivePageLayout(ctx)
            return true
        }
        match (shownPage()) {
            case Some(page) =>
                ensureActivePageLayout(ctx)
                return page.handle(ctx, event)
            case None => false
        }
    }

    public func isFlexible(): Bool {
        true
    }

    public func focusableId(): ?String {
        Some(controlId)
    }

    public func focusableIds(): Array<String> {
        // The strip plus every page's stops, so disabling a whole TabView removes them all.
        // Lazy mode has only the shown page — hidden pages were never built, so there are
        // no stops of theirs to remove (eager mode includes hidden pages', which a later
        // frame's rebuild would otherwise re-register).
        let ids = ArrayList<String>()
        ids.add(controlId)
        match (lazyPage) {
            case Some(page) =>
                for (id in page.focusableIds()) {
                    ids.add(id)
                }
            case None =>
                for (page in pages) {
                    for (id in page.focusableIds()) {
                        ids.add(id)
                    }
                }
        }
        ids.toArray()
    }

    private func pageIndex(): Int64 {
        match (lazyPage) {
            case Some(_) => clampIndex(selected.value, labels.size)
            case None => clampIndex(selected.value, pages.size)
        }
    }

    /*
     * The page drawn and given events this frame. Lazy mode holds the page built at
     * construction; when the selection moved mid-frame (a strip click, code driving the
     * State) that is still the outgoing page — the incoming one is constructed on the next
     * rebuild. Events keep flowing to the outgoing page for the rest of the frame, which is
     * harmless: a strip click lands above the page frame and is never claimed by it.
     */
    private func shownPage(): ?Widget {
        match (lazyPage) {
            case Some(page) => Some(page)
            case None =>
                if (pages.size == 0) {
                    None
                } else {
                    Some(pages[pageIndex()])
                }
        }
    }

    private func layoutActivePage(ctx: UiContext): Unit {
        match (lazyPage) {
            case Some(page) =>
                page.layout(ctx, pageFrame())
                laidOutPage = lazyIndex
            case None =>
                if (pages.size == 0) {
                    return
                }
                let index = pageIndex()
                pages[index].layout(ctx, pageFrame())
                laidOutPage = index
        }
    }

    /*
     * The selected tab can change between a frame's layout pass and its draw/handle
     * passes — a click switches pages mid event drain, or code drives the State. In eager
     * mode the incoming page already exists and is laid out again on demand so it is never
     * drawn or handled with a stale (or never assigned) frame. Lazy mode needs nothing: the
     * shown page's layout is still valid, and the incoming page is built next frame.
     */
    private func ensureActivePageLayout(ctx: UiContext): Unit {
        if (lazyPage.isNone() && pages.size > 0) {
            if (pageIndex() != laidOutPage) {
                layoutActivePage(ctx)
            }
        }
    }

    private func pageFrame(): Rect {
        Rect(frame.x, frame.y + CUI_CONTROL_H + CUI_GAP, frame.w, max(0.0, frame.h - CUI_CONTROL_H - CUI_GAP))
    }

    private func drawTabs(ctx: UiContext): Unit {
        if (labels.size == 0) {
            return
        }
        let header = Rect(frame.x, frame.y, frame.w, CUI_CONTROL_H)
        drawSurface(ctx, header, ctx.theme.fieldSurface(false))
        let target = Float32(clampIndex(selected.value, labels.size))
        drawSlidingSegments(ctx, header, labels, indicatorSpring.animate(ctx, target: target))
        if (ctx.showFocusRing(controlId)) {
            drawFocusRing(ctx, header, ctx.theme.controlRadius)
        }
    }

    private func handleTabs(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                let header = Rect(frame.x, frame.y, frame.w, CUI_CONTROL_H)
                if (header.contains(x, y) && labels.size > 0) {
                    ctx.focus(controlId)
                    let tabW = frame.w / Float32(labels.size)
                    selected.value = clampIndex(Int64((x - frame.x) / tabW), labels.size)
                    return true
                }
            case UiEvent.KeyDown(Key.Left, _) => return stepTab(ctx, -1)
            case UiEvent.KeyDown(Key.Right, _) => return stepTab(ctx, 1)
            case _ => ()
        }
        false
    }

    private func stepTab(ctx: UiContext, delta: Int64): Bool {
        if (!ctx.hasFocus(controlId) || labels.size == 0) {
            return false
        }
        selected.value = clampIndex(clampIndex(selected.value, labels.size) + delta, labels.size)
        true
    }
}

// Draws a segmented row's selection pill and labels, with the pill slid to `animatedIndex` (a
// fractional segment index). The label the pill mostly covers is drawn in the accent-on text
// colour; the pill is clamped to the row so a spring overshoot never escapes the control.
private func drawSlidingSegments(ctx: UiContext, row: Rect, items: Array<String>, animatedIndex: Float32): Unit {
    let count = items.size
    let segmentW = row.w / Float32(count)
    let clamped = clampF32(animatedIndex, 0.0, Float32(count - 1))
    drawSurface(ctx, Rect(row.x + clamped * segmentW, row.y, segmentW, row.h).inset(3.0), ctx.theme.selectedSurface())
    let highlighted = Int64(clamped + 0.5)
    var i: Int64 = 0
    while (i < count) {
        let cell = Rect(row.x + Float32(i) * segmentW, row.y, segmentW, row.h)
        let color = if (i == highlighted) {
            ctx.theme.accentText
        } else {
            ctx.theme.text
        }
        ctx.renderer.textCenter(items[i], cell, color)
        i += 1
    }
}

private func clampIndex(index: Int64, count: Int64): Int64 {
    if (count <= 0 || index < 0) {
        0
    } else if (index >= count) {
        count - 1
    } else {
        index
    }
}
