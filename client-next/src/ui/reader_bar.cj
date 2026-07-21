package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*

// ── 阅读器专用顶栏（reader-redesign.html #topbar，与其他界面的通用 titleBar 完全不同）──
// 左→右 = ← 返回详情 → ☰ 页面导航 → 档案标题 · 页标题（flex，省略号截断，即窗口拖动区）
// → 页码胶囊 → ◐ 主题 → ⇄ 阅读模式（宽自适应带文字标签）→ ♥ 收藏 → ⚙ 阅读设置
// → 1×20 分隔线 → 最小化/最大化/关闭。高 52vp，底 = bg 纵向渐隐（.95→.75）+ 1px panelEdge
// 底边线。chrome 显隐由 readerTopBarChrome 容器负责：顶栏始终挂载，隐藏时整体上滑出屏
// （Spring 260/26，与 Drawer/dock 一致），页面区经 main.cj 的 ZStack 叠层恒吃满全高。

// 顶栏高（vp；原型 52px，比通用 titleBar 的 56 低一档）。
public let READER_BAR_HEIGHT: Int32 = 52

// ── 拖动区几何（逻辑 vp）──
// 左固定带 = 左内边距 12 + ←34 + 间距 6 + ☰34 + 间距 6 = 92。
private let RB_DRAG_LEFT: Int32 = 92
// 右固定带 ≈ 页码胶囊 ~66 + ◐34 + 模式钮 ≤150 + ♥34 + ⚙34 + 分隔线 13 + 窗口控制 118
// + 间距 6×8 + 右内边距 12 ≈ 513，取 540 留边（同 titlebar 的保守哲学：宁可少注册，
// 不错盖交互控件；标题文本才是唯一死区/拖动区）。
private let RB_DRAG_RIGHT: Int32 = 540

// 阅读器顶栏拖动矩形集：仅标题弹性区一块，窗口过窄（控件相互贴靠）时不注册。
// 坐标为逻辑 vp；chrome 隐藏时由 main.cj 清空拖动区（顶栏不存在，顶部恢复点击翻页）。
public func readerBarDragRects(windowWidth: Int32): Array<(Int32, Int32, Int32, Int32)> {
    let w = windowWidth - RB_DRAG_LEFT - RB_DRAG_RIGHT
    if (w <= 0) {
        return Array<(Int32, Int32, Int32, Int32)>(0, repeat: (0, 0, 0, 0))
    }
    [(RB_DRAG_LEFT, 0, w, READER_BAR_HEIGHT)]
}

// 标题区（原型 .tb-title：档案名主文字色 + 「 · 页标题」muted，作为一个文本流整体单行
// 省略号截断）。两个 Label 无法兼顾「相邻」与「整体截断」（flex 槽会把页标题推到槽尾，
// 中间留出空档），故自绘：档案名先按剩余宽截断，页标题紧随其后。
private class ReaderTitle <: Widget {
    private let title: String
    private let chapter: String
    private var frame = Rect.zero()

    public init(title: String, chapter: String) {
        this.title = title
        this.chapter = chapter
        emit(this)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        let ps: Float32 = 14.0
        var w = ctx.renderer.textWidth(title, pointSize: ps)
        if (chapter.size > 0) {
            w += ctx.renderer.textWidth(" · ${chapter}", pointSize: ps)
        }
        Size(min(available.w, w), ctx.renderer.textHeight(pointSize: ps))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let ps: Float32 = 14.0
        let th = ctx.renderer.textHeight(pointSize: ps)
        let ty = frame.centerY() - th / 2.0
        var x = frame.x
        // 页标题宽（含「 · 」前缀），为它在标题截断中预留整宽；标题更短时自然左邻。
        var chapText = ""
        var chapW: Float32 = 0.0
        if (chapter.size > 0) {
            chapText = " · ${chapter}"
            chapW = ctx.renderer.textWidth(chapText, pointSize: ps)
        }
        let fittedTitle = ellipsizeText(ctx, title, frame.w - chapW, ps)
        if (fittedTitle.size > 0) {
            ctx.renderer.text(fittedTitle, x, ty, ctx.theme.text, pointSize: ps)
            x += ctx.renderer.textWidth(fittedTitle, pointSize: ps)
        }
        if (chapW > 0.0) {
            let fittedChap = ellipsizeText(ctx, chapText, frame.right() - x, ps)
            if (fittedChap.size > 0) {
                ctx.renderer.text(fittedChap, x, ty, ctx.theme.mutedText, pointSize: ps)
            }
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 单行省略号截断（cui.core 的 ellipsize 未对应用导出，这里按同一思路二分前缀）。
private func ellipsizeText(ctx: UiContext, text: String, maxWidth: Float32, ps: Float32): String {
    if (text.size == 0 || maxWidth <= 0.0) { return "" }
    if (ctx.renderer.textWidth(text, pointSize: ps) <= maxWidth) { return text }
    if (ctx.renderer.textWidth("…", pointSize: ps) > maxWidth) { return "" }
    let runes = text.toRuneArray()
    var low: Int64 = 0
    var high = runes.size - 1
    while (low < high) {
        let mid = (low + high + 1) / 2
        let candidate = runesToString(runes, 0, mid) + "…"
        if (ctx.renderer.textWidth(candidate, pointSize: ps) <= maxWidth) {
            low = mid
        } else {
            high = mid - 1
        }
    }
    runesToString(runes, 0, low) + "…"
}

// Rune 切片转字符串（titlebar.cj 同名助手为文件私有，这里自备一份）。
private func runesToString(runes: Array<Rune>, start: Int64, end: Int64): String {
    let builder = StringBuilder()
    var i = start
    while (i < end) {
        builder.append(runes[i])
        i += 1
    }
    builder.toString()
}

// 底边 1px panelEdge 线（原型 border-bottom）。自绘而不用 VStack+Spacer+background
// 组合——空 VStack 套 height(1.vp) 在该组合下会异常撑高（实测铺出 22px 灰带）。
private class ReaderBarEdge <: Widget {
    private var frame = Rect.zero()

    public init() {
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        ctx.renderer.fill(Rect(frame.x, frame.bottom() - 1.0, frame.w, 1.0), ctx.theme.panelEdge)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 阅读模式钮（原型 #mode-btn：icon-btn 变体——高 34、宽自适应、⇄ + 12.5fp 文字标签，
// hover 铺 overlayHover 圆角底、文字转主文字色）。点击循环切模式（状态机内持久化）。
private class ReaderModeButton <: Widget {
    private let model: AppModel
    private let hoverId = "readerbar:mode"
    private var frame = Rect.zero()

    public init(model: AppModel) {
        this.model = model
        emit(this)
    }

    // 标签文案与原型 modes 表一致。
    private func label(): String {
        match (model.reader.mode) {
            case ReadingMode.SingleLtr => "单页 · 左到右"
            case ReadingMode.SingleRtl => "单页 · 右到左"
            case ReadingMode.SingleTtb => "单页 · 纵向"
            case ReadingMode.Webtoon => "条漫滚动"
        }
    }

    public func measure(ctx: UiContext, _: Size): Size {
        // 左右内边距 12 + ⇄ 图标 14 + 图标文字间距 6 + 文字宽（原型 padding:0 12px、gap:6px）。
        Size(12.0 + 14.0 + 6.0 + ctx.renderer.textWidth(label(), pointSize: 12.5) + 12.0, 34.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let hovered = ctx.isHovered(hoverId)
        if (hovered) {
            ctx.renderer.fillRoundedRect(frame, 9.0, ctx.theme.overlayHover)
        }
        let color = if (hovered) { ctx.theme.text } else { ctx.theme.mutedText }
        let cy = frame.centerY()
        drawGhostGlyph(ctx.renderer, GhostGlyph.Swap, frame.x + 12.0 + 7.0, cy, color)
        let text = label()
        let th = ctx.renderer.textHeight(pointSize: 12.5)
        ctx.renderer.text(text, frame.x + 12.0 + 14.0 + 6.0, cy - th / 2.0, color,
            pointSize: 12.5)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    ctx.claimHover(hoverId, CursorShape.Interactive)
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    model.cycleReadingMode()
                    return true
                }
            case _ => ()
        }
        false
    }
}

// 页码胶囊（原型 .tb-page：bg-elev 底 + 1px 描边 + 全圆角 + 12.5fp muted，padding 4px 10px）。
private func pagePill(model: AppModel): Unit {
    // 显示语义：seamless 开 = segment 内页码/页数，关 = 全局；虚拟结束页显示「完」。
    if (model.reader.onVirtualEnd) {
        let elev0 = if (model.isLight()) { LANLU_L_PANEL } else { LANLU_PANEL }
        ZStack {
            Label("完").fontSize(12.5.fp).muted()
                .padding(10.vp, 4.vp).background(elev0, 999.vp)
            StaticBorder(999.0)
        }
        return
    }
    let cur = model.reader.displayPage
    let total = model.reader.displayTotal
    let elev = if (model.isLight()) { LANLU_L_PANEL } else { LANLU_PANEL }
    ZStack {
        Label("${cur} / ${total}").fontSize(12.5.fp).muted()
            .padding(10.vp, 4.vp).background(elev, 999.vp)
        StaticBorder(999.0)
    }
}

// 阅读器顶栏。window 仅用于窗口控制三钮（最小化/最大化/关闭）。
public func readerTitleBar(window: SdlWindow, model: AppModel): Unit {
    let light = model.isLight()
    let bg = if (light) { LANLU_L_BG } else { LANLU_BG }
    // 标题区：档案名（主文字色；原型 <b> 粗体，cui 无字重原语，以色彩分层代替）
    // + 当前页标题（muted，前置「 · 」）。元数据未到货/不是当前档案时不显示档案名。
    let archiveTitle = match (model.meta.value) {
        case Some(m) => if (m.arcid == model.readerArcid) { m.title } else { "" }
        case None => ""
    }
    let favorited = match (model.meta.value) {
        case Some(m) => m.arcid == model.readerArcid && m.isfavorite
        case None => false
    }
    let chapter = match (model.reader.currentReal) {
        case Some(i) => match (model.reader.pageAt(i)) {
            case Some(p) => p.title
            case None => ""
        }
        case None => ""
    }
    ZStack {
        // 底：bg 95%→75% 纵向渐隐（原型 linear-gradient；亮色 .96→.80）。
        if (light) {
            GradientScrim(direction: GradientDirection.Bottom,
                stops: [(0.0, bg.withAlpha(245)), (1.0, bg.withAlpha(204))])
        } else {
            GradientScrim(direction: GradientDirection.Bottom,
                stops: [(0.0, bg.withAlpha(242)), (1.0, bg.withAlpha(191))])
        }
        // 底边 1px panelEdge（原型 border-bottom）。
        ReaderBarEdge()
        HStack {
            GhostIconButton(GhostGlyph.Back, "readerbar:back") {=>
                model.openDetail(model.readerArcid)
            }
            GhostIconButton(GhostGlyph.Menu, "readerbar:pagenav") {=> model.toggleReaderSidebar() }
            // 标题 flex 吃掉中间剩余宽（原型 .tb-title flex:1；超长整体省略号截断）。
            ReaderTitle(archiveTitle, chapter).flex()
            pagePill(model)
            GhostIconButton(GhostGlyph.Theme, "readerbar:theme") {=>
                model.setTheme(if (model.settings.theme == "dark") { "light" } else { "dark" })
            }
            ReaderModeButton(model)
            GhostIconButton(GhostGlyph.Heart, "readerbar:fav", active: favorited) {=>
                model.toggleReaderFavorite()
            }
            GhostIconButton(GhostGlyph.Gear, "readerbar:settings") {=> model.toggleReaderSettings() }
            WinSep()
            WinControlButton(WinGlyph.Min, "readerbar:min") { _ => window.minimize() }
            WinControlButton(WinGlyph.Max, "readerbar:max") { _ => window.maximize() }
            WinControlButton(WinGlyph.Close, "readerbar:close") { ctx => ctx.requestClose() }
        }.spacing(6.0).crossAxisAlignment(CrossAxisAlignment.Center).padding(12.0, 0.0, 12.0, 0.0)
    // alignment 是 ZStack 专有链式，须排在通用修饰器 height 之前（同 titleBar 写法）。
    }.alignment(Alignment.TopLeading).height(Float32(READER_BAR_HEIGHT))
}

// ── chrome 显隐滑动容器（reader-redesign #topbar transform 过渡）──
// 位移走 .offset 修饰器（layout 期平移子树，命中测试随位移——滑出屏的 chrome 不可点，
// 见 widget.cj offset 注释）；不用「布局高度随动画收放」方案——那会让页面区跟动画重排、
// 图像反复缩放闪动，原型也是舞台全高、顶栏叠层浮在上面（main.cj ZStack 方案 b）。
// 应用层无法 buildChild 包裹子树做自绘位移容器（cui.core 未导出，见 widgets.cj ClickArea
// 注释），故 Spring 由一个零尺寸叶子（ReaderChromeTicker）在 draw 里逐帧推进，构建期读
// 上一帧推进后的值决定本帧位移（弹簧逐帧差一帧无感）。原型 topbar 只有位移没有淡入，
// 且 cui 的 opacity 修饰器只淡 surface 不淡文字，故不叠透明度。

// chrome 滑动画弹簧的逐帧推进器：零尺寸、不绘不交互，只在 draw 里 animate 并续帧。
private class ReaderChromeTicker <: Widget {
    private let spring: Spring
    private let showing: Bool
    private let builtT: Float32 // 本帧构建用的位移值（上一帧 draw 的推进结果）

    public init(spring: Spring, visible: Bool, builtT: Float32) {
        this.spring = spring
        this.showing = visible
        this.builtT = builtT
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, _: Rect): Unit {
    }

    public func draw(ctx: UiContext): Unit {
        let t = spring.animate(ctx, target: if (showing) {
            1.0
        } else {
            0.0
        })
        // animate 停稳帧返回目标值，但本帧构建用的还是旧值：补一帧让停稳值落到布局上
        //（隐藏到 0 后下一帧重建即卸载顶栏，见 readerTopBarChrome 的构建条件）。
        if (t != builtT) {
            ctx.requestFrame()
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 阅读器顶栏 + chrome 显隐动画。chrome 可见或滑动未停时构建子树并位移绘制；
// 完全隐藏且停稳后整栏不构建（不吃事件、不注册焦点，同 Drawer 的收尾思路）。
public func readerTopBarChrome(window: SdlWindow, model: AppModel): Unit {
    let visible = model.reader.chromeVisible
    // 弹簧跨帧驻留；初值取当前可见性（静态首帧即停稳，快照稳定，同 Drawer 惯例）。
    let spring = rememberState<Spring>("reader:topbar:slide",
        {=> Spring(if (model.reader.chromeVisible) {
            1.0
        } else {
            0.0
        }, stiffness: 260.0, damping: 26.0) }).value
    let t = spring.value
    if (visible || t != 0.0 || !spring.settled()) {
        ReaderChromeTicker(spring, visible, t)
        // 位移量 = (1-t)×栏高：t=1 原位，t=0 整体上滑出屏（弹簧过冲 t>1 时自然回弹）。
        ZStack {
            readerTitleBar(window, model)
        }.alignment(Alignment.TopLeading).offset(x: 0.0, y: -(1.0 - t) * Float32(READER_BAR_HEIGHT))
    }
}
