package lanlu_client_next.net

import std.collection.ArrayList

private func projectionMeta(): ArchiveMeta {
    let meta = ArchiveMeta()
    meta.arcid = "arc:1"
    meta.title = "档案标题"
    meta.description = "档案简介"
    meta.archivetype = "image"
    meta.filename = "archive.zip"
    meta.tags.add("作者:甲")
    meta.tags.add("语言:中文")
    meta.coverAssetId = 42
    meta.pagecount = 120
    meta.progress = 17
    meta.size = 4096
    meta.isnew = true
    meta.isfavorite = true
    meta.lastreadtime = 123456
    return meta
}

@Test
func searchItemFromMetaProjectsAllOverlappingFields(): Unit {
    let meta = projectionMeta()
    let item = searchItemFromMeta(meta)
    @Expect(item.arcid, "arc:1")
    @Expect(item.title, "档案标题")
    @Expect(item.description, "档案简介")
    @Expect(item.archivetype, "image")
    @Expect(item.filename, "archive.zip")
    @Expect(item.tagsCsv, "作者:甲, 语言:中文")
    @Expect(item.coverAssetId, 42)
    @Expect(item.pagecount, 120)
    @Expect(item.progress, 17)
    @Expect(item.size, 4096)
    @Expect(item.isnew, true)
    @Expect(item.isfavorite, true)
    @Expect(item.lastreadtime, 123456)
}

@Test
func metaFromSearchItemProjectsBackAndTagsSplitMatchesJoin(): Unit {
    let item = searchItemFromMeta(projectionMeta())
    let meta = metaFromSearchItem(item)
    @Expect(meta.arcid, "arc:1")
    @Expect(meta.title, "档案标题")
    @Expect(meta.tags.size, 2)
    @Expect(meta.tags[0], "作者:甲")
    @Expect(meta.tags[1], "语言:中文")
    @Expect(meta.pagecount, 120)
    @Expect(meta.isfavorite, true)

    // join/split 往返稳定：CSV 语义集中在 mapper，AppModel 与编辑器共用。
    let roundTrip = joinTags(splitTags(joinTags(meta.tags)))
    @Expect(roundTrip, "作者:甲, 语言:中文")
    // 去重：重复标签只保留一次。
    let dupes = ArrayList<String>()
    dupes.add("a")
    dupes.add("a")
    dupes.add("b")
    @Expect(joinTags(splitTags(joinTags(dupes))), "a, b")
}

@Test
func copySearchProjectionKeepsIdentityAndOverwritesOverlap(): Unit {
    let dst = SearchItem()
    dst.arcid = "arc:1"
    dst.itemType = "archive"
    dst.title = "旧标题"
    dst.isfavorite = false
    dst.tankoubonId = "ignored"
    let src = searchItemFromMeta(projectionMeta())
    copySearchProjection(dst, src)
    @Expect(dst.arcid, "arc:1")
    @Expect(dst.itemType, "archive")
    @Expect(dst.title, "档案标题")
    @Expect(dst.isfavorite, true)
    @Expect(dst.pagecount, 120)
    // 非重叠身份字段不写入 src 值。
    @Expect(dst.tankoubonId, "ignored")
}

@Test
func categoryProjectionKeepsCatidStableKey(): Unit {
    let admin = AdminCategoryItem()
    admin.id = 7
    admin.catid = "cat:web"
    admin.name = "网页分类"
    admin.archiveCount = 33
    let item = projectAdminToCategory(admin)
    @Expect(item.catid, "cat:web")
    @Expect(item.id, 7)
    @Expect(item.name, "网页分类")
    @Expect(item.archiveCount, 33)
    @Expect(categoryKey("cat:web"), "category:cat:web")
    @Expect(categoryKey("cat:web") != categoryKey("cat:other"), true)
}
