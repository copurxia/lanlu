package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import std.math.sqrt

// ── 主题切换涟漪动画（网页 Material 涟漪式明暗切换）──
// 不立即切换 ctx.theme，而是从窗口中心扩展一个填充新主题背景色的圆，
// 动画完成后再应用实际主题切换。视觉效果：新主题从中心向外揭示。

// 涟漪动画跨帧状态
class ThemeRippleState {
    var active = false
    var targetMode = "" // "dark" | "light"
    var originX: Float32 = -1.0
    var originY: Float32 = -1.0
    var oldSnapshot: ?Texture = None
    var targetSnapshot: ?Texture = None
    // easeOutCubic：快起慢止，接近 Material 涟漪的自然衰减
    let tween = Tween(850, {t: Float32 => Easing.easeOutCubic(t)})
}

// 全屏遮罩 widget：ZStack 中覆盖整个窗口，不消费任何事件。
public class ThemeRipple <: Widget {
    private let model: AppModel
    private let st: ThemeRippleState

    public init(model: AppModel) {
        this.model = model
        st = rememberState<ThemeRippleState>("theme:ripple", {=> ThemeRippleState()}).value

        // 模型侧 setTheme 已推迟实际切换，在此检测待处理请求
        if (model.themeRipplePending) {
            st.active = true
            st.targetMode = model.themeRippleTarget
            st.originX = model.themeRippleX
            st.originY = model.themeRippleY
            closeSnapshot(st.oldSnapshot)
            closeSnapshot(st.targetSnapshot)
            st.oldSnapshot = None
            st.targetSnapshot = None
            st.tween.reset(0.0)
            model.themeRipplePending = false
        }

        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, available.h)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        // 全屏占位，实际绘制坐标从 ctx.viewportWidth/Height 读取
    }

    public func draw(ctx: UiContext): Unit {
        if (!st.active) {
            return
        }

        // 第一阶段：此时下层刚绘完旧主题，捕获完整旧帧；随后应用目标主题并请求
        // 下一帧。下一次重建会让所有控件、文字、图片都按目标 Theme 绘制。
        if (st.oldSnapshot.isNone()) {
            st.oldSnapshot = captureThemeSnapshot(ctx)
            model.applyPendingTheme()
            if (st.oldSnapshot.isNone()) {
                // 不支持 GPU 回读的后端退化为立即切换，不能卡在过渡状态。
                finishRipple()
                return
            }
            ctx.requestFrame()
            return
        }

        // 第二阶段首帧：下层已经是完整目标主题，先捕获它，随后才用旧帧覆盖并
        // 通过纹理圆逐步揭示目标快照。
        if (st.targetSnapshot.isNone()) {
            st.targetSnapshot = captureThemeSnapshot(ctx)
            st.tween.reset(0.0)
        }

        let oldSnapshot = match (st.oldSnapshot) {
            case Some(texture) => texture
            case None => return
        }
        let targetSnapshot = match (st.targetSnapshot) {
            case Some(texture) => texture
            case None =>
                // 读回失败时下层已经是目标主题，直接结束而不是退回空白色圆。
                finishRipple()
                return
        }

        // 动画进度：0→1，tween.animate 内部自动 ctx.requestFrame() 驱动连续帧。
        let t = st.tween.animate(ctx, target: 1.0)

        // 指针触发时从实际点击点扩散；键盘/设置分段触发时回落窗口中心。
        let cx = if (st.originX >= 0.0 && st.originX <= ctx.viewportWidth) {
            st.originX
        } else {
            ctx.viewportWidth / 2.0
        }
        let cy = if (st.originY >= 0.0 && st.originY <= ctx.viewportHeight) {
            st.originY
        } else {
            ctx.viewportHeight / 2.0
        }

        // 圆心到四角的最大距离：确保 t=1 时圆完全覆盖窗口
        let w = ctx.viewportWidth
        let h = ctx.viewportHeight
        let farX = max(cx, w - cx)
        let farY = max(cy, h - cy)
        let maxR = sqrt(farX * farX + farY * farY)
        let r = maxR * t

        // 旧主题快照铺满窗口，圆内绘制目标主题快照；圆外保持旧主题。
        ctx.renderer.texture(oldSnapshot, Rect(0.0, 0.0, ctx.viewportWidth, ctx.viewportHeight))
        ctx.renderer.textureClippedCircle(cx, cy, r, targetSnapshot)

        // 参考页的先行辉光环：比主圆更快抵达边缘并逐渐淡出。
        let ringT = min(t / 0.76, 1.0)
        let ringAlpha = Int64(128.0 * (1.0 - ringT))
        if (ringAlpha > 0) {
            let ringColor = if (st.targetMode == "light") {
                LANLU_L_ACCENT.withAlpha(ringAlpha)
            } else {
                LANLU_ACCENT.withAlpha(ringAlpha)
            }
            ctx.renderer.strokeCircle(cx, cy, maxR * ringT, Pen(width: 3.0, color: ringColor))
        }

        // 动画完成：切换实际主题并关闭涟漪
        if (t >= 1.0) {
            finishRipple()
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        // 纯视觉遮罩，不消费事件；点击/滚轮穿透到下层的主题 UI
        false
    }

    private func finishRipple(): Unit {
        closeSnapshot(st.oldSnapshot)
        closeSnapshot(st.targetSnapshot)
        st.oldSnapshot = None
        st.targetSnapshot = None
        st.active = false
    }
}

private func closeSnapshot(snapshot: ?Texture): Unit {
    match (snapshot) {
        case Some(texture) => texture.close()
        case None => ()
    }
}

// GPU render-target 复制不离开渲染线程，也不触发同步像素回读。不支持目标纹理的
// 后端返回 None，由调用处立即切换主题，避免为了动画阻塞 UI 线程。
private func captureThemeSnapshot(ctx: UiContext): ?Texture {
    ctx.renderer.captureTextureGpu(ctx.viewportWidth, ctx.viewportHeight)
}
