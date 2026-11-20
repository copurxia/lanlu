package cui.controls

import std.collection.ArrayList
import std.math.{cos, sin, sqrt}
import std.sort.sort
import lbase.{Color, Rect, Size}
import cui.base.{MouseButton, UiEvent}
import cui.core.{CursorShape, UiContext, Widget, claimHoverIfInside, emit}

private let WORD_CLOUD_TAU: Float64 = 6.283185307179586
private let WORD_CLOUD_PADDING: Float32 = 3.0
private let WORD_CLOUD_EDGE: Float32 = 8.0
private let WORD_CLOUD_STEPS: Int64 = 240
private let WORD_CLOUD_MAX_ITEMS: Int64 = 100
private let WORD_CLOUD_GRID_SIZE: Float32 = 12.0

/** A weighted entry rendered by [WordCloud]. */
public struct WordCloudItem {
    public let key: String
    public let text: String
    public let weight: Float64

    public init(key: String, text: String, weight: Float64) {
        this.key = key
        this.text = text
        this.weight = max(0.0, weight)
    }
}

private struct PlacedWord {
    let item: WordCloudItem
    let frame: Rect
    let pointSize: Float32
    let colorIndex: Int64

    init(item: WordCloudItem, frame: Rect, pointSize: Float32, colorIndex: Int64) {
        this.item = item
        this.frame = frame
        this.pointSize = pointSize
        this.colorIndex = colorIndex
    }
}

// A coarse occupancy bitmap makes collision checks independent of the number of words already
// placed. Marking whole cells is slightly conservative, which also gives the cloud even spacing.
private class WordCloudGrid {
    private let originX: Float32
    private let originY: Float32
    private let columns: Int64
    private let rows: Int64
    private let occupied: Array<Bool>

    init(bounds: Rect) {
        originX = bounds.x
        originY = bounds.y
        columns = max(1, Int64(bounds.w / WORD_CLOUD_GRID_SIZE) + 1)
        rows = max(1, Int64(bounds.h / WORD_CLOUD_GRID_SIZE) + 1)
        occupied = Array<Bool>(columns * rows, repeat: false)
    }

    func isFree(rect: Rect): Bool {
        let cells = cellRange(rect)
        for (row in cells[1]..=cells[3]) {
            for (column in cells[0]..=cells[2]) {
                if (occupied[row * columns + column]) {
                    return false
                }
            }
        }
        true
    }

    func occupy(rect: Rect): Unit {
        let cells = cellRange(rect)
        for (row in cells[1]..=cells[3]) {
            for (column in cells[0]..=cells[2]) {
                occupied[row * columns + column] = true
            }
        }
    }

    private func cellRange(rect: Rect): (Int64, Int64, Int64, Int64) {
        let left = clampCell(Int64((rect.x - originX) / WORD_CLOUD_GRID_SIZE), columns)
        let top = clampCell(Int64((rect.y - originY) / WORD_CLOUD_GRID_SIZE), rows)
        let right = clampCell(Int64((rect.right() - originX) / WORD_CLOUD_GRID_SIZE), columns)
        let bottom = clampCell(Int64((rect.bottom() - originY) / WORD_CLOUD_GRID_SIZE), rows)
        (left, top, right, bottom)
    }

    private func clampCell(value: Int64, count: Int64): Int64 {
        max(0, min(count - 1, value))
    }
}

/**
 * Packs weighted text from the centre outwards on an elliptical spiral. Words never overlap;
 * entries that cannot fit are omitted. Layout is deterministic, so unchanged data does not jump
 * between frames. Clicking a word invokes `onClick` with its original item.
 */
public class WordCloud <: Widget {
    private let items: Array<WordCloudItem>
    private let onClick: (WordCloudItem) -> Unit
    private let minPointSize: Float32
    private let maxPointSize: Float32
    private let preferredHeight: Float32
    private var frame = Rect.zero()
    private var placed = ArrayList<PlacedWord>()
    private var layoutWidth: Float32 = -1.0
    private var layoutHeight: Float32 = -1.0

    public init(
        items: Array<WordCloudItem>,
        minPointSize!: Float32 = 12.0,
        maxPointSize!: Float32 = 38.0,
        preferredHeight!: Float32 = 420.0,
        onClick!: (WordCloudItem) -> Unit = {_ => ()}
    ) {
        this.items = items
        this.minPointSize = max(1.0, minPointSize)
        this.maxPointSize = max(this.minPointSize, maxPointSize)
        this.preferredHeight = max(1.0, preferredHeight)
        this.onClick = onClick
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, min(available.h, preferredHeight))
    }

    public func layout(ctx: UiContext, rect: Rect): Unit {
        frame = rect
        if (layoutWidth != rect.w || layoutHeight != rect.h) {
            placed = packWords(ctx, rect)
            layoutWidth = rect.w
            layoutHeight = rect.h
        }
    }

    public func draw(ctx: UiContext): Unit {
        ctx.renderer.pushClip(frame)
        for (word in placed) {
            let color = wordColor(ctx, word.colorIndex)
            ctx.renderer.text(word.item.text, word.frame.x, word.frame.y, color, pointSize: word.pointSize)
        }
        ctx.renderer.popClip()
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        let hovered = wordAt(ctx.mouseX, ctx.mouseY)
        match (hovered) {
            case Some(word) => claimHoverIfInside(ctx, event, word.frame, word.item.key, CursorShape.Interactive)
            case None => ()
        }
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) => match (wordAt(x, y)) {
                case Some(word) =>
                    onClick(word.item);
                    true
                case None => false
            }
            case _ => false
        }
    }

    public func isFlexible(): Bool {
        false
    }

    /** Number of entries which fit in the latest layout, useful for diagnostics and tests. */
    public func visibleWordCount(): Int64 {
        placed.size
    }

    private func packWords(ctx: UiContext, bounds: Rect): ArrayList<PlacedWord> {
        let result = ArrayList<PlacedWord>()
        if (items.size == 0 || bounds.w <= WORD_CLOUD_EDGE * 2.0 || bounds.h <= WORD_CLOUD_EDGE * 2.0) {
            return result
        }
        let sorted = ArrayList<WordCloudItem>()
        for (item in items) {
            if (item.text.size > 0 && item.weight > 0.0) {
                sorted.add(item)
            }
        }
        sort(sorted, lessThan: {
            a, b => if (a.weight == b.weight) {
                a.key < b.key
            } else {
                a.weight > b.weight
            }
        })
        if (sorted.size == 0) {
            return result
        }
        let minWeight = sorted[sorted.size - 1].weight
        let maxWeight = sorted[0].weight
        let grid = WordCloudGrid(bounds)
        let itemCount = min(sorted.size, WORD_CLOUD_MAX_ITEMS)
        for (index in 0..itemCount) {
            let item = sorted[index]
            let pointSize = scaledPointSize(item.weight, minWeight, maxWeight)
            let textW = ctx.renderer.textWidth(item.text, pointSize: pointSize)
            let textH = ctx.renderer.textHeight(pointSize: pointSize)
            if (textW + WORD_CLOUD_EDGE * 2.0 > bounds.w || textH + WORD_CLOUD_EDGE * 2.0 > bounds.h) {
                continue
            }
            match (findPosition(bounds, textW, textH, index, grid)) {
                case Some(wordFrame) =>
                    result.add(PlacedWord(item, wordFrame, pointSize, index))
                    grid.occupy(wordFrame.inset(-WORD_CLOUD_PADDING))
                case None => ()
            }
        }
        result
    }

    private func scaledPointSize(weight: Float64, minWeight: Float64, maxWeight: Float64): Float32 {
        if (maxWeight <= minWeight) {
            return (minPointSize + maxPointSize) / 2.0
        }
        // Square-root scaling preserves visible differences without letting one outlier dominate.
        let normalized = sqrt((weight - minWeight) / (maxWeight - minWeight))
        minPointSize + (maxPointSize - minPointSize) * Float32(normalized)
    }

    private func findPosition(
        bounds: Rect,
        textW: Float32,
        textH: Float32,
        itemIndex: Int64,
        grid: WordCloudGrid
    ): ?Rect {
        // A key-derived phase separates similarly sized neighbours while preserving determinism.
        let phase = WORD_CLOUD_TAU * Float64(itemIndex % 11) / 11.0
        for (step in 0..WORD_CLOUD_STEPS) {
            let angle = phase + Float64(step) * 0.31
            let radius = Float32(step) * 1.5
            let x = bounds.centerX() + Float32(cos(angle)) * radius * 1.45 - textW / 2.0
            let y = bounds.centerY() + Float32(sin(angle)) * radius * 0.82 - textH / 2.0
            let candidate = Rect(x, y, textW, textH)
            if (!inside(bounds, candidate) || !grid.isFree(candidate.inset(-WORD_CLOUD_PADDING))) {
                continue
            }
            return Some(candidate)
        }
        None
    }

    private func wordAt(x: Float32, y: Float32): ?PlacedWord {
        for (word in placed) {
            if (word.frame.contains(x, y)) {
                return Some(word)
            }
        }
        None
    }
}

private func inside(bounds: Rect, candidate: Rect): Bool {
    candidate.x >= bounds.x + WORD_CLOUD_EDGE && candidate.y >= bounds.y + WORD_CLOUD_EDGE && candidate.right() <=
        bounds.right() - WORD_CLOUD_EDGE && candidate.bottom() <= bounds.bottom() - WORD_CLOUD_EDGE
}

private func wordColor(ctx: UiContext, index: Int64): Color {
    let palette = [
        ctx.theme.accent,
        Color.rgb(16, 148, 86),
        Color.rgb(37, 99, 235),
        Color.rgb(147, 51, 234),
        Color.rgb(190, 77, 15),
        Color.rgb(190, 24, 93)
    ]
    palette[index % palette.size]
}
