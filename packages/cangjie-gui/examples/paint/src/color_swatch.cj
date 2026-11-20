/*
 * ColorSwatch：可点选的画笔颜色小方块。
 * 应用层自定义 Widget 的最小样例——实现 measure/layout/draw/handle 四个钩子
 * 并 emit(this)，即可像内置控件一样参与声明式布局。
 */
package cui_paint

import cui.{Color, MouseButton, Rect, Size, State, UiContext, UiEvent, Widget, emit}

/** 色块边长与圆角（逻辑像素）。 */
private let SWATCH_SIZE: Float32 = 26.0
private let SWATCH_RADIUS: Float32 = 8.0
/** 选中环分两圈：外圈向外扩出主题文本色描边，内圈留出一道亮色间隙衬托色块。 */
private let RING_OUTER: Float32 = 3.0
private let RING_INNER: Float32 = 1.0

class ColorSwatch <: Widget {
    private let swatch: Color
    private let selected: State<Color>
    private var frame = Rect.zero()

    init(swatch: Color, selected: State<Color>) {
        this.swatch = swatch
        this.selected = selected
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(SWATCH_SIZE, SWATCH_SIZE)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let box = Rect(frame.x, frame.centerY() - SWATCH_SIZE / 2.0, SWATCH_SIZE, SWATCH_SIZE)
        if (isSelected()) {
            // 圆角随外扩量同步加大，环的弧度才能与色块保持同心。
            ctx.renderer.fillRoundedRect(box.inset(-RING_OUTER), SWATCH_RADIUS + RING_OUTER, ctx.theme.text)
            ctx.renderer.fillRoundedRect(box.inset(-RING_INNER), SWATCH_RADIUS + RING_INNER, ctx.theme.panelRaised)
        }
        ctx.renderer.fillRoundedRect(box, SWATCH_RADIUS, swatch)
    }

    public func handle(_: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    selected.value = swatch
                    return true
                }
            case _ => ()
        }
        false
    }

    private func isSelected(): Bool {
        // 逐通道比较时 alpha 不能漏：调色板一旦出现同 RGB 不同透明度的颜色，
        // 漏掉 alpha 会让多个色块同时呈现选中态。
        let current = selected.value
        current.r == swatch.r && current.g == swatch.g && current.b == swatch.b && current.a == swatch.a
    }
}
