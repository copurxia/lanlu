package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.{AdminCategoryItem, AdminTagItem, SmartFilterItem}
import std.collection.ArrayList

// 设置区·内容管理板块（原型 settings-redesign.html：分类/标签/智能分类）。
// 分类管理页已充实；标签/智能分类由对应 Task 就地充实。

func categoriesPage(model: AppModel): Unit {
    // 进场加载一次：rememberState 随页面卸载清除，每次进入重拉（同概览页约定）。
    let loaded = rememberState<Bool>("cats.loaded", {=> false})
    if (!loaded.value) {
        loaded.value = true
        model.loadAdminCategories()
    }
    pageHeader("分类管理", "管理档案分类和扫描目录")

    // 工具条（原型 .toolbar：搜索 + 状态过滤 + 扫描媒体库 + 创建）。
    let q = rememberState<String>("cats.q", {=> ""})
    let status = rememberState<Int64>("cats.status", {=> 0})  // 0 全部 1 已启用 2 已禁用
    HStack {
        HStack {
            // cui TextField 无 placeholder 参数：ZStack 叠 muted Label 实现（同 formField）。
            ZStack {
                TextField(q.project(get: {v => v }, set: {_, v => v }))
                if (q.value.size == 0) {
                    Label("搜索分类...").fontSize(13.fp).muted().padding(8.vp, 10.vp, 0.vp, 0.vp)
                }
            }.alignment(Alignment.TopLeading)
        }.flex()
        SegmentedControl(["所有状态", "已启用", "已禁用"],
            status.project(get: {v => v }, set: {_, v => v }))
        Button("▶ 扫描媒体库", {=> model.actScanAllCategories() })
        // 创建/编辑弹窗含插件排序列表，首版走 todoToast（YAGNI，计划评审已确认）。
        Button("＋ 创建分类", {=> model.todoToast("创建分类（编辑弹窗）") }).role(ButtonRole.Primary)
    }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()

    // 卡片网格（原型 .grid-3：三列，封面横幅 + 名称/数量/开关 + 操作行）。
    // cui LazyGrid 行高固定且自身虚拟化滚动（measure 占满可用高），与页层 ScrollView
    // 嵌套会拿到无限高、视口计算失效，故退化为 HStack 三列等宽分行布局（brief 允许）。
    let delCat = rememberState<String>("cats.delCat", {=> ""})
    let delOpen = rememberState<Bool>("cats.delOpen", {=> false})
    let cats = model.adminCategories.value
    if (cats.size == 0) {
        pageLoading(model, "暂无分类或加载中…")
    }
    // SizeProbe 探测网格真实宽度：横幅封面按 (宽-2间距)/3 的单元格宽铺满（设计稿满宽横幅）。
    SizeProbe(width: model.contentWidth) {
    ForEachIndexed(chunkCats(filteredCats(cats, q.value, status.value), 3).toArray()) { _, row =>
        HStack {
            ForEach(row.toArray(), key: { c: AdminCategoryItem => c.catid }) { c =>
                VStack {
                    categoryCard(model, c, delCat, delOpen)
                }.flex()
            }
            // 末行补空槽，保持三列等宽。
            for (_ in 0..(3 - row.size)) {
                VStack { }.flex()
            }
        }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
    }
    }
    confirmModal(delOpen, "确认删除分类",
        "将从数据库中删除该分类及其下所有档案记录（不删除磁盘文件），并清理该分类的缩略图缓存。", "删除", {=>
        model.actDeleteCategory(delCat.value)
    })
}

// 工具条过滤：名称包含 + 启用状态。
private func filteredCats(cats: ArrayList<AdminCategoryItem>, q: String, status: Int64): ArrayList<AdminCategoryItem> {
    let out = ArrayList<AdminCategoryItem>()
    for (c in cats) {
        if (q.size > 0 && !c.name.contains(q)) { continue }
        if (status == 1 && !c.enabled) { continue }
        if (status == 2 && c.enabled) { continue }
        out.add(c)
    }
    return out
}

// 按 cols 切成若干行（HStack 分行布局用；lambda 不能捕获可变局部变量，故预先切块）。
private func chunkCats(items: ArrayList<AdminCategoryItem>, cols: Int64): ArrayList<ArrayList<AdminCategoryItem>> {
    let rows = ArrayList<ArrayList<AdminCategoryItem>>()
    var i = 0
    while (i < items.size) {
        let row = ArrayList<AdminCategoryItem>()
        var c = 0
        while (c < cols && i + c < items.size) {
            row.add(items[i + c])
            c += 1
        }
        rows.add(row)
        i += cols
    }
    return rows
}

// 分类卡（原型 .m-card：横幅封面 + 名称 + 档案数 + 启用开关 + 扫描/编辑/删除）。
private func categoryCard(model: AppModel, c: AdminCategoryItem, delCat: State<String>, delOpen: State<Bool>): Unit {
    let panel = if (model.isLight()) { LANLU_L_PANEL } else { LANLU_PANEL }
    let raised = if (model.isLight()) { LANLU_L_PANEL_RAISED } else { LANLU_PANEL_RAISED }
    let cellW = Float64(model.contentWidth.value - 24.0) / 3.0
    let bannerW = if (cellW > 100.0) { cellW } else { 100.0 }
    VStack {
        // 条幅只展示封面；分类信息和开关放在下方内容区，避免遮挡图片。
        if (c.coverAssetId > 0) {
            remoteImage(model, "asset:${c.coverAssetId}", "/api/assets/${c.coverAssetId}", bannerW.vp, 96.vp)
        } else {
            // 无封面：raised 色块 + 居中首字符，保持条幅高度一致。
            VStack {
                Label(firstChar(c.name)).fontSize(22.fp).muted()
            }.mainAxisAlignment(MainAxisAlignment.Center).crossAxisAlignment(CrossAxisAlignment.Center)
                .height(96.vp).fillWidth().background(raised)
        }
        VStack {
            HStack {
                VStack {
                    Label(c.name).fontSize(15.fp)
                    Label("${c.archiveCount} 个档案").fontSize(10.fp).muted()
                }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start)
                Spacer()
                // cui Switch 两参数均位置参数；绑定件按 catid 唯一化 key（见 switchBindKeyed）。
                Switch("", switchBindKeyed("cats.${c.catid}", c.enabled, {v => model.actToggleCategory(c.catid, v) }))
            }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).fillWidth()
            Label(if (c.description.size > 0) { c.description } else { "暂无描述" })
                .fontSize(11.fp).muted().maxLines(2)
            HStack {
                // 「▶ 扫描」均分整行（设计稿 flex-1），行尾「编辑/删除」不再贴卡片右缘。
                // cui Button 无 flex 修饰，故包一层 HStack 兜底。
                HStack { Button("▶ 扫描", {=> model.actScanCategory(c.catid) })
                    .style(ghostStyleOf(model)).enabled(c.enabled) }.flex()
                Button("编辑", {=> model.todoToast("分类编辑弹窗") }).style(ghostStyleOf(model))
                Button("删除", {=>
                    delCat.value = c.catid
                    delOpen.value = true
                }).role(ButtonRole.Danger)
            }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center)
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().padding(10.vp, 12.vp, 12.vp, 12.vp)
    }.spacing(0.0).crossAxisAlignment(CrossAxisAlignment.Start).hug()
        .background(panel, 14.vp).fillWidth()
}

func tagsPage(model: AppModel): Unit {
    let q = rememberState<String>("tags.q", {=> ""})
    let nsIdx = rememberState<Int64>("tags.nsIdx", {=> 0})
    let pageIdx = rememberState<Int64>("tags.page", {=> 0})
    // 进场与筛选变化时加载（q/ns/page 都作为加载条件的组成）。
    let loadedKey = rememberState<String>("tags.loadedKey", {=> ""})
    let nsName = if (nsIdx.value > 0 && nsIdx.value <= model.tagNs.value.size) {
        model.tagNs.value[nsIdx.value - 1]
    } else { "" }
    let key = "${q.value}|${nsName}|${pageIdx.value}"
    if (loadedKey.value != key) {
        loadedKey.value = key
        model.loadTagNamespaces()
        model.loadTagPage(q.value, nsName, pageIdx.value * 20)
    }
    pageHeader("标签管理", "管理系统标签、命名空间和多语言翻译")

    // 筛选行（原型：搜索 + 命名空间下拉 + 清空 + 创建）。
    HStack {
        HStack {
            // cui TextField 无 placeholder 参数：ZStack 叠 muted Label 实现（同 formField）。
            ZStack {
                TextField(q.project(get: {v => v }, set: {_, v => pageIdx.value = 0; return v }))
                if (q.value.size == 0) {
                    Label("搜索标签...").fontSize(13.fp).muted().padding(8.vp, 10.vp, 0.vp, 0.vp)
                }
            }.alignment(Alignment.TopLeading)
        }.flex()
        Dropdown(nsOptions(model), nsIdx.project(get: {v => v }, set: {_, v => pageIdx.value = 0; return v }))
        Button("清空", {=>
            q.value = ""
            nsIdx.value = 0
            pageIdx.value = 0
        })
        Spacer()
        // 创建/编辑弹窗首版走 todoToast（YAGNI，计划评审已确认）。
        Button("＋ 创建新标签", {=> model.todoToast("标签编辑弹窗") }).role(ButtonRole.Primary)
    }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()

    // 标签行列表（原型：图标 + 命名空间徽章 + 名称 + 翻译行 + 操作）。
    let delId = rememberState<Int64>("tags.delId", {=> -1})
    let delOpen = rememberState<Bool>("tags.delOpen", {=> false})
    match (model.tagPage.value) {
        case Some(p) =>
            if (p.items.size == 0) {
                Label("未找到标签").fontSize(12.fp).muted()
            }
            ForEach(p.items.toArray(), key: { t: AdminTagItem => "${t.id}" }) { t =>
                // 行卡（原型 .s-card 单行）：图标盒 + 命名空间徽章（空则不显示）+ 名称 + 翻译行 + 右侧操作。
                HStack {
                    VStack {
                        Label(tagInitial(t)).fontSize(14.fp)
                            .foregroundColor(Color.rgb(255, 255, 255))
                    }.mainAxisAlignment(MainAxisAlignment.Center).crossAxisAlignment(CrossAxisAlignment.Center)
                        .flexible(false).width(36.vp).height(36.vp).background(Color.rgb(0x4A, 0x5A, 0x7A), 8.vp)
                    VStack {
                        HStack {
                            if (t.namespace.size > 0) { pill(model, t.namespace, PillTone.Gray) }
                            Label(t.name).fontSize(13.fp)
                        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center)
                        if (tagTransLine(t).size > 0) {
                            Label(tagTransLine(t)).fontSize(10.fp).muted().maxLines(1)
                        }
                    }.spacing(3.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
                    Button("编辑", {=> model.todoToast("标签编辑弹窗") }).style(ghostStyleOf(model))
                    Button("删除", {=>
                        delId.value = t.id
                        delOpen.value = true
                    }).role(ButtonRole.Danger)
                }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).flexible(false).fillWidth()
                    .padding(10.vp, 12.vp)
                    .background(if (model.isLight()) { LANLU_L_PANEL } else { LANLU_PANEL }, 12.vp)
            }
            // 分页（原型 .pager：左侧统计 + 右侧页码）
            HStack {
                let shownEnd = if ((pageIdx.value + 1) * 20 < p.total) { (pageIdx.value + 1) * 20 } else { p.total }
                Label("显示第 ${pageIdx.value * 20 + 1} 到 ${shownEnd} 项，共 ${p.total} 个标签")
                    .fontSize(11.fp).muted()
                Spacer()
                Button("‹", {=> if (pageIdx.value > 0) { pageIdx.value -= 1 } }).enabled(pageIdx.value > 0)
                Label("${pageIdx.value + 1} / ${(p.total + 19) / 20}").fontSize(11.fp).muted()
                Button("›", {=> pageIdx.value += 1 }).enabled((pageIdx.value + 1) * 20 < p.total)
            }.crossAxisAlignment(CrossAxisAlignment.Center).hug()
        case None => pageLoading(model, "标签加载中…")
    }
    confirmModal(delOpen, "确认删除标签", "确定要删除此标签吗？此操作无法撤销。", "删除", {=>
        model.actDeleteTag(delId.value)
        // 清空已加载标记：下次构建按当前筛选强制重拉（model 侧 act.tag 不再统一 reload）。
        loadedKey.value = ""
    })
}

// 命名空间下拉项：首项「所有命名空间」，其余为服务端动态列表。
private func nsOptions(model: AppModel): Array<String> {
    let out = ArrayList<String>()
    out.add("所有命名空间")
    for (n in model.tagNs.value) { out.add(n) }
    return out.toArray()
}

// 图标盒首字符：命名空间首字母，无命名空间时用标签名首字符（服务端存在无命名空间的年份标签）。
private func tagInitial(t: AdminTagItem): String {
    if (t.namespace.size > 0) { return firstChar(t.namespace) }
    if (t.name.size > 0) { return firstChar(t.name) }
    "?"
}

// 翻译摘要行（原型 .row-desc：中文/English/Links 按存在拼接）。
private func tagTransLine(t: AdminTagItem): String {
    var line = ""
    if (t.zhText.size > 0) { line += "中文: ${t.zhText}" }
    if (t.enText.size > 0) {
        if (line.size > 0) { line += " · " }
        line += "English: ${t.enText}"
    }
    if (t.links.size > 0) {
        if (line.size > 0) { line += " · " }
        line += "Links: ${t.links}"
    }
    return line
}

func filtersPage(model: AppModel): Unit {
    // 进场加载一次（同分类页约定）。
    let loaded = rememberState<Bool>("filters.loaded", {=> false})
    if (!loaded.value) {
        loaded.value = true
        model.loadSmartFilters()
    }
    pageHeader("智能分类", "管理预设的快速筛选条件，用于搜索侧边栏")
    HStack {
        Spacer()
        // 编辑/添加弹窗首版走 todoToast（YAGNI，计划评审已确认）。
        Button("＋ 添加", {=> model.todoToast("智能分类编辑弹窗") }).role(ButtonRole.Primary)
    }.hug()

    let delId = rememberState<Int64>("filters.delId", {=> -1})
    let delOpen = rememberState<Bool>("filters.delOpen", {=> false})
    let list = model.smartFilters.value
    if (list.size == 0) {
        pageLoading(model, "暂无数据")
    }
    detailCard(model, "筛选器列表") {
        ForEachIndexed(list.toArray()) { i, f =>
            HStack {
                // 拖拽手柄：应用字体无 ⠿（U+28FF）字形（真机渲染为豆腐块），改用覆盖范围内的 ≡（U+2261）。
                Label("≡").fontSize(12.fp).muted()
                VStack {
                    Label(if (f.name.size > 0) { f.name } else { "未命名" }).fontSize(13.fp)
                    Label(filterSummary(f)).fontSize(10.fp).muted().maxLines(1)
                }.spacing(3.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
                Button("↑", {=> model.actMoveFilter(f.id, true) }).style(ghostStyleOf(model)).enabled(i > 0)
                Button("↓", {=> model.actMoveFilter(f.id, false) }).style(ghostStyleOf(model)).enabled(i < list.size - 1)
                // cui Switch 两参数均位置参数；绑定件按 filter id 唯一化 key（见 switchBindKeyed）。
                Switch("", switchBindKeyed("filters.${f.id}", f.enabled, {v => model.actToggleFilter(f.id) }))
                Button("编辑", {=> model.todoToast("智能分类编辑弹窗") }).style(ghostStyleOf(model))
                Button("删除", {=>
                    delId.value = f.id
                    delOpen.value = true
                }).role(ButtonRole.Danger)
            }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).flexible(false).fillWidth().padding(0.vp, 6.vp)
        }
    }
    confirmModal(delOpen, "确认删除", "确定要删除此智能分类吗？", "删除", {=>
        model.actDeleteFilter(delId.value)
    })
}

// 摘要行（原型：Q/仅显示新档案/仅显示无标签档案/开始日期/排序方式 按存在拼接）。
private func filterSummary(f: SmartFilterItem): String {
    var s = ""
    if (f.query.size > 0) { s += "Q: ${f.query} · " }
    if (f.newonly) { s += "仅显示新档案 · " }
    if (f.untaggedonly) { s += "仅显示无标签档案 · " }
    if (f.dateFrom.size > 0) { s += "开始日期: ${f.dateFrom} · " }
    if (f.sortBy.size > 0) {
        s += "排序方式: ${sortByLabel(f.sortBy)} ${if (f.sortOrder == "asc") { "升序" } else { "降序" }}"
    }
    // " · " 是 4 字节（空格 + U+00B7 两字节 + 空格），需截掉 4 字节。
    if (s.endsWith(" · ")) { s = s[0..(s.size - 4)] }
    return s
}

// 排序字段中文标签。
private func sortByLabel(v: String): String {
    match (v) {
        case "created_at" => "创建时间"
        case "release_at" => "发行时间"
        case "updated_at" => "更新时间"
        case "lastread" => "最后阅读"
        case "title" => "标题"
        case "pagecount" => "页数"
        case _ => "默认"
    }
}
