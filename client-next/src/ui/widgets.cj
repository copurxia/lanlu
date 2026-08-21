package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.{ArchivePageView, SearchItem, SearchItemProjectionView, SearchItemView, TankoubonInfo,
    TankoubonView, PageInfo, percentEncode}
import std.collection.{ArrayList, HashMap, HashSet}
import std.math.{cos, sin}

// 品牌 logo（顶栏 28vp / 登录卡 44vp 共用）：金色镂空书架方块。
// PNG 字节由 build.cj 内嵌进二进制（embedded_logo.cj），发布产物不再附带图片文件；
// 首次使用时注册进纹理缓存的内存注册表，之后与普通图片同一路径解码渲染。
private let LOGO_TEXTURE_KEY = "embedded:lanlu_logo_gold"
private var logoBytesRegistered = false

func brandLogo(size: Length): Unit {
    if (!logoBytesRegistered) {
        registerImageBytes(LOGO_TEXTURE_KEY, EMBEDDED_LOGO_PNG)
        logoBytesRegistered = true
    }
    ImageView(LOGO_TEXTURE_KEY, preferredWidth: Some(size), preferredHeight: size)
}

// 旋转加载圈（indeterminate spinner）：270° 弧的起点随帧钟旋转，绘制时 requestFrame
// 保持帧流动（同 TextField 光标闪烁的做法）。用于登录「正在连接…」按钮态。
class Spinner <: Widget {
    private let diameter: Float32
    private let color: Color
    private var frame = Rect.zero()

    public init(diameter: Float32, color: Color) {
        this.diameter = diameter
        this.color = color
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(diameter, diameter)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        ctx.requestFrame()
        let tau = 6.283185307179586
        let start = Float64(ctx.frame.elapsedMs % 900) / 900.0 * tau
        let cx = frame.centerX()
        let cy = frame.centerY()
        let radius = (min(frame.w, frame.h) - 2.0) / 2.0
        let pen = Pen(width: 2.0, color: color)
        let segs = 20
        for (i in 0..segs) {
            let a0 = start + tau * 0.75 * Float64(i) / Float64(segs)
            let a1 = start + tau * 0.75 * Float64(i + 1) / Float64(segs)
            ctx
                .renderer
                .strokeLine(cx + radius * Float32(cos(a0)), cy + radius * Float32(sin(a0)), cx + radius * Float32(cos(
                    a1)), cy + radius * Float32(sin(a1)), pen)
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 阴影卡片铺底层：cui 的 .background 修饰符只有填充没有阴影/描边，drawSurface 是
// cui.core 内部件（protected，应用层不可见），这里用 renderer 原语自绘：
// 两层 feather 圆角矩形叠出软阴影（对齐 cui.core surface_draw.cj 的 drawSoftShadow），
// 再画圆角填充与 1px 描边。自身不托管子树（buildChild 未导出），用法同 ClickArea：
// ZStack 底层放 SurfaceCard，上层放内容。
class SurfaceCard <: Widget {
    private let fill: Color
    private let border: Color
    private let radius: Float32
    private let shadowColor: Color
    private let spreadOverride: Float32
    private let shadowOffsetY: Float32
    private var frame = Rect.zero()

    public init(fill: Color, border: Color, radius!: Float32 = 14.0, shadow!: Color = Color.rgba(0, 0, 0, 110),
        spread!: Float32 = 0.0, offsetY!: Float32 = 8.0) {
        this.fill = fill
        this.border = border
        this.radius = radius
        this.shadowColor = shadow
        this.spreadOverride = spread
        this.shadowOffsetY = offsetY
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        // spread 默认沿用框架经验式（4+r/2 钳制 5..13），登录卡等大面需要更扩展的光晕时显式传入。
        let spread = if (spreadOverride > 0.0) {
            spreadOverride
        } else {
            clampF32(4.0 + radius * 0.5, 5.0, 13.0)
        }
        let base = frame.shift(0.0, shadowOffsetY)
        let a = Int64(shadowColor.a)
        ctx
            .renderer
            .fillRoundedRectSoft(base.inset(-spread * 0.3), radius + spread * 0.3, shadowColor.withAlpha(a * 3 / 5),
                feather: spread)
        ctx.renderer.fillRoundedRectSoft(base, radius, shadowColor.withAlpha(a / 2), feather: spread * 0.5)
        ctx.renderer.fillRoundedRect(frame, radius, fill)
        if (Int64(border.a) > 0) {
            ctx.renderer.strokeRoundedRect(frame.inset(0.5), max(0.0, radius - 0.5), Pen(width: 1.0, color: border))
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 点击传感器：透明、自身不占尺寸，layout 时记录父容器（ZStack）下发的整个矩形，
// 左键 MouseUp 命中该矩形时触发 onClick 并消费事件。
// 应用层自定义 Widget：实现 measure/layout/draw/handle 并在构造时 emit(this)
// （协议见 api-reference §2，写法参照 examples/explorer 的 EntryRow）。
class ClickSensor <: Widget {
    private let onClick: () -> Unit
    private var bounds = Rect.zero()

    public init(onClick: () -> Unit) {
        this.onClick = onClick
        emit(this)
    }

    // 不参与内容测量：传感器不撑大布局，区域大小完全由叠在上层的内容决定。
    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        bounds = rect
    }

    public func draw(_: UiContext): Unit {} // 全透明，只负责事件

    public func handle(_: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (bounds.contains(x, y)) {
                    onClick()
                    return true
                }
            case _ => ()
        }
        false
    }
}

// 可点击区域：框架没有通用 onClick 修饰器；cui.core 的 buildChild 是模块内部助手
// （未对应用导出，cui 伞包只重导出 emit），应用层自定义 Widget 无法包裹 builder 子树，
// 因此以 ZStack 叠层代替包裹——底层传感器随 ZStack 拉伸充满整个区域，内容绘制在上层；
// 事件自顶向下分发，内容未消费的左键抬起最终落到传感器触发 onClick。
public class ClickArea {
    public init(onClick!: () -> Unit, body!: () -> Unit) {
        ZStack {
            ClickSensor(onClick)
            body()
        }.alignment(Alignment.TopLeading)
    }
}

// 悬停传感器：透明充满父容器（ZStack 底层），MouseMove 命中时经 ctx.claimHover 认领
// hoverId（指针移出后无人认领，isHovered 自动回落）；不消费任何事件，点击穿透给下层。
// 配对用法：绘制层（如 CoverBorder）以同一 hoverId 调 ctx.isHovered 取态。
class HoverSensor <: Widget {
    private let hoverId: String
    private var frame = Rect.zero()

    public init(hoverId: String) {
        this.hoverId = hoverId
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(_: UiContext): Unit {}

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    ctx.claimHover(hoverId, CursorShape.Interactive)
                }
            case _ => ()
        }
        false
    }
}

// ── 无边框图标钮（原型 .icon-btn：34×34、圆角 9、muted 图标、hover 铺 overlayHover 底）──

// 图标钮图形种类：Named 走 sdl 矢量图标库（drawIcon），其余为本文件手绘矢量/文本字形
// （IconName 枚举无对应项；原型符号 ⚙/◐/⌕/⇄ 在 NotoSansCJK/msyh 无字形，不依赖字体符号）。
// Back/Menu/Swap/Heart 为阅读器顶栏（reader-redesign #topbar）增补；
// Download/AddTank/Ellipsis 为详情操作卡增补（替代 ⬇/⊕/⋯ 文本兜底）。
// Book/Pages/Disk/Box 为设置页统计卡增补（替代 ♥/▤/▣/● 文本符号，原型 .stat-card 图标）；
// Tag/Globe/Sparkle/Monitor/Chart/Info 为设置导航图标增补（原型 #set-nav .side-item .ico）。
public enum GhostGlyph {
    | Named(IconName)
    | Gear
    | Theme
    | Search
    | Filter
    | Back
    | Menu
    | Swap
    | Heart
    | Download
    | AddTank
    | Ellipsis
    | Book
    | Pages
    | Disk
    | Box
    | Tag
    | Globe
    | Sparkle
    | Monitor
    | Chart
    | Info
    | Home
    | LogOut
}

// 绘制 GhostGlyph 图形（16×16 视觉格，中心 cx/cy）：GhostIconButton 与阅读器模式钮共用。
public func drawGhostGlyph(renderer: Renderer, glyph: GhostGlyph, cx: Float32, cy: Float32, color: Color): Unit {
    match (glyph) {
        case GhostGlyph.Named(icon) => drawIcon(renderer, icon, Rect(cx - 8.0, cy - 8.0, 16.0, 16.0), color)
        case GhostGlyph.Gear =>
            // 齿轮：紧凑的环形轮廓 + 8 个切向圆角齿块 + 中心孔。
            // 齿块沿圆周展开，不再用放射长线；16px 下更像齿轮而不是太阳。
            let toothPen = Pen(width: 2.0, color: color)
            for (i in 0..8) {
                let a = Float64(i) * 0.7853982 // π/4
                let radialX = Float32(cos(a))
                let radialY = Float32(sin(a))
                let toothX = cx + radialX * 6.55
                let toothY = cy + radialY * 6.55
                let tangentX = -radialY * 0.9
                let tangentY = radialX * 0.9
                renderer.strokeLine(toothX - tangentX, toothY - tangentY, toothX + tangentX, toothY + tangentY, toothPen)
            }
            renderer.strokeCircle(cx, cy, 5.35, Pen(width: 1.55, color: color))
            renderer.strokeCircle(cx, cy, 2.0, Pen(width: 1.45, color: color))
        case GhostGlyph.Theme =>
            // ◐ 的矢量等价：外圈描边 + 左半填充（clip 裁掉右半）。
            renderer.strokeCircle(cx, cy, 6.5, Pen(width: 1.2, color: color))
            renderer.pushClip(Rect(cx - 6.5, cy - 6.5, 6.5, 13.0))
            renderer.fillCircle(cx, cy, 5.2, color)
            renderer.popClip()
        case GhostGlyph.Search =>
            // 放大镜：圆 + 右下手柄。
            let pen = Pen(width: 1.4, color: color)
            renderer.strokeCircle(cx - 1.0, cy - 1.0, 5.2, pen)
            renderer.strokeLine(cx + 3.0, cy + 3.0, cx + 6.8, cy + 6.8, pen)
        case GhostGlyph.Filter =>
            // 漏斗：对齐 frontend 的 lucide Filter，宽口收束为短竖柄。
            let pen = Pen(width: 1.5, color: color)
            renderer.strokeLine(cx - 7.0, cy - 6.0, cx + 7.0, cy - 6.0, pen)
            renderer.strokeLine(cx - 7.0, cy - 6.0, cx - 1.8, cy, pen)
            renderer.strokeLine(cx + 7.0, cy - 6.0, cx + 1.8, cy, pen)
            renderer.strokeLine(cx - 1.8, cy, cx - 1.8, cy + 6.5, pen)
            renderer.strokeLine(cx - 1.8, cy + 6.5, cx + 1.8, cy + 4.5, pen)
            renderer.strokeLine(cx + 1.8, cy + 4.5, cx + 1.8, cy, pen)
        case GhostGlyph.Back =>
            // ←：水平干线 + 左向箭头头。
            let pen = Pen(width: 1.6, color: color)
            renderer.strokeLine(cx - 6.5, cy, cx + 6.5, cy, pen)
            renderer.strokeLine(cx - 6.5, cy, cx - 1.5, cy - 5.0, pen)
            renderer.strokeLine(cx - 6.5, cy, cx - 1.5, cy + 5.0, pen)
        case GhostGlyph.Menu =>
            // ☰：三根等距横线。
            let pen = Pen(width: 1.6, color: color)
            renderer.strokeLine(cx - 6.5, cy - 5.0, cx + 6.5, cy - 5.0, pen)
            renderer.strokeLine(cx - 6.5, cy, cx + 6.5, cy, pen)
            renderer.strokeLine(cx - 6.5, cy + 5.0, cx + 6.5, cy + 5.0, pen)
        case GhostGlyph.Swap =>
            // ⇄：上箭头向右、下箭头向左。
            let pen = Pen(width: 1.5, color: color)
            renderer.strokeLine(cx - 6.5, cy - 3.5, cx + 6.5, cy - 3.5, pen)
            renderer.strokeLine(cx + 6.5, cy - 3.5, cx + 3.0, cy - 6.5, pen)
            renderer.strokeLine(cx + 6.5, cy - 3.5, cx + 3.0, cy - 0.5, pen)
            renderer.strokeLine(cx - 6.5, cy + 3.5, cx + 6.5, cy + 3.5, pen)
            renderer.strokeLine(cx - 6.5, cy + 3.5, cx - 3.0, cy + 0.5, pen)
            renderer.strokeLine(cx - 6.5, cy + 3.5, cx - 3.0, cy + 6.5, pen)
        case GhostGlyph.LogOut =>
            // lucide log-out：右侧开口的门框 + 穿门而出的箭头。
            let pen = Pen(width: 1.5, color: color)
            renderer.strokeLine(cx - 0.5, cy - 6.5, cx - 6.5, cy - 6.5, pen)
            renderer.strokeLine(cx - 6.5, cy - 6.5, cx - 6.5, cy + 6.5, pen)
            renderer.strokeLine(cx - 6.5, cy + 6.5, cx - 0.5, cy + 6.5, pen)
            renderer.strokeLine(cx - 2.0, cy, cx + 6.5, cy, pen)
            renderer.strokeLine(cx + 3.5, cy - 3.0, cx + 6.5, cy, pen)
            renderer.strokeLine(cx + 6.5, cy, cx + 3.5, cy + 3.0, pen)
        case GhostGlyph.Heart =>
            // 心形使用矢量折线近似 lucide heart，避免 Linux 字体缺少 ♥ 时只剩按钮底板。
            let pen = Pen(width: 1.7, color: color)
            let points: Array<(Float32, Float32)> = [
                (-6.5, -2.7),
                (-6.0, -4.5),
                (-4.6, -5.7),
                (-2.8, -6.0),
                (-1.2, -5.3),
                (0.0, -3.9),
                (1.2, -5.3),
                (2.8, -6.0),
                (4.6, -5.7),
                (6.0, -4.5),
                (6.5, -2.7),
                (6.1, -0.5),
                (4.6, 1.8),
                (0.0, 6.4),
                (-4.6, 1.8),
                (-6.1, -0.5),
                (-6.5, -2.7)
            ]
            for (i in 0..points.size - 1) {
                renderer.strokeLine(cx + points[i][0], cy + points[i][1], cx + points[i + 1][0], cy + points[i + 1][1],
                    pen)
            }
        case GhostGlyph.Download =>
            // ⤓：下箭头入盘（干线 + 箭头头 + 三边底盘，原型 .action-icons 下载钮）。
            let pen = Pen(width: 1.6, color: color)
            renderer.strokeLine(cx, cy - 7.0, cx, cy + 1.5, pen)
            renderer.strokeLine(cx - 4.5, cy - 2.5, cx, cy + 2.0, pen)
            renderer.strokeLine(cx + 4.5, cy - 2.5, cx, cy + 2.0, pen)
            renderer.strokeLine(cx - 7.0, cy + 2.0, cx - 7.0, cy + 6.5, pen)
            renderer.strokeLine(cx - 7.0, cy + 6.5, cx + 7.0, cy + 6.5, pen)
            renderer.strokeLine(cx + 7.0, cy + 6.5, cx + 7.0, cy + 2.0, pen)
        case GhostGlyph.AddTank =>
            // ⧉：双层错位圆角方块（原型 .action-icons 加入合集钮）。
            let pen = Pen(width: 1.4, color: color)
            renderer.strokeRoundedRect(Rect(cx - 2.5, cy - 7.5, 9.5, 9.5), 2.5, pen)
            renderer.strokeRoundedRect(Rect(cx - 7.0, cy - 2.0, 9.5, 9.5), 2.5, pen)
        case GhostGlyph.Ellipsis =>
            // ⋯：三点（原型 .action-icons 更多钮）。
            renderer.fillCircle(cx - 5.5, cy, 1.3, color)
            renderer.fillCircle(cx, cy, 1.3, color)
            renderer.fillCircle(cx + 5.5, cy, 1.3, color)
        case GhostGlyph.Book =>
            // 📖：摊开的书——中缝 + 左右两页外框（统计卡「已读档案」）。
            let pen = Pen(width: 1.5, color: color)
            renderer.strokeLine(cx, cy - 6.0, cx, cy + 6.0, pen)
            renderer.strokeLine(cx, cy - 6.0, cx - 6.5, cy - 4.5, pen)
            renderer.strokeLine(cx - 6.5, cy - 4.5, cx - 6.5, cy + 4.5, pen)
            renderer.strokeLine(cx - 6.5, cy + 4.5, cx, cy + 6.0, pen)
            renderer.strokeLine(cx, cy - 6.0, cx + 6.5, cy - 4.5, pen)
            renderer.strokeLine(cx + 6.5, cy - 4.5, cx + 6.5, cy + 4.5, pen)
            renderer.strokeLine(cx + 6.5, cy + 4.5, cx, cy + 6.0, pen)
        case GhostGlyph.Pages =>
            // ▤→页堆：后页上缘露边 + 前页框内两条横线（统计卡「总阅读页数」）。
            let pen = Pen(width: 1.4, color: color)
            renderer.strokeLine(cx - 4.5, cy - 7.0, cx + 6.5, cy - 7.0, pen)
            renderer.strokeLine(cx + 6.5, cy - 7.0, cx + 6.5, cy - 4.5, pen)
            renderer.strokeRoundedRect(Rect(cx - 6.5, cy - 4.5, 11.0, 12.0), 1.5, pen)
            renderer.strokeLine(cx - 3.5, cy - 0.5, cx + 1.5, cy - 0.5, pen)
            renderer.strokeLine(cx - 3.5, cy + 2.5, cx + 1.5, cy + 2.5, pen)
        case GhostGlyph.Disk =>
            // 🗄：三层数据库盘（设置导航「缓存」/统计卡「档案总数」语义存储）。
            let pen = Pen(width: 1.4, color: color)
            renderer.strokeRoundedRect(Rect(cx - 6.5, cy - 7.0, 13.0, 4.6), 2.3, pen)
            renderer.strokeRoundedRect(Rect(cx - 6.5, cy - 2.3, 13.0, 4.6), 2.3, pen)
            renderer.strokeRoundedRect(Rect(cx - 6.5, cy + 2.4, 13.0, 4.6), 2.3, pen)
        case GhostGlyph.Box =>
            // 📦：箱体 + 顶盖中线（设置导航「插件管理」）。
            let pen = Pen(width: 1.4, color: color)
            renderer.strokeRoundedRect(Rect(cx - 6.5, cy - 4.5, 13.0, 11.0), 1.5, pen)
            renderer.strokeLine(cx - 6.5, cy - 1.5, cx + 6.5, cy - 1.5, pen)
            renderer.strokeLine(cx, cy - 4.5, cx, cy - 1.5, pen)
        case GhostGlyph.Tag =>
            // 🏷：标签牌——尖角五边形 + 穿绳孔（设置导航「标签管理」）。
            let pen = Pen(width: 1.4, color: color)
            renderer.strokeLine(cx - 6.5, cy - 6.5, cx + 1.5, cy - 6.5, pen)
            renderer.strokeLine(cx + 1.5, cy - 6.5, cx + 6.5, cy - 1.5, pen)
            renderer.strokeLine(cx + 6.5, cy - 1.5, cx - 1.5, cy + 6.5, pen)
            renderer.strokeLine(cx - 1.5, cy + 6.5, cx - 6.5, cy - 1.5, pen)
            renderer.strokeLine(cx - 6.5, cy - 1.5, cx - 6.5, cy - 6.5, pen)
            renderer.fillCircle(cx - 2.5, cy - 2.5, 1.3, color)
        case GhostGlyph.Globe =>
            // 🌐：外圈 + 赤道线 + 两条纵经线弧（设置导航「语言」）。
            let pen = Pen(width: 1.3, color: color)
            renderer.strokeCircle(cx, cy, 7.0, pen)
            renderer.strokeLine(cx - 7.0, cy, cx + 7.0, cy, pen)
            // 纵经线用密集小线段逼近椭圆弧。
            for (off in [-3.2, 3.2]) {
                var px = cx + Float32(off)
                var py = cy - 6.0
                for (i in 1..13) {
                    let t = -1.0 + 2.0 * Float64(i) / 12.0
                    let ny = cy + Float32(t * 6.0)
                    let nx = cx + Float32(off * (1.0 - t * t))
                    renderer.strokeLine(px, py, nx, ny, pen)
                    px = nx
                    py = ny
                }
            }
        case GhostGlyph.Sparkle =>
            // ✦：四角星——中心向四正点细线 + 四斜点短线（设置导航「智能分类」）。
            let pen = Pen(width: 1.5, color: color)
            renderer.strokeLine(cx, cy - 7.0, cx, cy + 7.0, pen)
            renderer.strokeLine(cx - 7.0, cy, cx + 7.0, cy, pen)
            let pen2 = Pen(width: 1.2, color: color)
            renderer.strokeLine(cx - 3.4, cy - 3.4, cx + 3.4, cy + 3.4, pen2)
            renderer.strokeLine(cx + 3.4, cy - 3.4, cx - 3.4, cy + 3.4, pen2)
        case GhostGlyph.Monitor =>
            // 🖥：屏框 + 底座（设置导航「系统设置」）。
            let pen = Pen(width: 1.4, color: color)
            renderer.strokeRoundedRect(Rect(cx - 7.0, cy - 6.0, 14.0, 10.0), 1.5, pen)
            renderer.strokeLine(cx, cy + 4.0, cx, cy + 6.5, pen)
            renderer.strokeLine(cx - 4.0, cy + 6.5, cx + 4.0, cy + 6.5, pen)
        case GhostGlyph.Chart =>
            // 📊：三根递增柱 + 底线（设置导航「统计信息」）。
            let pen = Pen(width: 1.6, color: color)
            renderer.strokeLine(cx - 7.0, cy + 6.5, cx + 7.0, cy + 6.5, pen)
            renderer.strokeLine(cx - 4.5, cy + 1.5, cx - 4.5, cy + 5.0, Pen(width: 2.6, color: color))
            renderer.strokeLine(cx, cy - 2.5, cx, cy + 5.0, Pen(width: 2.6, color: color))
            renderer.strokeLine(cx + 4.5, cy - 6.5, cx + 4.5, cy + 5.0, Pen(width: 2.6, color: color))
        case GhostGlyph.Info =>
            // ℹ：外圈 + i 点与竖（设置导航「关于」）。
            let pen = Pen(width: 1.4, color: color)
            renderer.strokeCircle(cx, cy, 7.0, pen)
            renderer.fillCircle(cx, cy - 3.4, 1.2, color)
            renderer.strokeLine(cx, cy - 0.5, cx, cy + 4.0, Pen(width: 1.8, color: color))
        case GhostGlyph.Home =>
            // ⌂：屋顶 + 屋身（关于页「项目主页」，原型 ⌂）。
            let pen = Pen(width: 1.4, color: color)
            renderer.strokeLine(cx - 7.0, cy - 0.5, cx, cy - 6.5, pen)
            renderer.strokeLine(cx, cy - 6.5, cx + 7.0, cy - 0.5, pen)
            renderer.strokeLine(cx - 5.0, cy - 1.5, cx - 5.0, cy + 6.0, pen)
            renderer.strokeLine(cx + 5.0, cy - 1.5, cx + 5.0, cy + 6.0, pen)
            renderer.strokeLine(cx - 5.0, cy + 6.0, cx + 5.0, cy + 6.0, pen)
    }
}

// 非按钮图形图标：在 measure 尺寸内居中绘制 GhostGlyph（统计卡/设置行/导航前置图标用，
// GhostIconButton 是整块热区，这里只要纯展示）。
public class GlyphIcon <: Widget {
    private let glyph: GhostGlyph
    private let extent: Float32
    private let color: ?Color
    private var frame = Rect.zero()

    public init(glyph: GhostGlyph, size!: Float32 = 16.0, color!: ?Color = None) {
        this.glyph = glyph
        this.extent = size
        this.color = color
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(extent, extent)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let c = match (color) {
            case Some(v) => v
            case None => ctx.theme.text
        }
        drawGhostGlyph(ctx.renderer, glyph, frame.centerX(), frame.centerY(), c)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 无边框图标钮：34×34 透明底，hover 铺圆角 overlayHover 底、图标转主文字色；
// active 时常驻 accentSoft 底 + accent 图标（原型 .icon-btn.active，阅读器收藏态用）。
// 左键抬起命中触发 onClick 并消费事件。工具条刷新钮与顶栏设置/主题钮共用。
public class GhostIconButton <: Widget {
    private let glyph: GhostGlyph
    private let hoverId: String
    private let onClick: () -> Unit
    private let active: Bool
    private let size: Float32
    // 固定图标色（如退出登录用 danger 红，对齐 client LogOut 图标）；None 走默认态色。
    private let tint: ?Color
    private var frame = Rect.zero()

    // size：默认 34（顶栏/阅读器）；详情操作卡用 28（原型 .action-icons .icon-btn 32px 的紧凑近似）。
    public init(glyph: GhostGlyph, hoverId: String, size!: Float32 = 34.0, active!: Bool = false, color!: ?Color = None,
        onClick!: () -> Unit) {
        this.glyph = glyph
        this.hoverId = hoverId
        this.onClick = onClick
        this.active = active
        this.size = size
        this.tint = color
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(size, size)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let hovered = ctx.isHovered(hoverId)
        let radius: Float32 = if (size >= 34.0) {
            9.0
        } else {
            8.0
        }
        if (active) {
            ctx.renderer.fillRoundedRect(frame, radius, ctx.theme.accentSoft)
        } else if (hovered) {
            ctx.renderer.fillRoundedRect(frame, radius, ctx.theme.overlayHover)
        }
        let color = match (tint) {
            case Some(c) => c
            case None =>
                if (active) {
                    ctx.theme.accent
                } else if (hovered) {
                    ctx.theme.text
                } else {
                    ctx.theme.mutedText
                }
        }
        drawGhostGlyph(ctx.renderer, glyph, frame.centerX(), frame.centerY(), color)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    ctx.claimHover(hoverId, CursorShape.Interactive)
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    onClick()
                    return true
                }
            case _ => ()
        }
        false
    }
}

// 明暗切换专用按钮：根据当前主题绘制太阳/月亮，并把点击坐标交给涟漪层。
// 其余尺寸、hover 与 GhostIconButton 保持一致。
public class ThemeToggleButton <: Widget {
    private let model: AppModel
    private let hoverId: String
    private var frame = Rect.zero()

    public init(model: AppModel, hoverId: String) {
        this.model = model
        this.hoverId = hoverId
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(34.0, 34.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let hovered = ctx.isHovered(hoverId)
        if (hovered) {
            ctx.renderer.fillRoundedRect(frame, 9.0, ctx.theme.overlayHover)
        }
        let color = if (hovered) {
            ctx.theme.text
        } else {
            ctx.theme.mutedText
        }
        let cx = frame.centerX()
        let cy = frame.centerY()
        if (model.isLight()) {
            ctx.renderer.fillCircle(cx, cy, 3.8, color)
            let pen = Pen(width: 1.4, color: color)
            for (i in 0..8) {
                let a = Float64(i) * 0.7853982
                ctx
                    .renderer
                    .strokeLine(cx + Float32(cos(a)) * 6.0, cy + Float32(sin(a)) * 6.0, cx + Float32(cos(a)) * 8.0,
                        cy + Float32(sin(a)) * 8.0, pen)
            }
        } else {
            // 月牙：主色圆上用当前面板色挖去右上区域。
            ctx.renderer.fillCircle(cx, cy, 6.5, color)
            ctx.renderer.fillCircle(cx + 3.2, cy - 2.8, 6.0, if (hovered) {
                ctx.theme.overlayHover
            } else {
                ctx.theme.panel
            })
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    ctx.claimHover(hoverId, CursorShape.Interactive)
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    model.setThemeFromToggle(if (model.settings.theme == "dark") {
                        "light"
                    } else {
                        "dark"
                    }, x, y, frame.centerX(), frame.centerY())
                    return true
                }
            case _ => ()
        }
        false
    }
}

// 迷你分段（原型 .mini-seg）：elev 底 + 1px 描边 + 圆角 8 容器（内边距 2、间距 2）；
// 项 11fp、padding 4×9、圆角 6；选中 accentSoft 浅金底 + accent 字（设计稿为浅金，
// 框架 SegmentedControl 实金底过重，故详情页专用此件）；hover 未选项转主文字色。
public class MiniSeg <: Widget {
    private let items: Array<String>
    private let selected: State<Int64>
    private let segId: String
    private var frame = Rect.zero()

    public init(items: Array<String>, selected: State<Int64>, key!: String) {
        this.items = items
        this.selected = selected
        this.segId = key
        emit(this)
    }

    private func itemWidth(ctx: UiContext, label: String): Float32 {
        ctx.renderer.textWidth(label, pointSize: 11.0) + 18.0 // 原型 padding:4px 9px
    }

    public func measure(ctx: UiContext, _: Size): Size {
        var w = 4.0 + 2.0 * Float32(items.size - 1) // 容器 padding 2×2 + 项间距 2
        for (l in items) {
            w += itemWidth(ctx, l)
        }
        Size(w, 26.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    private func itemRect(ctx: UiContext, i: Int64): Rect {
        var x = frame.x + 2.0
        for (j in 0..i) {
            x += itemWidth(ctx, items[j]) + 2.0
        }
        Rect(x, frame.y + 2.0, itemWidth(ctx, items[i]), frame.h - 4.0)
    }

    public func draw(ctx: UiContext): Unit {
        ctx.renderer.fillRoundedRect(frame, 8.0, ctx.theme.panel)
        ctx.renderer.strokeRoundedRect(frame.inset(0.5), 7.5, Pen(width: 1.0, color: ctx.theme.panelEdge))
        for (i in 0..items.size) {
            let item = itemRect(ctx, i)
            let th = ctx.renderer.textHeight(pointSize: 11.0)
            let tw = ctx.renderer.textWidth(items[i], pointSize: 11.0)
            if (Int64(i) == selected.value) {
                ctx.renderer.fillRoundedRect(item, 6.0, ctx.theme.accentSoft)
                ctx
                    .renderer
                    .text(items[i], item.centerX() - tw / 2.0, item.centerY() - th / 2.0, ctx.theme.accent,
                        pointSize: 11.0)
            } else {
                let fg = if (ctx.isHovered("${segId}:${i}")) {
                    ctx.theme.text
                } else {
                    ctx.theme.mutedText
                }
                ctx.renderer.text(items[i], item.centerX() - tw / 2.0, item.centerY() - th / 2.0, fg, pointSize: 11.0)
            }
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) => for (i in 0..items.size) {
                if (itemRect(ctx, i).contains(x, y)) {
                    ctx.claimHover("${segId}:${i}", CursorShape.Interactive)
                }
            }
            case UiEvent.MouseUp(MouseButton.Left, x, y) => for (i in 0..items.size) {
                if (itemRect(ctx, i).contains(x, y)) {
                    selected.value = Int64(i)
                    return true
                }
            }
            case _ => ()
        }
        false
    }
}

// 封面描边层：叠在封面（remoteImage 或圆角占位色块）顶层的透明绘制件。
// 成品封面的圆角由像素 alpha 烘焙（model.roundCoverCorners），占位色块用
// .background(color, 8.vp) 圆角填充；这里只画 1px 圆角描边：常态 panelEdge，
// hover 时 accent（母计划 §2 的描边级反馈，hoverId 由底层 HoverSensor 认领）。
class CoverBorder <: Widget {
    private let hoverId: String
    private var frame = Rect.zero()

    public init(hoverId: String) {
        this.hoverId = hoverId
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let edge = if (ctx.isHovered(hoverId)) {
            ctx.theme.accent
        } else {
            ctx.theme.panelEdge
        }
        // 圆角半径与 model.roundCoverCorners 的烘焙比例（短边 7.2%）保持一致：
        // 首页 168vp 封面 ≈ 12（原型 .card .cover border-radius:12px）。
        let radius = min(frame.w, frame.h) * 0.072 - 0.5
        ctx.renderer.strokeRoundedRect(frame.inset(0.5), radius, Pen(width: 1.0, color: edge))
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 多选选中描边（第二波）：叠在封面顶层的 2px accent 圆角描边，仅选中态挂载，
// 圆角与 CoverBorder 同源（短边 7.2%），线宽内收 1px 避免盖出封面弧外。
class SelectionRing <: Widget {
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
        let radius = min(frame.w, frame.h) * 0.072 - 0.5
        ctx.renderer.strokeRoundedRect(frame.inset(1.0), radius, Pen(width: 2.0, color: ctx.theme.accent))
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 多选勾选圆点（第二波，对齐 frontend 卡片 check 角标）：封面右上 20vp 圆，
// 选中=accent 实底白勾；未选=半透黑底白描边（叠在封面上不随主题翻转，取舍同 tankBadge）。
class SelectionDot <: Widget {
    private let selected: Bool
    private var frame = Rect.zero()

    public init(selected: Bool) {
        this.selected = selected
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(20.0, 20.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let cx = frame.centerX()
        let cy = frame.centerY()
        if (selected) {
            ctx.renderer.fillCircle(cx, cy, 9.0, ctx.theme.accent)
            drawIcon(ctx.renderer, IconName.Check, Rect(cx - 6.0, cy - 6.0, 12.0, 12.0), Color.rgb(255, 255, 255))
        } else {
            ctx.renderer.fillCircle(cx, cy, 9.0, Color.rgba(0, 0, 0, 110))
            ctx.renderer.strokeCircle(cx, cy, 9.0, Pen(width: 1.4, color: Color.rgba(255, 255, 255, 170)))
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 侧栏导航项（原型 .side-item）：全宽行（高 34），圆角 9；激活铺 accentSoft 圆角底 +
// accent 文字（.side-item.on），hover 铺 overlayHover 底且文字保持主文字色，
// 可选左侧 18vp 前置图标（原型 .side-item .ico，书库侧栏不带、设置导航带），
// 可选右侧 muted 计数（11fp）；左键抬起触发 onClick。自定义 Widget（同 ClickSensor 协议）。
public class NavItem <: Widget {
    private let label: String
    private let count: String
    private let active: Bool
    private let onClick: () -> Unit
    private let hoverId: String
    private let glyph: ?GhostGlyph
    private var frame = Rect.zero()

    public init(label: String, active!: Bool = false, count!: String = "", glyph!: ?GhostGlyph = None,
        onClick!: () -> Unit) {
        this.label = label
        this.count = count
        this.active = active
        this.onClick = onClick
        this.glyph = glyph
        // 侧栏条目按文案唯一（全部/仅收藏/…/分类名），整树每帧重建不留残留。
        this.hoverId = "NavItem:${label}"
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(min(available.w, 226.0), 34.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        if (active) {
            ctx.renderer.fillRoundedRect(frame, 9.0, ctx.theme.accentSoft)
        } else if (ctx.isHovered(hoverId)) {
            ctx.renderer.fillRoundedRect(frame, 9.0, ctx.theme.overlayHover)
        }
        // 激活金文字（.side-item.on color: var(--accent)）；hover/常态均主文字色。
        let labelColor = if (active) {
            ctx.theme.accent
        } else {
            ctx.theme.text
        }
        var textX = frame.x + 12.0
        match (glyph) {
            case Some(g) =>
                // 原型 .side-item .ico：18px 图标位 + 9px 间距；激活态图标随文字转金色。
                drawGhostGlyph(ctx.renderer, g, textX + 9.0, frame.centerY(), labelColor)
                textX += 27.0
            case None => ()
        }
        let th = ctx.renderer.textHeight(pointSize: FontSizes.CONTROL)
        let ty = frame.centerY() - th / 2.0
        ctx.renderer.text(label, textX, ty, labelColor, pointSize: FontSizes.CONTROL)
        if (count.size > 0) {
            // 原型 .side-item .cnt：11px、低透明（muted 即低对比语义）。
            let cw = ctx.renderer.textWidth(count, pointSize: 11.0)
            ctx.renderer.text(count, frame.right() - 12.0 - cw, ty, ctx.theme.mutedText, pointSize: 11.0)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    ctx.claimHover(hoverId, CursorShape.Interactive)
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    onClick()
                    return true
                }
            case _ => ()
        }
        false
    }
}

// 图片占位：扁平 field 色块（不用 Panel——raised 描边+阴影与扁平卡片设计冲突），
// 圆角随封面规格（短边 7.2%，对齐原型 .card .cover 的 12px），与 alpha 烘焙的成品封面圆角一致。
// 构建期拿不到 ctx.theme，底色按 model.isLight() 在 palette 明/暗常量间二选一。
private func imagePlaceholder(model: AppModel, w: Length, h: Length, text: String): Unit {
    let field = if (model.isLight()) {
        LANLU_L_FIELD
    } else {
        LANLU_FIELD
    }
    let radius = Length(min(w.value, h.value) * 0.072, w.unit)
    VStack {
        Label(text).fontSize(12.fp).muted()
    }
        .mainAxisAlignment(MainAxisAlignment.Center)
        .crossAxisAlignment(CrossAxisAlignment.Center)
        .width(w)
        .height(h)
        .background(field, radius)
}

// 远程图片：三态（占位/错误可点击重试/成品）。key 形如 asset:42、page:arc:path。
// 首次构建（状态 ""）时经 model.requestImage 发起加载（并发上限由 model 保证）。
// zoom >1 时成品图绕中心放大并裁回框内（卡片 hover 缩放动画用；占位/错误态不缩放）。
public func remoteImage(model: AppModel, key: String, url: String, w: Length, h: Length, zoom!: Float32 = 1.0,
    radius!: Float32 = 0.0, fit!: ImageFit = ImageFit.Cover, startAligned!: Bool = false): Unit {
    let st = model.imageState(key)
    if (st.value == "") {
        model.requestImage(key, url)
        imagePlaceholder(model, w, h, "…")
    } else if (st.value == "loading") {
        imagePlaceholder(model, w, h, "加载中…")
    } else if (st.value == "error") {
        ClickArea(onClick: {=> model.retryImage(key, url)}) {
            imagePlaceholder(model, w, h, "加载失败，点击重试")
        }
    } else {
        // 状态为 "ready"：像素已 stage 进 cui 像素纹理缓存，PixelImageView 首帧惰性建纹理。
        // 封面用 Cover 裁满卡片；width/height 为首选尺寸；zoom 仅作用在成品图上。
        if (startAligned) {
            StartAlignedPixelImage(key, w, h)
        } else {
            PixelImageView(key, w, h, fit: fit).zoom(zoom).rounded(radius)
        }
    }
}

// clearlogo 通常带大块透明画布。普通 Contain 会把可见内容居中，导致它与下一行
// 元数据错位；这里保持等比缩放，只把目标矩形贴到布局框左侧。
private class StartAlignedPixelImage <: Widget {
    private let key: String
    private let preferredWidth: Length
    private let preferredHeight: Length
    private var frame = Rect.zero()

    init(key: String, width: Length, height: Length) {
        this.key = key
        preferredWidth = width
        preferredHeight = height
        emit(this)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        Size(min(available.w, max(0.0, ctx.resolve(preferredWidth))),
            min(available.h, max(0.0, ctx.resolve(preferredHeight))))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        match (pixelTexture(ctx.renderer, key)) {
            case Some(image) =>
                let fitted = fittedRect(Size(image.width, image.height), frame, ImageFit.Contain)
                ctx.renderer.texture(image, Rect(frame.x, fitted.y, fitted.w, fitted.h))
            case None => ()
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 描边色（明/暗双主题；原 login_view 私有件，提升为设置区/登录页共享）。
func edgeOf(model: AppModel): Color {
    if (model.isLight()) {
        LANLU_L_PANEL_EDGE
    } else {
        LANLU_PANEL_EDGE
    }
}

// 幽灵按钮样式（设计稿 .btn-ghost：透明底 + 1px 描边），次要动作用——
// cui Button 默认 buttonSurface 填充色在卡片里显得过重。
func ghostStyleOf(model: AppModel): SurfaceStyle {
    SurfaceStyle(Color.rgba(0, 0, 0, 0), border: edgeOf(model), radius: 10.0, borderWidth: 1.0)
}

// ── 首页卡片组件（Task 9；原型 home-detail-redesign.html「首页」视图 .card 族）──

// hover 封面缩放幅度（frontend base-media-card 的 group-hover:scale-105 同款：
// 卡片不动，封面图在框内放大，替代早期的整卡 translateY 上浮）。
private let CARD_ZOOM: Float32 = 0.05
private let CARD_OVERLAY_MS: Int64 = 180

// 对齐 frontend BaseMediaCard：只为首批 24 张卡片播放 520ms 入场，按序号
// 每张错开 50ms（最多 500ms），避免长列表持续占用重绘。
private let CARD_ENTRANCE_MS: Int64 = 520
private let CARD_ENTRANCE_LIMIT: Int64 = 24
private let CARD_ENTRANCE_STAGGER_MS: Int64 = 50
private let CARD_ENTRANCE_MAX_DELAY_MS: Int64 = 500

// 卡片入场状态按 cardKey 驻留；同一条目因选择态/收藏态重建时不会重复播放。
class CardEntranceState {
    var startedAt: ?UInt64 = None
    var progress: Float32 = 0.0
}

// 构建期读取上一帧 progress 布局位移，绘制期由 ticker 推进时钟。该模式与 HoverLift
// 一致，可在应用层无法直接包裹 builder 子树的限制下保持连续动画。
class CardEntranceTicker <: Widget {
    private let state: CardEntranceState
    private let index: Int64

    public init(state: CardEntranceState, index: Int64) {
        this.state = state
        this.index = index
        if (index >= CARD_ENTRANCE_LIMIT) {
            state.progress = 1.0
        }
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(_: UiContext, _: Rect): Unit {}

    public func draw(ctx: UiContext): Unit {
        if (state.progress >= 1.0 || index >= CARD_ENTRANCE_LIMIT) {
            return
        }
        let startedAt = match (state.startedAt) {
            case Some(value) => value
            case None =>
                state.startedAt = Some(ctx.frame.elapsedMs)
                ctx.frame.elapsedMs
        }
        let elapsed = ctx.frame.elapsedMs - startedAt
        let delay = UInt64(min(index * CARD_ENTRANCE_STAGGER_MS, CARD_ENTRANCE_MAX_DELAY_MS))
        if (elapsed < delay) {
            ctx.requestFrame()
            return
        }
        let wasInFlight = state.progress < 1.0
        state.progress = min(1.0, Float32(Int64(elapsed - delay)) / Float32(CARD_ENTRANCE_MS))
        // 到达 1.0 时再补一帧，让构建期位移精确归零，而不是停在上一帧的近似值。
        if (state.progress < 1.0 || wasInFlight) {
            ctx.requestFrame()
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// CUI 暂无整棵子树的 global alpha；在同色页面底上覆盖反向透明遮罩，可让图片、
// 文本和自绘图形一起淡入，而不是只淡化 surface 修饰器。
class CardEntranceVeil <: Widget {
    private let state: CardEntranceState
    private var frame = Rect.zero()

    public init(state: CardEntranceState) {
        this.state = state
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let alpha = cardEntranceOpacity(state.progress)
        if (alpha < 1.0) {
            ctx.renderer.fill(frame, ctx.theme.bg.withAlpha(Int64(255.0 * (1.0 - alpha))))
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// CSS animation timing-function cubic-bezier(.16,1,.3,1)：逐关键帧分段求值，
// 对齐 frontend archive-card-in 的 0% / 55% / 80% / 100% 纵向回弹。
private func cardEntranceCurve(progress: Float32): Float32 {
    let x = max(0.0, min(1.0, progress))
    var low: Float32 = 0.0
    var high: Float32 = 1.0
    var parameter: Float32 = x
    for (_ in 0..12) {
        parameter = (low + high) / 2.0
        let u = 1.0 - parameter
        let bx = 3.0 * u * u * parameter * 0.16 + 3.0 * u * parameter * parameter * 0.3 +
            parameter * parameter * parameter
        if (bx < x) {
            low = parameter
        } else {
            high = parameter
        }
    }
    let u = 1.0 - parameter
    3.0 * u * u * parameter + 3.0 * u * parameter * parameter + parameter * parameter * parameter
}

private func cardEntranceSegment(progress: Float32, start: Float32, end: Float32, from: Float32,
    to: Float32): Float32 {
    let local = cardEntranceCurve((progress - start) / (end - start))
    from + (to - from) * local
}

private func cardEntranceOffset(progress: Float32): Float32 {
    if (progress < 0.55) {
        cardEntranceSegment(progress, 0.0, 0.55, 14.0, -2.0)
    } else if (progress < 0.8) {
        cardEntranceSegment(progress, 0.55, 0.8, -2.0, 1.0)
    } else {
        cardEntranceSegment(progress, 0.8, 1.0, 1.0, 0.0)
    }
}

private func cardEntranceOpacity(progress: Float32): Float32 {
    if (progress >= 0.55) {
        1.0
    } else {
        cardEntranceCurve(progress / 0.55)
    }
}

// 悬停动画传感器：HoverSensor 的变体——认领 hoverId，并在 draw 里同步推进封面缩放
// Spring 与浮层显隐 Tween。卡片构建期读取动画值（应用层拿不到 buildChild，自定义
// Widget 无法包裹 builder 子树，只能采用「传感器 + 构建期读值」组合）。
class HoverLift <: Widget {
    private let hoverId: String
    private let spring: Spring
    private let overlayTween: Tween
    private let hovered: State<Bool>
    private var frame = Rect.zero()

    public init(hoverId: String, spring: Spring, overlayTween: Tween, hovered: State<Bool>) {
        this.hoverId = hoverId
        this.spring = spring
        this.overlayTween = overlayTween
        this.hovered = hovered
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let isHovered = ctx.isHovered(hoverId)
        if (hovered.value != isHovered) {
            hovered.value = isHovered
        }
        let goal: Float32 = if (isHovered) {
            1.0
        } else {
            0.0
        }
        let _ = spring.animate(ctx, target: goal)
        let _ = overlayTween.animate(ctx, target: goal)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    ctx.claimHover(hoverId, CursorShape.Interactive)
                }
            case _ => ()
        }
        false
    }
}

// ZStack 本身只负责叠放，不会裁剪子树。悬浮信息层可能因标签换行超过封面高度，
// 因此在它绘制前后显式压入/弹出封面裁剪区，避免覆盖标题、meta 或拉长卡片的视觉边界。
// 两个哨兵都以零尺寸参与测量、在 ZStack 布局时伸展到完整封面 frame。
class CoverClipStart <: Widget {
    private var frame = Rect.zero()

    public init() {
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        ctx.renderer.pushClip(frame)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

class CoverClipEnd <: Widget {
    public init() {
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(_: UiContext, _: Rect): Unit {}

    public func draw(ctx: UiContext): Unit {
        ctx.renderer.popClip()
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 封面底部进度条（原型 .cover .prog）：3vp 高，轨道走 ctx.theme.overlayTrack（明暗自适），
// 填充 accent；两端内缩 5vp 避开封面圆角（圆角是封面像素烘焙的 alpha，方角条不能盖出弧外）。
class CoverProgress <: Widget {
    private let pct: Int64 // 0..100
    private var frame = Rect.zero()

    public init(pct: Int64) {
        this.pct = pct
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        // 零尺寸参与测量：ZStack 布局时伸展到完整封面 frame（同 CardHoverActions），
        // 浮层内容不反向参与封面测量。
        Size.zero()
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        // frame 为完整封面 rect，贴底 3vp 自算轨道；两端内缩 5vp：封面圆角为短边 7.2%
        //（168vp 宽 ≈ 12vp），内缩 5 可保证 3vp 高的贴底条始终落在圆角弧内
        //（原型 .cover .prog 为全宽贴底条）。
        let track = Rect(frame.x + 5.0, frame.y + frame.h - 3.0, frame.w - 10.0, 3.0)
        if (track.w <= 0.0) {
            return
        }
        ctx.renderer.fillRoundedRect(track, 1.5, ctx.theme.overlayTrack)
        let clamped = min(max(pct, 0), 100)
        let fw = track.w * Float32(clamped) / 100.0
        if (fw > 0.0) {
            ctx.renderer.fillRoundedRect(Rect(track.x, track.y, fw, 3.0), 1.5, ctx.theme.accent)
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 封面浮层操作层：对应 frontend BaseMediaCard 左下角 32×32 secondary icon button
// （详情/收藏），外加「多选」入口钮（frontend hover 菜单的 multiselect 项——点击
// 进入选择模式并选中本卡，即 model.enterSelection）。
// 绘制与命中共用 detailsRect/favoriteRect/selectRect，避免布局包装层造成视觉位置与点击 frame 偏离。
class CardHoverActions <: Widget {
    private let key: String
    private let hoverVisible: State<Bool>
    private let progress: Float32
    private let favorited: Bool
    private let onDetails: () -> Unit
    private let onFavorite: () -> Unit
    private let onSelect: () -> Unit
    private var frame = Rect.zero()

    public init(key: String, visible: State<Bool>, progress: Float32, favorited: Bool, onDetails: () -> Unit,
        onFavorite: () -> Unit, onSelect: () -> Unit) {
        this.key = key
        this.hoverVisible = visible
        this.progress = progress
        this.favorited = favorited
        this.onDetails = onDetails
        this.onFavorite = onFavorite
        this.onSelect = onSelect
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size.zero()
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    private func detailsRect(): Rect {
        Rect(frame.x + 10.0, frame.y + frame.h - 42.0, 32.0, 32.0)
    }

    private func favoriteRect(): Rect {
        Rect(frame.x + 49.0, frame.y + frame.h - 42.0, 32.0, 32.0)
    }

    // 多选入口钮：排在详情/收藏之后（frontend hover 菜单的 multiselect 项）。
    private func selectRect(): Rect {
        Rect(frame.x + 88.0, frame.y + frame.h - 42.0, 32.0, 32.0)
    }

    private func drawButton(ctx: UiContext, baseRect: Rect, glyph: GhostGlyph, active: Bool, reveal: Float32): Unit {
        let t = max(0.0, min(1.0, reveal))
        if (t <= 0.0) {
            return
        }
        let rect = baseRect.shift(0.0, (1.0 - t) * 6.0)
        // 操作钮与封面必须共享同一个 hover ID，否则上层按钮先认领 MouseMove 后会让
        // 封面 HoverLift 误判为移出并收起整层。按钮自身的高亮直接按实际绘制热区判断。
        let bg = if (rect.contains(ctx.mouseX, ctx.mouseY)) {
            Color.rgba(255, 255, 255, Int64(64.0 * t))
        } else {
            Color.rgba(255, 255, 255, Int64(38.0 * t))
        }
        ctx.renderer.fillRoundedRect(rect, 8.0, bg)
        let iconColor = if (active) {
            ctx.theme.accent
        } else {
            LANLU_ON_MEDIA
        }
        drawGhostGlyph(ctx.renderer, glyph, rect.centerX(), rect.centerY(),
            iconColor.withAlpha(Int64(Float32(Int64(iconColor.a)) * t)))
    }

    public func draw(ctx: UiContext): Unit {
        let detailsT = max(0.0, min(1.0, (progress - 0.06) / 0.94))
        let favoriteT = max(0.0, min(1.0, (progress - 0.16) / 0.84))
        let selectT = max(0.0, min(1.0, (progress - 0.26) / 0.74))
        drawButton(ctx, detailsRect(), GhostGlyph.Named(IconName.Eye), false, detailsT)
        drawButton(ctx, favoriteRect(), GhostGlyph.Heart, favorited, favoriteT)
        drawButton(ctx, selectRect(), GhostGlyph.Named(IconName.Check), false, selectT)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        if (!hoverVisible.value && progress <= 0.01) {
            return false
        }
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (detailsRect().contains(x, y) || favoriteRect().contains(x, y) || selectRect().contains(x, y)) {
                    // ZStack 从上到下派发，操作层会先于 HoverLift 收到事件。继续认领封面
                    // hoverId，保证指针从图片移入按钮时浮层不会因 ID 切换而消失。
                    ctx.claimHover("cover:${key}", CursorShape.Interactive)
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (favoriteRect().contains(x, y)) {
                    onFavorite()
                    return true
                }
                if (detailsRect().contains(x, y)) {
                    onDetails()
                    return true
                }
                if (selectRect().contains(x, y)) {
                    onSelect()
                    return true
                }
            case _ => ()
        }
        false
    }
}

// 合集叠层（原型 .card.tank .stack::before/::after）：封面底下两张错位垫底面板，
// 近层 translate(5,-5) scale(.96)、远层 translate(10,-10) scale(.92)，圆角同封面。
// 颜色随主题两组（palette 的 TANK_STACK_HI/LO），构建期按 isLight 选好传入。
class TankBackdrop <: Widget {
    private let hi: Color
    private let lo: Color
    private let edge: Color
    private var frame = Rect.zero()

    public init(hi: Color, lo: Color, edge: Color) {
        this.hi = hi
        this.lo = lo
        this.edge = edge
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let pen = Pen(width: 1.0, color: edge)
        // 圆角同封面（短边 7.2%，原型 .card.tank .stack 与 .cover 同为 12px）。
        let radius = min(frame.w, frame.h) * 0.072
        let far = Rect(frame.x + frame.w * 0.04 + 10.0, frame.y + frame.h * 0.04 - 10.0, frame.w * 0.92, frame.h * 0.92)
        ctx.renderer.fillRoundedRect(far, radius, lo)
        ctx.renderer.strokeRoundedRect(far, radius, pen)
        let near = Rect(frame.x + frame.w * 0.02 + 5.0, frame.y + frame.h * 0.02 - 5.0, frame.w * 0.96, frame.h * 0.96)
        ctx.renderer.fillRoundedRect(near, radius, hi)
        ctx.renderer.strokeRoundedRect(near, radius, pen)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 合集卡视图模型：由 TankoubonInfo 映射而来（见 tankCardRow），供首页/详情共用 tankCard 渲染。
public class TankCardItem {
    public var id: String = ""
    public var title: String = ""
    public var description: String = ""
    public var tagsCsv: String = ""
    public var coverAssetId: Int64 = 0
    public var archiveCount: Int64 = 0
    public var readPct: Int64 = 0 // 0..100
    public var isfavorite: Bool = false
}

// 聚合合辑条目判定（groupby_tanks 响应的 type=="tankoubon"；普通档案 arcid 非空、itemType 为空）。
public func isTankItem(item: SearchItem): Bool {
    item.itemType == "tankoubon"
}

// LazyRow/LazyGrid 子项 key：合辑用 tank: 前缀，档案用 arc: 前缀——聚合响应里
// 合辑条目 arcid 为空，直接用 arcid 会撞 key（rememberState 'zoom:' 重复闪退的根因）。
public func searchItemKey(item: SearchItem): String {
    if (isTankItem(item)) {
        "tank:${item.tankoubonId}"
    } else {
        "arc:${item.arcid}"
    }
}

// 卡片按类型分派：聚合合辑条目渲染合集卡（点进合集详情），其余渲染档案卡。
public func searchItemCard(model: AppModel, item: SearchItem, coverW: Float32, index!: Int64 = 0): Unit {
    if (isTankItem(item)) {
        let t = TankCardItem()
        t.id = item.tankoubonId
        t.title = item.title
        t.description = item.description
        t.tagsCsv = item.tagsCsv
        t.coverAssetId = item.coverAssetId
        t.archiveCount = item.archiveCount
        t.readPct = progressPct(item.pagecount, item.progress)
        t.isfavorite = item.isfavorite
        tankCard(model, t, coverW, index: index)
    } else {
        archiveCard(model, item, coverW, index: index)
    }
}

// 档案卡片（原型 .card）：扁平无卡片底；封面 3:4 Cover，hover 封面放大 5% + 金描边
// （HoverLift 推进 Spring、PixelImageView.zoom 绕中心放大裁回框内，CoverBorder 切 accent）；
// 右上 NEW 红 pill；悬浮层提供标签/简介/详情/收藏操作；底部 3vp 进度条；
// 封面下标题 1 行截断 + meta 行 muted。
public func archiveCard(model: AppModel, item: SearchItem, coverW: Float32, index!: Int64 = 0): Unit {
    homeCoverCard(model, item.arcid, item.title, cardMeta(item), coverW, item.coverAssetId,
        {=> model.openDetail(item.arcid)}, {=> model.toggleFavoriteOnCard(item.arcid)},
        {=> model.enterSelection(item.arcid)}, isNew: item.isnew, tank: false, favorited: item.isfavorite,
        pct: progressPct(item.pagecount, item.progress), summary: item.description, tagsCsv: item.tagsCsv, index: index)
}

// 书架历史卡片复用同一封面骨架，但 meta 改为“相对阅读时间 · 页数”。
public func archiveCardWithMeta(model: AppModel, item: SearchItem, coverW: Float32, meta: String,
    index!: Int64 = 0): Unit {
    homeCoverCard(model, item.arcid, item.title, meta, coverW, item.coverAssetId, {=> model.openDetail(item.arcid)},
        {=> model.toggleFavoriteOnCard(item.arcid)}, {=> model.enterSelection(item.arcid)}, isNew: item.isnew,
        tank: false, favorited: item.isfavorite, pct: progressPct(item.pagecount, item.progress),
        summary: item.description, tagsCsv: item.tagsCsv, index: index)
}

// 合集卡片（原型 .card.tank）：同骨架 + 封面后两层错位堆栈 + 左上开书图标「合集」角标，
// meta 为「N 个档案 · X%」。点击进合集详情（T11 接通路由）。
public func tankCard(model: AppModel, item: TankCardItem, coverW: Float32, index!: Int64 = 0): Unit {
    homeCoverCard(model, item.id, item.title, "${item.archiveCount} 个档案 · ${item.readPct}%", coverW,
        item.coverAssetId, {=> model.openTank(item.id)}, {=> model.toggleTankFavoriteOnCard(item.id)},
        {=> model.enterSelection(item.id)}, isNew: false, tank: true, favorited: item.isfavorite, pct: item.readPct,
        summary: item.description, tagsCsv: item.tagsCsv, index: index)
}

// 卡片公共骨架：封面 ZStack（可选叠层/封面/描边/角标/进度/悬浮信息层）+ 标题 + meta。
// onSelect 为 hover 浮层「多选」入口（frontend hover 菜单的 multiselect 项）：进入选择模式
// 并选中本卡；tank 详情成员卡由调用方在回调里顺带记录 detailSelectionOwner（见 detail_view）。
private func homeCoverCard(model: AppModel, id: String, title: String, meta: String, coverW: Float32,
    coverAssetId: Int64, onClick: () -> Unit, onFavorite: () -> Unit, onSelect: () -> Unit, isNew!: Bool, tank!: Bool,
    favorited!: Bool, pct!: Int64, summary!: String = "", tagsCsv!: String = "", index!: Int64 = 0): Unit {
    let coverH = coverW * 4.0 / 3.0
    let cardKey = if (tank) {
        "tank:${id}"
    } else {
        "arc:${id}"
    }
    let hoverId = "cover:${cardKey}"
    let entrance = rememberState<CardEntranceState>("entrance:${cardKey}", {=> CardEntranceState()}).value
    if (index >= CARD_ENTRANCE_LIMIT) {
        entrance.progress = 1.0
    }
    let entranceY = cardEntranceOffset(entrance.progress)
    // Spring 0→1 驱动封面缩放（HoverLift 传感器在 draw 里推进弹簧）。
    let zoomSpring = rememberState<Spring>("zoom:${cardKey}", {=> Spring(0.0)}).value
    let overlayTween = rememberState<Tween>("overlay-motion:${cardKey}", {
        => Tween(CARD_OVERLAY_MS, Easing.easeOutCubic)
    }).value
    let overlayT = overlayTween.value
    // HoverLift 在绘制期同步悬停态，下一帧构建与 BaseMediaCard 一致的信息/操作浮层。
    let overlayHovered = rememberState<Bool>("cover-overlay:${cardKey}", {=> false})
    // 多选（第二波）：选择模式下单击 = 切换选中（不再打开详情），选中卡叠 accent
    // 描边 + 右上勾选圆点；浮层详情/收藏操作在选择模式下整层不挂载。
    let selecting = model.selectionMode.value
    let selected = model.isSelected(id)
    ClickArea(onClick: {
        => if (selecting) {
            model.toggleSelected(id)
        } else {
            onClick()
        }
    }) {
        ZStack {
            // 入场播完（progress 达 1.0）后 ticker 不再挂树；状态由分支外的 rememberState
            // 驻留（key 不变），选择态/收藏态重建或列表复用都不会重播。
            if (entrance.progress < 1.0) {
                CardEntranceTicker(entrance, index)
            }
            VStack {
                ZStack {
                    if (tank) {
                        let hi = if (model.isLight()) {
                            LANLU_L_TANK_STACK_HI
                        } else {
                            LANLU_TANK_STACK_HI
                        }
                        let lo = if (model.isLight()) {
                            LANLU_L_TANK_STACK_LO
                        } else {
                            LANLU_TANK_STACK_LO
                        }
                        let edge = if (model.isLight()) {
                            LANLU_L_PANEL_EDGE
                        } else {
                            LANLU_PANEL_EDGE
                        }
                        TankBackdrop(hi, lo, edge)
                    }
                    HoverLift(hoverId, zoomSpring, overlayTween, overlayHovered)
                    if (coverAssetId > 0) {
                        remoteImage(model, "asset:${coverAssetId}", "/api/assets/${coverAssetId}",
                            Length(coverW, LengthUnit.Vp), Length(coverH, LengthUnit.Vp),
                            zoom: 1.0 + CARD_ZOOM * zoomSpring.value, radius: coverW * 0.072)
                    } else {
                        noCoverBox(model, coverW, coverH)
                    }
                    CoverBorder(hoverId)
                    if (selecting && selected) {
                        SelectionRing()
                    }
                    if (overlayT > 0.001) {
                        CoverClipStart()
                        cardHoverOverlay(summary, tagsCsv, coverH, overlayT)
                        CoverClipEnd()
                    }
                    // 命中层始终留在封面树中，避免按下后即时重建移除浮层、MouseUp 穿透到卡片主体。
                    // 选择模式下不挂载：浮层按钮的详情/收藏语义与 toggle 选中冲突。
                    if (!selecting) {
                        CardHoverActions(cardKey, overlayHovered, overlayT, favorited, onClick, onFavorite, onSelect)
                    }
                    // 顶部角标行：左上合集类型、右上 NEW（原型 .badge-type / .badge-new 位置）；
                    // 选择模式下 NEW 让位给勾选圆点（选择态比「新到」更需要一目了然）。
                    // 无任何角标可显示时整行不挂载：空行只剩 HStack{Spacer}.padding 稳态废节点。
                    if (tank || selecting || (isNew && !tank)) {
                        HStack {
                            if (tank) {
                                tankBadge(model)
                            }
                            Spacer()
                            if (selecting) {
                                SelectionDot(selected)
                            } else if (isNew && !tank) {
                                newBadge()
                            }
                        }.crossAxisAlignment(CrossAxisAlignment.Start).padding(8.vp)
                    }
                    // 底部进度条：CoverProgress 与 CardHoverActions 同法，在 ZStack 内伸展到
                    // 完整封面 frame、自算贴底 rect（两端内缩在其内部处理），不再要包装层。
                    if (pct > 0) {
                        CoverProgress(pct)
                    }
                    // 浮层内容不能反向参与封面测量；封面槽位始终保持调用方给定的固定尺寸。
                }.alignment(Alignment.TopLeading).width(coverW).height(coverH)
                Label(title).maxLines(1).fontSize(12.5.fp)
                Label(meta).fontSize(11.fp).muted()
            }.spacing(4.vp).crossAxisAlignment(CrossAxisAlignment.Start).width(coverW).offset(x: 0.0, y: entranceY)
            // 入场遮罩与 ticker 同生命周期：progress 达 1.0 后其 draw 本就不产生任何绘制，
            // 整节点不挂载（连同 offset 修饰节点）。
            if (entrance.progress < 1.0) {
                CardEntranceVeil(entrance).offset(x: 0.0, y: entranceY)
            }
        }.alignment(Alignment.TopLeading)
    }
}

// BaseMediaCard 同款封面悬浮层：底部渐变上依次放标签、三行简介和详情/收藏操作。
// 选择模式的 toggle 由 homeCoverCard 的 ClickArea 分派，本浮层及其操作层仅在非选择模式挂载。
private func cardHoverOverlay(summary: String, tagsCsv: String, coverH: Float32, progress: Float32): Unit {
    let tags = cardHoverTags(tagsCsv)
    let maxTags: Int64 = if (summary.size > 0) {
        5
    } else {
        8
    }
    let t = max(0.0, min(1.0, progress))
    ZStack {
        GradientScrim(direction: GradientDirection.Bottom,
            stops: [(0.0, Color.rgba(0, 0, 0, 0)), (0.38, Color.rgba(0, 0, 0, Int64(56.0 * t))),
                (1.0, Color.rgba(0, 0, 0, Int64(196.0 * t)))])
        // 与 frontend BaseMediaCard 的 absolute bottom 内容层对应：预留 48vp 给操作区，
        // 标签/简介仅在封面内自底向上排布，过长内容由外层封面裁剪。
        VStack {
            if (tags.size > 0) {
                FlowRow {
                    let shown = min(tags.size, maxTags)
                    for (i in 0..shown) {
                        Label(tags[i])
                            .fontSize(10.fp)
                            .foregroundColor(LANLU_ON_MEDIA.withAlpha(Int64(255.0 * t)))
                            .tight()
                            .padding(6.vp, 2.vp)
                            .background(Color.rgba(255, 255, 255, Int64(38.0 * t)), 5.vp)
                    }
                    if (tags.size > shown) {
                        Label("+${tags.size - shown}")
                            .fontSize(10.fp)
                            .foregroundColor(LANLU_ON_MEDIA.withAlpha(Int64(255.0 * t)))
                            .tight()
                            .padding(6.vp, 2.vp)
                            .background(Color.rgba(255, 255, 255, Int64(38.0 * t)), 5.vp)
                    }
                }.spacing(4.vp)
            }
            if (summary.size > 0) {
                Label(summary)
                    .fontSize(10.5.fp)
                    .foregroundColor(Color.rgba(255, 255, 255, Int64(230.0 * t)))
                    .maxLines(3)
                    .tight()
                    .fillWidth()
            }
        }.spacing(6.vp).crossAxisAlignment(CrossAxisAlignment.Start).padding(10.vp, 10.vp, 10.vp, 48.vp).maxHeight(
            coverH)
    }.alignment(Alignment.BottomLeading).offset(x: 0.0, y: (1.0 - t) * 8.0)
}

// 搜索 DTO 的 tags 是 CSV。悬浮卡只展示值部分，过滤 source 命名空间，与 frontend
// BaseMediaCard 的 hoverTags 规则保持一致；原始数据不修改，详情页仍可显示完整标签。
private func cardHoverTags(tagsCsv: String): ArrayList<String> {
    let tags = ArrayList<String>()
    for (raw in tagsCsv.split(",")) {
        let tag = raw.trimAscii()
        if (tag.size == 0 || tag.toAsciiLower().contains("source")) {
            continue
        }
        let shown = match (tag.indexOf(":")) {
            case Some(i) => tag[(i + 1)..tag.size].trimAscii()
            case None => tag
        }
        if (shown.size > 0) {
            tags.add(shown)
        }
    }
    tags
}

// 阅读进度百分比（0..100；无进度返回 0）。
private func progressPct(pagecount: Int64, progress: Int64): Int64 {
    if (pagecount <= 0 || progress <= 0) {
        return 0
    }
    min(100, progress * 100 / pagecount)
}

// meta 行：有进度时「N 页 · 已读 X%」，否则仅「N 页」。
private func cardMeta(item: SearchItem): String {
    let pct = progressPct(item.pagecount, item.progress)
    if (item.pagecount > 0 && pct > 0) {
        return "${item.pagecount} 页 · 已读 ${pct}%"
    }
    "${item.pagecount} 页"
}

private func noCoverBox(model: AppModel, w: Float32, h: Float32): Unit {
    let field = if (model.isLight()) {
        LANLU_L_FIELD
    } else {
        LANLU_FIELD
    }
    VStack {
        Label("无封面").fontSize(12.fp).muted()
    }
        .mainAxisAlignment(MainAxisAlignment.Center)
        .crossAxisAlignment(CrossAxisAlignment.Center)
        .width(w)
        .height(h)
        .background(field, Length(min(w, h) * 0.072, LengthUnit.Vp))
}

// NEW 角标（原型 .badge-new）：danger 红 pill（两主题共用），白字 10fp，圆角 6。
private func newBadge(): Unit {
    Label("NEW")
        .fontSize(10.fp)
        .foregroundColor(Color.rgb(255, 255, 255))
        .padding(7.vp, 2.vp)
        .background(LANLU_NEW_RED, 6.vp)
}

// 合集类型角标（原型 .badge-type.tank）：accent 色字 + rgba(0,0,0,.65) 底
// （叠在封面上不随主题翻转，仅文字色随主题 accent）。
private func tankBadge(model: AppModel): Unit {
    let accent = if (model.isLight()) {
        LANLU_L_ACCENT
    } else {
        LANLU_ACCENT
    }
    HStack {
        GlyphIcon(GhostGlyph.Book, size: 13.0, color: accent)
        Label("合集").fontSize(10.5.fp).foregroundColor(accent)
    }
        .spacing(3.vp)
        .crossAxisAlignment(CrossAxisAlignment.Center)
        .hug()
        .padding(8.vp, 3.vp)
        .background(Color.rgba(0, 0, 0, 165), 6.vp)
}

// 行头（原型 .row-head）：16fp 标题 + 右侧操作位（换一批/查看更多，由调用方给）。
public func sectionHeader(title: String, trailing: () -> Unit): Unit {
    HStack {
        Label(title).fontSize(16.fp)
        Spacer()
        trailing()
    }.crossAxisAlignment(CrossAxisAlignment.Center).hug()
}

// 横排卡片行（原型 .card-row）：横向滚动（滚轮/滑块齐备），只物化视口附近列；
// 间距 14vp，行高由调用方按卡片规格给定。子项 key/卡片按条目类型分派（聚合合辑
// 条目的 arcid 为空，直接用会撞 key 闪退，见 searchItemKey）。
// items 直接持 RocksDB-backed view 引用，LazyRow 仅按可见 rank 解码热点对象。
// scroll：外置横向滚动位置（默认 None 用行内局部状态）。浏览页纵向虚拟化后行会随
// 滚动卸载/重建，局部状态被 StateStore 清除，调用方需外置持有才能保住横滚位置。
public func cardRow(model: AppModel, rowKey: String, items: SearchItemView, coverW: Float32, stripH: Float32,
    recommendationScene!: String = "", seedType!: String = "", seedId!: String = "",
    scroll!: ?State<Float32> = None): Unit {
    LazyRow(items.size, coverW, spacing: 14.0, scroll: scroll, key: {i => searchItemKey(items[i])}, id: "browse:${rowKey}") {
        i =>
            let item = items[i]
            if (recommendationScene.size > 0 && item.arcid.size > 0) {
                homeCoverCard(
                    model,
                    item.arcid,
                    item.title,
                    cardMeta(item),
                    coverW,
                    item.coverAssetId,
                    {=> model.openRecommendedArchive(recommendationScene, seedType, seedId, item.arcid)},
                    {
                        =>
                            model.trackRecommendation(recommendationScene, seedType, seedId, "archive", item.arcid,
                                "favorite")
                            model.toggleFavoriteOnCard(item.arcid)
                    },
                    {=> model.enterSelection(item.arcid)},
                    isNew: item.isnew,
                    tank: false,
                    favorited: item.isfavorite,
                    pct: progressPct(item.pagecount, item.progress),
                    summary: item.description,
                    tagsCsv: item.tagsCsv,
                    index: i
                )
            } else {
                searchItemCard(model, item, coverW, index: i)
            }
    }.height(stripH)
}

// ── 多选批量操作（第二波；对齐 frontend useHomeSelection + HomeBatchActionBar）──

// 把选中的 id 按条目类型拆成档案/合集两列（model.batch* 的两列入参）。类型依据当前
// 已加载条目（搜索结果 + 浏览行）判定；未匹配的 id 按档案处理——翻页/重搜/切页都会
// exitSelection（见 model），正常不会有不可见残留选中。
public func splitSelection(model: AppModel): (ArrayList<String>, ArrayList<String>) {
    let tankIds = HashSet<String>()
    for (item in model.items.value) {
        if (isTankItem(item)) {
            tankIds.add(item.tankoubonId)
        }
    }
    for (row in model.browseRows.value) {
        for (item in row.items) {
            if (isTankItem(item)) {
                tankIds.add(item.tankoubonId)
            }
        }
    }
    let arcids = ArrayList<String>()
    let tanks = ArrayList<String>()
    for (id in model.selectedIds.value) {
        if (tankIds.contains(id)) {
            tanks.add(id)
        } else {
            arcids.add(id)
        }
    }
    (arcids, tanks)
}

// 底部悬浮胶囊批量栏：已选计数 + 收藏/取消收藏/加入合集/删除/退出。
// 删除（二次确认）与加入合集（选合集对话框）的弹窗状态由调用方持有，这里只透传回调；
// 「加入合集」仅档案可加入，无档案选中时禁用。胶囊造型同阅读器页码 pill（panel 底 +
// 全圆角 + StaticBorder 描边）。
public func batchActionBar(model: AppModel, onAddToTank: () -> Unit, onDelete: () -> Unit): Unit {
    let panel = if (model.isLight()) {
        LANLU_L_PANEL
    } else {
        LANLU_PANEL
    }
    let (arcids, tankIds) = splitSelection(model)
    ZStack {
        HStack {
            Label("已选 ${model.selectedCount()} 项").fontSize(12.5.fp)
            Button("收藏", {=> model.batchFavorite(arcids, tankIds, true)}).style(ghostStyleOf(model))
            Button("取消收藏", {=> model.batchFavorite(arcids, tankIds, false)}).style(ghostStyleOf(model))
            Button("加入合集", onAddToTank).style(ghostStyleOf(model)).enabled(arcids.size > 0)
            Button("删除", onDelete).role(ButtonRole.Danger)
            Button("退出", {=> model.exitSelection()}).style(ghostStyleOf(model))
        }
            .spacing(8.vp)
            .crossAxisAlignment(CrossAxisAlignment.Center)
            .hug()
            .padding(14.vp, 8.vp)
            .background(panel, 999.vp)
        StaticBorder(999.0)
    }
}

// ── 详情页共用骨架与组件（Task 11；原型 home-detail-redesign.html「档案详情/合集详情」视图）──

// backdrop 区高：模糊带高 300vp（原型 backdrop 300px）。
private let DETAIL_BACKDROP_H: Float32 = 300.0
// hero 相对 backdrop 底边的上叠量（原型 .hero margin-top:-128px）→ hero 顶占位 = 300-128。
private let HERO_LIFT_H: Float32 = 172.0
// hero 封面 200vp 2:3（原型 .hero .cover-big）。
private let HERO_COVER_W: Float32 = 200.0
private let HERO_COVER_H: Float32 = HERO_COVER_W * 3.0 / 2.0
// 玻璃操作卡宽（原型 .action-card 176px 列）。
private let ACTION_CARD_W: Float32 = 176.0
// 2xl 直出态容纳 6 × 28vp 图标、5 × 4vp 间距及左右内边距。
private let ACTION_CARD_W_INLINE: Float32 = 216.0
// 主侧双列间距与侧栏宽（原型 .detail-grid：1fr : 300px，gap 22）。
private let DETAIL_SIDE_W: Float32 = 300.0
private let DETAIL_COL_GAP: Float32 = 22.0
// 相关推荐/所属合集 mini 卡规格（原型 .rel-row .card 132px）。
private let REL_COVER_W: Float32 = 132.0
private let REL_STRIP_H: Float32 = REL_COVER_W * 4.0 / 3.0 + 50.0 + 12.0
// 成员卡文本区高（同首页 CARD_TEXT_H 规格）。
private let MEMBER_TEXT_H: Float32 = 50.0

// hero 数据（档案/合集共用；badge 首个渲染为金色 pill，其余为普通 pill）。
public class DetailHeroData {
    public var badges: Array<String> = []
    public var isNew: Bool = false // 档案 NEW 红 pill（合集恒 false）
    public var title: String = ""
    public var clearlogoAssetId: Int64 = 0
    public var metaLine: String = ""
    public var progressPct: Int64 = 0 // 0..100；<=0 隐藏内联进度条
    public var progressText: String = "" // 如 "已读 64%"
    public var summary: String = "" // 3 行截断
    public var tags = ArrayList<String>() // 超 10 个折叠为 "+N"
    public var primaryLabel: String = ""
    public var primaryEnabled: Bool = true
    public var onPrimary: () -> Unit = {=> ()}
}

// 无 hover 态圆角描边：详情 d-card / hero 封面 / 操作卡的 1px panelEdge 描边
// （背景由调用方铺，本件只在 ZStack 顶层画边）。
class StaticBorder <: Widget {
    private let radius: Float32
    private var frame = Rect.zero()

    public init(radius: Float32) {
        this.radius = radius
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        ctx.renderer.strokeRoundedRect(frame.inset(0.5), radius - 0.5, Pen(width: 1.0, color: ctx.theme.panelEdge))
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 封面软投影（原型 .cover-big box-shadow:0 18px 48px rgba(0,0,0,.55)）：
// 两层 fillRoundedRectSoft feather 光晕（对齐 cui.core drawSoftShadow / SurfaceCard 的
// 阴影部分，只画阴影不画面）；暗色累计 ≈.45、亮色压到 ≈.10。套在 hero 封面 ZStack 底层。
// 注意：不要用阶梯 alpha 多层矩形（有带状感）——框架原语 fillRoundedRectSoft 自带 feather。
class CoverShadow <: Widget {
    private let radius: Float32
    private let light: Bool
    private var frame = Rect.zero()

    public init(radius: Float32, light: Bool) {
        this.radius = radius
        this.light = light
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        // 原型 blur 48px → spread 取 20（feather 渐隐带的视觉等效，目检微调）；
        // y-offset 18 直接平移。暗色 alpha 140≈.55（原型）、亮色 26≈.10。
        let spread: Float32 = 20.0
        let alpha: Int64 = if (light) {
            26
        } else {
            140
        }
        let base = frame.shift(0.0, 18.0)
        let shadow = Color.rgba(0, 0, 0, alpha)
        ctx
            .renderer
            .fillRoundedRectSoft(base.inset(-spread * 0.3), radius + spread * 0.3, shadow.withAlpha(alpha * 3 / 5),
                feather: spread)
        ctx.renderer.fillRoundedRectSoft(base, radius, shadow.withAlpha(alpha / 2), feather: spread * 0.5)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// hover 描边：同 StaticBorder，但 hover 时描边转 accent（原型 .pv-thumb:hover outline）。
class HoverBorder <: Widget {
    private let radius: Float32
    private let hoverId: String
    private var frame = Rect.zero()

    public init(radius: Float32, hoverId: String) {
        this.radius = radius
        this.hoverId = hoverId
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let edge = if (ctx.isHovered(hoverId)) {
            ctx.theme.accent
        } else {
            ctx.theme.panelEdge
        }
        ctx.renderer.strokeRoundedRect(frame.inset(0.5), radius - 0.5, Pen(width: 1.0, color: edge))
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// hover 铺底：hover 时画 overlayHover 圆角底（原型 .pv-row:hover background）。
class HoverFill <: Widget {
    private let hoverId: String
    private let radius: Float32
    private var frame = Rect.zero()

    public init(hoverId: String, radius: Float32) {
        this.hoverId = hoverId
        this.radius = radius
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(0.0, 0.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        if (ctx.isHovered(hoverId)) {
            ctx.renderer.fillRoundedRect(frame, radius, ctx.theme.overlayHover)
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 进度轨道条（原型 .hero-prog .bar / .prog-card .bar / .member-row .prog-mini）：
// 轨道 ctx.theme.overlayTrack（明暗自适），填充 accent；宽由构造给定（自适应交给父容器修饰器）。
public class ProgressTrack <: Widget {
    private let pct: Int64
    private let h: Float32
    private var frame = Rect.zero()

    public init(pct: Int64, h: Float32) {
        this.pct = pct
        this.h = h
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, h)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        ctx.renderer.fillRoundedRect(frame, h / 2.0, ctx.theme.overlayTrack)
        let clamped = min(max(pct, 0), 100)
        let fw = frame.w * Float32(clamped) / 100.0
        if (fw > 0.0) {
            ctx.renderer.fillRoundedRect(Rect(frame.x, frame.y, fw, h), h / 2.0, ctx.theme.accent)
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 合集已读百分比：对齐 frontend tankoubon/page.tsx :1619（AVG(成员页码) / 总页数，钳制 0..100）。
public func tankReadPct(t: TankoubonInfo): Int64 {
    if (t.totalPages <= 0 || t.progress <= 0.0) {
        return 0
    }
    let pct = Int64(t.progress * 100.0 / Float32(t.totalPages) + 0.5)
    min(100, max(0, pct))
}

// 成员档案已读百分比（成员页码/pagecount，对齐 frontend tankoubon/page.tsx :289
// Math.round：+0.5 取整，同本文件 tankReadPct 做法）。
public func memberReadPct(pagecount: Int64, progress: Int64): Int64 {
    if (pagecount <= 0 || progress <= 0) {
        return 0
    }
    min(100, Int64(Float32(progress) * 100.0 / Float32(pagecount) + 0.5))
}

// 详情共用骨架：backdrop（模糊大图 + 双层 scrim，主题自适应）→ 返回钮 + hero grid
// （封面 200vp 2:3 ｜ 中列 ｜ 176vp 玻璃操作卡）→ 1fr : 300vp 双列卡片流。
// backdropKey 空串表示无封面（纯色底 + scrim）。
public func detailSkeleton(model: AppModel, backdropKey: String, hero: DetailHeroData, coverAssetId: Int64,
    actionIcons: () -> Unit, mainCards: Array<() -> Unit>, sideCards: Array<() -> Unit>, tank!: Bool): Unit {
    let light = model.isLight()
    let panel = if (light) {
        LANLU_L_PANEL
    } else {
        LANLU_PANEL
    }
    let bg = if (light) {
        LANLU_L_BG
    } else {
        LANLU_BG
    }
    ScrollView {
        VStack {
            // backdrop 带（高 300，顶对齐）+ hero 上叠 128（原型 .backdrop 300px / .hero margin-top:-128px）：
            // 外层 ZStack 高 = max(300, 172+heroH)，封面 200×300 横跨模糊带底边。
            ZStack {
                ZStack {
                    // 底色兜底（backdrop 像素未就绪/无封面时可见）
                    VStack {}.fillWidth().height(DETAIL_BACKDROP_H).background(panel)
                    if (backdropKey.size > 0) {
                        PixelImageView(backdropKey, Length(0.0, LengthUnit.Vp), Length(DETAIL_BACKDROP_H, LengthUnit.Vp),
                            fit: ImageFit.Cover).fillWidth()
                    }
                    // 双层 scrim（原型 .backdrop .scrim；明暗两组）：横向左侧压暗 + 底部融入页面底。
                    if (light) {
                        GradientScrim(direction: GradientDirection.Right,
                            stops: [(0.0, Color.rgba(244, 244, 246, 140)), (0.4, Color.rgba(244, 244, 246, 0)),
                                (1.0, Color.rgba(244, 244, 246, 0))])
                        GradientScrim(direction: GradientDirection.Bottom,
                            stops: [(0.0, Color.rgba(244, 244, 246, 115)), (0.92, bg), (1.0, bg)])
                    } else {
                        GradientScrim(direction: GradientDirection.Right,
                            stops: [(0.0, Color.rgba(11, 11, 13, 128)), (0.4, Color.rgba(11, 11, 13, 0)),
                                (1.0, Color.rgba(11, 11, 13, 0))])
                        GradientScrim(direction: GradientDirection.Bottom,
                            stops: [(0.0, Color.rgba(11, 11, 13, 0)), (0.96, bg), (1.0, bg)])
                    }
                }.alignment(Alignment.TopLeading).height(DETAIL_BACKDROP_H).fillWidth()
                // hero 顶占位 172（= 300-128），hero 自 172 起排。
                VStack {
                    VStack {}.fillWidth().height(HERO_LIFT_H)
                    detailHero(model, hero, coverAssetId, actionIcons, tank: tank)
                }
            }.alignment(Alignment.TopLeading)

            // 主侧双列（原型 .detail-grid）：主列 1fr，侧栏 300vp，顶对齐。
            // 主列包 SizeProbe：页面预览缩略图/合集成员网格按它现算列数。
            // .hug().fillWidth()：hug 让整行纵向不参与外层 VStack 的 flex 分配，
            // fillWidth 让横向量满窗口（卡片按内容量宽，不强制时整行会缩在左侧）；
            // 侧栏必须 .hug()：Stack 子元素默认 flexible=true，不 hug 时侧栏会作为第二个
            // flex 子元素与主列均分剩余宽（Width 修饰器只在槽位内限宽绘制，槽位照分）。
            HStack {
                SizeProbe(width: model.detailWidth) {
                    VStack {
                        for (c in mainCards) {
                            c()
                        }
                    }.spacing(20.vp)
                }.flex()
                VStack {
                    for (c in sideCards) {
                        c()
                    }
                }.spacing(20.vp).hug().width(DETAIL_SIDE_W)
            }
                .spacing(DETAIL_COL_GAP)
                .crossAxisAlignment(CrossAxisAlignment.Start)
                .hug()
                .fillWidth()
                .padding(32.vp, 26.vp, 32.vp, 48.vp)
        }.spacing(0.0)
    }
}

// hero grid（原型 .hero）：封面（200vp 2:3，合集带双层堆栈垫底，顶对齐横跨模糊带）｜
// 中列（与封面顶对齐：badges/标题/meta/内联进度/3 行简介/标签 chips）｜
// 玻璃操作卡（底对齐，主按钮 + 图标行）。
public func detailHero(model: AppModel, data: DetailHeroData, coverAssetId: Int64, actionIcons: () -> Unit, tank!: Bool): Unit {
    let light = model.isLight()
    // 标题字号（原型 clamp(24px,3vw,36px)）：windowWidth 未就绪时回退 30。
    let w = model.windowWidth.value
    let titleSize: Float32 = if (w <= 0) {
        30.0
    } else {
        Float32(min(36, max(24, w * 3 / 100)))
    }
    let inlineActions = w >= 1536
    let actionCardW = if (inlineActions) {
        ACTION_CARD_W_INLINE
    } else {
        ACTION_CARD_W
    }
    // 中列宽 = 窗口 - 左右 32 - 封面 200 - 操作卡 - 两段 26vp 间距。
    // （操作卡虚拟预留：卡片在 ZStack 覆盖层、不占 HStack 子位）（windowWidth 未就绪按 1440 估）。
    // 必须显式定宽：框架 HStack 量测给 flex 子列喂全宽、布局却按实际宽约束，
    // 文本换行不一致会把中列尾块（标签 chips）挤出 hero 框架。
    let midW = max(160.0, Float32((if (w <= 0) {
        1440
    } else {
        w
    })) - 316.0 - actionCardW)
    ZStack {
        HStack {
            // 封面（2:3，圆角 14，1px 描边；合集叠两层错位垫底面板）
            ZStack {
                // 软投影恒有（无封面时占位色块同样有卡片感）；设计稿投影仅 .cover-big，操作卡不加
                CoverShadow(14.0, light)
                if (tank) {
                    let hi = if (light) {
                        LANLU_L_TANK_STACK_HI
                    } else {
                        LANLU_TANK_STACK_HI
                    }
                    let lo = if (light) {
                        LANLU_L_TANK_STACK_LO
                    } else {
                        LANLU_TANK_STACK_LO
                    }
                    let edge = if (light) {
                        LANLU_L_PANEL_EDGE
                    } else {
                        LANLU_PANEL_EDGE
                    }
                    TankBackdrop(hi, lo, edge)
                }
                if (coverAssetId > 0) {
                    remoteImage(model, "asset:${coverAssetId}", "/api/assets/${coverAssetId}",
                        Length(HERO_COVER_W, LengthUnit.Vp), Length(HERO_COVER_H, LengthUnit.Vp), radius: 14.0)
                } else {
                    noCoverBox(model, HERO_COVER_W, HERO_COVER_H)
                }
                StaticBorder(14.0)
            }.alignment(Alignment.TopLeading)

            // 中列（顶对齐；节奏 = badge 下 10 / 标题下 8 / 进度·简介·标签各上 12）
            VStack {
                // 徽标行：首个金 pill，其余普通 pill；档案可带 NEW 红 pill
                HStack {
                    ForEachIndexed(data.badges) {
                        i, b => if (i == 0) {
                            let accentSoft = if (light) {
                                LANLU_L_ACCENT_SOFT
                            } else {
                                LANLU_ACCENT_SOFT
                            }
                            let accent = if (light) {
                                LANLU_L_ACCENT
                            } else {
                                LANLU_ACCENT
                            }
                            Label(b)
                                .fontSize(11.fp)
                                .foregroundColor(accent)
                                .padding(10.vp, 3.vp)
                                .background(accentSoft, 12.vp)
                        } else {
                            let elev = if (light) {
                                LANLU_L_PANEL
                            } else {
                                LANLU_PANEL
                            }
                            Label(b)
                                .fontSize(11.fp)
                                .foregroundColor(if (light) {
                                    LANLU_L_MUTED
                                } else {
                                    LANLU_MUTED
                                })
                                .padding(10.vp, 3.vp)
                                .background(elev, 12.vp)
                        }
                    }
                    if (data.isNew) {
                        newBadge()
                    }
                    Spacer()
                }.spacing(8.vp).hug().padding(0.0, 0.0, 0.0, 10.0)

                // 标识区固定为两行：第一行 clearlogo/文字标题，第二行页数、大小等 meta。
                // clearlogo 使用左对齐 Contain，避免透明画布把可见 logo 推到中间。
                VStack {
                    if (data.clearlogoAssetId > 0 && model.imageState("asset:${data.clearlogoAssetId}").value != "error") {
                        remoteImage(model, "asset:${data.clearlogoAssetId}", "/api/assets/${data.clearlogoAssetId}",
                            Length(min(midW, 360.0), LengthUnit.Vp), Length(72.0, LengthUnit.Vp), fit: ImageFit.Contain,
                            startAligned: true)
                    } else {
                        Label(data.title).fontSize(titleSize).maxLines(2)
                    }
                    if (data.metaLine.size > 0) {
                        Label(data.metaLine).fontSize(13.fp).muted().maxLines(1)
                    }
                }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()

                // 内联进度条 + 百分比（原型 .hero-prog；有进度才显示）
                if (data.progressPct > 0) {
                    HStack {
                        ProgressTrack(data.progressPct, 5.0).width(320.vp)
                        let accent = if (light) {
                            LANLU_L_ACCENT
                        } else {
                            LANLU_ACCENT
                        }
                        Label(data.progressText).fontSize(12.fp).foregroundColor(accent)
                    }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().padding(0.0, 12.0, 0.0, 0.0)
                }

                // 简介（3 行截断）
                if (data.summary.size > 0) {
                    Label(data.summary).fontSize(13.fp).muted().maxLines(3).padding(0.0, 12.0, 0.0, 0.0)
                }

                // 标签 chips（超 10 个折叠 "+N"）
                if (data.tags.size > 0) {
                    VStack {tagFlow(model, data.tags)}.padding(0.0, 12.0, 0.0, 0.0)
                }
            }.spacing(0.0).crossAxisAlignment(CrossAxisAlignment.Start).width(midW).padding(0.0, 0.0, 0.0, 4.0)
        }.spacing(26.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().padding(32.vp, 0.vp, 32.vp, 0.vp)

        // 玻璃操作卡（176vp，半透明 capsule 底 + 1px 描边）：ZStack 默认拉伸子元素，
        // 用 Spacer 把卡片压到右下（右 32 底 4，原型 .action-card margin-bottom:4px）。
        // 卡行必须 .hug()：Stack 子元素默认 flexible=true，不 hug 时卡行与 Spacer
        // 均分列高（各分一半），卡行 crossAxis 默认 Stretch 会把卡片拉到 ~170vp。
        VStack {
            Spacer()
            HStack {
                Spacer()
                ZStack {
                    VStack {
                        IconButton(IconName.Play, label: Some(data.primaryLabel), role: ButtonRole.Primary,
                            onClick: data.onPrimary).enabled(data.primaryEnabled)
                        HStack {
                            actionIcons()
                        }.spacing(4.vp).mainAxisAlignment(MainAxisAlignment.SpaceBetween).hug()
                    }.spacing(9.vp).padding(14.vp)
                    StaticBorder(14.0)
                }.width(actionCardW).background(if (light) {
                    LANLU_L_OVERLAY_SURFACE
                } else {
                    LANLU_OVERLAY_SURFACE
                }, 14.vp)
            }.hug()
        }.padding(0.0, 0.0, 32.0, 4.0)
    }.alignment(Alignment.TopLeading)
}

// 详情卡片容器（原型 .d-card）：bg-card + 1px 描边 + 圆角 14 + 18vp 内边距；
// 头部 = 标题 + 可选计数 pill + 右侧工具位（mini-seg/筛选框等）。
public func detailCard(model: AppModel, title: String, count!: String = "", tools!: () -> Unit = {=> ()},
    body!: () -> Unit): Unit {
    let light = model.isLight()
    let bg = if (light) {
        LANLU_L_PANEL
    } else {
        LANLU_FIELD
    }
    let elev = if (light) {
        LANLU_L_PANEL_RAISED
    } else {
        LANLU_PANEL
    }
    ZStack {
        VStack {
            HStack {
                Label(title).fontSize(15.fp)
                if (count.size > 0) {
                    Label(count).fontSize(11.fp).muted().padding(9.vp, 2.vp).background(elev, 10.vp)
                }
                Spacer()
                tools()
            }.crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
            body()
        }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Start).padding(18.vp)
        StaticBorder(14.0)
    // fillWidth：卡片须撑满所在内容列（设置区 640/900 列、详情页列均如此），
    // 缺省自然宽会让卡片只按内容宽度收缩，右侧留出空档。
    }.background(bg, 14.vp).fillWidth()
}

// 字段列表（原型 .info-list .info-row）：k 76vp muted 定宽，v 占满剩余宽度并按需换行；
// 行与分割线都铺满卡片内容宽度，避免按各行自然内容宽度收缩。
public func infoList(model: AppModel, rows: Array<(String, String)>): Unit {
    let sep = if (model.isLight()) {
        Color.rgba(0, 0, 0, 15)
    } else {
        Color.rgba(255, 255, 255, 10)
    }
    VStack {
        ForEachIndexed(rows) {
            i, row =>
                let (k, v) = row
                HStack {
                    Label(k).fontSize(12.fp).muted().width(76.vp)
                    Label(v).fontSize(12.fp).wrap().tight().flex()
                }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth().padding(0.vp, 7.vp)
                if (i + 1 < rows.size) {
                    Divider(color: sep).fillWidth()
                }
        }
    }.spacing(0.0).crossAxisAlignment(CrossAxisAlignment.Start).hug().fillWidth()
}

// 标签 chip（原型 .tag）：1px panelEdge 描边 + 低透明底 + muted 字 pill（圆角全圆）；
// hover 字/边转 accent（边 accent 40%）；点击触发 onTap（详情页：携标签跳搜索）。
class TagChip <: Widget {
    private let text: String
    private let light: Bool
    private let hoverId: String
    private let onTap: () -> Unit
    private let interactive: Bool
    private var frame = Rect.zero()

    public init(text: String, light: Bool, hoverId: String, onTap: () -> Unit, interactive!: Bool = true) {
        this.text = text
        this.light = light
        this.hoverId = hoverId
        this.onTap = onTap
        this.interactive = interactive
        emit(this)
    }

    public func measure(ctx: UiContext, _: Size): Size {
        Size(ctx.renderer.textWidth(text, pointSize: 11.0) + 22.0, ctx.renderer.textHeight(pointSize: 11.0) + 8.0) // 原型 padding:4px 11px
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let hovered = interactive && ctx.isHovered(hoverId)
        let bg = if (light) {
            Color.rgba(0, 0, 0, 13)
        } else {
            Color.rgba(255, 255, 255, 15)
        }
        ctx.renderer.fillRoundedRect(frame, frame.h / 2.0, bg)
        let accent = ctx.theme.accent
        let edge = if (hovered) {
            accent.withAlpha(102)
        } else {
            ctx.theme.panelEdge
        }
        ctx.renderer.strokeRoundedRect(frame.inset(0.5), frame.h / 2.0 - 0.5, Pen(width: 1.0, color: edge))
        let fg = if (hovered) {
            accent
        } else {
            ctx.theme.mutedText
        }
        let tw = ctx.renderer.textWidth(text, pointSize: 11.0)
        let th = ctx.renderer.textHeight(pointSize: 11.0)
        ctx.renderer.text(text, frame.centerX() - tw / 2.0, frame.centerY() - th / 2.0, fg, pointSize: 11.0)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        if (!interactive) {
            return false
        }
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    ctx.claimHover(hoverId, CursorShape.Interactive)
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    onTap()
                    return true
                }
            case _ => ()
        }
        false
    }
}

// 标签 chips 流（原型 .tag-row .tag）：1px 描边 pill、hover 变金、点击携 tag 跳搜索，自动换行。
public func tagFlow(model: AppModel, tags: ArrayList<String>): Unit {
    FlowRow {
        // 最多展示前 10 个，每个以 tag 串为 Keyed 身份（同 ForEach(key: {t => t}) 语义）。
        let shown = min(tags.size, 10)
        var i = 0
        while (i < shown) {
            let t = tags[i]
            Keyed(t) {
                TagChip(t, model.isLight(), "tf:${t}", {=> model.searchExactTag(t)}, interactive: true)
            }
            i += 1
        }
        if (tags.size > 10) {
            TagChip("+${tags.size - 10}", model.isLight(), "tf:overflow", {=> ()}, interactive: false)
        }
    }.spacing(7.vp)
}

// 侧栏标签分组（原型 .tag-group）：按命名空间前缀分组；组内 chips 同 tagFlow 规格，点击携原始串跳搜索。
public func tagGroups(model: AppModel, tags: ArrayList<String>): Unit {
    let groups = groupTagsByNamespace(tags)
    VStack {
        ForEachIndexed(groups) {
            _, g =>
                let (gk, values) = g
                Label(gk).fontSize(11.fp).muted().padding(0.vp, 8.vp, 0.vp, 2.vp)
                FlowRow {
                    ForEach(values, key: {v: (String, String) => v[1]}) {
                        v => TagChip(v[0], model.isLight(), "tg:${gk}:${v[1]}", {=> model.searchExactTag(v[1])},
                            interactive: true)
                    }
                }.spacing(7.vp)
        }
    }.spacing(4.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
}

// 标签分组：按首次出现序归组；返回 (组名, (显示值, 原始 tag) 数组) 列表——
// 显示值去命名空间前缀，点击检索仍用原始串。
private func groupTagsByNamespace(tags: ArrayList<String>): ArrayList<(String, Array<(String, String)>)> {
    let order = ArrayList<String>()
    let buckets = HashMap<String, ArrayList<(String, String)>>()
    for (t in tags) {
        var ns = ""
        var value = t
        match (t.indexOf(":")) {
            case Some(i) =>
                ns = t[0..i]
                value = t[(i + 1)..t.size]
            case None => ()
        }
        let label = tagGroupLabel(ns)
        if (buckets.get(label).isNone()) {
            order.add(label)
            buckets[label] = ArrayList<(String, String)>()
        }
        match (buckets.get(label)) {
            case Some(list) => list.add((value, t))
            case None => ()
        }
    }
    let result = ArrayList<(String, Array<(String, String)>)>()
    for (label in order) {
        match (buckets.get(label)) {
            case Some(list) => result.add((label, list.toArray()))
            case None => ()
        }
    }
    result
}

// 常见标签命名空间的中文组名（展示层静态映射；未收录的前缀按原名显示，无前缀归「其他」）。
private func tagGroupLabel(ns: String): String {
    match (ns) {
        case "artist" => "艺术家"
        case "group" => "社团"
        case "parody" => "原作"
        case "character" => "角色"
        case "language" => "语言"
        case "female" => "女性"
        case "male" => "男性"
        case "category" => "分类"
        case "" => "其他"
        case _ => ns
    }
}

// 侧栏进度大卡（原型 .prog-card）：居中大数字 + 说明行 + 6vp 轨道条。
public func progressCard(model: AppModel, big: String, ofText: String, pct: Int64): Unit {
    let light = model.isLight()
    let bg = if (light) {
        LANLU_L_PANEL
    } else {
        LANLU_FIELD
    }
    let accent = if (light) {
        LANLU_L_ACCENT
    } else {
        LANLU_ACCENT
    }
    ZStack {
        VStack {
            Label(big).fontSize(38.fp).foregroundColor(accent)
            Label(ofText).fontSize(12.fp).muted().maxLines(2)
            ProgressTrack(pct, 6.0).padding(0.0, 10.0, 0.0, 0.0)
        }.spacing(4.vp).crossAxisAlignment(CrossAxisAlignment.Center).padding(18.vp, 22.vp)
        StaticBorder(14.0)
    }.background(bg, 14.vp)
}

// 合集 mini 卡横排行（原型 .rel-row 的合集版）：132vp tankCard + 横向滚动。
// tanks 直接持 model 的 ArrayList 引用（只读、随帧释放），避免每帧 toArray 全量拷贝。
public func tankCardRow(model: AppModel, tanks: ArrayList<TankoubonInfo>, rowId: String,
    recommendationScene!: String = "", seedType!: String = "", seedId!: String = ""): Unit {
    let items = ArrayList<TankCardItem>()
    for (t in tanks) {
        items.add(tankCardItem(t))
    }
    renderTankCardRow(model, items, rowId, recommendationScene, seedType, seedId)
}

// RocksDB-backed 版本：按 rank 从有界视图取合集，不复制全量对象数组。
public func tankCardRow(model: AppModel, tanks: TankoubonView, rowId: String,
    recommendationScene!: String = "", seedType!: String = "", seedId!: String = ""): Unit {
    let items = ArrayList<TankCardItem>()
    for (i in 0..tanks.size) {
        match (tanks.itemAt(i)) {
            case Some(t) => items.add(tankCardItem(t))
            case None => ()
        }
    }
    renderTankCardRow(model, items, rowId, recommendationScene, seedType, seedId)
}

private func tankCardItem(t: TankoubonInfo): TankCardItem {
    let c = TankCardItem()
    c.id = t.id
    c.title = t.name
    c.description = t.description
    // StringBuilder 拼 CSV：String.join 要求 Array，会为每个合集每帧 toArray 一次标签表。
    let csv = StringBuilder()
    for (i in 0..t.tags.size) {
        if (i > 0) {
            csv.append(",")
        }
        csv.append(t.tags[i])
    }
    c.tagsCsv = csv.toString()
    c.coverAssetId = t.coverAssetId
    c.archiveCount = t.archiveCount
    c.readPct = tankReadPct(t)
    c.isfavorite = t.isfavorite
    return c
}

private func renderTankCardRow(model: AppModel, items: ArrayList<TankCardItem>, rowId: String,
    recommendationScene: String, seedType: String, seedId: String): Unit {
    LazyRow(items.size, REL_COVER_W, spacing: 14.0, key: {i => items[i].id}, id: rowId) {
        i =>
            let item = items[i]
            if (recommendationScene.size > 0) {
                homeCoverCard(
                    model,
                    item.id,
                    item.title,
                    "${item.archiveCount} 个档案 · ${item.readPct}%",
                    REL_COVER_W,
                    item.coverAssetId,
                    {=> model.openRecommendedTank(recommendationScene, seedType, seedId, item.id)},
                    {
                        =>
                            model.trackRecommendation(recommendationScene, seedType, seedId, "tankoubon", item.id,
                                "favorite")
                            model.toggleTankFavoriteOnCard(item.id)
                    },
                    {=> model.enterSelection(item.id)},
                    isNew: false,
                    tank: true,
                    favorited: item.isfavorite,
                    pct: item.readPct,
                    summary: item.description,
                    tagsCsv: item.tagsCsv,
                    index: i
                )
            } else {
                tankCard(model, item, REL_COVER_W, index: i)
            }
    }.height(REL_STRIP_H)
}

// ── 页面预览（原型 .pv-*：缩略图/列表/树三态；已读页半透明，媒体页带类型图标）──

private let PAGE_PREVIEW_MAX_H: Float32 = 500.0
private let PAGE_PREVIEW_ROW_H: Float32 = 32.0

func pagePreviewViewportHeight(contentHeight: Float32): Float32 {
    min(max(contentHeight, 0.0), PAGE_PREVIEW_MAX_H)
}

// 媒体页类型图标统一走 CUI 矢量图标，不依赖应用字体的符号/emoji 覆盖范围。
public func pageTypeIcon(pageType: String): ?IconName {
    match (pageType) {
        case "video" => Some(IconName.Play)
        case "audio" => Some(IconName.Music)
        case "html" => Some(IconName.NewDocument)
        case _ => None
    }
}

// 页面预览卡体：按 model.pageViewIndex（0=缩略图 1=列表 2=树）切换；
// readUpTo 为已读页码（≤ 该页码的页半透明）；点击页进阅读器对应页。
// pages 按 rank 从 RocksDB-backed view 取当前可见对象，避免长期保留全量 PageInfo 数组。
public func pagePreview(model: AppModel, arcid: String, pages: ArchivePageView, readUpTo: Int64,
    onOpenPage: (Int64) -> Unit): Unit {
    if (pages.size == 0) {
        return
    }
    if (model.pageViewIndex.value == 1) {
        pvList(model, pages, readUpTo, onOpenPage)
    } else if (model.pageViewIndex.value == 2) {
        pvTree(model, pages, readUpTo, onOpenPage)
    } else {
        pvGrid(model, arcid, pages, readUpTo, onOpenPage)
    }
}

// 缩略图态（原型 .pv-grid）：auto-fill minmax(96px,1fr) → 列数按主列宽现算；
// 单元格 16:10，左上页码 pill，右上媒体类型图标，已读半透明。
private func pvGrid(model: AppModel, arcid: String, pages: ArchivePageView, readUpTo: Int64,
    onOpenPage: (Int64) -> Unit): Unit {
    let w = model.detailWidth.value - 36.0 // 减去 d-card 两侧 18vp 内边距
    var cols = if (w <= 0.0) {
        6
    } else {
        Int64((w + 10.0) / 106.0)
    }
    if (cols < 2) {
        cols = 2
    }
    let cellW = if (w <= 0.0) {
        Float32(96.0)
    } else {
        (w - Float32(cols - 1) * 10.0) / Float32(cols)
    }
    let cellH = cellW * 10.0 / 16.0
    let rows = (pages.size + cols - 1) / cols
    let gridH = Float32(rows) * cellH + Float32(rows - 1) * 10.0
    // (count, itemAt) 形式按需取页：不再为配对页码每帧新建 indexed 中间表。
    LazyGrid(pages.size, cols, cellH, spacing: 10.0, columnSpacing: 10.0, id: "pv-grid", itemAt: {i => (i + 1, pages[i])}) {
        item =>
            let (no, p) = item
            pvThumb(model, arcid, no, p, no <= readUpTo, cellW, cellH) {=> onOpenPage(no)}
    }.height(pagePreviewViewportHeight(gridH))
}

// 详情页缩略图复用阅读器的原始页面磁盘缓存，但以 thumb: 展示 key 解码到 300px 档：
// 冷缓存只下载一份原图，之后进入阅读器可直接从同一原始缓存解码 2000px 档。
// 自定义缩略图优先走资产：展示 key 用 athumb:<id>（按 thumb 的 300px 档解码，显示位
// 仅 ~100-150vp，asset: 的 400 档浪费），rawKeyFor 归并回 asset:<id> 与封面共享同一
// 原始磁盘缓存（不重复下载）。非图片页没有自定义缩略图时保留媒体类型占位，避免把
// 视频/音频/html 原文件当图片送去解码。
func pagePreviewThumbKey(arcid: String, page: PageInfo): String {
    if (page.thumbAssetId > 0) {
        return "athumb:${page.thumbAssetId}"
    }
    if ((page.pageType == "image" || page.pageType == "") && page.id.size > 0) {
        return "thumb:${arcid}:${page.id}"
    }
    ""
}

func pagePreviewThumbUrl(arcid: String, page: PageInfo): String {
    if (page.thumbAssetId > 0) {
        return "/api/assets/${page.thumbAssetId}"
    }
    if ((page.pageType == "image" || page.pageType == "") && page.id.size > 0) {
        return "/api/archives/${arcid}/page?path=${percentEncode(page.id)}"
    }
    ""
}

private func pvThumb(model: AppModel, arcid: String, no: Int64, page: PageInfo, read: Bool, w: Float32, h: Float32,
    onOpen: () -> Unit): Unit {
    let light = model.isLight()
    // 原型 .pv-thumb 渐变近色（扁平近似），明暗两组。
    let thumbBg = if (light) {
        Color.rgb(0xD0, 0xD9, 0xE6)
    } else {
        Color.rgb(0x1D, 0x26, 0x35)
    }
    let badgeBg = if (light) {
        Color.rgba(255, 255, 255, 179)
    } else {
        Color.rgba(0, 0, 0, 153)
    }
    let badgeFg = if (light) {
        LANLU_L_TEXT
    } else {
        LANLU_ON_MEDIA
    }
    // 已读变淡：ZStack.opacity 只淡 surface（色块/pill 底），页码与图标是纯 Label——
    // 文字色显式换 45% 透明度色（115≈0.45*255），未读色保持原值。
    let badgeFgRead = if (light) {
        Color.rgba(0x1D, 0x1D, 0x21, 115)
    } else {
        Color.rgba(0xF2, 0xF2, 0xF4, 115)
    }
    let iconFg = if (light) {
        LANLU_L_TEXT
    } else {
        LANLU_TEXT
    }
    let iconFgRead = if (light) {
        Color.rgba(0x1D, 0x1D, 0x21, 115)
    } else {
        Color.rgba(0xE8, 0xE8, 0xEA, 115)
    }
    let icon = pageTypeIcon(page.pageType)
    let thumbKey = pagePreviewThumbKey(arcid, page)
    let thumbUrl = pagePreviewThumbUrl(arcid, page)
    // ClickArea 是发射类不是 Widget，opacity 要下放到内部 ZStack（传感器全透明不受影响）。
    ClickArea(onClick: onOpen) {
        ZStack {
            HoverSensor("pv:${no}")
            VStack {}.fillWidth().height(h).background(thumbBg, 9.vp)
            if (thumbKey.size > 0) {
                // pvGrid 由 LazyGrid 虚拟化：只有当前视口和少量 overscan 行会构建到这里，
                // 因而 remoteImage 的构建期请求天然是可见项按需加载；普通优先级确保
                // 阅读器当前页的 highPriority 请求仍可插队。
                remoteImage(model, thumbKey, thumbUrl, Length(w, LengthUnit.Vp), Length(h, LengthUnit.Vp), radius: 9.0)
            }
            VStack {
                HStack {
                    Label("${no}")
                        .fontSize(9.fp)
                        .foregroundColor(if (read) {
                            badgeFgRead
                        } else {
                            badgeFg
                        })
                        .padding(6.vp, 1.vp)
                        .background(badgeBg, 5.vp)
                    Spacer()
                    match (icon) {
                        case Some(value) => Icon(value, size: 10.vp, color: if (read) {
                            iconFgRead
                        } else {
                            iconFg
                        })
                        case None => ()
                    }
                }.hug()
            }.padding(5.vp)
            HoverBorder(9.0, "pv:${no}")
        }.opacity(if (read) {
            0.45
        } else {
            1.0
        })
    }
}

// 列表态（原型 .pv-list .pv-row）：页码右对齐定宽 + 文件名截断 + 类型图标，已读半透明。
private func pvList(model: AppModel, pages: ArchivePageView, readUpTo: Int64, onOpenPage: (Int64) -> Unit): Unit {
    let contentH = Float32(pages.size) * PAGE_PREVIEW_ROW_H
    LazyList(pages.size, {_ => PAGE_PREVIEW_ROW_H}, id: "pv-list", key: {i => "page:${i}"}) {
        i =>
            let no = i + 1
            let p = pages[i]
            pvRow(model, no, pageFileName(p), pageTypeIcon(p.pageType), no <= readUpTo, 0.0) {
                => onOpenPage(no)
            }
    }.height(pagePreviewViewportHeight(contentH))
}

// 树态（原型 #pv-tree）：按目录分组（首次出现序），目录行用向下矢量图标 + 成员行缩进。
private class PagePreviewTreeRow {
    var isHeader: Bool = false
    var title: String = ""
    var pageIndex: Int64 = 0
}

private func pvTree(model: AppModel, pages: ArchivePageView, readUpTo: Int64, onOpenPage: (Int64) -> Unit): Unit {
    // 预分组：目录 → 页码列表（保持原顺序）。
    let dirs = ArrayList<String>()
    let grouped = HashMap<String, ArrayList<Int64>>()
    for (i in 0..pages.size) {
        let d = pageDir(pages[i].id)
        if (grouped.get(d).isNone()) {
            dirs.add(d)
            grouped[d] = ArrayList<Int64>()
        }
        match (grouped.get(d)) {
            case Some(list) => list.add(i)
            case None => ()
        }
    }
    // 先把目录标题与页行压平为轻量索引，再由 LazyList 只构建可见 widget。
    // 分组仍是 O(n)，但不再为每页分配 ClickArea/ZStack/Label 整棵视图树。
    let rows = ArrayList<PagePreviewTreeRow>()
    for (d in dirs) {
        match (grouped.get(d)) {
            case Some(list) =>
                let header = PagePreviewTreeRow()
                header.isHeader = true
                let dirName = if (d.size > 0) {
                    d
                } else {
                    "（根目录）"
                }
                header.title = "${dirName}（${list.size}）"
                rows.add(header)
                for (i in list) {
                    let row = PagePreviewTreeRow()
                    row.pageIndex = i
                    rows.add(row)
                }
            case None => ()
        }
    }
    let contentH = Float32(rows.size) * PAGE_PREVIEW_ROW_H
    LazyList(rows.size, {_ => PAGE_PREVIEW_ROW_H}, id: "pv-tree", key: {
        i => if (rows[i].isHeader) {
            "dir:${rows[i].title}"
        } else {
            "page:${rows[i].pageIndex}"
        }
    }) {
        i =>
            let row = rows[i]
            if (row.isHeader) {
                let _ = HStack {
                    Icon(IconName.ChevronDown, size: 12.vp)
                    Label(row.title).fontSize(12.fp)
                }.spacing(5.vp).hug().padding(8.vp, 4.vp)
            } else {
                let no = row.pageIndex + 1
                let p = pages[row.pageIndex]
                pvRow(model, no, pageFileName(p), pageTypeIcon(p.pageType), no <= readUpTo, 20.0) {=> onOpenPage(no)}
            }
    }.height(pagePreviewViewportHeight(contentH))
}

// 列表/树共用行：indent 为左侧额外缩进（树态成员行用）；点击进阅读器对应页。
private func pvRow(model: AppModel, no: Int64, name: String, icon: ?IconName, read: Bool, indent: Float32,
    onOpen: () -> Unit): Unit {
    let light = model.isLight()
    // 已读变淡：整行是纯 Label，opacity 修饰器只作用 surface 填充（对行是死代码）——
    // 改为显式 45% 透明度文字色（115≈0.45*255），对齐原型 .pv-row.read{opacity:.45}；
    // 未读色与主题 text/muted token 同值，明暗两套随 isLight() 二选一。
    let fg = if (read) {
        if (light) {
            Color.rgba(0x6D, 0x6D, 0x76, 115)
        } else {
            Color.rgba(0x9A, 0x9A, 0xA2, 115)
        }
    } else {
        if (light) {
            LANLU_L_MUTED
        } else {
            LANLU_MUTED
        }
    }
    let iconFg = if (read) {
        if (light) {
            Color.rgba(0x1D, 0x1D, 0x21, 115)
        } else {
            Color.rgba(0xE8, 0xE8, 0xEA, 115)
        }
    } else {
        if (light) {
            LANLU_L_TEXT
        } else {
            LANLU_TEXT
        }
    }
    ClickArea(onClick: onOpen) {
        ZStack {
            HoverSensor("pvrow:${no}")
            HoverFill("pvrow:${no}", 8.0)
            HStack {
                if (indent > 0.0) {
                    Label("").width(Length(indent, LengthUnit.Vp))
                }
                Label("${no}").fontSize(12.fp).foregroundColor(fg).width(30.vp)
                Label(name).fontSize(12.fp).foregroundColor(fg).maxLines(1).flex()
                match (icon) {
                    case Some(value) => Icon(value, size: 11.vp, color: iconFg)
                    case None => ()
                }
            }.spacing(10.vp).hug().padding(8.vp, 4.vp)
        }.alignment(Alignment.TopLeading)
    }
}

// 页 id（路径）的目录部分；无 "/" 归根目录（空串）。
private func pageDir(id: String): String {
    match (id.lastIndexOf("/")) {
        case Some(i) => id[0..i]
        case None => ""
    }
}

// 页展示名：title 优先，缺省取 id 末段文件名。
private func pageFileName(p: PageInfo): String {
    if (p.title.size > 0) {
        return p.title
    }
    match (p.id.lastIndexOf("/")) {
        case Some(i) => p.id[(i + 1)..p.id.size]
        case None => p.id
    }
}

// ── 合集成员（原型 .member-grid / .member-list；成员行含 mini 进度条）──

// 网格态：auto-fill minmax(140px,1fr)；卡片同首页规格，悬停提供详情/收藏/多选图标按钮。
// onEnterSelection：hover 浮层「多选」入口回调（进入选择模式并选中该项；tank 详情由
// 调用方顺带记录选择归属，见 detail_view.detailSelectionOwner）。
public func memberGridContent(model: AppModel, members: SearchItemProjectionView, onEnterSelection: (String) -> Unit,
    onRemove: (String) -> Unit): Unit {
    let w = model.detailWidth.value - 36.0
    var cols = if (w <= 0.0) {
        4
    } else {
        Int64((w + 12.0) / 152.0)
    }
    if (cols < 2) {
        cols = 2
    }
    let cellW = if (w <= 0.0) {
        Float32(140.0)
    } else {
        (w - Float32(cols - 1) * 12.0) / Float32(cols)
    }
    let coverH = cellW * 4.0 / 3.0
    // 视口虚拟化：ClipLazyGrid 按祖先 ScrollView 的裁剪窗只物化可见行（±overscan），布局仍
    // 占满完整内容高（组件自行按行数×行高上报，勿加 .height(gridH)——那是 LazyGrid 的定高
    // 用法，会把视口撑成整个网格、虚拟化失效，几百个成员的一次性全量构建曾卡死详情页）。
    ClipLazyGrid(members.size, cols, coverH + MEMBER_TEXT_H, spacing: 16.0, columnSpacing: 12.0, id: "member-grid",
        itemAt: {i => (i, members[i])}) {
        pair =>
        let (index, item) = pair
        if (model.selectionMode.value) {
            memberSelectCard(model, item, cellW)
        } else {
            memberCard(model, item, cellW, onEnterSelection, onRemove, index: index)
        }
    }
}

// 成员卡：复用首页卡骨架，悬停提供详情/收藏/多选图标按钮。
private func memberCard(model: AppModel, item: SearchItem, coverW: Float32, onEnterSelection: (String) -> Unit,
    onRemove: (String) -> Unit, index!: Int64 = 0): Unit {
    ContextMenu(
        items: [
            MenuItem("打开详情", {=> model.openDetail(item.arcid)}),
            MenuItem(if (item.isfavorite) {
                "取消收藏"
            } else {
                "收藏"
            }, {=> model.toggleFavoriteOnCard(item.arcid)}),
            MenuItem("标为已读", {=> model.toggleIsNew(item.arcid, false)}),
            MenuItem.separator(),
            MenuItem("从合集移除", {=> onRemove(item.arcid)})
        ],
        key: "member:${item.arcid}"
    ) {
        homeCoverCard(model, item.arcid, item.title, cardMeta(item), coverW, item.coverAssetId,
            {=> model.openDetail(item.arcid)}, {=> model.toggleFavoriteOnCard(item.arcid)},
            {=> onEnterSelection(item.arcid)}, isNew: item.isnew, tank: false, favorited: item.isfavorite,
            pct: memberReadPct(item.pagecount, item.progress), summary: item.description, tagsCsv: item.tagsCsv,
            index: index)
    }
}

// 选择模式成员卡（网格态）：不走 homeCoverCard（该卡归书库多选改造），用简化卡——
// 封面 + 标题/meta，点击 = 切换选中；选中态为 accentSoft 高亮底 + 标题行勾选图标。
private func memberSelectCard(model: AppModel, item: SearchItem, coverW: Float32): Unit {
    let light = model.isLight()
    let accent = if (light) {
        LANLU_L_ACCENT
    } else {
        LANLU_ACCENT
    }
    let accentSoft = if (light) {
        LANLU_L_ACCENT_SOFT
    } else {
        LANLU_ACCENT_SOFT
    }
    let selected = model.isSelected(item.arcid)
    let coverH = coverW * 4.0 / 3.0
    ClickArea(onClick: {=> model.toggleSelected(item.arcid)}) {
        VStack {
            if (item.coverAssetId > 0) {
                remoteImage(model, "asset:${item.coverAssetId}", "/api/assets/${item.coverAssetId}",
                    Length(coverW, LengthUnit.Vp), Length(coverH, LengthUnit.Vp))
            } else {
                noCoverBox(model, coverW, coverH)
            }
            HStack {
                if (selected) {
                    Icon(IconName.Check, size: 12.vp, color: accent)
                }
                Label(item.title).fontSize(12.fp).maxLines(1).flex()
            }.spacing(4.vp).hug()
            Label(memberMeta(item, memberReadPct(item.pagecount, item.progress))).fontSize(11.fp).muted().maxLines(1)
        }.spacing(3.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().background(if (selected) {
            accentSoft
        } else {
            Color.rgba(0, 0, 0, 0)
        }, 10.vp)
    }
}

// 列表态行高：40×56 mini 封面 + 上下 8vp 内边距 = 72vp（LazyList 定高行）。
private let MEMBER_ROW_H: Float32 = 72.0
// 列表态高度上限（vp）：合集成员可达万级（model pageSize=10000），与页层 ScrollView
// 嵌套时 LazyList 若拿全内容高则视口=内容、虚拟化失效；封顶后列表内部自滚动，
// 行构建/绘制/封面请求只付一屏（评审 #9）。成员数少（内容高低于上限）时外观与原
// 全量 VStack 完全一致，仅大合集出现行内滚动条。
private let MEMBER_LIST_MAX_H: Float32 = 736.0

// 列表态（原型 .member-row）：序号 + 40×56 mini 封面 + 标题/meta + 90vp mini 进度条。
// 选择模式：行首勾选图标位、点击 = 切换选中（而非打开详情）、选中行铺 accentSoft 高亮底。
// 非选择模式：序号位让位给行首勾选圆圈（frontend 列表项 hover 勾选入口），点击 = 进入
// 选择模式并选中本行（onEnterSelection，tank 详情由调用方记录选择归属）。
public func memberListContent(model: AppModel, members: SearchItemProjectionView, onEnterSelection: (String) -> Unit,
    onRemove: (String) -> Unit): Unit {
    let light = model.isLight()
    let accent = if (light) {
        LANLU_L_ACCENT
    } else {
        LANLU_ACCENT
    }
    let accentSoft = if (light) {
        LANLU_L_ACCENT_SOFT
    } else {
        LANLU_ACCENT_SOFT
    }
    let contentH = Float32(members.size) * MEMBER_ROW_H + Float32(max(0, members.size - 1)) * 2.0
    LazyList(members.size, {_ => MEMBER_ROW_H}, spacing: 2.0, key: {i => members[i].arcid}, id: "member-list") {
        i =>
            let it = members[i]
            let pct = memberReadPct(it.pagecount, it.progress)
            let selecting = model.selectionMode.value
            let selected = selecting && model.isSelected(it.arcid)
            ContextMenu(
                items: [
                    MenuItem("打开详情", {=> model.openDetail(it.arcid)}),
                    MenuItem(if (it.isfavorite) {
                        "取消收藏"
                    } else {
                        "收藏"
                    }, {=> model.toggleFavoriteOnCard(it.arcid)}),
                    MenuItem("标为已读", {=> model.toggleIsNew(it.arcid, false)}),
                    MenuItem.separator(),
                    MenuItem("从合集移除", {=> onRemove(it.arcid)})
                ],
                key: "member-row:${it.arcid}"
            ) {
                ClickArea(onClick: {
                    => if (model.selectionMode.value) {
                        model.toggleSelected(it.arcid)
                    } else {
                        model.openDetail(it.arcid)
                    }
                }) {
                    HStack {
                        if (selecting) {
                            VStack {
                                if (selected) {
                                    Icon(IconName.Check, size: 12.vp, color: accent)
                                }
                            }.crossAxisAlignment(CrossAxisAlignment.Center).width(18.vp)
                        } else {
                            MemberRowSelectEntry(it.arcid, {=> onEnterSelection(it.arcid)})
                        }
                        Label("${i + 1}").fontSize(11.fp).muted().width(30.vp)
                        if (it.coverAssetId > 0) {
                            remoteImage(model, "asset:${it.coverAssetId}", "/api/assets/${it.coverAssetId}",
                                Length(40.0, LengthUnit.Vp), Length(56.0, LengthUnit.Vp))
                        } else {
                            noCoverBox(model, 40.0, 56.0)
                        }
                        VStack {
                            Label(it.title).fontSize(13.fp).maxLines(1)
                            Label(memberMeta(it, pct)).fontSize(11.fp).muted().maxLines(1)
                        }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
                        ProgressTrack(pct, 4.0).width(90.vp)
                    }
                        .spacing(12.vp)
                        .crossAxisAlignment(CrossAxisAlignment.Center)
                        .hug()
                        .padding(8.vp)
                        .background(if (selected) {
                            accentSoft
                        } else {
                            Color.rgba(0, 0, 0, 0)
                        }, 8.vp)
                }
            }
    }.height(min(contentH, MEMBER_LIST_MAX_H))
}

// 成员列表行首多选入口（frontend 列表项的勾选圆圈）：常态 muted 空心圆，hover 转
// accent 实底白勾提示可点；点击消费事件（不穿透到行 ClickArea 的打开详情）。
class MemberRowSelectEntry <: Widget {
    private let hoverId: String
    private let onEnter: () -> Unit
    private var frame = Rect.zero()

    public init(arcid: String, onEnter: () -> Unit) {
        this.hoverId = "member-select:${arcid}"
        this.onEnter = onEnter
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(18.0, 18.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let cx = frame.centerX()
        let cy = frame.centerY()
        if (ctx.isHovered(hoverId)) {
            ctx.renderer.fillCircle(cx, cy, 8.0, ctx.theme.accent)
            drawIcon(ctx.renderer, IconName.Check, Rect(cx - 5.0, cy - 5.0, 10.0, 10.0), Color.rgb(255, 255, 255))
        } else {
            ctx.renderer.strokeCircle(cx, cy, 8.0, Pen(width: 1.2, color: ctx.theme.mutedText))
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    ctx.claimHover(hoverId, CursorShape.Interactive)
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    onEnter()
                    return true
                }
            case _ => ()
        }
        false
    }
}

// 成员行 meta：「N 页 · 已读 X%」或仅「N 页」（与首页卡 meta 同规）。
private func memberMeta(item: SearchItem, pct: Int64): String {
    if (item.pagecount > 0 && pct > 0) {
        return "${item.pagecount} 页 · 已读 ${pct}%"
    }
    "${item.pagecount} 页"
}
