package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.percentEncode
import std.collection.ArrayList
import std.math.abs

// ── 阅读页舞台（reader-redesign #stage，T2）──
// 自绘而非 PixelImageView 组合：方向性翻页动画（旧页滑出+淡出 / 新页反向滑入，原型
// pg-in/out-r/l/b/t）需要对纹理做位移+alpha 绘制，固定控件路径表达不了。
// 内容分派：图片 spread（单页/双页并排）→ 纹理舞台；音频页/activeLane=Audio →
// 黑胶音频舞台（#page-audio）；video/html 等 → 诚实占位（视频播放后续接入）。
// 动画状态经 rememberState 跨帧保留（每帧重建的只是构建期声明，Tween 对象不重置）。

// ── 长图滚动（frontend .long-page-scroll-container 简化版）──
// 宽适配后的图高（纯函数，可单测）：图按舞台宽等比放大。
func longPageFittedHeight(imgW: Float32, imgH: Float32, frameW: Float32): Float32 {
    if (imgW <= 0.0 || frameW <= 0.0) {
        return 0.0
    }
    imgH * (frameW / imgW)
}

// 最大纵向滚动偏移（纯函数，可单测）：0 = 不溢出（走普通 contain，不启用滚动）。
func longPageMaxOffset(fittedH: Float32, frameH: Float32): Float32 {
    max(0.0, fittedH - frameH)
}

// 滚轮单位 → 滚动目标距离；实际位置由 SmoothScroll 的 ease-out 曲线追踪。
private let LONG_PAGE_WHEEL_PX: Float32 = 48.0

// 条漫滚动与 CUI 其他滚动容器保持同一手感（一个滚轮刻度 72vp）。内容宽度对齐
// frontend：桌面最多 800px，两侧各留 16px 安全边距；窄窗口占满可用宽度。
private let WEBTOON_WHEEL_PX: Float32 = 72.0
private let WEBTOON_MAX_WIDTH: Float32 = 800.0
private let WEBTOON_SIDE_PADDING: Float32 = 16.0
private let WEBTOON_MIN_PAGE_HEIGHT: Float32 = 100.0

func webtoonContentWidth(frameW: Float32): Float32 {
    max(1.0, min(WEBTOON_MAX_WIDTH, frameW - WEBTOON_SIDE_PADDING * 2.0))
}

func webtoonEstimatedHeight(contentW: Float32, viewportH: Float32): Float32 {
    max(WEBTOON_MIN_PAGE_HEIGHT, min(viewportH * 0.7, contentW * 1.5))
}

func webtoonImageHeight(imgW: Float32, imgH: Float32, contentW: Float32, fallback: Float32): Float32 {
    if (imgW <= 0.0 || imgH <= 0.0 || contentW <= 0.0) {
        return fallback
    }
    max(WEBTOON_MIN_PAGE_HEIGHT, imgH * contentW / imgW)
}

// frontend 以 scrollTop + viewport*0.3 作为当前页阈值；这里保留相同语义。
func webtoonIndexAtOffset(heights: Array<Float32>, offset: Float32): Int64 {
    if (heights.size == 0) {
        return 0
    }
    let target = max(0.0, offset)
    var top: Float32 = 0.0
    for (i in 0..heights.size) {
        let bottom = top + max(0.0, heights[i])
        if (target < bottom) {
            return Int64(i)
        }
        top = bottom
    }
    heights.size - 1
}

func webtoonContentHeight(heights: Array<Float32>): Float32 {
    var total: Float32 = 0.0
    for (height in heights) {
        total += max(0.0, height)
    }
    total
}

func webtoonOffsetBefore(heights: Array<Float32>, index: Int64): Float32 {
    var total: Float32 = 0.0
    let end = max(0, min(index, heights.size))
    for (i in 0..end) {
        total += max(0.0, heights[i])
    }
    total
}

// 只物化可视区附近页面：与 frontend 相同取上下各 3 屏缓冲，并额外扩 4 页，
// 既覆盖快速滚轮/触控板跳跃，也不会把整本档案一次加入图片下载队列。
func webtoonLazyRange(heights: Array<Float32>, scroll: Float32, viewportH: Float32): (Int64, Int64) {
    if (heights.size == 0) {
        return (0, -1)
    }
    let buffer = max(0.0, viewportH) * 3.0
    let first = max(0, webtoonIndexAtOffset(heights, max(0.0, scroll - buffer)) - 4)
    let last = min(heights.size - 1, webtoonIndexAtOffset(heights, scroll + max(0.0, viewportH) + buffer) + 4)
    (first, last)
}

// 翻页位移向量（纯函数）：新页滑入的来源方向单位向量——LTR forward 从右进 (1,0)、
// RTL forward 从左进 (-1,0)、TTB forward 从下进 (0,1)；旧页滑出恒为反向。
// webtoon 返回零向量：滚动驱动模式不做位移翻页动画（原型 #stage.webtoon 豁免）。
func pageTurnVector(mode: ReadingMode, forward: Bool): (Float32, Float32) {
    match (mode) {
        case ReadingMode.SingleLtr =>
            if (forward) {
                (1.0, 0.0)
            } else {
                (-1.0, 0.0)
            }
        case ReadingMode.SingleRtl =>
            if (forward) {
                (-1.0, 0.0)
            } else {
                (1.0, 0.0)
            }
        case ReadingMode.SingleTtb =>
            if (forward) {
                (0.0, 1.0)
            } else {
                (0.0, -1.0)
            }
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

// ── html 页拖动滚动（M3.2）──
// 拖动直接 scrollTo（跟手）；松手时速度达阈值才起惯性：目标位移 = 速度 × 时间窗，
// ease-out 曲线追踪（与 SmoothScroll/CUI 滚动条同一手感）。
private let HTML_FLING_MS: Int64 = 220
private let HTML_FLING_VELOCITY_THRESHOLD: Float32 = 0.4 // px/ms（400px/s）

// 滚轮在 html 页边界外溢翻页的冷却判定（纯函数，可单测）：距上次外溢不足冷却窗
// 则吞掉本次（防连续滚轮在边界误翻多页）。
func htmlOverflowTurnAllowed(lastMs: Int64, now: Int64, cooldownMs: Int64): Bool {
    now - lastMs >= cooldownMs
}

// 舞台动画/交互状态：rememberState 跨帧保留。Tween 在翻页触发时 reset(0) 重新起腿，
// 动画期间连续翻页直接以当前位置为新起点（reset 打断在飞腿，不卡死）。
class ReaderStageState {
    var inited = false
    var lastIndex: Int64 = -1
    var curKeys: Array<String> = [] // 当前 spread 的纹理 key（非图片页为 ""）
    var prevKeys: Array<String> = [] // 上一 spread（滑出层用）
    var dx: Float32 = 0.0
    var dy: Float32 = 0.0
    var zoomed = false
    let scrollY = State<Float32>(0.0) // 长图滚动偏移（vp；翻页/切 spread 复位）
    let longPageMotion = SmoothScroll(0.0)
    // 条漫是一个完整流的连续滚动面，不复用逐页 scrollY。scroll 自身是 State，滚轮
    // 写入后即触发下一帧重建；其余几何缓存随 ReaderStage 重建继续保留。
    let webtoonScroll = State<Float32>(0.0)
    let webtoonMotion = SmoothScroll(0.0)
    let webtoonBar = ScrollBar("reader:stage:webtoon:bar")
    var webtoonHeights: Array<Float32> = []
    var webtoonArchive = ""
    var webtoonContentW: Float32 = 0.0
    var webtoonViewportH: Float32 = 720.0
    var webtoonSyncedIndex: Int64 = -1
    var wasWebtoon = false
    var webtoonZoomIndex: Int64 = -1
    var webtoonZoomOriginX: Float32 = 0.5
    var webtoonZoomOriginY: Float32 = 0.5
    var lastLyricIndex: Int64 = -2
    var lastVideoGeneration: UInt64 = 0 // 视频舞台已见的帧代际（新帧驱动续帧用）
    var lastHtmlGeneration: UInt64 = 0 // html 舞台已见的帧代际（新帧驱动续帧用）
    var lastHtmlOverflowMs: Int64 = -10000 // html 滚动边界外溢翻页的冷却基准

    // html 页拖动/惯性状态（M3.2）：拖动记录起点与速度；松手后 ease-out 续滚。
    var htmlDragActive = false
    var htmlDragStartY: Float32 = 0.0
    var htmlDragStartScroll: Float32 = 0.0
    var htmlDragLastY: Float32 = 0.0
    var htmlDragLastMs: Int64 = 0
    var htmlDragVelocity: Float32 = 0.0
    var htmlDragMoved = false
    var htmlFlingActive = false
    var htmlFlingStart: Float32 = 0.0
    var htmlFlingDelta: Float32 = 0.0
    let htmlFlingTween = Tween(HTML_FLING_MS, {t: Float32 => Easing.easeOutCubic(t)})
    let lyricFocusTween = Tween(220, {t: Float32 => Easing.easeOutCubic(t)})
    let outTween = Tween(TURN_OUT_MS, {t: Float32 => Easing.easeInOutCubic(t)})
    let inTween = Tween(TURN_IN_MS, {t: Float32 => Easing.easeOutCubic(t)})
}

// 音频舞台只在这里决定区域关系。各绘制函数只使用自己的 Rect，避免封面、歌词、
// 元信息和控制条通过同一组绝对坐标互相侵占。
class AudioStageLayout {
    var scene = Rect.zero()
    var hero = Rect.zero()
    var cover = Rect.zero()
    var meta = Rect.zero()
    var lyrics = Rect.zero()
    var transport = Rect.zero()
    var back = Rect.zero()
    var play = Rect.zero()
    var forward = Rect.zero()
    var seek = Rect.zero()
    var mute = Rect.zero()
    var volume = Rect.zero()

    func resolve(frame: Rect): Unit {
        let pad: Float32 = 48.0
        if (frame.w >= 900.0 && frame.h >= 520.0) {
            // 桌面横屏：内容网格垂直居中；Transport 是跨栏的独立底层。
            // 为全局 lane dock 留出底部安全区，舞台 Transport 不与其重叠。
            transport = Rect(frame.x + pad, frame.bottom() - 122.0, frame.w - pad * 2.0, 52.0)
            scene = Rect(frame.x + pad, frame.y + 32.0, frame.w - pad * 2.0, max(0.0, transport.y - frame.y - 48.0))
            let leftW = min(400.0, max(300.0, scene.w * 0.32))
            hero = Rect(scene.x, scene.y, leftW, scene.h)
            lyrics = Rect(hero.right() + 40.0, scene.y, max(0.0, scene.right() - hero.right() - 40.0), scene.h)
            let coverSide = min(min(280.0, hero.w), max(164.0, hero.h - 110.0))
            let groupH = coverSide + 76.0
            let groupY = hero.centerY() - groupH / 2.0
            cover = Rect(hero.centerX() - coverSide / 2.0, groupY, coverSide, coverSide)
            meta = Rect(hero.x, cover.bottom() + 16.0, hero.w, 60.0)
        } else {
            // 紧凑窗口：上方封面/信息，中部歌词，下方控制条。
            hero = Rect(frame.x + 24.0, frame.y + 24.0, frame.w - 48.0, min(230.0, frame.h * 0.38))
            let coverSide = min(hero.h, min(190.0, hero.w * 0.34))
            cover = Rect(hero.x, hero.y, coverSide, coverSide)
            meta = Rect(cover.right() + 20.0, hero.y, max(0.0, hero.right() - cover.right() - 20.0), hero.h)
            transport = Rect(frame.x + 24.0, frame.bottom() - 116.0, frame.w - 48.0, 52.0)
            scene = Rect(frame.x + 24.0, frame.y + 24.0, frame.w - 48.0, max(0.0, transport.y - frame.y - 40.0))
            lyrics = Rect(frame.x + 24.0, hero.bottom() + 16.0, frame.w - 48.0,
                max(0.0, transport.y - hero.bottom() - 32.0))
        }
        let cy = transport.centerY()
        back = Rect(transport.x, cy - 17.0, 34.0, 34.0)
        play = Rect(transport.x + 42.0, cy - 22.0, 44.0, 44.0)
        forward = Rect(transport.x + 94.0, cy - 17.0, 34.0, 34.0)
        mute = Rect(transport.right() - 148.0, cy - 17.0, 34.0, 34.0)
        volume = Rect(transport.right() - 106.0, cy - 10.0, 106.0, 20.0)
        seek = Rect(transport.x + 184.0, cy - 10.0, max(0.0, mute.x - transport.x - 232.0), 20.0)
    }
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
        case LaneId.Html(_) =>
            // HTML 文档：H 形（左竖 + 中横 + 右竖），与书/胶片/音符同规格视觉格。
            let pen = Pen(width: 1.4, color: color)
            renderer.strokeLine(cx - 5.0, cy - 5.5, cx - 5.0, cy + 5.5, pen)
            renderer.strokeLine(cx - 5.0, cy, cx + 5.0, cy, pen)
            renderer.strokeLine(cx + 5.0, cy - 5.5, cx + 5.0, cy + 5.5, pen)
    }
}

// ‹ › 翻页箭头（dock Book lane 用）：forward=true 画 ›（尖朝右），false 画 ‹。
func drawChevronGlyph(renderer: Renderer, cx: Float32, cy: Float32, forward: Bool, color: Color): Unit {
    let pen = Pen(width: 1.8, color: color)
    let s: Float32 = if (forward) {
        -1.0
    } else {
        1.0
    }
    renderer.strokeLine(cx + 2.5 * s, cy - 5.0, cx - 2.5 * s, cy, pen)
    renderer.strokeLine(cx - 2.5 * s, cy, cx + 2.5 * s, cy + 5.0, pen)
}

// 播放进度滑条（音频舞台/dock 共用自绘）：轨道 4vp + accent 填充 + 圆头。
// 播放中每帧读 playback.positionSec 并以 250ms 定时帧请求续帧（不写 State，避免全树重建；
// 进度条与 mm:ss 时钟的可见精度远低于 60fps，4Hz 足够）。durationSec==0（未知）/未加载时灰显禁用。
// 拖拽几何换算在调用方的 handle 里（Slider 同款）。
func drawPlaybackSeekBar(ctx: UiContext, rect: Rect, pb: PlaybackModel): Unit {
    let cy = rect.centerY()
    let dur = pb.durationSec
    let enabled = dur > 0.0 && pb.loaded
    let amount: Float32 = if (enabled) {
        Float32(max(0.0, min(1.0, pb.positionSec / dur)))
    } else {
        0.0
    }
    let trackColor = if (enabled) {
        ctx.theme.onMedia.withAlpha(51)
    } else {
        ctx.theme.onMedia.withAlpha(25)
    }
    ctx.renderer.fillRoundedRect(Rect(rect.x, cy - 2.0, rect.w, 4.0), 2.0, trackColor)
    if (amount > 0.0) {
        ctx.renderer.fillRoundedRect(Rect(rect.x, cy - 2.0, rect.w * amount, 4.0), 2.0, ctx.theme.accent)
        ctx.renderer.fillCircle(rect.x + rect.w * amount, cy, 5.0, ctx.theme.accent)
    }
    if (pb.playing) {
        ctx.requestFrameAfter(250)
    }
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
    // 音频/视频舞台目标页只由当前 spread 决定，dock lane 仅控制哪组控件展开。
    private let audioPage: ?Int64
    private var audioCoverKey: String = ""
    private var audioBackdropKey: String = ""
    private let videoPage: ?Int64
    private let htmlPage: ?Int64
    // 音频舞台交互热区（layout 时算）
    private let audioLayout = AudioStageLayout()
    private var playRect = Rect.zero()
    private var backRect = Rect.zero()
    private var fwdRect = Rect.zero()
    private var seekRect = Rect.zero()
    private var muteRect = Rect.zero()
    private var volumeRect = Rect.zero()
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
                            model.requestImage(key, readerPageUrl(pageArc, p.id), highPriority: !firstRequested)
                            if (!firstRequested) {
                                model.prefetchAround()
                            }
                            firstRequested = true
                        }
                    } else {
                        kl.add("")
                    }
                case None => kl.add("")
            }
        }
        keys = kl.toArray()
        // 内容舞台不能读取 activeLane：切 Book/媒体 lane 只展开控制条，不切换页面内容。
        var ap: ?Int64 = None
        let mediaLane = r.spreadMediaLane()
        match (mediaLane) {
            case LaneId.Audio(i) => ap = Some(i)
            case _ => ()
        }
        audioPage = ap
        match (ap) {
            case Some(i) => match (r.pageAt(i)) {
                case Some(p) =>
                    if (p.thumbAssetId > 0) {
                        audioCoverKey = "asset:${p.thumbAssetId}"
                        audioBackdropKey = model.requestAudioBackdrop(p.thumbAssetId)
                        if (model.imageState(audioCoverKey).value == "") {
                            model.requestImage(audioCoverKey, "/api/assets/${p.thumbAssetId}", highPriority: true)
                        }
                    }
                case None => ()
            }
            case None => ()
        }
        var vp: ?Int64 = None
        match (mediaLane) {
            case LaneId.Video(i) => vp = Some(i)
            case _ => ()
        }
        videoPage = vp
        // html 页与媒体舞台共享独占语义：spread 有媒体 lane 时让位，
        // 仅 Html lane 时 html 单独成舞台。
        var hp: ?Int64 = None
        match (mediaLane) {
            case LaneId.Html(_) => hp = r.spreadHtmlPage()
            case _ => ()
        }
        htmlPage = hp
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
            st.scrollY.value = 0.0 // 长图滚动偏移随 spread 复位
            st.outTween.reset(0.0)
            st.inTween.reset(0.0)
        } else {
            // 同页重建（图片 ready / 设置变更等）：刷新 key 快照，不动动画。
            st.curKeys = keys
        }
        match (r.mode) {
            case ReadingMode.Webtoon => prepareWebtoonState()
            case _ =>
                st.wasWebtoon = false
                st.webtoonZoomIndex = -1
        }
        emit(this)
    }

    private func prepareWebtoonState(): Unit {
        let r = model.reader
        let count = r.streamItemCount
        let reset = !st.wasWebtoon || st.webtoonArchive != r.arcid
        let width = if (st.webtoonContentW > 0.0) {
            st.webtoonContentW
        } else {
            WEBTOON_MAX_WIDTH
        }
        let estimate = webtoonEstimatedHeight(width, st.webtoonViewportH)
        if (reset) {
            st.webtoonHeights = Array<Float32>(count, {
                i => if (r.realPageAtStream(i).isSome()) {
                    estimate
                } else {
                    max(320.0, st.webtoonViewportH)
                }
            })
            st.webtoonScroll.value = 0.0
            st.webtoonArchive = r.arcid
            st.webtoonZoomIndex = -1
            st.webtoonSyncedIndex = -1
        } else if (st.webtoonHeights.size != count) {
            // 无缝续读只在尾部追加：保留既有测量值与滚动锚点，仅为新流项补估算高。
            let old = st.webtoonHeights
            st.webtoonHeights = Array<Float32>(count, {
                i => if (i < old.size) {
                    old[i]
                } else if (r.realPageAtStream(i).isSome()) {
                    estimate
                } else {
                    max(320.0, st.webtoonViewportH)
                }
            })
        }
        // reader.index 与上次由滚动同步的索引不同，说明来源是初始进度、滑条或侧栏，
        // 需要像 frontend pendingWebtoonScrollToIndex 一样跳到目标页顶部。
        if (reset || r.index != st.webtoonSyncedIndex) {
            st.webtoonScroll.value = webtoonOffsetBefore(st.webtoonHeights, r.index)
            st.webtoonSyncedIndex = r.index
        }
        st.wasWebtoon = true
        requestVisibleWebtoonImages()
    }

    private func requestVisibleWebtoonImages(): Unit {
        if (st.webtoonHeights.size == 0) {
            return
        }
        let viewport = max(1.0, st.webtoonViewportH)
        let (first, last) = webtoonLazyRange(st.webtoonHeights, st.webtoonScroll.value, viewport)
        for (streamIndex in first..last + 1) {
            match (model.reader.realPageAtStream(streamIndex)) {
                case Some(realIndex) => match (model.reader.pageAt(realIndex)) {
                    case Some(page) =>
                        if (page.pageType == "image" || page.pageType == "") {
                            let arcid = model.reader.arcidOfReal(realIndex)
                            let key = readerPageKey(arcid, page.id)
                            if (model.imageState(key).value == "") {
                                let top = webtoonOffsetBefore(st.webtoonHeights, streamIndex)
                                let bottom = top + st.webtoonHeights[streamIndex]
                                model.requestImage(key, readerPageUrl(arcid, page.id),
                                    highPriority: top < st.webtoonScroll.value + viewport && bottom > st
                                        .webtoonScroll
                                        .value)
                            }
                        }
                    case None => ()
                }
                case None => ()
            }
        }
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, available.h)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
        match (model.reader.mode) {
            case ReadingMode.Webtoon =>
                let nextWidth = webtoonContentWidth(frame.w)
                let widthDelta = nextWidth - st.webtoonContentW
                if (st.webtoonContentW > 0.0 && (widthDelta > 1.0 || widthDelta < -1.0)) {
                    let ratio = nextWidth / st.webtoonContentW
                    for (i in 0..st.webtoonHeights.size) {
                        st.webtoonHeights[i] = max(WEBTOON_MIN_PAGE_HEIGHT, st.webtoonHeights[i] * ratio)
                    }
                    st.webtoonScroll.value = max(0.0, st.webtoonScroll.value * ratio)
                }
                st.webtoonContentW = nextWidth
                st.webtoonViewportH = max(1.0, frame.h)
                let maxOffset = max(0.0, webtoonContentHeight(st.webtoonHeights) - frame.h)
                if (st.webtoonScroll.value > maxOffset) {
                    st.webtoonScroll.value = maxOffset
                }
            case _ => ()
        }
        audioLayout.resolve(frame)
        backRect = audioLayout.back
        playRect = audioLayout.play
        fwdRect = audioLayout.forward
        seekRect = audioLayout.seek
        muteRect = audioLayout.mute
        volumeRect = audioLayout.volume
        // 结束页卡片：居中 420×320；按钮行在卡内底部（seamless 开时不画但热区保留零值）。
        let cw = min(420.0, frame.w - 48.0)
        let ch = min(320.0, frame.h - 48.0)
        endCardRect = Rect(frame.centerX() - cw / 2.0, frame.centerY() - ch / 2.0, cw, ch)
        endOpenRect = Rect(endCardRect.x + 32.0, endCardRect.bottom() - 64.0, 160.0, 36.0)
        endDetailRect = Rect(endCardRect.right() - 32.0 - 120.0, endCardRect.bottom() - 64.0, 120.0, 36.0)
    }

    public func draw(ctx: UiContext): Unit {
        match (model.reader.mode) {
            case ReadingMode.Webtoon =>
                drawWebtoonStage(ctx)
                if (model.readerShowInfo.value) {
                    drawMediaInfo(ctx)
                }
                return
            case _ => ()
        }
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
                case Some(i) => drawAudioStage(ctx, i)
                case None => match (htmlPage) {
                    case Some(i) =>
                        ctx.renderer.fill(frame, ctx.theme.stageBg)
                        drawHtmlStage(ctx, i)
                    case None =>
                        ctx.renderer.fill(frame, ctx.theme.stageBg)
                        drawImageStage(ctx)
                }
            }
        }
        if (model.readerShowInfo.value) {
            drawMediaInfo(ctx)
        }
    }

    // ── 图片舞台 ──

    private func drawWebtoonStage(ctx: UiContext): Unit {
        ctx.renderer.fill(frame, ctx.theme.stageBg)
        if (st.webtoonHeights.size == 0) {
            return
        }
        let contentHeight = webtoonContentHeight(st.webtoonHeights)
        let _ = st.webtoonMotion.animate(ctx, st.webtoonScroll, contentHeight, frame.h)
        syncWebtoonIndex()
        let contentW = webtoonContentWidth(frame.w)
        let contentX = frame.centerX() - contentW / 2.0
        let scroll = st.webtoonScroll.value
        let viewportTop = scroll
        let viewportBottom = scroll + frame.h
        let first = webtoonIndexAtOffset(st.webtoonHeights, viewportTop)
        let last = webtoonIndexAtOffset(st.webtoonHeights, viewportBottom)
        var top = webtoonOffsetBefore(st.webtoonHeights, first)
        var geometryChanged = false
        endCardRect = Rect.zero()
        endOpenRect = Rect.zero()
        endDetailRect = Rect.zero()

        ctx.renderer.pushClip(frame)
        for (streamIndex in first..last + 1) {
            var rowHeight = st.webtoonHeights[streamIndex]
            let rowY = frame.y + top - scroll
            let rowBottom = top + rowHeight
            // 绘制区只物化当前视口；上下三屏的加载窗口已在
            // requestVisibleWebtoonImages 处理。
            if (rowBottom >= viewportTop && top <= viewportBottom) {
                match (model.reader.realPageAtStream(streamIndex)) {
                    case Some(realIndex) => match (model.reader.pageAt(realIndex)) {
                        case Some(page) =>
                            if (page.pageType == "image" || page.pageType == "") {
                                let arcid = model.reader.arcidOfReal(realIndex)
                                let key = readerPageKey(arcid, page.id)
                                let imageStatus = model.imageState(key).value
                                if (imageStatus == "ready") {
                                    match (pixelTexture(ctx.renderer, key)) {
                                        case Some(tex) =>
                                            let measured = webtoonImageHeight(tex.width, tex.height, contentW, rowHeight)
                                            let heightDelta = measured - rowHeight
                                            if (heightDelta > 1.0 || heightDelta < -1.0) {
                                                rowHeight = measured
                                                st.webtoonHeights[streamIndex] = measured
                                                geometryChanged = true
                                            }
                                            var dest = Rect(contentX, rowY, contentW, rowHeight)
                                            if (st.webtoonZoomIndex == streamIndex) {
                                                let zoom: Float32 = STAGE_ZOOM
                                                let anchorX = dest.x + dest.w * st.webtoonZoomOriginX
                                                let anchorY = dest.y + dest.h * st.webtoonZoomOriginY
                                                dest = Rect(anchorX - (anchorX - dest.x) * zoom,
                                                    anchorY - (anchorY - dest.y) * zoom, dest.w * zoom, dest.h * zoom)
                                            }
                                            ctx.renderer.texture(tex, dest)
                                        case None => drawPagePlaceholder(ctx, Rect(contentX, rowY, contentW, rowHeight),
                                            model.t("common.loading"))
                                    }
                                } else if (imageStatus == "error") {
                                    drawPagePlaceholder(ctx, Rect(contentX, rowY, contentW, rowHeight),
                                        model.t("reader.loadFailedRetry"))
                                } else {
                                    drawPagePlaceholder(ctx, Rect(contentX, rowY, contentW, rowHeight),
                                        model.t("common.loading"))
                                }
                            } else {
                                // frontend 在条漫流内也给非图片页独立行；原生端尚未提供
                                // 可同时运行多个媒体播放器的能力，保留连续几何并诚实占位。
                                drawUnsupported(ctx, Rect(contentX, rowY, contentW, rowHeight), realIndex)
                            }
                        case None => ()
                    }
                    case None =>
                        let endFrame = Rect(contentX, rowY, contentW, rowHeight)
                        layoutEndCard(endFrame)
                        drawCollectionEnd(ctx)
                }
            }
            top += rowHeight
        }
        ctx.renderer.popClip()
        drawWebtoonScrollBar(ctx)
        if (geometryChanged) {
            // 本帧的 last 是按旧估算高算出的；立即续一帧用实测高重算可视范围，
            // 同时让新进入 3 屏缓冲区的页面开始懒加载。
            ctx.requestFrame()
        }
    }

    private func layoutEndCard(container: Rect): Unit {
        let cw = min(420.0, container.w - 48.0)
        let ch = min(320.0, container.h - 48.0)
        endCardRect = Rect(container.centerX() - cw / 2.0, container.centerY() - ch / 2.0, cw, ch)
        endOpenRect = Rect(endCardRect.x + 32.0, endCardRect.bottom() - 64.0, 160.0, 36.0)
        endDetailRect = Rect(endCardRect.right() - 32.0 - 120.0, endCardRect.bottom() - 64.0, 120.0, 36.0)
    }

    private func drawWebtoonScrollBar(ctx: UiContext): Unit {
        let contentHeight = webtoonContentHeight(st.webtoonHeights)
        if (contentHeight <= frame.h || frame.h <= 0.0) {
            return
        }
        let track = Rect(frame.right() - 8.0, frame.y + 2.0, 6.0, max(0.0, frame.h - 4.0))
        let thumbHeight = max(18.0, track.h * frame.h / contentHeight)
        let maxOffset = max(1.0, contentHeight - frame.h)
        let thumbY = track.y + (track.h - thumbHeight) * max(0.0, min(1.0, st.webtoonScroll.value / maxOffset))
        ctx.renderer.fill(track, ctx.theme.panelEdge.withAlpha(28))
        ctx
            .renderer
            .fill(Rect(track.x, thumbY, track.w, thumbHeight),
                ctx.theme.accent.withAlpha(if (st.webtoonBar.dragging(ctx)) {
                    230
                } else {
                    180
                }))
    }

    private func pageCell(i: Int64): Rect {
        if (keys.size <= 1) {
            return frame
        }
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

    private func drawSpread(ctx: UiContext, ks: Array<String>, ox: Float32, oy: Float32, alpha: Float32, zoomed: Bool,
        curPages: Bool): Unit {
        if (alpha <= 0.0) {
            return
        }
        for (i in 0..ks.size) {
            let cell = pageCell(Int64(i))
            let key = ks[i]
            if (key.size == 0) {
                // 非图片页：不参与图片滑动。html 页已有渲染纹理时作为普通
                // 纹理随翻页动画走（静止帧，M5 才考虑预热）；其余类型静止时
                // 静态占位（video/html 等），页型按 cell 对应的页索引取
                //（混合 spread 第二格不能拿 spread 首页的）。
                var drawn = false
                if (model.htmlPage.state != "idle") {
                    match (model.reader.pageAt(spreadIdx[Int64(i)])) {
                        case Some(p) =>
                            if (p.pageType == "html") {
                                match (pixelTexture(ctx.renderer, "html:${model.htmlPage.pageKey}")) {
                                    case Some(tex) =>
                                        drawTextureAlpha(ctx, tex, cell.shift(ox, oy), alpha)
                                        drawn = true
                                    case None => ()
                                }
                            }
                        case None => ()
                    }
                }
                if (!drawn && curPages && ox == 0.0 && oy == 0.0) {
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
                            let clamped = max(0.0, min(maxOff, st.scrollY.value))
                            if (clamped != st.scrollY.value) {
                                st.scrollY.value = clamped
                            }
                            let visibleScroll = st.longPageMotion.animate(ctx, st.scrollY, fittedH, frame.h)
                            ctx.renderer.pushClip(frame)
                            drawTextureAlpha(ctx, tex, Rect(frame.x, frame.y - visibleScroll, frame.w, fittedH), alpha)
                            ctx.renderer.popClip()
                        } else {
                            drawTextureAlpha(ctx, tex, dest.shift(ox, oy), alpha)
                        }
                    case None => drawPagePlaceholder(ctx, cell.shift(ox, oy), model.t("common.loading"))
                }
            } else if (st8 == "error") {
                drawPagePlaceholder(ctx, cell.shift(ox, oy), model.t("reader.loadFailedRetry"))
            } else {
                drawPagePlaceholder(ctx, cell.shift(ox, oy), model.t("common.loading"))
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
        let hint = model.t("reader.unsupported", params: [("type", pt)])
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
            case Some(texture) => ctx
                .renderer
                .texture(texture, fittedRect(Size(texture.width, texture.height), frame, ImageFit.Contain))
            case None =>
                var title = model.t("reader.video")
                match (model.reader.pageAt(pageIdx)) {
                    case Some(p) => title = if (p.title.size > 0) {
                        p.title
                    } else {
                        p.id
                    }
                    case None => ()
                }
                let status = if (pb.error.size > 0) {
                    model.t("reader.loadFailed", params: [("error", pb.error)])
                } else if (pb.loading) {
                    model.t("reader.downloading", params: [("title", title)])
                } else if (pb.loaded) {
                    model.t("reader.clickPlay")
                } else {
                    model.t("reader.preparingVideo")
                }
                ctx.renderer.textCenter(status, frame, ctx.theme.onMediaDim, pointSize: 14.0)
        }
        // 视频续帧由新帧驱动：takeVideoFrame 拿到新帧（videoGeneration 前进）时立即
        // requestFrame 拉下一帧，高帧率视频满速跟上；无新帧时 33ms 兜底轮询等解码产出，
        // 不再固定 60fps 全树重建。
        if (pb.playing) {
            if (pb.videoGeneration != st.lastVideoGeneration) {
                st.lastVideoGeneration = pb.videoGeneration
                ctx.requestFrame()
            } else {
                ctx.requestFrameAfter(33)
            }
        }
    }

    // html 离屏渲染舞台（Blitz）：会话视口跟随舞台物理像素，帧经
    // registerPixelImage 进 streaming 纹理（与视频舞台同构）。静止时零重绘：
    // 仅 generation 前进才续帧；子资源在途时 100ms 轮询兜底等回填。
    private func drawHtmlStage(ctx: UiContext, pageIdx: Int64): Unit {
        let hp = model.htmlPage
        let scale = max(1.0, ctx.displayScale)
        hp.setDoublePage(model.reader.doublePage)
        hp.ensureViewport(Int32(frame.w * scale), Int32(frame.h * scale), scale)
        // 拖动松手惯性：ease-out 追踪释放时速度推算的目标位移。scrollTo 驱动
        // native 滚动（dirty → 新帧 → generation 前进 → 本分支续帧）；曲线落定后
        // scrollTo 无变化不再出帧，静止零重绘。
        if (st.htmlFlingActive && hp.state == "ready" && !model.reader.doublePage) {
            let t = st.htmlFlingTween.animate(ctx, target: 1.0)
            hp.scrollTo(st.htmlFlingStart + st.htmlFlingDelta * t)
            if (t >= 1.0) {
                st.htmlFlingActive = false
            }
        }
        hp.pumpResources()
        let key = "html:${hp.pageKey}:left"
        let spreadKey = "html:${hp.pageKey}:right"
        match (hp.takeHtmlFrame()) {
            case Some(fr) => registerPixelImage(ctx.renderer, key, fr.width, fr.height, fr.rgba)
            case None => ()
        }
        if (model.reader.doublePage) {
            match (hp.takeHtmlSpreadFrame()) {
                case Some(fr) => registerPixelImage(ctx.renderer, spreadKey, fr.width, fr.height, fr.rgba)
                case None => ()
            }
            let left = Rect(frame.x, frame.y, frame.w / 2.0, frame.h)
            let right = Rect(left.right(), frame.y, frame.w - left.w, frame.h)
            match (pixelTexture(ctx.renderer, key)) {
                case Some(texture) => ctx.renderer.texture(texture, left)
                case None => drawHtmlPlaceholder(ctx, left, hp.state)
            }
            match (pixelTexture(ctx.renderer, spreadKey)) {
                case Some(texture) => ctx.renderer.texture(texture, right)
                case None => drawHtmlPlaceholder(ctx, right, hp.state)
            }
            ctx
                .renderer
                .strokeLine(frame.centerX(), frame.y + 20.0, frame.centerX(), frame.bottom() - 20.0,
                    Pen(width: 1.0, color: ctx.theme.panelEdge))
        } else {
            match (pixelTexture(ctx.renderer, key)) {
                case Some(texture) => ctx.renderer.texture(texture, frame)
                case None => drawHtmlPlaceholder(ctx, frame, hp.state)
            }
        }
        if (hp.htmlGeneration != st.lastHtmlGeneration) {
            st.lastHtmlGeneration = hp.htmlGeneration
            ctx.requestFrame()
        } else if (hp.resourcesInFlight > 0) {
            ctx.requestFrameAfter(100)
        }
    }

    private func drawHtmlPlaceholder(ctx: UiContext, rect: Rect, state: String): Unit {
        let text = if (state == "error") {
            model.t("reader.htmlError")
        } else {
            model.t("common.loading")
        }
        drawPagePlaceholder(ctx, rect, text)
    }

    // ── 音频舞台：区域编排，不在这里计算任何子区域坐标 ──

    private func drawAudioStage(ctx: UiContext, pageIdx: Int64): Unit {
        model.playback.refreshVlcState()
        drawAudioBackdrop(ctx)
        drawAudioHero(ctx, pageIdx)
        drawAudioLyrics(ctx)
        drawAudioTransport(ctx)
    }

    private func drawAudioBackdrop(ctx: UiContext): Unit {
        ctx.renderer.fill(frame, Color.rgb(8, 10, 14))
        if (audioCoverKey.size > 0 && model.imageState(audioCoverKey).value == "ready") {
            match (pixelTexture(ctx.renderer, audioBackdropKey)) {
                case Some(tex) =>
                    tex.setAlpha(210)
                    ctx.renderer.texture(tex, fittedRect(Size(tex.width, tex.height), frame, ImageFit.Cover))
                    tex.setAlpha(255)
                case None => ()
            }
        }
        // extraDark 等价遮罩；左右内容仍保留封面色彩，不退化为纯黑。
        ctx.renderer.fill(frame, Color.rgba(0, 0, 0, 132))
        ctx.renderer.fillHorizontalGradient(frame, Color.rgba(0, 0, 0, 6), Color.rgba(0, 0, 0, 58))
    }

    // 左侧 Hero 只负责封面和曲目信息。
    private func drawAudioHero(ctx: UiContext, pageIdx: Int64): Unit {
        let pb = model.playback
        let onMedia = ctx.theme.onMedia
        let onMediaDim = ctx.theme.onMediaDim
        ctx.renderer.pushClip(audioLayout.hero)
        var coverDrawn = false
        if (audioCoverKey.size > 0 && model.imageState(audioCoverKey).value == "ready") {
            match (pixelTexture(ctx.renderer, audioCoverKey)) {
                case Some(tex) =>
                    ctx.renderer.pushClip(audioLayout.cover)
                    ctx.renderer.texture(tex, fittedRect(Size(tex.width, tex.height), audioLayout.cover, ImageFit.Cover))
                    ctx.renderer.popClip()
                    coverDrawn = true
                case None => ()
            }
        }
        if (!coverDrawn) {
            ctx.renderer.fillRoundedRect(audioLayout.cover, 8.0, Color.rgb(18, 18, 18))
            let cx = audioLayout.cover.centerX()
            let cy = audioLayout.cover.centerY()
            drawIcon(ctx.renderer, IconName.Music, Rect(cx - 16.0, cy - 16.0, 32.0, 32.0), ctx.theme.accent, weight: 2.0)
        }
        var title = ""
        match (model.reader.pageAt(pageIdx)) {
            case Some(p) => title = if (p.title.size > 0) {
                p.title
            } else {
                p.id
            }
            case None => ()
        }
        let titleRect = Rect(audioLayout.meta.x, audioLayout.meta.y, audioLayout.meta.w, 28.0)
        ctx.renderer.textCenter(title, titleRect, onMedia, pointSize: 20.0)
        let sub = if (pb.error.size > 0) {
            model.t("reader.loadFailed", params: [("error", pb.error)])
        } else if (pb.loading) {
            model.t("common.loading")
        } else if (!pb.loaded) {
            model.t("reader.notLoaded")
        } else {
            "${formatMediaClock(pb.positionSec)} / ${if (pb.durationSec > 0.0) { formatMediaClock(pb.durationSec) } else { "--:--" }}"
        }
        ctx
            .renderer
            .textCenter(sub, Rect(audioLayout.meta.x, audioLayout.meta.y + 32.0, audioLayout.meta.w, 20.0), onMediaDim,
                pointSize: 13.0)
        ctx.renderer.popClip()
    }

    // Apple Music 风格歌词视口：大字号左对齐、当前行强对比，切行时上移并放大。
    private func drawAudioLyrics(ctx: UiContext): Unit {
        let pb = model.playback
        let area = audioLayout.lyrics
        ctx.renderer.pushClip(area)
        let lyricIndex = pb.activeLyricIndex()
        if (pb.lyricsLines.size > 0) {
            if (lyricIndex != st.lastLyricIndex) {
                st.lastLyricIndex = lyricIndex
                st.lyricFocusTween.reset(0.0)
            }
            let focusT = st.lyricFocusTween.animate(ctx, target: 1.0)
            let baseX = area.x + min(44.0, area.w * 0.07)
            let slideY = 12.0 * (1.0 - focusT)
            var row: Int64 = -3
            while (row <= 3) {
                let idx = lyricIndex + row
                if (idx >= 0 && idx < pb.lyricsLines.size) {
                    let line = pb.lyricsLines[idx]
                    let color = if (row == 0) {
                        ctx.theme.onMedia.withAlpha(Int64(190.0 + 65.0 * focusT))
                    } else {
                        ctx.theme.onMedia.withAlpha(if (row == -1 || row == 1) {
                            112
                        } else {
                            58
                        })
                    }
                    let size: Float32 = if (row == 0) {
                        22.0 + 8.0 * focusT
                    } else {
                        18.0
                    }
                    let spacing = 51.0 + 5.0 * focusT
                    let y = area.centerY() + Float32(row) * spacing - size / 2.0 + slideY
                    if (row == 0) {
                        // 当前行轻微光晕 + 双绘近似粗体；非当前行保持柔和。
                        ctx
                            .renderer
                            .text(line.text, baseX + 1.0, y + 2.0, ctx.theme.onMedia.withAlpha(Int64(35.0 * focusT)),
                                pointSize: size)
                        ctx.renderer.text(line.text, baseX + 0.7, y, color, pointSize: size)
                    }
                    ctx.renderer.text(line.text, baseX, y, color, pointSize: size)
                }
                row++
            }
        } else {
            ctx.renderer.textCenter(model.t("reader.noLyrics"), area, ctx.theme.onMediaDim, pointSize: 14.0)
        }
        ctx.renderer.popClip()
    }

    // Transport 拥有全部播放热区；seek 的几何与事件处理共享 AudioStageLayout。
    private func drawAudioTransport(ctx: UiContext): Unit {
        let pb = model.playback
        let onMedia = ctx.theme.onMedia
        ctx.renderer.pushClip(audioLayout.transport)
        let current = formatMediaClock(pb.positionSec)
        let currentX = fwdRect.right() + 10.0
        ctx.renderer.text(current, currentX, seekRect.y, ctx.theme.onMediaDim, pointSize: 11.0)
        let duration = if (pb.durationSec > 0.0) {
            formatMediaClock(pb.durationSec)
        } else {
            "--:--"
        }
        let durationW = ctx.renderer.textWidth(duration, pointSize: 11.0)
        ctx.renderer.text(duration, muteRect.x - 8.0 - durationW, seekRect.y, ctx.theme.onMediaDim, pointSize: 11.0)
        drawCircleButton(ctx, backRect, "reader:stage:back", {
            => drawSkipGlyph(ctx.renderer, backRect.centerX(), backRect.centerY(), -1.0, onMedia)
        })
        let playBg = if (ctx.isHovered("reader:stage:play")) {
            onMedia.withAlpha(220)
        } else {
            onMedia
        }
        ctx.renderer.fillCircle(playRect.centerX(), playRect.centerY(), playRect.w / 2.0, playBg)
        drawPlayPauseGlyph(ctx.renderer, playRect.centerX(), playRect.centerY(), pb.playing, Color.rgb(0, 0, 0))
        drawCircleButton(ctx, fwdRect, "reader:stage:fwd", {
            => drawSkipGlyph(ctx.renderer, fwdRect.centerX(), fwdRect.centerY(), 1.0, onMedia)
        })
        drawPlaybackSeekBar(ctx, seekRect, pb)
        drawCircleButton(ctx, muteRect, "reader:stage:mute", {
            => drawMuteGlyph(ctx.renderer, muteRect.centerX(), muteRect.centerY(), pb.muted, onMedia)
        })
        let vcy = volumeRect.centerY()
        ctx.renderer.fillRoundedRect(Rect(volumeRect.x, vcy - 2.0, volumeRect.w, 4.0), 2.0,
            ctx.theme.onMedia.withAlpha(50))
        let amount = Float32(pb.volume)
        ctx.renderer.fillRoundedRect(Rect(volumeRect.x, vcy - 2.0, volumeRect.w * amount, 4.0), 2.0, ctx.theme.onMedia)
        ctx.renderer.fillCircle(volumeRect.x + volumeRect.w * amount, vcy, 4.0, ctx.theme.onMedia)
        ctx.renderer.popClip()
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
            ctx.renderer.fillCircle(rect.centerX(), rect.centerY(), rect.w / 2.0, ctx.theme.onMedia.withAlpha(30))
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
        ctx.renderer.textCenter(model.t("reader.finished"), Rect(c.x, y, c.w, 24.0), ctx.theme.text, pointSize: 17.0)
        y += 32.0
        // 本 segment 标题：segment 回填优先，元数据兜底。
        var title = r.activeSegmentTitle
        if (title.size == 0) {
            match (model.meta.value) {
                case Some(m) =>
                    if (m.arcid == model.readerArcid) {
                        title = m.title
                    }
                case None => ()
            }
        }
        ctx.renderer.textCenter("《${title}》", Rect(c.x + 24.0, y, c.w - 48.0, 20.0), ctx.theme.mutedText,
            pointSize: 13.0)
        y += 48.0
        // 下一档案行：可选封面（AppModel 解析候选后经 asset 管线请求）+ 状态文案。
        let nextTitle = r.nextSegmentTitle
        if (nextTitle.size > 0) {
            drawNextLine(ctx, y, model.t("reader.nextArchive", params: [("title", nextTitle)]), true)
        } else if (r.appendError.size > 0) {
            drawNextLine(ctx, y, r.appendError, false)
        } else if (r.seamlessNext) {
            drawNextLine(ctx, y, model.t("reader.loadingNext"), false)
        } else if (model.readerNextTitle.value.size > 0) {
            drawNextLine(ctx, y, model.t("reader.nextArchive", params: [("title", model.readerNextTitle.value)]), true)
        } else {
            drawNextLine(ctx, y, model.t("reader.resolvingNext"), false)
        }
        // 按钮（seamless 关）：打开下一档案（候选未解析到时灰显）/ 查看详情。
        if (!r.seamlessNext) {
            drawEndButton(ctx, endOpenRect, "reader:end:open", model.t("reader.openNext"), model.hasNextCandidate(),
                true)
            drawEndButton(ctx, endDetailRect, "reader:end:detail", model.t("reader.viewDetails"), true, false)
        }
    }

    private func drawNextLine(ctx: UiContext, y: Float32, text: String, cover: Bool): Unit {
        let c = endCardRect
        var tx = c.x + 32.0
        // 候选封面 48×64（asset 管线；未就绪/无封面跳过不编）。
        if (cover && model.readerNextCoverKey.size > 0 && model.imageState(model.readerNextCoverKey).value == "ready") {
            match (pixelTexture(ctx.renderer, model.readerNextCoverKey)) {
                case Some(tex) =>
                    let dest = fittedRect(Size(tex.width, tex.height), Rect(tx, y - 8.0, 48.0, 64.0), ImageFit.Cover)
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
    private func drawEndButton(ctx: UiContext, rect: Rect, hoverId: String, label: String, enabled: Bool, primary: Bool): Unit {
        let hovered = enabled && ctx.isHovered(hoverId)
        let bg = if (!enabled) {
            ctx.theme.field
        } else if (primary) {
            if (hovered) {
                ctx.theme.accent.withAlpha(220)
            } else {
                ctx.theme.accent
            }
        } else {
            if (hovered) {
                ctx.theme.overlayHover
            } else {
                ctx.theme.field
            }
        }
        ctx.renderer.fillRoundedRect(rect, 9.0, bg)
        let fg = if (!enabled) {
            ctx.theme.mutedText
        } else if (primary) {
            ctx.theme.accentText
        } else {
            ctx.theme.text
        }
        ctx.renderer.textCenter(label, rect, fg, pointSize: 13.0)
    }

    // ── 媒体信息浮层（原型 #media-info；readerShowInfo 开时显示，左下角小字半透明底）──

    private func drawMediaInfo(ctx: UiContext): Unit {
        if (model.reader.onVirtualEnd) {
            return
        } // 结束页无媒体信息
        var parts = ArrayList<String>()
        parts.add("p.${model.reader.displayPage}")
        let realIdx = match (model.reader.currentReal) {
            case Some(i) => i
            case None => return
        }
        match (model.reader.pageAt(realIdx)) {
            case Some(p) =>
                parts.add(if (p.pageType.size > 0) {
                    p.pageType
                } else {
                    "image"
                })
                if (p.pageType == "image" || p.pageType == "") {
                    let key = readerPageKey(model.reader.arcidOfReal(realIdx), p.id)
                    match (pixelTexture(ctx.renderer, key)) {
                        case Some(tex) => parts.add("${Int64(tex.width)}×${Int64(tex.height)}")
                        case None => ()
                    }
                    // 加载态：没有「缓存命中/解码耗时」数据源，只报真实状态。
                    let st8 = model.imageState(key).value
                    parts.add(match (st8) {
                        case "ready" => model.t("reader.decoded")
                        case "error" => model.t("reader.loadFailedShort")
                        case "loading" => model.t("reader.downloadInProgress")
                        case _ => model.t("reader.queued")
                    })
                }
            case None => ()
        }
        let sb = StringBuilder()
        for (i in 0..parts.size) {
            if (i > 0) {
                sb.append(" · ")
            }
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

    // 长图滚动生效判定：longPage 开 + 单页图片 + TTB 模式 + 未放大 + 宽适配后高度
    // 溢出舞台。LTR/RTL 左右翻页模式下不应启用——长图按宽度拉伸会导致纵向溢出视口，
    // 左右翻页应始终 contain 适配。返回最大滚动偏移；不启用返回 None。
    private func longPageMax(ctx: UiContext): ?Float32 {
        let r = model.reader
        if (!r.longPage || keys.size != 1 || st.zoomed) {
            return None
        }
        // 只在纵向阅读模式下启用长图滚动：LTR/RTL 左右翻页使用 contain 适配即可。
        match (r.mode) {
            case ReadingMode.SingleTtb => ()
            case _ => return None
        }
        let key = keys[0]
        if (key.size == 0 || model.imageState(key).value != "ready") {
            return None
        }
        match (pixelTexture(ctx.renderer, key)) {
            case Some(tex) =>
                let maxOff = longPageMaxOffset(longPageFittedHeight(tex.width, tex.height, frame.w), frame.h)
                if (maxOff > 0.0) {
                    Some(maxOff)
                } else {
                    None
                }
            case None => None
        }
    }

    // 非条漫滚轮翻页走 spread 步进；条漫由 handleWebtoon 连续滚动，不进入这里。
    private func wheelTurn(forward: Bool): Unit {
        match (model.reader.mode) {
            case ReadingMode.Webtoon => ()
            case _ => model.readerTurnPage(forward)
        }
    }

    private func syncWebtoonIndex(): Unit {
        if (st.webtoonHeights.size == 0) {
            return
        }
        let threshold = st.webtoonScroll.value + frame.h * 0.3
        let streamIndex = webtoonIndexAtOffset(st.webtoonHeights, threshold)
        if (streamIndex != st.webtoonSyncedIndex) {
            // 先标记再广播：readerVersion 会立即重建视图；新实例据此识别这是滚动
            // 驱动的页码变化，不把 scroll 强行吸回页首。
            st.webtoonSyncedIndex = streamIndex
            model.syncWebtoonScrollPage(streamIndex)
        }
    }

    private func handleWebtoon(ctx: UiContext, event: UiEvent): Bool {
        let contentHeight = webtoonContentHeight(st.webtoonHeights)
        match (event) {
            case UiEvent.MouseWheel(_, wheelY, x, y) =>
                if (!frame.contains(x, y)) {
                    return false
                }
                model.noteReaderActivity()
                let _ = st.webtoonMotion.scrollBy(ctx, st.webtoonScroll, -wheelY * WEBTOON_WHEEL_PX, contentHeight,
                    frame.h)
                return true
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (!frame.contains(x, y)) {
                    return false
                }
                if (st.webtoonBar.press(ctx, frame, st.webtoonScroll, contentHeight, frame.h, x, y)) {
                    syncWebtoonIndex()
                    return true
                }
                if (model.reader.doubleTapZoom && ctx.clickCount >= 2) {
                    let contentOffset = st.webtoonScroll.value + y - frame.y
                    let streamIndex = webtoonIndexAtOffset(st.webtoonHeights, contentOffset)
                    match (model.reader.realPageAtStream(streamIndex)) {
                        case Some(realIndex) => match (model.reader.pageAt(realIndex)) {
                            case Some(page) =>
                                if (page.pageType == "image" || page.pageType == "") {
                                    if (st.webtoonZoomIndex == streamIndex) {
                                        st.webtoonZoomIndex = -1
                                    } else {
                                        let rowTop = webtoonOffsetBefore(st.webtoonHeights, streamIndex)
                                        let contentX = frame.centerX() - webtoonContentWidth(frame.w) / 2.0
                                        st.webtoonZoomIndex = streamIndex
                                        st.webtoonZoomOriginX = max(0.0,
                                            min(1.0, (x - contentX) / webtoonContentWidth(frame.w)))
                                        st.webtoonZoomOriginY = max(0.0,
                                            min(1.0, (contentOffset - rowTop) / st.webtoonHeights[streamIndex]))
                                    }
                                    ctx.requestFrame()
                                    return true
                                }
                            case None => ()
                        }
                        case None => ()
                    }
                }
            case UiEvent.MouseMove(x, y) =>
                if (st.webtoonBar.drag(ctx, frame, st.webtoonScroll, contentHeight, frame.h, y)) {
                    syncWebtoonIndex()
                    return true
                }
                if (model.reader.onVirtualEnd && !model.reader.seamlessNext) {
                    if (endOpenRect.contains(x, y) && model.hasNextCandidate()) {
                        ctx.claimHover("reader:end:open", CursorShape.Interactive)
                    }
                    if (endDetailRect.contains(x, y)) {
                        ctx.claimHover("reader:end:detail", CursorShape.Interactive)
                    }
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
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
                if (!frame.contains(x, y) || st.webtoonHeights.size == 0) {
                    return false
                }
                let streamIndex = webtoonIndexAtOffset(st.webtoonHeights, st.webtoonScroll.value + y - frame.y)
                match (model.reader.realPageAtStream(streamIndex)) {
                    case Some(realIndex) => match (model.reader.pageAt(realIndex)) {
                        case Some(page) =>
                            if (page.pageType == "image" || page.pageType == "") {
                                let arcid = model.reader.arcidOfReal(realIndex)
                                let key = readerPageKey(arcid, page.id)
                                if (model.imageState(key).value == "error") {
                                    model.retryImage(key, readerPageUrl(arcid, page.id))
                                    return true
                                }
                            }
                        case None => ()
                    }
                    case None => ()
                }
            case _ => ()
        }
        false
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (model.reader.mode) {
            case ReadingMode.Webtoon => return handleWebtoon(ctx, event)
            case _ => ()
        }
        match (event) {
            case UiEvent.MouseWheel(_, dy, x, y) =>
                if (!frame.contains(x, y)) {
                    return false
                }
                model.noteReaderActivity()
                // html 页滚动：先滚页内（滚轮一档≈ 3 行高）；到边界外溢给现有
                // 翻页导航，150ms 冷却防连续滚轮在边界误翻。
                if (htmlPage.isSome() && model.htmlPage.state == "ready" && dy != 0.0) {
                    let moved = model.htmlPage.scrollBy(dy * 60.0)
                    if (!moved) {
                        let now = model.reader.clock()
                        if (htmlOverflowTurnAllowed(st.lastHtmlOverflowMs, now, 150)) {
                            st.lastHtmlOverflowMs = now
                            wheelTurn(dy > 0.0)
                        }
                    }
                    ctx.requestFrame()
                    return true
                }
                // 长图滚动：滚轮先滚图；滚到顶再向上 → 上一页、滚到底再向下 → 下一页
                //（frontend 边缘倒计时 toast 省略：直接翻页）。滚动跟手无惯性。
                match (longPageMax(ctx)) {
                    case Some(maxOff) =>
                        if (dy != 0.0 &&
                            !st.longPageMotion.scrollBy(ctx, st.scrollY, dy * LONG_PAGE_WHEEL_PX, maxOff + frame.h,
                            frame.h)) {
                            wheelTurn(dy > 0.0)
                        }
                    case None =>
                        if (dy > 0.0) {
                            wheelTurn(true)
                        } else if (dy < 0.0) {
                            wheelTurn(false)
                        }
                }
                return true
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                // html 页拖动滚动（M3.2）：按下记录起点与速度基线；MouseMove 跟手
                // 滚动，MouseUp 按是否真拖决定消费与否——简单点击仍落到底层翻页区。
                if (htmlPage.isSome() && model.htmlPage.state == "ready" && !model.reader.doublePage && frame.contains(
                    x, y)) {
                    st.htmlDragActive = true
                    st.htmlDragMoved = false
                    st.htmlDragStartY = y
                    st.htmlDragStartScroll = model.htmlPage.scrollY()
                    st.htmlDragLastY = y
                    st.htmlDragLastMs = model.reader.clock()
                    st.htmlDragVelocity = 0.0
                    st.htmlFlingActive = false
                    ctx.beginDrag("reader:stage:html-scroll")
                    return true
                }
                // 双击缩放（cui 自带 clickCount：2=双击，见 UiContext）：
                // 仅图片舞台且设置开启时 1×/2× 切换。消费 MouseDown 不阻断配套
                // MouseUp——中央区双击=chrome 两次翻转（净零）+缩放切换，可接受。
                if (audioPage.isNone() && videoPage.isNone() && htmlPage.isNone() && model.reader.doubleTapZoom &&
                    ctx.clickCount >= 2 && frame.contains(x, y)) {
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
                    if (seekRect.contains(x, y) && model.playback.durationSec > 0.0 && model.playback.loaded) {
                        ctx.beginDrag("reader:stage:seek")
                        seekFromX(x, seekRect)
                        return true
                    }
                    if (muteRect.contains(x, y)) {
                        model.playback.toggleMute()
                        return true
                    }
                    if (volumeRect.contains(x, y)) {
                        ctx.beginDrag("reader:stage:volume")
                        volumeFromX(x)
                        return true
                    }
                }
            case UiEvent.MouseMove(x, y) =>
                // html 页拖动滚动：拖动中（按下起点在舞台内）跟手滚动并累计速度。
                if (st.htmlDragActive && ctx.isDragging("reader:stage:html-scroll") && ctx.leftMouseDown) {
                    let hp = model.htmlPage
                    let dy = y - st.htmlDragLastY
                    let now = model.reader.clock()
                    let dt = max(1, now - st.htmlDragLastMs)
                    // 速度平滑（px/ms）：拖动方向与滚动方向相反（往下拖 = 内容上移）。
                    st.htmlDragVelocity = st.htmlDragVelocity * 0.7 + (dy / Float32(dt)) * 0.3
                    st.htmlDragLastY = y
                    st.htmlDragLastMs = now
                    if (abs(y - st.htmlDragStartY) > 4.0) {
                        st.htmlDragMoved = true
                    }
                    hp.scrollTo(st.htmlDragStartScroll - (y - st.htmlDragStartY))
                    ctx.requestFrame()
                    return true
                }
                if (model.reader.onVirtualEnd && !model.reader.seamlessNext) {
                    if (endOpenRect.contains(x, y) && model.hasNextCandidate()) {
                        ctx.claimHover("reader:end:open", CursorShape.Interactive)
                    }
                    if (endDetailRect.contains(x, y)) {
                        ctx.claimHover("reader:end:detail", CursorShape.Interactive)
                    }
                }
                if (audioPage.isSome() || videoPage.isSome()) {
                    if (playRect.contains(x, y)) {
                        ctx.claimHover("reader:stage:play", CursorShape.Interactive)
                    }
                    if (backRect.contains(x, y)) {
                        ctx.claimHover("reader:stage:back", CursorShape.Interactive)
                    }
                    if (fwdRect.contains(x, y)) {
                        ctx.claimHover("reader:stage:fwd", CursorShape.Interactive)
                    }
                    if (seekRect.contains(x, y)) {
                        ctx.claimHover("reader:stage:seek", CursorShape.Interactive)
                    }
                    if (muteRect.contains(x, y)) {
                        ctx.claimHover("reader:stage:mute", CursorShape.Interactive)
                    }
                    if (volumeRect.contains(x, y)) {
                        ctx.claimHover("reader:stage:volume", CursorShape.Interactive)
                    }
                    if (ctx.isDragging("reader:stage:seek") && ctx.leftMouseDown) {
                        seekFromX(x, seekRect)
                        return true
                    }
                    if (ctx.isDragging("reader:stage:volume") && ctx.leftMouseDown) {
                        volumeFromX(x)
                        return true
                    }
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                // html 页拖动结束：真拖（移动超 4px）才消费——消费即吞掉底层翻页区
                // 的点击；简单点击不消费放行。速度达阈值起 ease-out 惯性续滚。
                if (st.htmlDragActive && ctx.isDragging("reader:stage:html-scroll")) {
                    st.htmlDragActive = false
                    ctx.clearDrag()
                    if (st.htmlDragMoved) {
                        let v = st.htmlDragVelocity
                        if (abs(v) >= HTML_FLING_VELOCITY_THRESHOLD) {
                            st.htmlFlingStart = model.htmlPage.scrollY()
                            st.htmlFlingDelta = -v * Float32(HTML_FLING_MS)
                            st.htmlFlingActive = true
                            st.htmlFlingTween.reset(0.0)
                        }
                        return true
                    }
                }
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
                if (ctx.isDragging("reader:stage:volume")) {
                    volumeFromX(x)
                    return true
                }
                // html 页错误态点击重试（整舞台都是热区）。
                if (htmlPage.isSome() && model.htmlPage.state == "error" && frame.contains(x, y)) {
                    model.htmlPage.retry()
                    return true
                }
                // 失败页点击重试：命中当前 spread 内 error 页 cell 才消费，
                // 否则穿透给底层翻页/chrome 点击区（与旧视图层级语义一致）。
                if (audioPage.isNone() && videoPage.isNone() && frame.contains(x, y)) {
                    for (i in 0..keys.size) {
                        let key = keys[i]
                        if (key.size > 0 && model.imageState(key).value == "error" && pageCell(Int64(i)).contains(x, y)) {
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
        if (dur <= 0.0 || rect.w <= 0.0) {
            return
        }
        let amount = Float64(max(0.0, min(1.0, (x - rect.x) / rect.w)))
        model.playback.seekTo(amount * dur)
    }

    private func volumeFromX(x: Float32): Unit {
        if (volumeRect.w <= 0.0) {
            return
        }
        model.playback.setVolume(Float64(max(0.0, min(1.0, (x - volumeRect.x) / volumeRect.w))))
    }
}
