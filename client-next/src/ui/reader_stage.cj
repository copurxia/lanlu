package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.percentEncode
import std.collection.ArrayList
import std.math.{cos, sin}

// ── 阅读页舞台（reader-redesign #stage，T2）──
// 自绘而非 PixelImageView 组合：方向性翻页动画（旧页滑出+淡出 / 新页反向滑入，原型
// pg-in/out-r/l/b/t）需要对纹理做位移+alpha 绘制，固定控件路径表达不了。
// 内容分派：图片 spread（单页/双页并排）→ 纹理舞台；音频页/activeLane=Audio →
// 黑胶音频舞台（#page-audio）；video/html 等 → 诚实占位（视频播放后续接入）。
// 动画状态经 rememberState 跨帧保留（每帧重建的只是构建期声明，Tween 对象不重置）。

// ── 长图滚动（frontend .long-page-scroll-container 简化版）──
// 宽适配后的图高（纯函数，可单测）：图按舞台宽等比放大。
func longPageFittedHeight(imgW: Float32, imgH: Float32, frameW: Float32): Float32 {
    if (imgW <= 0.0 || frameW <= 0.0) { return 0.0 }
    imgH * (frameW / imgW)
}

// 最大纵向滚动偏移（纯函数，可单测）：0 = 不溢出（走普通 contain，不启用滚动）。
func longPageMaxOffset(fittedH: Float32, frameH: Float32): Float32 {
    max(0.0, fittedH - frameH)
}

// 滚轮单位 → 滚动像素（无惯性跟手，不做 Spring）。
private let LONG_PAGE_WHEEL_PX: Float32 = 48.0

// 翻页位移向量（纯函数）：新页滑入的来源方向单位向量——LTR forward 从右进 (1,0)、
// RTL forward 从左进 (-1,0)、TTB forward 从下进 (0,1)；旧页滑出恒为反向。
// webtoon 返回零向量：滚动驱动模式不做位移翻页动画（原型 #stage.webtoon 豁免）。
func pageTurnVector(mode: ReadingMode, forward: Bool): (Float32, Float32) {
    match (mode) {
        case ReadingMode.SingleLtr => if (forward) { (1.0, 0.0) } else { (-1.0, 0.0) }
        case ReadingMode.SingleRtl => if (forward) { (-1.0, 0.0) } else { (1.0, 0.0) }
        case ReadingMode.SingleTtb => if (forward) { (0.0, 1.0) } else { (0.0, -1.0) }
        case ReadingMode.Webtoon => (0.0, 0.0)
    }
}

// 翻页动画参数（原型：进 .26s cubic-bezier(.2,.7,.3,1) ≈ easeOutCubic；
// 出 .18s ease-in，Easing 里最近的是 easeInOutCubic）。位移幅度 60vp 同原型。
private let TURN_IN_MS: Int64 = 260
private let TURN_OUT_MS: Int64 = 180
private let TURN_OFFSET: Float32 = 60.0

// 双击缩放倍率（原型 #stage.zoomed scale(2)）：1×/2× 切换，翻页复位。
private let STAGE_ZOOM: Float32 = 2.0

// 舞台动画/交互状态：rememberState 跨帧保留。Tween 在翻页触发时 reset(0) 重新起腿，
// 动画期间连续翻页直接以当前位置为新起点（reset 打断在飞腿，不卡死）。
class ReaderStageState {
    var inited = false
    var lastIndex: Int64 = -1
    var curKeys: Array<String> = []   // 当前 spread 的纹理 key（非图片页为 ""）
    var prevKeys: Array<String> = []  // 上一 spread（滑出层用）
    var dx: Float32 = 0.0
    var dy: Float32 = 0.0
    var zoomed = false
    var vinylAngle: Float64 = 0.0     // 黑胶转角（弧度，播放时按帧钟累积）
    var scrollY: Float32 = 0.0        // 长图滚动偏移（vp；翻页/切 spread 复位）
    let outTween = Tween(TURN_OUT_MS, {t: Float32 => Easing.easeInOutCubic(t)})
    let inTween = Tween(TURN_IN_MS, {t: Float32 => Easing.easeOutCubic(t)})
}

// 页 → 纹理 key / 下载 url（与 app 层 key 约定一致：page:<arcid>:<pagePath>）。
func readerPageKey(arcid: String, pid: String): String {
    "page:${arcid}:${pid}"
}
func readerPageUrl(arcid: String, pid: String): String {
    "/api/archives/${arcid}/page?path=${percentEncode(pid)}"
}

// 带 alpha 的纹理绘制：纹理跨 widget 共享（pixel_texture_cache），setAlpha 后必须复原 255。
private func drawTextureAlpha(ctx: UiContext, tex: Texture, dest: Rect, alpha: Float32): Unit {
    if (alpha >= 0.999) {
        ctx.renderer.texture(tex, dest)
        return
    }
    let a = max(0, min(255, Int64(alpha * 255.0)))
    tex.setAlpha(a)
    ctx.renderer.texture(tex, dest)
    tex.setAlpha(255)
}

// ── 播放器小图标（音频舞台与 dock 共用；IconName 无播放/暂停项，自绘三角/双竖）──

// 播放 ▶ / 暂停 ❚❚：16×16 视觉格，中心 (cx,cy)。
func drawPlayPauseGlyph(renderer: Renderer, cx: Float32, cy: Float32, playing: Bool, color: Color): Unit {
    if (playing) {
        renderer.fillRoundedRect(Rect(cx - 5.0, cy - 6.0, 3.6, 12.0), 1.0, color)
        renderer.fillRoundedRect(Rect(cx + 1.4, cy - 6.0, 3.6, 12.0), 1.0, color)
    } else {
        let pen = Pen(width: 5.0, color: color)
        // 用三条粗线拼实心三角（框架无多边形填充原语）。
        renderer.strokeLine(cx - 3.5, cy - 6.5, cx - 3.5, cy + 6.5, Pen(width: 3.0, color: color))
        renderer.strokeLine(cx - 2.0, cy - 3.8, cx + 4.5, cy, pen)
        renderer.strokeLine(cx - 2.0, cy + 3.8, cx + 4.5, cy, pen)
    }
}

// 静音 🔊/🔇：喇叭（方块 + 锥形）+ 右侧两道声波短线（muted 时打叉）。
// 声波用两条短斜线近似「)」：整圆在小尺寸下会读成 ⟳（T4 快照目检教训）。
func drawMuteGlyph(renderer: Renderer, cx: Float32, cy: Float32, muted: Bool, color: Color): Unit {
    let pen = Pen(width: 1.6, color: color)
    renderer.fill(Rect(cx - 7.0, cy - 3.0, 3.4, 6.0), color)
    renderer.strokeLine(cx - 3.6, cy - 5.5, cx - 0.5, cy - 2.0, Pen(width: 3.2, color: color))
    renderer.strokeLine(cx - 3.6, cy + 5.5, cx - 0.5, cy + 2.0, Pen(width: 3.2, color: color))
    if (muted) {
        renderer.strokeLine(cx + 2.5, cy - 3.5, cx + 7.5, cy + 3.5, pen)
        renderer.strokeLine(cx + 2.5, cy + 3.5, cx + 7.5, cy - 3.5, pen)
    } else {
        renderer.strokeLine(cx + 2.8, cy - 3.2, cx + 4.6, cy, pen)
        renderer.strokeLine(cx + 4.6, cy, cx + 2.8, cy + 3.2, pen)
        renderer.strokeLine(cx + 5.8, cy - 4.6, cx + 8.2, cy, pen)
        renderer.strokeLine(cx + 8.2, cy, cx + 5.8, cy + 4.6, pen)
    }
}

// lane-tab 图形：书 📖 / 胶片 🎬 / 音符 🎵 的矢量等价（原型 emoji 依赖字体，改自绘）。
func drawLaneGlyph(renderer: Renderer, lane: LaneId, cx: Float32, cy: Float32, color: Color): Unit {
    match (lane) {
        case LaneId.Book =>
            // 摊开的书：中缝 + 两页轮廓。
            let pen = Pen(width: 1.4, color: color)
            renderer.strokeLine(cx, cy - 5.5, cx, cy + 5.5, pen)
            renderer.strokeRoundedRect(Rect(cx - 7.0, cy - 5.5, 14.0, 11.0), 1.5, pen)
        case LaneId.Video(_) =>
            // 胶片：圆角框 + 上下两排齿孔。
            let pen = Pen(width: 1.4, color: color)
            renderer.strokeRoundedRect(Rect(cx - 7.0, cy - 5.5, 14.0, 11.0), 2.0, pen)
            renderer.fill(Rect(cx - 4.5, cy - 3.0, 2.2, 2.2), color)
            renderer.fill(Rect(cx + 2.3, cy - 3.0, 2.2, 2.2), color)
            renderer.fill(Rect(cx - 4.5, cy + 0.8, 2.2, 2.2), color)
            renderer.fill(Rect(cx + 2.3, cy + 0.8, 2.2, 2.2), color)
        case LaneId.Audio(_) =>
            // 音符：符头圆 + 符干 + 符尾。
            let pen = Pen(width: 1.5, color: color)
            renderer.fillCircle(cx - 2.5, cy + 4.0, 2.6, color)
            renderer.strokeLine(cx + 0.1, cy + 4.0, cx + 0.1, cy - 6.0, pen)
            renderer.strokeLine(cx + 0.1, cy - 6.0, cx + 5.0, cy - 3.5, pen)
    }
}

// ‹ › 翻页箭头（dock Book lane 用）：forward=true 画 ›（尖朝右），false 画 ‹。
func drawChevronGlyph(renderer: Renderer, cx: Float32, cy: Float32, forward: Bool, color: Color): Unit {
    let pen = Pen(width: 1.8, color: color)
    let s: Float32 = if (forward) { -1.0 } else { 1.0 }
    renderer.strokeLine(cx + 2.5 * s, cy - 5.0, cx - 2.5 * s, cy, pen)
    renderer.strokeLine(cx - 2.5 * s, cy, cx + 2.5 * s, cy + 5.0, pen)
}

// 播放进度滑条（音频舞台/dock 共用自绘）：轨道 4vp + accent 填充 + 圆头。
// 播放中每帧读 playback.positionSec 并 requestFrame 续帧（不写 State，避免 60fps 全树重建）；
// durationSec==0（未知）/未加载时灰显禁用。拖拽几何换算在调用方的 handle 里（Slider 同款）。
func drawPlaybackSeekBar(ctx: UiContext, rect: Rect, pb: PlaybackModel): Unit {
    let cy = rect.centerY()
    let dur = pb.durationSec
    let enabled = dur > 0.0 && pb.loaded
    let amount: Float32 = if (enabled) { Float32(max(0.0, min(1.0, pb.positionSec / dur))) } else { 0.0 }
    let trackColor = if (enabled) { ctx.theme.onMedia.withAlpha(51) } else { ctx.theme.onMedia.withAlpha(25) }
    ctx.renderer.fillRoundedRect(Rect(rect.x, cy - 2.0, rect.w, 4.0), 2.0, trackColor)
    if (amount > 0.0) {
        ctx.renderer.fillRoundedRect(Rect(rect.x, cy - 2.0, rect.w * amount, 4.0), 2.0,
            ctx.theme.accent)
        ctx.renderer.fillCircle(rect.x + rect.w * amount, cy, 5.0, ctx.theme.accent)
    }
    if (pb.playing) { ctx.requestFrame() }
}

// 阅读舞台。请求/预取在 init 发起（与旧 reader_view 的构建期副作用同款：
// imageState 自带去重，重复声明零成本）。
class ReaderStage <: Widget {
    private let model: AppModel
    private let st: ReaderStageState
    private var frame = Rect.zero()
    // 构建期快照：spread 页索引与对应纹理 key（非图片页 key=""）
    private let spreadIdx: Array<Int64>
    private let keys: Array<String>
    // 音频舞台目标页（activeLane=Audio 优先，否则 spread 内首个 audio 页）
    private let audioPage: ?Int64
    private let videoPage: ?Int64
    // 音频舞台交互热区（layout 时算）
    private var vinylRect = Rect.zero()
    private var playRect = Rect.zero()
    private var backRect = Rect.zero()
    private var fwdRect = Rect.zero()
    private var seekRect = Rect.zero()
    // 结束页卡片热区（虚拟页 layout 时算）
    private var endCardRect = Rect.zero()
    private var endOpenRect = Rect.zero()
    private var endDetailRect = Rect.zero()

    public init(model: AppModel) {
        this.model = model
        st = rememberState<ReaderStageState>("reader:stage", {=> ReaderStageState()}).value
        let r = model.reader
        spreadIdx = r.spreadPages()
        let kl = ArrayList<String>()
        var firstRequested = false
        for (i in spreadIdx) {
            match (r.pageAt(i)) {
                case Some(p) =>
                    if (p.pageType == "image" || p.pageType == "") {
                        // 多 segment 拼接后按页取 arcid（页可能属下一档案）。
                        let pageArc = r.arcidOfReal(i)
                        let key = readerPageKey(pageArc, p.id)
                        kl.add(key)
                        if (model.imageState(key).value == "") {
                            // spread 首页是用户正等着的图：高优先级插队；配页低优先级。
                            model.requestImage(key, readerPageUrl(pageArc, p.id),
                                highPriority: !firstRequested)
                            if (!firstRequested) { model.prefetchAround() }
                            firstRequested = true
                        }
                    } else {
                        kl.add("")
                    }
                case None => kl.add("")
            }
        }
        keys = kl.toArray()
        // 音频舞台判定：只看 activeLane（Audio(i) → 该页舞台）。不做「spread 内首个
        // audio 页」兜底——refreshLaneForSpread 在 gotoPage/setPages 内同步执行（moveTo
        // 同步链），UI 重建时 activeLane 已是新 lane，不存在帧延迟；兜底反而让舞台在
        // activeLane=Video 时错显音频舞台、与 dock/播放状态脱节（实机回归）。
        var ap: ?Int64 = None
        match (r.activeLane) {
            case LaneId.Audio(i) => ap = Some(i)
            case _ => ()
        }
        audioPage = ap
        var vp: ?Int64 = None
        match (r.activeLane) {
            case LaneId.Video(i) => vp = Some(i)
            case _ => ()
        }
        videoPage = vp
        // 翻页检测：index（恒为 spread 首页）变化即一次翻页。方向 = 阅读顺序
        //（index 增大 = forward），物理位移向量由模式换算（pageTurnVector）。
        if (!st.inited) {
            st.inited = true
            st.lastIndex = r.index
            st.curKeys = keys
            st.outTween.reset(1.0)
            st.inTween.reset(1.0)
        } else if (r.index != st.lastIndex) {
            let (dx, dy) = pageTurnVector(r.mode, r.index > st.lastIndex)
            st.dx = dx
            st.dy = dy
            st.prevKeys = st.curKeys
            st.curKeys = keys
            st.lastIndex = r.index
            st.zoomed = false // 缩放态翻页时复位（任务约束）
            st.scrollY = 0.0  // 长图滚动偏移随 spread 复位
            st.outTween.reset(0.0)
            st.inTween.reset(0.0)
        } else {
            // 同页重建（图片 ready / 设置变更等）：刷新 key 快照，不动动画。
            st.curKeys = keys
        }
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, available.h)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
        // 音频舞台热区（与 drawAudioStage 的几何保持一致）。
        let d = min(min(frame.h * 0.45, 240.0), frame.w * 0.3)
        vinylRect = Rect(frame.x + 56.0, frame.centerY() - 30.0 - d / 2.0, d, d)
        let rx = vinylRect.right() + 48.0
        let rw = max(0.0, frame.right() - 56.0 - rx)
        let by = frame.centerY() + 46.0
        backRect = Rect(rx, by, 34.0, 34.0)
        playRect = Rect(rx + 42.0, by - 6.0, 46.0, 46.0)
        fwdRect = Rect(rx + 96.0, by, 34.0, 34.0)
        seekRect = Rect(rx + 140.0, by + 7.0, max(0.0, rw - 140.0 - 110.0), 20.0)
        // 结束页卡片：居中 420×320；按钮行在卡内底部（seamless 开时不画但热区保留零值）。
        let cw = min(420.0, frame.w - 48.0)
        let ch = min(320.0, frame.h - 48.0)
        endCardRect = Rect(frame.centerX() - cw / 2.0, frame.centerY() - ch / 2.0, cw, ch)
        endOpenRect = Rect(endCardRect.x + 32.0, endCardRect.bottom() - 64.0, 160.0, 36.0)
        endDetailRect = Rect(endCardRect.right() - 32.0 - 120.0, endCardRect.bottom() - 64.0, 120.0, 36.0)
    }

    public func draw(ctx: UiContext): Unit {
        // 虚拟结束页：绘制结束卡片（替代图片/音频舞台，对齐 frontend
        // ReaderCollectionEndPage，单栏卡片简化版）。
        if (model.reader.onVirtualEnd) {
            ctx.renderer.fill(frame, ctx.theme.stageBg)
            drawCollectionEnd(ctx)
            return
        }
        match (videoPage) {
            case Some(i) =>
                ctx.renderer.fill(frame, Color.rgb(0, 0, 0))
                drawVideoStage(ctx, i)
            case None => match (audioPage) {
            case Some(i) =>
                // 音频舞台恒深（原型 #page-audio：媒体页不随主题翻转）。
                ctx.renderer.fill(frame, Color.rgb(0, 0, 0))
                drawAudioStage(ctx, i)
            case None =>
                ctx.renderer.fill(frame, ctx.theme.stageBg)
                drawImageStage(ctx)
            }
        }
        if (model.readerShowInfo.value) {
            drawMediaInfo(ctx)
        }
    }

    // ── 图片舞台 ──

    private func pageCell(i: Int64): Rect {
        if (keys.size <= 1) { return frame }
        // 双页并排（原型 #stage.double：row + gap 2）；顺序已含 RTL 校正（spreadPages）。
        let w = (frame.w - 2.0) / 2.0
        if (i == 0) {
            Rect(frame.x, frame.y, w, frame.h)
        } else {
            Rect(frame.x + w + 2.0, frame.y, w, frame.h)
        }
    }

    private func drawImageStage(ctx: UiContext): Unit {
        let inT = st.inTween.animate(ctx, target: 1.0)
        let outT = st.outTween.animate(ctx, target: 1.0)
        // 整层裁回舞台：翻页位移（±60vp）会把滑出/滑入层画出 frame
        //（TTB 纵向位移会盖到顶栏/dock 区域），zoom 路径另有 cell 级裁剪。
        ctx.renderer.pushClip(frame)
        // 旧 spread 滑出层（画在下层）：沿阅读方向滑出并淡出。
        if (outT < 1.0 && st.prevKeys.size > 0) {
            let ox = -st.dx * TURN_OFFSET * outT
            let oy = -st.dy * TURN_OFFSET * outT
            drawSpread(ctx, st.prevKeys, ox, oy, 1.0 - outT, false, false)
        }
        // 新 spread 滑入层：从反方向滑入并淡入。
        let ox = st.dx * TURN_OFFSET * (1.0 - inT)
        let oy = st.dy * TURN_OFFSET * (1.0 - inT)
        drawSpread(ctx, keys, ox, oy, inT, st.zoomed, true)
        ctx.renderer.popClip()
    }

    private func drawSpread(ctx: UiContext, ks: Array<String>, ox: Float32, oy: Float32,
        alpha: Float32, zoomed: Bool, curPages: Bool): Unit {
        if (alpha <= 0.0) { return }
        for (i in 0..ks.size) {
            let cell = pageCell(Int64(i))
            let key = ks[i]
            if (key.size == 0) {
                // 非图片页：不参与滑动，静止时静态占位（video/html 等）；
                // 页型按 cell 对应的页索引取（混合 spread 第二格不能拿 spread 首页的）。
                if (curPages && ox == 0.0 && oy == 0.0) {
                    drawUnsupported(ctx, cell, spreadIdx[Int64(i)])
                }
                continue
            }
            let st8 = model.imageState(key).value
            if (st8 == "ready") {
                match (pixelTexture(ctx.renderer, key)) {
                    case Some(tex) =>
                        var dest = fittedRect(Size(tex.width, tex.height), cell, ImageFit.Contain)
                        if (zoomed) {
                            // 双击缩放：目标矩形绕中心放大 + pushClip 裁回 cell
                            //（pixel_image_view.cj zoom 同款几何）。
                            let w = dest.w * STAGE_ZOOM
                            let h = dest.h * STAGE_ZOOM
                            dest = Rect(dest.centerX() - w / 2.0 + ox, dest.centerY() - h / 2.0 + oy, w, h)
                            ctx.renderer.pushClip(cell)
                            drawTextureAlpha(ctx, tex, dest, alpha)
                            ctx.renderer.popClip()
                        } else if (curPages && ox == 0.0 && oy == 0.0 && longPageMax(ctx).isSome()) {
                            // 长图滚动：图按宽适配（顶对齐），垂直偏移 scrollY，
                            // pushClip 裁回舞台；只在动画停稳的当前页启用（滑动层走 contain）。
                            let fittedH = longPageFittedHeight(tex.width, tex.height, frame.w)
                            let maxOff = longPageMaxOffset(fittedH, frame.h)
                            st.scrollY = max(0.0, min(maxOff, st.scrollY))
                            ctx.renderer.pushClip(frame)
                            drawTextureAlpha(ctx, tex,
                                Rect(frame.x, frame.y - st.scrollY, frame.w, fittedH), alpha)
                            ctx.renderer.popClip()
                        } else {
                            drawTextureAlpha(ctx, tex, dest.shift(ox, oy), alpha)
                        }
                    case None => drawPagePlaceholder(ctx, cell.shift(ox, oy), "加载中…")
                }
            } else if (st8 == "error") {
                drawPagePlaceholder(ctx, cell.shift(ox, oy), "加载失败，点击重试")
            } else {
                drawPagePlaceholder(ctx, cell.shift(ox, oy), "加载中…")
            }
        }
    }

    private func drawPagePlaceholder(ctx: UiContext, cell: Rect, text: String): Unit {
        ctx.renderer.textCenter(text, cell, ctx.theme.mutedText, pointSize: 13.0)
    }

    // 非图片/非音频页占位：诚实说明，video 页额外提示后续接入（任务约束）。
    private func drawUnsupported(ctx: UiContext, cell: Rect, pageIdx: Int64): Unit {
        var pt = ""
        match (model.reader.pageAt(pageIdx)) {
            case Some(p) => pt = p.pageType
            case None => ()
        }
        let hint = "该页类型（${pt}）不支持阅读，请翻页"
        ctx.renderer.textCenter(hint, cell, ctx.theme.mutedText, pointSize: 13.0)
    }

    private func drawVideoStage(ctx: UiContext, pageIdx: Int64): Unit {
        let pb = model.playback
        let key = "video:${pb.mediaKey}"
        match (pb.takeVideoFrame()) {
            case Some(video) => registerPixelImage(ctx.renderer, key, video.width, video.height, video.rgba)
            case None => ()
        }
        match (pixelTexture(ctx.renderer, key)) {
            case Some(texture) =>
                ctx.renderer.texture(texture, fittedRect(Size(texture.width, texture.height), frame, ImageFit.Contain))
            case None =>
                var title = "视频"
                match (model.reader.pageAt(pageIdx)) {
                    case Some(p) => title = if (p.title.size > 0) { p.title } else { p.id }
                    case None => ()
                }
                let status = if (pb.error.size > 0) { "加载失败：${pb.error}" }
                    else if (pb.loading) { "正在下载 ${title}…" }
                    else if (pb.loaded) { "点击底部播放按钮" }
                    else { "准备视频…" }
                ctx.renderer.textCenter(status, frame, ctx.theme.onMediaDim, pointSize: 14.0)
        }
        if (pb.playing) { ctx.requestFrame() }
    }

    // ── 音频舞台（原型 #page-audio：黑胶 + 标题 + 进度 + 控制，恒深底）──

    private func drawAudioStage(ctx: UiContext, pageIdx: Int64): Unit {
        let pb = model.playback
        let onMedia = ctx.theme.onMedia
        let onMediaDim = ctx.theme.onMediaDim
        // 黑胶：重复径向纹用同心圆环近似（框架无 repeating-radial-gradient），
        // 中心 accent 圆标 ♪；播放时圆周标记点随帧钟旋转（无旋转原语的替代方案）。
        let cx = vinylRect.centerX()
        let cy = vinylRect.centerY()
        let r = vinylRect.w / 2.0
        ctx.renderer.fillCircle(cx, cy, r, Color.rgb(10, 10, 10))
        var ring: Float32 = r - 8.0
        var dark = true
        while (ring > r * 0.36) {
            ctx.renderer.strokeCircle(cx, cy, ring,
                Pen(width: 3.0, color: if (dark) { Color.rgb(17, 17, 17) } else { Color.rgb(28, 28, 28) }))
            dark = !dark
            ring -= 4.0
        }
        ctx.renderer.fillCircle(cx, cy, r * 0.35, ctx.theme.accent)
        let noteW = ctx.renderer.textWidth("♪", pointSize: 26.0)
        let noteH = ctx.renderer.textHeight(pointSize: 26.0)
        ctx.renderer.text("♪", cx - noteW / 2.0, cy - noteH / 2.0, Color.rgb(20, 14, 4),
            pointSize: 26.0)
        if (pb.playing) {
            // 18s/圈（原型 spin 动画），按帧 delta 累积角度。
            st.vinylAngle += Float64(ctx.frame.deltaMs) / 18000.0 * 6.283185307179586
            let mx = cx + (r - 14.0) * Float32(cos(st.vinylAngle))
            let my = cy + (r - 14.0) * Float32(sin(st.vinylAngle))
            ctx.renderer.fillCircle(mx, my, 3.0, ctx.theme.accent)
            ctx.requestFrame()
        }
        // 右栏：标题（页标题或文件名）+ 状态/时间 + 控制行。
        var title = ""
        match (model.reader.pageAt(pageIdx)) {
            case Some(p) => title = if (p.title.size > 0) { p.title } else { p.id }
            case None => ()
        }
        let rx = vinylRect.right() + 48.0
        ctx.renderer.text(title, rx, frame.centerY() - 78.0, onMedia, pointSize: 20.0)
        let sub = if (pb.error.size > 0) {
            "加载失败：${pb.error}"
        } else if (pb.loading) {
            "下载中…"
        } else if (!pb.loaded) {
            "未加载"
        } else {
            "${formatMediaClock(pb.positionSec)} / ${if (pb.durationSec > 0.0) { formatMediaClock(pb.durationSec) } else { "--:--" }}"
        }
        ctx.renderer.text(sub, rx, frame.centerY() - 48.0, onMediaDim, pointSize: 13.0)
        // 控制行：−5s / 播放钮（accent 圆底反色）/ +5s / 进度条 / 时间。
        drawCircleButton(ctx, backRect, "reader:stage:back", {=> drawSkipGlyph(ctx.renderer, backRect.centerX(), backRect.centerY(), -1.0, onMedia) })
        let playBg = if (ctx.isHovered("reader:stage:play")) { onMedia.withAlpha(220) } else { onMedia }
        ctx.renderer.fillCircle(playRect.centerX(), playRect.centerY(), playRect.w / 2.0, playBg)
        drawPlayPauseGlyph(ctx.renderer, playRect.centerX(), playRect.centerY(), pb.playing,
            Color.rgb(0, 0, 0))
        drawCircleButton(ctx, fwdRect, "reader:stage:fwd", {=> drawSkipGlyph(ctx.renderer, fwdRect.centerX(), fwdRect.centerY(), 1.0, onMedia) })
        // 进度条：durationSec==0（未知）时禁用，只显示已播时长（任务约束）。
        drawPlaybackSeekBar(ctx, seekRect, model.playback)
    }

    // ±5s 跳转图形：双三角 + 竖线（⏮/⏭ 的矢量等价）。
    // ±5s 跳转图形：dir=-1 画 ⏮（竖线在左、双尖朝左 «），dir=+1 画 ⏭（双尖朝右 »、竖线在右）。
    // 尖的方向由两线公共端点（顶点）决定——实现里顶点落在 -dir 侧，故内部取 d=-dir。
    private func drawSkipGlyph(renderer: Renderer, cx: Float32, cy: Float32, dir: Float32, color: Color): Unit {
        let d = -dir
        let pen = Pen(width: 1.8, color: color)
        renderer.strokeLine(cx - 6.5 * d, cy - 6.0, cx - 6.5 * d, cy + 6.0, pen)
        renderer.strokeLine(cx - 5.0 * d, cy, cx + 2.0 * d, cy - 5.0, pen)
        renderer.strokeLine(cx - 5.0 * d, cy, cx + 2.0 * d, cy + 5.0, pen)
        renderer.strokeLine(cx + 2.5 * d, cy, cx + 7.5 * d, cy - 5.0, pen)
        renderer.strokeLine(cx + 2.5 * d, cy, cx + 7.5 * d, cy + 5.0, pen)
    }

    // 圆形热区钮：hover 铺浅色圆底，图标绘制由闭包给（圆底与图标色配对）。
    private func drawCircleButton(ctx: UiContext, rect: Rect, hoverId: String, glyph: () -> Unit): Unit {
        if (ctx.isHovered(hoverId)) {
            ctx.renderer.fillCircle(rect.centerX(), rect.centerY(), rect.w / 2.0,
                ctx.theme.onMedia.withAlpha(30))
        }
        glyph()
    }

    // ── 虚拟结束页卡片（ReaderCollectionEndPage 单栏简化版）──
    // 「已读完《X》」+ 下一档案信息（中间虚拟页 = 流内下一 segment；末尾虚拟页 =
    // AppModel 解析候选/加载态/失败态）+ 操作按钮（seamless 关：打开下一档案/查看详情）。
    private func drawCollectionEnd(ctx: UiContext): Unit {
        let r = model.reader
        let c = endCardRect
        ctx.renderer.fillRoundedRect(c, 14.0, ctx.theme.panel)
        ctx.renderer.strokeRoundedRect(c.inset(0.5), 13.5, Pen(width: 1.0, color: ctx.theme.panelEdge))
        var y = c.y + 36.0
        ctx.renderer.textCenter("已读完", Rect(c.x, y, c.w, 24.0), ctx.theme.text, pointSize: 17.0)
        y += 32.0
        // 本 segment 标题：segment 回填优先，元数据兜底。
        var title = r.activeSegmentTitle
        if (title.size == 0) {
            match (model.meta.value) {
                case Some(m) => if (m.arcid == model.readerArcid) { title = m.title }
                case None => ()
            }
        }
        ctx.renderer.textCenter("《${title}》", Rect(c.x + 24.0, y, c.w - 48.0, 20.0),
            ctx.theme.mutedText, pointSize: 13.0)
        y += 48.0
        // 下一档案行：可选封面（AppModel 解析候选后经 asset 管线请求）+ 状态文案。
        let nextTitle = r.nextSegmentTitle
        if (nextTitle.size > 0) {
            drawNextLine(ctx, y, "下一档案：${nextTitle}", true)
        } else if (r.appendError.size > 0) {
            drawNextLine(ctx, y, r.appendError, false)
        } else if (r.seamlessNext) {
            drawNextLine(ctx, y, "正在加载下一档案…", false)
        } else if (model.readerNextTitle.value.size > 0) {
            drawNextLine(ctx, y, "下一档案：${model.readerNextTitle.value}", true)
        } else {
            drawNextLine(ctx, y, "正在解析下一档案…", false)
        }
        // 按钮（seamless 关）：打开下一档案（候选未解析到时灰显）/ 查看详情。
        if (!r.seamlessNext) {
            drawEndButton(ctx, endOpenRect, "reader:end:open", "打开下一档案",
                model.hasNextCandidate(), true)
            drawEndButton(ctx, endDetailRect, "reader:end:detail", "查看详情", true, false)
        }
    }

    private func drawNextLine(ctx: UiContext, y: Float32, text: String, cover: Bool): Unit {
        let c = endCardRect
        var tx = c.x + 32.0
        // 候选封面 48×64（asset 管线；未就绪/无封面跳过不编）。
        if (cover && model.readerNextCoverKey.size > 0 &&
            model.imageState(model.readerNextCoverKey).value == "ready") {
            match (pixelTexture(ctx.renderer, model.readerNextCoverKey)) {
                case Some(tex) =>
                    let dest = fittedRect(Size(tex.width, tex.height), Rect(tx, y - 8.0, 48.0, 64.0),
                        ImageFit.Cover)
                    ctx.renderer.pushClip(Rect(tx, y - 8.0, 48.0, 64.0))
                    ctx.renderer.texture(tex, dest)
                    ctx.renderer.popClip()
                    tx += 60.0
                case None => ()
            }
        }
        let th = ctx.renderer.textHeight(pointSize: 13.0)
        ctx.renderer.text(text, tx, y + 24.0 - th / 2.0, ctx.theme.text, pointSize: 13.0)
    }

    // 结束页按钮：主操作 accent 底 / 次操作 field 底；disabled 灰显不响应。
    private func drawEndButton(ctx: UiContext, rect: Rect, hoverId: String, label: String,
        enabled: Bool, primary: Bool): Unit {
        let hovered = enabled && ctx.isHovered(hoverId)
        let bg = if (!enabled) {
            ctx.theme.field
        } else if (primary) {
            if (hovered) { ctx.theme.accent.withAlpha(220) } else { ctx.theme.accent }
        } else {
            if (hovered) { ctx.theme.overlayHover } else { ctx.theme.field }
        }
        ctx.renderer.fillRoundedRect(rect, 9.0, bg)
        let fg = if (!enabled) { ctx.theme.mutedText }
                 else if (primary) { ctx.theme.accentText }
                 else { ctx.theme.text }
        ctx.renderer.textCenter(label, rect, fg, pointSize: 13.0)
    }

    // ── 媒体信息浮层（原型 #media-info；readerShowInfo 开时显示，左下角小字半透明底）──

    private func drawMediaInfo(ctx: UiContext): Unit {
        if (model.reader.onVirtualEnd) { return } // 结束页无媒体信息
        var parts = ArrayList<String>()
        parts.add("p.${model.reader.displayPage}")
        let realIdx = match (model.reader.currentReal) {
            case Some(i) => i
            case None => return
        }
        match (model.reader.pageAt(realIdx)) {
            case Some(p) =>
                parts.add(if (p.pageType.size > 0) { p.pageType } else { "image" })
                if (p.pageType == "image" || p.pageType == "") {
                    let key = readerPageKey(model.reader.arcidOfReal(realIdx), p.id)
                    match (pixelTexture(ctx.renderer, key)) {
                        case Some(tex) => parts.add("${Int64(tex.width)}×${Int64(tex.height)}")
                        case None => ()
                    }
                    // 加载态：没有「缓存命中/解码耗时」数据源，只报真实状态。
                    let st8 = model.imageState(key).value
                    parts.add(match (st8) {
                        case "ready" => "已解码"
                        case "error" => "加载失败"
                        case "loading" => "下载中"
                        case _ => "排队中"
                    })
                }
            case None => ()
        }
        let sb = StringBuilder()
        for (i in 0..parts.size) {
            if (i > 0) { sb.append(" · ") }
            sb.append(parts[Int64(i)])
        }
        let text = sb.toString()
        let ps: Float32 = 11.5
        let tw = ctx.renderer.textWidth(text, pointSize: ps)
        let th = ctx.renderer.textHeight(pointSize: ps)
        let box = Rect(frame.x + 12.0, frame.bottom() - 12.0 - th - 14.0, tw + 24.0, th + 14.0)
        ctx.renderer.fillRoundedRect(box, 10.0, ctx.theme.overlaySurface)
        ctx.renderer.strokeRoundedRect(box.inset(0.5), 9.5, Pen(width: 1.0, color: ctx.theme.overlayBorder))
        ctx.renderer.text(text, box.x + 12.0, box.y + 7.0, ctx.theme.onOverlayDim, pointSize: ps)
    }

    // ── 事件：滚轮（长图滚动/翻页）+ 双击缩放 + 失败页点击重试 + 音频舞台控制 ──

    // 长图滚动生效判定：longPage 开 + 单页图片 + 非 webtoon + 未放大 + 宽适配后高度
    // 溢出舞台。返回最大滚动偏移；不启用返回 None（双页 spread/音频页/未就绪天然不满足）。
    private func longPageMax(ctx: UiContext): ?Float32 {
        let r = model.reader
        if (!r.longPage || keys.size != 1 || st.zoomed) { return None }
        match (r.mode) {
            case ReadingMode.Webtoon => return None
            case _ => ()
        }
        let key = keys[0]
        if (key.size == 0 || model.imageState(key).value != "ready") { return None }
        match (pixelTexture(ctx.renderer, key)) {
            case Some(tex) =>
                let maxOff = longPageMaxOffset(longPageFittedHeight(tex.width, tex.height, frame.w), frame.h)
                if (maxOff > 0.0) { Some(maxOff) } else { None }
            case None => None
        }
    }

    // 滚轮翻页：webtoon 维持旧 gotoPage ±1 整页步进（turnPage 对 webtoon 豁免）；
    // 其余模式走 spread 步进。
    private func wheelTurn(forward: Bool): Unit {
        match (model.reader.mode) {
            case ReadingMode.Webtoon =>
                model.gotoPage(model.readerIndex.value + if (forward) { 1 } else { -1 })
            case _ => model.readerTurnPage(forward)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseWheel(_, dy, x, y) =>
                if (!frame.contains(x, y)) { return false }
                model.noteReaderActivity()
                // 长图滚动：滚轮先滚图；滚到顶再向上 → 上一页、滚到底再向下 → 下一页
                //（frontend 边缘倒计时 toast 省略：直接翻页）。滚动跟手无惯性。
                match (longPageMax(ctx)) {
                    case Some(maxOff) =>
                        if (dy > 0.0) {
                            if (st.scrollY >= maxOff - 0.5) { wheelTurn(true) }
                            else { st.scrollY = min(maxOff, st.scrollY + dy * LONG_PAGE_WHEEL_PX) }
                        } else if (dy < 0.0) {
                            if (st.scrollY <= 0.5) { wheelTurn(false) }
                            else { st.scrollY = max(0.0, st.scrollY + dy * LONG_PAGE_WHEEL_PX) }
                        }
                    case None =>
                        if (dy > 0.0) { wheelTurn(true) } else if (dy < 0.0) { wheelTurn(false) }
                }
                return true
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                // 双击缩放（cui 自带 clickCount：2=双击，见 UiContext）：
                // 仅图片舞台且设置开启时 1×/2× 切换。消费 MouseDown 不阻断配套
                // MouseUp——中央区双击=chrome 两次翻转（净零）+缩放切换，可接受。
                if (audioPage.isNone() && videoPage.isNone() && model.reader.doubleTapZoom && ctx.clickCount >= 2 &&
                    frame.contains(x, y)) {
                    st.zoomed = !st.zoomed
                    return true
                }
                // 音频舞台：播放/±5s 按下即生效；进度条按下起拖。
                if (audioPage.isSome() || videoPage.isSome()) {
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
                    if (seekRect.contains(x, y) && model.playback.durationSec > 0.0 &&
                        model.playback.loaded) {
                        ctx.beginDrag("reader:stage:seek")
                        seekFromX(x, seekRect)
                        return true
                    }
                }
            case UiEvent.MouseMove(x, y) =>
                if (model.reader.onVirtualEnd && !model.reader.seamlessNext) {
                    if (endOpenRect.contains(x, y) && model.hasNextCandidate()) {
                        ctx.claimHover("reader:end:open", CursorShape.Interactive)
                    }
                    if (endDetailRect.contains(x, y)) {
                        ctx.claimHover("reader:end:detail", CursorShape.Interactive)
                    }
                }
                if (audioPage.isSome() || videoPage.isSome()) {
                    if (playRect.contains(x, y)) { ctx.claimHover("reader:stage:play", CursorShape.Interactive) }
                    if (backRect.contains(x, y)) { ctx.claimHover("reader:stage:back", CursorShape.Interactive) }
                    if (fwdRect.contains(x, y)) { ctx.claimHover("reader:stage:fwd", CursorShape.Interactive) }
                    if (seekRect.contains(x, y)) { ctx.claimHover("reader:stage:seek", CursorShape.Interactive) }
                    if (ctx.isDragging("reader:stage:seek") && ctx.leftMouseDown) {
                        seekFromX(x, seekRect)
                        return true
                    }
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                // 结束页卡片按钮（seamless 开时按钮未绘制，热区不响应）。
                if (model.reader.onVirtualEnd && !model.reader.seamlessNext) {
                    if (endOpenRect.contains(x, y) && model.hasNextCandidate()) {
                        model.openReaderNext()
                        return true
                    }
                    if (endDetailRect.contains(x, y)) {
                        model.openDetail(model.readerArcid)
                        return true
                    }
                }
                if (ctx.isDragging("reader:stage:seek")) {
                    seekFromX(x, seekRect)
                    return true
                }
                // 失败页点击重试：命中当前 spread 内 error 页 cell 才消费，
                // 否则穿透给底层翻页/chrome 点击区（与旧视图层级语义一致）。
                if (audioPage.isNone() && videoPage.isNone() && frame.contains(x, y)) {
                    for (i in 0..keys.size) {
                        let key = keys[i]
                        if (key.size > 0 && model.imageState(key).value == "error" &&
                            pageCell(Int64(i)).contains(x, y)) {
                            match (model.reader.pageAt(spreadIdx[Int64(i)])) {
                                case Some(p) =>
                                    model.retryImage(key, readerPageUrl(model.reader.arcid, p.id))
                                    return true
                                case None => ()
                            }
                        }
                    }
                }
            case _ => ()
        }
        false
    }

    private func seekFromX(x: Float32, rect: Rect): Unit {
        let dur = model.playback.durationSec
        if (dur <= 0.0 || rect.w <= 0.0) { return }
        let amount = Float64(max(0.0, min(1.0, (x - rect.x) / rect.w)))
        model.playback.seekTo(amount * dur)
    }
}
