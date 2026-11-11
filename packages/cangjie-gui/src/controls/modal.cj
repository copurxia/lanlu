package cui.controls

import lgui.{Color, Key, Rect, Size, SurfaceStyle, Texture, UiEvent}
import lgui.input.Keyboard
import cui.core.{Bindable, Easing, Overlay, State, Tween, UiContext, Widget, buildChild, controlIdentity, drawSurface, 
    emit, focusableCountNow, focusablesSince, localState}

/// 诊断出口：调用方（引擎/测试）注册后，Modal 会把遮罩相关尺寸交给它记录。
/// 用 sink 而不是直接写文件 —— lgui 与 cui 不持有任何平台路径（分层守卫会拦）。
public var modalDiagSink: Option<(String) -> Unit> = None

private let MODAL_PADDING: Float32 = 22.0
private let MODAL_MAX_W: Float32 = 460.0
private let MODAL_ANIMATION_MS: Int64 = 180
private let MODAL_ENTER_OFFSET_Y: Float32 = 16.0

/*
 * A modal dialog. While `presented` is true it floats a centred panel over a dimming backdrop
 * via the interactive overlay — but unlike a dropdown or context menu (which draw their body by
 * hand), a Modal hosts a real widget subtree: its `body` widgets are laid out inside the panel
 * and receive events routed through the overlay, so a dialog can hold buttons, text fields, or
 * anything else with normal state — including controls that open popups of their own (Dropdown,
 * ComboBox, ContextMenu), which register above the dialog on the overlay stack, paint on top,
 * and see events first.
 *
 * Being modal, it swallows every event (nothing reaches the backdrop tree); a press outside the
 * panel or Escape dismisses it. One eased progress value fades the backdrop and lifts the dialog
 * into place; on dismissal both motions reverse, with the body and overlay retained until the exit
 * finishes. A fully hidden dialog costs nothing and registers no focusables. It takes no space in
 * the tree — place it anywhere (a `ZStack` at the root is typical) and it centres itself against
 * the viewport.
 */
public class Modal <: Widget {
    private let presented: Bindable<Bool>
    private let content: ?Widget
    // The focus stops declared inside the dialog body, in build order. A modal is a focus
    // trap: Tab cycles these and never escapes to the controls under the backdrop (which
    // stay in the global ring but cannot receive events while the dialog is open).
    private let contentFocusables: Array<String>
    private let onDismiss: ?() -> Unit
    // Identifies this dialog's overlay registration across per-frame rebuilds, so dismissing
    // removes exactly this dialog from the overlay stack (never a popup opened above it).
    private let overlayOwner: String
    // 模糊遮罩（backdrop-filter）：打开时回读背景，经 libvips 高斯模糊成纹理（见
    // Renderer.captureBlurredTexture），关闭时销毁。遮罩暗化 55% 黑（原型 rgba(0,0,0,.55)）。
    private let blurBackdrop: Bool
    private let contentPadding: Float32
    private let modalMaxWidth: Float32
    private let maxHeightRatio: Float32
    private let transition: Tween
    private let blurTexture: State<?Texture>
    private var dialogRect = Rect.zero()
    private var transitionT: Float32 = 0.0

    public init(presented: Bindable<Bool>, onDismiss!: ?() -> Unit = None, blurBackdrop!: Bool = false,
        padding!: Float32 = MODAL_PADDING, maxWidth!: Float32 = MODAL_MAX_W, maxHeightRatio!: Float32 = 0.85,
        body!: () -> Unit) {
        this.presented = presented
        this.onDismiss = onDismiss
        this.blurBackdrop = blurBackdrop
        this.contentPadding = max(0.0, padding)
        this.modalMaxWidth = max(1.0, maxWidth)
        this.maxHeightRatio = max(0.1, min(1.0, maxHeightRatio))
        this.overlayOwner = controlIdentity("Modal")
        this.transition = localState<Tween>("${this.overlayOwner}:transition") {
            Tween(MODAL_ANIMATION_MS, {t => Easing.easeOutCubic(t)})
        }.value
        this.blurTexture = localState<?Texture>("Modal:${this.overlayOwner}:blur") {None}
        this.transitionT = transition.value
        if (presented.value || transition.value > 0.0 || !transition.settled()) {
            let focusStart = focusableCountNow()
            this.content = Some(buildChild(body))
            this.contentFocusables = focusablesSince(focusStart)
        } else {
            this.content = None
            this.contentFocusables = []
        }
        if (!presented.value && transition.value <= 0.0 && transition.settled()) {
            releaseBlurTexture()
        }
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(ctx: UiContext, _: Rect): Unit {
        match (content) {
            case Some(body) =>
                let goal: Float32 = if (presented.value) {
                    1.0
                } else {
                    0.0
                }
                transitionT = transition.animate(ctx, target: goal)
                // Centre the panel against the viewport, sizing it to the body plus padding but
                // never wider/taller than most of the window. The short lift moves layout and hit
                // testing together, so controls remain aligned with what is painted.
                let maxContentW = max(0.0, min(ctx.viewportWidth * 0.94, modalMaxWidth) - contentPadding * 2.0)
                let maxContentH = max(0.0, ctx.viewportHeight * maxHeightRatio - contentPadding * 2.0)
                let size = body.measure(ctx, Size(maxContentW, maxContentH))
                let w = size.w + contentPadding * 2.0
                let h = size.h + contentPadding * 2.0
                let offsetY = MODAL_ENTER_OFFSET_Y * (1.0 - transitionT)
                dialogRect = Rect((ctx.viewportWidth - w) / 2.0, (ctx.viewportHeight - h) / 2.0 + offsetY, w, h)
                body.layout(ctx, dialogRect.inset(contentPadding))
                if (!presented.value && transitionT <= 0.0) {
                    releaseBlurTexture()
                    // The current tree still contains the closing body. Rebuild once more so it
                    // and its focus stops are pruned after the invisible overlay is gone.
                    ctx.requestFrame()
                }
            case None => ()
        }
    }

    public func draw(ctx: UiContext): Unit {
        // Register only once the body exists. `presented` can flip true during this frame's event
        // phase — after init already built `content` as None — and painting then would flash an
        // empty panel for one frame; instead the dialog appears next frame, when the body is built.
        if (presented.value || transitionT > 0.0) {
            match (content) {
                case Some(_) => ctx.setOverlay(
                    Overlay(handleEvent: {c, e => handleModal(c, e)}, render: {c => drawModal(c)}, owner: overlayOwner))
                case None => ()
            }
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        // Input reaches the dialog subtree through the overlay (`handleModal`); only the
        // per-frame tick is dispatched to the tree directly, so it is forwarded by hand —
        // otherwise timed behaviours inside the dialog (a field's autofocus, an application
        // Frame hook) would never run.
        match (event) {
            case UiEvent.Frame(_) => routeToContent(ctx, event)
            case _ => ()
        }
        false
    }

    public func focusableIds(): Array<String> {
        contentFocusables // the stops the dialog's own focus trap cycles (empty while hidden)
    }

    private func handleModal(ctx: UiContext, event: UiEvent): Bool {
        if (!presented.value) {
            return true // keep the backdrop inert while the exit animation is still visible
        }
        match (event) {
            case UiEvent.KeyDown(Key.Escape, _) => dismiss(ctx)
            case UiEvent.KeyDown(Key.Tab, _) => cycleDialogFocus(ctx, if (Keyboard.modifiers().shift) {
                -1
            } else {
                1
            })
            case UiEvent.MouseDown(_, x, y) =>
                if (dialogRect.contains(x, y)) {
                    routeToContent(ctx, event)
                } else {
                    dismiss(ctx) // a press on the backdrop dismisses
                }
            case _ => routeToContent(ctx, event)
        }
        true // modal: an event never reaches the backdrop tree
    }

    // Moves keyboard focus by `step` through the dialog's own focus stops, wrapping at the
    // ends; from no (or an outside) focus, forward enters at the first stop and backward at
    // the last — the same entry rule as the shell's window-level traversal.
    private func cycleDialogFocus(ctx: UiContext, step: Int64): Unit {
        let count = contentFocusables.size
        if (count == 0) {
            return
        }
        var current = -1
        for (i in 0..count) {
            if (contentFocusables[i] == ctx.focusId) {
                current = i
                break
            }
        }
        let next = if (current < 0) {
            if (step > 0) {
                0
            } else {
                count - 1
            }
        } else {
            (((current + step) % count) + count) % count
        }
        ctx.focus(contentFocusables[next], viaKeyboard: true)
    }

    private func routeToContent(ctx: UiContext, event: UiEvent): Unit {
        match (content) {
            case Some(body) => let _ = body.handle(ctx, event)
            case None => ()
        }
    }

    private func drawModal(ctx: UiContext): Unit {
        let t = max(0.0, min(1.0, transitionT))
        if (t <= 0.0) {
            return
        }
        if (blurBackdrop) {
            // 诊断：把遮罩相关尺寸交给注册方（引擎写成 probe_trace）
            match (modalDiagSink) {
                case Some(sink) =>
                    let line = "modal viewport=" + ctx.viewportWidth.toString() + "x" + ctx.viewportHeight.toString() +
                        " blurTex=" + (if (blurTexture.value.isSome()) { "some" } else { "none" })
                    sink(line)
                case None => ()
            }
            // 首帧惰性捕捉背景模糊纹理（headless/回读失败回退为纯暗化）。
            if (blurTexture.value.isNone()) {
                // 原型是 backdrop-filter: blur(48px)。此前用 1/4 中间图 + sigma=4，
                // 等效只有约 16 物理像素 —— 在 2090px 宽的窗口上几乎看不出模糊
                // （真机反馈"背景模糊没有"）。改成 sigma=12 → 等效约 48 物理像素，
                // 与原型一致；仍用 1/4 中间图，避免回读与高斯开销翻倍。
                blurTexture.value = ctx.renderer.captureBlurredTexture(4, sigma: 12.0)
            }
            match (blurTexture.value) {
                case Some(texture) =>
                    texture.setAlpha(Int64(255.0 * t))
                    ctx.renderer.texture(texture, Rect(0.0, 0.0, ctx.viewportWidth, ctx.viewportHeight))
                    texture.setAlpha(255)
                case None => ()
            }
            ctx.renderer.fill(Rect(0.0, 0.0, ctx.viewportWidth, ctx.viewportHeight), fadedMaskColor(ctx, t))
        } else {
            ctx.renderer.fill(Rect(0.0, 0.0, ctx.viewportWidth, ctx.viewportHeight),
                Color.rgba(12, 14, 20, Int64(130.0 * t)))
        }
        drawSurface(ctx, dialogRect, modalSurface(ctx))
        match (content) {
            case Some(body) => body.draw(ctx)
            case None => ()
        }
    }

    private func dismiss(ctx: UiContext): Unit {
        if (!presented.value) {
            return
        }
        presented.value = false
        // Keep this layer registered until the next rebuild retargets the tween. That prevents
        // the backdrop tree from receiving input through a dialog that is still fading out.
        ctx.requestFrame()
        match (onDismiss) {
            case Some(callback) => callback()
            case None => ()
        }
    }

    // 弹窗表面用 field（卡片底色）而非 panelRaised：dialog 是内容卡片不是浮层，
    // lanlu 主题下 field = 亮白/暗 #131316，panelRaised 会显灰。
    private func modalSurface(ctx: UiContext): SurfaceStyle {
        SurfaceStyle(ctx.theme.field, border: ctx.theme.panelEdge, radius: ctx.theme.controlRadius, borderWidth: 1.0,
            shadow: ctx.theme.shadow, shadowOffsetY: 8.0)
    }

    // 遮罩随主题：亮主题白纱、暗主题黑纱（按 field 明度判定，55% 不透明度对齐原型）。
    private func maskColor(ctx: UiContext): Color {
        let f = ctx.theme.field
        let lum = (Int64(f.r) + Int64(f.g) + Int64(f.b)) / 3
        if (lum > 127) {
            Color.rgba(255, 255, 255, 140)
        } else {
            Color.rgba(0, 0, 0, 140)
        }
    }

    private func fadedMaskColor(ctx: UiContext, progress: Float32): Color {
        let color = maskColor(ctx)
        color.withAlpha(Int64(Float32(Int64(color.a)) * progress))
    }

    private func releaseBlurTexture(): Unit {
        match (blurTexture.value) {
            case Some(texture) => texture.close()
            case None => ()
        }
        if (blurTexture.value.isSome()) {
            blurTexture.value = None
        }
    }
}
