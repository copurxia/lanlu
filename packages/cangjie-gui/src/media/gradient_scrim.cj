package cui.media

import lbase.{Color, Rect, Size, clampF32}
import cui.base.{UiEvent}
import cui.core.{UiContext, Widget, emit}
import std.collection.ArrayList
import std.sort.sort

/** 渐变方向：语义同 CSS `to <direction>`——位置 0 在起始边，1 在 direction 指定的终止边。 */
public enum GradientDirection {
    | Left
    | Right
    | Top
    | Bottom
}

/*
 * 按位置 t（0..1，已钳制）在 stops 上线性插值取色。
 * stops 需按位置升序（GradientScrim 构造时已排序）；t 落在首/尾 stop 之外时取端点色，
 * stops 为空时返回全透明。alpha 随颜色一起插值（Color.lerp 四通道）。
 */
protected func gradientColorAt(stops: Array<(Float32, Color)>, t: Float32): Color {
    if (stops.size == 0) {
        return Color.rgba(0, 0, 0, 0)
    }
    let pos = clampF32(t, 0.0, 1.0)
    if (pos <= stops[0][0]) {
        return stops[0][1]
    }
    if (pos >= stops[stops.size - 1][0]) {
        return stops[stops.size - 1][1]
    }
    for (i in 0..stops.size - 1) {
        let (p0, c0) = stops[i]
        let (p1, c1) = stops[i + 1]
        if (pos >= p0 && pos <= p1) {
            let span = p1 - p0
            let local = if (span <= 0.0f32) { 0.0f32 } else { (pos - p0) / span }
            return c0.lerp(c1, local)
        }
    }
    stops[stops.size - 1][1]
}

/**
 * 线性渐变覆盖层：把自身矩形沿 `direction` 切成若干竖/横带，逐带以插值色 `Renderer.fill`
 * （Color 带 alpha，叠加在下层内容上）。用于详情页 backdrop 的左右渐变与底部融入页面底色。
 *
 * `stops` 为 (位置 0..1, 颜色) 序列，构造时按位置排序；`bands` 为分带数（默认 64，
 * ≥32 肉眼无条纹）。纯展示控件：不消费任何事件（handle 恒 false），不绘制自身底色，
 * 因此可直接叠在图片/内容之上（ZStack）。
 */
public class GradientScrim <: Widget {
    private let direction: GradientDirection
    private let stops: Array<(Float32, Color)>
    private let bands: Int64
    private var frame = Rect.zero()

    public init(direction!: GradientDirection, stops!: Array<(Float32, Color)>, bands!: Int64 = 64) {
        this.direction = direction
        // 排序拷贝，容忍调用方乱序给出 stops。
        let sorted = ArrayList<(Float32, Color)>()
        sorted.add(all: stops)
        sort(sorted, lessThan: { a, b => a[0] < b[0] })
        this.stops = sorted.toArray()
        this.bands = max(1, bands)
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, available.h)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        if (stops.size == 0 || frame.w <= 0.0 || frame.h <= 0.0) {
            return
        }
        let n = Float32(bands)
        // 带边缘对齐到整数物理像素：相邻带共享同一条整像素边，既不留缝也不重叠——
        // 半透明色重叠会二次混合出深纹，小数边各自取整则会周期性漏出底色细线。
        match (direction) {
            case GradientDirection.Right =>
                for (i in 0..bands) {
                    let x0 = snapX(i, n)
                    let t = (Float32(i) + 0.5) / n
                    ctx.renderer.fill(Rect(x0, frame.y, snapX(i + 1, n) - x0, frame.h), gradientColorAt(stops, t))
                }
            case GradientDirection.Left =>
                for (i in 0..bands) {
                    let x0 = snapX(i, n)
                    // 位置 0 在右边：从左数第 i 带对应 t = 1 - 中心位置。
                    let t = 1.0 - (Float32(i) + 0.5) / n
                    ctx.renderer.fill(Rect(x0, frame.y, snapX(i + 1, n) - x0, frame.h), gradientColorAt(stops, t))
                }
            case GradientDirection.Bottom =>
                for (i in 0..bands) {
                    let y0 = snapY(i, n)
                    let t = (Float32(i) + 0.5) / n
                    ctx.renderer.fill(Rect(frame.x, y0, frame.w, snapY(i + 1, n) - y0), gradientColorAt(stops, t))
                }
            case GradientDirection.Top =>
                for (i in 0..bands) {
                    let y0 = snapY(i, n)
                    let t = 1.0 - (Float32(i) + 0.5) / n
                    ctx.renderer.fill(Rect(frame.x, y0, frame.w, snapY(i + 1, n) - y0), gradientColorAt(stops, t))
                }
        }
    }

    // x 方向第 i 条带边（四舍五入到整数像素）。
    private func snapX(i: Int64, n: Float32): Float32 {
        Float32(Int64(frame.x + frame.w * Float32(i) / n + 0.5))
    }

    // y 方向第 i 条带边（四舍五入到整数像素）。
    private func snapY(i: Int64, n: Float32): Float32 {
        Float32(Int64(frame.y + frame.h * Float32(i) / n + 0.5))
    }

    // 纯覆盖层：事件一律不消费，让下层内容（卡片、按钮）照常响应。
    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }

    public func isFlexible(): Bool {
        true
    }
}
