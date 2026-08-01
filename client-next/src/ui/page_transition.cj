package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*

// ── 页面切换交叉淡化动画 ──
// 切页时不让新页面生硬出现：navigate() 推迟实际切页，本组件在旧页面仍留在屏幕上
// 的那一帧把它捕获为 GPU 纹理，随后提交切页（下层重建为新页面），旧纹理以
// 200ms easeOutCubic 淡出覆盖在新页面之上。效果克制：旧页像一层薄纱被揭开，
// 新页面早已在其下就位。与 ThemeRipple 同一技术路径（captureTextureGpu）；
// 后端不支持 GPU 回读时退化为立即切页，不卡在过渡态。

private let PAGE_TRANSITION_MS: Int64 = 200

// 跨帧动画状态。
class PageTransitionState {
    var active = false
    var oldSnapshot: ?Texture = None
    let fadeTween = Tween(PAGE_TRANSITION_MS, Easing.easeOutCubic)
}

// 全屏遮罩 widget：ZStack 中覆盖整个窗口，不消费任何事件（点击穿透到新页面）。
public class PageTransition <: Widget {
    private let model: AppModel
    private let st: PageTransitionState

    public init(model: AppModel) {
        this.model = model
        st = rememberState<PageTransitionState>("page:transition", {=> PageTransitionState()}).value

        // navigate() 已推迟实际切页；在此检测待处理请求并进入过渡态。
        if (model.pageTransitionPending) {
            st.active = true
            closeSnapshot(st.oldSnapshot)
            st.oldSnapshot = None
            st.fadeTween.reset(0.0)
            model.pageTransitionPending = false
        }

        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, available.h)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        // 全屏占位，实际绘制坐标从 ctx.viewportWidth/Height 读取。
    }

    public func draw(ctx: UiContext): Unit {
        if (!st.active) {
            return
        }

        // 第一阶段：此时下层刚绘完旧页面（page 尚未提交），捕获整帧；随后提交
        // 切页并请求下一帧。下一次重建会让下层按新 Page 绘制。
        if (st.oldSnapshot.isNone()) {
            st.oldSnapshot = ctx.renderer.captureTextureGpu(ctx.viewportWidth, ctx.viewportHeight)
            model.commitPendingPage()
            if (st.oldSnapshot.isNone()) {
                // 不支持 GPU 回读的后端退化为立即切页，不能卡在过渡状态。
                st.active = false
                return
            }
            ctx.requestFrame()
            return
        }

        let snapshot = match (st.oldSnapshot) {
            case Some(texture) => texture
            case None => return
        }

        // 淡出进度 0→1；tween.animate 内部自动 ctx.requestFrame() 驱动连续帧。
        // 旧帧 alpha 255→0，其下已是重建好的新页面，形成交叉淡化。
        let t = st.fadeTween.animate(ctx, target: 1.0)
        snapshot.setAlpha(Int64(255.0 * (1.0 - t)))
        ctx.renderer.texture(snapshot, Rect(0.0, 0.0, ctx.viewportWidth, ctx.viewportHeight))
        snapshot.setAlpha(255)

        // 动画完成：释放纹理并退出过渡态。
        if (st.fadeTween.settled()) {
            closeSnapshot(st.oldSnapshot)
            st.oldSnapshot = None
            st.active = false
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        // 纯视觉遮罩，不消费事件；点击/滚轮穿透到下层的新页面。
        false
    }
}

private func closeSnapshot(snapshot: ?Texture): Unit {
    match (snapshot) {
        case Some(texture) => texture.close()
        case None => ()
    }
}
