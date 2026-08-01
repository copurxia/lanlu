package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.{formatTimestamp, sourceNamespace, ArchiveMeta, TankoubonInfo, SearchItem, PageInfo}
import std.collection.ArrayList

// 详情页（档案 / 合集共用骨架；原型 home-detail-redesign.html「档案详情/合集详情」视图）：
// backdrop 模糊大图 + 双层 scrim → hero grid（封面 200vp 2:3 ｜ badges/大标题/meta/内联进度/
// 3 行简介/标签 chips ｜ 176vp 玻璃操作卡）→ 主侧双列（1fr : 300vp）。
// 骨架与卡片组件在 widgets.cj（detailSkeleton/detailHero/detailCard/progressCard/infoList/
// tagGroups/pagePreview/memberGridContent/memberListContent/tankCardRow），本文件只做数据装配。
//
// 数据接线（model.cj）：档案 = meta + dfiles（页面预览）+ ptanks（所属合集）+ related（相关推荐）；
// 合集 = tankmeta + tankmembers（search?tankoubon_id&tank_order）+ tankrelated。
// 辅助卡片失败静默、无数据即隐藏（不 mock）。

// ---- 档案详情 ----

// 选择模式归属（全局 selectionMode 与书库页共用一套）：tank 详情成员区多选入口（卡片
// hover 勾选钮 / 列表行首圆圈）进入时记录 tank id，空串表示非 tank 详情来源。
// 框架无页面卸载钩子，详情页构建期按归属守卫清理，
// 避免把 tank 成员的选择态带进档案详情/其他合集（书库直达返回的残留见批次说明）。
private var detailSelectionOwner: String = ""

// Danger 语义图标钮（详情操作卡「删除」）：形制同 GhostIconButton（34/28 见 size），
// 图标与 hover 底取危险红；不动 widgets.cj 共享的 GhostIconButton（并行任务在改）。
class DangerIconButton <: Widget {
    private let glyph: GhostGlyph
    private let hoverId: String
    private let onClick: () -> Unit
    private let size: Float32
    private var frame = Rect.zero()

    public init(glyph: GhostGlyph, hoverId: String, size!: Float32 = 34.0, onClick!: () -> Unit) {
        this.glyph = glyph
        this.hoverId = hoverId
        this.onClick = onClick
        this.size = size
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
        let radius: Float32 = if (size >= 34.0) { 9.0 } else { 8.0 }
        if (hovered) {
            ctx.renderer.fillRoundedRect(frame, radius, Color.rgba(0xE0, 0x5D, 0x5D, 30))
        }
        drawGhostGlyph(ctx.renderer, glyph, frame.centerX(), frame.centerY(),
            Color.rgb(0xE0, 0x5D, 0x5D))
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

public func detailView(model: AppModel): Unit {
    match (model.meta.value) {
        case None => Panel {Label(model.t("common.loading")).muted()}
        case Some(m) => archiveDetailBody(model, m)
    }
}

private func archiveDetailBody(model: AppModel, m: ArchiveMeta): Unit {
    // tank 详情进入的选择态不带进档案详情（框架无卸载钩子，构建期守卫一次性清理）。
    if (model.selectionMode.value && detailSelectionOwner.size > 0) {
        model.exitSelection()
        detailSelectionOwner = ""
    }
    let addTankOpen = rememberState<Bool>("detail.addTankOpen:${m.arcid}", {=> false})
    let delOpen = rememberState<Bool>("detail.delOpen:${m.arcid}", {=> false})
    let pct = memberReadPct(m.pagecount, m.progress)
    let hero = DetailHeroData()
    // 徽标行（原型：金「档案 · 图像」+ 灰「2024」「同人志」；蓝色「已完结」无数据字段不做）。
    // 年份自 release_at 推导；分类取首个 category: 前缀标签（无则不显示，不 mock）。NEW 红 pill 保留。
    let badgeList = ArrayList<String>()
    badgeList.add(model.t("detail.archiveBadge", params: [("type", m.archivetype)]))
    if (m.release_at > 0) {
        badgeList.add(formatTimestamp(m.release_at)[0..4])
    }
    for (t in m.tags) {
        if (t.startsWith("category:")) {
            badgeList.add(t[9..t.size])
            break
        }
    }
    hero.badges = badgeList.toArray()
    hero.isNew = m.isnew
    hero.title = m.title
    hero.metaLine = archiveMetaLine(model, m)
    hero.progressPct = pct
    hero.progressText = model.t("detail.readPercent", params: [("percent", "${pct}")])
    hero.summary = oneLineSummary(m.description)
    hero.tags = m.tags
    hero.primaryLabel = readButtonLabel(model, m)
    hero.primaryEnabled = m.pagecount > 0
    hero.onPrimary = {
        =>
            let start = if (m.progress >= m.pagecount) {
                1
            } else {
                m.progress + 1
            }
            model.openReader(m.arcid, start)
    }

    let actionIcons: () -> Unit = {
        =>
            // 矢量图标钮（28vp 紧凑尺寸）：编辑走 sdl 图标库 Pencil，下载/加入合集/更多
            // 为 GhostGlyph 手绘矢量（替代原 ⬇/⊕/编/⋯ 文本兜底）。
            // 加入合集/删除已接（第二波）；下载/更多动作留 TODO。
            GhostIconButton(GhostGlyph.Heart, "detail:fav", size: 28.0, active: m.isfavorite) {
                => model.toggleFavorite(m.arcid, !m.isfavorite)
            }
            GhostIconButton(GhostGlyph.Download, "detail:download", size: 28.0) {
                => model.todoToast(model.t("detail.download"))
            }
            GhostIconButton(GhostGlyph.AddTank, "detail:addtank", size: 28.0) {=> addTankOpen.value = true }
            GhostIconButton(GhostGlyph.Named(IconName.Pencil), "detail:edit", size: 28.0) {
                => model.openArchiveMetadataEditor(m.arcid)
            }
            DangerIconButton(GhostGlyph.Named(IconName.Trash), "detail:delete", size: 28.0) {
                => delOpen.value = true
            }
            GhostIconButton(GhostGlyph.Ellipsis, "detail:more", size: 28.0) {
                => model.todoToast(model.t("detail.moreActions"))
            }
    }

    // 主列：页面预览（到货才显示）→ 所属合集（无数据隐藏）→ 相关推荐（无数据隐藏）
    let mainCards = ArrayList<() -> Unit>()
    if (model.detailPages.value.size > 0) {
        mainCards.add({
            => detailCard(model, model.t("detail.pagePreview"), count: model.t("detail.pages",
                params: [("count", "${model.detailPages.value.size}")]), tools: {
                => MiniSeg([model.t("detail.thumbnails"), model.t("detail.list"), model.t("detail.tree")],
                    model.pageViewIndex, key: "pv-seg")
            }) {
                => pagePreview(model, model.detailPages.value, m.progress) {
                    no => model.openReader(m.arcid, no)
                }
            }
        })
    }
    if (model.parentTanks.value.size > 0) {
        mainCards.add({
            => detailCard(model, model.t("detail.parentCollections"), count: "${model.parentTanks.value.size}") {
                => tankCardRow(model, model.parentTanks.value, "parent-tanks")
            }
        })
    }
    if (model.relatedItems.value.size > 0) {
        mainCards.add({
            => detailCard(model, model.t("detail.related")) {
                => cardRow(model, "related", model.relatedItems.value, 132.0, 238.0)
            }
        })
    }

    // 侧栏：进度大卡 → 基础信息（含 statPages 混合统计行）→ 标签分组
    let sideCards = ArrayList<() -> Unit>()
    let ofText = if (m.progress > 0) {
        model.t("detail.readProgress", params: [("read", "${m.progress}"), ("total", "${m.pagecount}")])
    } else {
        model.t("detail.notStarted", params: [("count", "${m.pagecount}")])
    }
    sideCards.add({=> progressCard(model, "${pct}%", ofText, pct)})
    sideCards.add({
        => detailCard(model, model.t("detail.basicInfo")) {
            => infoList(model, archiveInfoRows(model, m, model.detailPages.value))
        }
    })
    if (m.tags.size > 0) {
        sideCards.add({
            => detailCard(model, model.t("detail.tags")) {=> tagGroups(model, m.tags)}
        })
    }

    let backdropKey = if (m.coverAssetId > 0) {
        "backdrop:${m.arcid}"
    } else {
        ""
    }
    detailSkeleton(model, backdropKey, hero, m.coverAssetId, actionIcons, mainCards.toArray(), sideCards.toArray(),
        tank: false)
    // 弹窗与页面同根兄弟挂载（Modal 零尺寸，不占布局，同 settings_view 惯例）。
    addToTankDialog(model, addTankOpen, m.arcid)
    confirmModal(model, delOpen, model.t("detail.deleteArchiveTitle"), model.t("detail.deleteArchiveDetail",
        params: [("title", m.title)]), model.t("detail.delete"), {
        => model.deleteArchive(m.arcid)
    })
}

// ---- 合集详情 ----

public func tankView(model: AppModel): Unit {
    match (model.tank.value) {
        case None => Panel {Label(model.t("common.loading")).muted()}
        case Some(t) => tankDetailBody(model, t)
    }
}

private func tankDetailBody(model: AppModel, t: TankoubonInfo): Unit {
    // 选择态归属守卫：selectionMode 与书库页共用一套，进入本合集详情时发现选择是在
    // 别处（书库/其他合集/档案详情）进入的即退出，避免把外部选择态带进成员区。
    if (model.selectionMode.value && detailSelectionOwner != t.id) {
        model.exitSelection()
        detailSelectionOwner = ""
    }
    let delOpen = rememberState<Bool>("tank.delOpen:${t.id}", {=> false})
    let addOpen = rememberState<Bool>("tank.addOpen:${t.id}", {=> false})
    let removeOpen = rememberState<Bool>("tank.removeOpen:${t.id}", {=> false})
    let batchDelOpen = rememberState<Bool>("tank.batchDelOpen:${t.id}", {=> false})
    let members = model.tankMembers.value
    let pct = tankReadPct(t)
    let hero = DetailHeroData()
    hero.badges = [model.t("detail.collectionBadge")]
    hero.title = t.name
    hero.metaLine = tankMetaLine(model, t)
    hero.progressPct = pct
    hero.progressText = model.t("detail.readPercent", params: [("percent", "${pct}")])
    hero.summary = oneLineSummary(t.description)
    hero.tags = t.tags
    hero.primaryLabel = model.t("detail.readFromStart")
    hero.primaryEnabled = members.size > 0
    hero.onPrimary = {=> model.startTankReading()}

    let actionIcons: () -> Unit = {
        =>
            // 合集 4+1 图标（用户决定：不与档案同构；设计稿 tank 视图下载/加入合集为 only-archive）。
            // 收藏/添加档案/删除已接（第二波）；更多动作留 TODO。矢量图标钮（28vp）。
            GhostIconButton(GhostGlyph.Heart, "tank:fav", size: 28.0, active: t.isfavorite) {
                => model.setTankFavoriteOnDetail(t.id, !t.isfavorite)
            }
            GhostIconButton(GhostGlyph.AddTank, "tank:addarchives", size: 28.0) {=> addOpen.value = true }
            GhostIconButton(GhostGlyph.Named(IconName.Pencil), "tank:edit", size: 28.0) {
                => model.openTankMetadataEditor(t.id)
            }
            DangerIconButton(GhostGlyph.Named(IconName.Trash), "tank:delete", size: 28.0) {
                => delOpen.value = true
            }
            GhostIconButton(GhostGlyph.Ellipsis, "tank:more", size: 28.0) {
                => model.todoToast(model.t("detail.moreActions"))
            }
    }

    // 成员筛选 memo（#9）：仅在 (筛选词, tankMembers 代次) 变化时重算全量小写化匹配，
    // 封面到货等无关状态写引发的重建直接命中缓存，万级成员合集不再每帧 O(n) 过滤。
    let filterMemo = rememberState<MemberFilterMemo>("detail:tank:member-filter", {=> MemberFilterMemo()}).value

    // 主列：收录档案（网格/列表切换 + 即时筛选 + 计数）→ 相关推荐（无数据隐藏）
    // 多选入口对齐 frontend：成员区无显式按钮，由卡片 hover 浮层勾选钮 / 列表行首
    // 勾选圆圈进入（onEnterMemberSelection 记录选择归属再 enterSelection）。
    let onEnterMemberSelection: (String) -> Unit = {
        arcid =>
            detailSelectionOwner = t.id
            model.enterSelection(arcid)
    }
    let mainCards = ArrayList<() -> Unit>()
    if (members.size > 0) {
        mainCards.add({
            => detailCard(model, model.t("detail.includedArchives"), count: "${members.size}", tools: {
                => HStack {
                    TextField(model.tankFilter, key: "tank-filter").width(130.vp)
                    MiniSeg([model.t("detail.grid"), model.t("detail.list")], model.tankMemberViewIndex,
                        key: "mb-seg")
                }.spacing(8.vp).hug()
            }) {
                =>
                    let shown = filteredMembers(model, filterMemo)
                    if (shown.size == 0) {
                        Label(model.t("detail.noMatch")).fontSize(12.fp).muted()
                    } else if (model.tankMemberViewIndex.value == 1) {
                        memberListContent(model, shown, onEnterMemberSelection)
                    } else {
                        memberGridContent(model, shown, onEnterMemberSelection)
                    }
                    // 选择模式批量栏（成员区底部）：已选计数 + 收藏/取消收藏/移除/删除/退出。
                    if (model.selectionMode.value) {
                        tankMemberBatchBar(model, removeOpen, batchDelOpen)
                    }
            }
        })
    }
    if (model.tankRelated.value.size > 0) {
        mainCards.add({
            => detailCard(model, model.t("detail.related")) {
                => tankCardRow(model, model.tankRelated.value, "tank-related")
            }
        })
    }

    // 侧栏：进度大卡（大数字 + 已读完 N 个）→ 基础信息 → 标签分组
    let done = countFinishedMembers(members)
    let sideCards = ArrayList<() -> Unit>()
    sideCards.add({=> progressCard(model, "${pct}%", model.t("detail.collectionProgress",
        params: [("count", "${t.archiveCount}"), ("done", "${done}")]), pct)})
    sideCards.add({
        => detailCard(model, model.t("detail.basicInfo")) {=> infoList(model, tankInfoRows(model, t))}
    })
    if (t.tags.size > 0) {
        sideCards.add({
            => detailCard(model, model.t("detail.tags")) {=> tagGroups(model, t.tags)}
        })
    }

    let backdropKey = if (t.coverAssetId > 0) {
        "backdrop:tank:${t.id}"
    } else {
        ""
    }
    detailSkeleton(model, backdropKey, hero, t.coverAssetId, actionIcons, mainCards.toArray(), sideCards.toArray(),
        tank: true)
    // 弹窗与页面同根兄弟挂载（Modal 零尺寸，不占布局）。
    tankAddArchivesDialog(model, addOpen, t.id)
    confirmModal(model, delOpen, model.t("detail.deleteCollectionTitle"), model.t("detail.deleteCollectionDetail",
        params: [("title", t.name)]), model.t("detail.delete"), {
        => model.deleteCurrentTank(t.id)
    })
    confirmModal(model, removeOpen, model.t("detail.removeTitle"), model.t("detail.removeDetail",
        params: [("count", "${model.selectedCount()}")]), model.t("detail.remove"), {
        =>
            model.removeTankMembers(t.id, selectedArcidList(model))
            model.exitSelection()
            detailSelectionOwner = ""
    })
    confirmModal(model, batchDelOpen, model.t("detail.deleteSelectedTitle"), model.t("detail.deleteSelectedDetail",
        params: [("count", "${model.selectedCount()}")]), model.t("detail.delete"), {
        =>
            model.batchDelete(selectedArcidList(model), ArrayList<String>())
            detailSelectionOwner = ""
    })
}

// ---- 合集成员多选批量栏 ----

// 已选档案 id 列表（tank 成员均为档案 id，无需按 isTankItem 拆分）。
private func selectedArcidList(model: AppModel): ArrayList<String> {
    let ids = ArrayList<String>()
    for (id in model.selectedIds.value) {
        ids.add(id)
    }
    ids
}

// 选择模式批量操作栏：已选计数 + 收藏/取消收藏/从合集移除/删除/退出。
// 移除/删除为 destructive 动作，先落确认框（open 状态由 tankDetailBody 持有）。
private func tankMemberBatchBar(model: AppModel, removeOpen: State<Bool>,
    batchDelOpen: State<Bool>): Unit {
    let elev = if (model.isLight()) { LANLU_L_PANEL } else { LANLU_PANEL }
    HStack {
        Label(model.t("detail.selected", params: [("count", "${model.selectedCount()}")])).fontSize(12.fp)
        Spacer()
        Button(model.t("detail.favorite"), {=> model.batchFavorite(selectedArcidList(model), ArrayList<String>(), true) })
            .style(ghostStyleOf(model))
        Button(model.t("detail.unfavorite"), {=> model.batchFavorite(selectedArcidList(model), ArrayList<String>(), false) })
            .style(ghostStyleOf(model))
        Button(model.t("detail.removeFromCollection"), {=> removeOpen.value = true }).style(ghostStyleOf(model))
        Button(model.t("detail.delete"), {=> batchDelOpen.value = true }).role(ButtonRole.Danger)
        Button(model.t("detail.exit"), {
            =>
                model.exitSelection()
                detailSelectionOwner = ""
        }).style(ghostStyleOf(model))
    }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().fillWidth()
        .padding(10.vp).background(elev, 10.vp)
}

// 成员筛选 memo 缓存（rememberState 跨帧保留）：结果仅在筛选词或成员代次变化时重算。
class MemberFilterMemo {
    var filter: String = ""
    var revision: UInt64 = 0
    var inited: Bool = false
    var result: Array<SearchItem> = []
}

// 成员即时筛选：标题包含（ASCII 大小写不敏感；空串返回全部）。
// 按 (tankFilter.value, tankMembers.revision) memo：成员列表只在 dispatch 整体重赋值时
// 推进代次（model 契约），筛选词与成员都未变时直接返回上次结果（评审 #9）。
private func filteredMembers(model: AppModel, memo: MemberFilterMemo): Array<SearchItem> {
    let filter = model.tankFilter.value.trimAscii()
    let revision = model.tankMembers.revision
    if (memo.inited && memo.filter == filter && memo.revision == revision) {
        return memo.result
    }
    let members = model.tankMembers.value
    let result = if (filter.size == 0) {
        members.toArray()
    } else {
        let lf = filter.toAsciiLower()
        let list = ArrayList<SearchItem>()
        for (it in members) {
            if (it.title.toAsciiLower().contains(lf)) {
                list.add(it)
            }
        }
        list.toArray()
    }
    memo.filter = filter
    memo.revision = revision
    memo.inited = true
    memo.result = result
    result
}

// 已读完成员数（progress >= pagecount），侧栏「已读完 N 个」。
private func countFinishedMembers(members: ArrayList<SearchItem>): Int64 {
    var n: Int64 = 0
    for (it in members) {
        if (it.pagecount > 0 && it.progress >= it.pagecount) {
            n++
        }
    }
    n
}

// ---- 数据装配辅助 ----

// 简介单行化：服务端 description 可能含换行符；cui Label 的 wrapText 不按 '\n' 分行
// （按宽度折行），但 SDL_ttf 绘制时会渲染换行——视觉行数超过 maxLines 量测的行高，
// 文本溢出与下方标签 chips 重叠（实机反馈）。换行/制表折叠为单个空格，对齐设计稿
// `.summary` 单行段落 + line-clamp:3 的行为。
private func oneLineSummary(s: String): String {
    let sb = StringBuilder()
    var pendingSpace = false
    for (r in s.runes()) {
        if (r == r'\n' || r == r'\r' || r == r'\t') {
            pendingSpace = true
        } else {
            if (pendingSpace && sb.size > 0) {
                sb.append(r' ')
            }
            pendingSpace = false
            sb.append(r)
        }
    }
    sb.toString()
}

private func readButtonLabel(model: AppModel, m: ArchiveMeta): String {
    if (m.progress <= 0) {
        return model.t("detail.startReading")
    }
    if (m.progress >= m.pagecount) {
        return model.t("detail.readAgain")
    }
    model.t("detail.continueReading", params: [("page", "${m.progress + 1}")])
}

// 档案 meta 行（原型：48 页 · 96.2 MB · 发布于 … · 更新于 …）。
private func archiveMetaLine(model: AppModel, m: ArchiveMeta): String {
    var s = ""
    if (m.pagecount > 0) {
        s = model.t("detail.pages", params: [("count", "${m.pagecount}")])
    }
    if (m.size > 0) {
        s = joinMeta(s, formatSize(m.size))
    }
    if (m.release_at > 0) {
        s = joinMeta(s, model.t("detail.releasedAt", params: [("date", formatTimestamp(m.release_at))]))
    }
    if (m.updated_at > 0) {
        s = joinMeta(s, model.t("detail.updatedAt", params: [("date", formatTimestamp(m.updated_at))]))
    }
    s
}

// 合集 meta 行（原型：12 个档案 · 共 486 页 · 更新于 …）。
private func tankMetaLine(model: AppModel, t: TankoubonInfo): String {
    var s = model.t("detail.collectionMeta", params: [("archives", "${t.archiveCount}"),
        ("pages", "${t.totalPages}")])
    if (t.updatedAt.size > 0) {
        s = joinMeta(s, model.t("detail.updatedAt", params: [("date", tankDate(t.updatedAt))]))
    }
    s
}

private func joinMeta(a: String, b: String): String {
    if (a.size == 0) {
        return b
    }
    "${a} · ${b}"
}

// 档案基础信息行（原型 info-list：文件名/大小/页数/路径/来源/发布日期/添加时间/最近阅读；
// 「更新时间」「状态」「文件类型」为保留的额外行，置尾）。路径/来源无数据即隐藏。
private func archiveInfoRows(model: AppModel, m: ArchiveMeta,
    pages: ArrayList<PageInfo>): Array<(String, String)> {
    let rows = ArrayList<(String, String)>()
    if (m.filename.size > 0) {
        rows.add((model.t("detail.filename"), m.filename))
    }
    if (m.size > 0) {
        rows.add((model.t("detail.size"), formatSize(m.size)))
    }
    rows.add((model.t("detail.pageCount"), pageStatText(model, m.pagecount, pages)))
    if (m.relativePath.size > 0) {
        rows.add((model.t("detail.path"), m.relativePath))
    }
    let ns = sourceNamespace(m.arcid)
    if (ns.size > 0) {
        rows.add((model.t("detail.source"), model.t("detail.pluginSource", params: [("name", ns)])))
    }
    if (m.release_at > 0) {
        rows.add((model.t("detail.releaseDate"), formatTimestamp(m.release_at)))
    }
    if (m.created_at > 0) {
        rows.add((model.t("detail.addedAt"), formatTimestamp(m.created_at)))
    }
    if (m.lastreadtime > 0) {
        rows.add((model.t("detail.lastRead"), formatTimestamp(m.lastreadtime)))
    }
    if (m.updated_at > 0) {
        rows.add((model.t("detail.updatedTime"), formatTimestamp(m.updated_at)))
    }
    rows.add((model.t("detail.status"), if (m.isnew) {
            model.t("detail.unread")
        } else {
            model.t("detail.read")
        }))
    if (m.archivetype.size > 0) {
        rows.add((model.t("detail.fileType"), m.archivetype))
    }
    rows.toArray()
}

// 页数行：「48（图像 44 · 视频 2 · 音频 1 · 文本 1）」；无页表或无统计时仅总页数。
private func pageStatText(model: AppModel, pagecount: Int64, pages: ArrayList<PageInfo>): String {
    if (pages.size == 0) {
        return "${pagecount}"
    }
    // 与 net.statPages 同口径按 pageType 计数；此处直接遍历 ArrayList——页表可达千级，
    // 若为调 statPages（签名要 Array）每帧 toArray 一次，恰是评审 #29 要消掉的拷贝。
    var image: Int64 = 0
    var video: Int64 = 0
    var audio: Int64 = 0
    var html: Int64 = 0
    for (p in pages) {
        match (p.pageType) {
            case "image" => image += 1
            case "video" => video += 1
            case "audio" => audio += 1
            case "html" => html += 1
            case _ => ()
        }
    }
    let parts = ArrayList<String>()
    if (image > 0) {
        parts.add(model.t("detail.imageCount", params: [("count", "${image}")]))
    }
    if (video > 0) {
        parts.add(model.t("detail.videoCount", params: [("count", "${video}")]))
    }
    if (audio > 0) {
        parts.add(model.t("detail.audioCount", params: [("count", "${audio}")]))
    }
    if (html > 0) {
        parts.add(model.t("detail.textCount", params: [("count", "${html}")]))
    }
    if (parts.size == 0) {
        return "${pagecount}"
    }
    var inner = parts[0]
    for (i in 1..parts.size) {
        inner = "${inner} · ${parts[i]}"
    }
    model.t("detail.pageBreakdown", params: [("total", "${pagecount}"), ("details", inner)])
}

// 合集基础信息行（原型 infoTank：名称/档案数/总页数/创建/更新）。
private func tankInfoRows(model: AppModel, t: TankoubonInfo): Array<(String, String)> {
    let rows = ArrayList<(String, String)>()
    rows.add((model.t("detail.name"), t.name))
    rows.add((model.t("detail.archiveCount"), "${t.archiveCount}"))
    rows.add((model.t("detail.totalPages"), "${t.totalPages}"))
    rows.add((model.t("detail.cover"), if (t.coverAssetId > 0) {
            model.t("detail.custom")
        } else {
            model.t("detail.automatic")
        }))
    if (t.createdAt.size > 0) {
        rows.add((model.t("detail.createdAt"), tankDate(t.createdAt)))
    }
    if (t.updatedAt.size > 0) {
        rows.add((model.t("detail.updatedTime"), tankDate(t.updatedAt)))
    }
    rows.toArray()
}

// 合集时间戳（postgres TEXT，如 "2024-06-12 10:30:00"）取日期段。
private func tankDate(s: String): String {
    if (s.size >= 10) {
        return s[0..10]
    }
    s
}

private func formatSize(bytes: Int64): String {
    if (bytes >= 1073741824) {
        return "${bytes / 1048576 / 1024}.${(bytes / 1048576) % 1024 / 100} GB"
    }
    if (bytes >= 1048576) {
        return "${bytes / 1048576} MB"
    }
    if (bytes >= 1024) {
        return "${bytes / 1024} KB"
    }
    "${bytes} B"
}
