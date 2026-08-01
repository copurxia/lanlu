package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.SearchItem
import std.collection.ArrayList
import std.time.DateTime

private let SHELF_SIDE_W: Float32 = 224.0
private let SHELF_PADDING: Float32 = 22.0
private let SHELF_GRID_GAP: Float32 = 14.0
private let SHELF_MIN_CARD_W: Float32 = 150.0

private func shelfSortLabels(model: AppModel): Array<String> {
    if (model.shelfTab.value == 0) {
        [model.t("shelf.sort.added"), model.t("library.sort.title"), model.t("library.sort.pages")]
    } else {
        [model.t("shelf.sort.read"), model.t("library.sort.title"), model.t("library.sort.pages")]
    }
}

// library-redesign.html：左侧书架导航 + 右侧收藏/历史主区。顶栏搜索绑定
// shelfSearchText，输入即本地过滤标题与标签；数据仍来自真实 search API。
public func shelfView(model: AppModel): Unit {
    HStack {
        shelfSidebar(model)
        Divider(axis: Axis.Vertical)
        SizeProbe(width: model.shelfContentWidth) {
            let items = visibleShelfItems(model)
            VStack {
                shelfToolbar(model, items.size)
                if (activeShelfLoading(model) && activeShelfItems(model).size == 0) {
                    shelfMessage(model, IconName.Refresh, model.t("shelf.loading"), "")
                } else if (activeShelfFailed(model) && activeShelfItems(model).size == 0) {
                    shelfMessage(model, IconName.Refresh, model.t("shelf.loadFailed"), model.t("shelf.retry"))
                } else if (items.size == 0) {
                    let filtered = model.shelfSearchText.value.trimAscii().size > 0 || model.shelfFilter.value != 0
                    shelfMessage(model, if (model.shelfTab.value == 0) {
                        IconName.OpenFolder
                    } else {
                        IconName.Clock
                    }, if (filtered) {
                        model.t("shelf.noMatch")
                    } else if (model.shelfTab.value == 0) {
                        model.t("shelf.emptyFavorites")
                    } else {
                        model.t("shelf.emptyHistory")
                    }, if (filtered) {
                        model.t("shelf.adjustFilter")
                    } else if (model.shelfTab.value == 0) {
                        model.t("shelf.emptyFavoritesHint")
                    } else {
                        model.t("shelf.emptyHistoryHint")
                    })
                } else if (model.shelfTab.value == 0) {
                    favoritesContent(model, items)
                } else {
                    historyContent(model, items)
                }
            }.spacing(0.0)
        }
    }.spacing(0.0)
}

private func shelfSidebar(model: AppModel): Unit {
    let bg = if (model.isLight()) {
        LANLU_L_BG
    } else {
        LANLU_BG
    }
    VStack {
        VStack {
            Label(model.t("shelf.section")).fontSize(11.fp).muted().padding(10.vp, 6.vp)
            NavItem(model.t("shelf.favorites"), active: model.shelfTab.value == 0,
                count: "${model.shelfFavorites.value.size}", glyph: Some(GhostGlyph.Heart)) {
                => model.selectShelfTab(0)
            }
            NavItem(model.t("shelf.history"), active: model.shelfTab.value == 1,
                count: "${historyCount(model.shelfHistory.value)}", glyph: Some(GhostGlyph.Named(IconName.Clock))) {
                => model.selectShelfTab(1)
            }
        }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().padding(10.vp, 8.vp)
        VStack {
            Label(model.t("shelf.quickFilters")).fontSize(11.fp).muted().padding(10.vp, 6.vp)
            NavItem(model.t("shelf.unfinished"), active: model.shelfFilter.value == 1, glyph: Some(GhostGlyph.Pages)) {
                => model.toggleShelfFilter(1)
            }
            NavItem(model.t("shelf.collectionsOnly"), active: model.shelfFilter.value == 2, glyph: Some(GhostGlyph.Book)) {
                => model.toggleShelfFilter(2)
            }
            NavItem(model.t("shelf.newOnly"), active: model.shelfFilter.value == 3,
                glyph: Some(GhostGlyph.Named(IconName.Sparkle))) {=> model.toggleShelfFilter(3)}
        }.spacing(2.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().padding(10.vp, 8.vp)
        Spacer()
    }.spacing(2.vp).hug().width(SHELF_SIDE_W).background(bg)
}

private func shelfToolbar(model: AppModel, count: Int64): Unit {
    let sortState = if (model.shelfTab.value == 0) {
        model.shelfFavoriteSortIndex
    } else {
        model.shelfHistorySortIndex
    }
    HStack {
        Label(if (model.shelfTab.value == 0) {
            model.t("shelf.favorites")
        } else {
            model.t("shelf.history")
        }).fontSize(20.fp).maxLines(1)
        SegmentedControl(
            [model.t("shelf.tabFavorites"), model.t("shelf.tabHistory")],
            model.shelfTab.project(
                get: {v => v},
                set: {
                    _, v =>
                        model.selectShelfTab(v)
                        v
                }
            ),
            key: "shelf:tabs"
        ).width(190.vp)
        Spacer()
        Label(if (model.shelfTab.value == 0) {
            model.t("shelf.favoriteCount", params: [("count", "${count}")])
        } else {
            model.t("shelf.historyCount", params: [("count", "${count}")])
        }).fontSize(12.fp).muted()
        Dropdown(
            shelfSortLabels(model),
            sortState.project(
                get: {v => v},
                set: {
                    _, v =>
                        model.setShelfSort(v)
                        v
                }
            )
        ).width(142.vp)
        GhostIconButton(GhostGlyph.Named(IconName.Refresh), "shelf:refresh") {=> model.refreshShelf()}
    }.spacing(10.vp).hug().padding(SHELF_PADDING, 14.0)
}

private func activeShelfItems(model: AppModel): ArrayList<SearchItem> {
    if (model.shelfTab.value == 0) {
        model.shelfFavorites.value
    } else {
        model.shelfHistory.value
    }
}

private func activeShelfLoading(model: AppModel): Bool {
    if (model.shelfTab.value == 0) {
        model.shelfFavoritesLoading.value
    } else {
        model.shelfHistoryLoading.value
    }
}

private func activeShelfFailed(model: AppModel): Bool {
    if (model.shelfTab.value == 0) {
        model.shelfFavoritesFailed.value
    } else {
        model.shelfHistoryFailed.value
    }
}

private func historyCount(items: ArrayList<SearchItem>): Int64 {
    var count: Int64 = 0
    for (item in items) {
        if (item.lastreadtime > 0 && !isTankItem(item)) {
            count++
        }
    }
    count
}

private func visibleShelfItems(model: AppModel): ArrayList<SearchItem> {
    let result = ArrayList<SearchItem>()
    let query = model.shelfSearchText.value.trimAscii().toAsciiLower()
    let history = model.shelfTab.value == 1
    for (item in activeShelfItems(model)) {
        if (history && (item.lastreadtime <= 0 || isTankItem(item))) {
            continue
        }
        if (query.size > 0 && !item.title.toAsciiLower().contains(query) && !item
            .tagsCsv
            .toAsciiLower()
            .contains(query)) {
            continue
        }
        match (model.shelfFilter.value) {
            case 1 =>
                if (item.progress <= 0 || item.pagecount <= 0 || item.progress >= item.pagecount) {
                    continue
                }
            case 2 =>
                if (!isTankItem(item)) {
                    continue
                }
            case 3 =>
                if (!item.isnew) {
                    continue
                }
            case _ => ()
        }
        result.add(item)
    }
    result
}

private func shelfColumns(width: Float32): Int64 {
    if (width <= 0.0) {
        return 5
    }
    let inner = max(SHELF_MIN_CARD_W, width - 2.0 * SHELF_PADDING)
    var cols = Int64((inner + SHELF_GRID_GAP) / (SHELF_MIN_CARD_W + SHELF_GRID_GAP))
    if (cols < 2) {
        cols = 2
    }
    if (cols > 10) {
        cols = 10
    }
    cols
}

private func shelfCardWidth(width: Float32): Float32 {
    if (width <= 0.0) {
        return 168.0
    }
    let cols = shelfColumns(width)
    (width - 2.0 * SHELF_PADDING - Float32(cols - 1) * SHELF_GRID_GAP) / Float32(cols)
}

private func favoritesContent(model: AppModel, items: ArrayList<SearchItem>): Unit {
    let cardW = shelfCardWidth(model.shelfContentWidth.value)
    ScrollView(key: "shelf:favorites") {
        FlowRow {
            ForEach(items, key: {item => searchItemKey(item)}) {
                item => searchItemCard(model, item, cardW)
            }
        }.spacing(SHELF_GRID_GAP, 18.0)
    }.padding(SHELF_PADDING, 4.0, SHELF_PADDING, 30.0)
}

private func historyContent(model: AppModel, items: ArrayList<SearchItem>): Unit {
    let now = DateTime.now().toUnixTimeStamp().toSeconds()
    let today = ArrayList<SearchItem>()
    let week = ArrayList<SearchItem>()
    let earlier = ArrayList<SearchItem>()
    for (item in items) {
        let age = max(Int64(0), now - item.lastreadtime)
        if (age < 86400) {
            today.add(item)
        } else if (age < 7 * 86400) {
            week.add(item)
        } else {
            earlier.add(item)
        }
    }
    let cardW = shelfCardWidth(model.shelfContentWidth.value)
    ScrollView(key: "shelf:history") {
        VStack {
            if (model.shelfSearchText.value.trimAscii().size == 0 && model.shelfFilter.value == 0) {
                match (mostRecentHistory(model.shelfHistory.value)) {
                    case Some(item) => resumeBanner(model, item)
                    case None => ()
                }
            }
            historyGroup(model, model.t("shelf.today"), today, cardW, now)
            historyGroup(model, model.t("shelf.thisWeek"), week, cardW, now)
            historyGroup(model, model.t("shelf.earlier"), earlier, cardW, now)
        }.spacing(26.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
    }.padding(SHELF_PADDING, 4.0, SHELF_PADDING, 30.0)
}

private func mostRecentHistory(items: ArrayList<SearchItem>): ?SearchItem {
    var latest: ?SearchItem = None
    var latestTime: Int64 = 0
    for (item in items) {
        if (!isTankItem(item) && item.lastreadtime > latestTime) {
            latest = Some(item)
            latestTime = item.lastreadtime
        }
    }
    latest
}

private func historyGroup(model: AppModel, title: String, items: ArrayList<SearchItem>, cardW: Float32, now: Int64): Unit {
    if (items.size == 0) {
        return
    }
    VStack {
        HStack {
            Label(title).fontSize(14.fp)
            Label(model.t("shelf.groupCount", params: [("count", "${items.size}")])).fontSize(11.5.fp).muted()
            Divider()
        }.spacing(10.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
        FlowRow {
            ForEach(items, key: {item => searchItemKey(item)}) {
                item => archiveCardWithMeta(model, item, cardW,
                    "${relativeReadTime(model, now, item.lastreadtime)} · ${model.t("shelf.pages", params: [("count", "${item.pagecount}")])}")
            }
        }.spacing(SHELF_GRID_GAP, 18.0)
    }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug()
}

private func resumeBanner(model: AppModel, item: SearchItem): Unit {
    let panel = if (model.isLight()) {
        LANLU_L_PANEL
    } else {
        LANLU_PANEL
    }
    let pct = if (item.pagecount > 0) {
        min(100, max(0, item.progress * 100 / item.pagecount))
    } else {
        0
    }
    let start = if (item.pagecount > 0 && item.progress >= item.pagecount) {
        1
    } else {
        max(1, item.progress + 1)
    }
    ClickArea(onClick: {=> model.openReader(item.arcid, start)}) {
        HStack {
            if (item.coverAssetId > 0) {
                remoteImage(model, "asset:${item.coverAssetId}", "/api/assets/${item.coverAssetId}", 64.vp, 86.vp,
                    radius: 9.0)
            } else {
                VStack {Icon(IconName.Image, size: 22.vp)}
                    .mainAxisAlignment(MainAxisAlignment.Center)
                    .crossAxisAlignment(CrossAxisAlignment.Center)
                    .width(64.vp)
                    .height(86.vp)
                    .background(if (model.isLight()) {
                        LANLU_L_FIELD
                    } else {
                        LANLU_FIELD
                    }, 9.vp)
            }
            VStack {
                Label(model.t("shelf.resumeKicker", params: [("page", "${start}"), ("total", "${item.pagecount}")]))
                    .fontSize(11.fp)
                    .foregroundColor(if (model.isLight()) {
                        LANLU_L_ACCENT
                    } else {
                        LANLU_ACCENT
                    })
                Label(item.title).fontSize(14.5.fp).maxLines(1)
                Label(
                    model.t("shelf.resumeMeta",
                        params: [("time", relativeReadTime(model, DateTime.now().toUnixTimeStamp().toSeconds(),
                                item.lastreadtime))])).fontSize(11.5.fp).muted()
                ProgressTrack(pct, 4.0).fillWidth()
            }.spacing(5.vp).crossAxisAlignment(CrossAxisAlignment.Start).flex()
            Button(model.t("shelf.continue"), {=> model.openReader(item.arcid, start)}, role: ButtonRole.Primary)
                .width(120.vp)
        }.spacing(16.vp).crossAxisAlignment(CrossAxisAlignment.Center).padding(16.vp, 14.vp).background(panel, 14.vp)
    }
}

private func relativeReadTime(model: AppModel, now: Int64, timestamp: Int64): String {
    let age = max(Int64(0), now - timestamp)
    if (age < 60) {
        return model.t("shelf.justNow")
    }
    if (age < 3600) {
        return model.t("shelf.minutesAgo", params: [("count", "${age / 60}")])
    }
    if (age < 86400) {
        return model.t("shelf.hoursAgo", params: [("count", "${age / 3600}")])
    }
    model.t("shelf.daysAgo", params: [("count", "${age / 86400}")])
}

private func shelfMessage(model: AppModel, icon: IconName, title: String, detail: String): Unit {
    VStack {
        Icon(icon, size: 42.vp, color: if (model.isLight()) {
            LANLU_L_MUTED
        } else {
            LANLU_MUTED
        })
        Label(title).fontSize(14.fp)
        if (detail.size > 0) {
            Label(detail).fontSize(11.5.fp).muted()
        }
        if (activeShelfFailed(model)) {
            Button(model.t("shelf.retry"), {=> model.refreshShelf()}, role: ButtonRole.Primary)
        }
    }.spacing(8.vp).mainAxisAlignment(MainAxisAlignment.Center).crossAxisAlignment(CrossAxisAlignment.Center)
}
