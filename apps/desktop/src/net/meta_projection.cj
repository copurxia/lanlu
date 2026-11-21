package lanlu_client_next.net

import std.collection.ArrayList

// ---- ArchiveMeta ↔ SearchItem 字段投影 ----
// ArchiveMeta 来自 /api/archives/:id/metadata，SearchItem 来自 /api/search；两者重叠字段
// （arcid/title/description/archivetype/filename/coverAssetId/pagecount/progress/size/isnew/
// isfavorite/lastreadtime 与 tags）由一个 mapper 双向维护，避免两个 DTO 各自解析时字段漂移。
// tags 在 SearchItem 中是 CSV 字符串，在 ArchiveMeta 中是 ArrayList<String>；join/split 语义
// 集中在 joinTags/splitTags，AppModel 与元数据编辑器都走同一套。

public func searchItemFromMeta(meta: ArchiveMeta): SearchItem {
    let item = SearchItem()
    item.arcid = meta.arcid
    item.title = meta.title
    item.description = meta.description
    item.archivetype = meta.archivetype
    item.filename = meta.filename
    item.tagsCsv = joinTags(meta.tags)
    item.coverAssetId = meta.coverAssetId
    item.pagecount = meta.pagecount
    item.progress = meta.progress
    item.size = meta.size
    item.isnew = meta.isnew
    item.isfavorite = meta.isfavorite
    item.lastreadtime = meta.lastreadtime
    return item
}

// 把 src 的重叠字段原样拷到 dst（保留 dst 的 arcid/itemType/tankoubonId/archiveCount 等身份字段），
// 供视图内共享对象原地更新后写回规范记录。
public func copySearchProjection(dst: SearchItem, src: SearchItem): Unit {
    dst.title = src.title
    dst.description = src.description
    dst.archivetype = src.archivetype
    dst.filename = src.filename
    dst.tagsCsv = src.tagsCsv
    dst.coverAssetId = src.coverAssetId
    dst.pagecount = src.pagecount
    dst.progress = src.progress
    dst.size = src.size
    dst.isnew = src.isnew
    dst.isfavorite = src.isfavorite
    dst.lastreadtime = src.lastreadtime
}

public func metaFromSearchItem(item: SearchItem): ArchiveMeta {
    let meta = ArchiveMeta()
    meta.arcid = item.arcid
    meta.title = item.title
    meta.description = item.description
    meta.archivetype = item.archivetype
    meta.filename = item.filename
    meta.tags = splitTags(item.tagsCsv)
    meta.coverAssetId = item.coverAssetId
    meta.pagecount = item.pagecount
    meta.progress = item.progress
    meta.size = item.size
    meta.isnew = item.isnew
    meta.isfavorite = item.isfavorite
    meta.lastreadtime = item.lastreadtime
    return meta
}

public func joinTags(tags: ArrayList<String>): String {
    let out = StringBuilder()
    for (i in 0..tags.size) {
        if (i > 0) {
            out.append(", ")
        }
        out.append(tags[i])
    }
    out.toString()
}

public func splitTags(raw: String): ArrayList<String> {
    let out = ArrayList<String>()
    for (part in raw.split(",")) {
        let tag = part.trimAscii()
        if (tag.size > 0 && !out.contains(tag)) {
            out.add(tag)
        }
    }
    out
}

// ---- CategoryItem / AdminCategoryItem 共用 catid 主键 ----
// 管理列表（/api/admin/categories）与上传分类（/api/categories）是同一实体集合的两种视图；
// catid 字符串是跨 DTO 的稳定主键。投影集中在这里，管理行编辑后按 catid 回写，避免两个
// DTO 各维护一份 name/archiveCount 拷贝。

public func categoryKey(catid: String): String {
    return "category:${catid}"
}

public func projectAdminToCategory(admin: AdminCategoryItem): CategoryItem {
    let item = CategoryItem()
    item.catid = admin.catid
    item.id = admin.id
    item.name = admin.name
    item.archiveCount = admin.archiveCount
    return item
}
