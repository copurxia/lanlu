package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.SearchItem
import std.collection.ArrayList

private let SORT_FIELDS = ["title", "created_at", "updated_at", "lastread", "pagecount", "release_at"]
private let SORT_LABELS = ["标题", "创建时间", "更新时间", "最近阅读", "页数", "发布日期"]
private let ORDER_LABELS = ["升序", "降序"]

// 书库主页：顶部工具条 → 封面网格（5 列 LazyGrid）→ 底部分页条。
public func libraryView(model: AppModel): Unit {
    VStack {
        toolbar(model)
        Divider()
        if (model.loading.value && model.items.value.size == 0) {
            Panel { Label("加载中…").muted() }
        } else if (model.items.value.size == 0) {
            Panel {
                VStack {
                    Label("没有匹配的档案").muted()
                    Button("重新加载", {=> model.submitSearch(1) })
                }.spacing(8.vp)
            }
        } else {
            grid(model)
        }
        Divider()
        pager(model)
    }
}

private func toolbar(model: AppModel): Unit {
    HStack {
        TextField(model.searchText, key: "search").flex()
        Button("搜索", {=>
            model.query.filter = model.searchText.value
            model.submitSearch(1)
        }).role(ButtonRole.Primary)
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
        Button("设置", {=> model.page.value = Page.Settings })
        // 容器默认 flexible:true，工具条/分页条要 hug 按内容收缩（hug 是 HStack
        // 专有链式，须排在返回 Widget 的通用修饰器 padding 之前）。
    }.spacing(8.vp).hug().padding(8.vp)
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

private func grid(model: AppModel): Unit {
    // LazyGrid 的 data 形参是 Array<T>，State 里是 ArrayList，逐帧 toArray 一份。
    LazyGrid(model.items.value.toArray(), 5, 340.0, spacing: 12.0, columnSpacing: 12.0,
        id: "library-grid") { item =>
        archiveCard(model, item)
    }.padding(12.vp)
}

private func archiveCard(model: AppModel, item: SearchItem): Unit {
    ClickArea(onClick: {=> model.openDetail(item.arcid) }) {
        VStack {
            if (item.coverAssetId > 0) {
                remoteImage(model, "asset:${item.coverAssetId}", "/api/assets/${item.coverAssetId}",
                    180.vp, 250.vp)
            } else {
                Panel { Label("无封面").muted() }.width(180.vp).height(250.vp)
            }
            Label(item.title).maxLines(2)
            HStack {
                Label("${item.pagecount} 页").muted()
                if (item.isnew) { Label("NEW") }
                if (item.isfavorite) { Label("★") }
                if (item.progress > 0) { Label("${item.progress}/${item.pagecount}").muted() }
            }.spacing(6.vp)
            // Stack 跨轴默认 Stretch 会把 ImageView 拉满整列宽，与固定 180vp 的
            // 占位 Panel 宽度不一致；Start 让子项保持自然宽度（封面/占位均 180）。
        }.spacing(4.vp).crossAxisAlignment(CrossAxisAlignment.Start)
    }
}

private func pager(model: AppModel): Unit {
    HStack {
        Button("上一页", {=>
            if (model.currentPage.value > 1) { model.submitSearch(model.currentPage.value - 1) }
        })
        Label("第 ${model.currentPage.value} / ${model.maxPage()} 页 · 共 ${model.recordsTotal.value} 项").muted()
        Button("下一页", {=>
            if (model.currentPage.value < model.maxPage()) { model.submitSearch(model.currentPage.value + 1) }
        })
    }.spacing(12.vp).hug().padding(8.vp)
}
