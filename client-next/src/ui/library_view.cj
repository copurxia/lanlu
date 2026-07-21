package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*

// 与 app 包 SEARCH_SORT_FIELDS 按下标一一对应（改动须两边同步）。
private let SORT_LABELS = ["标题", "创建时间", "更新时间", "最近阅读", "页数", "发布日期"]
private let ORDER_LABELS = ["升序", "降序"]
// 合集聚合开关（原型 home-tools 第二个下拉；消费为查询参数 groupby_tanks，
// 变更即按新规格重取，见 model.applyTankGroupChange）。
private let TANK_GROUP_LABELS = ["合集聚合： 开", "合集聚合： 关"]

// 浏览模式行规格（原型 §首页 .card{width:168px}：封面宽 168vp、3:4；卡片间距 14vp）；行高 = 封面 + 标题/meta 文本区。
private let BROWSE_COVER_W: Float32 = 168.0
private let BROWSE_COVER_H: Float32 = BROWSE_COVER_W * 4.0 / 3.0 // =224
private let CARD_TEXT_H: Float32 = 50.0 // 标题(13fp)+meta(11fp)+内部间距
// LazyRow 的横向滚动条画在卡片条底部带上，条高须额外留出间隙，否则压到 meta 行。
private let ROW_SCROLLBAR_CLEARANCE: Float32 = 12.0
private let BROWSE_STRIP_H: Float32 = BROWSE_COVER_H + CARD_TEXT_H + ROW_SCROLLBAR_CLEARANCE

// 搜索/过滤模式自适应网格（原型 #home-grid：列数 = clamp(floor(宽/196), 3, 10)）
private let GRID_PADDING: Float32 = 20.0
private let GRID_SPACING: Float32 = 16.0

// 书库主页（原型 home-detail-redesign.html「首页」视图）：左 224vp 侧栏（浏览过滤互斥 +
// 分类计数 + 设置）｜右边线｜主区（顶部工具条 + 双模式内容：浏览=横排行，搜索/过滤=密网格+分页）。
// 卡片/行组件在 widgets.cj（archiveCard/tankCard/cardRow/sectionHeader）。
public func libraryView(model: AppModel): Unit {
    // 根 HStack 默认 8vp 间距会在侧栏/边线/内容区之间留出死区，必须清零。
    HStack {
        sidebar(model)
        Divider(axis: Axis.Vertical)
        // SizeProbe 包住整个内容区：搜索网格（自适应列数）与工具条（窄宽适配）都读它。
        SizeProbe(width: model.contentWidth) {
            VStack {
                toolbar(model)
                // 工具条下不画分割线：原型 .home-tools 无底边线，主区唯一的横向分界是顶栏底线。
                if (model.isBrowseMode()) {
                    browseContent(model)
                } else {
                    searchContent(model)
                }
            }
        }
    }.spacing(0.0)
}

// ---- 左侧栏（原型 #home-side：224vp，无自带底色、与主区同为窗口 BG，仅右边线分隔）----
// 品牌块与「设置」项已上移顶栏（#topbar 的品牌区与 ⚙ 钮），侧栏只留浏览/分类两组。

private func sidebar(model: AppModel): Unit {
    let bg = if (model.isLight()) { LANLU_L_BG } else { LANLU_BG }
    VStack {
        // 「浏览」分组：互斥单选，点击即生效。
        // 计数只展示有真实数据源的项：后端对「全部/仅收藏/仅未读/仅无标签」均无独立
        // 计数接口（recordsTotal 是当前查询结果总数，不是档案库总量，语义不符），
        // 按「不留假数据」原则四项都不带计数；分类计数来自 CategoryItem.archiveCount。
        VStack {
            navGroupHeader("浏览")
            NavItem("全部档案", active: allFilterInactive(model)) {=> model.selectBrowseFilter(0) }
            NavItem("仅收藏", active: model.favOnly.value) {=> model.selectBrowseFilter(1) }
            NavItem("仅未读", active: model.newOnly.value) {=> model.selectBrowseFilter(2) }
            NavItem("无标签", active: model.untaggedOnly.value) {=> model.selectBrowseFilter(3) }
        }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().padding(10.vp, 8.vp)
        // 「分类」分组：占满侧栏剩余高度，列表内部滚动；计数来自 CategoryItem.archiveCount。
        // 组间不画分割线：原型侧栏只靠 .side-sec 小标题分组，无分隔线。
        VStack {
            navGroupHeader("分类")
            ScrollView(key: "sidebar-categories") {
                VStack {
                    ForEachIndexed(model.categories.value.toArray()) { i, c =>
                        NavItem(c.name, active: model.categoryIndex.value == i + 1,
                            count: "${c.archiveCount}") {=> model.selectCategory(i + 1) }
                    }
                    if (model.categories.value.size == 0) {
                        Label("暂无分类").fontSize(12.fp).muted().padding(12.vp, 0.vp)
                    }
                }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
            }
        }.spacing(6.vp).crossAxisAlignment(CrossAxisAlignment.Start).padding(10.vp, 8.vp)
        // 固定 224vp 宽且不参与主轴弹性分配（hug 是 VStack 专有链式，须在通用修饰器之前）
    }.hug().width(224.vp).background(bg)
}

private func navGroupHeader(text: String): Unit {
    Label(text).fontSize(11.fp).muted().padding(12.vp, 0.vp)
}

// 「全部档案」的激活态：无任何侧栏过滤且未选分类（搜索词不影响导航激活态）。
private func allFilterInactive(model: AppModel): Bool {
    !model.favOnly.value && !model.newOnly.value && !model.untaggedOnly.value &&
        model.categoryIndex.value == 0
}

// ---- 工具条（原型 .home-tools：排序/方向/合集聚合下拉 + 右侧计数 + 纯图标刷新钮）----
// 搜索框已上移顶栏（#topbar .search-shell）；工具条内按钮类元素一律无边框 icon-btn 风格。

private func toolbar(model: AppModel): Unit {
    // 窄宽适配（<1100vp，含 960 最小窗宽）：结果计数让位给下拉组（计数是纯信息，
    // 挤压到不可用的是交互控件）；首帧宽度未知按宽屏起画。
    let narrow = model.contentWidth.value > 0.0 && model.contentWidth.value < 1100.0
    HStack {
        // 排序/方向变更即时生效：project 绑定的 set 里写回索引并收束查询；
        // 选中未变（重复点同一项）时不发请求。下拉限宽（默认 190 太占工具条），
        // 标签最长 4 字（更新时间）在 150/110vp 下完整可见。
        Dropdown(SORT_LABELS, model.sortIndex.project(get: {v => v}, set: {_, v =>
            if (model.sortIndex.value != v) {
                model.sortIndex.value = v
                model.applyFilters()
            }
            return v
        })).width(150.vp)
        Dropdown(ORDER_LABELS, model.orderIndex.project(get: {v => v}, set: {_, v =>
            if (model.orderIndex.value != v) {
                model.orderIndex.value = v
                model.applyFilters()
            }
            return v
        })).width(110.vp)
        // 合集聚合开关：接入查询（groupby_tanks）；变更即按新规格重取（见 model）。
        Dropdown(TANK_GROUP_LABELS, model.tankGroupIndex.project(get: {v => v}, set: {_, v =>
            if (model.tankGroupIndex.value != v) {
                model.tankGroupIndex.value = v
                model.applyTankGroupChange()
            }
            return v
        })).width(140.vp)
        Spacer()
        // 原型 .result-cnt：右对齐 muted 12fp；浏览模式无查询总数，只在搜索/过滤模式展示。
        if (!model.isBrowseMode() && !narrow) {
            Label("共 ${model.recordsTotal.value} 项").fontSize(12.fp).muted()
        }
        // 原型 .home-tools 的 ⟳：纯图标无边框钮。
        GhostIconButton(GhostGlyph.Named(IconName.Refresh), "toolbar:refresh") {=>
            model.refreshLibrary()
        }
    }.spacing(10.vp).hug().padding(16.vp, 10.vp)
}

// ---- 浏览模式（横排行：继续阅读 / 随机推荐 / 新到档案 / 分类行）----

private func browseContent(model: AppModel): Unit {
    ScrollView(key: "browse-rows") {
        VStack {
            for (row in model.browseRows.value) {
                // 加载完成且无内容的行直接隐藏（空分类不制造噪音）。
                if (row.loading || row.failed || row.items.size > 0) {
                    browseRowSection(model, row)
                }
            }
        }.spacing(28.vp).hug().padding(20.vp)
    }
}

private func browseRowSection(model: AppModel, row: BrowseRow): Unit {
    VStack {
        sectionHeader(row.title) {=> rowTrailing(model, row) }
        if (row.loading) {
            rowStripPlaceholder("加载中…")
        } else if (row.failed) {
            ClickArea(onClick: {=> model.retryRow(row.key) }) {
                rowStripPlaceholder("加载失败，点击重试")
            }
        } else {
            cardRow(model, row.key, row.items.toArray(), BROWSE_COVER_W, BROWSE_STRIP_H)
        }
    }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
}

// 行头右侧操作：随机行「换一批」；继续阅读/分类行「查看更多 ›」。
private func rowTrailing(model: AppModel, row: BrowseRow): Unit {
    if (row.key == "random") {
        reshuffleLink(model) {=> model.refreshRandomRow() }
    } else if (row.key == "resume") {
        moreLink(model, "查看更多 ›") {=> model.viewAllRow(row.key) }
    } else {
        moreLink(model, "查看更多 ›") {=> model.openCategory(row.catid) }
    }
}

// 「换一批」：无边框 icon+文字链接（原型 .row-head .more：muted 12fp，hover accent；
// 与「查看更多 ›」同为行头轻量操作，不用带边框的 IconButton）。
private func reshuffleLink(model: AppModel, onClick: () -> Unit): Unit {
    let muted = if (model.isLight()) { LANLU_L_MUTED } else { LANLU_MUTED }
    ClickArea(onClick: onClick) {
        HStack {
            Icon(IconName.Refresh, size: 13.vp, color: muted)
            Label("换一批").fontSize(12.fp).foregroundColor(muted)
        }.spacing(5.vp).crossAxisAlignment(CrossAxisAlignment.Center)
    }
}

private func moreLink(model: AppModel, text: String, onClick: () -> Unit): Unit {
    // 原型 .row-head .more：常态 muted、hover 才 accent（构建期无 hover 上下文，取常态色）。
    let muted = if (model.isLight()) { LANLU_L_MUTED } else { LANLU_MUTED }
    ClickArea(onClick: onClick) {
        Label(text).fontSize(12.fp).foregroundColor(muted)
    }
}

private func rowStripPlaceholder(text: String): Unit {
    // fillWidth 撑满整行宽：行容器 hug 时其宽度取最宽子项（行头），不设 fillWidth
    // 占位条会被收束到行头宽度而左漂；文案在整行宽、284vp 高条内居中。
    VStack {
        Label(text).fontSize(12.fp).muted()
    }.mainAxisAlignment(MainAxisAlignment.Center).crossAxisAlignment(CrossAxisAlignment.Center)
        .fillWidth().height(BROWSE_STRIP_H)
}

// ---- 搜索/过滤模式 ----

private func searchContent(model: AppModel): Unit {
    // SizeProbe 已上移到根布局包住整个内容区（工具条也要读宽度），这里直接用。
    VStack {
        if (model.loading.value && model.items.value.size == 0) {
            loadingState()
        } else if (model.items.value.size == 0) {
            emptyState(model)
        } else {
            searchGrid(model)
        }
        // 分页条上不画分割线（原型 .pager 无顶边线）。
        pager(model)
    }
}

private func searchGrid(model: AppModel): Unit {
    let w = model.contentWidth.value
    let cols = gridColumns(w)
    let cellW = gridCellWidth(w, cols)
    let coverH = cellW * 4.0 / 3.0
    // 行高 = 封面 + 标题/meta 文本区；LazyGrid 行高固定，按测得宽度逐帧现算。
    LazyGrid(model.items.value.toArray(), cols, coverH + CARD_TEXT_H, spacing: GRID_SPACING,
        columnSpacing: GRID_SPACING, id: "search-grid") { item =>
        searchItemCard(model, item, cellW)
    // Float32 走 padding 的 vp 重载（.vp 后缀仅 Int64/Float64 有）。
    }.padding(GRID_PADDING)
}

// 列数 = clamp(floor(宽/196), 3, 10)；宽未知（首帧 State 初值 0）按 5 列保守起画，
// SizeProbe 一帧内写入真实宽度后收敛。
private func gridColumns(w: Float32): Int64 {
    if (w <= 0.0) { return 5 }
    var n = Int64(w / 196.0)
    if (n < 3) { n = 3 }
    if (n > 10) { n = 10 }
    n
}

// 卡片宽随列数：内容宽减去两侧 padding 与列间距后均分。
private func gridCellWidth(w: Float32, cols: Int64): Float32 {
    if (w <= 0.0) { return BROWSE_COVER_W }
    (w - 2.0 * GRID_PADDING - Float32(cols - 1) * GRID_SPACING) / Float32(cols)
}

// 加载态：在内容区居中放大留白呈现。
private func loadingState(): Unit {
    VStack {
        Label("正在加载书库…").fontSize(16.fp)
        Label("首次加载或网络较慢时需要稍作等待").fontSize(12.fp).muted()
    }.spacing(10.vp).mainAxisAlignment(MainAxisAlignment.Center).crossAxisAlignment(CrossAxisAlignment.Center)
}

// 空态：居中 muted 图标 + 引导文案 + 主色重试按钮。
private func emptyState(model: AppModel): Unit {
    let muted = if (model.isLight()) { LANLU_L_MUTED } else { LANLU_MUTED }
    VStack {
        Icon(IconName.OpenFolder, size: 40.vp, color: muted)
        Label("没有匹配的档案").fontSize(16.fp)
        Label("试试更换搜索词，或在左侧调整过滤条件").fontSize(12.fp).muted()
        IconButton(IconName.Refresh, label: Some("重新加载"), role: ButtonRole.Primary) {=>
            model.submitSearch(1)
        }
    }.spacing(12.vp).mainAxisAlignment(MainAxisAlignment.Center).crossAxisAlignment(CrossAxisAlignment.Center)
}

// ---- 分页条（沿用现语义：chevron + muted 页码，边界页禁用）----

private func pager(model: AppModel): Unit {
    HStack {
        IconButton(IconName.ChevronLeft, label: Some("上一页")) {=>
            if (model.currentPage.value > 1) { model.submitSearch(model.currentPage.value - 1) }
        }.enabled(model.currentPage.value > 1)
        Label("第 ${model.currentPage.value} / ${model.maxPage()} 页").fontSize(12.fp).muted()
        IconButton(IconName.ChevronRight, label: Some("下一页")) {=>
            if (model.currentPage.value < model.maxPage()) { model.submitSearch(model.currentPage.value + 1) }
        }.enabled(model.currentPage.value < model.maxPage())
    }.spacing(12.vp).mainAxisAlignment(MainAxisAlignment.Center).hug().padding(10.vp)
}
