package cui.core

import std.collection.{ArrayList, HashMap}
import lbase.{Color, Rect, Size}
import cui.base.{FontSizes, Key, MouseButton, SurfaceStyle, UiEvent}

private let LABEL_LINE_GAP: Float32 = 2.0
private let LABEL_ELLIPSIS = "…"

// ===== 换行结果全局缓存（G3，perf-plan R9.2）=====
// Label 每帧重建，实例级 cachedLines 每帧失效 ⇒ 多行 Label 每帧重跑 wrapText
// （replace+split+toRuneArray+逐行测量）。缓存键 = (text, maxWidth, pointSize, lineLimit)，
// 覆盖文本/可用宽度/字号（含 fontScale/超采样后的 ps）/行数上限四个失效维度；字体运行期
// 不变，与 lgpu measureCache、renderer metricsCache 的键口径一致。值（行数组与最宽行宽）
// 跨帧只读共享——Label 只遍历行、不修改数组。两代淘汰与 EllipsizeCache 同构。
private const WRAPPED_LINES_CACHE_CAP: Int64 = 1024

private struct WrappedLinesKey <: Hashable & Equatable<WrappedLinesKey> {
    let text: String
    let maxWidth: Float32
    let pointSize: Float32
    let lineLimit: Int64

    init(text: String, maxWidth: Float32, pointSize: Float32, lineLimit: Int64) {
        this.text = text
        this.maxWidth = maxWidth
        this.pointSize = pointSize
        this.lineLimit = lineLimit
    }

    // 以文本散列为主：同文本不同宽度/字号/上限的少量碰撞由 == 区分。
    public func hashCode(): Int64 {
        text.hashCode()
    }

    public operator func ==(rhs: WrappedLinesKey): Bool {
        text == rhs.text && maxWidth == rhs.maxWidth && pointSize == rhs.pointSize &&
            lineLimit == rhs.lineLimit
    }

    public operator func !=(rhs: WrappedLinesKey): Bool {
        !(this == rhs)
    }
}

private class WrappedLinesEntry {
    let lines: Array<String>
    let widest: Float32

    init(lines: Array<String>, widest: Float32) {
        this.lines = lines
        this.widest = widest
    }
}

private class WrappedLinesGeneration {
    private let capacity: Int64
    private var active = HashMap<WrappedLinesKey, WrappedLinesEntry>()
    private var retired = HashMap<WrappedLinesKey, WrappedLinesEntry>()

    init(capacity: Int64) {
        this.capacity = if (capacity < 1) {
            1
        } else {
            capacity
        }
    }

    func get(key: WrappedLinesKey): ?WrappedLinesEntry {
        match (active.get(key)) {
            case Some(entry) => return Some(entry)
            case None => ()
        }
        match (retired.get(key)) {
            case Some(entry) =>
                put(key, entry)
                Some(entry)
            case None => None
        }
    }

    func put(key: WrappedLinesKey, entry: WrappedLinesEntry): Unit {
        if (active.size >= capacity) {
            let recycled = retired
            recycled.clear()
            retired = active
            active = recycled
        }
        active[key] = entry
    }
}

private class WrappedLinesCache {
    private let capacity: Int64
    private var byPointSize = HashMap<Int64, WrappedLinesGeneration>()

    init(capacity: Int64) {
        this.capacity = capacity
    }

    func get(ps: Float32, key: WrappedLinesKey): ?WrappedLinesEntry {
        let sizeKey = Int64(ps * Float32(4.0))
        match (byPointSize.get(sizeKey)) {
            case Some(generation) => return generation.get(key)
            case None => return None
        }
    }

    func put(ps: Float32, key: WrappedLinesKey, entry: WrappedLinesEntry): Unit {
        let sizeKey = Int64(ps * Float32(4.0))
        let generation = match (byPointSize.get(sizeKey)) {
            case Some(existing) => existing
            case None =>
                let created = WrappedLinesGeneration(capacity)
                byPointSize[sizeKey] = created
                created
        }
        generation.put(key, entry)
    }
}

// UI 仅单线程访问，与框架其余缓存一致无需加锁。
private let wrappedLinesCache = WrappedLinesCache(WRAPPED_LINES_CACHE_CAP)

/// 文字墨迹中心到"行盒顶"的距离占字号的比例。
///
/// 排版用的 textHeight（= 1.35×字号）是行盒高度，不是墨迹框；直接拿它做
/// `y = centerY − textHeight/2` 会把文字画高约 (1.35/2 − 0.475)×字号 ≈ 0.2em。
/// 真机像素实测（HarmonyOS Sans @1.9，标题栏 15fp）：墨迹中心比 56vp 栏中心高 3vp，
/// 反推墨迹中心 ≈ 盒顶 + 0.475×字号。所有"垂直居中"的文字都应改用这个偏移。
public let TEXT_INK_TOP_RATIO: Float32 = 0.475

/// 垂直居中时文字应画的 y（墨迹中心落在 centerY 上）。
public func inkTop(centerY: Float32, pointSize: Float32): Float32 {
    centerY - pointSize * TEXT_INK_TOP_RATIO
}

public class Label <: Widget {
    private let text: String
    private var isMuted: Bool
    private var alignment: TextAlign
    private var textColor: ?Color
    private var pointSize: Length
    private var lineLimit: Int64 = 1
    // 密集文本块（卡片/头部多行小字）去掉 CUI_SMALL_H 行高下限，行距由字号决定。
    private var tightHeight = false
    private var frame = Rect.zero()
    // Wrapping runs several renderer measurements; measure and draw reuse the result
    // for the same width and point size instead of re-breaking the text each pass.
    private var cachedLines: ?Array<String> = None
    private var cachedLinesWidth: Float32 = -1.0
    private var cachedLinesPointSize: Float32 = -1.0
    // The widest wrapped line, cached with the lines it derives from so a warm multi-line measure
    // re-measures nothing instead of re-scanning every line each measure pass.
    private var cachedLinesWidest: Float32 = 0.0
    private var cachedTextWidth: Float32 = -1.0
    private var cachedTextWidthPointSize: Float32 = -1.0

    public init(
        text: String,
        muted!: Bool = false,
        align!: TextAlign = TextAlign.Leading,
        color!: ?Color = None,
        fontSize!: Length = Length(FontSizes.BODY, LengthUnit.Fp)
    ) {
        this.text = text
        this.isMuted = muted
        this.alignment = align
        this.textColor = color
        this.pointSize = fontSize
        emit(this)
    }

    /** Uses the theme's secondary text color. */
    public func muted(): Label {
        isMuted = true
        this
    }

    /** Controls whether the theme's secondary text color is used. */
    public func muted(value: Bool): Label {
        isMuted = value
        this
    }

    /** Sets horizontal text alignment inside the assigned frame. */
    public func textAlign(value: TextAlign): Label {
        alignment = value
        this
    }

    /** Overrides the theme-derived text color. */
    public func foregroundColor(value: Color): Label {
        textColor = Some(value)
        this
    }

    /** Sets the font size, e.g. `.fontSize(15.fp)`. */
    public func fontSize(value: Length): Label {
        pointSize = value
        this
    }

    /** Sets the font size in font pixels. */
    public func fontSize(value: Float32): Label {
        fontSize(Length(value, LengthUnit.Fp))
    }

    /**
     * Allows the text to wrap onto up to `value` lines. The final line is ellipsized
     * when text remains. Throws `IllegalArgumentException` when `value` is not positive.
     */
    public func maxLines(value: Int64): Label {
        if (value <= 0) {
            throw IllegalArgumentException("Label maxLines must be greater than zero")
        }
        lineLimit = value
        this
    }

    /** Lets the text wrap onto as many lines as it needs. */
    public func wrap(): Label {
        lineLimit = Int64.Max
        this
    }

    /** Drops the CUI_SMALL_H minimum row height; for dense multi-line text blocks. */
    public func tight(): Label {
        tightHeight = true
        this
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let ps = resolvedPointSize(ctx)
        let lineHeight = ctx.renderer.textHeight(pointSize: ps)
        let minH: Float32 = if (tightHeight) {
            0.0
        } else {
            CUI_SMALL_H
        }
        if (lineLimit == 1) {
            return Size(min(available.w, singleLineWidth(ctx, ps)), max(minH, lineHeight + 6.0))
        }
        let lines = linesFor(ctx, available.w, ps)
        let count = max(1, lines.size)
        let textBlock = Float32(count) * lineHeight + Float32(count - 1) * LABEL_LINE_GAP
        // widest was measured when the lines were wrapped and cached; a warm pass reuses it.
        Size(min(available.w, cachedLinesWidest), max(minH, textBlock + 6.0))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let ps = resolvedPointSize(ctx)
        let color = drawColor(ctx)
        let lineHeight = ctx.renderer.textHeight(pointSize: ps)
        if (lineLimit == 1) {
            // Reuse the cached full-text width for the fit test: ellipsize (a binary search) runs
            // only when the text overflows, so a fitting single-line label re-measures nothing.
            let fitted = if (singleLineWidth(ctx, ps) <= frame.w) {
                text
            } else {
                ellipsize(ctx, text, frame.w, ps)
            }
            // 墨迹居中（不是行盒居中）：见 TEXT_INK_TOP_RATIO
            ctx.renderer.text(fitted, lineX(ctx, fitted, ps), inkTop(frame.centerY(), ps), color, pointSize: ps)
            return
        }
        let lines = linesFor(ctx, frame.w, ps)
        let textBlock = Float32(lines.size) * lineHeight + Float32(max(0, lines.size - 1)) * LABEL_LINE_GAP
        // 多行块同样按**墨迹**居中：块高按行盒算，但首行墨迹在行盒里偏上 0.2em，
        // 所以整块要下移 0.2×字号才让墨迹视觉居中（真机像素实测，见 TEXT_INK_TOP_RATIO）。
        var y = frame.centerY() - textBlock / 2.0 + ps * (lineHeight / 2.0 / ps - TEXT_INK_TOP_RATIO)
        for (line in lines) {
            ctx.renderer.text(line, lineX(ctx, line, ps), y, color, pointSize: ps)
            y += lineHeight + LABEL_LINE_GAP
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }

    private func drawColor(ctx: UiContext): Color {
        match (textColor) {
            case Some(value) => value
            case None =>
                if (isMuted) {
                    ctx.theme.mutedText
                } else {
                    ctx.theme.text
                }
        }
    }

    private func resolvedPointSize(ctx: UiContext): Float32 {
        max(1.0, ctx.resolve(pointSize))
    }

    // Exact float comparison is deliberate in both caches: the keys are reused values,
    // not computed approximations, so equality means "same inputs as last time".
    private func singleLineWidth(ctx: UiContext, ps: Float32): Float32 {
        if (cachedTextWidthPointSize != ps) {
            cachedTextWidth = ctx.renderer.textWidth(text, pointSize: ps)
            cachedTextWidthPointSize = ps
        }
        cachedTextWidth
    }

    private func linesFor(ctx: UiContext, width: Float32, ps: Float32): Array<String> {
        match (cachedLines) {
            case Some(lines) where cachedLinesWidth == width && cachedLinesPointSize == ps => lines
            case _ =>
                // G3：实例缓存未命中（每帧重建必未命中）先查全局缓存；命中即跳过
                // wrapText 与逐行测量。键含 text/width/ps/lineLimit 四个失效维度。
                let key = WrappedLinesKey(text, width, ps, lineLimit)
                match (wrappedLinesCache.get(ps, key)) {
                    case Some(entry) =>
                        cachedLines = Some(entry.lines)
                        cachedLinesWidth = width
                        cachedLinesPointSize = ps
                        cachedLinesWidest = entry.widest
                        return entry.lines
                    case None => ()
                }
                let lines = wrapText(ctx, text, width, ps, lineLimit)
                var widest: Float32 = 0.0
                for (line in lines) {
                    widest = max(widest, ctx.renderer.textWidth(line, pointSize: ps))
                }
                cachedLines = Some(lines)
                cachedLinesWidth = width
                cachedLinesPointSize = ps
                cachedLinesWidest = widest
                wrappedLinesCache.put(ps, key, WrappedLinesEntry(lines, widest))
                lines
        }
    }

    private func lineX(ctx: UiContext, line: String, ps: Float32): Float32 {
        // Leading (the default) does not need the line width, so the common case skips the measure.
        match (alignment) {
            case TextAlign.Leading => frame.x
            case TextAlign.Center =>
                let lineW = ctx.renderer.textWidth(line, pointSize: ps)
                frame.x + max(0.0, frame.w - lineW) / 2.0
            case TextAlign.Trailing =>
                let lineW = ctx.renderer.textWidth(line, pointSize: ps)
                frame.right() - lineW
        }
    }
}

/*
 * Text fitting shared by single-line ellipsis and multi-line wrapping. Prefix widths are
 * found with binary search over the rune array, so the cost per line is O(log n) renderer
 * measurements instead of one per character.
 */

// ellipsize 记忆化每桶（每个字号档）的容量，与 TextMetricsCache 的每桶 1024 一致。
private let ELLIPSIZE_CACHE_CAP_PER_SIZE: Int64 = 1024

/*
 * ellipsize 记忆化的缓存键，包含结果的全部输入：
 * - text / maxWidth：二分截断的原文与可用宽度；
 * - fullWidth：当前渲染状态下 text 的实测整宽。渲染缩放（setScale/超采样/DPI）与字体
 *   后端只经 textWidth 影响截断结果，而任何这类变化必然改变同一文本的整宽——旧键随
 *   渲染状态变化自然失配重算，绝不会按旧状态返回截断串。
 * 字号不进键：外层按字号分桶（与 TextMetricsCache 同构），fontScale/displayScale 已由
 * 调用方经 ctx.resolve 折入 ps，ps 再决定分桶。
 */
private struct EllipsizeKey <: Hashable & Equatable<EllipsizeKey> {
    let text: String
    let maxWidth: Float32
    let fullWidth: Float32

    init(text: String, maxWidth: Float32, fullWidth: Float32) {
        this.text = text
        this.maxWidth = maxWidth
        this.fullWidth = fullWidth
    }

    // 以文本散列：同文本不同宽度/整宽的少量碰撞由 == 区分。
    public func hashCode(): Int64 {
        text.hashCode()
    }

    public operator func ==(rhs: EllipsizeKey): Bool {
        text == rhs.text && maxWidth == rhs.maxWidth && fullWidth == rhs.fullWidth
    }

    public operator func !=(rhs: EllipsizeKey): Bool {
        !(this == rhs)
    }
}

// 每个字号档一个两代淘汰缓存：active 满时整体丢弃 retired 并轮换，命中 retired 的条目
// 提升回 active，热条目熬过轮换。结构与 TextMetricsCache 的 MetricsGeneration 一致。
private class EllipsizeGeneration {
    private let capacity: Int64
    private var active = HashMap<EllipsizeKey, String>()
    private var retired = HashMap<EllipsizeKey, String>()

    init(capacity: Int64) {
        this.capacity = if (capacity < 1) {
            1
        } else {
            capacity
        }
    }

    func get(key: EllipsizeKey): ?String {
        match (active.get(key)) {
            case Some(value) => return Some(value)
            case None => ()
        }
        match (retired.get(key)) {
            case Some(value) =>
                put(key, value)
                Some(value)
            case None => None
        }
    }

    func put(key: EllipsizeKey, value: String): Unit {
        if (active.size >= capacity) {
            let recycled = retired
            recycled.clear()
            retired = active
            active = recycled
        }
        active[key] = value
    }
}

private class EllipsizeCache {
    private let capacityPerSize: Int64
    private var bySize = HashMap<Int64, EllipsizeGeneration>()

    init(capacityPerSize: Int64) {
        this.capacityPerSize = capacityPerSize
    }

    func get(sizeKey: Int64, key: EllipsizeKey): ?String {
        match (bySize.get(sizeKey)) {
            case Some(generation) => generation.get(key)
            case None => None
        }
    }

    func put(sizeKey: Int64, key: EllipsizeKey, value: String): Unit {
        let generation = match (bySize.get(sizeKey)) {
            case Some(existing) => existing
            case None =>
                let created = EllipsizeGeneration(capacityPerSize)
                bySize[sizeKey] = created
                created
        }
        generation.put(key, value)
    }
}

// 超长文本每帧重二分（约 log2(n) 次测量 + 每次一个候选子串分配）是帧成本热点；
// UI 仅单线程访问，与框架其余缓存一致无需加锁。
private let ellipsizeCache = EllipsizeCache(ELLIPSIZE_CACHE_CAP_PER_SIZE)



/** Returns `text` unchanged when it fits, otherwise the widest `prefix + …` that fits. */
protected func ellipsize(ctx: UiContext, text: String, maxWidth: Float32, ps: Float32): String {
    let fullWidth = ctx.renderer.textWidth(text, pointSize: ps)
    if (fullWidth <= maxWidth) {
        return text
    }
    // 只有溢出才查缓存：命中即省去二分的多次测量与候选子串分配，代价仅是上面这一次
    // 整宽测量（与原实现的第一步相同）。分桶键与原 TextMetricsCache 同为 1/256pt 量化。
    let sizeKey = Int64(ps * 256.0)
    let key = EllipsizeKey(text, maxWidth, fullWidth)
    match (ellipsizeCache.get(sizeKey, key)) {
        case Some(fitted) => return fitted
        case None => ()
    }
    let fitted = ellipsizeOverflow(ctx, text, maxWidth, ps)
    ellipsizeCache.put(sizeKey, key, fitted)
    fitted
}

// 溢出路径的实际截断（缓存未命中时调用）：与记忆化前 ellipsize 的后半段逐行一致，
// 仅整宽测量已由调用方做过。
private func ellipsizeOverflow(ctx: UiContext, text: String, maxWidth: Float32, ps: Float32): String {
    if (ctx.renderer.textWidth(LABEL_ELLIPSIS, pointSize: ps) > maxWidth) {
        return ""
    }
    let runes = text.toRuneArray()
    var low: Int64 = 0
    var high = runes.size - 1
    while (low < high) {
        let mid = (low + high + 1) / 2
        let candidate = runeSlice(runes, 0, mid) + LABEL_ELLIPSIS
        if (ctx.renderer.textWidth(candidate, pointSize: ps) <= maxWidth) {
            low = mid
        } else {
            high = mid - 1
        }
    }
    runeSlice(runes, 0, low) + LABEL_ELLIPSIS
}

/**
 * Breaks `text` into at most `maxLines` display lines that fit `maxWidth`, preferring
 * space boundaries and falling back to per-rune breaks (which suits CJK text). The last
 * line is ellipsized when text remains.
 */
protected func wrapText(
    ctx: UiContext,
    text: String,
    maxWidth: Float32,
    ps: Float32,
    maxLines: Int64
): Array<String> {
    let lines = ArrayList<String>()
    let paragraphs = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    for (paragraph in paragraphs) {
        appendWrappedParagraph(ctx, lines, paragraph, maxWidth, ps, maxLines)
        if (lines.size >= maxLines) {
            break
        }
    }
    if (lines.isEmpty()) {
        lines.add("")
    }
    lines.toArray()
}

private func appendWrappedParagraph(
    ctx: UiContext,
    lines: ArrayList<String>,
    paragraph: String,
    maxWidth: Float32,
    ps: Float32,
    maxLines: Int64
): Unit {
    let runes = paragraph.toRuneArray()
    if (runes.isEmpty()) {
        lines.add("")
        return
    }
    var start: Int64 = 0
    while (start < runes.size && lines.size < maxLines) {
        if (lines.size == maxLines - 1) {
            lines.add(ellipsize(ctx, runeSlice(runes, start, runes.size), maxWidth, ps))
            return
        }
        var take = maxFittingRunes(ctx, runes, start, maxWidth, ps)
        if (start + take < runes.size && runes[start + take] != r' ') {
            var back = take - 1
            while (back > 0) {
                if (runes[start + back] == r' ') {
                    take = back + 1
                    break
                }
                back -= 1
            }
        }
        var lineEnd = start + take
        while (lineEnd > start && runes[lineEnd - 1] == r' ') {
            lineEnd -= 1
        }
        lines.add(runeSlice(runes, start, lineEnd))
        start += take
        while (start < runes.size && runes[start] == r' ') {
            start += 1
        }
    }
}

/** The largest rune count from `start` whose text fits `maxWidth`; at least one. */
private func maxFittingRunes(
    ctx: UiContext,
    runes: Array<Rune>,
    start: Int64,
    maxWidth: Float32,
    ps: Float32
): Int64 {
    let remaining = runes.size - start
    if (ctx.renderer.textWidth(runeSlice(runes, start, runes.size), pointSize: ps) <= maxWidth) {
        return remaining
    }
    var low: Int64 = 1
    var high = remaining - 1
    while (low < high) {
        let mid = (low + high + 1) / 2
        if (ctx.renderer.textWidth(runeSlice(runes, start, start + mid), pointSize: ps) <= maxWidth) {
            low = mid
        } else {
            high = mid - 1
        }
    }
    max(1, low)
}

private func runeSlice(runes: Array<Rune>, start: Int64, end: Int64): String {
    let builder = StringBuilder()
    var i = start
    while (i < end) {
        builder.append(runes[i])
        i += 1
    }
    builder.toString()
}

public class Spacer <: Widget {
    public init() {
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(_: UiContext, _: Rect): Unit {}

    public func draw(_: UiContext): Unit {}

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }

    public func isFlexible(): Bool {
        true
    }
}

public class Button <: Widget {
    private let title: String
    private let onClick: () -> Unit
    private var buttonRole: ButtonRole
    private var customStyle: ?SurfaceStyle
    private var pointSize: Length
    private var controlId: String
    private var frame = Rect.zero()

    public init(
        title: String,
        onClick: () -> Unit,
        role!: ButtonRole = ButtonRole.Normal,
        style!: ?SurfaceStyle = None,
        fontSize!: Length = Length(FontSizes.CONTROL, LengthUnit.Fp)
    ) {
        this.title = title
        this.onClick = onClick
        this.buttonRole = role
        this.customStyle = style
        this.pointSize = fontSize
        // Interaction identity follows build position, not display text, so live locale changes
        // do not drop focus or press state.
        this.controlId = focusableControlIdentity("Button")
        emit(this)
    }

    /**
     * Sets an explicit focus and press identity. Defaults are already unique per build;
     * set one when identity must survive tree reshapes (for example a button that moves
     * between containers). Throws `IllegalArgumentException` when `value` is empty.
     */
    public func key(value: String): Button {
        requireControlId(value, "Button")
        reregisterFocusable(controlId, value)
        controlId = value
        this
    }

    /** Applies semantic button coloring. */
    public func role(value: ButtonRole): Button {
        buttonRole = value
        this
    }

    /** Overrides the theme-derived button surface. */
    public func style(value: SurfaceStyle): Button {
        customStyle = Some(value)
        this
    }

    /** Sets the label font size, e.g. `.fontSize(15.fp)`. */
    public func fontSize(value: Length): Button {
        pointSize = value
        this
    }

    /** Sets the label font size in font pixels. */
    public func fontSize(value: Float32): Button {
        fontSize(Length(value, LengthUnit.Fp))
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let ps = max(1.0, ctx.resolve(pointSize))
        Size(min(available.w, max(72.0, ctx.renderer.textWidth(title, pointSize: ps) + 24.0)), CUI_CONTROL_H)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        drawSurface(ctx, frame, buttonStyle(ctx))
        let textColor = match (buttonRole) {
            case ButtonRole.Normal => ctx.theme.text
            case _ => ctx.theme.accentText
        }
        ctx.renderer.textCenter(title, frame, textColor, pointSize: max(1.0, ctx.resolve(pointSize)))
        if (ctx.showFocusRing(controlId)) {
            drawFocusRing(ctx, frame, ctx.theme.controlRadius)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        claimHoverIfInside(ctx, event, frame, controlId, CursorShape.Interactive)
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    ctx.focus(controlId)
                    ctx.press(controlId)
                    return true
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (ctx.isPressed(controlId)) {
                    if (frame.contains(x, y)) {
                        onClick()
                    }
                    return true
                }
            case UiEvent.KeyDown(Key.Enter, _) =>
                if (ctx.hasFocus(controlId)) {
                    onClick()
                    return true
                }
            case UiEvent.KeyDown(Key.Space, _) =>
                if (ctx.hasFocus(controlId)) {
                    onClick()
                    return true
                }
            case _ => ()
        }
        false
    }

    public func focusableId(): ?String {
        Some(controlId)
    }

    private func buttonStyle(ctx: UiContext): SurfaceStyle {
        match (customStyle) {
            case Some(value) => value
            case None =>
                let base = ctx.theme.buttonSurface(buttonRole)
                match (buttonRole) {
                    case ButtonRole.Normal =>
                        var style = base
                        if (ctx.isPressed(controlId)) {
                            style = style.withFill(ctx.theme.accentSoft)
                        } else if (ctx.isHovered(controlId)) {
                            // Single-winner hover: in overlapping layouts only the visually
                            // top-most claimant highlights (same protocol as the cursor shape).
                            style = style.withFill(ctx.theme.fieldActive)
                        }
                        // The focus ring (drawn in draw() on keyboard focus) shows where
                        // Enter/Space will land — no need to also recolour the border.
                        style
                    case _ => base
                }
        }
    }
}
