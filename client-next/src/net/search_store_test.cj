package lanlu_client_next.net

import std.collection.ArrayList
import std.fs.{Directory, Path}

private func searchStoreItems(title!: String = "档案一"): ArrayList<SearchItem> {
    let items = ArrayList<SearchItem>()
    let archive = SearchItem()
    archive.arcid = "arc:1"
    archive.title = title
    archive.description = "简介"
    archive.tagsCsv = "作者:甲,语言:中文"
    archive.archivetype = "image"
    archive.filename = "archive.zip"
    archive.coverAssetId = 42
    archive.pagecount = 120
    archive.progress = 17
    archive.size = 4096
    archive.lastreadtime = 123456
    archive.isnew = true
    archive.isfavorite = true
    items.add(archive)

    let tank = SearchItem()
    tank.itemType = "tankoubon"
    tank.tankoubonId = "tank:1"
    tank.title = "合集一"
    tank.archiveCount = 8
    items.add(tank)
    return items
}

private func memorySearchItems(query: String, language: String, title!: String = "档案一"): SearchItemView {
    SearchItemView.memory(query, language, searchStoreItems(title: title))
}

@Test
func searchItemsShareLocalizedObjectsAndQueriesSurviveReplacement(): Unit {
    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    let first = cache
        .storeSearchItems("server", "account", "search:q1", "zh", memorySearchItems("search:q1", "zh"))
        .getOrThrow()
    @Expect(first.size, 2)
    @Expect(first[0].arcid, "arc:1")
    @Expect(first[0].coverAssetId, 42)
    @Expect(first[0].isfavorite, true)
    @Expect(first[1].tankoubonId, "tank:1")

    let shared = ArrayList<SearchItem>()
    shared.add(searchStoreItems(title: "更新标题")[0])
    let second = cache
        .storeSearchItems("server", "account", "search:q2", "zh", SearchItemView.memory("search:q2", "zh", shared))
        .getOrThrow()
    @Expect(second.size, 1)
    @Expect(cache.openSearchItems("server", "account", "search:q1", "zh").getOrThrow()[0].title, "更新标题")
    let mutated = second[0]
    mutated.isfavorite = false
    @Expect(second.persist(mutated), true)
    @Expect(cache.openSearchItems("server", "account", "search:q1", "zh").getOrThrow()[0].isfavorite, false)

    let replacement = ArrayList<SearchItem>()
    replacement.add(searchStoreItems()[1])
    let replaced = cache
        .storeSearchItems("server", "account", "search:q1", "zh", SearchItemView.memory("search:q1", "zh", replacement))
        .getOrThrow()
    @Expect(replaced.size, 1)
    @Expect(replaced[0].tankoubonId, "tank:1")
    @Expect(cache.openSearchItems("server", "account", "search:q2", "zh").getOrThrow().size, 1)
    cache.close()

    let reopened = OfflineCache.open(path).getOrThrow()
    @Expect(reopened.openSearchItems("server", "account", "search:q1", "zh").getOrThrow()[0].title, "合集一")
    @Expect(reopened.openSearchItems("server", "other", "search:q1", "zh").isNone(), true)
    reopened.clearServer("server")
    @Expect(reopened.openSearchItems("server", "account", "search:q1", "zh").isNone(), true)
    reopened.close()
}

@Test
func searchItemLanguageProjectionAndRankFilterAreIsolated(): Unit {
    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    let zh = cache
        .storeSearchItems("server", "account", "search:zh", "zh", memorySearchItems("search:zh", "zh", title: "中文标题"))
        .getOrThrow()
    let en = cache
        .storeSearchItems("server", "account", "search:en", "en",
            memorySearchItems("search:en", "en", title: "English title"))
        .getOrThrow()
    @Expect(zh[0].title, "中文标题")
    @Expect(en[0].title, "English title")
    @Expect(cache.openSearchItems("server", "account", "search:zh", "zh").getOrThrow()[0].title, "中文标题")

    let filtered = SearchItemProjectionView.filter(zh, {item => item.isfavorite})
    @Expect(filtered.size, 1)
    @Expect(filtered[0].arcid, "arc:1")
    @Expect(SearchItemProjectionView.all(zh).size, 2)
    @Expect(zh.itemAt(-1).isNone(), true)
    @Expect(zh.itemAt(2).isNone(), true)
    cache.close()
}

@Test
func searchItemPagesAppendByRankWithoutHoldingDecodedSnapshot(): Unit {
    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    let first = memorySearchItems("tank:all", "zh")
    @Expect(cache.storeSearchItemPage(
        "server", "account", "tank:all", "zh", 0, true, first).getOrThrow().size, 2)

    let tailItems = ArrayList<SearchItem>()
    let tail = SearchItem()
    tail.arcid = "arc:2"
    tail.title = "档案二"
    tailItems.add(tail)
    let appended = cache
        .storeSearchItemPage("server", "account", "tank:all", "zh", 2, false,
            SearchItemView.memory("tail", "zh", tailItems))
        .getOrThrow()
    @Expect(appended.size, 3)
    @Expect(appended[2].arcid, "arc:2")

    let replacement = cache
        .storeSearchItemPage("server", "account", "tank:all", "zh", 0, true,
            SearchItemView.memory("replacement", "zh", tailItems))
        .getOrThrow()
    @Expect(replacement.size, 1)
    @Expect(replacement[0].arcid, "arc:2")
    cache.close()
}

@Test
func updateCachedCopyMutatesMemoryAndHotWindowOnly(): Unit {
    // 内存视图：命中即原地更新；未命中返回 None。
    let memory = memorySearchItems("search:mem", "zh")
    let hit = memory.updateCachedCopy("arc:1", {it => it.title = "内存改"})
    @Expect(hit.isSome(), true)
    @Expect(memory[0].title, "内存改")
    @Expect(memory.updateCachedCopy("arc:none", {_ => ()}).isNone(), true)

    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    let persisted = cache
        .storeSearchItems("server", "account", "search:p", "zh", memorySearchItems("search:p", "zh"))
        .getOrThrow()
    // 热窗为空时不得触发按 rank 扫描，直接未命中。
    @Expect(persisted.updateCachedCopy("arc:1", {_ => ()}).isNone(), true)
    // itemAt 把 rank 0 装入热窗后即可命中并原地更新。
    let _ = persisted.itemAt(0)
    let warmed = persisted.updateCachedCopy("arc:1", {it => it.title = "热窗改"})
    @Expect(warmed.isSome(), true)
    @Expect(persisted.persist(warmed.getOrThrow()), true)
    @Expect(cache.openSearchItems("server", "account", "search:p", "zh").getOrThrow()[0].title, "热窗改")
    cache.close()
}

@Test
func loadByArcidReadsCanonicalEntityWithoutRankScan(): Unit {
    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    let view = cache
        .storeSearchItems("server", "account", "search:q", "zh", memorySearchItems("search:q", "zh"))
        .getOrThrow()
    // 规范实体按键直查：archive 记录命中，tank 记录（tank: 命名空间）与未知 arcid 不命中。
    @Expect(view.loadByArcid("arc:1").getOrThrow().title, "档案一")
    @Expect(view.loadByArcid("tank:1").isNone(), true)
    @Expect(view.loadByArcid("arc:none").isNone(), true)
    @Expect(view.loadByArcid("").isNone(), true)
    // 内存视图没有存储后端，恒为 None。
    @Expect(memorySearchItems("search:mem", "zh").loadByArcid("arc:1").isNone(), true)
    cache.close()
}
