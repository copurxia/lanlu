package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import std.collection.ArrayList

// ── 自定义标题栏（无边框窗口顶栏）──
// 布局对齐仓库根 home-detail-redesign.html #topbar：高 56vp、底边 1px panelEdge；
// 左→右 = 品牌（金色圆角方块 + Lanlu）→ 弹性空隙 → 全局搜索框（icon + 占位 + kbd「/」，
// 默认封顶 460vp，点击/聚焦后展开至 680vp，在品牌与右侧固定带之间水平居中）→
// 弹性空隙 → 导航胶囊（首页/书架/在线源，
// 后两项无页面置灰）→ ◐ 主题 → 用户菜单 → 1×20 分隔线 → 最小化/最大化/关闭。
// 窗口拖动走 SdlWindow.setDragRegions 多矩形（main.cj 注册：品牌区 + 搜索框两侧的弹性空隙，
// 见 titleBarDragRects）——DRAGGABLE 内鼠标事件不投递给应用，
// 故所有交互控件都必须落在注册矩形之外。双击最大化手势因同一限制放弃（YAGNI）。

// 标题栏高（vp）；main.cj 注册拖动区时同用。
public let TITLEBAR_HEIGHT: Int32 = 56

// ── 拖动区几何（逻辑 vp）──
// 品牌区：左内边距 16 + 方块 28 + 间距 9 + 「Lanlu」15fp ≈ 45 ≈ 98，注册 100 留边。
private let DRAG_BRAND_W: Int32 = 100
// 搜索框视觉规格（原型 .search-shell）：圆角 10、左侧图标位、右侧 kbd 位。
// 拖动区始终按展开宽度避让：动画中搜索框不会被 OS 拖动命中区覆盖。
private let SEARCH_REST_W: Float32 = 460.0
private let SEARCH_EXPANDED_W: Float32 = 680.0
private let SEARCH_EXPAND_MS: Int64 = 220
// 首页搜索框右侧筛选钮占 34vp，外加 HStack 的 10vp 间距。
private let FILTER_BUTTON_SLOT_W: Float32 = 44.0
// 右侧固定带保留宽（右内边距 16 + 胶囊 ≈182 + 主题 34 + 用户芯片 ≤166 + 分隔线 13
// + 窗口控制 118 + 间距 ≈ 80，取 640 留安全边；用户名超长的芯片已截断兜底）。
private let DRAG_RIGHT_RESERVE: Int32 = 640

// 返回钮（详情/合集页）占位宽：左内边距 16 + 钮 34 + 间距 10 = 60，品牌矩形右移至 60、
// 左侧预留带同步右移（44 = 钮 34 + 间距 10，即返回钮相对品牌块的位移）。
private let DRAG_BACK_OFFSET: Int32 = 44

// 标题栏拖动矩形集：品牌区恒有；搜索框在品牌区与右侧固定带之间水平居中（前后各一个
// Spacer），两侧弹性空隙各注册一块（窗口过窄空隙不存在则不注册，避免盖住交互控件）。
// hasBack：详情/合集页顶栏最左有返回钮，拖动矩形整体避让（品牌矩形与左预留带右移）；
// hasFilter：首页搜索框右侧有筛选钮，搜索簇与右侧拖动带均须为它留出命中空间。
// 坐标为逻辑 vp。
public func titleBarDragRects(windowWidth: Int32, hasBack: Bool, hasFilter: Bool): Array<(Int32, Int32, Int32, Int32)> {
    let rects = ArrayList<(Int32, Int32, Int32, Int32)>()
    let brandX: Int32 = if (hasBack) {
        16 + DRAG_BACK_OFFSET
    } else {
        0
    }
    rects.add((brandX, 0, DRAG_BRAND_W, TITLEBAR_HEIGHT))
    let leftReserve = brandX + DRAG_BRAND_W
    let freeW = windowWidth - leftReserve - DRAG_RIGHT_RESERVE
    if (freeW > 0) {
        let filterSlot: Int32 = if (hasFilter) {
            Int32(FILTER_BUTTON_SLOT_W)
        } else {
            0
        }
        let searchW = min(Int32(SEARCH_EXPANDED_W), max(0, freeW - filterSlot))
        let searchClusterW = searchW + filterSlot
        let side = (freeW - searchClusterW) / 2
        if (side > 0) {
            rects.add((leftReserve, 0, side, TITLEBAR_HEIGHT))
            rects.add((leftReserve + side + searchClusterW, 0, side, TITLEBAR_HEIGHT))
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
private let SEARCH_KBD_INSET: Float32 = 30.0 // TextField 右内缩
// 搜索框控件 id（TextField key 即焦点 id；Enter 提交、「/」聚焦、Esc 失焦都按它判定）。
private let SEARCH_FIELD_ID = "titlebar-search"
// SDL_SCANCODE_SLASH（keyFromScancode 未映射的符号键以 RawScancode 透传）。
private let SCANCODE_SLASH: Int32 = 56
// 头像底色（原型 .avatar 渐变 #4a6fa5→#2b3a55，取起色实色近似；renderer 无渐变填充）。
private let AVATAR_BLUE = Color.rgb(0x4A, 0x6F, 0xA5)
private let USER_MENU_OWNER = "titlebar:user-menu"
private let USER_MENU_WIDTH: Float32 = 176.0
private let USER_MENU_ROW_HEIGHT: Float32 = 36.0
private let USER_MENU_PADDING: Float32 = 6.0
private let USER_MENU_GROUP_GAP: Float32 = 9.0
private let USER_MENU_ITEM_COUNT: Int64 = 4
private let USER_MENU_ANIMATION_MS: Int64 = 180
private let USER_MENU_ENTER_OFFSET_Y: Float32 = 4.0
private let USER_MENU_ENTER_SCALE: Float32 = 0.97
private let USER_SERVER_MENU_WIDTH: Float32 = 228.0
private let USER_SERVER_MENU_ROW_HEIGHT: Float32 = 46.0
private let USER_SERVER_MENU_ANIMATION_MS: Int64 = 160
private let USER_SERVER_MENU_OVERLAP: Float32 = 2.0
private let USER_MENU_LIGHT_SURFACE = Color.rgb(255, 255, 255)
private let USER_MENU_LIGHT_BORDER = Color.rgba(0, 0, 0, 28)
private let USER_MENU_LIGHT_TEXT = Color.rgb(0x1D, 0x1D, 0x21)
private let USER_MENU_LIGHT_HOVER = Color.rgb(0xF2, 0xF2, 0xF4)

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
            case WinGlyph.Min => ctx.renderer.fill(Rect(cx - 5.0, cy - 0.6, 10.0, 1.2), glyphColor)
            case WinGlyph.Max => ctx
                .renderer
                .strokeRect(Rect(cx - 4.5, cy - 4.5, 9.0, 9.0), Pen(width: 1.2, color: glyphColor))
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
        ctx.renderer.strokeLine(frame.x + 17.2, frame.centerY() + 2.2, frame.x + 20.4, frame.centerY() + 5.4, pen)
        // 右侧 kbd「/」（原型 .kbd：1px 边、圆角 5、10.5fp muted）。
        let kw: Float32 = 18.0
        let kh: Float32 = 18.0
        let kx = frame.right() - 8.0 - kw
        let ky = frame.centerY() - kh / 2.0
        ctx
            .renderer
            .strokeRoundedRect(Rect(kx + 0.5, ky + 0.5, kw - 1.0, kh - 1.0), 4.5,
                Pen(width: 1.0, color: ctx.theme.panelEdge))
        let sw = ctx.renderer.textWidth("/", pointSize: 10.5)
        let sh = ctx.renderer.textHeight(pointSize: 10.5)
        ctx.renderer.text("/", kx + (kw - sw) / 2.0, ky + (kh - sh) / 2.0, ctx.theme.mutedText, pointSize: 10.5)
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
    private let shelf: Bool
    private var frame = Rect.zero()

    public init(model: AppModel, shelf: Bool) {
        this.model = model
        this.shelf = shelf
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
        let value = if (shelf) {
            model.shelfSearchText.value
        } else {
            model.searchText.value
        }
        if (value.size > 0) {
            return
        }
        let ph = if (shelf) {
            model.t("shelf.search")
        } else {
            model.t("nav.search")
        }
        let th = ctx.renderer.textHeight(pointSize: 13.0)
        ctx
            .renderer
            .text(ph, frame.x + SEARCH_ICON_INSET + 12.0, frame.centerY() - th / 2.0, ctx.theme.mutedText,
                pointSize: 13.0)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 搜索框聚焦动画的逐帧推进器。构建期使用 Tween 上一帧的值计算宽度，
// draw 期再读取 TextField 的真实焦点并推进动画；补请求一帧使最后的 0/1 精确落到布局上。
private class SearchExpandTicker <: Widget {
    private let tween: Tween
    private let builtProgress: Float32

    public init(tween: Tween, builtProgress: Float32) {
        this.tween = tween
        this.builtProgress = builtProgress
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, _: Rect): Unit {}

    public func draw(ctx: UiContext): Unit {
        let progress = tween.animate(ctx, target: if (ctx.hasFocus(SEARCH_FIELD_ID)) {
            1.0
        } else {
            0.0
        })
        if (progress != builtProgress) {
            ctx.requestFrame()
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

private func searchWidth(progress: Float32): Float32 {
    SEARCH_REST_W + (SEARCH_EXPANDED_W - SEARCH_REST_W) * progress
}

// 以与拖动区相同的几何预算限制宽度：常规窗口拿到完整动画宽度，
// 窄窗口则优先保留右侧导航/窗口按钮，搜索框自适应收窄。
private func searchLayoutWidth(windowWidth: Int32, hasBack: Bool, hasFilter: Bool, progress: Float32): Float32 {
    let brandX: Int32 = if (hasBack) {
        16 + DRAG_BACK_OFFSET
    } else {
        0
    }
    let filterSlot: Float32 = if (hasFilter) {
        FILTER_BUTTON_SLOT_W
    } else {
        0.0
    }
    let available = max(0.0, Float32(windowWidth - brandX - DRAG_BRAND_W - DRAG_RIGHT_RESERVE) - filterSlot)
    min(searchWidth(progress), available)
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
        this.slashPending = rememberState<Bool>("titlebar:slash-pending", {=> false})
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
            case UiEvent.Frame(_) => slashPending.value = false
            case _ => ()
        }
        false
    }
}

// 导航胶囊（原型 .nav-pill）：首页与书架均为真实页面；在线源尚未落地，保持禁用。
// 选中底块用一个 0（首页）↔ 1（书架）的弹簧驱动，并在两端实际 Rect 之间插值，
// 因此中英文标签宽度不同也能同时平滑改变 x / width；弹簧初值取当前上下文，首帧静止。
private class NavPill <: Widget {
    private let model: AppModel
    private let labels: Array<String>
    private let indicatorSpring: Spring
    private var frame = Rect.zero()

    public init(model: AppModel) {
        this.model = model
        this.labels = [model.t("nav.home"), model.t("nav.shelf"), model.t("nav.sources")]
        let start: Float32 = if (model.isShelfContext()) {
            1.0
        } else {
            0.0
        }
        this.indicatorSpring = rememberState<Spring>("titlebar:nav:indicator", {
            => Spring(start, stiffness: 260.0, damping: 28.0)
        }).value
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

    private func itemRect(ctx: UiContext, index: Int64): Rect {
        var x = frame.x + 3.0
        var i: Int64 = 0
        while (i < index) {
            x += itemWidth(ctx, labels[i]) + 2.0
            i++
        }
        Rect(x, frame.y + 3.0, itemWidth(ctx, labels[index]), frame.h - 6.0)
    }

    public func draw(ctx: UiContext): Unit {
        ctx.renderer.fillRoundedRect(frame, frame.h / 2.0, ctx.theme.panel)
        ctx.renderer.strokeRoundedRect(frame.inset(0.5), frame.h / 2.0 - 0.5, Pen(width: 1.0, color: ctx
            .theme
            .panelEdge))
        let target: Float32 = if (model.isShelfContext()) {
            1.0
        } else {
            0.0
        }
        // 钳制轻微的弹簧过冲，避免高亮越出首尾可选项；速度与回弹仍由 Spring 保留。
        let position = clampF32(indicatorSpring.animate(ctx, target: target), 0.0, 1.0)
        let home = itemRect(ctx, 0)
        let shelf = itemRect(ctx, 1)
        let indicator = Rect(home.x + (shelf.x - home.x) * position, home.y, home.w + (shelf.w - home.w) * position,
            home.h)
        ctx.renderer.fillRoundedRect(indicator, indicator.h / 2.0, ctx.theme.accentSoft)

        var x = frame.x + 3.0
        for (i in 0..labels.size) {
            let w = itemWidth(ctx, labels[i])
            let item = Rect(x, frame.y + 3.0, w, frame.h - 6.0)
            let th = ctx.renderer.textHeight(pointSize: 12.5)
            if (i == 0) {
                drawPillText(ctx, labels[i], item, th, ctx.theme.mutedText.lerp(ctx.theme.accent, 1.0 - position))
            } else if (i == 1) {
                drawPillText(ctx, labels[i], item, th, ctx.theme.mutedText.lerp(ctx.theme.accent, position))
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
        ctx.renderer.text(label, item.centerX() - tw / 2.0, item.centerY() - th / 2.0, color, pointSize: 12.5)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (itemRect(ctx, 0).contains(x, y) || itemRect(ctx, 1).contains(x, y)) {
                    ctx.claimHover("titlebar:nav", CursorShape.Interactive)
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (itemRect(ctx, 0).contains(x, y)) {
                    model.openHome()
                    return true
                }
                if (itemRect(ctx, 1).contains(x, y)) {
                    model.openShelf()
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

// 用户菜单（原型 .user-chip）：点击用户信息展开上传、设置、切换服务器与退出登录。
// 菜单通过 Overlay 绘制在页面之上；点击外部/Esc 关闭，方向键与 Enter 可操作。
// 用户名超 8 字截断，防止把右侧固定带撑出拖动区预算。
private class UserMenuChip <: Widget {
    private let model: AppModel
    private let logoutOpen: State<Bool>
    private let open: State<Bool>
    private let highlight: State<Int64>
    private let popupAnim: Tween
    private let serverMenuOpen: State<Bool>
    private let serverHighlight: State<Int64>
    private let serverMenuAnim: Tween
    private var frame = Rect.zero()

    public init(model: AppModel, logoutOpen: State<Bool>) {
        this.model = model
        this.logoutOpen = logoutOpen
        this.open = rememberState<Bool>("${USER_MENU_OWNER}:open", {=> false})
        this.highlight = rememberState<Int64>("${USER_MENU_OWNER}:highlight", {=> -1})
        this.popupAnim = rememberState<Tween>("${USER_MENU_OWNER}:anim", {
            => Tween(USER_MENU_ANIMATION_MS, {t => Easing.easeOutCubic(t)})
        }).value
        this.serverMenuOpen = rememberState<Bool>("${USER_MENU_OWNER}:server-open", {=> false})
        this.serverHighlight = rememberState<Int64>("${USER_MENU_OWNER}:server-highlight", {=> -1})
        this.serverMenuAnim = rememberState<Tween>("${USER_MENU_OWNER}:server-anim", {
            => Tween(USER_SERVER_MENU_ANIMATION_MS, {t => Easing.easeOutCubic(t)})
        }).value
        emit(this)
    }

    // 用户名截断（>8 rune 截断 + …）：防止超长名把右侧固定带撑出拖动区预算。
    private func displayName(): String {
        let runes = model.settings.username.toRuneArray()
        runesToString(runes, 0, min(runes.size, 8)) + if (runes.size > 8) {
            "…"
        } else {
            ""
        }
    }

    public func measure(ctx: UiContext, _: Size): Size {
        let w = 4.0 + 24.0 + 7.0 + ctx.renderer.textWidth(displayName(), pointSize: 12.0) + 6.0 + 12.0 + 8.0
        Size(w, 32.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let _ = model.serversVersion.value
        let hovered = ctx.isHovered(USER_MENU_OWNER)
        ctx.renderer.fillRoundedRect(frame, frame.h / 2.0, if (hovered || open.value) {
            ctx.theme.overlayHover
        } else {
            ctx.theme.panel
        })
        ctx
            .renderer
            .strokeRoundedRect(frame.inset(0.5), frame.h / 2.0 - 0.5, Pen(width: 1.0, color: if (open.value) {
                ctx.theme.accent
            } else {
                ctx.theme.panelEdge
            }))
        let ax = frame.x + 4.0 + 12.0
        ctx.renderer.fillCircle(ax, frame.centerY(), 12.0, AVATAR_BLUE)
        let initial = initialLetter()
        let tw = ctx.renderer.textWidth(initial, pointSize: 11.0)
        let th = ctx.renderer.textHeight(pointSize: 11.0)
        ctx.renderer.text(initial, ax - tw / 2.0, frame.centerY() - th / 2.0, Color.rgb(255, 255, 255), pointSize: 11.0)
        let name = displayName()
        let nw = ctx.renderer.textWidth(name, pointSize: 12.0)
        let nh = ctx.renderer.textHeight(pointSize: 12.0)
        let arrowX = frame.right() - 14.0
        ctx.renderer.text(name, arrowX - 10.0 - nw, frame.centerY() - nh / 2.0, ctx.theme.mutedText, pointSize: 12.0)
        drawIcon(ctx.renderer, IconName.ChevronDown, Rect(arrowX - 6.0, frame.centerY() - 6.0, 12.0, 12.0),
            ctx.theme.mutedText)

        // 关闭后保留浮层直至反向动画归零；快速再次点击可从当前进度平滑反转。
        if (open.value || popupAnim.value > 0.0) {
            let menu = popupRect(ctx)
            ctx.setOverlay(Overlay(owner: USER_MENU_OWNER, handleEvent: {
                c, event => if (open.value) {
                    handlePopup(c, event, menu)
                } else {
                    handleClosingPopup(c, event)
                }
            }, render: {c => drawPopup(c, menu)}))
        }
    }

    // 首 rune 作头像字母（空名兜底 U；不做大小写变换，中日韩文字原样亦成立）。
    private func initialLetter(): String {
        let runes = model.settings.username.toRuneArray()
        if (runes.size == 0) {
            return "U"
        }
        runesToString(runes, 0, 1)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    ctx.claimHover(USER_MENU_OWNER, CursorShape.Interactive)
                }
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    openPopup(ctx)
                    return true
                }
            case _ => ()
        }
        false
    }

    private func openPopup(ctx: UiContext): Unit {
        open.value = true
        // 动作菜单没有已选值；鼠标打开时保持无高亮，避免首行色块突现。
        highlight.value = -1
        closeServerMenu(ctx)
        ctx.requestFrame()
    }

    private func popupRect(ctx: UiContext): Rect {
        let height = USER_MENU_PADDING * 2.0 + USER_MENU_ROW_HEIGHT * Float32(USER_MENU_ITEM_COUNT) + USER_MENU_GROUP_GAP
        let x = max(4.0, min(frame.right() - USER_MENU_WIDTH, ctx.viewportWidth - USER_MENU_WIDTH - 4.0))
        let y = min(frame.bottom() + 6.0, ctx.viewportHeight - height - 4.0)
        Rect(x, max(4.0, y), USER_MENU_WIDTH, height)
    }

    private func rowRect(menu: Rect, index: Int64): Rect {
        let groupOffset: Float32 = if (index >= 2) {
            USER_MENU_GROUP_GAP
        } else {
            0.0
        }
        Rect(menu.x + 5.0, menu.y + USER_MENU_PADDING + Float32(index) * USER_MENU_ROW_HEIGHT + groupOffset,
            menu.w - 10.0, USER_MENU_ROW_HEIGHT)
    }

    private func itemAt(menu: Rect, x: Float32, y: Float32): Int64 {
        for (i in 0..USER_MENU_ITEM_COUNT) {
            if (rowRect(menu, i).contains(x, y)) {
                return i
            }
        }
        -1
    }

    private func itemLabel(index: Int64): String {
        match (index) {
            case 0 => model.t("titlebar.uploadFiles")
            case 1 => model.t("common.settings")
            case 2 => model.t("overview.switchServer")
            case 3 => model.t("overview.logout")
            case _ => ""
        }
    }

    private func itemGlyph(index: Int64): GhostGlyph {
        match (index) {
            case 0 => GhostGlyph.Named(IconName.Upload)
            case 1 => GhostGlyph.Gear
            case 2 => GhostGlyph.Swap
            case 3 => GhostGlyph.LogOut
            case _ => GhostGlyph.Menu
        }
    }

    private func serverMenuRect(ctx: UiContext, menu: Rect): Rect {
        let height = USER_MENU_PADDING * 2.0 + USER_SERVER_MENU_ROW_HEIGHT * Float32(model.settings.servers.size)
        let trigger = rowRect(menu, 2)
        let leftX = menu.x - USER_SERVER_MENU_WIDTH + USER_SERVER_MENU_OVERLAP
        let rightX = menu.right() - USER_SERVER_MENU_OVERLAP
        let x = if (leftX >= 4.0) {
            leftX
        } else {
            min(rightX, ctx.viewportWidth - USER_SERVER_MENU_WIDTH - 4.0)
        }
        let y = max(4.0, min(trigger.y - USER_MENU_PADDING, ctx.viewportHeight - height - 4.0))
        Rect(x, y, USER_SERVER_MENU_WIDTH, height)
    }

    private func serverRowRect(menu: Rect, index: Int64): Rect {
        Rect(menu.x + 5.0, menu.y + USER_MENU_PADDING + Float32(index) * USER_SERVER_MENU_ROW_HEIGHT, menu.w - 10.0,
            USER_SERVER_MENU_ROW_HEIGHT)
    }

    private func serverAt(menu: Rect, x: Float32, y: Float32): Int64 {
        for (i in 0..model.settings.servers.size) {
            if (serverRowRect(menu, i).contains(x, y)) {
                return i
            }
        }
        -1
    }

    private func drawPopup(ctx: UiContext, menu: Rect): Unit {
        let target: Float32 = if (open.value) {
            1.0
        } else {
            0.0
        }
        let progress = popupAnim.animate(ctx, target: target)
        let shell = animatedPopupRect(menu, progress)
        let surface = if (model.isLight()) {
            USER_MENU_LIGHT_SURFACE
        } else {
            ctx.theme.panelRaised
        }
        let border = if (model.isLight()) {
            USER_MENU_LIGHT_BORDER
        } else {
            ctx.theme.panelEdge
        }
        let textColor = if (model.isLight()) {
            USER_MENU_LIGHT_TEXT
        } else {
            ctx.theme.text
        }
        let hover = if (model.isLight()) {
            USER_MENU_LIGHT_HOVER
        } else {
            ctx.theme.overlayHover
        }
        // 与普通 Dropdown 一样，表面和阴影随进度渐入；右上角保持锚定，避免横向漂移。
        ctx
            .renderer
            .fillRoundedRectSoft(shell.shift(0.0, 4.0), 10.0, userMenuAlpha(ctx.theme.shadow, progress), feather: 8.0)
        ctx.renderer.fillRoundedRect(shell, 10.0, userMenuAlpha(surface, progress))
        ctx.renderer.strokeRoundedRect(shell.inset(0.5), 9.5, Pen(width: 1.0, color: userMenuAlpha(border, progress)))
        ctx.renderer.pushClip(shell)
        let separatorY = shell.y + USER_MENU_PADDING + USER_MENU_ROW_HEIGHT * 2.0 + USER_MENU_GROUP_GAP / 2.0
        ctx.renderer.fill(Rect(shell.x + 10.0, separatorY, shell.w - 20.0, 1.0), userMenuAlpha(border, progress))

        for (i in 0..USER_MENU_ITEM_COUNT) {
            let row = rowRect(shell, i)
            let selected = i == highlight.value
            if (selected) {
                ctx.renderer.fillRoundedRect(row, 7.0, if (i == 3) {
                    userMenuAlpha(LANLU_DANGER.withAlpha(28), progress)
                } else {
                    userMenuAlpha(hover, progress)
                })
            }
            let color = if (i == 3) {
                LANLU_DANGER
            } else {
                textColor
            }
            let animatedColor = userMenuAlpha(color, progress)
            drawGhostGlyph(ctx.renderer, itemGlyph(i), row.x + 17.0, row.centerY(), animatedColor)
            let label = itemLabel(i)
            let textHeight = ctx.renderer.textHeight(pointSize: 12.0)
            ctx.renderer.text(label, row.x + 34.0, row.centerY() - textHeight / 2.0, animatedColor, pointSize: 12.0)
            if (i == 2) {
                drawIcon(ctx.renderer, IconName.ChevronRight, Rect(row.right() - 18.0, row.centerY() - 6.0, 12.0, 12.0),
                    animatedColor)
            }
        }
        ctx.renderer.popClip()
        if (serverMenuOpen.value || serverMenuAnim.value > 0.0) {
            drawServerPopup(ctx, menu, serverMenuRect(ctx, menu))
        }
        if (!open.value && progress <= 0.0) {
            // 再请求一帧，让不可见的关闭浮层从 overlay 栈彻底移除。
            ctx.requestFrame()
        }
    }

    private func animatedPopupRect(menu: Rect, progress: Float32): Rect {
        let scale = USER_MENU_ENTER_SCALE + (1.0 - USER_MENU_ENTER_SCALE) * progress
        let width = menu.w * scale
        let height = menu.h * scale
        Rect(menu.right() - width, menu.y - USER_MENU_ENTER_OFFSET_Y * (1.0 - progress), width, height)
    }

    private func drawServerPopup(ctx: UiContext, parent: Rect, menu: Rect): Unit {
        let target: Float32 = if (serverMenuOpen.value && open.value) {
            1.0
        } else {
            0.0
        }
        let progress = serverMenuAnim.animate(ctx, target: target)
        let shell = animatedServerPopupRect(parent, menu, progress)
        let surface = if (model.isLight()) {
            USER_MENU_LIGHT_SURFACE
        } else {
            ctx.theme.panelRaised
        }
        let border = if (model.isLight()) {
            USER_MENU_LIGHT_BORDER
        } else {
            ctx.theme.panelEdge
        }
        let textColor = if (model.isLight()) {
            USER_MENU_LIGHT_TEXT
        } else {
            ctx.theme.text
        }
        let hover = if (model.isLight()) {
            USER_MENU_LIGHT_HOVER
        } else {
            ctx.theme.overlayHover
        }
        ctx
            .renderer
            .fillRoundedRectSoft(shell.shift(0.0, 4.0), 10.0, userMenuAlpha(ctx.theme.shadow, progress), feather: 8.0)
        ctx.renderer.fillRoundedRect(shell, 10.0, userMenuAlpha(surface, progress))
        ctx.renderer.strokeRoundedRect(shell.inset(0.5), 9.5, Pen(width: 1.0, color: userMenuAlpha(border, progress)))
        ctx.renderer.pushClip(shell)
        for (i in 0..model.settings.servers.size) {
            let server = model.settings.servers[i]
            let row = serverRowRect(shell, i)
            let current = server.id == model.settings.activeServerId
            if (i == serverHighlight.value && !current) {
                ctx.renderer.fillRoundedRect(row, 7.0, userMenuAlpha(hover, progress))
            }
            let primary = userMenuAlpha(if (current) {
                ctx.theme.accent
            } else {
                textColor
            }, progress)
            let secondary = userMenuAlpha(ctx.theme.mutedText, progress)
            drawIcon(ctx.renderer, IconName.Server, Rect(row.x + 11.0, row.centerY() - 7.0, 14.0, 14.0), primary)
            let hasName = server.name.trimAscii().size > 0
            let name = if (hasName) {
                server.name.trimAscii()
            } else {
                server.baseUrl
            }
            let textX = row.x + 34.0
            let textRight = row.right() - 28.0
            ctx.renderer.pushClip(Rect(textX, row.y, max(0.0, textRight - textX), row.h))
            if (hasName) {
                ctx.renderer.text(name, textX, row.y + 7.0, primary, pointSize: 12.0)
                ctx.renderer.text(server.baseUrl, textX, row.y + 25.0, secondary, pointSize: 10.0)
            } else {
                let th = ctx.renderer.textHeight(pointSize: 11.0)
                ctx.renderer.text(name, textX, row.centerY() - th / 2.0, primary, pointSize: 11.0)
            }
            ctx.renderer.popClip()
            if (current) {
                drawIcon(ctx.renderer, IconName.Check, Rect(row.right() - 20.0, row.centerY() - 6.0, 12.0, 12.0),
                    primary)
            }
        }
        ctx.renderer.popClip()
    }

    private func animatedServerPopupRect(parent: Rect, menu: Rect, progress: Float32): Rect {
        let scale = USER_MENU_ENTER_SCALE + (1.0 - USER_MENU_ENTER_SCALE) * progress
        let width = menu.w * scale
        let height = menu.h * scale
        if (menu.x < parent.x) {
            Rect(menu.right() - width + USER_MENU_ENTER_OFFSET_Y * (1.0 - progress), menu.y, width, height)
        } else {
            Rect(menu.x - USER_MENU_ENTER_OFFSET_Y * (1.0 - progress), menu.y, width, height)
        }
    }

    private func handlePopup(ctx: UiContext, event: UiEvent, menu: Rect): Bool {
        let servers = serverMenuRect(ctx, menu)
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if ((serverMenuOpen.value || serverMenuAnim.value > 0.0) && servers.contains(x, y)) {
                    // 关闭动画尚未结束时重新移入，直接从当前进度反向展开。
                    openServerMenu(ctx, false)
                    highlight.value = 2
                    let index = serverAt(servers, x, y)
                    if (index >= 0) {
                        serverHighlight.value = index
                    }
                    ctx.claimHover(USER_MENU_OWNER, CursorShape.Interactive)
                } else if (menu.contains(x, y)) {
                    let index = itemAt(menu, x, y)
                    if (index >= 0) {
                        highlight.value = index
                    }
                    if (index == 2) {
                        openServerMenu(ctx, false)
                    } else {
                        closeServerMenu(ctx)
                    }
                    ctx.claimHover(USER_MENU_OWNER, CursorShape.Interactive)
                } else {
                    closeServerMenu(ctx)
                }
                false
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (serverMenuOpen.value && servers.contains(x, y)) {
                    runServer(ctx, serverAt(servers, x, y))
                } else if (menu.contains(x, y)) {
                    let index = itemAt(menu, x, y)
                    if (index == 2) {
                        openServerMenu(ctx, true)
                    } else {
                        runItem(ctx, index)
                    }
                } else {
                    close(ctx)
                }
                true
            case UiEvent.MouseDown(_, _, _) =>
                close(ctx)
                true
            case UiEvent.KeyDown(Key.Escape, _) =>
                if (serverMenuOpen.value) {
                    closeServerMenu(ctx)
                } else {
                    close(ctx)
                }
                true
            case UiEvent.KeyDown(Key.Enter, _) =>
                if (serverMenuOpen.value) {
                    runServer(ctx, serverHighlight.value)
                } else if (highlight.value == 2) {
                    openServerMenu(ctx, true)
                } else {
                    runItem(ctx, highlight.value)
                }
                true
            case UiEvent.KeyDown(Key.Down, _) =>
                if (serverMenuOpen.value) {
                    moveServerHighlight(1)
                } else {
                    moveHighlight(1)
                }
                true
            case UiEvent.KeyDown(Key.Up, _) =>
                if (serverMenuOpen.value) {
                    moveServerHighlight(-1)
                } else {
                    moveHighlight(-1)
                }
                true
            case UiEvent.KeyDown(Key.Right, _) =>
                if (highlight.value == 2) {
                    openServerMenu(ctx, true)
                }
                true
            case UiEvent.KeyDown(Key.Left, _) =>
                closeServerMenu(ctx)
                true
            case _ => false
        }
    }

    private func handleClosingPopup(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    openPopup(ctx)
                }
                true
            case _ => true
        }
    }

    private func moveHighlight(delta: Int64): Unit {
        closeServerMenuWithoutFrame()
        if (highlight.value < 0) {
            highlight.value = if (delta > 0) {
                0
            } else {
                USER_MENU_ITEM_COUNT - 1
            }
        } else {
            highlight.value = (highlight.value + USER_MENU_ITEM_COUNT + delta) % USER_MENU_ITEM_COUNT
        }
    }

    private func openServerMenu(ctx: UiContext, selectFirst: Bool): Unit {
        if (!serverMenuOpen.value) {
            serverMenuOpen.value = true
            serverHighlight.value = if (selectFirst) {
                firstSwitchableServer()
            } else {
                -1
            }
            ctx.requestFrame()
        } else if (selectFirst && serverHighlight.value < 0) {
            serverHighlight.value = firstSwitchableServer()
        }
    }

    private func closeServerMenu(ctx: UiContext): Unit {
        closeServerMenuWithoutFrame()
        let _ = serverMenuAnim.animate(ctx, target: 0.0)
    }

    private func closeServerMenuWithoutFrame(): Unit {
        serverMenuOpen.value = false
        serverHighlight.value = -1
    }

    private func firstSwitchableServer(): Int64 {
        for (i in 0..model.settings.servers.size) {
            if (model.settings.servers[i].id != model.settings.activeServerId) {
                return i
            }
        }
        -1
    }

    private func moveServerHighlight(delta: Int64): Unit {
        let count = model.settings.servers.size
        if (count <= 1) {
            serverHighlight.value = firstSwitchableServer()
            return
        }
        var next = serverHighlight.value
        for (_ in 0..count) {
            next = if (next < 0) {
                if (delta > 0) {
                    0
                } else {
                    count - 1
                }
            } else {
                (next + count + delta) % count
            }
            if (model.settings.servers[next].id != model.settings.activeServerId) {
                serverHighlight.value = next
                return
            }
        }
    }

    private func runServer(ctx: UiContext, index: Int64): Unit {
        if (index < 0 || index >= model.settings.servers.size) {
            return
        }
        let server = model.settings.servers[index]
        if (server.id == model.settings.activeServerId) {
            return
        }
        close(ctx)
        // 没有已保存会话时停在目标服务器的登录表单；有会话则 selectServer 静默恢复。
        model.navigate(Page.Login)
        model.selectServer(server.id)
    }

    private func runItem(ctx: UiContext, index: Int64): Unit {
        if (index == 2) {
            openServerMenu(ctx, true)
            return
        }
        close(ctx)
        match (index) {
            case 0 => model.openUploadDrawer()
            case 1 => model.navigate(Page.Settings)
            case 2 => ()
            case 3 => logoutOpen.value = true
            case _ => ()
        }
    }

    private func close(ctx: UiContext): Unit {
        open.value = false
        closeServerMenu(ctx)
        // 从当前进度反向播放；不直接销毁动画状态。
        let _ = popupAnim.animate(ctx, target: 0.0)
        ctx.removeOverlay(USER_MENU_OWNER)
    }
}

private func userMenuAlpha(color: Color, progress: Float32): Color {
    color.withAlpha(Int64(Float32(Int64(color.a)) * max(0.0, min(1.0, progress))))
}

private func titleBarLogoutConfirmModal(model: AppModel, logoutOpen: State<Bool>): Unit {
    Modal(logoutOpen, body: {
        => VStack {
            Label(model.t("titlebar.logoutTitle")).fontSize(15.fp)
            Label(model.t("titlebar.logoutDescription")).fontSize(12.fp).muted()
            HStack {
                Spacer()
                Button(model.t("common.cancel"), {=> logoutOpen.value = false}).style(ghostStyleOf(model))
                Button(
                    model.t("overview.logout"),
                    {
                        =>
                            logoutOpen.value = false
                            model.logout()
                    }
                ).role(ButtonRole.Danger)
            }.spacing(8.vp)
        }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Start).width(340.vp)
    })
}

// 自定义标题栏：品牌 + 全局搜索 + 导航胶囊 + 设置/主题 + 用户芯片 + 分隔线 +
// 最小化/最大化/关闭。登录页只保留品牌与右侧主题/窗口控制（无可搜内容、无会话用户）。
// 最小化/最大化经 SdlWindow 扩展直达，关闭走 ctx.requestClose()。
public func titleBar(window: SdlWindow, model: AppModel): Unit {
    let logoutOpen = rememberState<Bool>("titlebar:logout-open", {=> false})
    let onLogin = match (model.page.value) {
        case Page.Login => true
        case _ => false
    }
    // 返回钮（原型 #btn-back）：详情/合集/设置视图显示，顶栏最左、品牌区之前。
    let showBack = match (model.page.value) {
        case Page.Detail(_) | Page.Tank(_) | Page.Settings => true
        case _ => false
    }
    let onShelf = match (model.page.value) {
        case Page.Shelf => true
        case _ => false
    }
    let onLibrary = match (model.page.value) {
        case Page.Library => true
        case _ => false
    }
    let searchTween = rememberState<Tween>("titlebar:search-expand", {
        => Tween(SEARCH_EXPAND_MS, Easing.easeOutCubic)
    }).value
    let searchProgress = searchTween.value
    ZStack {
        TitleBarBackground()
        HStack {
            if (showBack) {
                GhostIconButton(GhostGlyph.Back, "titlebar:back") {
                    => model.leaveDetailOrSettings()
                }
            }
            HStack {
                brandLogo(28.vp)
                Label("Lanlu").fontSize(15.fp)
            }.spacing(9.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
            if (!onLogin) {
                // 搜索框在品牌与右侧固定带之间水平居中（前后各一个弹性 Spacer）。
                Spacer()
                ZStack {
                    SearchChrome(model)
                    // chrome 关闭：外壳由 SearchChrome 自绘，避免 TextField 默认底/边再套一层。
                    TextField(if (onShelf) {
                        model.shelfSearchText
                    } else {
                        model.searchText
                    }, key: SEARCH_FIELD_ID, chrome: false).padding(SEARCH_ICON_INSET + 4.0, 0.0, SEARCH_KBD_INSET + 4.0,
                        0.0)
                    SearchPlaceholder(model, onShelf)
                    if (!onShelf) {
                        SearchAutocomplete(model, SEARCH_FIELD_ID)
                    }
                    SearchExpandTicker(searchTween, searchProgress)
                }
                    .alignment(Alignment.TopLeading)
                    .width(searchLayoutWidth(window.width, showBack, onLibrary, searchProgress))
                if (onLibrary) {
                    GhostIconButton(GhostGlyph.Filter, "titlebar:filter") {=> model.openAdvancedFilter()}
                }
                Spacer()
                NavPill(model)
            } else {
                Spacer()
            }
            ThemeToggleButton(model, "titlebar:theme")
            if (!onLogin && model.settings.username.size > 0) {
                UserMenuChip(model, logoutOpen)
            }
            WinSep()
            WinControlButton(WinGlyph.Min, "titlebar:min") {_ => window.minimize()}
            WinControlButton(WinGlyph.Max, "titlebar:max") {_ => window.maximize()}
            WinControlButton(WinGlyph.Close, "titlebar:close") {ctx => ctx.requestClose()}
        }.spacing(10.0).crossAxisAlignment(CrossAxisAlignment.Center).padding(16.0, 0.0, 16.0, 0.0)
        // 顶层键盘接线件：最后声明 = 事件分发最优先（只吃不相关鼠标事件之外的键）。
        SearchKeys(model)
    // alignment 是 ZStack 专有链式，须排在返回 Widget 的通用修饰器 height 之前。
    }.alignment(Alignment.TopLeading).height(Float32(TITLEBAR_HEIGHT))
    titleBarLogoutConfirmModal(model, logoutOpen)
}
