package lanlu_client_next.net

import std.collection.ArrayList
import std.fs.{Directory, Path}

private func tankStoreItems(name!: String = "合集一"): ArrayList<TankoubonInfo> {
    let items = ArrayList<TankoubonInfo>()
    let tank = TankoubonInfo()
    tank.id = "tank:1"
    tank.name = name
    tank.description = "合集简介"
    tank.tags.add("作者:甲")
    tank.tags.add("语言:中文")
    tank.archiveCount = 8
    tank.totalPages = 486
    tank.progress = 311.0
    tank.coverAssetId = 9002
    tank.backdropAssetId = 9003
    tank.isfavorite = true
    items.add(tank)

    let empty = TankoubonInfo()
    empty.id = "tank:2"
    empty.name = "空合集"
    items.add(empty)
    return items
}

private func memoryTanks(query: String, language: String, name!: String = "合集一"): TankoubonView {
    TankoubonView.memory(query, language, tankStoreItems(name: name))
}

@Test
func tankListsShareObjectsAndSurviveReplacement(): Unit {
    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    let first = cache
        .storeTanks("server", "account", "parent:arc:1", "zh", memoryTanks("parent:arc:1", "zh"))
        .getOrThrow()
    @Expect(first.size, 2)
    @Expect(first[0].id, "tank:1")
    @Expect(first[0].name, "合集一")
    @Expect(first[0].archiveCount, 8)
    @Expect(first[0].coverAssetId, 9002)
    @Expect(first[0].isfavorite, true)
    @Expect(first[1].id, "tank:2")

    // 不同 query 共享同一规范实体：改名后旧 query 视图读到新标题。
    let shared = ArrayList<TankoubonInfo>()
    shared.add(tankStoreItems(name: "更新标题")[0])
    let second = cache
        .storeTanks("server", "account", "related:tank:1", "zh",
            TankoubonView.memory("related:tank:1", "zh", shared))
        .getOrThrow()
    @Expect(second.size, 1)
    @Expect(cache.openTanks("server", "account", "parent:arc:1", "zh").getOrThrow()[0].name, "更新标题")

    // persist 只写规范主记录，不改 membership。
    let mutated = second[0]
    mutated.isfavorite = false
    @Expect(second.persist(mutated), true)
    @Expect(cache.openTanks("server", "account", "parent:arc:1", "zh").getOrThrow()[0].isfavorite, false)
    @Expect(cache.openTanks("server", "account", "related:tank:1", "zh").getOrThrow()[0].isfavorite, false)

    // 整表替换原子删除旧 membership。
    let replacement = ArrayList<TankoubonInfo>()
    replacement.add(tankStoreItems(name: "替换表")[1])
    let replaced = cache
        .storeTanks("server", "account", "parent:arc:1", "zh",
            TankoubonView.memory("parent:arc:1", "zh", replacement))
        .getOrThrow()
    @Expect(replaced.size, 1)
    @Expect(replaced[0].id, "tank:2")
    @Expect(cache.openTanks("server", "account", "related:tank:1", "zh").getOrThrow().size, 1)
    cache.close()

    // 重开、账户隔离与服务器清理。
    let reopened = OfflineCache.open(path).getOrThrow()
    @Expect(reopened.openTanks("server", "account", "parent:arc:1", "zh").getOrThrow()[0].name, "空合集")
    @Expect(reopened.openTanks("server", "other", "parent:arc:1", "zh").isNone(), true)
    reopened.clearServer("server")
    @Expect(reopened.openTanks("server", "account", "parent:arc:1", "zh").isNone(), true)
    reopened.close()
}

@Test
func tankListsIsolateByLanguageAndRankBound(): Unit {
    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    // query key 必须包含语言（对齐 SearchItem 的约定），语言间实体按 query 隔离。
    let zh = cache
        .storeTanks("server", "account", "parent:arc:1:zh", "zh", memoryTanks("parent:arc:1:zh", "zh",
            name: "中文名"))
        .getOrThrow()
    let en = cache
        .storeTanks("server", "account", "parent:arc:1:en", "en", memoryTanks("parent:arc:1:en", "en",
            name: "English"))
        .getOrThrow()
    @Expect(zh[0].name, "中文名")
    @Expect(en[0].name, "English")
    @Expect(cache.openTanks("server", "account", "parent:arc:1:zh", "zh").getOrThrow()[0].name, "中文名")

    @Expect(zh.itemAt(-1).isNone(), true)
    @Expect(zh.itemAt(2).isNone(), true)
    @Expect(zh.at(0).id, "tank:1")
    cache.close()
}
