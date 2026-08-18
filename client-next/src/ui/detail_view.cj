package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.{formatTimestamp, sourceNamespace, ArchiveMeta, ArchivePageView, TankoubonInfo, SearchItem,
    SearchItemProjectionView, SearchItemView}
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
        let radius: Float32 = if (size >= 34.0) {
            9.0
        } else {
            8.0
        }
        if (hovered) {
            ctx.renderer.fillRoundedRect(frame, radius, Color.rgba(0xE0, 0x5D, 0x5D, 30))
        }
        drawGhostGlyph(ctx.renderer, glyph, frame.centerX(), frame.centerY(), Color.rgb(0xE0, 0x5D, 0x5D))
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

private class DetailMenuAction {
    let label: String
    let enabled: Bool
    let danger: Bool
    let action: () -> Unit
    init(label: String, action: () -> Unit, enabled!: Bool = true, danger!: Bool = false) {
        this.label = label
        this.action = action
        this.enabled = enabled
        this.danger = danger
    }
}

// 详情操作卡在管理员态最多有 6 个图标：2xl 直出全部；常规桌面宽度保留
// 3 个高频动作 + “更多”；真正窄屏才只保留“更多”。
private let DETAIL_INLINE_ACTIONS_MIN_WIDTH: Int64 = 1536
private let DETAIL_COMPACT_ACTIONS_MIN_WIDTH: Int64 = 900

// 窄屏“更多”是可交互 overlay 菜单：点击外部/Esc 关闭，方向键与 Enter 可操作；
// 宽屏不构建它，所有允许动作直接显示在操作卡里。
private class DetailMoreButton <: Widget {
    private let owner: String
    private let hoverId: String
    private let actions: Array<DetailMenuAction>
    private let open: State<Bool>
    private let highlight: State<Int64>
    private var frame = Rect.zero()

    init(key: String, actions: Array<DetailMenuAction>) {
        owner = "detail-more:${key}"
        hoverId = "${owner}:button"
        this.actions = actions
        open = rememberState<Bool>("${owner}:open", {=> false})
        highlight = rememberState<Int64>("${owner}:highlight", {=> 0})
        emit(this)
    }

    public func measure(_: UiContext, _: Size): Size {
        Size(28.0, 28.0)
    }
    public func layout(_: UiContext, rect: Rect): Unit {
        frame = rect
    }

    public func draw(ctx: UiContext): Unit {
        if (ctx.isHovered(hoverId) || open.value) {
            ctx.renderer.fillRoundedRect(frame, 8.0, ctx.theme.overlayHover)
        }
        drawGhostGlyph(ctx.renderer, GhostGlyph.Ellipsis, frame.centerX(), frame.centerY(), ctx.theme.text)
        if (open.value && actions.size > 0) {
            let menu = popupRect(ctx)
            ctx.setOverlay(
                Overlay(owner: owner, handleEvent: {c, e => handlePopup(c, e, menu)}, render: {c => drawPopup(c, menu)}))
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
                    open.value = !open.value
                    highlight.value = firstEnabled()
                    return true
                }
            case _ => ()
        }
        false
    }

    private func popupRect(ctx: UiContext): Rect {
        let w: Float32 = 190.0
        let h = Float32(actions.size) * 36.0 + 10.0
        let x = max(4.0, min(frame.right() - w, ctx.viewportWidth - w - 4.0))
        var y = frame.bottom() + 4.0
        if (y + h > ctx.viewportHeight - 4.0) {
            y = max(4.0, frame.y - h - 4.0)
        }
        Rect(x, y, w, h)
    }

    private func drawPopup(ctx: UiContext, menu: Rect): Unit {
        ctx.renderer.fillRoundedRect(menu, 10.0, ctx.theme.panelRaised)
        ctx.renderer.strokeRoundedRect(menu.inset(0.5), 9.5, Pen(width: 1.0, color: ctx.theme.panelEdge))
        var y = menu.y + 5.0
        for (i in 0..actions.size) {
            let item = actions[i]
            let row = Rect(menu.x + 5.0, y, menu.w - 10.0, 36.0)
            if (i == highlight.value && item.enabled) {
                ctx.renderer.fillRoundedRect(row, 7.0, ctx.theme.overlayHover)
            }
            let color = if (!item.enabled) {
                ctx.theme.mutedText
            } else if (item.danger) {
                Color.rgb(0xE0, 0x5D, 0x5D)
            } else {
                ctx.theme.text
            }
            let th = ctx.renderer.textHeight(pointSize: 12.0)
            ctx.renderer.text(item.label, row.x + 10.0, row.centerY() - th / 2.0, color, pointSize: 12.0)
            y += 36.0
        }
    }

    private func handlePopup(ctx: UiContext, event: UiEvent, menu: Rect): Bool {
        match (event) {
            case UiEvent.MouseMove(x, y) =>
                if (menu.contains(x, y)) {
                    let i = Int64((y - menu.y - 5.0) / 36.0)
                    if (i >= 0 && i < actions.size && actions[i].enabled) {
                        highlight.value = i
                    }
                    ctx.claimHover(owner, CursorShape.Default)
                }
                false
            case UiEvent.MouseDown(MouseButton.Left, x, y) =>
                if (menu.contains(x, y)) {
                    run(ctx, Int64((y - menu.y - 5.0) / 36.0))
                } else {
                    close(ctx)
                }
                true
            case UiEvent.MouseDown(_, _, _) =>
                close(ctx);
                true
            case UiEvent.KeyDown(Key.Escape, _) =>
                close(ctx);
                true
            case UiEvent.KeyDown(Key.Enter, _) =>
                run(ctx, highlight.value);
                true
            case UiEvent.KeyDown(Key.Down, _) =>
                moveHighlight(1);
                true
            case UiEvent.KeyDown(Key.Up, _) =>
                moveHighlight(-1);
                true
            case _ => false
        }
    }

    private func run(ctx: UiContext, i: Int64): Unit {
        close(ctx)
        if (i >= 0 && i < actions.size && actions[i].enabled) {
            actions[i].action()
        }
    }
    private func close(ctx: UiContext): Unit {
        open.value = false
        ctx.removeOverlay(owner)
    }
    private func firstEnabled(): Int64 {
        for (i in 0..actions.size) {
            if (actions[i].enabled) {
                return i
            }
        }
        0
    }
    private func moveHighlight(direction: Int64): Unit {
        var i = highlight.value + direction
        while (i >= 0 && i < actions.size) {
            if (actions[i].enabled) {
                highlight.value = i
                return
            }
            i += direction
        }
    }
}

public func detailView(model: AppModel): Unit {
    match (model.meta.value) {
        case None => match (model.page.value) {
            case Page.Detail(id) => detailLoadPanel(model, model.detailLoadState.value, model.detailLoadError.value,
                {=> model.retryDetail(id)})
            case _ => Panel {Label(model.t("common.loading")).muted()}
        }
        case Some(m) => archiveDetailBody(model, m)
    }
}

private func detailLoadPanel(model: AppModel, state: String, message: String, retry: () -> Unit): Unit {
    Panel {
        VStack {
            if (state == "error") {
                VStack {
                    Icon(IconName.Process, size: 28.vp).foregroundColor(Color.rgb(0xE0, 0x5D, 0x5D))
                    Label(if (message.size > 0) {
                        message
                    } else {
                        "加载失败"
                    }).muted().wrap()
                    Button("重试", retry).role(ButtonRole.Primary)
                }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
            } else {
                VStack {
                    Spinner(22.0, if (model.isLight()) {
                        LANLU_L_ACCENT
                    } else {
                        LANLU_ACCENT
                    })
                    Label(model.t("common.loading")).muted()
                }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug()
            }
        }.spacing(12.vp).crossAxisAlignment(CrossAxisAlignment.Center).hug().padding(28.vp)
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
    hero.clearlogoAssetId = m.clearlogoAssetId
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

    let isSource = sourceNamespace(m.arcid).size > 0
    let wideActions = model.windowWidth.value >= DETAIL_INLINE_ACTIONS_MIN_WIDTH
    let compactActions = model.windowWidth.value >= DETAIL_COMPACT_ACTIONS_MIN_WIDTH
    let download: () -> Unit = {=> beginArchiveDownload(model, m)}
    let toggleRead: () -> Unit = {=> model.toggleIsNew(m.arcid, !m.isnew)}
    let moreActions = ArrayList<DetailMenuAction>()
    let overflowActions = ArrayList<DetailMenuAction>()
    moreActions.add(DetailMenuAction(model.t("detail.download"), download, enabled: !isSource || model.isAdmin.value))
    if (!isSource) {
        moreActions.add(DetailMenuAction(model.t("detail.favorite"), {
            => model.toggleFavorite(m.arcid, !m.isfavorite)
        }))
    }
    if (!isSource) {
        let readAction = DetailMenuAction(if (m.isnew) {
            "标为已读"
        } else {
            "标为未读"
        }, toggleRead)
        moreActions.add(readAction)
        moreActions.add(DetailMenuAction("加入合集", {=> addTankOpen.value = true}))
        let editAction = DetailMenuAction("编辑", {=> model.openArchiveMetadataEditor(m.arcid)})
        moreActions.add(editAction)
        overflowActions.add(readAction)
        overflowActions.add(editAction)
        if (model.isAdmin.value) {
            let deleteAction = DetailMenuAction(model.t("detail.delete"), {=> delOpen.value = true}, danger: true)
            moreActions.add(deleteAction)
            overflowActions.add(deleteAction)
        }
    }

    let actionIcons: () -> Unit = {
        => if (wideActions) {
            if (!isSource) {
                GhostIconButton(GhostGlyph.AddTank, "detail:addtank", size: 28.0) {=> addTankOpen.value = true}
                GhostIconButton(GhostGlyph.Heart, "detail:fav", size: 28.0, active: m.isfavorite) {
                    => model.toggleFavorite(m.arcid, !m.isfavorite)
                }
            }
            if (!isSource || model.isAdmin.value) {
                GhostIconButton(GhostGlyph.Download, "detail:download", size: 28.0, onClick: download)
            }
            if (!isSource) {
                GhostIconButton(if (m.isnew) {
                    GhostGlyph.Named(IconName.Check)
                } else {
                    GhostGlyph.Named(IconName.Refresh)
                }, "detail:read-status", size: 28.0, onClick: toggleRead)
                GhostIconButton(GhostGlyph.Named(IconName.Pencil), "detail:edit", size: 28.0) {
                    => model.openArchiveMetadataEditor(m.arcid)
                }
                if (model.isAdmin.value) {
                    DangerIconButton(GhostGlyph.Named(IconName.Trash), "detail:delete", size: 28.0) {
                        => delOpen.value = true
                    }
                }
            }
        } else if (compactActions) {
            if (!isSource) {
                GhostIconButton(GhostGlyph.AddTank, "detail:addtank", size: 28.0) {=> addTankOpen.value = true}
                GhostIconButton(GhostGlyph.Heart, "detail:fav", size: 28.0, active: m.isfavorite) {
                    => model.toggleFavorite(m.arcid, !m.isfavorite)
                }
            }
            if (!isSource || model.isAdmin.value) {
                GhostIconButton(GhostGlyph.Download, "detail:download", size: 28.0, onClick: download)
            }
            if (overflowActions.size > 0) {
                DetailMoreButton("archive:${m.arcid}:overflow", overflowActions.toArray())
            }
        } else {
            DetailMoreButton("archive:${m.arcid}", moreActions.toArray())
        }
    }

    // 主列：页面预览（到货才显示）→ 所属合集（无数据隐藏）→ 相关推荐（无数据隐藏）
    let mainCards = ArrayList<() -> Unit>()
    if (model.detailPagesState.value != "idle") {
        mainCards.add({
            => detailCard(model, model.t("detail.pagePreview"),
                count: model.t("detail.pages", params: [("count", "${model.detailPages.value.size}")]), tools: {
                    => MiniSeg([model.t("detail.thumbnails"), model.t("detail.list"), model.t("detail.tree")],
                        model.pageViewIndex, key: "pv-seg")
                }) {
                => if (model.detailPagesState.value == "loading") {
                    Label(model.t("common.loading")).fontSize(12.fp).muted().padding(12.vp)
                } else if (model.detailPagesState.value == "error") {
                    VStack {
                        Label(if (model.detailPagesError.value.size > 0) {
                            model.detailPagesError.value
                        } else {
                            "页面预览加载失败"
                        }).fontSize(12.fp).muted().wrap()
                        Button("重试", {=> model.retryDetail(m.arcid)}).style(ghostStyleOf(model))
                    }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().padding(12.vp)
                } else if (model.detailPages.value.size == 0) {
                    Label("这个档案没有可预览页面").fontSize(12.fp).muted().padding(12.vp)
                } else {
                    pagePreview(model, m.arcid, model.detailPages.value, m.progress) {
                        no => model.openReader(m.arcid, no)
                    }
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
                => cardRow(model, "related", model.relatedItems.value, 132.0, 238.0,
                    recommendationScene: "archive_related", seedType: "archive", seedId: m.arcid)
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
    confirmModal(model, delOpen, model.t("detail.deleteArchiveTitle"),
        model.t("detail.deleteArchiveDetail", params: [("title", m.title)]), model.t("detail.delete"), {
            => model.deleteArchive(m.arcid)
        })
}

// ---- 合集详情 ----

public func tankView(model: AppModel): Unit {
    match (model.tank.value) {
        case None => match (model.page.value) {
            case Page.Tank(id) => detailLoadPanel(model, model.tankLoadState.value, model.tankLoadError.value,
                {=> model.retryTank(id)})
            case _ => Panel {Label(model.t("common.loading")).muted()}
        }
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
    let batchEditOpen = rememberState<Bool>("tank.batchEditOpen:${t.id}", {=> false})
    let batchAddTags = rememberState<String>("tank.batchAddTags:${t.id}", {=> ""})
    let batchRemoveTags = rememberState<String>("tank.batchRemoveTags:${t.id}", {=> ""})
    let batchSummary = rememberState<String>("tank.batchSummary:${t.id}", {=> ""})
    let members = model.tankMembers.value
    let pct = tankReadPct(t)
    let hero = DetailHeroData()
    hero.badges = [model.t("detail.collectionBadge")]
    hero.title = t.name
    hero.clearlogoAssetId = t.clearlogoAssetId
    hero.metaLine = tankMetaLine(model, t)
    hero.progressPct = pct
    hero.progressText = model.t("detail.readPercent", params: [("percent", "${pct}")])
    hero.summary = oneLineSummary(t.description)
    hero.tags = t.tags
    hero.primaryLabel = "添加档案"
    hero.primaryEnabled = true
    hero.onPrimary = {=> addOpen.value = true}
    let wideActions = model.windowWidth.value >= DETAIL_INLINE_ACTIONS_MIN_WIDTH
    let compactActions = model.windowWidth.value >= DETAIL_COMPACT_ACTIONS_MIN_WIDTH
    let tankSource = sourceNamespace(t.id).size > 0
    let moreActions = ArrayList<DetailMenuAction>()
    if (!tankSource) {
        moreActions.add(
            DetailMenuAction(if (t.isfavorite) {
                model.t("detail.unfavorite")
            } else {
                model.t("detail.favorite")
            }, {=> model.setTankFavoriteOnDetail(t.id, !t.isfavorite)}))
        moreActions.add(DetailMenuAction("编辑", {=> model.openTankMetadataEditor(t.id)}))
        if (model.isAdmin.value) {
            moreActions.add(DetailMenuAction(model.t("detail.delete"), {=> delOpen.value = true}, danger: true))
        }
    }

    let actionIcons: () -> Unit = {
        => if (wideActions || compactActions) {
            if (!tankSource) {
                GhostIconButton(GhostGlyph.Heart, "tank:fav", size: 28.0, active: t.isfavorite) {
                    => model.setTankFavoriteOnDetail(t.id, !t.isfavorite)
                }
                GhostIconButton(GhostGlyph.Named(IconName.Pencil), "tank:edit", size: 28.0) {
                    => model.openTankMetadataEditor(t.id)
                }
                if (model.isAdmin.value) {
                    DangerIconButton(GhostGlyph.Named(IconName.Trash), "tank:delete", size: 28.0) {
                        => delOpen.value = true
                    }
                }
            }
        } else {
            DetailMoreButton("tank:${t.id}", moreActions.toArray())
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
    mainCards.add({
        => detailCard(model, model.t("detail.includedArchives"), count: "${members.size}", tools: {
            => HStack {
                TextField(model.tankFilter, key: "tank-filter").width(130.vp)
                MiniSeg([model.t("detail.grid"), model.t("detail.list")], model.tankMemberViewIndex, key: "mb-seg")
            }.spacing(8.vp).hug()
        }) {
            => if (model.tankMembersState.value == "loading") {
                HStack {
                    Spinner(16.0, if (model.isLight()) {
                        LANLU_L_ACCENT
                    } else {
                        LANLU_ACCENT
                    })
                    Label(model.t("common.loading")).muted()
                }.spacing(8.vp).hug().padding(12.vp)
            } else if (model.tankMembersState.value == "error") {
                VStack {
                    Label(if (model.tankMembersError.value.size > 0) {
                        model.tankMembersError.value
                    } else {
                        "成员加载失败"
                    }).muted().wrap()
                    Button("重试", {=> model.retryTank(t.id)}).style(ghostStyleOf(model))
                }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().padding(12.vp)
            } else if (members.size == 0) {
                VStack {
                    Label("这个合集还没有档案").fontSize(13.fp)
                    Label("添加档案后即可阅读、排序和执行批量操作。 ").fontSize(11.fp).muted()
                    Button("添加档案", {=> addOpen.value = true}).role(ButtonRole.Primary)
                }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Start).hug().padding(12.vp)
            } else {
                let shown = filteredMembers(model, filterMemo)
                if (shown.size == 0) {
                    Label(model.t("detail.noMatch")).fontSize(12.fp).muted()
                } else if (model.tankMemberViewIndex.value == 1) {
                    memberListContent(model, shown, onEnterMemberSelection, {
                        id => model.removeTankMembers(t.id, oneArcid(id))
                    })
                } else {
                    memberGridContent(model, shown, onEnterMemberSelection, {
                        id => model.removeTankMembers(t.id, oneArcid(id))
                    })
                }
                if (model.selectionMode.value) {
                    tankMemberBatchBar(model, members, removeOpen, batchDelOpen, batchEditOpen)
                }
            }
        }
    })
    if (model.tankRelated.value.size > 0) {
        mainCards.add({
            => detailCard(model, model.t("detail.related")) {
                => tankCardRow(model, model.tankRelated.value, "tank-related", recommendationScene: "tankoubon_related",
                    seedType: "tankoubon", seedId: t.id)
            }
        })
    }

    // 侧栏：进度大卡（大数字 + 已读完 N 个）→ 基础信息 → 标签分组
    let done = countFinishedMembers(members)
    let sideCards = ArrayList<() -> Unit>()
    sideCards.add({
        => progressCard(model, "${pct}%",
            model.t("detail.collectionProgress", params: [("count", "${t.archiveCount}"), ("done", "${done}")]), pct)
    })
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
    confirmModal(model, delOpen, model.t("detail.deleteCollectionTitle"),
        model.t("detail.deleteCollectionDetail", params: [("title", t.name)]), model.t("detail.delete"), {
            => model.deleteCurrentTank(t.id)
        })
    confirmModal(
        model,
        removeOpen,
        model.t("detail.removeTitle"),
        model.t("detail.removeDetail", params: [("count", "${model.selectedCount()}")]),
        model.t("detail.remove"),
        {
            =>
                model.removeTankMembers(t.id, selectedArcidList(model))
                model.exitSelection()
                detailSelectionOwner = ""
        }
    )
    confirmModal(
        model,
        batchDelOpen,
        model.t("detail.deleteSelectedTitle"),
        model.t("detail.deleteSelectedDetail", params: [("count", "${model.selectedCount()}")]),
        model.t("detail.delete"),
        {
            =>
                model.batchDelete(selectedArcidList(model), ArrayList<String>())
                detailSelectionOwner = ""
        }
    )
    batchMemberEditModal(model, batchEditOpen, batchAddTags, batchRemoveTags, batchSummary)
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

private func oneArcid(id: String): ArrayList<String> {
    let out = ArrayList<String>()
    out.add(id)
    out
}

// 选择模式批量操作栏：已选计数 + 收藏/取消收藏/从合集移除/删除/退出。
// 移除/删除为 destructive 动作，先落确认框（open 状态由 tankDetailBody 持有）。
private func tankMemberBatchBar(model: AppModel, members: SearchItemView, removeOpen: State<Bool>,
    batchDelOpen: State<Bool>, batchEditOpen: State<Bool>): Unit {
    let elev = if (model.isLight()) {
        LANLU_L_PANEL
    } else {
        LANLU_PANEL
    }
    let selected = selectedArcidList(model)
    let allFavorite = selectedAll(model, members, {it => it.isfavorite})
    let allNew = selectedAll(model, members, {it => it.isnew})
    HStack {
        Label(model.t("detail.selected", params: [("count", "${model.selectedCount()}")])).fontSize(12.fp)
        Spacer()
        Button(if (allFavorite) {
            model.t("detail.unfavorite")
        } else {
            model.t("detail.favorite")
        }, {
            => model.batchFavorite(selected, ArrayList<String>(), !allFavorite)
        }).style(ghostStyleOf(model))
        Button(if (allNew) {
            "标为已读"
        } else {
            "标为未读"
        }, {
            => model.batchSetIsNew(selected, !allNew)
        }).style(ghostStyleOf(model))
        Button(
            "下载",
            {
                =>
                    let request = FileDialogs.openFolder()
                    model.beginBatchArchiveDownloadSelection(request, selected)
            }
        ).style(ghostStyleOf(model))
        Button("批量编辑", {=> batchEditOpen.value = true}).style(ghostStyleOf(model))
        Button(model.t("detail.removeFromCollection"), {=> removeOpen.value = true}).style(ghostStyleOf(model))
        if (model.isAdmin.value) {
            Button(model.t("detail.delete"), {=> batchDelOpen.value = true}).role(ButtonRole.Danger)
        }
        Button(
            model.t("detail.exit"),
            {
                =>
                    model.exitSelection()
                    detailSelectionOwner = ""
            }
        ).style(ghostStyleOf(model))
    }
        .spacing(8.vp)
        .crossAxisAlignment(CrossAxisAlignment.Center)
        .hug()
        .fillWidth()
        .padding(10.vp)
        .background(elev, 10.vp)
}

private func selectedAll(model: AppModel, members: SearchItemView, predicate: (SearchItem) -> Bool): Bool {
    if (model.selectedCount() == 0) {
        return false
    }
    var found: Int64 = 0
    for (item in members) {
        if (model.isSelected(item.arcid)) {
            found += 1
            if (!predicate(item)) {
                return false
            }
        }
    }
    found == model.selectedCount()
}

private func batchMemberEditModal(model: AppModel, open: State<Bool>, addTags: State<String>, removeTags: State<String>,
    summary: State<String>): Unit {
    Modal(open, onDismiss: {=> open.value = false}, body: {
        => VStack {
            Label("批量编辑 ${model.selectedCount()} 个档案").fontSize(15.fp)
            Label("只应用填写的增量；标签使用逗号分隔。 ").fontSize(11.fp).muted()
            Label("添加标签").fontSize(11.fp).muted()
            TextField(addTags, key: "tank.batch-edit.add-tags").fillWidth()
            Label("移除标签").fontSize(11.fp).muted()
            TextField(removeTags, key: "tank.batch-edit.remove-tags").fillWidth()
            Label("追加简介").fontSize(11.fp).muted()
            TextField(summary, key: "tank.batch-edit.summary").fillWidth()
            HStack {
                Spacer()
                Button("取消", {=> open.value = false}).style(ghostStyleOf(model))
                Button(
                    "应用",
                    {
                        =>
                            model.batchEditTankMembers(selectedArcidList(model), addTags.value, removeTags.value,
                                summary.value)
                            open.value = false
                            addTags.value = ""
                            removeTags.value = ""
                            summary.value = ""
                    }
                ).role(ButtonRole.Primary)
            }.spacing(8.vp).hug().fillWidth()
        }.spacing(8.vp).crossAxisAlignment(CrossAxisAlignment.Start).width(430.vp)
    })
}

// 成员筛选 memo 缓存（rememberState 跨帧保留）：结果仅在筛选词或成员代次变化时重算。
class MemberFilterMemo {
    var filter: String = ""
    var revision: UInt64 = 0
    var inited: Bool = false
    var result: SearchItemProjectionView = SearchItemProjectionView.all(SearchItemView.empty())
}

// 成员即时筛选：标题包含（ASCII 大小写不敏感；空串返回全部）。
// 按 (tankFilter.value, tankMembers.revision) memo：成员列表只在 dispatch 整体重赋值时
// 推进代次（model 契约），筛选词与成员都未变时直接返回上次结果（评审 #9）。
private func filteredMembers(model: AppModel, memo: MemberFilterMemo): SearchItemProjectionView {
    let filter = model.tankFilter.value.trimAscii()
    let revision = model.tankMembers.revision
    if (memo.inited && memo.filter == filter && memo.revision == revision) {
        return memo.result
    }
    let members = model.tankMembers.value
    let result = if (filter.size == 0) {
        SearchItemProjectionView.all(members)
    } else {
        let lf = filter.toAsciiLower()
        SearchItemProjectionView.filter(members, {
            it => it.title.toAsciiLower().contains(lf) || it.tagsCsv.toAsciiLower().contains(lf)
        })
    }
    memo.filter = filter
    memo.revision = revision
    memo.inited = true
    memo.result = result
    result
}

// 已读完成员数（progress >= pagecount），侧栏「已读完 N 个」。
private func countFinishedMembers(members: SearchItemView): Int64 {
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

private func beginArchiveDownload(model: AppModel, m: ArchiveMeta): Unit {
    if (sourceNamespace(m.arcid).size > 0) {
        model.startSourceArchiveDownload(m.arcid)
        return
    }
    let filename = if (m.filename.trimAscii().size > 0) {
        m.filename.trimAscii()
    } else {
        m.arcid
    }
    let request = FileDialogs.saveFile(options: FileDialogOptions(defaultLocation: Some(filename)))
    model.beginArchiveDownloadSelection(request, m.arcid)
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
    var s = model.t("detail.collectionMeta", params: [("archives", "${t.archiveCount}"), ("pages", "${t.totalPages}")])
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
private func archiveInfoRows(model: AppModel, m: ArchiveMeta, pages: ArchivePageView): Array<(String, String)> {
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
private func pageStatText(model: AppModel, pagecount: Int64, pages: ArchivePageView): String {
    if (pages.size == 0) {
        return "${pagecount}"
    }
    // 统计随 RocksDB 页表快照一次生成；视图重建不再遍历并解码整本页表。
    let image = pages.stats.image
    let video = pages.stats.video
    let audio = pages.stats.audio
    let html = pages.stats.html
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
