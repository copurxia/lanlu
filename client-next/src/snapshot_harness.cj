package lanlu_client_next

import cui.stagePixelImage
import lanlu_client_next.app.*
import lanlu_client_next.net.{CategoryItem, SearchItem, ArchiveMeta, TankoubonInfo, PageInfo, ServerInfo,
    UserStats, TrendPoint, CloudTag, AdminUserItem, AdminCategoryItem, AdminTagItem, TagListPage,
    SmartFilterItem, TaskRecord, TaskListPage, CronTask, CronStatus, PluginItem, SessionItem, TokenItem,
    PasskeyItem, TotpStatus}
import std.collection.ArrayList
import std.convert.Parsable
import std.env.getCommandLine

// ── 临时快照播种装置（Task E3 验证专用，用后删除，不随产品交付）──
// 命令行 --seed-browse / --seed-search 触发：全程离线（api 保持 None），直接向
// AppModel 种入假分类/假浏览行/假搜索结果与合成封面像素，配合框架内置
// `--snapshot <path.bmp>` 输出布局快照；--width N 覆盖窗口宽（默认 1440），
// 用于 960/1440/1920 三宽度验证。
// T11 增补：--seed-detail（档案详情）/ --seed-tank（合集详情），种子覆盖 hero、
// 页面预览（含目录层级与媒体页）、所属合集、成员列表、侧栏卡片与 backdrop 像素。
// Task 5 增补：--seed-settings（设置页），种子账号/服务器信息（serverInfo）。
// T13 增补：--seed-reader（阅读器），种子元数据（标题/收藏态）、24 页页表（第 5 页视频、
// 第 6 页音频，验证 lane/舞台分派）与全部图片页像素。阅读器视图态开关：--reader-nochrome
//（chrome 隐藏）、--reader-settings / --reader-sidebar（抽屉开启）、--reader-double /
// --reader-rtl（双页/RTL）、--reader-audio（从第 6 页音频页起）。

public func harnessSeedMode(): String {
    for (a in getCommandLine()) {
        if (a == "--seed-browse") { return "browse" }
        if (a == "--seed-search") { return "search" }
        if (a == "--seed-detail") { return "detail" }
        if (a == "--seed-tank") { return "tank" }
        if (a == "--seed-settings") { return "settings" }
        if (a == "--seed-reader") { return "reader" }
    }
    ""
}

public func harnessWindowWidth(): Int32 {
    let args = getCommandLine()
    var i = 0
    while (i + 1 < args.size) {
        if (args[i] == "--width") {
            return Int32(Int64.parse(args[i + 1]))
        }
        i++
    }
    1440
}

// 窗口高覆盖（默认 900）：详情页内容超一屏，加高可一帧拍下全部卡片。
public func harnessWindowHeight(): Int32 {
    let args = getCommandLine()
    var i = 0
    while (i + 1 < args.size) {
        if (args[i] == "--height") {
            return Int32(Int64.parse(args[i + 1]))
        }
        i++
    }
    900
}

// 视图态开关（--pv-list / --pv-tree / --mb-list）：快照覆盖页面预览列表/树态与成员列表态。
public func harnessHasArg(flag: String): Bool {
    for (a in getCommandLine()) {
        if (a == flag) { return true }
    }
    false
}

public func seedLibrarySnapshot(model: AppModel, mode: String): Unit {
    if (mode == "detail") {
        seedArchiveDetail(model)
        return
    }
    if (mode == "tank") {
        seedTankDetail(model)
        return
    }
    if (mode == "settings") {
        seedSettings(model)
        return
    }
    if (mode == "reader") {
        seedReader(model)
        return
    }
    model.page.value = Page.Library
    seedCategories(model)
    if (mode == "search") {
        seedSearchMode(model)
    } else {
        seedBrowseMode(model)
    }
}

// ---- 假数据 ----

private func seedCategories(model: AppModel): Unit {
    let cats = ArrayList<CategoryItem>()
    cats.add(makeCategory(1, "CAT_1", "同人志", 128))
    cats.add(makeCategory(2, "CAT_2", "漫画", 86))
    cats.add(makeCategory(3, "CAT_3", "画集", 42))
    cats.add(makeCategory(4, "CAT_4", "写真集", 17))
    cats.add(makeCategory(5, "CAT_5", "小说", 9))
    model.categories.value = cats
}

private func makeCategory(id: Int64, catid: String, name: String, count: Int64): CategoryItem {
    let c = CategoryItem()
    c.id = id
    c.catid = catid
    c.name = name
    c.archiveCount = count
    c
}

// 浏览模式：继续阅读 + 随机推荐 + 分类行，覆盖全部行态
// （已加载×3 / 加载中 / 失败可重试）。seqBase 402 起让继续阅读行多数卡片带进度；
// 新到档案行已随产品要求移除，NEW 徽标改由随机/分类行的 seq%4 规则交错覆盖。
private func seedBrowseMode(model: AppModel): Unit {
    let rows = ArrayList<BrowseRow>()
    rows.add(makeRow("resume", "继续阅读", "", seedItems(model, 12, 402)))
    rows.add(makeRow("random", "随机推荐", "", seedItems(model, 12, 0)))
    rows.add(makeRow("CAT_1", "同人志", "CAT_1", seedItems(model, 12, 100)))
    // 行级加载态：画集行仍在加载
    let loading = BrowseRow()
    loading.key = "CAT_3"
    loading.title = "画集"
    loading.catid = "CAT_3"
    loading.requested = true
    loading.loading = true
    rows.add(loading)
    // 行级失败态：写真集行加载失败，可点击重试
    let failed = BrowseRow()
    failed.key = "CAT_4"
    failed.title = "写真集"
    failed.catid = "CAT_4"
    failed.requested = true
    failed.loading = false
    failed.failed = true
    rows.add(failed)
    rows.add(makeRow("CAT_2", "漫画", "CAT_2", seedItems(model, 9, 200)))
    model.browseRows.value = rows
}

// 搜索/过滤模式：有关键词即非浏览模式，种 18 条结果（总数 42，供分页条显示）。
private func seedSearchMode(model: AppModel): Unit {
    model.searchText.value = "魔法"
    model.query.filter = "魔法"
    model.items.value = seedItems(model, 18, 300)
    model.recordsTotal.value = 42
    model.currentPage.value = 1
}

private func makeRow(key: String, title: String, catid: String, items: ArrayList<SearchItem>): BrowseRow {
    let r = BrowseRow()
    r.key = key
    r.title = title
    r.catid = catid
    r.items = items
    r.requested = true
    r.loading = false
    r.failed = false
    r
}

// 生成 n 条假档案并预置封面状态：大部分为合成像素成品封面，每隔几条分布
// 无封面/加载中/加载失败态；NEW/收藏徽标与阅读进度按序交错（混合卡片态）。
private func seedItems(model: AppModel, n: Int64, seqBase: Int64): ArrayList<SearchItem> {
    let list = ArrayList<SearchItem>()
    for (i in 0..n) {
        let seq = seqBase + i
        let it = SearchItem()
        it.arcid = "ARC${seq}"
        it.title = fakeTitle(seq)
        it.pagecount = 20 + seq % 180
        it.archivetype = "doujinshi"
        // 进度：约 1/3 未读，其余部分进度，个别读完（100%）
        let pm = seq % 6
        if (pm == 0 || pm == 1) {
            it.progress = 0
        } else if (pm == 5) {
            it.progress = it.pagecount
        } else {
            it.progress = it.pagecount * (seq % 80 + 10) / 100
        }
        it.isnew = (seq % 4 == 1)
        it.isfavorite = (seq % 3 == 2)
        let state = seq % 9
        if (state == 3) {
            it.coverAssetId = 0 // 无封面占位
        } else {
            it.coverAssetId = 1000 + seq
            let key = "asset:${it.coverAssetId}"
            if (state == 6) {
                model.imageState(key).value = "loading" // 封面加载中
            } else if (state == 8) {
                model.imageState(key).value = "error" // 封面加载失败（可点击重试）
            } else {
                stageCover(model, key, seq) // 合成成品封面
            }
        }
        list.add(it)
    }
    list
}

// 标题长度交错，含一条超长标题验证 1 行截断。
private func fakeTitle(seq: Int64): String {
    let n = seq % 5
    if (n == 0) { return "短标题 ${seq}" }
    if (n == 1) { return "中等长度的档案标题 ${seq}" }
    if (n == 2) { return "(C102) [サークル名] とても長いタイトルの同人誌 その壱 ～特別編～ ${seq}" }
    if (n == 3) { return "档案 No.${seq}" }
    "[合集] 系列作品总集篇 第 ${seq} 弹"
}

private let COVER_COLORS = [
    [0x52, 0x88, 0xE0], [0xDC, 0x46, 0x28], [0x3A, 0xA6, 0x7A],
    [0xB8, 0x7A, 0xE0], [0xE0, 0xA8, 0x52], [0x52, 0xB8, 0xC8]
]

// 合成 48×64 RGBA 封面：按种子取底色 + 纵向渐变 + 书脊暗条，四角按 ~4.5% 短边
// 半径清零 alpha（对齐 model.roundCoverCorners 的烘焙效果，快照里呈现真圆角）。
private func stageCover(model: AppModel, key: String, seed: Int64): Unit {
    let w = 48
    let h = 64
    let pixels = Array<UInt8>(w * h * 4, repeat: 0u8)
    let c = COVER_COLORS[seed % COVER_COLORS.size]
    for (y in 0..h) {
        let f = 0.72 + 0.28 * (1.0 - Float64(y) / Float64(h))
        for (x in 0..w) {
            let spine = if (x < 6) { 0.72 } else { 1.0 }
            let o = (y * w + x) * 4
            pixels[o] = UInt8(Float64(c[0]) * f * spine)
            pixels[o + 1] = UInt8(Float64(c[1]) * f * spine)
            pixels[o + 2] = UInt8(Float64(c[2]) * f * spine)
            pixels[o + 3] = 255u8
        }
    }
    let r = 3.5 // 48×64 缩样的短边 7.2%，对齐 model.roundCoverCorners 的新比例
    clearCorner(pixels, w, 0, 0, r, r, r)
    clearCorner(pixels, w, w - 4, 0, Float64(w - 1) - r, r, r)
    clearCorner(pixels, w, 0, h - 4, r, Float64(h - 1) - r, r)
    clearCorner(pixels, w, w - 4, h - 4, Float64(w - 1) - r, Float64(h - 1) - r, r)
    stagePixelImage(key, Int32(w), Int32(h), pixels)
    model.imageState(key).value = "ready"
}

// 角弧（圆心 (cx,cy) 半径 r）以外的 4×4 角区像素 alpha 清零。
private func clearCorner(pixels: Array<UInt8>, w: Int64, x0: Int64, y0: Int64, cx: Float64,
    cy: Float64, r: Float64): Unit {
    for (y in y0..y0 + 4) {
        for (x in x0..x0 + 4) {
            let dx = Float64(x) - cx
            let dy = Float64(y) - cy
            if (dx * dx + dy * dy > r * r) {
                pixels[(y * w + x) * 4 + 3] = 0u8
            }
        }
    }
}

// ---- T11 详情页种子（档案 / 合集）----

// 档案详情：hero（封面/徽标/大标题/meta/内联进度/简介/标签 + 玻璃操作卡）、
// 页面预览（24 页，含目录层级与 🎬🎵📄 媒体页，前 14 页已读半透明）、
// 所属合集 ×2、相关推荐 ×6、侧栏进度大卡 + 基础信息（混合页统计）+ 标签分组。
private func seedArchiveDetail(model: AppModel): Unit {
    model.page.value = Page.Detail("ARC_D1")
    let m = ArchiveMeta()
    m.arcid = "ARC_D1"
    m.title = "(C102) [サークル名] とても長いタイトルの同人誌 その壱 ～特別編～"
    m.description = "这里是档案简介，三到四行截断。讲述主角在命运的岔路口做出的抉择，\n以及那场改变一切的雪夜之战。简介内容由元数据插件抓取，可编辑。"
    m.archivetype = "doujinshi"
    m.filename = "page_pack_vol3.cbz"
    m.relativePath = "doujin/2024/"
    m.coverAssetId = 9001
    stageCover(model, "asset:9001", 7)
    m.pagecount = 24
    m.progress = 14
    m.size = 100873216 // 96.2 MB
    m.isnew = false
    m.isfavorite = true
    m.release_at = 1723766400 // 2024-08-17
    m.created_at = 1725062400 // 2024-09-01
    m.updated_at = 1730422400 // 2024-11-02
    m.lastreadtime = 1730422400
    let tags = ArrayList<String>()
    for (t in ["category:同人志", "artist:某某", "group:某社团", "parody:原作名", "full color", "language:chinese",
        "multi-work series"]) {
        tags.add(t)
    }
    m.tags = tags
    model.meta.value = Some(m)
    // 页面预览视图态开关：--pv-list / --pv-tree（默认缩略图）。
    if (harnessHasArg("--pv-list")) { model.pageViewIndex.value = 1 }
    if (harnessHasArg("--pv-tree")) { model.pageViewIndex.value = 2 }

    // 页面预览：第14章 20 图像 + media 3（🎬视频/🎵音频/图像）+ text 1（📄html）。
    let pages = ArrayList<PageInfo>()
    for (i in 1..21) {
        pages.add(makePage("第14章/page_${pad3(i)}.avif", "image"))
    }
    pages.add(makePage("media/PV1.mp4", "video"))
    pages.add(makePage("media/theme.flac", "audio"))
    pages.add(makePage("media/cover.avif", "image"))
    pages.add(makePage("text/ch14.xhtml", "html"))
    model.detailPages.value = pages

    // 所属合集 ×2（一个带 64% 进度）
    let tanks = ArrayList<TankoubonInfo>()
    tanks.add(makeTank(model, "TANK_P1", "某个合集", 9002, 12, 486, 311.0))
    tanks.add(makeTank(model, "TANK_P2", "某系列 总集篇", 9003, 8, 320, 0.0))
    model.parentTanks.value = tanks

    // 相关推荐 ×6（混合卡片态：进度/NEW/收藏交错）
    model.relatedItems.value = seedItems(model, 6, 700)

    stageBackdrop("backdrop:ARC_D1", 11)
}

// 合集详情：hero（⧉ 合集徽标 + 叠层封面 + 64% 内联进度）、收录档案 12 成员
// （前 7 个读完、第 8 个 40%、其余未读 → 侧栏「已读完 7 个」）、相关合集 ×3。
private func seedTankDetail(model: AppModel): Unit {
    model.page.value = Page.Tank("TANK_1")
    let t = TankoubonInfo()
    t.id = "TANK_1"
    t.name = "某个合集"
    t.description = "系列作品完整收录：从初遇的雪夜到黎明前的决断，含番外篇与最终话。"
    t.archiveCount = 12
    t.totalPages = 486
    t.progress = 311.0 // 311/486 → 64%
    t.coverAssetId = 9010
    stageCover(model, "asset:9010", 3)
    let tags = ArrayList<String>()
    for (tag in ["parody:原作名", "artist:某某", "group:某社团", "language:chinese", "full color"]) {
        tags.add(tag)
    }
    t.tags = tags
    t.createdAt = "2024-06-12 10:00:00"
    t.updatedAt = "2024-11-02 22:14:00"
    model.tank.value = Some(t)
    // 成员视图态开关：--mb-list（默认网格）。
    if (harnessHasArg("--mb-list")) { model.tankMemberViewIndex.value = 1 }

    let titles = ["第1话 相遇", "第2话 暗流", "第3话 转折之时", "第4话 远雷", "第5话 归乡",
        "第6话 雪解", "第7话 灯火", "第8话 决断", "第9话 夜航", "第10话 黎明前",
        "番外篇 祭典", "最终话 新的旅程"]
    let members = ArrayList<SearchItem>()
    for (i in 0..12) {
        let it = SearchItem()
        it.arcid = "ARC_M${i}"
        it.title = titles[i]
        it.pagecount = 24 + i * 4
        it.coverAssetId = 9100 + i
        stageCover(model, "asset:${it.coverAssetId}", i)
        if (i < 7) {
            it.progress = it.pagecount // 已读完
        } else if (i == 7) {
            it.progress = it.pagecount * 40 / 100
        }
        it.isnew = (i == 11)
        members.add(it)
    }
    model.tankMembers.value = members

    let related = ArrayList<TankoubonInfo>()
    related.add(makeTank(model, "TANK_R1", "同作者精选集", 9201, 6, 210, 80.0))
    related.add(makeTank(model, "TANK_R2", "某系列 总集篇", 9202, 8, 320, 0.0))
    related.add(makeTank(model, "TANK_R3", "冬日主题合集", 9203, 10, 400, 160.0))
    model.tankRelated.value = related

    stageBackdrop("backdrop:tank:TANK_1", 5)
}

private func makePage(id: String, pageType: String): PageInfo {
    let p = PageInfo()
    p.id = id
    p.pageType = pageType
    p
}

// 合集种子：coverAssetId > 0 时种合成封面；createdAt/updatedAt 固定样本值。
private func makeTank(model: AppModel, id: String, name: String, coverAssetId: Int64, count: Int64,
    pages: Int64, progress: Float32): TankoubonInfo {
    let t = TankoubonInfo()
    t.id = id
    t.name = name
    t.archiveCount = count
    t.totalPages = pages
    t.progress = progress
    t.coverAssetId = coverAssetId
    if (coverAssetId > 0) {
        stageCover(model, "asset:${coverAssetId}", Int64(id.size) + count)
    }
    t.createdAt = "2024-06-12 10:00:00"
    t.updatedAt = "2024-11-02 22:14:00"
    t
}

// backdrop 合成像素：96×46 纵向渐变（暗色基调，Cover 放大后经 scrim 融入页面底）。
private func stageBackdrop(key: String, seed: Int64): Unit {
    let w = 96
    let h = 46
    let pixels = Array<UInt8>(w * h * 4, repeat: 0u8)
    let c = COVER_COLORS[seed % COVER_COLORS.size]
    for (y in 0..h) {
        let f = 0.45 + 0.4 * (1.0 - Float64(y) / Float64(h))
        for (x in 0..w) {
            let o = (y * w + x) * 4
            pixels[o] = UInt8(Float64(c[0]) * f)
            pixels[o + 1] = UInt8(Float64(c[1]) * f)
            pixels[o + 2] = UInt8(Float64(c[2]) * f)
            pixels[o + 3] = 255u8
        }
    }
    stagePixelImage(key, Int32(w), Int32(h), pixels)
}

// 设置页种子：账号卡（用户名/服务器地址）+ 服务器信息卡。
// cacheInfo 不种子：设置页进场（settings.loaded）必调 refreshCacheInfo 覆盖之，
// 离线环境下展示 "图片缓存 0 MB"，属真实行为。loadServerInfo 在 api=None 时直接
// return，种入的 serverInfo 保持不动。
private func seedSettings(model: AppModel): Unit {
    model.settings.username = "demo_user"
    model.page.value = Page.Settings
    let info = ServerInfo()
    info.name = "Lanlu Demo Server"
    info.version = "0.9.1"
    info.versionName = "RE-RELEASE"
    info.motd = "离线快照演示数据"
    info.totalArchives = 256
    model.serverInfo.value = Some(info)

    // 设置区扩展种子（Task 20）：概览 dashboard / 用户 / 系统设置 / 分类 / 标签 /
    // 智能分类 / 任务 / cron / 插件 / 账户安全。演示取值参照原型 settings-redesign.html
    // （同人志 486 档案、Job #1284、EhMeta 1.4.2、汉化 44 等）。
    model.isAdmin.value = true

    // 概览 dashboard：阅读统计卡 + 30 天趋势柱。
    let us = UserStats()
    us.favoriteCount = 328
    us.readCount = 542
    us.totalPagesRead = 18964
    us.totalArchives = 1286
    model.userStats.value = Some(us)
    let trend = ArrayList<TrendPoint>()
    for (i in 0..30) {
        let p = TrendPoint()
        p.date = "2026-06-${20 + i % 10}"
        p.count = (i * 7) % 38
        trend.add(p)
    }
    model.userTrend.value = trend

    // 最近阅读/收藏：模拟异步到达的两行数据（验证 ForEach(key) 重建不错位、行不跑出卡片）。
    let read = ArrayList<SearchItem>()
    let r1 = SearchItem(); r1.arcid = "seed-r1"; r1.title = "(C105) [Starlight] Summer Days"; r1.pagecount = 320; r1.progress = 128
    let r2 = SearchItem(); r2.arcid = "seed-r2"; r2.title = "[Alpha] Illustration Works 2025"; r2.pagecount = 64; r2.progress = 64
    read.add(r1); read.add(r2)
    model.recentRead.value = read
    let fav = ArrayList<SearchItem>()
    let f1 = SearchItem(); f1.arcid = "seed-f1"; f1.title = "[Studio Nekome] 画集：青の記憶"; f1.pagecount = 128; f1.progress = 0
    fav.add(f1)
    model.recentFav.value = fav

    // 管理板块：用户列表（admin 管理员 / alice 普通用户）。
    let users = ArrayList<AdminUserItem>()
    let u1 = AdminUserItem(); u1.id = 1; u1.username = "admin"; u1.isAdmin = true; u1.createdAt = "2025-12-01"
    let u2 = AdminUserItem(); u2.id = 2; u2.username = "alice"; u2.createdAt = "2026-02-14"
    users.add(u1); users.add(u2)
    model.adminUsers.value = users

    // 管理板块：分类（同人志 486 档案 + 画集）。
    let cats = ArrayList<AdminCategoryItem>()
    let c1 = AdminCategoryItem()
    c1.id = 1; c1.catid = "doujinshi"; c1.name = "同人志"; c1.scanPath = "/content/doujinshi"
    c1.description = "Comic Market 等同人志扫本，按社团与艺术家归档"
    c1.sortOrder = 1; c1.enabled = true; c1.archiveCount = 486
    let c2 = AdminCategoryItem()
    c2.id = 2; c2.catid = "artbook"; c2.name = "画集"; c2.scanPath = "/content/artbook"
    c2.description = "商业画集与设定集"; c2.sortOrder = 2; c2.enabled = true; c2.archiveCount = 74
    cats.add(c1); cats.add(c2)
    model.adminCategories.value = cats

    // 管理板块：标签分页（namespace/name + 中英译名）。
    let tagItems = ArrayList<AdminTagItem>()
    let t1 = AdminTagItem(); t1.id = 1; t1.namespace = "parody"; t1.name = "touhou_project"
    t1.zhText = "东方Project"; t1.enText = "Touhou Project"
    let t2 = AdminTagItem(); t2.id = 2; t2.namespace = "female"; t2.name = "sole_female"
    t2.zhText = "纯女主"; t2.enText = "Sole Female"
    let t3 = AdminTagItem(); t3.id = 3; t3.namespace = "language"; t3.name = "chinese"
    t3.zhText = "汉化"; t3.enText = "Chinese"
    tagItems.add(t1); tagItems.add(t2); tagItems.add(t3)
    let tp = TagListPage()
    tp.items = tagItems
    tp.total = 1823
    model.tagPage.value = Some(tp)

    // 管理板块：智能分类（两条过滤规则）。
    let sfs = ArrayList<SmartFilterItem>()
    let sf1 = SmartFilterItem(); sf1.id = 1; sf1.name = "本周新增"; sf1.icon = "🕒"
    sf1.query = ""; sf1.sortBy = "date_added"; sf1.sortOrder = "desc"
    sf1.newonly = true; sf1.enabled = true; sf1.sortOrderNum = 1
    let sf2 = SmartFilterItem(); sf2.id = 2; sf2.name = "待补标签"; sf2.icon = "🏷"
    sf2.query = ""; sf2.untaggedonly = true; sf2.enabled = true; sf2.sortOrderNum = 2
    sfs.add(sf1); sfs.add(sf2)
    model.smartFilters.value = sfs

    // 管理板块：任务记录（扫描分类「同人志」 Job #1284 进行中 + 已完成任务）。
    let tr1 = TaskRecord()
    tr1.id = 1284; tr1.name = "扫描分类「同人志」"; tr1.status = "running"; tr1.phase = "scan"
    tr1.message = "已处理 301/486 个档案，新增 3 个"; tr1.taskType = "scan_single_category"
    tr1.triggerSource = "manual"; tr1.progress = 62; tr1.priority = 5
    tr1.createdAt = "2026-07-19 10:20:01"; tr1.startedAt = "2026-07-19 10:20:03"
    let tr2 = TaskRecord()
    tr2.id = 1283; tr2.name = "EhMeta 元数据补全"; tr2.status = "completed"; tr2.phase = "done"
    tr2.message = "共补全 128 个档案"; tr2.taskType = "metadata_plugin"; tr2.pluginNamespace = "ehmeta"
    tr2.triggerSource = "cron"; tr2.progress = 100
    tr2.createdAt = "2026-07-19 06:00:00"; tr2.completedAt = "2026-07-19 06:04:37"
    let taskItems = ArrayList<TaskRecord>()
    taskItems.add(tr1); taskItems.add(tr2)
    let taskPg = TaskListPage()
    taskPg.tasks = taskItems
    taskPg.total = 2
    model.taskPage.value = Some(taskPg)

    // 管理板块：定时任务状态 + 两条 cron 任务。
    let cs = CronStatus()
    cs.running = true; cs.totalTasks = 2; cs.enabledTasks = 2
    model.cronStatus.value = Some(cs)
    let crons = ArrayList<CronTask>()
    let ct1 = CronTask()
    ct1.id = 1; ct1.name = "每日元数据补全"; ct1.cronExpression = "0 6 * * *"
    ct1.taskType = "metadata_plugin"; ct1.enabled = true; ct1.priority = 3
    ct1.runCount = 42; ct1.lastRunAt = "2026-07-19 06:00:00"; ct1.nextRunAt = "2026-07-20 06:00:00"
    ct1.hasLastRun = true; ct1.lastRunSuccess = true
    let ct2 = CronTask()
    ct2.id = 2; ct2.name = "每周缓存清理"; ct2.cronExpression = "0 3 * * 0"
    ct2.taskType = "clear_cache"; ct2.enabled = true; ct2.priority = 1
    ct2.runCount = 12; ct2.lastRunAt = "2026-07-13 03:00:00"; ct2.nextRunAt = "2026-07-20 03:00:00"
    ct2.hasLastRun = true; ct2.lastRunSuccess = true
    crons.add(ct1); crons.add(ct2)
    model.cronTasks.value = crons

    // 管理板块：插件（EhMeta 1.4.2 已启用 + 未启用的一条）。
    let plgs = ArrayList<PluginItem>()
    let pl1 = PluginItem()
    pl1.name = "EhMeta"; pl1.namespace = "ehmeta"; pl1.version = "1.4.2"
    pl1.pluginType = "metadata"; pl1.author = "lanlup"; pl1.description = "E站元数据"
    pl1.enabled = true; pl1.installed = true; pl1.hasSchema = true
    let pl2 = PluginItem()
    pl2.name = "Hdoujin"; pl2.namespace = "hdoujin"; pl2.version = "0.9.0"
    pl2.pluginType = "metadata"; pl2.author = "community"; pl2.description = "Hdoujin 元数据下载"
    pl2.enabled = false; pl2.installed = true; pl2.hasSchema = false
    plgs.add(pl1); plgs.add(pl2)
    model.plugins.value = plgs

    // 账户安全：登录设备（当前会话 + 一台手机）。
    let sess = ArrayList<SessionItem>()
    let s1 = SessionItem()
    s1.id = 11; s1.name = "Windows · Chrome 138"; s1.prefix = "lanlu_Kd82"
    s1.createdAt = "2026-07-12"; s1.lastUsedAt = "2026-07-19 10:00"
    s1.lastUsedIp = "192.168.1.23"; s1.current = true
    let s2 = SessionItem()
    s2.id = 9; s2.name = "Android · 手机浏览器"; s2.prefix = "lanlu_3fE0"
    s2.createdAt = "2026-06-28"; s2.lastUsedAt = "2026-07-18 22:41"
    s2.lastUsedIp = "192.168.1.45"
    sess.add(s1); sess.add(s2)
    model.sessions.value = sess

    // 账户安全：API Token 一条。
    let toks = ArrayList<TokenItem>()
    let tk1 = TokenItem()
    tk1.id = 3; tk1.name = "eh-sync 脚本"; tk1.prefix = "lanlu_t0k3n"
    toks.add(tk1)
    model.apiTokens.value = toks

    // 账户安全：Passkey 一把 + TOTP 已启用。
    let pks = ArrayList<PasskeyItem>()
    let pk1 = PasskeyItem()
    pk1.id = 7; pk1.name = "我的工作电脑"; pk1.credentialId = "9f3a21c7"
    pk1.algorithm = "ES256"; pk1.userVerified = true; pk1.lastUsedAt = "2026-07-19 09:58"
    pks.add(pk1)
    model.passkeys.value = pks
    let totp = TotpStatus()
    totp.enabled = true; totp.credentialName = "Lanlu (admin)"
    totp.createdAt = "2026-05-30"; totp.recoveryCodesRemaining = 7
    model.totpStatus.value = Some(totp)

    // 管理板块：标签云（统计信息，取值同原型演示序列）。
    let cloud = ArrayList<CloudTag>()
    let cloudSeed = [("汉化", 44), ("原创", 38), ("同人志", 34), ("全彩", 30), ("纯爱", 28), ("彩色", 26)]
    for ((tag, cnt) in cloudSeed) {
        let ct = CloudTag()
        ct.tag = tag
        ct.display = tag
        ct.count = cnt
        cloud.add(ct)
    }
    model.tagCloud.value = cloud
}

// 阅读器（T13）：专用顶栏（档案标题 · 页标题、页码胶囊、模式标签、收藏态）+ 页面区。
// 种 24 页页表（当前第 12 页）、元数据（长标题 + 已收藏）与当前页合成像素。
// 页表同 seedArchiveDetail 的目录形态；open/setPages 直接驱动状态机（api 离线为空，
// 不走 openReader 的网络通道），readerIndex 按惯例同步回 1 基。
private func seedReader(model: AppModel): Unit {
    let m = ArchiveMeta()
    m.arcid = "ARC_R1"
    m.title = "(C102) [サークル名] とても長いタイトルの同人誌 その壱 ～特別編～"
    m.pagecount = 24
    m.progress = 12
    m.isfavorite = true
    model.meta.value = Some(m)

    let pages = ArrayList<PageInfo>()
    for (i in 1..25) {
        let p = PageInfo()
        p.id = "第14章/page_${pad3(i)}.avif"
        p.pageType = "image"
        p.title = "第14章 转折之时"
        // 混合档案形态：第 5 页视频、第 6 页音频（验证 lane/舞台/占位）。
        if (i == 5) {
            p.id = "media/PV1.mp4"
            p.pageType = "video"
            p.title = "PV1"
        } else if (i == 6) {
            p.id = "media/theme.flac"
            p.pageType = "audio"
            p.title = "夜に駆ける"
        }
        pages.add(p)
    }
    model.pages.value = pages
    model.readerArcid = "ARC_R1"
    model.reader.open("ARC_R1", 11) // 0 基 → 第 12 页
    model.reader.setPages(pages)
    model.readerIndex.value = model.reader.displayPage
    // --reader-end：跳到末尾虚拟结束页（验证结束卡片；api 离线 → 解析走 None 失败态）。
    if (harnessHasArg("--reader-end")) {
        model.reader.gotoPage(999999)
        model.readerIndex.value = model.reader.displayPage
    }
    model.page.value = Page.Reader("ARC_R1", 12)
    // chrome 隐藏态开关（--reader-nochrome）：验证顶栏撤出、页面区吃满全高的布局。
    if (harnessHasArg("--reader-nochrome")) {
        model.reader.toggleChrome()
    }
    // 抽屉开启态开关（--reader-settings / --reader-sidebar）：验证两个 Drawer 的布局。
    if (harnessHasArg("--reader-settings")) {
        model.readerSettingsOpen.value = true
    }
    if (harnessHasArg("--reader-sidebar")) {
        model.readerSidebarOpen.value = true
    }
    // 音频页起始开关（--reader-audio）：从第 6 页（音频）起，验证音频舞台与 audio lane。
    if (harnessHasArg("--reader-audio")) {
        model.reader.gotoPage(5) // 0 基 → 第 6 页
        model.readerIndex.value = model.reader.index + 1
        model.page.value = Page.Reader("ARC_R1", 6)
    }
    // 双页/RTL 态开关（--reader-double / --reader-rtl）：验证 spread 布局与方向动画。
    if (harnessHasArg("--reader-double")) {
        model.reader.setDoublePage(true)
    }
    if (harnessHasArg("--reader-rtl")) {
        model.reader.setMode(ReadingMode.SingleRtl)
    }
    // 全部图片页合成像素（翻页动画/双页 spread 需要相邻页同帧在位；音频/视频页不上色）。
    for (i in 1..25) {
        if (i == 5 || i == 6) { continue }
        stageCover(model, "page:ARC_R1:第14章/page_${pad3(i)}.avif", i)
    }
}

private func pad3(n: Int64): String {
    if (n < 10) { return "00${n}" }
    if (n < 100) { return "0${n}" }
    "${n}"
}
