package lanlu_client_next.net

import std.collection.ArrayList
import std.fs.{Directory, Path}

private func pageStoreTestPages(): ArrayList<PageInfo> {
    let pages = ArrayList<PageInfo>()
    let image = PageInfo()
    image.id = "chapter:1/001.avif"
    image.sourcePath = image.id
    image.pageType = "image"
    image.title = "第一页"
    image.description = "binary-safe : path"
    image.orderIndex = 1
    image.thumbAssetId = 12
    let subtitle = SubtitleAttachment()
    subtitle.assetId = 42
    subtitle.kind = "subtitle"
    subtitle.name = "中文.ass"
    subtitle.language = "zh-CN"
    subtitle.orderIndex = 2
    image.subtitleAttachments.add(subtitle)
    pages.add(image)

    let video = PageInfo()
    video.id = "media/video.mp4"
    video.sourcePath = video.id
    video.pageType = "video"
    video.lyricsAssetId = 99
    pages.add(video)
    return pages
}

@Test
func archivePagesPersistByRankReplaceAtomicallyAndReopen(): Unit {
    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    let first = cache.storePages("server", "account", "arc:1", pageStoreTestPages()).getOrThrow()
    @Expect(first.size, 2)
    @Expect(first.stats.image, 1)
    @Expect(first.stats.video, 1)
    @Expect(first[0].title, "第一页")
    @Expect(first[0].subtitleAttachments[0].assetId, 42)
    @Expect(first[1].lyricsAssetId, 99)

    let replacement = ArrayList<PageInfo>()
    let html = PageInfo()
    html.id = "text/chapter.xhtml"
    html.sourcePath = html.id
    html.pageType = "html"
    replacement.add(html)
    let second = cache.storePages("server", "account", "arc:1", replacement).getOrThrow()
    @Expect(second.size, 1)
    @Expect(second[0].id, "text/chapter.xhtml")
    cache.close()

    let reopened = OfflineCache.open(path).getOrThrow()
    let view = reopened.openPages("server", "account", "arc:1").getOrThrow()
    @Expect(view.size, 1)
    @Expect(view.stats.html, 1)
    @Expect(view[0].id, "text/chapter.xhtml")
    @Expect(reopened.openPages("server", "other-account", "arc:1").isNone(), true)
    reopened.clearServer("server")
    @Expect(reopened.openPages("server", "account", "arc:1").isNone(), true)
    reopened.close()
}

@Test
func memoryArchivePageViewIsBoundedAndIterable(): Unit {
    let view = ArchivePageView.memory("arc", pageStoreTestPages())
    var count: Int64 = 0
    for (page in view) {
        @Expect(page.id.size > 0, true)
        count += 1
    }
    @Expect(count, 2)
    @Expect(view.itemAt(-1).isNone(), true)
    @Expect(view.itemAt(2).isNone(), true)
}

@Test
func singlePageUpdateWritesOnlyOneRankAndReplacesRevision(): Unit {
    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    let view = cache.storePages("server", "account", "arc:1", pageStoreTestPages()).getOrThrow()
    @Expect(view.size, 2)

    // 编辑第一页：只更新单页主记录，不整本重写。
    let edited = view[0]
    edited.title = "更新后的标题"
    edited.description = "新的描述"
    @Expect(cache.updatePage("server", "account", "arc:1", 0, edited), true)

    // 失效热点窗口后重读 rank 0：主记录已被更新（envelope revision 替换）。
    view.invalidateRank(0)
    @Expect(view[0].title, "更新后的标题")
    @Expect(view[0].description, "新的描述")
    // rank 1 不受影响。
    @Expect(view[1].lyricsAssetId, 99)
    @Expect(view[1].title, "")

    // 重开后单页更新仍持久化，整页统计不变。
    cache.close()
    let reopened = OfflineCache.open(path).getOrThrow()
    let reopenedView = reopened.openPages("server", "account", "arc:1").getOrThrow()
    @Expect(reopenedView.size, 2)
    @Expect(reopenedView.stats.image, 1)
    @Expect(reopenedView.stats.video, 1)
    @Expect(reopenedView[0].title, "更新后的标题")
    @Expect(reopenedView[1].lyricsAssetId, 99)
    reopened.close()
}

@Test
func singlePageUpdateInvalidatesHotWindowAndIgnoresUnknownRank(): Unit {
    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    let view = cache.storePages("server", "account", "arc:1", pageStoreTestPages()).getOrThrow()

    // 先预热热点窗口，再更新并失效。
    let _ = view[0].title
    view.invalidateRank(0)
    let edited = view[0]
    edited.title = "热点失效后重读"
    @Expect(cache.updatePage("server", "account", "arc:1", 0, edited), true)
    @Expect(view[0].title, "热点失效后重读")

    // 越界 rank 更新返回 false 且不崩溃。
    let bogus = view[0]
    @Expect(cache.updatePage("server", "account", "arc:1", 99, bogus), false)
    cache.close()
}
