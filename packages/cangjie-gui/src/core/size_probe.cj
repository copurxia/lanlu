package cui.core

import lbase.{Rect, Size}
import cui.base.{UiEvent}

/**
 * 尺寸探针：布局阶段把自身矩形的宽（可选高）写入调用方持有的 `State`，
 * 视图构建期从下一帧起即可读到该值——`State` 写入会推进状态代次，帧循环自动重渲染，
 * 因此尺寸变化最迟一帧内收敛（与 `LazyRow` 记录视口宽的做法同源）。
 *
 * 典型用途：自适应网格列数——把内容区包一层 SizeProbe，列数 =
 * clamp(floor(width / 卡片节距), 下限, 上限) 在构建期算出；初帧宽度为 State 初值
 * （建议给 0 并在视图中按「未知」走保守列数）。
 *
 * 包装器语义：measure/layout/draw/handle 与灵活性全部透传唯一子视图，探针本身不可见、
 * 不改变布局。
 */
public class SizeProbe <: Widget {
    private let child: Widget
    private let widthState: State<Float32>
    private let heightState: ?State<Float32>

    public init(width!: State<Float32>, height!: ?State<Float32> = None, body!: () -> Unit) {
        this.child = buildChild(body)
        this.widthState = width
        this.heightState = height
        emit(this)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        child.measure(ctx, available)
    }

    public func layout(ctx: UiContext, rect: Rect): Unit {
        // 仅在变化时写入，避免每帧推进状态代次造成无效重渲染。
        let _ = widthState.setIfChanged(rect.w)
        if (let Some(h) <- heightState) {
            let _ = h.setIfChanged(rect.h)
        }
        child.layout(ctx, rect)
    }

    public func draw(ctx: UiContext): Unit {
        child.draw(ctx)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        child.handle(ctx, event)
    }

    public func isFlexible(): Bool {
        child.isFlexible()
    }

    public func flexWeight(): Float32 {
        child.flexWeight()
    }

    public func acceptsStretch(axis: Axis): Bool {
        child.acceptsStretch(axis)
    }

    public func participatesInLayout(): Bool {
        child.participatesInLayout()
    }

    public func focusableId(): ?String {
        child.focusableId()
    }

    public func focusableIds(): Array<String> {
        child.focusableIds()
    }
}
