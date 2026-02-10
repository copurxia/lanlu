package lanlu.controllers

import cjoy.*
import lanlu.models.*
import lanlu.views.*
import lanlu.dao.*
import lanlu.middleware.*
import std.convert.*
import std.collection.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*

/**
 * 搜索控制器
 */
public class SearchController {

    /**
     * 从逗号分隔的 tags 字符串中提取并去重标签（namespace:name），用于批量翻译。
     */
    private static func collectUniqueTags(tagsString: String, seen: HashMap<String, Bool>, out: ArrayList<String>) {
        if (tagsString.size == 0) { return }
        let parts = tagsString.split(",")
        for (p in parts) {
            let t = p.trimAscii()
            if (t.size == 0) { continue }
            match (seen.get(t)) {
                case Some(_) => ()
                case None =>
                    seen[t] = true
                    out.add(t)
            }
        }
    }

    /**
     * 搜索归档
     */
    public static func searchArchives(ctx: JoyContext) {
        let category = ctx.getQuery("category") ?? ""
        let filter = ctx.getQuery("filter") ?? ""
        let tankoubonId = ctx.getQuery("tankoubon_id") ?? ""

        // 处理分页参数
        let pageStr = ctx.getQuery("page") ?? "1"
        let pageSizeStr = ctx.getQuery("pageSize") ?? "20"
        let sortby = ctx.getQuery("sortby") ?? "title"
        let order = ctx.getQuery("order") ?? "asc"

        // 处理过滤参数
        let newOnlyStr = ctx.getQuery("newonly") ?? "false"
        let untaggedOnlyStr = ctx.getQuery("untaggedonly") ?? "false"
        let groupByTanksStr = ctx.getQuery("groupby_tanks") ?? "false"  // 默认为false
        let favoriteOnlyStr = ctx.getQuery("favoriteonly") ?? "false"
        let favoriteTankoubonsOnlyStr = ctx.getQuery("favorite_tankoubons_only") ?? "false"
        let newOnly = newOnlyStr == "true" || newOnlyStr == "1"
        let untaggedOnly = untaggedOnlyStr == "true" || untaggedOnlyStr == "1"
        let groupByTanks = groupByTanksStr == "true" || groupByTanksStr == "1"
        let favoriteOnly = favoriteOnlyStr == "true" || favoriteOnlyStr == "1"
        let favoriteTankoubonsOnly = favoriteTankoubonsOnlyStr == "true" || favoriteTankoubonsOnlyStr == "1"

        // 处理日期范围参数
        let dateFrom = ctx.getQuery("date_from") ?? ""
        let dateTo = ctx.getQuery("date_to") ?? ""

        // 处理语言参数（用于标签翻译）
        let lang = ctx.getQuery("lang") ?? ""

        // 解析分页参数
        var page = 1i32
        var pageSize = 20i32
        var start = 0i32
        var count = 20i32

        page = try {
            Int32.parse(pageStr)
        } catch (e: Exception) {
            1i32
        }
        if (page < 1i32) { page = 1i32 }

        pageSize = try {
            Int32.parse(pageSizeStr)
        } catch (e: Exception) {
            20i32
        }
        if (pageSize < 1i32) { pageSize = 20i32 }
        if (pageSize > 200i32) { pageSize = 200i32 }

        start = (page - 1i32) * pageSize
        count = pageSize

        // 获取用户ID（用于 newOnly 过滤）
        let userIdOpt = AuthMiddleware.optionalUser(ctx)
        let userId: Int64 = match (userIdOpt) {
            case Some(id) => id
            case None => 0
        }

        // 如果启用了 favoriteTankoubonsOnly，直接返回用户收藏的合集列表
        if (favoriteTankoubonsOnly && userId > 0) {
            let (tankoubonIds, totalTankCount) = UserTankoubonFavoriteDao.getUserFavoriteTankoubonIdsPaged(userId, start, count)

            // 批量获取收藏时间
            let tankFavoriteTimeMap = UserTankoubonFavoriteDao.getBatchFavoriteTime(userId, tankoubonIds)

            // 批量获取合集聚合元数据 + 归档列表，避免逐个查询
            let aggMap = TankoubonDao.getBatchAggregatedMetadata(tankoubonIds, userId)
            let tankArchivesCache = TankoubonDao.getBatchArchivesInTankoubon(tankoubonIds)

            // 批量获取标签翻译映射（按请求维度一次查询）
            var tagTranslations: HashMap<String, String> = HashMap<String, String>()
            if (lang.size > 0) {
                var uniqueTags = ArrayList<String>()
                var seenTags: HashMap<String, Bool> = HashMap<String, Bool>()
                for ((_, agg) in aggMap) {
                    collectUniqueTags(agg.tags, seenTags, uniqueTags)
                }
                if (uniqueTags.size > 0) {
                    tagTranslations = TagDao.batchGetTranslations(uniqueTags.toArray(), lang)
                }
            }

            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("data")
            w.startArray()
            for (tid in tankoubonIds) {
                match (aggMap.get(tid)) {
                    case Some(agg) =>
                        let tankFavoriteTime = match (tankFavoriteTimeMap.get(tid)) {
                            case Some(time) => time
                            case None => 0
                        }

                        let translatedTags = if (lang.size > 0) {
                            TagDao.translateTagsString(agg.tags, lang, tagTranslations)
                        } else {
                            agg.tags
                        }

                        w.startObject()
                        w.writeName("type").writeValue("tankoubon")
                        w.writeName("tankoubon_id").writeValue(agg.tankoubon_id)
                        w.writeName("name").writeValue(agg.name)
                        w.writeName("summary").writeValue(agg.summary)
                        w.writeName("cover_asset_id").writeValue(agg.cover_asset_id)
                        w.writeName("tags").writeValue(translatedTags)
                        w.writeName("archives")
                        w.startArray()
                        match (tankArchivesCache.get(tid)) {
                            case Some(archives) =>
                                for (archiveId in archives) {
                                    w.writeValue(archiveId)
                                }
                            case None => ()
                        }
                        w.endArray()
                        w.writeName("pagecount").writeValue(agg.pagecount)
                        w.writeName("progress").writeValue(agg.progress)
                        w.writeName("lastreadtime").writeValue(agg.last_read_time)
                        w.writeName("isnew").writeValue(agg.isnew)
                        w.writeName("archive_count").writeValue(agg.archive_count)
                        w.writeName("isfavorite").writeValue(true)
                        w.writeName("favoritetime").writeValue(tankFavoriteTime)
                        w.endObject()
                    case None => ()
                }
            }
            w.endArray()
            w.writeName("draw").writeValue(0)
            w.writeName("page").writeValue(page)
            w.writeName("pageSize").writeValue(pageSize)
            w.writeName("recordsFiltered").writeValue(totalTankCount)
            w.writeName("recordsTotal").writeValue(totalTankCount)
            w.endObject()
            w.flush()
            ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
            return
        }

        var archives: Array<Archive> = Array<Archive>()
        var totalCount: Int64 = 0
        var responseItemTypes: ArrayList<String> = ArrayList<String>()
        var responseItemIds: ArrayList<String> = ArrayList<String>()
        var archiveMap: HashMap<String, Archive> = HashMap<String, Archive>()
        var tankoubonIdsList: ArrayList<String> = ArrayList<String>()

        if (groupByTanks) {
            // 分组分页下推到数据库：避免 start=-1 全量拉取 + 大 IN 映射查询。
            let (groupedRows, groupedTotal) = ArchiveDao.searchArchivesGrouped(
                filter,
                category,
                Int32(start),
                Int32(count),
                sortby,
                order,
                newOnly,
                untaggedOnly,
                favoriteOnly,
                dateFrom,
                dateTo,
                userId,
                tankoubonId
            )

            totalCount = groupedTotal
            var pagedArchives = ArrayList<Archive>()
            for (row in groupedRows) {
                let itemType = if (row.group_item_type.size > 0) { row.group_item_type } else { "archive" }
                let itemId = if (row.group_item_id.size > 0) { row.group_item_id } else { row.id }

                responseItemTypes.add(itemType)
                responseItemIds.add(itemId)

                if (itemType == "tankoubon") {
                    tankoubonIdsList.add(itemId)
                    continue
                }

                // archive item
                let archive = Archive()
                archive.id = row.id
                archive.internalId = row.internalId
                archive.title = row.title
                archive.filename = row.filename
                archive.summary = row.summary
                archive.thumbhash = row.thumbhash
                archive.cover_asset_id = row.cover_asset_id
                archive.created_at = row.created_at
                archive.updated_at = row.updated_at
                archive.relative_path = row.relative_path
                archive.file_size = row.file_size
                archive.pagecount = row.pagecount
                archive.archive_type = row.archive_type
                archive.tags = row.tags

                pagedArchives.add(archive)
                archiveMap[archive.id] = archive
            }
            archives = pagedArchives.toArray()
        } else {
            let (pagedArchives, pagedTotalCount) = ArchiveModel.searchArchives(filter, category, Int32(start), Int32(count), sortby, order, newOnly, untaggedOnly, favoriteOnly, dateFrom, dateTo, userId, tankoubonId)
            archives = pagedArchives
            totalCount = pagedTotalCount
            for (archive in archives) {
                responseItemTypes.add("archive")
                responseItemIds.add(archive.id)
                archiveMap[archive.id] = archive
            }
        }

        // 批量获取当前页 Tankoubon 聚合数据 / 收藏信息。
        let tankoubonDataCache = TankoubonDao.getBatchAggregatedMetadata(tankoubonIdsList.toArray(), userId)
        let tankFavoriteMap = UserTankoubonFavoriteDao.getBatchFavoriteStatus(userId, tankoubonIdsList.toArray())
        let tankFavoriteTimeMap = UserTankoubonFavoriteDao.getBatchFavoriteTime(userId, tankoubonIdsList.toArray())
        let tankoubonArchivesCache = TankoubonDao.getBatchArchivesInTankoubon(tankoubonIdsList.toArray())

        // 批量获取用户的 isNew 状态、收藏状态和收藏时间
        var isNewMap = HashMap<Int64, Bool>()
        var isFavoriteMap = HashMap<Int64, Bool>()
        var favoriteTimeMap = HashMap<Int64, Int64>()
        var progressMap = HashMap<Int64, Int32>()
        var lastReadTimeMap = HashMap<Int64, Int64>()
        if (userId > 0) {
            var archiveIds = ArrayList<Int64>()
            for (archive in archives) {
                if (archive.internalId > 0) {
                    archiveIds.add(archive.internalId)
                }
            }
            if (archiveIds.size > 0) {
                isNewMap = UserArchiveStatusDao.getBatchStatus(userId, archiveIds.toArray())
                isFavoriteMap = UserFavoriteDao.getBatchFavoriteStatus(userId, archiveIds.toArray())
                favoriteTimeMap = UserFavoriteDao.getBatchFavoriteTime(userId, archiveIds.toArray())
                let (progressMapResult, lastReadTimeMapResult) = UserArchiveStatusDao.getBatchProgressAndTime(userId, archiveIds.toArray())
                progressMap = progressMapResult
                lastReadTimeMap = lastReadTimeMapResult
            }
        }

        // 批量获取标签翻译映射（按请求维度一次查询）
        var tagTranslations: HashMap<String, String> = HashMap<String, String>()
        if (lang.size > 0) {
            var uniqueTags = ArrayList<String>()
            var seenTags: HashMap<String, Bool> = HashMap<String, Bool>()
            for (archive in archives) {
                collectUniqueTags(archive.tags, seenTags, uniqueTags)
            }
            for ((_, tank) in tankoubonDataCache) {
                collectUniqueTags(tank.tags, seenTags, uniqueTags)
            }
            if (uniqueTags.size > 0) {
                tagTranslations = TagDao.batchGetTranslations(uniqueTags.toArray(), lang)
            }
        }

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("data")
        w.startArray()

        for (i in 0..responseItemTypes.size) {
            let itemType = responseItemTypes[i]
            let itemId = responseItemIds[i]

            if (itemType == "tankoubon") {
                match (tankoubonDataCache.get(itemId)) {
                    case Some(tankoubon) =>
                        let translatedTankTags = if (lang.size > 0) {
                            TagDao.translateTagsString(tankoubon.tags, lang, tagTranslations)
                        } else {
                            tankoubon.tags
                        }

                        var isTankFavorite = false
                        match (tankFavoriteMap.get(itemId)) {
                            case Some(status) => isTankFavorite = status
                            case None => isTankFavorite = false
                        }
                        var tankFavoriteTime = 0
                        match (tankFavoriteTimeMap.get(itemId)) {
                            case Some(time) => tankFavoriteTime = time
                            case None => tankFavoriteTime = 0
                        }

                        w.startObject()
                        w.writeName("type").writeValue("tankoubon")
                        w.writeName("tankoubon_id").writeValue(tankoubon.tankoubon_id)
                        w.writeName("name").writeValue(tankoubon.name)
                        w.writeName("summary").writeValue(tankoubon.summary)
                        w.writeName("cover_asset_id").writeValue(tankoubon.cover_asset_id)
                        w.writeName("tags").writeValue(translatedTankTags)
                        w.writeName("archives")
                        w.startArray()
                        match (tankoubonArchivesCache.get(itemId)) {
                            case Some(tankoubonArchives) =>
                                for (archiveId in tankoubonArchives) {
                                    w.writeValue(archiveId)
                                }
                            case None => ()
                        }
                        w.endArray()
                        w.writeName("pagecount").writeValue(tankoubon.pagecount)
                        w.writeName("progress").writeValue(tankoubon.progress)
                        w.writeName("lastreadtime").writeValue(tankoubon.last_read_time)
                        w.writeName("isnew").writeValue(tankoubon.isnew)
                        w.writeName("archive_count").writeValue(tankoubon.archive_count)
                        w.writeName("isfavorite").writeValue(isTankFavorite)
                        w.writeName("favoritetime").writeValue(tankFavoriteTime)
                        w.endObject()
                    case None => ()
                }
                continue
            }

            match (archiveMap.get(itemId)) {
                case Some(archive) =>
                    let internalId = archive.internalId
                    var isNew = true
                    var isFavorite = false
                    var favoriteTime: Int64 = 0
                    var progress: Int32 = 0
                    var lastReadTime: Int64 = 0
                    if (internalId > 0) {
                        match (isNewMap.get(internalId)) {
                            case Some(status) => isNew = status
                            case None => isNew = true
                        }
                        match (isFavoriteMap.get(internalId)) {
                            case Some(status) => isFavorite = status
                            case None => isFavorite = false
                        }
                        match (favoriteTimeMap.get(internalId)) {
                            case Some(time) => favoriteTime = time
                            case None => favoriteTime = 0
                        }
                        if (progressMap.contains(internalId)) {
                            match (progressMap.get(internalId)) {
                                case Some(p) => if (p > 0i32) { progress = p }
                                case None => ()
                            }
                        }
                        if (lastReadTimeMap.contains(internalId)) {
                            match (lastReadTimeMap.get(internalId)) {
                                case Some(t) => lastReadTime = t
                                case None => ()
                            }
                        }
                    }

                    let translatedArchiveTags = if (lang.size > 0) {
                        TagDao.translateTagsString(archive.tags, lang, tagTranslations)
                    } else {
                        archive.tags
                    }

                    w.startObject()
                    w.writeName("type").writeValue("archive")
                    w.writeName("arcid").writeValue(archive.id)
                    w.writeName("archivetype").writeValue(archive.archive_type)
                    w.writeName("filename").writeValue(archive.filename)
                    w.writeName("isnew").writeValue(isNew)
                    w.writeName("isfavorite").writeValue(isFavorite)
                    w.writeName("favoritetime").writeValue(favoriteTime)
                    w.writeName("lastreadtime").writeValue(lastReadTime)
                    w.writeName("pagecount").writeValue(archive.pagecount)
                    w.writeName("progress").writeValue(progress)
                    w.writeName("size").writeValue(archive.size())
                    w.writeName("cover_asset_id").writeValue(archive.cover_asset_id)
                    w.writeName("summary").writeValue(archive.summary)
                    w.writeName("tags").writeValue(translatedArchiveTags)
                    w.writeName("title").writeValue(archive.title)
                    w.endObject()
                case None => ()
            }
        }

        w.endArray()
        w.writeName("draw").writeValue(0)
        w.writeName("page").writeValue(page)
        w.writeName("pageSize").writeValue(pageSize)
        w.writeName("recordsFiltered").writeValue(totalCount)
        w.writeName("recordsTotal").writeValue(totalCount)
        w.endObject()
        w.flush()
        ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
    }

    /**
     * 随机获取归档
     */
    public static func getRandomArchives(ctx: JoyContext) {
        let category = ctx.getQuery("category") ?? ""
        let filter = ctx.getQuery("filter") ?? ""
        let countStr = ctx.getQuery("count") ?? "5"
        let newOnlyStr = ctx.getQuery("newonly") ?? "false"
        let untaggedOnlyStr = ctx.getQuery("untaggedonly") ?? "false"
        let groupByTanksStr = ctx.getQuery("groupby_tanks") ?? "true"  // 随机推荐默认按 Tankoubon 分组
        let lang = ctx.getQuery("lang") ?? ""

        let count = try {
            Int32.parse(countStr)
        } catch (e: Exception) {
            5i32
        }
        let newOnly = newOnlyStr == "true"
        let untaggedOnly = untaggedOnlyStr == "true"
        let groupByTanks = groupByTanksStr == "true" || groupByTanksStr == "1"

        // 获取用户ID（可选）
        let userIdOpt = AuthMiddleware.optionalUser(ctx)
        let userId: Int64 = match (userIdOpt) {
            case Some(id) => id
            case None => 0
        }

        var archives: Array<Archive> = Array<Archive>()
        var responseItemTypes: ArrayList<String> = ArrayList<String>()
        var responseItemIds: ArrayList<String> = ArrayList<String>()
        var archiveMap: HashMap<String, Archive> = HashMap<String, Archive>()
        var tankoubonIdsList: ArrayList<String> = ArrayList<String>()
        var totalCount: Int64 = 0

        if (groupByTanks) {
            let (groupedRows, groupedTotal) = ArchiveDao.searchArchivesGrouped(
                filter,
                category,
                0,
                count,
                "RANDOM()",
                "desc",
                newOnly,
                untaggedOnly,
                false,
                "",
                "",
                userId,
                ""
            )

            totalCount = groupedTotal
            var groupedArchives = ArrayList<Archive>()
            for (row in groupedRows) {
                let itemType = if (row.group_item_type.size > 0) { row.group_item_type } else { "archive" }
                let itemId = if (row.group_item_id.size > 0) { row.group_item_id } else { row.id }

                responseItemTypes.add(itemType)
                responseItemIds.add(itemId)

                if (itemType == "tankoubon") {
                    tankoubonIdsList.add(itemId)
                    continue
                }

                let archive = Archive()
                archive.id = row.id
                archive.internalId = row.internalId
                archive.title = row.title
                archive.filename = row.filename
                archive.summary = row.summary
                archive.thumbhash = row.thumbhash
                archive.cover_asset_id = row.cover_asset_id
                archive.created_at = row.created_at
                archive.updated_at = row.updated_at
                archive.relative_path = row.relative_path
                archive.file_size = row.file_size
                archive.pagecount = row.pagecount
                archive.archive_type = row.archive_type
                archive.tags = row.tags

                groupedArchives.add(archive)
                archiveMap[archive.id] = archive
            }
            archives = groupedArchives.toArray()
        } else {
            let (resultArchives, resultTotal) = ArchiveModel.searchArchives(filter, category, 0, count, "RANDOM()", "desc", newOnly, untaggedOnly)
            archives = resultArchives
            totalCount = resultTotal
            for (archive in archives) {
                responseItemTypes.add("archive")
                responseItemIds.add(archive.id)
                archiveMap[archive.id] = archive
            }
        }

        // 批量获取当前页 Tankoubon 聚合数据 / 收藏信息。
        let tankoubonDataCache = TankoubonDao.getBatchAggregatedMetadata(tankoubonIdsList.toArray(), userId)
        let tankFavoriteMap = UserTankoubonFavoriteDao.getBatchFavoriteStatus(userId, tankoubonIdsList.toArray())
        let tankFavoriteTimeMap = UserTankoubonFavoriteDao.getBatchFavoriteTime(userId, tankoubonIdsList.toArray())
        let tankoubonArchivesCache = TankoubonDao.getBatchArchivesInTankoubon(tankoubonIdsList.toArray())

        // 批量获取用户的 isNew 状态和收藏状态
        var isNewMap = HashMap<Int64, Bool>()
        var isFavoriteMap = HashMap<Int64, Bool>()
        var favoriteTimeMap = HashMap<Int64, Int64>()
        var progressMap = HashMap<Int64, Int32>()
        var lastReadTimeMap = HashMap<Int64, Int64>()
        if (userId > 0) {
                // 使用 archive.internalId，无需额外查询
                var archiveIds = ArrayList<Int64>()
                for (archive in archives) {
                    if (archive.internalId > 0) {
                        archiveIds.add(archive.internalId)
                    }
                }
                if (archiveIds.size > 0) {
                    isNewMap = UserArchiveStatusDao.getBatchStatus(userId, archiveIds.toArray())
                    isFavoriteMap = UserFavoriteDao.getBatchFavoriteStatus(userId, archiveIds.toArray())
                    favoriteTimeMap = UserFavoriteDao.getBatchFavoriteTime(userId, archiveIds.toArray())
                    let (progressMapResult, lastReadTimeMapResult) = UserArchiveStatusDao.getBatchProgressAndTime(userId, archiveIds.toArray())
                    progressMap = progressMapResult
                    lastReadTimeMap = lastReadTimeMapResult
                }
        }

        // 批量获取标签翻译映射（按请求维度一次查询）
        var tagTranslations: HashMap<String, String> = HashMap<String, String>()
        if (lang.size > 0) {
            var uniqueTags = ArrayList<String>()
            var seenTags: HashMap<String, Bool> = HashMap<String, Bool>()
            for (archive in archives) {
                collectUniqueTags(archive.tags, seenTags, uniqueTags)
            }
            for ((_, tank) in tankoubonDataCache) {
                collectUniqueTags(tank.tags, seenTags, uniqueTags)
            }
            if (uniqueTags.size > 0) {
                tagTranslations = TagDao.batchGetTranslations(uniqueTags.toArray(), lang)
            }
        }

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("data")
        w.startArray()
        for (i in 0..responseItemTypes.size) {
            let itemType = responseItemTypes[i]
            let itemId = responseItemIds[i]

            if (itemType == "tankoubon") {
                match (tankoubonDataCache.get(itemId)) {
                    case Some(tankoubon) =>
                        let translatedTankTags = if (lang.size > 0) {
                            TagDao.translateTagsString(tankoubon.tags, lang, tagTranslations)
                        } else {
                            tankoubon.tags
                        }

                        var isTankFavorite = false
                        match (tankFavoriteMap.get(itemId)) {
                            case Some(status) => isTankFavorite = status
                            case None => isTankFavorite = false
                        }
                        var tankFavoriteTime = 0
                        match (tankFavoriteTimeMap.get(itemId)) {
                            case Some(time) => tankFavoriteTime = time
                            case None => tankFavoriteTime = 0
                        }

                        w.startObject()
                        w.writeName("type").writeValue("tankoubon")
                        w.writeName("tankoubon_id").writeValue(tankoubon.tankoubon_id)
                        w.writeName("name").writeValue(tankoubon.name)
                        w.writeName("summary").writeValue(tankoubon.summary)
                        w.writeName("cover_asset_id").writeValue(tankoubon.cover_asset_id)
                        w.writeName("tags").writeValue(translatedTankTags)
                        w.writeName("archives")
                        w.startArray()
                        match (tankoubonArchivesCache.get(itemId)) {
                            case Some(tankoubonArchives) =>
                                for (archiveId in tankoubonArchives) {
                                    w.writeValue(archiveId)
                                }
                            case None => ()
                        }
                        w.endArray()
                        w.writeName("pagecount").writeValue(tankoubon.pagecount)
                        w.writeName("progress").writeValue(tankoubon.progress)
                        w.writeName("lastreadtime").writeValue(tankoubon.last_read_time)
                        w.writeName("isnew").writeValue(tankoubon.isnew)
                        w.writeName("archive_count").writeValue(tankoubon.archive_count)
                        w.writeName("isfavorite").writeValue(isTankFavorite)
                        w.writeName("favoritetime").writeValue(tankFavoriteTime)
                        w.endObject()
                    case None => ()
                }
                continue
            }

            match (archiveMap.get(itemId)) {
                case Some(archive) =>
                    let internalId = archive.internalId
                    var isNew = true
                    var isFavorite = false
                    var favoriteTime: Int64 = 0
                    var progress: Int32 = 0
                    var lastReadTime: Int64 = 0
                    if (internalId > 0) {
                        match (isNewMap.get(internalId)) {
                            case Some(status) => isNew = status
                            case None => isNew = true
                        }
                        match (isFavoriteMap.get(internalId)) {
                            case Some(status) => isFavorite = status
                            case None => isFavorite = false
                        }
                        match (favoriteTimeMap.get(internalId)) {
                            case Some(time) => favoriteTime = time
                            case None => favoriteTime = 0
                        }
                        if (progressMap.contains(internalId)) {
                            match (progressMap.get(internalId)) {
                                case Some(p) => if (p > 0i32) { progress = p }
                                case None => ()
                            }
                        }
                        if (lastReadTimeMap.contains(internalId)) {
                            match (lastReadTimeMap.get(internalId)) {
                                case Some(t) => lastReadTime = t
                                case None => ()
                            }
                        }
                    }

                    let translatedRandomTags = if (lang.size > 0) {
                        TagDao.translateTagsString(archive.tags, lang, tagTranslations)
                    } else {
                        archive.tags
                    }

                    w.startObject()
                    w.writeName("type").writeValue("archive")
                    w.writeName("arcid").writeValue(archive.id)
                    w.writeName("archivetype").writeValue(archive.archive_type)
                    w.writeName("filename").writeValue(archive.filename)
                    w.writeName("isnew").writeValue(isNew)
                    w.writeName("isfavorite").writeValue(isFavorite)
                    w.writeName("favoritetime").writeValue(favoriteTime)
                    w.writeName("lastreadtime").writeValue(lastReadTime)
                    w.writeName("pagecount").writeValue(archive.pagecount)
                    w.writeName("progress").writeValue(progress)
                    w.writeName("size").writeValue(archive.size())
                    w.writeName("cover_asset_id").writeValue(archive.cover_asset_id)
                    w.writeName("summary").writeValue(archive.summary)
                    w.writeName("tags").writeValue(translatedRandomTags)
                    w.writeName("title").writeValue(archive.title)
                    w.endObject()
                case None => ()
            }
        }
        w.endArray()
        w.writeName("recordsTotal").writeValue(totalCount)
        w.endObject()
        w.flush()
        ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
    }

    /**
     * 获取搜索建议
     */
    public static func getSearchSuggestions(ctx: JoyContext) {
        let suggestions = "[\"suggestion1\",\"suggestion2\",\"suggestion3\"]"
        ResponseView.successJson(ctx, suggestions, "获取搜索建议成功")
    }

}
