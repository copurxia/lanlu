package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import std.math.{cos, sin, sqrt}

// ── 主题切换涟漪动画（网页 Material 涟漪式明暗切换）──
// 不立即切换 ctx.theme，而是从窗口中心扩展一个填充新主题背景色的圆，
// 动画完成后再应用实际主题切换。视觉效果：新主题从中心向外揭示。

// 涟漪动画跨帧状态
class ThemeRippleState {
    var active = false
    var targetMode = "" // "dark" | "light"
    var originX: Float32 = -1.0
    var originY: Float32 = -1.0
    var toggleX: Float32 = -1.0
    var toggleY: Float32 = -1.0
    var oldSnapshot: ?Texture = None
    var targetSnapshot: ?Texture = None
    // 三条独立时间线与 light-dark.html 对齐：主揭示 850ms、辉光环 650ms、图标 550ms。
    let revealTween = Tween(850, revealEasing)
    let ringTween = Tween(650, ringEasing)
    let iconTween = Tween(550, Easing.linear)
    let rayTween = Tween(480, iconBezierEasing)
    let depthTween = Tween(500, Easing.easeOutCubic)
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
            st.toggleX = model.themeToggleX
            st.toggleY = model.themeToggleY
            closeSnapshot(st.oldSnapshot)
            closeSnapshot(st.targetSnapshot)
            st.oldSnapshot = None
            st.targetSnapshot = None
            resetTimelines()
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
            resetTimelines()
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
        let t = st.revealTween.animate(ctx, target: 1.0)
        let ringT = st.ringTween.animate(ctx, target: 1.0)
        let iconT = st.iconTween.animate(ctx, target: 1.0)
        let rayT = st.rayTween.animate(ctx, target: 1.0)
        let depthT = st.depthTween.animate(ctx, target: 1.0)

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
        // HTML 的 ::view-transition-old(root)：500ms 内缩至 .985、淡至 .6，制造被新主题
        // 推开的纵深。纹理销毁前无需恢复 alpha。
        let oldScale = 1.0 - 0.015 * depthT
        let oldWidth = ctx.viewportWidth * oldScale
        let oldHeight = ctx.viewportHeight * oldScale
        oldSnapshot.setAlpha(Int64(255.0 - 102.0 * depthT))
        ctx.renderer.texture(oldSnapshot,
            Rect((ctx.viewportWidth - oldWidth) / 2.0, (ctx.viewportHeight - oldHeight) / 2.0, oldWidth, oldHeight))
        ctx.renderer.textureClippedCircle(cx, cy, r, targetSnapshot)

        // 参考页 .glow-ring：3px 边线 + 30px 外发光 + 20px 内发光；颜色取目标主题
        // 的 --toggle-ring，而不是应用 accent（金色）。
        drawGlowRing(ctx, cx, cy, maxR * ringT, ringT)

        drawMorphingThemeIcon(ctx, iconT, rayT)

        // 动画完成：切换实际主题并关闭涟漪
        if (st.revealTween.settled()) {
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

    private func resetTimelines(): Unit {
        st.revealTween.reset(0.0)
        st.ringTween.reset(0.0)
        st.iconTween.reset(0.0)
        st.rayTween.reset(0.0)
        st.depthTween.reset(0.0)
    }

    private func drawMorphingThemeIcon(ctx: UiContext, progress: Float32, rayProgress: Float32): Unit {
        if (st.toggleX < 0.0 || st.toggleY < 0.0) {
            return
        }
        let cx = st.toggleX
        let cy = st.toggleY
        let base = match (model.page.value) {
            case Page.Reader(_, _) => if (st.targetMode == "light") { LANLU_L_BG } else { LANLU_BG }
            case _ => if (st.targetMode == "light") { LANLU_L_PANEL } else { LANLU_PANEL }
        }
        ctx.renderer.fillRoundedRect(Rect(cx - 15.0, cy - 15.0, 30.0, 30.0), 8.0, base)
        ctx.renderer.fillRoundedRect(Rect(cx - 15.0, cy - 15.0, 30.0, 30.0), 8.0, ctx.theme.overlayHover)

        // core/rays 使用源码 cubic-bezier(.34,1.56,.64,1)，挖孔属性使用源码
        // easeOutBack 近似；不能 clamp 到 0...1，否则越界回落的回弹会消失。
        let coreP = clampBack(iconBezierEasing(progress))
        let holeP = clampBack(iconEasing(progress))
        let rayP = clampBack(rayProgress)
        let coreMoon = if (st.targetMode == "dark") { coreP } else { 1.0 - coreP }
        let holeMoon = if (st.targetMode == "dark") { holeP } else { 1.0 - holeP }
        let rayMoon = if (st.targetMode == "dark") { rayP } else { 1.0 - rayP }
        let color = ctx.theme.accent
        // SVG core 从 scale(1) 到 scale(.82)，过冲时先略小于终值再回弹。
        let coreRadius = 6.0 * (1.0 - 0.18 * coreMoon)
        ctx.renderer.fillCircle(cx, cy, coreRadius, color)

        let rayAlpha = Int64(255.0 * clampUnit(1.0 - rayMoon))
        if (rayAlpha > 0) {
            let pen = Pen(width: 1.5, color: color.withAlpha(rayAlpha))
            let rayScale = 1.0 - 0.7 * rayMoon
            let rotation = if (st.targetMode == "dark") {
                -Float64(rayMoon) * 1.0471976
            } else {
                Float64(rayMoon) * 1.0471976
            }
            for (i in 0..8) {
                let angle = Float64(i) * 0.7853982 + rotation
                ctx.renderer.strokeLine(cx + Float32(cos(angle)) * 6.0 * rayScale,
                    cy + Float32(sin(angle)) * 6.0 * rayScale,
                    cx + Float32(cos(angle)) * 8.3 * rayScale,
                    cy + Float32(sin(angle)) * 8.3 * rayScale, pen)
            }
        }
        // 挖圆从图标外移动到右上角，形成太阳到月牙的连续形变。
        let holeX = cx + 18.0 - 13.0 * holeMoon
        let holeY = cy - 8.0 + 3.0 * holeMoon
        ctx.renderer.fillCircle(holeX, holeY, 6.0, base)
    }

    private func drawGlowRing(ctx: UiContext, cx: Float32, cy: Float32, radius: Float32,
        progress: Float32): Unit {
        let fade = 1.0 - clampUnit(progress)
        if (fade <= 0.0 || radius <= 0.0) {
            return
        }
        // light-dark.html：亮目标 rgba(76,110,245,.55)，暗目标 rgba(255,209,102,.5)；
        // ring 元素初始 opacity=.9，故实线峰值分别约 126/115 alpha。
        let (red, green, blue, peakAlpha) = if (st.targetMode == "light") {
            (Int64(76), Int64(110), Int64(245), Int64(126))
        } else {
            (Int64(255), Int64(209), Int64(102), Int64(115))
        }
        // 多层同心描边模拟 box-shadow。外层覆盖约 30px，内层覆盖约 20px，
        // 越远离 3px 实线透明度越低。
        let offsets: Array<Float32> = [5.0, 10.0, 15.0, 20.0, 25.0, 30.0]
        let weights: Array<Float32> = [0.25, 0.19, 0.14, 0.10, 0.065, 0.035]
        for (i in 0..offsets.size) {
            let alpha = Int64(Float32(peakAlpha) * fade * weights[i])
            if (alpha <= 0) {
                continue
            }
            let glow = Color.rgba(red, green, blue, alpha)
            ctx.renderer.strokeCircle(cx, cy, radius + offsets[i], Pen(width: 6.0, color: glow))
            // inset shadow 只延伸约 20px，对应前三至四层。
            if (i < 4 && radius > offsets[i]) {
                ctx.renderer.strokeCircle(cx, cy, radius - offsets[i], Pen(width: 6.0, color: glow))
            }
        }
        let borderAlpha = Int64(Float32(peakAlpha) * fade)
        ctx.renderer.strokeCircle(cx, cy, radius,
            Pen(width: 3.0, color: Color.rgba(red, green, blue, borderAlpha)))
    }
}

private func clampUnit(value: Float32): Float32 {
    max(0.0, min(1.0, value))
}

private func clampBack(value: Float32): Float32 {
    max(-0.15, min(1.15, value))
}

// 求 CSS cubic-bezier 在给定时间 x 上的 y；二分求参数可稳定支持 y>1 的轻微过冲。
private func cubicBezier(progress: Float32, x1: Float32, y1: Float32, x2: Float32, y2: Float32): Float32 {
    let x = clampUnit(progress)
    var low: Float32 = 0.0
    var high: Float32 = 1.0
    var parameter: Float32 = x
    for (_ in 0..12) {
        parameter = (low + high) / 2.0
        if (bezierCoordinate(parameter, x1, x2) < x) {
            low = parameter
        } else {
            high = parameter
        }
    }
    bezierCoordinate(parameter, y1, y2)
}

private func bezierCoordinate(t: Float32, p1: Float32, p2: Float32): Float32 {
    let u = 1.0 - t
    3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t
}

private func revealEasing(t: Float32): Float32 { cubicBezier(t, 0.2, 0.9, 0.25, 1.05) }

private func ringEasing(t: Float32): Float32 { cubicBezier(t, 0.15, 0.8, 0.3, 1.0) }

private func iconBezierEasing(t: Float32): Float32 { cubicBezier(t, 0.34, 1.56, 0.64, 1.0) }

private func iconEasing(t: Float32): Float32 {
    let k = clampUnit(t)
    let u = k - 1.0
    1.0 + 1.56 * u * u * u + 0.56 * u * u
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
