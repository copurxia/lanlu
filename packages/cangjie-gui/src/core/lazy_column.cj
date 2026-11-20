package cui.core

import std.collection.ArrayList
import lbase.{Rect, Size}
import cui.base.{UiEvent}

// Extra rows built above and below the viewport so a one-frame scroll never reveals a blank edge.
let LAZY_OVERSCAN: Int64 = 2

// The viewport height assumed on the very first frame, before layout has measured the real one — a
// full-ish screen, so the first frame is populated rather than blank. Layout corrects it at once.
let LAZY_DEFAULT_VIEWPORT: Float32 = 720.0

/**
 * A vertically scrolling list that materializes only the rows near the viewport. Rows have a fixed
 * height (in logical pixels) and are built on demand by index, so build, layout and draw are all
 * O(visible) rather than O(count): a list of thousands of arbitrary item widgets scrolls at the
 * cost of a screenful.
 *
 * Because only visible rows are built, per-row local state (`rememberState` / `Keyed`) lives only
 * while a row is on screen and is dropped when it scrolls off; hoist any state that must outlive
 * scrolling into the application model. The scroll offset may be owned externally (via `scroll`) for
 * coordination or animation. The `id` scopes the retained scroll and per-row state, like other
 * scrollable controls.
 *
 * Immediate-mode note: the tree is rebuilt every frame, so the visible window is chosen during the
 * build pass from the scroll offset and viewport height retained from the previous frame, then that
 * same snapshot drives layout and draw. A wheel or drag updates the live offset for the next frame;
 * the overscan rows keep the edges filled across that one-frame settle.
 */
public class LazyColumn <: Widget {
    private let count: Int64
    private let itemHeight: Float32
    private let spacing: Float32
    private let scrollStateValue: State<Float32>
    private let viewportHeightState: State<Float32>
    private let scrollMotion: SmoothScroll
    private let scrollBar: ScrollBar
    // Rows materialized this frame, each paired with its absolute index for positioning and events.
    private let visibleItems: Array<(Int64, Widget)>
    // The scroll offset snapshotted for the whole frame so build, layout and draw agree.
    private var frameScroll: Float32
    private var frame = Rect.zero()

    /**
     * The index form: `count` rows built on demand by index. `id` is the optional container identity
     * (auto-derived by build order when omitted; an explicit one must be non-empty). Row height is in
     * logical pixels. `key` optionally gives each row a stable identity string (so its per-row state
     * follows the item across inserts/reorders); when omitted, rows are keyed by index — see
     * `LazyColumn.of` for the data-driven form.
     */
    public init(
        count: Int64,
        itemHeight: Float32,
        spacing!: Float32 = 0.0,
        scroll!: ?State<Float32> = None,
        key!: ?((Int64) -> String) = None,
        id!: ?String = None,
        item!: (Int64) -> Unit
    ) {
        let ident = resolveControlKey(id, "LazyColumn")
        this.count = max(0, count)
        this.itemHeight = max(1.0, itemHeight)
        this.spacing = max(0.0, spacing)
        let initialScroll = match (scroll) {
            case Some(value) => value
            case None => localState<Float32>("LazyColumn:${ident}:scroll") {0.0}
        }
        this.scrollStateValue = initialScroll
        // Retained so the build pass (which has no layout rect yet) knows how tall the viewport was
        // last frame and thus which rows to materialize; layout updates it for the next frame.
        this.viewportHeightState = localState<Float32>("LazyColumn:${ident}:viewportH") {LAZY_DEFAULT_VIEWPORT}
        this.scrollMotion = localState<SmoothScroll>("LazyColumn:${ident}:motion") {
            SmoothScroll(initialScroll.value)
        }.value
        this.scrollBar = ScrollBar("LazyColumn:${ident}:thumb")
        let content = lazyContentHeight(this.count, this.itemHeight, this.spacing)
        this.frameScroll = clampScrollOffset(this.scrollStateValue.value, content, this.viewportHeightState.value)
        let (first, last) = lazyVisibleRange(this.frameScroll, this.viewportHeightState.value, this.itemHeight,
            this.spacing, this.count, LAZY_OVERSCAN)
        this.visibleItems = buildLazyChildren("LazyColumn:${ident}", first, last, lazyKeyOrIndex(key), item)
        emit(this)
    }

    /**
     * The data-driven form: builds a virtualized column from `data` and a per-item row builder, so a
     * list of arbitrary item widgets over an `Array<T>` needs neither a manual `count` nor an
     * index-into-data lookup. `key` gives each item a stable identity (its per-row state and position
     * follow the item across inserts/reorders rather than the slot); omit it to key by index.
     * `itemHeight` is the fixed row height in logical pixels, as for the index form.
     *
     * ```
     * LazyColumn.of(model.notes, 72.0, key: {n => n.id}) { note => noteRow(note) }
     * ```
     */
    public static func of<T>(
        data: Array<T>,
        itemHeight: Float32,
        spacing!: Float32 = 0.0,
        scroll!: ?State<Float32> = None,
        key!: ?((T) -> String) = None,
        id!: ?String = None,
        item!: (T) -> Unit
    ): LazyColumn {
        let rowKey: ?((Int64) -> String) = match (key) {
            case Some(k) => Some({index => k(data[index])})
            case None => None
        }
        LazyColumn(data.size, itemHeight, spacing: spacing, scroll: scroll, key: rowKey, id: id) {
            index => item(data[index])
        }
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, available.h)
    }

    public func layout(ctx: UiContext, rect: Rect): Unit {
        frame = rect
        // Record the viewport height for the next frame's build; write-on-change to avoid churn.
        let _ = viewportHeightState.setIfChanged(rect.h)
        let content = lazyContentHeight(count, itemHeight, spacing)
        // Correct the live offset for the next frame in case the content shrank.
        let clamped = clampScrollOffset(scrollStateValue.value, content, rect.h)
        if (clamped != scrollStateValue.value) {
            scrollStateValue.value = clamped
        }
        frameScroll = scrollMotion.animate(ctx, scrollStateValue, content, rect.h)
        let stride = itemHeight + spacing
        let contentWidth = if (content > rect.h) {
            max(0.0, rect.w - scrollBarGutter())
        } else {
            rect.w
        }
        for (pair in visibleItems) {
            let (index, widget) = pair
            let y = rect.y - frameScroll + Float32(index) * stride
            widget.layout(ctx, Rect(rect.x, y, contentWidth, itemHeight))
        }
    }

    public func draw(ctx: UiContext): Unit {
        let content = lazyContentHeight(count, itemHeight, spacing)
        let stride = itemHeight + spacing
        // Exact on the scroll axis, shadow clearance on the cross axis (see CUI_SHADOW_CLEARANCE).
        ctx.renderer.pushClip(Rect(frame.x - CUI_SHADOW_CLEARANCE, frame.y, frame.w + 2.0 * CUI_SHADOW_CLEARANCE,
            frame.h))
        for (pair in visibleItems) {
            let (index, widget) = pair
            // Clip each row to its own bounds plus shadow clearance (intersected with the viewport):
            // grossly oversized content is still truncated near its slot, while a card row's soft
            // halo wraps its corners instead of being cut into hard-edged bands at the slot line.
            let rowRect = Rect(frame.x, frame.y - frameScroll + Float32(index) * stride, frame.w, itemHeight)
            ctx.renderer.pushClip(rowRect.inset(-CUI_SHADOW_CLEARANCE))
            widget.draw(ctx)
            ctx.renderer.popClip()
        }
        ctx.renderer.popClip()
        drawVerticalScrollBar(ctx, frame, frameScroll, content, frame.h, active: scrollBar.dragging(ctx))
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        let content = lazyContentHeight(count, itemHeight, spacing)
        let viewportH = frame.h
        match (event) {
            case UiEvent.Frame(_) =>
                for (pair in visibleItems) {
                    let (_, widget) = pair
                    let _ = widget.handle(ctx, event)
                }
                return false
            case UiEvent.MouseWheel(_, wheelY, pointerX, pointerY) =>
                if (frame.contains(pointerX, pointerY)) {
                    if (scrollMotion.wheel(ctx, scrollStateValue, wheelY, content, viewportH)) {
                        return true
                    }
                }
            case UiEvent.MouseDown(_, x, y) =>
                if (scrollBar.press(ctx, frame, scrollStateValue, content, viewportH, x, y)) {
                    return true
                }
                if (!frame.contains(x, y)) {
                    return false
                }
            case UiEvent.MouseMove(x, y) =>
                if (scrollBar.drag(ctx, frame, scrollStateValue, content, viewportH, y)) {
                    return true
                }
                // While a child drag is live, track the pointer past the edge to the release.
                if (!frame.contains(x, y) && ctx.dragId.isEmpty()) {
                    return false
                }
            case UiEvent.MouseUp(_, x, y) =>
                if (!frame.contains(x, y) && ctx.dragId.isEmpty()) {
                    return false
                }
            case _ => ()
        }
        // Route to the materialized rows, top-most first, so a row consumes its own clicks.
        var i = visibleItems.size - 1
        while (i >= 0) {
            let (_, widget) = visibleItems[i]
            if (widget.handle(ctx, event)) {
                return true
            }
            i -= 1
        }
        false
    }

    public func isFlexible(): Bool {
        true
    }

    public func focusableIds(): Array<String> {
        let ids = ArrayList<String>()
        for (pair in visibleItems) {
            let (_, widget) = pair
            for (fid in widget.focusableIds()) {
                ids.add(fid)
            }
        }
        ids.toArray()
    }
}

/**
 * A virtualized column for use INSIDE an ancestor scroller (`ScrollView`), where `LazyColumn`
 * cannot go: it reports its full content height like a plain `VStack` and owns no scrolling of
 * its own — no wheel handling, no scrollbar — so the page keeps a single scroll position and the
 * column flows with the surrounding content. Only the rows intersecting the clip currently in
 * effect (the ancestor viewport) are materialized, so build, layout and draw stay O(visible)
 * even for thousands of rows deep inside a long page.
 *
 * Immediate-mode note: the tree is rebuilt every frame, so the visible window is chosen during
 * the build pass from the frame and clip retained during the previous frame's layout and draw,
 * then that same snapshot drives layout and draw. An ancestor scroll shifts the retained frame on
 * the next layout; the overscan rows keep the edges filled across that one-frame settle. Before
 * the first draw the clip is unknown and a default screenful (`LAZY_DEFAULT_VIEWPORT`) is built
 * from the top; in a genuinely unclipped context (headless tests, direct root drawing) the column
 * degrades to building every row, matching a plain `VStack`.
 *
 * Per-row state lives only while a row is on screen and is dropped when it scrolls off — hoist
 * anything that must persist into the application model, exactly as for `LazyColumn`.
 */
public class ClipLazyColumn <: Widget {
    private let count: Int64
    private let itemHeight: Float32
    private let spacing: Float32
    // Rows materialized this frame, each paired with its absolute index for positioning and events.
    private let visibleItems: Array<(Int64, Widget)>
    private var frame = Rect.zero()
    // Retained across builds so the build pass (which runs before layout) knows where the ancestor
    // viewport sat over this content last frame: this widget's absolute top from the last layout,
    // and the clip in effect during the last draw. Writes go through setIfChanged — layout and
    // draw run every frame, and unchanged values must not notify observers.
    private let frameTopState: State<Float32>
    private let clipTopState: State<Float32>
    private let clipBottomState: State<Float32>
    // 0 = no clip seen yet (first frame), 1 = clipped by an ancestor (window to it),
    // 2 = drawn unclipped (nothing to window against — build everything).
    private let clipModeState: State<Int64>

    /**
     * The index form: `count` rows built on demand by index. Mirrors `LazyColumn`'s constructor
     * minus the `scroll` parameter — the ancestor owns the scroll offset. `id` scopes the retained
     * frame/clip snapshot and per-row state, like other controls.
     */
    public init(
        count: Int64,
        itemHeight: Float32,
        spacing!: Float32 = 0.0,
        key!: ?((Int64) -> String) = None,
        id!: ?String = None,
        item!: (Int64) -> Unit
    ) {
        let ident = resolveControlKey(id, "ClipLazyColumn")
        this.count = max(0, count)
        this.itemHeight = max(1.0, itemHeight)
        this.spacing = max(0.0, spacing)
        this.frameTopState = localState<Float32>("ClipLazyColumn:${ident}:frameY") {0.0}
        this.clipTopState = localState<Float32>("ClipLazyColumn:${ident}:clipTop") {0.0}
        this.clipBottomState = localState<Float32>("ClipLazyColumn:${ident}:clipBottom") {0.0}
        this.clipModeState = localState<Int64>("ClipLazyColumn:${ident}:clipMode") {0}
        let (first, last) = match (clipModeState.value) {
            case 1 => lazyVisibleRange(clipTopState.value - frameTopState.value,
                clipBottomState.value - clipTopState.value, this.itemHeight, this.spacing, this.count,
                LAZY_OVERSCAN)
            case 2 => (0, this.count - 1)
            case _ => lazyVisibleRange(0.0, LAZY_DEFAULT_VIEWPORT, this.itemHeight, this.spacing, this.count,
                LAZY_OVERSCAN)
        }
        this.visibleItems = buildLazyChildren("ClipLazyColumn:${ident}", first, last, lazyKeyOrIndex(key), item)
        emit(this)
    }

    // Full content height: the column occupies its complete extent in the ancestor's flow, exactly
    // as if every row were built — the windowing is invisible to layout.
    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, lazyContentHeight(count, itemHeight, spacing))
    }

    public func layout(ctx: UiContext, rect: Rect): Unit {
        frame = rect
        // Retain the absolute top for the next frame's build; write-on-change to avoid churn.
        let _ = frameTopState.setIfChanged(rect.y)
        let stride = itemHeight + spacing
        for (pair in visibleItems) {
            let (index, widget) = pair
            widget.layout(ctx, Rect(rect.x, rect.y + Float32(index) * stride, rect.w, itemHeight))
        }
    }

    public func draw(ctx: UiContext): Unit {
        // Retain the clip in effect (the ancestor scroller's viewport, intersected with any
        // defensive ancestor clips) for the next frame's build. An empty stack means this draw is
        // unclipped, so there is nothing to window against.
        match (ctx.renderer.currentClip()) {
            case Some(clip) =>
                let _ = clipTopState.setIfChanged(clip.y)
                let _ = clipBottomState.setIfChanged(clip.bottom())
                let _ = clipModeState.setIfChanged(1)
            case None =>
                let _ = clipModeState.setIfChanged(2)
        }
        let stride = itemHeight + spacing
        for (pair in visibleItems) {
            let (index, widget) = pair
            // Same per-row clip as LazyColumn: grossly oversized content is still truncated near
            // its slot, while a card row's soft halo survives via the shadow clearance. The
            // viewport clip itself is the ancestor's job, not repeated here.
            let rowRect = Rect(frame.x, frame.y + Float32(index) * stride, frame.w, itemHeight)
            ctx.renderer.pushClip(rowRect.inset(-CUI_SHADOW_CLEARANCE))
            widget.draw(ctx)
            ctx.renderer.popClip()
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.Frame(_) =>
                for (pair in visibleItems) {
                    let (_, widget) = pair
                    let _ = widget.handle(ctx, event)
                }
                return false
            // This column scrolls nothing itself: the wheel falls through to the ancestor
            // scroller unless a materialized row consumes it below.
            case UiEvent.MouseDown(_, x, y) =>
                if (!frame.contains(x, y)) {
                    return false
                }
            case UiEvent.MouseMove(x, y) =>
                // While a child drag is live, track the pointer past the edge to the release.
                if (!frame.contains(x, y) && ctx.dragId.isEmpty()) {
                    return false
                }
            case UiEvent.MouseUp(_, x, y) =>
                if (!frame.contains(x, y) && ctx.dragId.isEmpty()) {
                    return false
                }
            case _ => ()
        }
        // Route to the materialized rows, top-most first, so a row consumes its own clicks.
        var i = visibleItems.size - 1
        while (i >= 0) {
            let (_, widget) = visibleItems[i]
            if (widget.handle(ctx, event)) {
                return true
            }
            i -= 1
        }
        false
    }

    public func focusableIds(): Array<String> {
        let ids = ArrayList<String>()
        for (pair in visibleItems) {
            let (_, widget) = pair
            for (fid in widget.focusableIds()) {
                ids.add(fid)
            }
        }
        ids.toArray()
    }
}

/** The total scrollable height of `count` fixed-height rows separated by `spacing`. */
internal func lazyContentHeight(count: Int64, itemHeight: Float32, spacing: Float32): Float32 {
    if (count <= 0) {
        return 0.0
    }
    Float32(count) * (itemHeight + spacing) - spacing
}

/*
 * The inclusive [first, last] row range to materialize for a viewport at `scroll`, widened by
 * `overscan` rows each side. Returns an empty range (first > last) when there is nothing to show.
 */
internal func lazyVisibleRange(
    scroll: Float32,
    viewportH: Float32,
    itemHeight: Float32,
    spacing: Float32,
    count: Int64,
    overscan: Int64
): (Int64, Int64) {
    if (count <= 0 || itemHeight <= 0.0) {
        return (0, -1)
    }
    let stride = itemHeight + spacing
    let top = max(0.0, scroll)
    var first = Int64(top / stride) - overscan
    if (first < 0) {
        first = 0
    }
    var last = Int64((top + max(0.0, viewportH)) / stride) + overscan
    if (last > count - 1) {
        last = count - 1
    }
    (first, last)
}

// Materializes the visible items in `[first, last]` during the build pass, each scoped by
// `scope:item:key(index)` so its local state follows it (across scrolls, and — with a data key —
// across inserts/reorders); it is dropped when the item scrolls off, so hoist anything that must
// persist. Shared by both axes: LazyColumn passes its rows, LazyRow its columns — and by
// ReorderableList in cui.controls, which virtualizes its rows the same way.
protected func buildLazyChildren(
    scope: String,
    first: Int64,
    last: Int64,
    key: (Int64) -> String,
    item: (Int64) -> Unit
): Array<(Int64, Widget)> {
    let built = ArrayList<(Int64, Widget)>()
    var index = first
    while (index <= last) {
        let itemIndex = index
        let widget = buildKeyedChild("${scope}:item:${key(itemIndex)}") {=> item(itemIndex)}
        built.add((itemIndex, widget))
        index += 1
    }
    built.toArray()
}

// The effective item-key function: the caller's key, or the index as a string. The index default
// reproduces the historical per-item scope key exactly, so index-keyed lists are byte-for-byte unchanged.
protected func lazyKeyOrIndex(key: ?((Int64) -> String)): (Int64) -> String {
    match (key) {
        case Some(k) => k
        case None => {index => "${index}"}
    }
}

/**
 * A vertically scrolling, virtualized grid: `data` arranged in `columns` equal columns and windowed by
 * row, so a large collection of uniform cells — a photo wall, a card grid — costs only a screenful.
 * It composes the proven pieces (each virtualized row is a `Grid` of up to `columns` cells over the
 * vertical `LazyColumn`), so it needs no separate horizontal scrolling. `itemHeight` is the fixed row
 * height in logical pixels; `spacing` is the gap between rows and `columnSpacing` the gap between cells.
 * Cells within a row are keyed by their position, so per-cell local state follows the slot — hoist
 * anything that must persist across data reorders.
 *
 * ```
 * LazyGrid(photos, 4, 160.0, spacing: 12.0, columnSpacing: 12.0) { photo => photoCell(photo) }
 * ```
 */
public func LazyGrid<T>(
    data: Array<T>,
    columns: Int64,
    itemHeight: Float32,
    spacing!: Float32 = 0.0,
    columnSpacing!: Float32 = 0.0,
    scroll!: ?State<Float32> = None,
    id!: ?String = None,
    item!: (T) -> Unit
): LazyColumn {
    LazyGrid<T>(data.size, columns, itemHeight, spacing: spacing, columnSpacing: columnSpacing, scroll: scroll, id: id,
        itemAt: {i => data[i]}, item: item)
}

/**
 * The copy-free form of `LazyGrid`: `count` items read on demand through `itemAt(index)` instead of a
 * materialized `Array<T>`, so a view holding an `ArrayList` (or any indexed source) feeds the grid
 * without a per-build `toArray()` copy. `itemAt` is only called for cells of the visible rows; it must
 * be cheap (an indexed read, not a fresh measurement) and pure — the grid does not retain it beyond
 * the build pass.
 *
 * ```
 * LazyGrid(photos.size, 4, 160.0, spacing: 12.0, itemAt: {i => photos[i]}) { photo => photoCell(photo) }
 * ```
 */
public func LazyGrid<T>(
    count: Int64,
    columns: Int64,
    itemHeight: Float32,
    spacing!: Float32 = 0.0,
    columnSpacing!: Float32 = 0.0,
    scroll!: ?State<Float32> = None,
    id!: ?String = None,
    itemAt!: (Int64) -> T,
    item!: (T) -> Unit
): LazyColumn {
    let cols = max(1, columns)
    let n = max(0, count)
    let rowCount = (n + cols - 1) / cols
    LazyColumn(rowCount, itemHeight, spacing: spacing, scroll: scroll, id: id) {
        rowIndex => Grid(cols) {
            var c = 0
            while (c < cols) {
                let dataIndex = rowIndex * cols + c
                if (dataIndex < n) {
                    item(itemAt(dataIndex))
                }
                c += 1
            }
        }.spacing(columnSpacing)
    }
}

/**
 * The flow variant of `LazyGrid` for grids embedded in an ancestor scroller: `data` arranged in
 * `columns` equal columns and windowed by row through `ClipLazyColumn`, so a large card grid in the
 * middle of a long page costs only a screenful while the page keeps its single scroll position.
 * Where `LazyGrid` measures to fill the available height and scrolls internally, this one reports
 * its full content height and scrolls with the ancestor — do not cap it with `.height(...)`, or the
 * windowing degenerates exactly like it does for `LazyGrid`.
 *
 * ```
 * ClipLazyGrid(members, 4, 190.0, spacing: 16.0, columnSpacing: 12.0) { m => memberCard(m) }
 * ```
 */
public func ClipLazyGrid<T>(
    data: Array<T>,
    columns: Int64,
    itemHeight: Float32,
    spacing!: Float32 = 0.0,
    columnSpacing!: Float32 = 0.0,
    id!: ?String = None,
    item!: (T) -> Unit
): ClipLazyColumn {
    ClipLazyGrid<T>(data.size, columns, itemHeight, spacing: spacing, columnSpacing: columnSpacing, id: id,
        itemAt: {i => data[i]}, item: item)
}

/**
 * The copy-free form of `ClipLazyGrid`: `count` items read on demand through `itemAt(index)`.
 * `itemAt` is only called for cells of the materialized rows; it must be cheap (an indexed read,
 * not a fresh measurement) and pure — the grid does not retain it beyond the build pass.
 */
public func ClipLazyGrid<T>(
    count: Int64,
    columns: Int64,
    itemHeight: Float32,
    spacing!: Float32 = 0.0,
    columnSpacing!: Float32 = 0.0,
    id!: ?String = None,
    itemAt!: (Int64) -> T,
    item!: (T) -> Unit
): ClipLazyColumn {
    let cols = max(1, columns)
    let n = max(0, count)
    let rowCount = (n + cols - 1) / cols
    ClipLazyColumn(rowCount, itemHeight, spacing: spacing, id: id) {
        rowIndex => Grid(cols) {
            var c = 0
            while (c < cols) {
                let dataIndex = rowIndex * cols + c
                if (dataIndex < n) {
                    item(itemAt(dataIndex))
                }
                c += 1
            }
        }.spacing(columnSpacing)
    }
}
