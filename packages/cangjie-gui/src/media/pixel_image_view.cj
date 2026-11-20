package cui.media

import lbase.{Rect, Size}
import cui.base.{UiEvent}
import cui.core.{Length, UiContext, Widget, emit}

/*
 * 显示一张由 registerPixelImage 注册的内存像素图。纹理存放在按 key 键控的共享缓存中
 * （见 pixel_texture_cache.cj），因此 PixelImageView 与其它控件一样逐帧声明即可——
 * 每帧重建只是一次缓存查询。key 未注册（或注册失败）时绘制为空，占位由调用方负责。
 * 点击等事件不消费，行为与 ImageView 一致。
 */
public class PixelImageView <: Widget {
    private let key: String
    private var imageFit: ImageFit
    private let preferredWidth: Length
    private let preferredHeight: Length
    // 中心缩放系数（1 = 原始；>1 时目标矩形绕中心放大并裁回 frame，用于 hover 缩放动画）。
    private var zoomFactor: Float32 = 1.0
    private var cornerRadius: Float32 = 0.0
    private var frame = Rect.zero()

    public init(key: String, width: Length, height: Length, fit!: ImageFit = ImageFit.Contain) {
        this.key = key
        this.preferredWidth = width
        this.preferredHeight = height
        this.imageFit = fit
        emit(this)
    }

    /** 选择图像像素在分配到的绘制框内的适配方式。 */
    public func fit(value: ImageFit): PixelImageView {
        imageFit = value
        this
    }

    /** 设置中心缩放系数（1 = 不缩放；>1 放大并裁切到 frame 内，配合动画做 hover 缩放）。 */
    public func zoom(value: Float32): PixelImageView {
        zoomFactor = max(0.01, value)
        this
    }

    /** Clips the final fitted image to a rounded display frame; zero keeps rectangular drawing. */
    public func rounded(radius: Float32): PixelImageView {
        cornerRadius = max(0.0, radius)
        this
    }

    public func measure(ctx: UiContext, available: Size): Size {
        Size(
            min(available.w, max(0.0, ctx.resolve(preferredWidth))),
            min(available.h, max(0.0, ctx.resolve(preferredHeight)))
        )
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let got = pixelTexture(ctx.renderer, key)
        match (got) {
            case Some(image) =>
                // 真机诊断（G2）：改内存环形缓冲（首见 key 记一条），不再每次绘制读写 img_diag.txt。
                imgDiagPushNew("pivDraw ${key}",
                    "[diag] pivDraw key=${key} texId=${image.id} closed=${image.isClosed()} frame=${frame.w}x${frame.h}")
                var destination = fittedRect(Size(image.width, image.height), frame, imageFit)
                // 缩放 >1：目标矩形绕自身中心放大（内容向四周溢出），裁回 frame 内。
                if (zoomFactor > 1.0) {
                    let w = destination.w * zoomFactor
                    let h = destination.h * zoomFactor
                    destination = Rect(destination.centerX() - w / 2.0, destination.centerY() - h / 2.0, w, h)
                    if (cornerRadius > 0.0) {
                        ctx.renderer.textureRoundedRect(image, destination, frame, cornerRadius)
                    } else {
                        ctx.renderer.pushClip(frame)
                        ctx.renderer.texture(image, destination)
                        ctx.renderer.popClip()
                    }
                    return
                }
                if (cornerRadius > 0.0) {
                    imgDiagPushNew("pivRounded ${key}",
                        "[diag] pivRounded key=${key} dst=(${destination.x},${destination.y},${destination.w},${destination.h}) frame=(${frame.x},${frame.y},${frame.w},${frame.h}) r=${cornerRadius}")
                    ctx.renderer.textureRoundedRect(image, destination, frame, cornerRadius)
                    return
                }
                match (imageFit) {
                    case ImageFit.Cover =>
                        ctx.renderer.pushClip(frame)
                        ctx.renderer.texture(image, destination)
                        ctx.renderer.popClip()
                    case _ => ctx.renderer.texture(image, destination)
                }
            case None => () // 未注册或注册失败：绘制为空而不是打死帧循环
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}
