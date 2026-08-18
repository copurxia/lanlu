package lanlu_client_next.net

import std.collection.ArrayList
import std.fs.{Directory, Path}

private func translationEntries(): ArrayList<(String, String)> {
    let entries = ArrayList<(String, String)>()
    entries.add(("作者:甲", "作者:张三"))
    entries.add(("语言:中文", "Chinese"))
    return entries
}

@Test
func tagTranslationListsShareCanonicalRecordsAndIsolateByScope(): Unit {
    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    let archiveView = cache
        .storeTagTranslations("server", "account", "tag-translations:archive:arc:1:zh", "zh", translationEntries())
        .getOrThrow()
    @Expect(archiveView.size, 2)
    @Expect(archiveView.lookup("作者:甲").getOrThrow(), "作者:张三")
    @Expect(archiveView.lookup("语言:中文").getOrThrow(), "Chinese")
    @Expect(archiveView.lookup("不存在的标签").isNone(), true)
    let first = archiveView.entryAt(0).getOrThrow()
    let (firstCanonical, _) = first
    @Expect(firstCanonical, "作者:甲")
    let second = archiveView.entryAt(1).getOrThrow()
    let (_, secondTranslated) = second
    @Expect(secondTranslated, "Chinese")

    // 不同 scope（tank 详情）写入同一规范实体：档案详情视图直接读到合集视图写回的新翻译。
    let tankEntries = ArrayList<(String, String)>()
    tankEntries.add(("作者:甲", "作者:李四"))
    let tankView = cache
        .storeTagTranslations("server", "account", "tag-translations:tank:tank:1:zh", "zh", tankEntries)
        .getOrThrow()
    @Expect(tankView.size, 1)
    @Expect(tankView.lookup("作者:甲").getOrThrow(), "作者:李四")
    @Expect(cache.openTagTranslations("server", "account", "tag-translations:archive:arc:1:zh", "zh")
        .getOrThrow().lookup("作者:甲").getOrThrow(), "作者:李四")

    // 整表替换只影响自身 membership。
    let replaced = cache
        .storeTagTranslations("server", "account", "tag-translations:archive:arc:1:zh", "zh",
            translationEntries())
        .getOrThrow()
    @Expect(replaced.size, 2)
    @Expect(cache.openTagTranslations("server", "account", "tag-translations:tank:tank:1:zh", "zh")
        .getOrThrow().size, 1)
    cache.close()

    // 重开、账户隔离与服务器清理。
    let reopened = OfflineCache.open(path).getOrThrow()
    @Expect(reopened.openTagTranslations("server", "account", "tag-translations:archive:arc:1:zh", "zh")
        .getOrThrow().lookup("作者:甲").getOrThrow(), "作者:张三")
    @Expect(reopened.openTagTranslations("server", "other", "tag-translations:archive:arc:1:zh", "zh")
        .isNone(), true)
    reopened.clearServer("server")
    @Expect(reopened.openTagTranslations("server", "account", "tag-translations:archive:arc:1:zh", "zh")
        .isNone(), true)
    reopened.close()
}

@Test
func tagTranslationViewsIsolateByLanguageAndRankBound(): Unit {
    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    let zh = cache
        .storeTagTranslations("server", "account", "tag-translations:archive:arc:1:zh", "zh", translationEntries())
        .getOrThrow()
    let enEntries = ArrayList<(String, String)>()
    enEntries.add(("语言:中文", "Chinese (EN)"))
    let en = cache
        .storeTagTranslations("server", "account", "tag-translations:archive:arc:1:en", "en", enEntries)
        .getOrThrow()
    @Expect(zh.lookup("语言:中文").getOrThrow(), "Chinese")
    @Expect(en.lookup("语言:中文").getOrThrow(), "Chinese (EN)")

    @Expect(zh.entryAt(-1).isNone(), true)
    @Expect(zh.entryAt(2).isNone(), true)
    let firstEntry = zh.entryAt(0).getOrThrow()
    let (firstRaw, _) = firstEntry
    @Expect(firstRaw, "作者:甲")
    cache.close()
}
