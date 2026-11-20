package cui.core

import std.collection.ArrayList
import lbase.{Rect, Size}
import cui.base.{FrameInfo, MouseButton, UiEvent}

// A reference-type counter so a build closure can tally invocations (captured vars are read-only).
class LazyBuildCounter {
    var count: Int64 = 0

    func bump(): Unit {
        count += 1
    }
}

// Records which row indices a build closure was asked to materialize.
class LazyBuiltIndices {
    var low: Int64 = Int64.Max
    var high: Int64 = Int64.Min
    var count: Int64 = 0

    func add(index: Int64): Unit {
        count += 1
        if (index < low) {
            low = index
        }
        if (index > high) {
            high = index
        }
    }
}

@Test
func lazyContentHeightSumsRowsAndGaps(): Unit {
    @Expect(lazyContentHeight(0, 100.0, 10.0), 0.0)
    @Expect(lazyContentHeight(1, 100.0, 10.0), 100.0)
    @Expect(lazyContentHeight(3, 100.0, 10.0), 320.0) // 3*110 - trailing 10
}

@Test
func lazyVisibleRangeWindowsAroundScrollWithOverscan(): Unit {
    // Top of a long list: rows 0..(500/100) widened by 2 of overscan, floored at 0.
    let (first0, last0) = lazyVisibleRange(0.0, 500.0, 100.0, 0.0, 1000, 2)
    @Expect(first0, 0)
    @Expect(last0, 7)
    // Scrolled to row 100: window recentres, overscan on both sides.
    let (first1, last1) = lazyVisibleRange(10000.0, 500.0, 100.0, 0.0, 1000, 2)
    @Expect(first1, 98)
    @Expect(last1, 107)
}

@Test
func lazyVisibleRangeClampsToBounds(): Unit {
    // Scrolled past the end, `last` clamps to the final index rather than running off.
    let (_, last) = lazyVisibleRange(99900.0, 500.0, 100.0, 0.0, 1000, 2)
    @Expect(last, 999)
    // Empty list yields an empty range (first > last), so nothing is built.
    let (firstEmpty, lastEmpty) = lazyVisibleRange(0.0, 500.0, 100.0, 0.0, 0, 2)
    @Expect(firstEmpty > lastEmpty, true)
}

@Test
func lazyColumnMaterializesOnlyAScreenful(): Unit {
    let counter = LazyBuildCounter()
    // A thousand rows, but only the default-viewport window (720px / 100px + overscan) is built.
    let column = LazyColumn(1000, 100.0, id: "test.lazy") {
        _ =>
            counter.bump()
            emit(Spacer())
    }
    @Expect(counter.count > 0, true)
    @Expect(counter.count < 20, true)
    // Reference the widget so its construction is not optimised away.
    @Expect(column.isFlexible(), true)
}

@Test
func lazyColumnBuildsWindowAroundExternalScroll(): Unit {
    let built = LazyBuiltIndices()
    // Scroll near row 500 (500 * 100 px). The materialized window should centre there, not at 0.
    let scroll = State<Float32>(50000.0)
    let column = LazyColumn(1000, 100.0, scroll: scroll, id: "test.lazy.scroll") {
        index =>
            built.add(index)
            emit(Spacer())
    }
    @Expect(built.low >= 490, true)
    @Expect(built.low <= 500, true)
    @Expect(built.high >= 505, true)
    @Expect(built.high < 520, true)
    @Expect(column.isFlexible(), true)
}

@Test
func lazyColumnWheelFallsThroughAtVerticalEdges(): Unit {
    let ctx = testContext()
    let scroll = State<Float32>(0.0)
    let column = LazyColumn(100, 50.0, scroll: scroll, id: "test.lazy.edge") {
        _ => emit(Spacer())
    }
    column.layout(ctx, Rect(0.0, 0.0, 300.0, 400.0))

    // At the top, an upward wheel cannot move this viewport and is left for an outer scroller.
    @Expect(!column.handle(ctx, UiEvent.MouseWheel(0.0, 1.0, 150.0, 200.0)))
    @Expect(scroll.value, Float32(0.0))

    @Expect(column.handle(ctx, UiEvent.MouseWheel(0.0, -1.0, 150.0, 200.0)))
    ctx.frame = FrameInfo(UInt64(200), UInt64(16))
    column.layout(ctx, Rect(0.0, 0.0, 300.0, 400.0))
    @Expect(scroll.value, Float32(72.0))

    // content 5000 - viewport 400 = max offset 4600.
    scroll.value = 4600.0
    @Expect(!column.handle(ctx, UiEvent.MouseWheel(0.0, -1.0, 150.0, 200.0)))
    @Expect(scroll.value, Float32(4600.0))
}

// The data-driven `LazyColumn.of` must virtualize (build only a screenful) AND hand the row builder
// the DATA elements at the visible indices — not the raw indices — so a list over `Array<T>` needs no
// manual count or data[i] lookup.
@Test
func lazyColumnOfBuildsRowsFromData(): Unit {
    // data[i] == i * 10, so a built value reveals which index it came from.
    let data = Array<Int64>(1000, {i => i * 10})
    let built = LazyBuiltIndices()
    let scroll = State<Float32>(50000.0) // near row 500
    let column = LazyColumn.of<Int64>(data, 100.0, scroll: scroll, key: {v => "v${v}"}, id: "test.of") {
        value =>
            built.add(value)
            emit(Spacer())
    }
    // Only a screenful materialized, not all 1000.
    @Expect(built.count > 0, true)
    @Expect(built.count < 20, true)
    // The builder received data VALUES near row 500 (value == index*10 ~ 4980..5090), proving the
    // index->data mapping, not raw indices (~498..509).
    @Expect(built.low >= 4900, true)
    @Expect(built.high <= 5200, true)
    @Expect(column.isFlexible(), true)
}

// LazyGrid windows by row (data / columns), so a large collection builds only the cells of the
// visible rows, and each built cell is the data element at its grid position.
@Test
func lazyGridBuildsVisibleCellsFromData(): Unit {
    let data = Array<Int64>(1000, {i => i}) // cell value == data index
    let built = LazyBuiltIndices()
    let scroll = State<Float32>(10000.0) // near row 100 of 250 (1000 items / 4 columns)
    let grid = LazyGrid<Int64>(data, 4, 100.0, scroll: scroll, id: "test.grid") {
        value =>
            built.add(value)
            emit(Spacer())
    }
    // Only a screenful of rows' cells built, not all 1000.
    @Expect(built.count > 0, true)
    @Expect(built.count < 60, true)
    // Visible rows ~98..109 × 4 columns → data indices ~392..439.
    @Expect(built.low >= 350, true)
    @Expect(built.high <= 480, true)
    @Expect(grid.isFlexible(), true) // LazyGrid returns the underlying LazyColumn
}

// The (count, itemAt) form windows identically to the Array form but reads data through the getter on
// demand — an ArrayList-backed source feeds the grid with no toArray() copy, and the getter is only
// consulted for cells of the visible rows.
@Test
func lazyGridCountItemAtFormReadsVisibleCellsThroughGetter(): Unit {
    let data = ArrayList<Int64>()
    for (i in 0..1000) {
        data.add(i * 2) // cell value == data index * 2
    }
    let built = LazyBuiltIndices()
    let getterCalls = LazyBuildCounter()
    let scroll = State<Float32>(10000.0) // near row 100 of 250 (1000 items / 4 columns)
    let grid = LazyGrid<Int64>(
        data.size,
        4,
        100.0,
        scroll: scroll,
        id: "test.grid.getter",
        itemAt: {
            i =>
                getterCalls.bump()
                data[i]
        }
    ) {
        value =>
            built.add(value)
            emit(Spacer())
    }
    // Only a screenful of rows' cells built and read through the getter, not all 1000.
    @Expect(built.count > 0, true)
    @Expect(built.count < 60, true)
    @Expect(getterCalls.count == built.count, true)
    // Visible rows ~98..109 × 4 columns → data indices ~392..439 → values ~784..878.
    @Expect(built.low >= 700, true)
    @Expect(built.high <= 960, true)
    @Expect(grid.isFlexible(), true)
}

// ── ClipLazyColumn / ClipLazyGrid: windowing against an ancestor scroller's clip ──

// The flow column hugs its content like a VStack (full content height, not flexible), so it can
// sit inside a ScrollView without capping — the windowing must be invisible to layout.
@Test
func clipLazyColumnMeasuresFullContentHeight(): Unit {
    let ctx = testContext()
    let column = ClipLazyColumn(100, 50.0, spacing: 10.0, id: "clip.measure") {
        _ => emit(Spacer())
    }
    let size = column.measure(ctx, Size(300.0, 400.0))
    @Expect(size.w, Float32(300.0))
    @Expect(size.h, Float32(100 * 60 - 10))
    @Expect(column.isFlexible(), false)
}

// Before the first draw the ancestor clip is unknown, so only a default screenful from the top
// is materialized — the first frame of a huge grid stays cheap.
@Test
func clipLazyColumnBuildsScreenfulBeforeFirstDraw(): Unit {
    let counter = LazyBuildCounter()
    let column = ClipLazyColumn(1000, 100.0, id: "clip.first") {
        _ =>
            counter.bump()
            emit(Spacer())
    }
    // 720px default viewport / 100px rows + overscan, nowhere near 1000.
    @Expect(counter.count > 0, true)
    @Expect(counter.count < 20, true)
}

// The visible window follows the ancestor clip across rebuilds: after a frame laid out at a
// scrolled position and drawn under the ancestor's clip, the next build materializes the rows
// under that clip (± overscan), not the top of the list.
@Test
func clipLazyColumnWindowsToAncestorClipAcrossRebuilds(): Unit {
    let ctx = testContext()
    let store = StateStore()
    ctx.renderer.clearClipStack()
    // Frame 1: initial build (top screenful), laid out unscrolled, drawn under a 400px clip.
    let first = buildRoot(
        {
            => ClipLazyColumn(1000, 100.0, id: "clip.win") {
                _ => emit(Spacer())
            }
        },
        store
    )
    first.layout(ctx, Rect(0.0, 0.0, 300.0, 100000.0))
    ctx.renderer.pushClip(Rect(0.0, 0.0, 300.0, 400.0))
    first.draw(ctx)
    ctx.renderer.popClip()
    // Frame 2: the ancestor scrolled 50000px, so the same content sits at y = -50000; the draw
    // still happens under the same viewport clip. This frame's build still uses frame 1's
    // snapshot — the one-frame settle the overscan covers.
    let second = buildRoot(
        {
            => ClipLazyColumn(1000, 100.0, id: "clip.win") {
                _ => emit(Spacer())
            }
        },
        store
    )
    second.layout(ctx, Rect(0.0, -50000.0, 300.0, 100000.0))
    ctx.renderer.pushClip(Rect(0.0, 0.0, 300.0, 400.0))
    second.draw(ctx)
    ctx.renderer.popClip()
    // Frame 3: the window recentres on row 500 (50000/100), widened by 2 rows of overscan.
    let built = LazyBuiltIndices()
    let third = buildRoot(
        {
            => ClipLazyColumn(1000, 100.0, id: "clip.win") {
                index =>
                    built.add(index)
                    emit(Spacer())
            }
        },
        store
    )
    @Expect(built.low, Int64(498))
    @Expect(built.high, Int64(506))
    @Expect(built.count, Int64(9))
    // Rows are positioned at their absolute content offsets, not re-based to the window top.
    third.layout(ctx, Rect(0.0, -50000.0, 300.0, 100000.0))
}

// Drawn with no clip in effect (headless root drawing, tests), the column has nothing to window
// against and degrades to building every row — same result as a plain VStack.
@Test
func clipLazyColumnBuildsEverythingWhenUnclipped(): Unit {
    let ctx = testContext()
    let store = StateStore()
    ctx.renderer.clearClipStack()
    let first = buildRoot(
        {
            => ClipLazyColumn(1000, 100.0, id: "clip.unclipped") {
                _ => emit(Spacer())
            }
        },
        store
    )
    first.layout(ctx, Rect(0.0, 0.0, 300.0, 100000.0))
    first.draw(ctx)
    let counter = LazyBuildCounter()
    let _ = buildRoot(
        {
            => ClipLazyColumn(1000, 100.0, id: "clip.unclipped") {
                _ =>
                    counter.bump()
                    emit(Spacer())
            }
        },
        store
    )
    @Expect(counter.count, Int64(1000))
}

// The column scrolls nothing itself: the wheel is left for the ancestor scroller (rows here are
// plain Spacers, which never consume it).
@Test
func clipLazyColumnLeavesWheelToAncestor(): Unit {
    let ctx = testContext()
    let column = ClipLazyColumn(100, 50.0, id: "clip.wheel") {
        _ => emit(Spacer())
    }
    column.layout(ctx, Rect(0.0, 0.0, 300.0, 100000.0))
    @Expect(!column.handle(ctx, UiEvent.MouseWheel(0.0, -1.0, 150.0, 200.0)))
    // Outside its frame, pointer events are not routed to the materialized rows either.
    @Expect(!column.handle(ctx, UiEvent.MouseDown(MouseButton.Left, 150.0, 200000.0)))
}

// ClipLazyGrid windows by row like ClipLazyColumn (data / columns), reporting the full grid height
// while building only the cells of the materialized rows through the getter.
@Test
func clipLazyGridBuildsScreenfulCellsAndMeasuresFullHeight(): Unit {
    let ctx = testContext()
    let data = ArrayList<Int64>()
    for (i in 0..1000) {
        data.add(i * 2) // cell value == data index * 2
    }
    let built = LazyBuiltIndices()
    let getterCalls = LazyBuildCounter()
    let grid = ClipLazyGrid<Int64>(
        data.size,
        4,
        100.0,
        spacing: 10.0,
        id: "clip.grid",
        itemAt: {
            i =>
                getterCalls.bump()
                data[i]
        }
    ) {
        value =>
            built.add(value)
            emit(Spacer())
    }
    // First frame: only the default-viewport rows' cells built and read through the getter.
    @Expect(built.count > 0, true)
    @Expect(built.count < 60, true)
    @Expect(getterCalls.count == built.count, true)
    // 250 rows of 110px - trailing spacing.
    @Expect(grid.measure(ctx, Size(300.0, 400.0)).h, Float32(250 * 110 - 10))
    @Expect(grid.isFlexible(), false)
}
