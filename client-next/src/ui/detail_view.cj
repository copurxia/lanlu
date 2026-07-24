package lanlu_client_next.ui

import cui.*
import lanlu_client_next.app.*
import lanlu_client_next.net.{formatTimestamp, sourceNamespace, ArchiveMeta, TankoubonInfo, SearchItem, PageInfo,
    statPages}
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

public func detailView(model: AppModel): Unit {
    match (model.meta.value) {
        case None => Panel {Label("加载中…").muted()}
        case Some(m) => archiveDetailBody(model, m)
    }
}

private func archiveDetailBody(model: AppModel, m: ArchiveMeta): Unit {
    let pct = memberReadPct(m.pagecount, m.progress)
    let hero = DetailHeroData()
    // 徽标行（原型：金「档案 · 图像」+ 灰「2024」「同人志」；蓝色「已完结」无数据字段不做）。
    // 年份自 release_at 推导；分类取首个 category: 前缀标签（无则不显示，不 mock）。NEW 红 pill 保留。
    let badgeList = ArrayList<String>()
    badgeList.add("档案 · ${m.archivetype}")
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
    hero.metaLine = archiveMetaLine(m)
    hero.progressPct = pct
    hero.progressText = "已读 ${pct}%"
    hero.summary = oneLineSummary(m.description)
    hero.tags = m.tags.toArray()
    hero.primaryLabel = readButtonLabel(m)
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
            // 下载/加入合集/编辑/更多动作留 TODO（T11 范围外）。
            GhostIconButton(GhostGlyph.Heart, "detail:fav", size: 28.0, active: m.isfavorite) {
                => model.toggleFavorite(m.arcid, !m.isfavorite)
            }
            GhostIconButton(GhostGlyph.Download, "detail:download", size: 28.0) {=> model.todoToast("下载")}
            GhostIconButton(GhostGlyph.AddTank, "detail:addtank", size: 28.0) {=> model.todoToast("加入合集")}
        GhostIconButton(GhostGlyph.Named(IconName.Pencil), "detail:edit", size: 28.0) {
            => model.todoToast("编辑")
        }
            GhostIconButton(GhostGlyph.Ellipsis, "detail:more", size: 28.0) {=> model.todoToast("更多操作")}
    }

    // 主列：页面预览（到货才显示）→ 所属合集（无数据隐藏）→ 相关推荐（无数据隐藏）
    let mainCards = ArrayList<() -> Unit>()
    if (model.detailPages.value.size > 0) {
        mainCards.add({
            => detailCard(model, "页面预览", count: "${model.detailPages.value.size} 页", tools: {
                => MiniSeg(["缩略图", "列表", "树"], model.pageViewIndex, key: "pv-seg")
            }) {
                => pagePreview(model, model.detailPages.value.toArray(), m.progress) {
                    no => model.openReader(m.arcid, no)
                }
            }
        })
    }
    if (model.parentTanks.value.size > 0) {
        mainCards.add({
            => detailCard(model, "所属合集", count: "${model.parentTanks.value.size}") {
                => tankCardRow(model, model.parentTanks.value.toArray(), "parent-tanks")
            }
        })
    }
    if (model.relatedItems.value.size > 0) {
        mainCards.add({
            => detailCard(model, "相关推荐") {
                => cardRow(model, "related", model.relatedItems.value.toArray(), 132.0, 238.0)
            }
        })
    }

    // 侧栏：进度大卡 → 基础信息（含 statPages 混合统计行）→ 标签分组
    let sideCards = ArrayList<() -> Unit>()
    let ofText = if (m.progress > 0) {
        "已读 ${m.progress} / ${m.pagecount} 页 · 上次读到 P.${m.progress}"
    } else {
        "${m.pagecount} 页 · 尚未开始阅读"
    }
    sideCards.add({=> progressCard(model, "${pct}%", ofText, pct)})
    sideCards.add({
        => detailCard(model, "基础信息") {
            => infoList(model, archiveInfoRows(m, model.detailPages.value.toArray()))
        }
    })
    if (m.tags.size > 0) {
        sideCards.add({
            => detailCard(model, "标签") {=> tagGroups(model, m.tags.toArray())}
        })
    }

    let backdropKey = if (m.coverAssetId > 0) {
        "backdrop:${m.arcid}"
    } else {
        ""
    }
    detailSkeleton(model, backdropKey, hero, m.coverAssetId, actionIcons, mainCards.toArray(), sideCards.toArray(),
        tank: false)
}

// ---- 合集详情 ----

public func tankView(model: AppModel): Unit {
    match (model.tank.value) {
        case None => Panel {Label("加载中…").muted()}
        case Some(t) => tankDetailBody(model, t)
    }
}

private func tankDetailBody(model: AppModel, t: TankoubonInfo): Unit {
    let members = model.tankMembers.value
    let pct = tankReadPct(t)
    let hero = DetailHeroData()
    hero.badges = ["合集"]
    hero.title = t.name
    hero.metaLine = tankMetaLine(t)
    hero.progressPct = pct
    hero.progressText = "已读 ${pct}%"
    hero.summary = oneLineSummary(t.description)
    hero.tags = t.tags.toArray()
    hero.primaryLabel = "▶ 从头开始阅读"
    hero.primaryEnabled = members.size > 0
    hero.onPrimary = {=> model.startTankReading()}

    let actionIcons: () -> Unit = {
        =>
            // 合集 3 图标（用户决定：不与档案同构；设计稿 tank 视图下载/加入合集为 only-archive）。
            // 收藏/编辑/更多动作留 TODO。矢量图标钮（28vp）。
            GhostIconButton(GhostGlyph.Heart, "tank:fav", size: 28.0) {=> model.todoToast("合集收藏")}
            GhostIconButton(GhostGlyph.Named(IconName.Pencil), "tank:edit", size: 28.0) {
                => model.todoToast("编辑")
            }
            GhostIconButton(GhostGlyph.Ellipsis, "tank:more", size: 28.0) {=> model.todoToast("更多操作")}
    }

    // 主列：收录档案（网格/列表切换 + 即时筛选 + 计数）→ 相关推荐（无数据隐藏）
    let mainCards = ArrayList<() -> Unit>()
    if (members.size > 0) {
        mainCards.add({
            => detailCard(model, "收录档案", count: "${members.size}", tools: {
                => HStack {
                    TextField(model.tankFilter, key: "tank-filter").width(130.vp)
                    MiniSeg(["网格", "列表"], model.tankMemberViewIndex, key: "mb-seg")
                }.spacing(8.vp).hug()
            }) {
                =>
                    let shown = filteredMembers(model)
                    if (shown.size == 0) {
                        Label("无匹配档案").fontSize(12.fp).muted()
                    } else if (model.tankMemberViewIndex.value == 1) {
                        memberListContent(model, shown)
                    } else {
                        memberGridContent(model, shown)
                    }
            }
        })
    }
    if (model.tankRelated.value.size > 0) {
        mainCards.add({
            => detailCard(model, "相关推荐") {
                => tankCardRow(model, model.tankRelated.value.toArray(), "tank-related")
            }
        })
    }

    // 侧栏：进度大卡（大数字 + 已读完 N 个）→ 基础信息 → 标签分组
    let done = countFinishedMembers(members)
    let sideCards = ArrayList<() -> Unit>()
    sideCards.add({=> progressCard(model, "${pct}%", "${t.archiveCount} 个档案 · 已读完 ${done} 个", pct)})
    sideCards.add({
        => detailCard(model, "基础信息") {=> infoList(model, tankInfoRows(t))}
    })
    if (t.tags.size > 0) {
        sideCards.add({
            => detailCard(model, "标签") {=> tagGroups(model, t.tags.toArray())}
        })
    }

    let backdropKey = if (t.coverAssetId > 0) {
        "backdrop:tank:${t.id}"
    } else {
        ""
    }
    detailSkeleton(model, backdropKey, hero, t.coverAssetId, actionIcons, mainCards.toArray(), sideCards.toArray(),
        tank: true)
}

// 成员即时筛选：标题包含（ASCII 大小写不敏感；空串返回全部）。
private func filteredMembers(model: AppModel): Array<SearchItem> {
    let filter = model.tankFilter.value.trimAscii()
    let members = model.tankMembers.value
    if (filter.size == 0) {
        return members.toArray()
    }
    let lf = filter.toAsciiLower()
    let list = ArrayList<SearchItem>()
    for (it in members) {
        if (it.title.toAsciiLower().contains(lf)) {
            list.add(it)
        }
    }
    list.toArray()
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

private func readButtonLabel(m: ArchiveMeta): String {
    if (m.progress <= 0) {
        return "▶ 开始阅读"
    }
    if (m.progress >= m.pagecount) {
        return "▶ 重新阅读"
    }
    "▶ 继续阅读 · P.${m.progress + 1}"
}

// 档案 meta 行（原型：48 页 · 96.2 MB · 发布于 … · 更新于 …）。
private func archiveMetaLine(m: ArchiveMeta): String {
    var s = ""
    if (m.pagecount > 0) {
        s = "${m.pagecount} 页"
    }
    if (m.size > 0) {
        s = joinMeta(s, formatSize(m.size))
    }
    if (m.release_at > 0) {
        s = joinMeta(s, "发布于 ${formatTimestamp(m.release_at)}")
    }
    if (m.updated_at > 0) {
        s = joinMeta(s, "更新于 ${formatTimestamp(m.updated_at)}")
    }
    s
}

// 合集 meta 行（原型：12 个档案 · 共 486 页 · 更新于 …）。
private func tankMetaLine(t: TankoubonInfo): String {
    var s = "${t.archiveCount} 个档案 · 共 ${t.totalPages} 页"
    if (t.updatedAt.size > 0) {
        s = joinMeta(s, "更新于 ${tankDate(t.updatedAt)}")
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
private func archiveInfoRows(m: ArchiveMeta, pages: Array<PageInfo>): Array<(String, String)> {
    let rows = ArrayList<(String, String)>()
    if (m.filename.size > 0) {
        rows.add(("文件名", m.filename))
    }
    if (m.size > 0) {
        rows.add(("大小", formatSize(m.size)))
    }
    rows.add(("页数", pageStatText(m.pagecount, pages)))
    if (m.relativePath.size > 0) {
        rows.add(("路径", m.relativePath))
    }
    let ns = sourceNamespace(m.arcid)
    if (ns.size > 0) {
        rows.add(("来源", "${ns} 插件"))
    }
    if (m.release_at > 0) {
        rows.add(("发布日期", formatTimestamp(m.release_at)))
    }
    if (m.created_at > 0) {
        rows.add(("添加时间", formatTimestamp(m.created_at)))
    }
    if (m.lastreadtime > 0) {
        rows.add(("最近阅读", formatTimestamp(m.lastreadtime)))
    }
    if (m.updated_at > 0) {
        rows.add(("更新时间", formatTimestamp(m.updated_at)))
    }
    rows.add(("状态", if (m.isnew) {
            "未读"
        } else {
            "已读"
        }))
    if (m.archivetype.size > 0) {
        rows.add(("文件类型", m.archivetype))
    }
    rows.toArray()
}

// 页数行：「48（图像 44 · 视频 2 · 音频 1 · 文本 1）」；无页表或无统计时仅总页数。
private func pageStatText(pagecount: Int64, pages: Array<PageInfo>): String {
    if (pages.size == 0) {
        return "${pagecount}"
    }
    let s = statPages(pages)
    let parts = ArrayList<String>()
    if (s.image > 0) {
        parts.add("图像 ${s.image}")
    }
    if (s.video > 0) {
        parts.add("视频 ${s.video}")
    }
    if (s.audio > 0) {
        parts.add("音频 ${s.audio}")
    }
    if (s.html > 0) {
        parts.add("文本 ${s.html}")
    }
    if (parts.size == 0) {
        return "${pagecount}"
    }
    var inner = parts[0]
    for (i in 1..parts.size) {
        inner = "${inner} · ${parts[i]}"
    }
    "${pagecount}（${inner}）"
}

// 合集基础信息行（原型 infoTank：名称/档案数/总页数/创建/更新）。
private func tankInfoRows(t: TankoubonInfo): Array<(String, String)> {
    let rows = ArrayList<(String, String)>()
    rows.add(("名称", t.name))
    rows.add(("档案数", "${t.archiveCount}"))
    rows.add(("总页数", "${t.totalPages}"))
    rows.add(("封面", if (t.coverAssetId > 0) {
            "自定义"
        } else {
            "自动"
        }))
    if (t.createdAt.size > 0) {
        rows.add(("创建时间", tankDate(t.createdAt)))
    }
    if (t.updatedAt.size > 0) {
        rows.add(("更新时间", tankDate(t.updatedAt)))
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
