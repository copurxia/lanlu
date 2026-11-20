package cui.media

import lbase.{Rect, Size}
import cui.base.{UiEvent}
import cui.core.{UiContext, Widget, emit}

/*
 * 可缩放的内存像素图视图：与 PixelImageView 共用按 key 键控的两阶段纹理缓存
 * （stagePixelImage / pixelTexture，见 pixel_texture_cache.cj），逐帧声明只是一次缓存查询。
 *
 * 几何：`fit` 决定基准适配矩形（同 fittedRect），绘制时把基准尺寸乘 `scale`、绕组件中心
 * 展开，再加 `offsetX/offsetY` 平移；结果矩形 clip 到组件 bounds，放大时不会画出界。
 *
 * 本控件不做任何手势：scale/offset 由调用方驱动（双击切换可用 ctx.clickCount，
 * theme_state.cj 的 400ms/4px 多击窗口），事件一律不消费。
 */
public class ZoomableImageView <: Widget {
    private let key: String
    private let imageFit: ImageFit
    private var frame = Rect.zero()

    /** 缩放倍数，1 为基准 fit 尺寸；由调用方改写。 */
    public var scale: Float32 = 1.0
    /** 缩放后相对组件中心的水平/垂直平移（逻辑像素）。 */
    public var offsetX: Float32 = 0.0
    public var offsetY: Float32 = 0.0

    public init(key: String, fit!: ImageFit = ImageFit.Contain) {
        this.key = key
        this.imageFit = fit
        emit(this)
    }

    /** 回到未缩放、未平移的初始状态。 */
    public func resetZoom(): Unit {
        scale = 1.0
        offsetX = 0.0
        offsetY = 0.0
    }

    // 阅读器式全幅控件：吃掉全部分配空间（同 GradientScrim），由外层布局决定大小。
    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, available.h)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        match (pixelTexture(ctx.renderer, key)) {
            case Some(image) =>
                let base = fittedRect(Size(image.width, image.height), frame, imageFit)
                let w = base.w * max(0.0, scale)
                let h = base.h * max(0.0, scale)
                let destination = Rect(frame.centerX() + offsetX - w / 2.0, frame.centerY() + offsetY - h / 2.0, w, h)
                // 放大/平移后 dest 几乎总是溢出 bounds，始终 clip（不止 Cover）。
                ctx.renderer.pushClip(frame)
                ctx.renderer.texture(image, destination)
                ctx.renderer.popClip()
            case None => () // 未注册或注册失败：绘制为空而不是打死帧循环
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }

    public func isFlexible(): Bool {
        true
    }
}
