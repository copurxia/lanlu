package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.SearchItem
import std.collection.ArrayList

private let SORT_FIELDS = ["title", "created_at", "updated_at", "lastread", "pagecount", "release_at"]
private let SORT_LABELS = ["标题", "创建时间", "更新时间", "最近阅读", "页数", "发布日期"]
private let ORDER_LABELS = ["升序", "降序"]

// 封面高度：宽随卡片（跨轴拉伸），高固定 210vp，LazyGrid 行高按此预算。
private let COVER_H = 210.vp

// 书库主页：品牌行 → 过滤行 → 封面网格（5 列 LazyGrid）→ 居中分页条。
public func libraryView(model: AppModel): Unit {
    VStack {
        brandBar(model)
        Divider()
        filterBar(model)
        if (model.loading.value && model.items.value.size == 0) {
            loadingState()
        } else if (model.items.value.size == 0) {
            emptyState(model)
        } else {
            grid(model)
        }
        Divider()
        pager(model)
    }
}

// 品牌行：左侧应用名 + muted 服务器地址，右侧搜索框（flex）+ 主色搜索 + 设置入口。
private func brandBar(model: AppModel): Unit {
    HStack {
        VStack {
            Label("兰鹿").fontSize(20.fp)
            Label(serverSubtitle(model)).fontSize(11.fp).muted().maxWidth(320.vp)
            // 品牌块在水平主轴上按内容收缩，把剩余宽度让给搜索框。
        }.spacing(0.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
        TextField(model.searchText, key: "search").flex()
        Button("搜索", {=>
            model.query.filter = model.searchText.value
            model.submitSearch(1)
        }).role(ButtonRole.Primary)
        // IconName 枚举无齿轮图标，按既定降级用文本按钮。
        Button("设置", {=> model.page.value = Page.Settings })
        // 容器默认 flexible:true，行高按内容收缩（hug 是 HStack 专有链式，
        // 须排在返回 Widget 的通用修饰器 padding 之前）。
    }.spacing(12.vp).hug().padding(16.vp, 12.vp)
}

// 品牌行副标题：已配置服务器时显示地址，否则显示“桌面客户端”。
private func serverSubtitle(model: AppModel): String {
    let url = model.settings.serverUrl
    if (url.size == 0) { return "桌面客户端" }
    url
}

// 过滤行：排序/方向/分类 + 三个过滤 Switch + 应用，右端 muted 结果计数；
// 整行铺 panel 底色与品牌行分组（sort/order/category 仍走“应用”提交）。
private func filterBar(model: AppModel): Unit {
    HStack {
        Dropdown(SORT_LABELS, model.sortIndex)
        Dropdown(ORDER_LABELS, model.orderIndex)
        Dropdown(categoryLabels(model), model.categoryIndex)
        Switch("仅收藏", model.favOnly)
        Switch("仅未读", model.newOnly)
        Switch("仅无标签", model.untaggedOnly)
        Button("应用", {=>
            model.query.sortby = SORT_FIELDS[model.sortIndex.value]
            model.query.order = if (model.orderIndex.value == 0) { "asc" } else { "desc" }
            model.query.categoryId = selectedCategoryId(model)
            model.submitSearch(1)
        })
        Spacer()
        Label("共 ${model.recordsTotal.value} 项").fontSize(12.fp).muted()
    }.spacing(10.vp).hug().padding(16.vp, 10.vp).background(Theme.dark().panel)
}

private func categoryLabels(model: AppModel): Array<String> {
    let labels = ArrayList<String>()
    labels.add("全部分类")
    for (c in model.categories.value) { labels.add(c.name) }
    labels.toArray()
}

private func selectedCategoryId(model: AppModel): String {
    let idx = model.categoryIndex.value
    // 重新登录（含换服务器）后分类列表会被整体替换、可能变短，而 categoryIndex 是
    // model 级记忆状态；越界时按“全部分类”返回，避免 categories.value[idx - 1] 索引越界崩溃。
    if (idx <= 0 || idx > model.categories.value.size) { return "" }
    model.categories.value[idx - 1].catid
}

// 加载态：在内容区居中放大留白呈现。
private func loadingState(): Unit {
    VStack {
        Label("正在加载书库…").fontSize(16.fp)
        Label("首次加载或网络较慢时需要稍作等待").fontSize(12.fp).muted()
    }.spacing(8.vp).mainAxisAlignment(MainAxisAlignment.Center).crossAxisAlignment(CrossAxisAlignment.Center)
}

// 空态：居中 + 引导文案 + 主色重试按钮。
private func emptyState(model: AppModel): Unit {
    VStack {
        Label("没有匹配的档案").fontSize(16.fp)
        Label("试试更换搜索词，或调整过滤条件后重新应用").fontSize(12.fp).muted()
        Button("重新加载", {=> model.submitSearch(1) }).role(ButtonRole.Primary)
    }.spacing(10.vp).mainAxisAlignment(MainAxisAlignment.Center).crossAxisAlignment(CrossAxisAlignment.Center)
}

private func grid(model: AppModel): Unit {
    // LazyGrid 的 data 形参是 Array<T>，State 里是 ArrayList，逐帧 toArray 一份。
    // 行高 336 按卡片内容预算（封面 210 + 标题两行 + meta + 细进度条 + 内边距）。
    LazyGrid(model.items.value.toArray(), 5, 336.0, spacing: 16.0, columnSpacing: 16.0,
        id: "library-grid") { item =>
        archiveCard(model, item)
    }.padding(16.vp)
}

// 档案卡片：圆角 panel 表面 + 整卡 ClickArea；封面宽随卡片，角标叠于封面上，
// 底部 meta 与细进度条经 Spacer 压到卡底，保证行内各卡底部对齐。
private func archiveCard(model: AppModel, item: SearchItem): Unit {
    ClickArea(onClick: {=> model.openDetail(item.arcid) }) {
        VStack {
            ZStack {
                if (item.coverAssetId > 0) {
                    remoteImage(model, "asset:${item.coverAssetId}", "/api/assets/${item.coverAssetId}",
                        152.vp, COVER_H)
                } else {
                    Panel { Label("无封面").muted().textAlign(TextAlign.Center) }.height(COVER_H)
                }
                // 角标行随 ZStack 拉伸铺满封面宽：左上 NEW、右上收藏星。
                HStack {
                    if (item.isnew) { newBadge() }
                    Spacer()
                    if (item.isfavorite) { favBadge() }
                }.crossAxisAlignment(CrossAxisAlignment.Start).padding(6.vp)
            }.alignment(Alignment.TopLeading)
            Label(item.title).maxLines(2).fontSize(14.fp)
            Spacer()
            VStack {
                Label(cardMeta(item)).fontSize(12.fp).muted()
                if (item.pagecount > 0 && item.progress > 0) {
                    MiniProgress(Float32(item.progress) / Float32(item.pagecount))
                }
                // meta 块 hug，把弹性余量只留给上方的 Spacer。
            }.spacing(4.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
        }.spacing(6.vp).padding(10.vp).background(Theme.dark().panel, 12.vp)
    }
}

// meta 行：有进度时 “N 页 · 已读 X%”，否则仅 “N 页”。
private func cardMeta(item: SearchItem): String {
    if (item.pagecount > 0 && item.progress > 0) {
        let pct = min(100, item.progress * 100 / item.pagecount)
        return "${item.pagecount} 页 · 已读 ${pct}%"
    }
    "${item.pagecount} 页"
}

// NEW 角标：accent 底圆角小标签（padding 须先于 background，底色才包含内边距）。
private func newBadge(): Unit {
    Label("NEW").fontSize(11.fp).foregroundColor(Theme.dark().accentText)
        .padding(6.vp, 1.vp).background(Theme.dark().accent, 4.vp)
}

// 收藏角标：accent 色星形 + 深色半透明底，压在封面上保证可读。
private func favBadge(): Unit {
    Label("★").fontSize(12.fp).foregroundColor(Theme.dark().accent)
        .padding(6.vp, 1.vp).background(Color.rgba(9, 13, 20, 150), 4.vp)
}

// 细进度条：框架 ProgressBar 高 28vp 且自带居中百分比文字，与卡片底部
// “细条 + muted 百分比文字”的设计重复，故按 ClickSensor 同款应用层 Widget
// 协议实现 4vp 细条；颜色取 ctx.theme，不硬编码主题。
class MiniProgress <: Widget {
    private let ratio: Float32
    private var frame = Rect.zero()

    public init(ratio: Float32) {
        this.ratio = min(1.0, max(0.0, ratio))
        emit(this)
    }

    // 宽度随卡片拉伸（acceptsStretch 默认 true），自然宽度只作下限参考。
    public func measure(_: UiContext, available: Size): Size {
        Size(min(available.w, 200.0), 4.0)
    }

    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        let t = ctx.theme
        ctx.renderer.fillRoundedRect(frame, 2.0, t.field)
        if (ratio > 0.0) {
            ctx.renderer.fillRoundedRect(Rect(frame.x, frame.y, frame.w * ratio, frame.h), 2.0, t.accent)
        }
    }

    public func handle(_: UiContext, _: UiEvent): Bool {
        false
    }
}

// 分页条：居中收敛（muted 页码信息 + 留白），翻页语义不变。
private func pager(model: AppModel): Unit {
    HStack {
        Button("‹ 上一页", {=>
            if (model.currentPage.value > 1) { model.submitSearch(model.currentPage.value - 1) }
        })
        Label("第 ${model.currentPage.value} / ${model.maxPage()} 页 · 共 ${model.recordsTotal.value} 项").muted()
        Button("下一页 ›", {=>
            if (model.currentPage.value < model.maxPage()) { model.submitSearch(model.currentPage.value + 1) }
        })
    }.spacing(12.vp).mainAxisAlignment(MainAxisAlignment.Center).hug().padding(10.vp)
}
