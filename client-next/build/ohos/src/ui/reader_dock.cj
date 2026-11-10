package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.SubtitleAttachment
import std.collection.{ArrayList, HashMap}

// ── 阅读页底部 lane 胶囊（reader-redesign #dock，T2）──
// 单叶自绘 Widget（不组合 Slider/按钮控件）：lane-body 的宽度弹簧、lane 出现/消失的
// scale+淡入、播放进度的逐帧自绘滑条，都需要在 draw 里直接读 Spring/playback 并
// requestFrame 续帧，组合控件表达不了「宽度动画裁切」这层容器。
// 结构：每条 lane 一个圆形 tab（Book=书/Video=胶片/Audio=音符，自绘矢量），
// activeLane 的 lane-body 展开（Spring 宽度 0↔内容宽 + 淡入，原型 .lane-body 340ms）。
// 显隐随 reader.chromeVisible：Spring 下滑/上滑 + 淡入淡出（stiffness 260/damping 26
// 与 Drawer 一致）；隐藏且停稳后不绘制、不消费事件（点击穿透回翻页区）。

// lane-body 内容自然宽（原型 .lane-slider 200px 与控件排布推算；cap 400 同原型 .lane max-width）。
private let DOCK_BOOK_BODY_W: Float32 = 356.0
private let DOCK_AUDIO_BODY_W: Float32 = 390.0
private let DOCK_VIDEO_BODY_W: Float32 = 426.0
// html lane body：页内滚动进度 + 页码 + HTML 专属字号/页边距调节。
private let DOCK_HTML_BODY_W: Float32 = 420.0
private let DOCK_TAB: Float32 = 36.0
private let DOCK_PAD: Float32 = 6.0
private let DOCK_GAP: Float32 = 4.0

// 字幕/音量弹出面板常量
private let SUBTITLE_POPUP_OWNER = "reader:dock:subtitlePopup"
private let VOLUME_POPUP_OWNER = "reader:dock:volumePopup"
private let POPUP_ANIMATION_MS: Int64 = 180
private let POPUP_ENTER_SCALE: Float32 = 0.95
private let POPUP_ENTER_OFFSET_Y: Float32 = 4.0
private let SUBTITLE_POPUP_W: Float32 = 200.0
private let SUBTITLE_ROW_H: Float32 = 28.0
private let SUBTITLE_POPUP_PAD: Float32 = 6.0
private let SUBTITLE_TITLE_H: Float32 = 24.0
private let VOLUME_POPUP_W: Float32 = 160.0
private let VOLUME_POPUP_PAD: Float32 = 8.0
private let VOLUME_SLIDER_W: Float32 = 120.0
private let VOLUME_SLIDER_H: Float32 = 20.0
private let VOLUME_TEXT_H: Float32 = 16.0

// dock 动画状态：rememberState 跨帧保留（每帧重建的 Widget 只是声明）。
class ReaderDockState {
    // chrome 显隐滑块：初始取当前可见性（静态首帧即停稳，快照稳定，同 Drawer 惯例）。
    let slide: Spring
    // lane body 展开度。切换时先把 displayedLane 收到 0，再换成 pendingLane 展开，
    // 避免旧内容瞬间消失以及两种不同宽度的 body 跳变。
    // 两阶段切换需要让收起和展开都可辨识；比 Drawer/整体显隐的 260/26 更舒缓。
    let body = Spring(0.0, stiffness: 140.0, damping: 22.0)
    var lastActiveKey = ""
    var displayedLane: LaneId = LaneId.Book
    var pendingLane: ?LaneId = None
    var laneInited = false
    // 媒体 lane 出现动画（scale .6→1 + 淡入）的弹簧：按 lane key 驻留，
    // lane 消失后条目留存无害（下次同 lane 再现从停稳值起播）。
    let laneSprings = HashMap<String, Spring>()
    // 字幕选择面板
    var subtitleOpen = false
    let subtitleAnim = Tween(POPUP_ANIMATION_MS, {t: Float32 => Easing.easeOutCubic(t)})
    // 音量调节面板
    var volumeOpen = false
    let volumeAnim = Tween(POPUP_ANIMATION_MS, {t: Float32 => Easing.easeOutCubic(t)})
    // 音量滑条拖拽中
    var volumeDragging = false

    init(chromeVisible: Bool) {
        slide = Spring(if (chromeVisible) {
            1.0
        } else {
            0.0
        }, stiffness: 260.0, damping: 26.0)
    }

    func laneSpring(lane: LaneId): Spring {
        let k = lane.toString()
        match (laneSprings.get(k)) {
            case Some(s) => s
            case None =>
                let s = Spring(0.0, stiffness: 260.0, damping: 26.0)
                laneSprings[k] = s
                s
        }
    }
}

// 颜色 alpha 按比例缩放（dock 滑出/淡入时整组元素同步衰减）。
private func fadeColor(c: Color, k: Float32): Color {
    c.withAlpha(Int64(Float32(Int64(c.a)) * max(0.0, min(1.0, k))))
}

// 弹出面板颜色 alpha 随动画进度缩放（与 fadeColor 同语义，面板专用命名）。
private func popupAlpha(c: Color, progress: Float32): Color {
    fadeColor(c, progress)
}

class ReaderDock <: Widget {
    private let model: AppModel
    private let st: ReaderDockState
    private var frame = Rect.zero()
    private var slideT: Float32 = 1.0
    // layout 期算好的热区：lane tab 矩形与 active body 内的控件矩形。
    private let lanes: Array<LaneId>
    private var active: LaneId = LaneId.Book
    private var displayed: LaneId = LaneId.Book
    private var tabRects = ArrayList<Rect>()
    private var bodyRect = Rect.zero() // active lane 的 body 裁切框（已乘展开度）
    private var bodyFullRect = Rect.zero() // body 全宽框（内容定位用）
    private var prevRect = Rect.zero()
    private var nextRect = Rect.zero()
    private var bookSeekRect = Rect.zero()
    private var backRect = Rect.zero()
    private var playRect = Rect.zero()
    private var fwdRect = Rect.zero()
    private var audioSeekRect = Rect.zero()
    private var muteRect = Rect.zero()
    private var subtitleRect = Rect.zero()
    private var htmlSeekRect = Rect.zero()
    private var htmlFontDownRect = Rect.zero()
    private var htmlFontValueRect = Rect.zero()
    private var htmlFontUpRect = Rect.zero()
    private var htmlMarginDownRect = Rect.zero()
    private var htmlMarginValueRect = Rect.zero()
    private var htmlMarginUpRect = Rect.zero()

    public init(model: AppModel) {
        this.model = model
        st = rememberState<ReaderDockState>("reader:dock", {=> ReaderDockState(model.reader.chromeVisible)}).value
        lanes = model.reader.laneSpecs()
        active = model.reader.activeLane
        if (!st.laneInited) {
            st.laneInited = true
            st.lastActiveKey = active.toString()
            st.displayedLane = active
        } else if (active.toString() != st.lastActiveKey) {
            st.lastActiveKey = active.toString()
            if (containsLane(lanes, st.displayedLane)) {
                st.pendingLane = Some(active)
            } else {
                // spread 切换后旧媒体 lane 已不存在，没有可绘制的退出态。
                st.displayedLane = active
                st.pendingLane = None
                st.body.reset(0.0)
            }
        }
        displayed = st.displayedLane
        emit(this)
    }

    private func containsLane(items: Array<LaneId>, wanted: LaneId): Bool {
        for (lane in items) {
            if (lane.equals(wanted)) {
                return true
            }
        }
        false
    }

    private func bodyWidth(lane: LaneId): Float32 {
        match (lane) {
            case LaneId.Book => DOCK_BOOK_BODY_W
            case LaneId.Audio(_) => DOCK_AUDIO_BODY_W
            case LaneId.Video(_) => DOCK_VIDEO_BODY_W
            case LaneId.Html(_) => DOCK_HTML_BODY_W
        }
    }

    // 内容自然总宽（body 按展开度折算），measure/layout 共用。
    private func contentWidth(bodyT: Float32): Float32 {
        var w = DOCK_PAD * 2.0
        for (i in 0..lanes.size) {
            if (i > 0) {
                w += DOCK_GAP
            }
            w += DOCK_TAB
            if (lanes[Int64(i)].equals(displayed)) {
                w += bodyWidth(displayed) * bodyT
            }
        }
        w
    }

    public func measure(ctx: UiContext, _: Size): Size {
        // body 展开弹簧在 measure 推进：本帧宽度参与父布局（胶囊随展开平滑变宽）。
        var target: Float32 = 1.0
        if (st.pendingLane.isSome()) {
            target = 0.0
        }
        var bodyT = st.body.animate(ctx, target: target)
        if (target == 0.0 && bodyT <= 0.02) {
            match (st.pendingLane) {
                case Some(next) =>
                    st.displayedLane = next
                    displayed = next
                    st.pendingLane = None
                    st.body.reset(0.0)
                    bodyT = 0.0
                    ctx.requestFrame()
                case None => ()
            }
        }
        Size(contentWidth(bodyT), DOCK_TAB + DOCK_PAD * 2.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
        tabRects = ArrayList<Rect>()
        var x = rect.x + DOCK_PAD
        let y = rect.y + DOCK_PAD
        let bodyT = max(0.0, min(1.0, st.body.value))
        for (i in 0..lanes.size) {
            let lane = lanes[Int64(i)]
            tabRects.add(Rect(x, y, DOCK_TAB, DOCK_TAB))
            x += DOCK_TAB
            if (lane.equals(displayed)) {
                let fullW = bodyWidth(lane)
                bodyFullRect = Rect(x, y, fullW, DOCK_TAB)
                bodyRect = Rect(x, y, fullW * bodyT, DOCK_TAB)
                x += fullW * bodyT
                layoutBody(lane)
            }
            x += DOCK_GAP
        }
    }

    // active body 内部控件几何（相对 bodyFullRect 排布；绘制时裁到 bodyRect）。
    private func layoutBody(lane: LaneId): Unit {
        let bx = bodyFullRect.x + 2.0
        let cy = bodyFullRect.centerY()
        match (lane) {
            case LaneId.Book =>
                prevRect = Rect(bx, cy - 15.0, 30.0, 30.0)
                bookSeekRect = Rect(bx + 36.0, cy - 10.0, 200.0, 20.0)
                nextRect = Rect(bx + 36.0 + 200.0 + 76.0, cy - 15.0, 30.0, 30.0)
            case LaneId.Audio(_) =>
                backRect = Rect(bx, cy - 15.0, 30.0, 30.0)
                playRect = Rect(bx + 34.0, cy - 17.0, 34.0, 34.0)
                fwdRect = Rect(bx + 72.0, cy - 15.0, 30.0, 30.0)
                audioSeekRect = Rect(bx + 108.0, cy - 10.0, 140.0, 20.0)
                muteRect = Rect(bx + 108.0 + 140.0 + 94.0, cy - 15.0, 30.0, 30.0)
            case LaneId.Video(_) =>
                backRect = Rect(bx, cy - 15.0, 30.0, 30.0)
                playRect = Rect(bx + 34.0, cy - 17.0, 34.0, 34.0)
                fwdRect = Rect(bx + 72.0, cy - 15.0, 30.0, 30.0)
                audioSeekRect = Rect(bx + 108.0, cy - 10.0, 140.0, 20.0)
                muteRect = Rect(bx + 108.0 + 140.0 + 94.0, cy - 15.0, 30.0, 30.0)
                subtitleRect = Rect(bx + 376.0, cy - 15.0, 38.0, 30.0)
            case LaneId.Html(_) =>
                // 进度 150 + 页码 54 + 字号三格 + 页边距三格；Book lane 兜底翻章节。
                htmlSeekRect = Rect(bx, cy - 10.0, 150.0, 20.0)
                htmlFontDownRect = Rect(bx + 212.0, cy - 15.0, 28.0, 30.0)
                htmlFontValueRect = Rect(bx + 240.0, cy - 15.0, 32.0, 30.0)
                htmlFontUpRect = Rect(bx + 272.0, cy - 15.0, 28.0, 30.0)
                htmlMarginDownRect = Rect(bx + 306.0, cy - 15.0, 28.0, 30.0)
                htmlMarginValueRect = Rect(bx + 334.0, cy - 15.0, 36.0, 30.0)
                htmlMarginUpRect = Rect(bx + 370.0, cy - 15.0, 28.0, 30.0)
        }
    }

    public func draw(ctx: UiContext): Unit {
        let visible = model.reader.chromeVisible
        let t = st.slide.animate(ctx, target: if (visible) {
            1.0
        } else {
            0.0
        })
        slideT = t
        if (t <= 0.01) {
            closeAllPopups(ctx)
            return
        } // 隐藏停稳：不绘制（事件侧 handle 同步放空）
        let dy = (1.0 - t) * (frame.h + 24.0) // 下滑出屏（原型 chrome-dock-in 反向）
        let alpha = max(0.0, min(1.0, t))
        let a255 = Int64(alpha * 255.0)
        let f = frame.shift(0.0, dy)
        // 胶囊底：半透明毛玻璃语义色（主题翻转由 theme.overlaySurface 自带），圆角 999。
        ctx.renderer.fillRoundedRect(f, f.h / 2.0, fadeColor(ctx.theme.overlaySurface, alpha))
        ctx
            .renderer
            .strokeRoundedRect(f.inset(0.5), f.h / 2.0 - 0.5,
                Pen(width: 1.0, color: fadeColor(ctx.theme.overlayBorder, alpha)))
        for (i in 0..lanes.size) {
            let lane = lanes[Int64(i)]
            drawLaneTab(ctx, lane, tabRects[Int64(i)].shift(0.0, dy), a255)
            if (lane.equals(displayed) && st.body.value > 0.01) {
                ctx.renderer.pushClip(bodyRect.shift(0.0, dy))
                drawLaneBody(ctx, lane, dy, Int64(Float32(a255) * max(0.0, min(1.0, st.body.value))))
                ctx.renderer.popClip()
            }
        }
        // 字幕/音量弹出面板（Overlay 浮层，事件优先于树，绘制在最顶层）
        if (st.subtitleOpen || st.subtitleAnim.value > 0.0) {
            let popup = subtitlePopupRect(ctx)
            ctx.setOverlay(
                Overlay(owner: SUBTITLE_POPUP_OWNER, handleEvent: {
                    c, e => if (st.subtitleOpen) {
                        handleSubtitleOverlay(c, e, popup)
                    } else {
                        handleClosingPopup(c, e)
                    }
                }, render: {c => drawSubtitlePopup(c, popup)}))
        }
        if (st.volumeOpen || st.volumeAnim.value > 0.0) {
            let popup = volumePopupRect(ctx)
            ctx.setOverlay(Overlay(owner: VOLUME_POPUP_OWNER, handleEvent: {
                c, e => if (st.volumeOpen) {
                    handleVolumeOverlay(c, e, popup)
                } else {
                    handleClosingPopup(c, e)
                }
            }, render: {c => drawVolumePopup(c, popup)}))
        }
    }

    private func dimColor(ctx: UiContext, a: Int64): Color {
        fadeColor(ctx.theme.onOverlayDim, Float32(a) / 255.0)
    }
    private func mainColor(ctx: UiContext, a: Int64): Color {
        fadeColor(ctx.theme.onOverlay, Float32(a) / 255.0)
    }

    private func drawLaneTab(ctx: UiContext, lane: LaneId, rect: Rect, a: Int64): Unit {
        let id = "reader:dock:tab:${lane.toString()}"
        let isActive = lane.equals(active)
        // lane 出现/消失动画（spread 切换导致 laneSpecs 变化）：媒体 lane scale .6→1 + 淡入
        //（Spring 驻留在 ReaderDockState，按 lane key 取；Book 恒在不播）。
        var scale: Float32 = 1.0
        var alpha = a
        match (lane) {
            case LaneId.Book => ()
            case _ =>
                let v = st.laneSpring(lane).animate(ctx, target: 1.0)
                scale = 0.6 + 0.4 * v
                alpha = Int64(Float32(a) * v)
        }
        if (alpha <= 0) {
            return
        }
        let cx = rect.centerX()
        let cy = rect.centerY()
        let r = rect.w / 2.0 * scale
        if (isActive) {
            ctx.renderer.fillCircle(cx, cy, r, fadeColor(ctx.theme.accentSoft, Float32(alpha) / 255.0))
        } else if (ctx.isHovered(id)) {
            ctx.renderer.fillCircle(cx, cy, r, fadeColor(ctx.theme.overlayHover, Float32(alpha) / 255.0))
        }
        let color = if (isActive) {
            ctx.theme.accent.withAlpha(alpha)
        } else {
            dimColor(ctx, alpha)
        }
        drawLaneGlyph(ctx.renderer, lane, cx, cy, color)
    }

    private func drawLaneBody(ctx: UiContext, lane: LaneId, dy: Float32, a: Int64): Unit {
        match (lane) {
            case LaneId.Book => drawBookBody(ctx, dy, a)
            case LaneId.Audio(_) => drawAudioBody(ctx, dy, a)
            case LaneId.Video(_) => drawVideoBody(ctx, dy, a)
            case LaneId.Html(_) => drawHtmlBody(ctx, dy, a)
        }
    }

    // body 内 30×30 小钮（原型 .lane .icon-btn）：hover 铺圆底，图形由调用方画。
    private func drawBodyButton(ctx: UiContext, rect: Rect, dy: Float32, id: String, a: Int64): Bool {
        let hovered = ctx.isHovered(id)
        if (hovered) {
            ctx
                .renderer
                .fillCircle(rect.centerX(), rect.centerY() + dy, rect.w / 2.0,
                    fadeColor(ctx.theme.overlayHover, Float32(a) / 255.0))
        }
        hovered
    }

    private func drawBookBody(ctx: UiContext, dy: Float32, a: Int64): Unit {
        let r = model.reader
        let pageButtonsEnabled = match (r.mode) {
            case ReadingMode.Webtoon => false
            case _ => true
        }
        if (pageButtonsEnabled) {
            let _ = drawBodyButton(ctx, prevRect, dy, "reader:dock:prev", a)
            let _ = drawBodyButton(ctx, nextRect, dy, "reader:dock:next", a)
        }
        let pageButtonColor = if (pageButtonsEnabled) {
            dimColor(ctx, a)
        } else {
            ctx.theme.mutedText.withAlpha(min(a, 90))
        }
        drawChevronGlyph(ctx.renderer, prevRect.centerX(), prevRect.centerY() + dy, false, pageButtonColor)
        drawChevronGlyph(ctx.renderer, nextRect.centerX(), nextRect.centerY() + dy, true, pageButtonColor)
        // 页码滑条（原型 .lane-slider）：轨道 overlayTrack + accent 填充 + 圆头。
        // 显示语义：seamless 开 = segment 内页码/页数（frontend slider 语义），关 = 全局；
        // 虚拟结束页满格 + 「完」。
        let sr = bookSeekRect.shift(0.0, dy)
        let total = r.displayTotal
        let amount: Float32 = if (total > 1) {
            Float32(r.displayPage - 1) / Float32(total - 1)
        } else {
            1.0
        }
        ctx
            .renderer
            .fillRoundedRect(Rect(sr.x, sr.centerY() - 2.0, sr.w, 4.0), 2.0,
                fadeColor(ctx.theme.overlayTrack, Float32(a) / 255.0))
        ctx.renderer.fillRoundedRect(Rect(sr.x, sr.centerY() - 2.0, sr.w * amount, 4.0), 2.0,
            ctx.theme.accent.withAlpha(a))
        ctx.renderer.fillCircle(sr.x + sr.w * amount, sr.centerY(), 5.0, ctx.theme.accent.withAlpha(a))
        // cur / total（tabular 语义即可，cui 无 font-variant-numeric 原语）。
        let num = if (r.onVirtualEnd) {
            model.t("reader.finishedShort")
        } else {
            "${r.displayPage} / ${total}"
        }
        let nw = ctx.renderer.textWidth(num, pointSize: 12.0)
        let nh = ctx.renderer.textHeight(pointSize: 12.0)
        ctx.renderer.text(num, sr.right() + 6.0 + (70.0 - nw) / 2.0, sr.centerY() - nh / 2.0, dimColor(ctx, a),
            pointSize: 12.0)
    }

    // html lane body：页内滚动进度条（电子书式，页内粒度而非页码粒度）以及
    // HTML 专属排版控制。字号/页边距展示实际 px 值，左右按钮按档位调节。
    // 值 = HtmlPageModel.htmlPageProgress01（scrollY/(contentHeight-viewportH)）；
    // 未就绪（loading/error）显示 0 格，页码照常（拖动由 handle 的 htmlSeek 消费）。
    private func drawHtmlBody(ctx: UiContext, dy: Float32, a: Int64): Unit {
        let hp = model.htmlPage
        let sr = htmlSeekRect.shift(0.0, dy)
        let amount = if (hp.state == "ready") {
            hp.htmlPageProgress01()
        } else {
            0.0f32
        }
        ctx
            .renderer
            .fillRoundedRect(Rect(sr.x, sr.centerY() - 2.0, sr.w, 4.0), 2.0,
                fadeColor(ctx.theme.overlayTrack, Float32(a) / 255.0))
        ctx.renderer.fillRoundedRect(Rect(sr.x, sr.centerY() - 2.0, sr.w * amount, 4.0), 2.0,
            ctx.theme.accent.withAlpha(a))
        ctx.renderer.fillCircle(sr.x + sr.w * amount, sr.centerY(), 5.0, ctx.theme.accent.withAlpha(a))
        // 页码数字区（对齐 Book body 的 cur/total 排布）。
        let num = if (model.reader.onVirtualEnd) {
            model.t("reader.finishedShort")
        } else {
            "${model.reader.displayPage} / ${model.reader.displayTotal}"
        }
        let nw = ctx.renderer.textWidth(num, pointSize: 12.0)
        let nh = ctx.renderer.textHeight(pointSize: 12.0)
        ctx.renderer.text(num, sr.right() + 4.0 + (54.0 - nw) / 2.0, sr.centerY() - nh / 2.0, dimColor(ctx, a),
            pointSize: 12.0)

        let divider = fadeColor(ctx.theme.overlayBorder, Float32(a) / 255.0)
        ctx
            .renderer
            .strokeLine(sr.right() + 62.0, sr.centerY() - 8.0, sr.right() + 62.0, sr.centerY() + 8.0,
                Pen(width: 1.0, color: divider))
        drawHtmlValue(ctx, htmlFontValueRect, dy, "${model.reader.htmlFontSize}", a)
        drawHtmlAdjust(ctx, htmlFontDownRect, dy, "reader:dock:htmlFontDown", "A-",
            htmlFontTierIndex(model.reader.htmlFontSize) > 0, a)
        drawHtmlAdjust(ctx, htmlFontUpRect, dy, "reader:dock:htmlFontUp", "A+",
            htmlFontTierIndex(model.reader.htmlFontSize) < 3, a)

        ctx
            .renderer
            .strokeLine(htmlFontUpRect.right() + 3.0, sr.centerY() - 8.0, htmlFontUpRect.right() + 3.0,
                sr.centerY() + 8.0, Pen(width: 1.0, color: divider))
        drawHtmlValue(ctx, htmlMarginValueRect, dy, "${model.reader.htmlMargin}", a)
        drawHtmlAdjust(ctx, htmlMarginDownRect, dy, "reader:dock:htmlMarginDown", "M-",
            htmlMarginTierIndex(model.reader.htmlMargin) > 0, a)
        drawHtmlAdjust(ctx, htmlMarginUpRect, dy, "reader:dock:htmlMarginUp", "M+",
            htmlMarginTierIndex(model.reader.htmlMargin) < 2, a)
    }

    private func drawHtmlValue(ctx: UiContext, rect: Rect, dy: Float32, value: String, a: Int64): Unit {
        ctx.renderer.textCenter(value, rect.shift(0.0, dy), dimColor(ctx, a), pointSize: 10.5)
    }

    private func drawHtmlAdjust(ctx: UiContext, rect: Rect, dy: Float32, id: String, label: String, enabled: Bool,
        a: Int64): Unit {
        let shifted = rect.shift(0.0, dy)
        if (enabled && ctx.isHovered(id)) {
            ctx
                .renderer
                .fillCircle(shifted.centerX(), shifted.centerY(), shifted.w / 2.0,
                    fadeColor(ctx.theme.overlayHover, Float32(a) / 255.0))
        }
        let color = if (enabled) {
            dimColor(ctx, a)
        } else {
            ctx.theme.mutedText.withAlpha(min(a, 72))
        }
        ctx.renderer.textCenter(label, shifted, color, pointSize: 10.5)
    }

    private func drawAudioBody(ctx: UiContext, dy: Float32, a: Int64): Unit {
        let pb = model.playback
        let _ = drawBodyButton(ctx, backRect, dy, "reader:dock:back", a)
        drawSkipSmall(ctx.renderer, backRect.centerX(), backRect.centerY() + dy, -1.0, dimColor(ctx, a))
        let playHover = drawBodyButton(ctx, playRect, dy, "reader:dock:play", a)
        drawPlayPauseGlyph(ctx.renderer, playRect.centerX(), playRect.centerY() + dy, pb.playing,
            if (playHover) {
                mainColor(ctx, a)
            } else {
                dimColor(ctx, a)
            })
        let _ = drawBodyButton(ctx, fwdRect, dy, "reader:dock:fwd", a)
        drawSkipSmall(ctx.renderer, fwdRect.centerX(), fwdRect.centerY() + dy, 1.0, dimColor(ctx, a))
        // 播放进度：自绘滑条逐帧读 positionSec（playing 时 250ms 定时帧请求续帧，
        // 不写 State 避免全树重建）；durationSec==0 禁用。
        drawPlaybackSeekBar(ctx, audioSeekRect.shift(0.0, dy), pb)
        let timeText = "${formatMediaClock(pb.positionSec)}/${if (pb.durationSec > 0.0) { formatMediaClock(pb.durationSec) } else { "--:--" }}"
        let tw = ctx.renderer.textWidth(timeText, pointSize: 12.0)
        let th = ctx.renderer.textHeight(pointSize: 12.0)
        ctx
            .renderer
            .text(timeText, audioSeekRect.right() + 6.0 + (88.0 - tw) / 2.0, audioSeekRect.centerY() + dy - th / 2.0,
                dimColor(ctx, a), pointSize: 12.0)
        // 音量按钮：面板打开时保持高亮底色
        if (st.volumeOpen) {
            ctx
                .renderer
                .fillCircle(muteRect.centerX(), muteRect.centerY() + dy, muteRect.w / 2.0,
                    fadeColor(ctx.theme.overlayHover, Float32(a) / 255.0))
        }
        let _ = drawBodyButton(ctx, muteRect, dy, "reader:dock:mute", a)
        drawMuteGlyph(ctx.renderer, muteRect.centerX(), muteRect.centerY() + dy, pb.muted, if (st.volumeOpen) {
            mainColor(ctx, a)
        } else {
            dimColor(ctx, a)
        })
    }

    private func drawVideoBody(ctx: UiContext, dy: Float32, a: Int64): Unit {
        drawAudioBody(ctx, dy, a)
        let pb = model.playback
        // 面板打开时按钮保持高亮底色
        if (st.subtitleOpen) {
            ctx
                .renderer
                .fillCircle(subtitleRect.centerX(), subtitleRect.centerY() + dy, subtitleRect.w / 2.0,
                    fadeColor(ctx.theme.overlayHover, Float32(a) / 255.0))
        }
        let hover = drawBodyButton(ctx, subtitleRect, dy, "reader:dock:subtitle", a)
        // 有内嵌轨或有外挂字幕选中都算"字幕开"（同 frontend 计数徽标语义）。
        let enabled = !pb.activeEmbeddedStreamIndexes.isEmpty() || !pb.activeSubtitleIndexes.isEmpty()
        let color = if (enabled) {
            ctx.theme.accent.withAlpha(a)
        } else if (hover || st.subtitleOpen) {
            mainColor(ctx, a)
        } else {
            dimColor(ctx, a)
        }
        let label = if (enabled) {
            "CC·"
        } else {
            "CC"
        }
        let tw = ctx.renderer.textWidth(label, pointSize: 11.0)
        let th = ctx.renderer.textHeight(pointSize: 11.0)
        ctx
            .renderer
            .text(label, subtitleRect.centerX() - tw / 2.0, subtitleRect.centerY() + dy - th / 2.0, color,
                pointSize: 11.0)
    }

    // ±5s 小跳转图形（30×30 槽内 13px 规格，原型 .lane .icon-btn）。
    // 方向语义同 drawSkipGlyph（顶点在 -dir 侧，取 d=-dir 修正）。
    private func drawSkipSmall(renderer: Renderer, cx: Float32, cy: Float32, dir: Float32, color: Color): Unit {
        let d = -dir
        let pen = Pen(width: 1.5, color: color)
        renderer.strokeLine(cx - 5.5 * d, cy - 5.0, cx - 5.5 * d, cy + 5.0, pen)
        renderer.strokeLine(cx - 4.0 * d, cy, cx + 1.5 * d, cy - 4.2, pen)
        renderer.strokeLine(cx - 4.0 * d, cy, cx + 1.5 * d, cy + 4.2, pen)
        renderer.strokeLine(cx + 2.0 * d, cy, cx + 6.5 * d, cy - 4.2, pen)
        renderer.strokeLine(cx + 2.0 * d, cy, cx + 6.5 * d, cy + 4.2, pen)
    }

    // ── 字幕/音量弹出面板 ──

    // 关闭中浮层仍消费事件（防止穿透到下层控件），点击触发按钮可反转回打开。
    private func handleClosingPopup(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (subtitleRect.contains(x, y) && model.playback.isVideo) {
                    toggleSubtitlePopup(ctx)
                } else if (muteRect.contains(x, y)) {
                    toggleVolumePopup(ctx)
                }
                true
            case _ => true
        }
    }

    // 打开/关闭字幕面板（互斥：打开时关闭音量面板）
    private func toggleSubtitlePopup(ctx: UiContext): Unit {
        if (st.subtitleOpen) {
            closeSubtitlePopup(ctx)
        } else {
            closeVolumePopup(ctx)
            st.subtitleOpen = true
            ctx.requestFrame()
        }
    }

    private func closeSubtitlePopup(ctx: UiContext): Unit {
        st.subtitleOpen = false
        let _ = st.subtitleAnim.animate(ctx, target: 0.0)
        ctx.removeOverlay(SUBTITLE_POPUP_OWNER)
    }

    // 打开/关闭音量面板（互斥：打开时关闭字幕面板）
    private func toggleVolumePopup(ctx: UiContext): Unit {
        if (st.volumeOpen) {
            closeVolumePopup(ctx)
        } else {
            closeSubtitlePopup(ctx)
            st.volumeOpen = true
            ctx.requestFrame()
        }
    }

    private func closeVolumePopup(ctx: UiContext): Unit {
        st.volumeOpen = false
        st.volumeDragging = false
        let _ = st.volumeAnim.animate(ctx, target: 0.0)
        ctx.removeOverlay(VOLUME_POPUP_OWNER)
    }

    // dock 隐藏时关闭所有面板
    private func closeAllPopups(ctx: UiContext): Unit {
        if (st.subtitleOpen) {
            closeSubtitlePopup(ctx)
        }
        if (st.volumeOpen) {
            closeVolumePopup(ctx)
        }
    }

    // ── 字幕选择面板 ──
    // 行布局：Off | 外挂字幕（多选切换）| [Embedded 分隔行] | 内嵌轨（单选）。
    // 多选语义同 frontend/client：点选不关面板，面板外点击/Esc 关闭。

    // 外挂字幕选项标签（同 client buildSubtitleOptionLabel）。
    private func subtitleAttachmentLabel(a: SubtitleAttachment, index: Int64): String {
        let language = a.language
        let kind = a.kind.toAsciiLower()
        let name = a.name
        if (language.size > 0 && kind.size > 0) {
            return "${language} · ${kind}"
        }
        if (language.size > 0) {
            return language
        }
        if (name.size > 0 && kind.size > 0 && !name.toAsciiLower().endsWith(".${kind}")) {
            return "${name} · ${kind}"
        }
        if (name.size > 0) {
            return name
        }
        if (kind.size > 0) {
            return kind
        }
        "Subtitle ${index + 1}"
    }

    private func isSubtitleIndexActive(index: Int64): Bool {
        for (i in model.playback.activeSubtitleIndexes) {
            if (i == index) {
                return true
            }
        }
        false
    }

    private func isEmbeddedSubtitleActive(streamIndex: Int32): Bool {
        for (index in model.playback.activeEmbeddedStreamIndexes) {
            if (index == streamIndex) {
                return true
            }
        }
        false
    }

    // 外挂与内嵌两段都存在时，中间插一行分隔标题（占一行高，不可点）。
    private func subtitleHasSeparator(pb: PlaybackModel): Bool {
        !pb.subtitleAttachments.isEmpty() && !pb.embeddedSubtitleStreams.isEmpty()
    }

    // 字幕面板内容行数（Off + 外挂 + 分隔行 + 内嵌轨）。
    private func subtitleItemCount(): Int64 {
        let pb = model.playback
        1 + pb.subtitleAttachments.size + (if (subtitleHasSeparator(pb)) {
            1
        } else {
            0
        }) + pb.embeddedSubtitleStreams.size
    }

    private func subtitleStatusRows(): Int64 {
        let pb = model.playback
        if (pb.subtitleProbeLoading || pb.subtitleScanLoading || pb.subtitleError.size > 0) {
            1
        } else {
            0
        }
    }

    private func subtitlePopupRect(ctx: UiContext): Rect {
        let itemCount = subtitleItemCount()
        let contentH = SUBTITLE_TITLE_H + Float32(itemCount + subtitleStatusRows()) * SUBTITLE_ROW_H
        let h = SUBTITLE_POPUP_PAD * 2.0 + contentH
        // 从 subtitleRect 向上弹出，水平右对齐 subtitleRect 右缘
        let x = max(4.0, min(subtitleRect.right() - SUBTITLE_POPUP_W, ctx.viewportWidth - SUBTITLE_POPUP_W - 4.0))
        let y = max(4.0, frame.y - h - 8.0)
        Rect(x, y, SUBTITLE_POPUP_W, h)
    }

    // 面板内行矩形（index 0 = Off, 1..N = subtitleTracks）
    private func subtitleRowRect(popup: Rect, index: Int64): Rect {
        Rect(popup.x + 4.0, popup.y + SUBTITLE_POPUP_PAD + SUBTITLE_TITLE_H + Float32(index) * SUBTITLE_ROW_H,
            popup.w - 8.0, SUBTITLE_ROW_H)
    }

    private func subtitleItemAt(popup: Rect, y: Float32): Int64 {
        let listTop = popup.y + SUBTITLE_POPUP_PAD + SUBTITLE_TITLE_H
        if (y < listTop) {
            return -1
        }
        let idx = Int64((y - listTop) / SUBTITLE_ROW_H)
        if (idx >= 0 && idx < subtitleItemCount()) {
            return idx
        }
        -1
    }

    private func handleSubtitleOverlay(ctx: UiContext, event: UiEvent, popup: Rect): Bool {
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (popup.contains(x, y)) {
                    let pb = model.playback
                    let extCount = pb.subtitleAttachments.size
                    let sep = if (subtitleHasSeparator(pb)) {
                        1
                    } else {
                        0
                    }
                    let idx = subtitleItemAt(popup, y)
                    if (idx == 0) {
                        pb.clearSubtitles()
                    } else if (idx > 0 && idx <= extCount) {
                        pb.toggleSubtitleIndex(idx - 1)
                    } else if (idx > extCount + sep) {
                        let stream = pb.embeddedSubtitleStreams[idx - 1 - extCount - sep]
                        if (stream.supported) {
                            pb.toggleEmbeddedSubtitle(stream.streamIndex)
                        }
                    }
                    // 多选语义：点选保持面板打开（外部点击/Esc 关闭）。
                    ctx.requestFrame()
                } else {
                    closeSubtitlePopup(ctx)
                }
                true
            case UiEvent.MouseMove(x, y) =>
                // 面板内移动续帧刷新 hover 高亮（不穿透到下层）。
                if (popup.contains(x, y)) {
                    ctx.requestFrame()
                    return true
                }
                false
            case UiEvent.KeyDown(Key.Escape, _) =>
                closeSubtitlePopup(ctx)
                true
            case _ => false
        }
    }

    private func drawSubtitlePopup(ctx: UiContext, popup: Rect): Unit {
        let target: Float32 = if (st.subtitleOpen) {
            1.0
        } else {
            0.0
        }
        let progress = st.subtitleAnim.animate(ctx, target: target)
        let shell = animatedPopupRect(popup, progress)
        // 表面与阴影
        ctx.renderer.fillRoundedRectSoft(shell.shift(0.0, 4.0), 10.0, popupAlpha(ctx.theme.shadow, progress),
            feather: 8.0)
        ctx.renderer.fillRoundedRect(shell, 10.0, popupAlpha(ctx.theme.panelRaised, progress))
        ctx
            .renderer
            .strokeRoundedRect(shell.inset(0.5), 9.5, Pen(width: 1.0, color: popupAlpha(ctx.theme.panelEdge, progress)))
        ctx.renderer.pushClip(shell)
        // 标题行
        let titleY = shell.y + SUBTITLE_POPUP_PAD
        let titleColor = popupAlpha(ctx.theme.mutedText, progress)
        ctx.renderer.text("Subtitles", shell.x + 12.0, titleY + 4.0, titleColor, pointSize: 10.0)
        // 分隔线
        let sepY = titleY + SUBTITLE_TITLE_H
        ctx.renderer.fill(Rect(shell.x + 8.0, sepY, shell.w - 16.0, 1.0), popupAlpha(ctx.theme.panelEdge, progress))
        // 字幕列表：Off + 外挂（多选）+ [分隔] + 内嵌轨（多选）
        let pb = model.playback
        let extCount = pb.subtitleAttachments.size
        let trkCount = pb.embeddedSubtitleStreams.size
        let sep = if (subtitleHasSeparator(pb)) {
            1
        } else {
            0
        }
        if (extCount == 0 && trkCount == 0) {
            // 无字幕可选（外挂/内嵌都没有）
            let noSubColor = popupAlpha(ctx.theme.mutedText, progress)
            let row = subtitleRowRect(shell, 0)
            ctx.renderer.textCenter("No subtitles", row, noSubColor, pointSize: 12.0)
        } else {
            let itemCount = subtitleItemCount()
            for (i in 0..itemCount) {
                let row = subtitleRowRect(shell, i)
                if (sep > 0 && i == extCount + 1) {
                    // 分隔行：内嵌轨小标题
                    ctx
                        .renderer
                        .text("Embedded", row.x + 8.0, row.centerY() - ctx.renderer.textHeight(pointSize: 9.0) / 2.0,
                            popupAlpha(ctx.theme.mutedText, progress), pointSize: 9.0)
                    continue
                }
                let isSelected = if (i == 0) {
                    pb.activeSubtitleIndexes.isEmpty() && pb.activeEmbeddedStreamIndexes.isEmpty()
                } else if (i <= extCount) {
                    isSubtitleIndexActive(i - 1)
                } else {
                    isEmbeddedSubtitleActive(pb.embeddedSubtitleStreams[i - 1 - extCount - sep].streamIndex)
                }
                // hover 高亮
                if (row.contains(ctx.mouseX, ctx.mouseY) && !isSelected) {
                    ctx.renderer.fillRoundedRect(row, 6.0, popupAlpha(ctx.theme.overlayHover, progress))
                }
                // 选中标记（对勾）
                let supported = if (i > extCount + sep) {
                    pb.embeddedSubtitleStreams[i - 1 - extCount - sep].supported
                } else {
                    true
                }
                let textColor = if (!supported) {
                    popupAlpha(ctx.theme.mutedText, progress * 0.65)
                } else if (isSelected) {
                    popupAlpha(ctx.theme.accent, progress)
                } else {
                    popupAlpha(ctx.theme.text, progress)
                }
                if (isSelected) {
                    drawPopupCheckmark(ctx, row, popupAlpha(ctx.theme.accent, progress))
                }
                // 行标签
                let label = if (i == 0) {
                    "Off"
                } else if (i <= extCount) {
                    subtitleAttachmentLabel(pb.subtitleAttachments[i - 1], i - 1)
                } else {
                    let stream = pb.embeddedSubtitleStreams[i - 1 - extCount - sep]
                    let base = if (stream.title.size > 0) {
                        stream.title
                    } else if (stream.language.size > 0) {
                        "${stream.language} · ${stream.codecName}"
                    } else {
                        "${stream.codecName} · #${stream.streamIndex}"
                    }
                    if (stream.supported) {
                        base
                    } else {
                        "${base} · Unsupported"
                    }
                }
                let textX = row.x + 24.0 // 留对勾位置
                let textY = row.centerY() - ctx.renderer.textHeight(pointSize: 12.0) / 2.0
                let labelRect = Rect(textX, row.y, max(0.0, row.right() - textX - 8.0), row.h)
                ctx.renderer.pushClip(labelRect)
                ctx.renderer.text(label, textX, textY, textColor, pointSize: 12.0)
                ctx.renderer.popClip()
            }
        }
        let status = if (pb.subtitleProbeLoading) {
            "Probing embedded subtitles…"
        } else if (pb.subtitleScanLoading) {
            "Extracting subtitles…"
        } else if (pb.subtitleError.size > 0) {
            "Subtitle error: ${pb.subtitleError}"
        } else {
            ""
        }
        if (status.size > 0) {
            let statusRow = subtitleRowRect(shell, subtitleItemCount())
            ctx.renderer.pushClip(statusRow)
            ctx
                .renderer
                .text(status, statusRow.x + 8.0, statusRow.centerY() - ctx.renderer.textHeight(pointSize: 9.0) / 2.0,
                    popupAlpha(ctx.theme.mutedText, progress), pointSize: 9.0)
            ctx.renderer.popClip()
        }
        ctx.renderer.popClip()
        if (!st.subtitleOpen && progress <= 0.0) {
            ctx.requestFrame()
        }
    }

    // ── 音量调节面板 ──
    // 面板只含滑条与百分比：静音不再重复画图标，直接点 dock 静音按钮切换。

    private func volumePopupRect(ctx: UiContext): Rect {
        let h = VOLUME_POPUP_PAD * 2.0 + VOLUME_SLIDER_H + 4.0 + VOLUME_TEXT_H
        // 从 muteRect 向上弹出，水平居中对齐 muteRect 中心
        let cx = muteRect.centerX()
        let x = max(4.0, min(cx - VOLUME_POPUP_W / 2.0, ctx.viewportWidth - VOLUME_POPUP_W - 4.0))
        let y = max(4.0, frame.y - h - 8.0)
        Rect(x, y, VOLUME_POPUP_W, h)
    }

    // 音量面板内各区域
    private func volumeSliderRect(popup: Rect): Rect {
        Rect(popup.centerX() - VOLUME_SLIDER_W / 2.0, popup.y + VOLUME_POPUP_PAD, VOLUME_SLIDER_W, VOLUME_SLIDER_H)
    }

    private func volumeTextRect(popup: Rect): Rect {
        Rect(popup.x, popup.y + VOLUME_POPUP_PAD + VOLUME_SLIDER_H + 4.0, popup.w, VOLUME_TEXT_H)
    }

    private func handleVolumeOverlay(ctx: UiContext, event: UiEvent, popup: Rect): Bool {
        let sliderRect = volumeSliderRect(popup)
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                // 面板打开时点 dock 静音图标 = 切换静音（替代原面板内重复的图标按钮）。
                if (muteRect.contains(x, y)) {
                    model.playback.toggleMute()
                    ctx.requestFrame()
                    return true
                }
                if (sliderRect.contains(x, y)) {
                    st.volumeDragging = true
                    volumeFromSliderX(x, sliderRect)
                    return true
                }
                if (!popup.contains(x, y)) {
                    closeVolumePopup(ctx)
                }
                true
            case UiEvent.MouseMove(x, _) =>
                if (st.volumeDragging) {
                    volumeFromSliderX(x, sliderRect)
                    return true
                }
                false
            case UiEvent.MouseUp(MouseButton.Left, _, _) =>
                if (st.volumeDragging) {
                    st.volumeDragging = false
                    return true
                }
                false
            case UiEvent.KeyDown(Key.Escape, _) =>
                closeVolumePopup(ctx)
                true
            case _ => false
        }
    }

    private func volumeFromSliderX(x: Float32, sliderRect: Rect): Unit {
        if (sliderRect.w <= 0.0) {
            return
        }
        let amount = Float64(max(0.0, min(1.0, (x - sliderRect.x) / sliderRect.w)))
        model.playback.setVolume(amount)
    }

    private func drawVolumePopup(ctx: UiContext, popup: Rect): Unit {
        let target: Float32 = if (st.volumeOpen) {
            1.0
        } else {
            0.0
        }
        let progress = st.volumeAnim.animate(ctx, target: target)
        let shell = animatedPopupRect(popup, progress)
        // 表面与阴影
        ctx.renderer.fillRoundedRectSoft(shell.shift(0.0, 4.0), 10.0, popupAlpha(ctx.theme.shadow, progress),
            feather: 8.0)
        ctx.renderer.fillRoundedRect(shell, 10.0, popupAlpha(ctx.theme.panelRaised, progress))
        ctx
            .renderer
            .strokeRoundedRect(shell.inset(0.5), 9.5, Pen(width: 1.0, color: popupAlpha(ctx.theme.panelEdge, progress)))
        ctx.renderer.pushClip(shell)
        let pb = model.playback
        // 音量滑条
        let slider = volumeSliderRect(shell)
        let cy = slider.centerY()
        let amount = Float32(max(0.0, min(1.0, pb.volume)))
        let trackColor = if (pb.muted) {
            popupAlpha(ctx.theme.mutedText.withAlpha(60), progress)
        } else {
            popupAlpha(ctx.theme.onMedia.withAlpha(51), progress)
        }
        ctx.renderer.fillRoundedRect(Rect(slider.x, cy - 2.0, slider.w, 4.0), 2.0, trackColor)
        if (amount > 0.0 && !pb.muted) {
            ctx
                .renderer
                .fillRoundedRect(Rect(slider.x, cy - 2.0, slider.w * amount, 4.0), 2.0,
                    popupAlpha(ctx.theme.accent, progress))
            ctx.renderer.fillCircle(slider.x + slider.w * amount, cy, 5.0, popupAlpha(ctx.theme.accent, progress))
        } else if (pb.muted) {
            // 静音时画灰色圆头在 0 位置
            ctx.renderer.fillCircle(slider.x, cy, 5.0, popupAlpha(ctx.theme.mutedText, progress))
        }
        // 音量百分比文本
        let textR = volumeTextRect(shell)
        let volumeText = if (pb.muted) {
            "Muted"
        } else {
            "${Int64(pb.volume * 100.0)}%"
        }
        ctx.renderer.textCenter(volumeText, textR, popupAlpha(ctx.theme.mutedText, progress), pointSize: 10.0)
        ctx.renderer.popClip()
        if (!st.volumeOpen && progress <= 0.0) {
            ctx.requestFrame()
        }
    }

    // ── 面板共用 ──

    // 弹出面板动画矩形：scale + 上移
    private func animatedPopupRect(popup: Rect, progress: Float32): Rect {
        let scale = POPUP_ENTER_SCALE + (1.0 - POPUP_ENTER_SCALE) * progress
        let w = popup.w * scale
        let h = popup.h * scale
        Rect(popup.x + (popup.w - w) / 2.0, popup.y + (popup.h - h) + POPUP_ENTER_OFFSET_Y * (1.0 - progress), w, h)
    }

    // 弹出面板对勾标记
    private func drawPopupCheckmark(ctx: UiContext, row: Rect, color: Color): Unit {
        let cx = row.x + 12.0
        let cy = row.centerY()
        let pen = Pen(width: 1.8, color: color)
        ctx.renderer.strokeLine(cx - 4.5, cy, cx - 1.0, cy + 3.5, pen)
        ctx.renderer.strokeLine(cx - 1.0, cy + 3.5, cx + 5.0, cy - 3.5, pen)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        if (slideT < 0.5) {
            return false
        } // 滑出中/隐藏：点击穿透回翻页区
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (!frame.contains(x, y)) {
                    return false
                }
                claimHovers(ctx, x, y)
                if (ctx.isDragging("reader:dock:bookSeek") && ctx.leftMouseDown) {
                    bookSeekFromX(x)
                    return true
                }
                if (ctx.isDragging("reader:dock:audioSeek") && ctx.leftMouseDown) {
                    audioSeekFromX(x)
                    return true
                }
                if (ctx.isDragging("reader:dock:htmlSeek") && ctx.leftMouseDown) {
                    htmlSeekFromX(x)
                    return true
                }
                return true // 胶囊范围内的移动不穿透（避免误刷 chrome 计时之外的语义）
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (!frame.contains(x, y)) {
                    return false
                }
                if (bookSeekRect.contains(x, y) && active.equals(LaneId.Book)) {
                    ctx.beginDrag("reader:dock:bookSeek")
                    bookSeekFromX(x)
                    return true
                }
                if (audioSeekRect.contains(x, y) && model.playback.durationSec > 0.0 && model.playback.loaded &&
                    isMediaActive()) {
                    ctx.beginDrag("reader:dock:audioSeek")
                    audioSeekFromX(x)
                    return true
                }
                if (htmlSeekRect.contains(x, y) && isHtmlActive()) {
                    ctx.beginDrag("reader:dock:htmlSeek")
                    htmlSeekFromX(x)
                    return true
                }
                return true
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (ctx.isDragging("reader:dock:bookSeek")) {
                    bookSeekFromX(x)
                    return true
                }
                if (ctx.isDragging("reader:dock:audioSeek")) {
                    audioSeekFromX(x)
                    return true
                }
                if (ctx.isDragging("reader:dock:htmlSeek")) {
                    htmlSeekFromX(x)
                    return true
                }
                if (!frame.contains(x, y)) {
                    return false
                }
                // lane tab：只切换展开的控制组，不触碰当前 spread 的媒体生命周期。
                for (i in 0..lanes.size) {
                    if (tabRects[Int64(i)].contains(x, y)) {
                        model.syncReaderLane(lanes[Int64(i)])
                        return true
                    }
                }
                if (active.equals(LaneId.Book)) {
                    match (model.reader.mode) {
                        case ReadingMode.Webtoon => ()
                        case _ =>
                            if (prevRect.contains(x, y)) {
                                model.readerTurnPage(false)
                                return true
                            }
                            if (nextRect.contains(x, y)) {
                                model.readerTurnPage(true)
                                return true
                            }
                    }
                }
                if (isMediaActive()) {
                    if (playRect.contains(x, y)) {
                        model.playback.togglePlay()
                        return true
                    }
                    if (backRect.contains(x, y)) {
                        model.playback.skip(-5.0)
                        return true
                    }
                    if (fwdRect.contains(x, y)) {
                        model.playback.skip(5.0)
                        return true
                    }
                    if (muteRect.contains(x, y)) {
                        toggleVolumePopup(ctx)
                        return true
                    }
                    if (subtitleRect.contains(x, y) && model.playback.isVideo) {
                        toggleSubtitlePopup(ctx)
                        return true
                    }
                }
                if (isHtmlActive()) {
                    let fontTier = htmlFontTierIndex(model.reader.htmlFontSize)
                    let marginTier = htmlMarginTierIndex(model.reader.htmlMargin)
                    if (htmlFontDownRect.contains(x, y) && fontTier > 0) {
                        model.setReaderHtmlFontSize(htmlFontTierPx(fontTier - 1))
                        return true
                    }
                    if (htmlFontUpRect.contains(x, y) && fontTier < 3) {
                        model.setReaderHtmlFontSize(htmlFontTierPx(fontTier + 1))
                        return true
                    }
                    if (htmlMarginDownRect.contains(x, y) && marginTier > 0) {
                        model.setReaderHtmlMargin(htmlMarginTierPx(marginTier - 1))
                        return true
                    }
                    if (htmlMarginUpRect.contains(x, y) && marginTier < 2) {
                        model.setReaderHtmlMargin(htmlMarginTierPx(marginTier + 1))
                        return true
                    }
                }
                return true
            case UiEvent.MouseWheel(_, _, x, y) =>
                // 胶囊上滚轮不翻页（原型 dock 浮于舞台之上，滚动留给滑条语义）。
                frame.contains(x, y)
            case _ => false
        }
    }

    private func isMediaActive(): Bool {
        match (active) {
            case LaneId.Audio(_) => true
            case LaneId.Video(_) => true
            case _ => false
        }
    }

    private func isHtmlActive(): Bool {
        match (active) {
            case LaneId.Html(_) => true
            case _ => false
        }
    }

    private func claimHovers(ctx: UiContext, x: Float32, y: Float32): Unit {
        for (i in 0..lanes.size) {
            if (tabRects[Int64(i)].contains(x, y)) {
                ctx.claimHover("reader:dock:tab:${lanes[Int64(i)].toString()}", CursorShape.Interactive)
            }
        }
        if (htmlSeekRect.contains(x, y) && isHtmlActive()) {
            ctx.claimHover("reader:dock:htmlSeek", CursorShape.Interactive)
        }
        if (isHtmlActive()) {
            let htmlSpots = [("reader:dock:htmlFontDown", htmlFontDownRect), ("reader:dock:htmlFontUp", htmlFontUpRect),
                ("reader:dock:htmlMarginDown", htmlMarginDownRect), ("reader:dock:htmlMarginUp", htmlMarginUpRect)]
            for ((id, rect) in htmlSpots) {
                if (rect.contains(x, y)) {
                    ctx.claimHover(id, CursorShape.Interactive)
                }
            }
        }
        match (model.reader.mode) {
            case ReadingMode.Webtoon => ()
            case _ =>
                if (prevRect.contains(x, y)) {
                    ctx.claimHover("reader:dock:prev", CursorShape.Interactive)
                }
                if (nextRect.contains(x, y)) {
                    ctx.claimHover("reader:dock:next", CursorShape.Interactive)
                }
        }
        let spots = [("reader:dock:back", backRect), ("reader:dock:play", playRect), ("reader:dock:fwd", fwdRect),
            ("reader:dock:mute", muteRect), ("reader:dock:subtitle", subtitleRect),
            ("reader:dock:bookSeek", bookSeekRect), ("reader:dock:audioSeek", audioSeekRect)]
        for ((id, rect) in spots) {
            if (rect.contains(x, y)) {
                ctx.claimHover(id, CursorShape.Interactive)
            }
        }
    }

    // Book 滑条：几何换算成 1 基页码经 gotoPage 落地（gotoPage 回写 readerPageSlider
    // 镜像，双向同步无抖动——不经过 Slider 控件的 State 往返）。
    private func bookSeekFromX(x: Float32): Unit {
        let total = model.reader.displayTotal
        if (total <= 1 || bookSeekRect.w <= 0.0) {
            return
        }
        let amount = Float64(max(0.0, min(1.0, (x - bookSeekRect.x) / bookSeekRect.w)))
        model.gotoPage(1 + Int64(amount * Float64(total - 1) + 0.5))
    }

    private func audioSeekFromX(x: Float32): Unit {
        let dur = model.playback.durationSec
        if (dur <= 0.0 || audioSeekRect.w <= 0.0) {
            return
        }
        let amount = Float64(max(0.0, min(1.0, (x - audioSeekRect.x) / audioSeekRect.w)))
        model.playback.seekTo(amount * dur)
    }

    // html 页内进度条：x 比例 → 可滚范围偏移经 scrollTo 落地（native 侧 clamp）。
    private func htmlSeekFromX(x: Float32): Unit {
        let hp = model.htmlPage
        if (hp.state != "ready" || htmlSeekRect.w <= 0.0) {
            return
        }
        let maxScroll = hp.maxReadingOffset()
        if (maxScroll <= 1.0) {
            return
        }
        let amount = Float64(max(0.0, min(1.0, (x - htmlSeekRect.x) / htmlSeekRect.w)))
        hp.scrollTo(Float32(amount) * maxScroll)
    }
}

// HTML 排版档位 px ⇔ 索引（见 settings.clampHtmlFontSize/clampHtmlMargin）。
func htmlFontTierIndex(px: Int64): Int64 {
    if (px <= 14) {
        0
    } else if (px <= 17) {
        1
    } else if (px <= 20) {
        2
    } else {
        3
    }
}

func htmlFontTierPx(i: Int64): Int64 {
    let tiers: Array<Int64> = [13, 16, 19, 22]
    tiers[Int64(max(0, min(3, i)))]
}

func htmlMarginTierIndex(px: Int64): Int64 {
    if (px <= 36) {
        0
    } else if (px <= 60) {
        1
    } else {
        2
    }
}

func htmlMarginTierPx(i: Int64): Int64 {
    let tiers: Array<Int64> = [24, 48, 72]
    tiers[Int64(max(0, min(2, i)))]
}

// dock 叠层：readerView 的 ZStack 内底部居中（原型 #dock bottom:20px）；
// 隐藏动画播完前保持挂载（slide Spring 在 draw 内推进，停稳后 ReaderDock 自身不绘不吃事件）。
// 注意：VStack/HStack 门面默认 flexible:true——内层 HStack 必须 .hug() 收成内容高（48），
// 否则它与 Spacer 等权瓜分舞台高度并把 ReaderDock 交叉轴拉伸成数百 vp，
// 胶囊底 fillRoundedRect(f, f.h/2) 会画成巨大圆斑（T4 实测回归）。
public func readerDock(model: AppModel): Unit {
    VStack {
        Spacer()
        HStack {
            Spacer()
            ReaderDock(model)
            Spacer()
        }.hug()
    }.padding(0.0, 0.0, 0.0, 20.0)
}
