package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import std.collection.ArrayList

// ── 自定义标题栏（无边框窗口顶栏）──
// 布局对齐仓库根 home-detail-redesign.html #topbar：高 56vp、底边 1px panelEdge；
// 左→右 = 品牌（金色圆角方块 + Lanlu）→ 弹性空隙 → 全局搜索框（icon + 占位 + kbd「/」，
// flex 封顶 460vp，在品牌与右侧固定带之间水平居中）→ 弹性空隙 → 导航胶囊（首页/书架/在线源，
// 后两项无页面置灰）→ ⚙ 设置 → ◐ 主题 → 用户芯片 → 1×20 分隔线 → 最小化/最大化/关闭。
// 窗口拖动走 SdlWindow.setDragRegions 多矩形（main.cj 注册：品牌区 + 搜索框两侧的弹性空隙，
// 见 titleBarDragRects）——DRAGGABLE 内鼠标事件不投递给应用，
// 故所有交互控件都必须落在注册矩形之外。双击最大化手势因同一限制放弃（YAGNI）。

// 标题栏高（vp）；main.cj 注册拖动区时同用。
public let TITLEBAR_HEIGHT: Int32 = 56

// ── 拖动区几何（逻辑 vp）──
// 品牌区：左内边距 16 + 方块 28 + 间距 9 + 「Lanlu」15fp ≈ 45 ≈ 98，注册 100 留边。
private let DRAG_BRAND_W: Int32 = 100
// 搜索框视觉规格（原型 .search-shell）：圆角 10、左侧图标位、右侧 kbd 位。
// MAX_W 提前到此：titleBarDragRects 要用它算搜索框落点。
private let SEARCH_MAX_W: Float32 = 460.0
// 右侧固定带保留宽（右内边距 16 + 胶囊 ≈182 + 设置/主题 34×2 + 用户芯片 ≤150 + 分隔线 13
// + 窗口控制 118 + 间距 6×10 ≈ 607，取 640 留安全边；用户名超长的芯片已截断兜底）。
private let DRAG_RIGHT_RESERVE: Int32 = 640

// 返回钮（详情/合集页）占位宽：左内边距 16 + 钮 34 + 间距 10 = 60，品牌矩形右移至 60、
// 左侧预留带同步右移（44 = 钮 34 + 间距 10，即返回钮相对品牌块的位移）。
private let DRAG_BACK_OFFSET: Int32 = 44

// 标题栏拖动矩形集：品牌区恒有；搜索框在品牌区与右侧固定带之间水平居中（前后各一个
// Spacer），两侧弹性空隙各注册一块（窗口过窄空隙不存在则不注册，避免盖住交互控件）。
// hasBack：详情/合集页顶栏最左有返回钮，拖动矩形整体避让（品牌矩形与左预留带右移）。
// 坐标为逻辑 vp。
public func titleBarDragRects(windowWidth: Int32, hasBack: Bool): Array<(Int32, Int32, Int32, Int32)> {
    let rects = ArrayList<(Int32, Int32, Int32, Int32)>()
    let brandX: Int32 = if (hasBack) { 16 + DRAG_BACK_OFFSET } else { 0 }
    rects.add((brandX, 0, DRAG_BRAND_W, TITLEBAR_HEIGHT))
    let leftReserve = brandX + DRAG_BRAND_W
    let freeW = windowWidth - leftReserve - DRAG_RIGHT_RESERVE
    if (freeW > 0) {
        let searchW = min(Int32(SEARCH_MAX_W), freeW)
        let side = (freeW - searchW) / 2
        if (side > 0) {
            rects.add((leftReserve, 0, side, TITLEBAR_HEIGHT))
            rects.add((leftReserve + side + searchW, 0, side, TITLEBAR_HEIGHT))
        }
    }
    rects.toArray()
}

private let WIN_BTN_W: Float32 = 38.0
private let WIN_BTN_H: Float32 = 30.0
private let WIN_BTN_GAP: Float32 = 2.0
// 分隔线占位宽：1vp 线 + 两侧各 6vp 外边距（原型 .win-sep margin:0 6px）。
private let WIN_SEP_W: Float32 = 13.0
// 搜索框左右内缩规格（图标 12..24 位 / kbd 宽 18 + 边距位）。
private let SEARCH_ICON_INSET: Float32 = 26.0 // TextField 左内缩
private let SEARCH_KBD_INSET: Float32 = 30.0  // TextField 右内缩
// 搜索框控件 id（TextField key 即焦点 id；Enter 提交、「/」聚焦、Esc 失焦都按它判定）。
private let SEARCH_FIELD_ID = "titlebar-search"
// SDL_SCANCODE_SLASH（keyFromScancode 未映射的符号键以 RawScancode 透传）。
private let SCANCODE_SLASH: Int32 = 56
// 头像底色（原型 .avatar 渐变 #4a6fa5→#2b3a55，取起色实色近似；renderer 无渐变填充）。
private let AVATAR_BLUE = Color.rgb(0x4A, 0x6F, 0xA5)

// 控制钮图形种类（右侧固定的窗口控制三钮；主题钮已改为 GhostIconButton.Theme 风格）。
// public：阅读器顶栏（reader_bar.cj）复用同一组窗口控制钮。
public enum WinGlyph {
    | Min | Max | Close
}

// 38×30 控制钮：hover 铺圆角底（一般钮 = overlayHover，关闭 = 红底白字），
// 图形全部矢量绘制（不依赖字体符号覆盖），左键抬起命中触发 onClick。
// 自定义 Widget 协议同 widgets.cj 的 NavItem（measure/layout/draw/handle + emit）。
public class WinControlButton <: Widget {
    private let glyph: WinGlyph
    private let hoverId: String
    private let onClick: (UiContext) -> Unit
    private var frame = Rect.zero()

    public init(glyph: WinGlyph, hoverId: String, onClick: (UiContext) -> Unit) {
        this.glyph = glyph
        this.hoverId = hoverId
        this.onClick = onClick
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(WIN_BTN_W, WIN_BTN_H)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        var glyphColor = ctx.theme.mutedText
        if (ctx.isHovered(hoverId)) {
            match (glyph) {
                case WinGlyph.Close =>
                    ctx.renderer.fillRoundedRect(frame, 7.0, LANLU_WIN_CLOSE_HOVER)
                    glyphColor = Color.rgb(255, 255, 255)
                case _ =>
                    ctx.renderer.fillRoundedRect(frame, 7.0, ctx.theme.overlayHover)
                    glyphColor = ctx.theme.text
            }
        }
        let cx = frame.centerX()
        let cy = frame.centerY()
        match (glyph) {
            case WinGlyph.Min =>
                ctx.renderer.fill(Rect(cx - 5.0, cy - 0.6, 10.0, 1.2), glyphColor)
            case WinGlyph.Max =>
                ctx.renderer.strokeRect(Rect(cx - 4.5, cy - 4.5, 9.0, 9.0),
                    Pen(width: 1.2, color: glyphColor))
            case WinGlyph.Close =>
                let pen = Pen(width: 1.2, color: glyphColor)
                ctx.renderer.strokeLine(cx - 4.0, cy - 4.0, cx + 4.0, cy + 4.0, pen)
                ctx.renderer.strokeLine(cx - 4.0, cy + 4.0, cx + 4.0, cy - 4.0, pen)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    // 桌面窗口控制惯例用箭头而非手型（原型 .win-btn 亦无 pointer）。
                    ctx.claimHover(hoverId, CursorShape.Default)
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    onClick(ctx)
                    return true
                }
            case _ => ()
        }
        false
    }
}

// 标题栏底：panel 铺底 + 底部 1px panelEdge 边线（原型 border-bottom）。随 ZStack 拉伸铺满。
private class TitleBarBackground <: Widget {
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
        ctx.renderer.fill(frame, ctx.theme.panel)
        ctx.renderer.fill(Rect(frame.x, frame.bottom() - 1.0, frame.w, 1.0), ctx.theme.panelEdge)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 分隔线：13vp 宽占位（1vp 线 + 两侧各 6vp 外边距），1×20 panelEdge 竖条居中。
// 不用定宽 Spacer 做外边距：Spacer.isFlexible 恒为 true（.width 修饰器不透传），
// 会在 HStack flex 分配中均分剩余空间。public：阅读器顶栏复用。
public class WinSep <: Widget {
    private var frame = Rect.zero()

    public init() {
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(WIN_SEP_W, 20.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        ctx.renderer.fill(Rect(frame.centerX() - 0.5, frame.y, 1.0, frame.h), ctx.theme.panelEdge)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 搜索框外壳（原型 .search-shell）：panel 底 + 1px 描边（hover/聚焦时 accent 40%）+
// 左侧放大镜矢量图标 + 空态占位文案 + 右侧 kbd「/」。仅绘制：文本编辑由上层
// TextField 承担（左右内缩避开图标/kbd 位），本件不消费点击。
private class SearchChrome <: Widget {
    private let model: AppModel
    private let hoverId: String
    private var frame = Rect.zero()

    public init(model: AppModel) {
        this.model = model
        this.hoverId = "titlebar:search-chrome"
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let focused = ctx.hasFocus(SEARCH_FIELD_ID)
        ctx.renderer.fillRoundedRect(frame, 10.0, ctx.theme.panel)
        let edge = if (focused || ctx.isHovered(hoverId)) {
            // accent 40% 描边（原型 .search-shell:hover/:focus-within）。
            let a = ctx.theme.accent
            a.withAlpha(102)
        } else {
            ctx.theme.panelEdge
        }
        ctx.renderer.strokeRoundedRect(frame.inset(0.5), 9.5, Pen(width: 1.0, color: edge))
        // 左侧放大镜（⌕ 的矢量等价）。
        let iconColor = ctx.theme.mutedText
        let pen = Pen(width: 1.3, color: iconColor)
        ctx.renderer.strokeCircle(frame.x + 14.0, frame.centerY() - 1.0, 4.2, pen)
        ctx.renderer.strokeLine(frame.x + 17.2, frame.centerY() + 2.2, frame.x + 20.4,
            frame.centerY() + 5.4, pen)
        // 右侧 kbd「/」（原型 .kbd：1px 边、圆角 5、10.5fp muted）。
        let kw: Float32 = 18.0
        let kh: Float32 = 18.0
        let kx = frame.right() - 8.0 - kw
        let ky = frame.centerY() - kh / 2.0
        ctx.renderer.strokeRoundedRect(Rect(kx + 0.5, ky + 0.5, kw - 1.0, kh - 1.0), 4.5,
            Pen(width: 1.0, color: ctx.theme.panelEdge))
        let sw = ctx.renderer.textWidth("/", pointSize: 10.5)
        let sh = ctx.renderer.textHeight(pointSize: 10.5)
        ctx.renderer.text("/", kx + (kw - sw) / 2.0, ky + (kh - sh) / 2.0, ctx.theme.mutedText,
            pointSize: 10.5)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    ctx.claimHover(hoverId, CursorShape.Text)
                }
            case _ => ()
        }
        false
    }
}

// 搜索框占位层：叠在 TextField 之上（TextField 自带 chrome 会盖住底层 SearchChrome
// 画的占位文案），空态且未聚焦时画占位文本；不消费任何事件，点击穿透给 TextField。
private class SearchPlaceholder <: Widget {
    private let model: AppModel
    private var frame = Rect.zero()

    public init(model: AppModel) {
        this.model = model
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        // 占位文案仅在有输入时隐藏（与浏览器 placeholder 一致：聚焦但为空时仍显示）。
        if (model.searchText.value.size > 0) { return }
        let ph = "搜索标题 / 标签 / 艺术家…"
        let th = ctx.renderer.textHeight(pointSize: 13.0)
        ctx.renderer.text(ph, frame.x + SEARCH_ICON_INSET + 12.0, frame.centerY() - th / 2.0,
            ctx.theme.mutedText, pointSize: 13.0)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}


// 搜索框按键接线（ZStack 顶层、不消费鼠标事件的纯键盘件）：
// Enter（聚焦时）→ 提交搜索；Esc（聚焦时）→ 失焦；「/」（无任何控件聚焦时）→ 聚焦搜索框。
// 聚焦由 KeyDown 触发，同帧随后的 TextInput("/") 会被聚焦后的 TextField 收下——用
// rememberState 标志把它吃掉，避免搜索框里凭空多一个「/」。
private class SearchKeys <: Widget {
    private let model: AppModel
    private let slashPending: State<Bool>

    public init(model: AppModel) {
        this.model = model
        this.slashPending = rememberState<Bool>("titlebar:slash-pending", {=> false })
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, _: Rect): Unit {}

    public func draw(_: UiContext): Unit {}

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.KeyDown(Key.Enter, _) =>
                if (ctx.hasFocus(SEARCH_FIELD_ID)) {
                    model.submitFilter()
                    return true
                }
            case UiEvent.KeyDown(Key.Escape, _) =>
                if (ctx.hasFocus(SEARCH_FIELD_ID)) {
                    ctx.clearFocus()
                    return true
                }
            case UiEvent.KeyDown(Key.RawScancode(code), _) =>
                // 任意输入控件聚焦时让路（不打断登录框等正常输入）。
                if (code == SCANCODE_SLASH && ctx.focusId == "") {
                    ctx.focus(SEARCH_FIELD_ID, viaKeyboard: true)
                    slashPending.value = true
                    return true
                }
            case UiEvent.TextInput(value) =>
                if (slashPending.value && value == "/") {
                    slashPending.value = false
                    return true
                }
            case UiEvent.Frame(_) =>
                slashPending.value = false
            case _ => ()
        }
        false
    }
}

// 导航胶囊（原型 .nav-pill）：elev 底 + 1px 描边 + 全圆角容器，选中项 accentSoft 底 +
// accent 字。「首页」点击回书库页；「书架」「在线源」无对应页面，置灰禁用（点击无反应，
// hover 不给手型——比假跳转诚实）。
private class NavPill <: Widget {
    private let model: AppModel
    private let labels = ["首页", "书架", "在线源"]
    private var frame = Rect.zero()

    public init(model: AppModel) {
        this.model = model
        emit(this)
    }

    private func itemWidth(ctx: UiContext, label: String): Float32 {
        ctx.renderer.textWidth(label, pointSize: 12.5) + 28.0 // 原型 padding:6px 14px
    }

    public func measure(ctx: UiContext, _: Size): Size {
        var w = 6.0 + 2.0 * Float32(labels.size - 1) // 容器 padding 3×2 + 项间距 2
        for (l in labels) {
            w += itemWidth(ctx, l)
        }
        Size(w, 32.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    // 「首页」项矩形（其余项禁用，不需要命中区）。
    private func homeRect(ctx: UiContext): Rect {
        Rect(frame.x + 3.0, frame.y + 3.0, itemWidth(ctx, labels[0]), frame.h - 6.0)
    }

    public func draw(ctx: UiContext): Unit {
        ctx.renderer.fillRoundedRect(frame, frame.h / 2.0, ctx.theme.panel)
        ctx.renderer.strokeRoundedRect(frame.inset(0.5), frame.h / 2.0 - 0.5,
            Pen(width: 1.0, color: ctx.theme.panelEdge))
        var x = frame.x + 3.0
        for (i in 0..labels.size) {
            let w = itemWidth(ctx, labels[i])
            let item = Rect(x, frame.y + 3.0, w, frame.h - 6.0)
            let th = ctx.renderer.textHeight(pointSize: 12.5)
            if (i == 0) {
                // 首页恒为选中态（本客户端当前唯一已实现的导航目标）。
                ctx.renderer.fillRoundedRect(item, item.h / 2.0, ctx.theme.accentSoft)
                drawPillText(ctx, labels[i], item, th, ctx.theme.accent)
            } else {
                // 禁用态：muted 再降透明度，视觉置灰。
                let m = ctx.theme.mutedText
                drawPillText(ctx, labels[i], item, th, m.withAlpha(110))
            }
            x += w + 2.0
        }
    }

    private func drawPillText(ctx: UiContext, label: String, item: Rect, th: Float32, color: Color): Unit {
        let tw = ctx.renderer.textWidth(label, pointSize: 12.5)
        ctx.renderer.text(label, item.centerX() - tw / 2.0, item.centerY() - th / 2.0, color,
            pointSize: 12.5)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (homeRect(ctx).contains(x, y)) {
                    ctx.claimHover("titlebar:nav-home", CursorShape.Interactive)
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (homeRect(ctx).contains(x, y)) {
                    model.page.value = Page.Library
                    return true
                }
            case _ => ()
        }
        false
    }
}

// Rune 切片转字符串（Array<Rune> 无直接 toString，逐 rune append）。
private func runesToString(runes: Array<Rune>, start: Int64, end: Int64): String {
    let builder = StringBuilder()
    var i = start
    while (i < end) {
        builder.append(runes[i])
        i += 1
    }
    builder.toString()
}

// 用户芯片（原型 .user-chip）：elev 胶囊 + 圆形头像（username 首字母）+ 用户名文本。
// 纯展示不交互（账号操作在设置页）；用户名超 8 字截断，防止把右侧固定带撑出拖动区预算。
private class UserChip <: Widget {
    private let model: AppModel
    private var frame = Rect.zero()

    public init(model: AppModel) {
        this.model = model
        emit(this)
    }

    // 用户名截断（>8 rune 截断 + …）：防止超长名把右侧固定带撑出拖动区预算。
    private func displayName(): String {
        let runes = model.settings.username.toRuneArray()
        runesToString(runes, 0, min(runes.size, 8)) + if (runes.size > 8) { "…" } else { "" }
    }

    public func measure(ctx: UiContext, _: Size): Size {
        let w = 4.0 + 24.0 + 7.0 + ctx.renderer.textWidth(displayName(), pointSize: 12.0) + 10.0
        Size(w, 32.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        ctx.renderer.fillRoundedRect(frame, frame.h / 2.0, ctx.theme.panel)
        ctx.renderer.strokeRoundedRect(frame.inset(0.5), frame.h / 2.0 - 0.5,
            Pen(width: 1.0, color: ctx.theme.panelEdge))
        let ax = frame.x + 4.0 + 12.0
        ctx.renderer.fillCircle(ax, frame.centerY(), 12.0, AVATAR_BLUE)
        let initial = initialLetter()
        let tw = ctx.renderer.textWidth(initial, pointSize: 11.0)
        let th = ctx.renderer.textHeight(pointSize: 11.0)
        ctx.renderer.text(initial, ax - tw / 2.0, frame.centerY() - th / 2.0,
            Color.rgb(255, 255, 255), pointSize: 11.0)
        let name = displayName()
        let nw = ctx.renderer.textWidth(name, pointSize: 12.0)
        let nh = ctx.renderer.textHeight(pointSize: 12.0)
        ctx.renderer.text(name, frame.right() - 10.0 - nw, frame.centerY() - nh / 2.0,
            ctx.theme.mutedText, pointSize: 12.0)
    }

    // 首 rune 作头像字母（空名兜底 U；不做大小写变换，中日韩文字原样亦成立）。
    private func initialLetter(): String {
        let runes = model.settings.username.toRuneArray()
        if (runes.size == 0) { return "U" }
        runesToString(runes, 0, 1)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 自定义标题栏：品牌 + 全局搜索 + 导航胶囊 + 设置/主题 + 用户芯片 + 分隔线 +
// 最小化/最大化/关闭。登录页只保留品牌与右侧主题/窗口控制（无可搜内容、无会话用户）。
// 最小化/最大化经 SdlWindow 扩展直达，关闭走 ctx.requestClose()。
public func titleBar(window: SdlWindow, model: AppModel): Unit {
    let onLogin = match (model.page.value) {
        case Page.Login => true
        case _ => false
    }
    // 返回钮（原型 #btn-back）：详情/合集/设置视图显示，顶栏最左、品牌区之前。
    let showBack = match (model.page.value) {
        case Page.Detail(_) | Page.Tank(_) | Page.Settings => true
        case _ => false
    }
    ZStack {
        TitleBarBackground()
        HStack {
            if (showBack) {
                GhostIconButton(GhostGlyph.Back, "titlebar:back") {=> model.page.value = Page.Library }
            }
            HStack {
                brandLogo(model, 28.vp)
                Label("Lanlu").fontSize(15.fp)
            }.spacing(9.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
            if (!onLogin) {
                // 搜索框在品牌与右侧固定带之间水平居中（前后各一个弹性 Spacer）。
                Spacer()
                ZStack {
                    SearchChrome(model)
                    // chrome 关闭：外壳由 SearchChrome 自绘，避免 TextField 默认底/边再套一层。
                    TextField(model.searchText, key: SEARCH_FIELD_ID, chrome: false)
                        .padding(SEARCH_ICON_INSET + 4.0, 0.0, SEARCH_KBD_INSET + 4.0, 0.0)
                    SearchPlaceholder(model)
                }.alignment(Alignment.TopLeading).flex().maxWidth(SEARCH_MAX_W)
                Spacer()
                NavPill(model)
                GhostIconButton(GhostGlyph.Gear, "titlebar:settings") {=>
                    model.page.value = Page.Settings
                }
            } else {
                Spacer()
            }
            GhostIconButton(GhostGlyph.Theme, "titlebar:theme") {=>
                model.setTheme(if (model.settings.theme == "dark") { "light" } else { "dark" })
            }
            if (!onLogin && model.settings.username.size > 0) {
                UserChip(model)
            }
            WinSep()
            WinControlButton(WinGlyph.Min, "titlebar:min") { _ => window.minimize() }
            WinControlButton(WinGlyph.Max, "titlebar:max") { _ => window.maximize() }
            WinControlButton(WinGlyph.Close, "titlebar:close") { ctx => ctx.requestClose() }
        }.spacing(10.0).crossAxisAlignment(CrossAxisAlignment.Center).padding(16.0, 0.0, 16.0, 0.0)
        // 顶层键盘接线件：最后声明 = 事件分发最优先（只吃不相关鼠标事件之外的键）。
        SearchKeys(model)
    // alignment 是 ZStack 专有链式，须排在返回 Widget 的通用修饰器 height 之前。
    }.alignment(Alignment.TopLeading).height(Float32(TITLEBAR_HEIGHT))
}
