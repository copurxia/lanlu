package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import std.collection.{ArrayList, HashSet}

// ── 阅读器两个边缘抽屉（reader-redesign.html #sidebar / #settings，T3）──
// 右侧 #settings 阅读设置 / 左侧 #sidebar 页面导航，均直接复用 cui Drawer：
// 弹簧滑入滑出（stiffness 260/damping 26）、scrim 淡入、点击 scrim 或 Esc 关闭、
// 非模态（面板外事件落回底层阅读页）都由 Drawer 自带，这里只提供面板内容。
// presented 直接绑 AppModel 的 State（互斥由 toggleReaderSettings/toggleReaderSidebar
// 保证）；Drawer 的 onDismiss 在用户经 scrim/Esc 关闭时回落到 closeReaderPanels，
// 保证两个 State 始终同假。抽屉挂在 readerView 的 ZStack 里（不占布局空间，
// Drawer 经 overlay 自锚定视口边缘）。

// 设计稿窗口为 1280 CSS px、导出图按 1.125 倍呈现；桌面端默认 1440 宽时保持
// sidebar/settings 约 23.5%/25% 的视觉占比，避免原 300/320 在实机上显得过窄。
private let READER_SIDEBAR_WIDTH: Float32 = 338.0
private let READER_SETTINGS_WIDTH: Float32 = 360.0
// 对齐 frontend ReaderSidebar：列表项 p-2 + 40px 缩略图（约 56px），文件树项 h-7（28px）。
private let READER_SIDEBAR_LIST_ROW_H: Float32 = 56.0
private let READER_SIDEBAR_TREE_ROW_H: Float32 = 28.0
private let READER_THUMB_W: Float32 = 99.0
private let READER_THUMB_H: Float32 = 132.0
private let READER_THUMB_ROW_H: Float32 = 140.0

// ── #settings 控件精确几何/色值（原型 275-295 行 CSS；cui 标准 Switch/SegmentedControl
// 规格与设计稿不符，故自绘）──
// .switch：38×22、圆角 999、off 底 15% 白（亮色 18% 黑）、on 底 accent、
// 滑块 16×16 白、top 3、x 3→19（中心 11→27）。
private let SWITCH_W: Float32 = 38.0
private let SWITCH_H: Float32 = 22.0
private let SWITCH_KNOB_R: Float32 = 8.0
private let SWITCH_KNOB_OFF_CX: Float32 = 3.0 + SWITCH_KNOB_R
private let SWITCH_KNOB_ON_CX: Float32 = 19.0 + SWITCH_KNOB_R
// .seg：整条圆角 10、内边距 3、钮间隙 2、底 7% 白（亮色 6% 黑）；钮圆角 8、
// padding 7 0、字号 12、选中底 accent-soft/字 accent。
private let SEG_RADIUS: Float32 = 10.0
private let SEG_PAD: Float32 = 3.0
private let SEG_GAP: Float32 = 2.0
private let SEG_BTN_RADIUS: Float32 = 8.0
private let SEG_BTN_VPAD: Float32 = 7.0
private let SEG_PS: Float32 = 12.0

// 轨道/底槽的透明白黑（主题分支；palette.cj 无对应 token，属原型 CSS 直接换算）。
private func segTrackColor(light: Bool): Color {
    if (light) {
        Color.rgba(0, 0, 0, 15)
    } else {
        Color.rgba(255, 255, 255, 18)
    }
}

private func switchOffColor(light: Bool): Color {
    if (light) {
        Color.rgba(0, 0, 0, 46)
    } else {
        Color.rgba(255, 255, 255, 38)
    }
}

private func readerModeIndex(m: ReadingMode): Int64 {
    match (m) {
        case ReadingMode.SingleLtr => 0
        case ReadingMode.SingleRtl => 1
        case ReadingMode.SingleTtb => 2
        case ReadingMode.Webtoon => 3
    }
}

private func readerModeAt(i: Int64): ReadingMode {
    match (i) {
        case 0 => ReadingMode.SingleLtr
        case 1 => ReadingMode.SingleRtl
        case 2 => ReadingMode.SingleTtb
        case _ => ReadingMode.Webtoon
    }
}

// ── 自绘开关（原型 .switch）──
// 真值直读 ReaderModel/AppModel State（视图经 readerVersion 订阅，外部变更即时同步，
// 不驻留 rememberState 镜像）；只有滑块弹簧按 key 驻留（200ms 量级的过渡，
// stiffness 300/damping 30 比 Drawer 的 260/26 略快，贴原型 transition .2s）。
private class ReaderSwitch <: Widget {
    private let light: Bool
    private let onToggle: () -> Unit
    private let spring: Spring
    private let hoverId: String
    private var on: Bool
    private var frame = Rect.zero()

    public init(key: String, light: Bool, on: Bool, onToggle: () -> Unit) {
        this.light = light
        this.on = on
        this.onToggle = onToggle
        this.hoverId = "readerswitch:${key}"
        // 弹簧初值取当前态（静态首帧即停稳，快照稳定，同 cui Switch 惯例）。
        this.spring = rememberState<Spring>("readerswitch:${key}:knob", {
            => Spring(if (on) {
                1.0
            } else {
                0.0
            }, stiffness: 300.0, damping: 30.0)
        }).value
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(SWITCH_W, SWITCH_H)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let t = spring.animate(ctx, target: if (on) {
            1.0
        } else {
            0.0
        })
        ctx.renderer.fillRoundedRect(frame, SWITCH_H / 2.0, switchOffColor(light).lerp(ctx.theme.accent, t))
        let kx = frame.x + SWITCH_KNOB_OFF_CX + (SWITCH_KNOB_ON_CX - SWITCH_KNOB_OFF_CX) * t
        ctx.renderer.fillCircle(kx, frame.centerY(), SWITCH_KNOB_R, Color.rgb(255, 255, 255))
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    ctx.claimHover(hoverId, CursorShape.Interactive)
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    onToggle()
                    return true
                }
            case _ => ()
        }
        false
    }
}

// ── 自绘分段选择器（原型 .seg 四模式钮）──
// 选中胶囊在段索引空间滑动（Spring 260/26 与全局一致；设计稿无动画，只加这一个
// 小过渡，文字色不做交叉淡变——两种金色文字色互淡会闪过脏色）。当前段直读
// model.reader.mode（顶栏模式钮等外部变更经 readerVersion 重建即时同步）。
private class ReaderModeSeg <: Widget {
    private let model: AppModel
    private let spring: Spring
    private var frame = Rect.zero()
    private var segW: Float32 = 0.0

    public init(model: AppModel) {
        this.model = model
        this.spring = rememberState<Spring>("readerpanel:mode:pill",
            {=> Spring(Float32(readerModeIndex(model.reader.mode)), stiffness: 260.0, damping: 26.0)}).value
        emit(this)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        Size(available.w, ctx.renderer.textHeight(pointSize: SEG_PS) + SEG_BTN_VPAD * 2.0 + SEG_PAD * 2.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
        segW = (rect.w - SEG_PAD * 2.0 - SEG_GAP * 3.0) / 4.0
    }

    public func draw(ctx: UiContext): Unit {
        let labels = ["左到右", "右到左", "纵向", "条漫"]
        let current = readerModeIndex(model.reader.mode)
        ctx.renderer.fillRoundedRect(frame, SEG_RADIUS, segTrackColor(model.isLight()))
        let pos = spring.animate(ctx, target: Float32(current))
        let pill = Rect(frame.x + SEG_PAD + pos * (segW + SEG_GAP), frame.y + SEG_PAD, segW, frame.h - SEG_PAD * 2.0)
        ctx.renderer.fillRoundedRect(pill, SEG_BTN_RADIUS, ctx.theme.accentSoft)
        for (i in 0..4) {
            let r = Rect(frame.x + SEG_PAD + Float32(i) * (segW + SEG_GAP), frame.y + SEG_PAD, segW,
                frame.h - SEG_PAD * 2.0)
            let color = if (Int64(i) == current) {
                ctx.theme.accent
            } else {
                ctx.theme.mutedText
            }
            ctx.renderer.textCenter(labels[Int64(i)], r, color, pointSize: SEG_PS)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    ctx.claimHover("readerpanel:mode", CursorShape.Interactive)
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (frame.contains(x, y) && segW > 0.0) {
                    var i = Int64((x - frame.x - SEG_PAD) / (segW + SEG_GAP))
                    i = max(0, min(3, i))
                    model.setReadingMode(readerModeAt(i))
                    return true
                }
            case _ => ()
        }
        false
    }
}

// 小节标题（原型 .set-sec：11px dim、letter-spacing .1em、margin 18/8；
// cui 无字距原语，中文小节字少，字距省略）。
private func panelSection(text: String): Unit {
    VStack {
        Label(text).fontSize(11.fp).muted()
    }.crossAxisAlignment(CrossAxisAlignment.Start).padding(0.0, 18.0, 0.0, 8.0)
}

// 开关行（原型 .set-row：13px、padding 9px 2px、label flex:1 居左、开关居右）。
// 真值直读模型（见 ReaderSwitch 注释），onToggle 走 AppModel 的 toggle 入口
//（持久化 + bump readerVersion 已在模型内完成）。
private func panelSwitchRow(model: AppModel, key: String, label: String, on: Bool, onToggle: () -> Unit): Unit {
    HStack {
        Label(label).fontSize(13.fp).flex()
        ReaderSwitch(key, model.isLight(), on, onToggle)
    }.crossAxisAlignment(CrossAxisAlignment.Center).padding(2.0, 9.0)
}

// 自动播放间隔行（开关打开时露出，frontend 同布局）：Slider 1..10 step 1 + 「N秒」。
// Slider 绑镜像 State：模型侧写入会同步镜像，故镜像 ≠ 模型值即用户拖动，
// 构建期提交 setReaderAutoPlayInterval（模型内钳制/持久化/重置计时）。
private func autoPlayIntervalRow(model: AppModel): Unit {
    let dragged = Int64(model.autoPlayIntervalSlider.value)
    if (dragged != model.reader.autoPlayIntervalSec) {
        model.setReaderAutoPlayInterval(dragged)
    }
    HStack {
        Slider(model.autoPlayIntervalSlider, key: "reader:autoPlayInterval", lower: 1.0, upper: 10.0, step: 1.0).flex()
        Label("${model.reader.autoPlayIntervalSec}秒").fontSize(12.fp).muted().padding(8.0, 0.0, 0.0, 0.0)
    }.crossAxisAlignment(CrossAxisAlignment.Center).padding(2.0, 0.0, 10.0, 9.0)
}

// ── 阅读设置抽屉（原型 #settings）──
public func readerSettingsDrawer(model: AppModel): Unit {
    Drawer(model.readerSettingsOpen, edge: DrawerEdge.Right, width: READER_SETTINGS_WIDTH,
        onDismiss: {=> model.closeReaderPanels()}) {
        readerSettingsBody(model)
    }
}

private func readerSettingsBody(model: AppModel): Unit {
    // 副标题：档案标题 · N 页（档案名取法同 reader_bar：元数据未到货/非当前档案时不显示）。
    let archiveTitle = match (model.meta.value) {
        case Some(m) =>
            if (m.arcid == model.readerArcid) {
                m.title
            } else {
                ""
            }
        case None => ""
    }
    // 排版对齐原型：面板 padding 18；h3 14 底距 4；sub 12 dim 底距 16；
    // 之后各节由 panelSection 自带 18/8 外边距。
    VStack {
        Label("阅读设置").fontSize(14.fp).padding(0.0, 0.0, 0.0, 4.0)
        ReaderSettingsSubtitle(archiveTitle, model.reader.pageCount).padding(0.0, 0.0, 0.0, 16.0)
        panelSection("阅读模式")
        ReaderModeSeg(model)
        panelSection("页面布局")
        panelSwitchRow(model, "reader.doublePage", "双页模式", model.reader.doublePage) {
            => model.toggleReaderDoublePage()
        }
        panelSwitchRow(model, "reader.splitCover", "拆分封面", model.reader.splitCover) {
            => model.toggleReaderSplitCover()
        }
        panelSwitchRow(model, "reader.longPage", "长图滚动", model.reader.longPage) {
            => model.toggleReaderLongPage()
        }
        panelSection("行为")
        panelSwitchRow(model, "reader.tapTurnPage", "点击翻页", model.reader.tapTurnPage) {
            => model.toggleReaderTapTurnPage()
        }
        // 自动播放（frontend ReaderSettingsSheet:287-295）：开关打开时行下露出间隔
        // 滑条（1..10s step 1）与秒数标签；间隔变更即生效（下次计时重置，模型侧处理）。
        panelSwitchRow(model, "reader.autoPlay", "自动播放", model.reader.autoPlay) {
            => model.toggleReaderAutoPlay()
        }
        if (model.reader.autoPlay) {
            autoPlayIntervalRow(model)
        }
        panelSwitchRow(model, "reader.doubleTapZoom", "双击缩放", model.reader.doubleTapZoom) {
            => model.toggleReaderDoubleTapZoom()
        }
        panelSwitchRow(model, "reader.autoHide", "工具栏自动隐藏", model.reader.autoHide) {
            => model.toggleReaderAutoHide()
        }
        panelSwitchRow(model, "reader.seamlessNext", "无缝续读下一档案", model.reader.seamlessNext) {
            => model.toggleReaderSeamlessNext()
        }
        panelSection("调试")
        panelSwitchRow(model, "reader.showInfo", "媒体信息浮层", model.readerShowInfo.value) {
            => model.toggleReaderShowInfo()
        }
    }.spacing(0.0).crossAxisAlignment(CrossAxisAlignment.Start).padding(18.0)
}

// ── 页面导航抽屉（原型 #sidebar）：缩略图 / 列表 / 文件树三态。──
public func readerSidebarDrawer(model: AppModel): Unit {
    Drawer(model.readerSidebarOpen, edge: DrawerEdge.Left, width: READER_SIDEBAR_WIDTH,
        onDismiss: {=> model.closeReaderPanels()}) {
        readerSidebarBody(model)
    }
}

// 页列表行描述：segment 分组标题（档案名）或真实页（pageList 0 基索引）。
// 虚拟结束页不进列表（frontend 侧边栏也只有真实页）。
class SidebarRow {
    var isHeader = false
    var realIdx: Int64 = 0
    var title = ""
    var depth: Int64 = 0
}

private func sidebarRows(model: AppModel): ArrayList<SidebarRow> {
    let rows = ArrayList<SidebarRow>()
    let segs = model.reader.segmentList
    let multi = segs.size > 1
    for (seg in segs) {
        // 单 segment（未拼接）时不加分组标题，保持旧列表形态。
        if (multi) {
            let h = SidebarRow()
            h.isHeader = true
            h.title = if (seg.title.size > 0) {
                seg.title
            } else {
                seg.arcid
            }
            rows.add(h)
        }
        for (l in 0..seg.count) {
            let r = SidebarRow()
            r.realIdx = seg.start + l
            rows.add(r)
        }
    }
    rows
}

// 按 frontend ReaderSidebar 的 getPagePathSegments 语义，从 sourcePath 建真实目录层级。
// API 页顺序仍是阅读顺序；目录只在首次出现时插入，文件行保留原始 page index。
private func sidebarTreeRows(model: AppModel): ArrayList<SidebarRow> {
    let rows = ArrayList<SidebarRow>()
    let seenFolders = HashSet<String>()
    for (i in 0..model.reader.pageCount) {
        match (model.reader.pageAt(i)) {
            case Some(p) =>
                let normalized = p.sourcePath.replace("\\", "/").trimAscii()
                let parts = normalized.split("/")
                var folderPath = ""
                var depth: Int64 = 0
                let folderCount = max(0, parts.size - 1)
                for (j in 0..folderCount) {
                    let name = parts[j].trimAscii()
                    if (name.size == 0) {
                        continue
                    }
                    folderPath = if (folderPath.size > 0) {
                        "${folderPath}/${name}"
                    } else {
                        name
                    }
                    if (!seenFolders.contains(folderPath)) {
                        seenFolders.add(folderPath)
                        let folder = SidebarRow()
                        folder.isHeader = true
                        folder.title = name
                        folder.depth = depth
                        rows.add(folder)
                    }
                    depth++
                }
                let file = SidebarRow()
                file.realIdx = i
                file.depth = depth
                rows.add(file)
            case None => ()
        }
    }
    rows
}

private func readerSidebarBody(model: AppModel): Unit {
    let tab = rememberState<Int64>("reader:sidebar:tab", {=> 0})
    VStack {
        ReaderSidebarTabs(tab)
        if (tab.value == 0) {
            readerThumbnailPane(model)
        } else if (tab.value == 1) {
            readerPageList(model, sidebarRows(model), false)
        } else {
            readerPageList(model, sidebarTreeRows(model), true)
        }
    }.spacing(0.0).crossAxisAlignment(CrossAxisAlignment.Start)
}

private class ReaderSidebarTabs <: Widget {
    private let selected: State<Int64>
    private var frame = Rect.zero()

    public init(selected: State<Int64>) {
        this.selected = selected
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, 52.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let labels = ["缩略图", "列表", "文件树"]
        let inner = Rect(frame.x + 10.0, frame.y + 10.0, frame.w - 20.0, 34.0)
        let gap: Float32 = 2.0
        let w = (inner.w - gap * 2.0) / 3.0
        for (i in 0..3) {
            let r = Rect(inner.x + Float32(i) * (w + gap), inner.y, w, inner.h)
            if (selected.value == Int64(i)) {
                ctx.renderer.fillRoundedRect(r, 9.0, ctx.theme.accentSoft)
            } else if (ctx.isHovered("reader:sidebar:tab:${i}")) {
                ctx.renderer.fillRoundedRect(r, 9.0, ctx.theme.overlayHover)
            }
            ctx.renderer.textCenter(labels[Int64(i)], r, if (selected.value == Int64(i)) {
                ctx.theme.accent
            } else {
                ctx.theme.mutedText
            }, pointSize: 12.5)
        }
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        let inner = Rect(frame.x + 10.0, frame.y + 10.0, frame.w - 20.0, 34.0)
        let gap: Float32 = 2.0
        let w = (inner.w - gap * 2.0) / 3.0
        match (event) {
            case UiEvent.MouseMove(x, y) => for (i in 0..3) {
                let r = Rect(inner.x + Float32(i) * (w + gap), inner.y, w, inner.h)
                if (r.contains(x, y)) {
                    ctx.claimHover("reader:sidebar:tab:${i}", CursorShape.Interactive)
                }
            }
            case UiEvent.MouseDown(MouseButton.Left, x, y) => for (i in 0..3) {
                let r = Rect(inner.x + Float32(i) * (w + gap), inner.y, w, inner.h)
                if (r.contains(x, y)) {
                    selected.value = Int64(i)
                    return true
                }
            }
            case _ => ()
        }
        false
    }
}

private func readerThumbnailPane(model: AppModel): Unit {
    let count = model.reader.pageCount
    let rowCount = (count + 2) / 3
    LazyList(rowCount, {_ => READER_THUMB_ROW_H}, spacing: 8.0, id: "reader:sidebar:thumbs",
        key: {i => "thumb-row:${i}"}) {
        row => HStack {
            for (column in 0..3) {
                let page = row * 3 + Int64(column)
                if (page < count) {
                    ReaderPageThumb(model, page)
                } else {
                    VStack {}.width(READER_THUMB_W).height(READER_THUMB_H)
                }
            }
        }.spacing(8.0)
    }.flex().padding(12.0, 0.0, 12.0, 12.0)
}

private func readerPageList(model: AppModel, rows: ArrayList<SidebarRow>, tree: Bool): Unit {
    VStack {
        LazyList(
            Int64(rows.size),
            {
                i => if (rows[i].isHeader || tree) {
                    READER_SIDEBAR_TREE_ROW_H
                } else {
                    READER_SIDEBAR_LIST_ROW_H
                }
            },
            spacing: if (tree) {
                2.0
            } else {
                4.0
            },
            id: if (tree) {
                "reader:sidebar:tree"
            } else {
                "reader:sidebar:list"
            },
            key: {
                i =>
                    let row = rows[i]
                    if (row.isHeader) {
                        "header:${row.title}"
                    } else {
                        "page:${row.realIdx}"
                    }
            }
        ) {
            i =>
                let row = rows[i]
                if (row.isHeader) {
                    let _ = ReaderSegmentHeader(row.title, depth: row.depth)
                } else {
                    let _ = ReaderPageRow(model, row.realIdx, tree: tree, depth: row.depth)
                }
        }.flex()
    }.spacing(2.0).flex().padding(12.0, 0.0, 12.0, 12.0)
}

private class ReaderPageThumb <: Widget {
    private let model: AppModel
    private let index: Int64
    private let key: String
    private let hoverId: String
    private var frame = Rect.zero()

    public init(model: AppModel, index: Int64) {
        this.model = model
        this.index = index
        hoverId = "reader:sidebar:thumb:${index}"
        var imageKey = ""
        match (model.reader.pageAt(index)) {
            case Some(p) =>
                if (p.pageType == "image" || p.pageType == "") {
                    let arcid = model.reader.arcidOfReal(index)
                    imageKey = readerPageKey(arcid, p.id)
                    if (model.imageState(imageKey).value == "") {
                        model.requestImage(imageKey, readerPageUrl(arcid, p.id))
                    }
                }
            case None => ()
        }
        key = imageKey
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(READER_THUMB_W, READER_THUMB_H)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        ctx.renderer.fillRoundedRect(frame, 8.0, ctx.theme.panel)
        match (pixelTexture(ctx.renderer, key)) {
            case Some(tex) =>
                let scale = min(frame.w / Float32(tex.width), frame.h / Float32(tex.height))
                let w = Float32(tex.width) * scale
                let h = Float32(tex.height) * scale
                ctx.renderer.pushClip(frame)
                ctx.renderer.texture(tex, Rect(frame.centerX() - w / 2.0, frame.centerY() - h / 2.0, w, h))
                ctx.renderer.popClip()
            case None => ctx
                .renderer
                .textCenter("${model.reader.displayPageOfReal(index)}", frame, ctx.theme.mutedText, pointSize: 11.0)
        }
        let current = match (model.reader.currentReal) {
            case Some(i) => i == index
            case None => false
        }
        if (current) {
            ctx.renderer.strokeRoundedRect(frame.inset(1.0), 7.0, Pen(width: 2.0, color: ctx.theme.accent))
        } else {
            ctx
                .renderer
                .strokeRoundedRect(frame.inset(0.5), 7.5, Pen(width: 1.0, color: if (ctx.isHovered(hoverId)) {
                    ctx.theme.text
                } else {
                    ctx.theme.panelEdge
                }))
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
                    model.gotoPage(model.reader.displayPageOfReal(index))
                    model.closeReaderPanels()
                    return true
                }
            case _ => ()
        }
        false
    }
}

// segment 分组标题行（原型 .sb-tree .row.dir：主文字色、略小字号、上间距）。
private class ReaderSegmentHeader <: Widget {
    private let title: String
    private let depth: Int64
    private var frame = Rect.zero()

    public init(title: String, depth!: Int64 = 0) {
        this.title = title
        this.depth = depth
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, READER_SIDEBAR_TREE_ROW_H)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let ps: Float32 = 12.0
        let th = ctx.renderer.textHeight(pointSize: ps)
        let x = frame.x + 6.0 + Float32(depth) * 14.0
        let fitted = sidebarEllipsize(ctx, "▾  ${title}", frame.right() - 8.0 - x, ps)
        ctx.renderer.text(fitted, x, frame.centerY() - th / 2.0, ctx.theme.accent, pointSize: ps)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 页面行：列表态对齐 frontend ReaderSidebar 的 56px 卡片（缩略图/圆形页码、标题、
// 文件名副标题、右侧媒体类型）；文件树态使用 28px 紧凑文件行。
private class ReaderPageRow <: Widget {
    private let model: AppModel
    private let index: Int64 // 0 基页索引
    private let tree: Bool
    private let depth: Int64
    private let hoverId: String
    private let thumbKey: String
    private var frame = Rect.zero()

    public init(model: AppModel, index: Int64, tree!: Bool = false, depth!: Int64 = 0) {
        this.model = model
        this.index = index
        this.tree = tree
        this.depth = depth
        this.hoverId = "reader:sidebar:row:${index}"
        var tk = ""
        if (!tree) {
            match (model.reader.pageAt(index)) {
                case Some(p) =>
                    if (p.thumbAssetId > 0) {
                        tk = "asset:${p.thumbAssetId}"
                        if (model.imageState(tk).value == "") {
                            model.requestImage(tk, "/api/assets/${p.thumbAssetId}")
                        }
                    }
                case None => ()
            }
        }
        thumbKey = tk
        emit(this)
    }

    public func measure(_: UiContext, available: Size): Size {
        Size(available.w, if (tree) {
            READER_SIDEBAR_TREE_ROW_H
        } else {
            READER_SIDEBAR_LIST_ROW_H
        })
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    // 页类型字标：emoji 🎬🎵📄 在随仓字体（NotoSansCJK/msyh）无字形，用单汉字代替。
    private func typeTag(pageType: String): String {
        if (pageType == "video") {
            "视"
        } else if (pageType == "audio") {
            "音"
        } else if (pageType == "html") {
            "文"
        } else {
            "" // image/未知：图片是常态，不占位
        }
    }

    public func draw(ctx: UiContext): Unit {
        let current = match (model.reader.currentReal) {
            case Some(r0) => index == r0
            case None => false
        }
        let hovered = ctx.isHovered(hoverId)
        if (current) {
            ctx.renderer.fillRoundedRect(frame, 8.0, ctx.theme.accentSoft)
        } else if (hovered) {
            ctx.renderer.fillRoundedRect(frame, 8.0, ctx.theme.overlayHover)
        }
        let color = if (current) {
            ctx.theme.accent
        } else if (hovered) {
            ctx.theme.text
        } else {
            ctx.theme.mutedText
        }
        if (!tree) {
            drawListContent(ctx, color)
            return
        }
        drawTreeFileContent(ctx, color)
    }

    private func drawListContent(ctx: UiContext, color: Color): Unit {
        let media = Rect(frame.x + 8.0, frame.y + 8.0, 56.0, 40.0)
        match (pixelTexture(ctx.renderer, thumbKey)) {
            case Some(tex) =>
                ctx.renderer.pushClip(media)
                let scale = max(media.w / Float32(tex.width), media.h / Float32(tex.height))
                let w = Float32(tex.width) * scale
                let h = Float32(tex.height) * scale
                ctx.renderer.texture(tex, Rect(media.centerX() - w / 2.0, media.centerY() - h / 2.0, w, h))
                ctx.renderer.popClip()
                ctx.renderer.strokeRoundedRect(media, 6.0, Pen(width: 1.0, color: ctx.theme.panelEdge))
            case None =>
                let circle = Rect(media.x + 14.0, media.y + 6.0, 28.0, 28.0)
                ctx.renderer.fillRoundedRect(circle, 14.0, ctx.theme.accentSoft)
                ctx.renderer.textCenter("${index + 1}", circle, ctx.theme.accent, pointSize: 11.0)
        }
        let textX = media.right() + 8.0
        let iconSlot: Float32 = 22.0
        let availableW = frame.right() - 8.0 - iconSlot - textX
        let maxW: Float32 = if (availableW > 0.0) {
            availableW
        } else {
            0.0
        }
        var title = "第 ${index + 1} 页"
        var subtitle = ""
        var pageType = ""
        match (model.reader.pageAt(index)) {
            case Some(p) =>
                if (p.title.size > 0) {
                    title = p.title
                }
                subtitle = fileNameOf(p.sourcePath)
                if (subtitle == title) {
                    subtitle = ""
                }
                pageType = p.pageType
            case None => ()
        }
        ctx.renderer.text(sidebarEllipsize(ctx, title, maxW, 12.5), textX, frame.y + 11.0, color, pointSize: 12.5)
        if (subtitle.size > 0) {
            ctx
                .renderer
                .text(sidebarEllipsize(ctx, subtitle, maxW, 10.5), textX, frame.y + 32.0, ctx.theme.mutedText,
                    pointSize: 10.5)
        }
        let tag = typeTag(pageType)
        if (tag.size > 0) {
            ctx
                .renderer
                .textCenter(tag, Rect(frame.right() - 28.0, frame.y, 20.0, frame.h), ctx.theme.mutedText,
                    pointSize: 11.0)
        }
    }

    private func drawTreeFileContent(ctx: UiContext, color: Color): Unit {
        let ps: Float32 = 12.0
        let th = ctx.renderer.textHeight(pointSize: ps)
        let ty = frame.centerY() - th / 2.0
        var x = frame.x + 6.0 + Float32(depth) * 14.0
        var name = ""
        var pageType = ""
        match (model.reader.pageAt(index)) {
            case Some(p) =>
                pageType = p.pageType
                name = fileNameOf(p.sourcePath)
            case None => ()
        }
        let tag = typeTag(pageType)
        ctx.renderer.text(if (tag.size > 0) {
            tag
        } else {
            "图"
        }, x, ty, ctx.theme.mutedText, pointSize: 10.5)
        x += 20.0
        let num = "${index + 1}"
        let numW = ctx.renderer.textWidth(num, pointSize: 10.0)
        let fitted = sidebarEllipsize(ctx, name, frame.right() - 12.0 - numW - 8.0 - x, ps)
        if (fitted.size > 0) {
            ctx.renderer.text(fitted, x, ty, color, pointSize: ps)
        }
        ctx
            .renderer
            .text(num, frame.right() - 8.0 - numW, frame.centerY() - ctx.renderer.textHeight(pointSize: 10.0) / 2.0,
                ctx.theme.mutedText, pointSize: 10.0)
    }

    public func handle(ctx: UiContext, event: UiEvent): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (frame.contains(x, y)) {
                    ctx.claimHover(hoverId, CursorShape.Interactive)
                }
            case UiEvent.MouseUp(MouseButton.Left, x, y) =>
                if (frame.contains(x, y)) {
                    // gotoPage 为 1 基显示页码（seamless 开 = segment 内页码）；
                    // 跳转后顺手关抽屉（原型行点击即导航）。
                    model.gotoPage(model.reader.displayPageOfReal(index))
                    model.closeReaderPanels()
                    return true
                }
            case _ => ()
        }
        false
    }
}

// 设置抽屉副标题（原型 #settings .sub：12px dim 单行）：「档案名 · N 页」。
// 页数后缀恒定保留，档案名按剩余宽度二分截断（Label.maxLines 整体截断会把
// 「· N 页」一起挤没）。截断复用本文件 sidebarEllipsize。
private class ReaderSettingsSubtitle <: Widget {
    private let title: String
    private let pageCount: Int64
    private var frame = Rect.zero()

    public init(title: String, pageCount: Int64) {
        this.title = title
        this.pageCount = pageCount
        emit(this)
    }

    public func measure(ctx: UiContext, available: Size): Size {
        Size(available.w, ctx.renderer.textHeight(pointSize: 12.0))
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let ps: Float32 = 12.0
        if (title.size == 0) {
            ctx.renderer.text("${pageCount} 页", frame.x, frame.y, ctx.theme.mutedText, pointSize: ps)
            return
        }
        let suffix = " · ${pageCount} 页"
        let suffixW = ctx.renderer.textWidth(suffix, pointSize: ps)
        let fitted = sidebarEllipsize(ctx, title, frame.w - suffixW, ps)
        ctx.renderer.text(fitted, frame.x, frame.y, ctx.theme.mutedText, pointSize: ps)
        let fittedW = ctx.renderer.textWidth(fitted, pointSize: ps)
        ctx.renderer.text(suffix, frame.x + fittedW, frame.y, ctx.theme.mutedText, pointSize: ps)
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 单行省略号截断（reader_bar 的 ellipsizeText 为文件私有，这里按同一思路自备二分前缀）。
private func sidebarEllipsize(ctx: UiContext, text: String, maxWidth: Float32, ps: Float32): String {
    if (text.size == 0 || maxWidth <= 0.0) {
        return ""
    }
    if (ctx.renderer.textWidth(text, pointSize: ps) <= maxWidth) {
        return text
    }
    if (ctx.renderer.textWidth("…", pointSize: ps) > maxWidth) {
        return ""
    }
    let runes = text.toRuneArray()
    var low: Int64 = 0
    var high = runes.size - 1
    while (low < high) {
        let mid = (low + high + 1) / 2
        if (ctx.renderer.textWidth(runesSliceToString(runes, 0, mid) + "…", pointSize: ps) <= maxWidth) {
            low = mid
        } else {
            high = mid - 1
        }
    }
    runesSliceToString(runes, 0, low) + "…"
}

private func fileNameOf(path: String): String {
    let normalized = path.replace("\\", "/").trimAscii()
    if (normalized.size == 0) {
        return ""
    }
    let parts = normalized.split("/")
    var i = parts.size - 1
    while (i >= 0) {
        let part = parts[i].trimAscii()
        if (part.size > 0) {
            return part
        }
        i--
    }
    normalized
}

private func runesSliceToString(runes: Array<Rune>, start: Int64, end: Int64): String {
    let builder = StringBuilder()
    var i = start
    while (i < end) {
        builder.append(runes[i])
        i += 1
    }
    builder.toString()
}
