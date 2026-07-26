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
    // easeOutCubic：快起慢止，接近 Material 涟漪的自然衰减
    let tween = Tween(450, {t: Float32 => Easing.easeOutCubic(t)})
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

        // 动画进度：0→1，tween.animate 内部自动 ctx.requestFrame() 驱动连续帧
        let t = st.tween.animate(ctx, target: 1.0)

        // 圆心取窗口几何中心（保证各边距相等，视觉均衡）
        let cx = ctx.viewportWidth / 2.0
        let cy = ctx.viewportHeight / 2.0

        // 圆心到四角的最大距离：确保 t=1 时圆完全覆盖窗口
        let w = ctx.viewportWidth
        let h = ctx.viewportHeight
        let halfW = w / 2.0
        let halfH = h / 2.0
        let maxR = sqrt(halfW * halfW + halfH * halfH)
        let r = maxR * t

        // 以新主题背景色填充扩展圆，覆盖旧主题 UI
        let bg = if (st.targetMode == "light") {
            LANLU_L_BG
        } else {
            LANLU_BG
        }
        ctx.renderer.fillCircle(cx, cy, r, bg)

        // 动画完成：切换实际主题并关闭涟漪
        if (t >= 1.0) {
            st.active = false
            model.applyPendingTheme()
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        // 纯视觉遮罩，不消费事件；点击/滚轮穿透到下层的主题 UI
        false
    }
}
