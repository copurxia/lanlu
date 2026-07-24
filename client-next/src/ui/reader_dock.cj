package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
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
private let DOCK_TAB: Float32 = 36.0
private let DOCK_PAD: Float32 = 6.0
private let DOCK_GAP: Float32 = 4.0

// dock 动画状态：rememberState 跨帧保留（每帧重建的 Widget 只是声明）。
class ReaderDockState {
    // chrome 显隐滑块：初始取当前可见性（静态首帧即停稳，快照稳定，同 Drawer 惯例）。
    let slide: Spring
    // activeLane body 展开度：切 lane 时 reset(0) 重新展开（旧 lane 立即收起，
    // 无交叉宽度过渡——lane 宽度各不相同，简化为只播展开侧）。
    let body = Spring(0.0, stiffness: 260.0, damping: 26.0)
    var lastActiveKey = ""
    // 媒体 lane 出现动画（scale .6→1 + 淡入）的弹簧：按 lane key 驻留，
    // lane 消失后条目留存无害（下次同 lane 再现从停稳值起播）。
    let laneSprings = HashMap<String, Spring>()

    init(chromeVisible: Bool) {
        slide = Spring(if (chromeVisible) { 1.0 } else { 0.0 }, stiffness: 260.0, damping: 26.0)
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

class ReaderDock <: Widget {
    private let model: AppModel
    private let st: ReaderDockState
    private var frame = Rect.zero()
    private var slideT: Float32 = 1.0
    // layout 期算好的热区：lane tab 矩形与 active body 内的控件矩形。
    private let lanes: Array<LaneId>
    private var active: LaneId = LaneId.Book
    private var tabRects = ArrayList<Rect>()
    private var bodyRect = Rect.zero()       // active lane 的 body 裁切框（已乘展开度）
    private var bodyFullRect = Rect.zero()   // body 全宽框（内容定位用）
    private var prevRect = Rect.zero()
    private var nextRect = Rect.zero()
    private var bookSeekRect = Rect.zero()
    private var backRect = Rect.zero()
    private var playRect = Rect.zero()
    private var fwdRect = Rect.zero()
    private var audioSeekRect = Rect.zero()
    private var muteRect = Rect.zero()
    private var subtitleRect = Rect.zero()

    public init(model: AppModel) {
        this.model = model
        st = rememberState<ReaderDockState>("reader:dock",
            {=> ReaderDockState(model.reader.chromeVisible) }).value
        lanes = model.reader.laneSpecs()
        active = model.reader.activeLane
        // 切 lane：body 重新展开（见 ReaderDockState.body 注释）。
        if (active.toString() != st.lastActiveKey) {
            st.lastActiveKey = active.toString()
            st.body.reset(0.0)
        }
        emit(this)
    }

    private func bodyWidth(lane: LaneId): Float32 {
        match (lane) {
            case LaneId.Book => DOCK_BOOK_BODY_W
            case LaneId.Audio(_) => DOCK_AUDIO_BODY_W
            case LaneId.Video(_) => DOCK_VIDEO_BODY_W
        }
    }

    // 内容自然总宽（body 按展开度折算），measure/layout 共用。
    private func contentWidth(bodyT: Float32): Float32 {
        var w = DOCK_PAD * 2.0
        for (i in 0..lanes.size) {
            if (i > 0) { w += DOCK_GAP }
            w += DOCK_TAB
            if (lanes[Int64(i)].equals(active)) {
                w += bodyWidth(active) * bodyT
            }
        }
        w
    }

    public func measure(ctx: UiContext, _: Size): Size {
        // body 展开弹簧在 measure 推进：本帧宽度参与父布局（胶囊随展开平滑变宽）。
        let bodyT = st.body.animate(ctx, target: 1.0)
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
            if (lane.equals(active)) {
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
        }
    }

    public func draw(ctx: UiContext): Unit {
        let visible = model.reader.chromeVisible
        let t = st.slide.animate(ctx, target: if (visible) { 1.0 } else { 0.0 })
        slideT = t
        if (t <= 0.01) { return } // 隐藏停稳：不绘制（事件侧 handle 同步放空）
        let dy = (1.0 - t) * (frame.h + 24.0) // 下滑出屏（原型 chrome-dock-in 反向）
        let alpha = max(0.0, min(1.0, t))
        let a255 = Int64(alpha * 255.0)
        let f = frame.shift(0.0, dy)
        // 胶囊底：半透明毛玻璃语义色（主题翻转由 theme.overlaySurface 自带），圆角 999。
        ctx.renderer.fillRoundedRect(f, f.h / 2.0, fadeColor(ctx.theme.overlaySurface, alpha))
        ctx.renderer.strokeRoundedRect(f.inset(0.5), f.h / 2.0 - 0.5,
            Pen(width: 1.0, color: fadeColor(ctx.theme.overlayBorder, alpha)))
        for (i in 0..lanes.size) {
            let lane = lanes[Int64(i)]
            drawLaneTab(ctx, lane, tabRects[Int64(i)].shift(0.0, dy), a255)
            if (lane.equals(active) && st.body.value > 0.01) {
                ctx.renderer.pushClip(bodyRect.shift(0.0, dy))
                drawLaneBody(ctx, lane, dy, Int64(Float32(a255) * max(0.0, min(1.0, st.body.value))))
                ctx.renderer.popClip()
            }
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
        if (alpha <= 0) { return }
        let cx = rect.centerX()
        let cy = rect.centerY()
        let r = rect.w / 2.0 * scale
        if (isActive) {
            ctx.renderer.fillCircle(cx, cy, r, fadeColor(ctx.theme.accentSoft, Float32(alpha) / 255.0))
        } else if (ctx.isHovered(id)) {
            ctx.renderer.fillCircle(cx, cy, r, fadeColor(ctx.theme.overlayHover, Float32(alpha) / 255.0))
        }
        let color = if (isActive) { ctx.theme.accent.withAlpha(alpha) } else { dimColor(ctx, alpha) }
        drawLaneGlyph(ctx.renderer, lane, cx, cy, color)
    }

    private func drawLaneBody(ctx: UiContext, lane: LaneId, dy: Float32, a: Int64): Unit {
        match (lane) {
            case LaneId.Book => drawBookBody(ctx, dy, a)
            case LaneId.Audio(_) => drawAudioBody(ctx, dy, a)
            case LaneId.Video(_) => drawVideoBody(ctx, dy, a)
        }
    }

    // body 内 30×30 小钮（原型 .lane .icon-btn）：hover 铺圆底，图形由调用方画。
    private func drawBodyButton(ctx: UiContext, rect: Rect, dy: Float32, id: String, a: Int64): Bool {
        let hovered = ctx.isHovered(id)
        if (hovered) {
            ctx.renderer.fillCircle(rect.centerX(), rect.centerY() + dy, rect.w / 2.0,
                fadeColor(ctx.theme.overlayHover, Float32(a) / 255.0))
        }
        hovered
    }

    private func drawBookBody(ctx: UiContext, dy: Float32, a: Int64): Unit {
        let r = model.reader
        let _ = drawBodyButton(ctx, prevRect, dy, "reader:dock:prev", a)
        drawChevronGlyph(ctx.renderer, prevRect.centerX(), prevRect.centerY() + dy, false,
            dimColor(ctx, a))
        let _ = drawBodyButton(ctx, nextRect, dy, "reader:dock:next", a)
        drawChevronGlyph(ctx.renderer, nextRect.centerX(), nextRect.centerY() + dy, true,
            dimColor(ctx, a))
        // 页码滑条（原型 .lane-slider）：轨道 overlayTrack + accent 填充 + 圆头。
        // 显示语义：seamless 开 = segment 内页码/页数（frontend slider 语义），关 = 全局；
        // 虚拟结束页满格 + 「完」。
        let sr = bookSeekRect.shift(0.0, dy)
        let total = r.displayTotal
        let amount: Float32 = if (total > 1) { Float32(r.displayPage - 1) / Float32(total - 1) } else { 1.0 }
        ctx.renderer.fillRoundedRect(Rect(sr.x, sr.centerY() - 2.0, sr.w, 4.0), 2.0,
            fadeColor(ctx.theme.overlayTrack, Float32(a) / 255.0))
        ctx.renderer.fillRoundedRect(Rect(sr.x, sr.centerY() - 2.0, sr.w * amount, 4.0), 2.0,
            ctx.theme.accent.withAlpha(a))
        ctx.renderer.fillCircle(sr.x + sr.w * amount, sr.centerY(), 5.0,
            ctx.theme.accent.withAlpha(a))
        // cur / total（tabular 语义即可，cui 无 font-variant-numeric 原语）。
        let num = if (r.onVirtualEnd) { "完" } else { "${r.displayPage} / ${total}" }
        let nw = ctx.renderer.textWidth(num, pointSize: 12.0)
        let nh = ctx.renderer.textHeight(pointSize: 12.0)
        ctx.renderer.text(num, sr.right() + 6.0 + (70.0 - nw) / 2.0, sr.centerY() - nh / 2.0,
            dimColor(ctx, a), pointSize: 12.0)
    }

    private func drawAudioBody(ctx: UiContext, dy: Float32, a: Int64): Unit {
        let pb = model.playback
        let _ = drawBodyButton(ctx, backRect, dy, "reader:dock:back", a)
        drawSkipSmall(ctx.renderer, backRect.centerX(), backRect.centerY() + dy, -1.0, dimColor(ctx, a))
        let playHover = drawBodyButton(ctx, playRect, dy, "reader:dock:play", a)
        drawPlayPauseGlyph(ctx.renderer, playRect.centerX(), playRect.centerY() + dy, pb.playing,
            if (playHover) { mainColor(ctx, a) } else { dimColor(ctx, a) })
        let _ = drawBodyButton(ctx, fwdRect, dy, "reader:dock:fwd", a)
        drawSkipSmall(ctx.renderer, fwdRect.centerX(), fwdRect.centerY() + dy, 1.0, dimColor(ctx, a))
        // 播放进度：自绘滑条逐帧读 positionSec（playing 时 requestFrame 续帧，
        // 不写 State 避免 60fps 重建）；durationSec==0 禁用。
        drawPlaybackSeekBar(ctx, audioSeekRect.shift(0.0, dy), pb)
        let timeText = "${formatMediaClock(pb.positionSec)}/${if (pb.durationSec > 0.0) { formatMediaClock(pb.durationSec) } else { "--:--" }}"
        let tw = ctx.renderer.textWidth(timeText, pointSize: 12.0)
        let th = ctx.renderer.textHeight(pointSize: 12.0)
        ctx.renderer.text(timeText, audioSeekRect.right() + 6.0 + (88.0 - tw) / 2.0,
            audioSeekRect.centerY() + dy - th / 2.0, dimColor(ctx, a), pointSize: 12.0)
        let _ = drawBodyButton(ctx, muteRect, dy, "reader:dock:mute", a)
        drawMuteGlyph(ctx.renderer, muteRect.centerX(), muteRect.centerY() + dy, pb.muted,
            dimColor(ctx, a))
    }

    private func drawVideoBody(ctx: UiContext, dy: Float32, a: Int64): Unit {
        drawAudioBody(ctx, dy, a)
        let pb = model.playback
        let hover = drawBodyButton(ctx, subtitleRect, dy, "reader:dock:subtitle", a)
        let enabled = pb.subtitleTrackId >= 0
        let color = if (enabled) { ctx.theme.accent.withAlpha(a) } else if (hover) {
            mainColor(ctx, a)
        } else {
            dimColor(ctx, a)
        }
        let label = if (enabled) { "CC·" } else { "CC" }
        let tw = ctx.renderer.textWidth(label, pointSize: 11.0)
        let th = ctx.renderer.textHeight(pointSize: 11.0)
        ctx.renderer.text(label, subtitleRect.centerX() - tw / 2.0,
            subtitleRect.centerY() + dy - th / 2.0, color, pointSize: 11.0)
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

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        if (slideT < 0.5) { return false } // 滑出中/隐藏：点击穿透回翻页区
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (!frame.contains(x, y)) { return false }
                claimHovers(ctx, x, y)
                if (ctx.isDragging("reader:dock:bookSeek") && ctx.leftMouseDown) {
                    bookSeekFromX(x)
                    return true
                }
                if (ctx.isDragging("reader:dock:audioSeek") && ctx.leftMouseDown) {
                    audioSeekFromX(x)
                    return true
                }
                return true // 胶囊范围内的移动不穿透（避免误刷 chrome 计时之外的语义）
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (!frame.contains(x, y)) { return false }
                if (bookSeekRect.contains(x, y) && active.equals(LaneId.Book)) {
                    ctx.beginDrag("reader:dock:bookSeek")
                    bookSeekFromX(x)
                    return true
                }
                if (audioSeekRect.contains(x, y) && model.playback.durationSec > 0.0 &&
                    model.playback.loaded && isMediaActive()) {
                    ctx.beginDrag("reader:dock:audioSeek")
                    audioSeekFromX(x)
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
                if (!frame.contains(x, y)) { return false }
                // lane tab：切换 activeLane（播放联动在 AppModel.syncReaderLane 内）。
                for (i in 0..lanes.size) {
                    if (tabRects[Int64(i)].contains(x, y)) {
                        model.syncReaderLane(lanes[Int64(i)])
                        return true
                    }
                }
                if (active.equals(LaneId.Book)) {
                    if (prevRect.contains(x, y)) {
                        model.readerTurnPage(false)
                        return true
                    }
                    if (nextRect.contains(x, y)) {
                        model.readerTurnPage(true)
                        return true
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
                        model.playback.toggleMute()
                        return true
                    }
                    if (subtitleRect.contains(x, y) && model.playback.isVideo) {
                        model.playback.cycleSubtitleTrack()
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

    private func claimHovers(ctx: UiContext, x: Float32, y: Float32): Unit {
        for (i in 0..lanes.size) {
            if (tabRects[Int64(i)].contains(x, y)) {
                ctx.claimHover("reader:dock:tab:${lanes[Int64(i)].toString()}", CursorShape.Interactive)
            }
        }
        let spots = [("reader:dock:prev", prevRect), ("reader:dock:next", nextRect),
            ("reader:dock:back", backRect), ("reader:dock:play", playRect),
            ("reader:dock:fwd", fwdRect), ("reader:dock:mute", muteRect),
            ("reader:dock:subtitle", subtitleRect),
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
        if (total <= 1 || bookSeekRect.w <= 0.0) { return }
        let amount = Float64(max(0.0, min(1.0, (x - bookSeekRect.x) / bookSeekRect.w)))
        model.gotoPage(1 + Int64(amount * Float64(total - 1) + 0.5))
    }

    private func audioSeekFromX(x: Float32): Unit {
        let dur = model.playback.durationSec
        if (dur <= 0.0 || audioSeekRect.w <= 0.0) { return }
        let amount = Float64(max(0.0, min(1.0, (x - audioSeekRect.x) / audioSeekRect.w)))
        model.playback.seekTo(amount * dur)
    }
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
