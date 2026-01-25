package lanlu.controllers

import cjoy.*
import lanlu.models.*
import lanlu.views.*
import lanlu.dao.*
import lanlu.middleware.*
import lanlu.utils.*
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

        // 处理分页参数，设置默认值
        let startStr = ctx.getQuery("start") ?? "0"
        let countStr = ctx.getQuery("count") ?? "20"
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
        let start = try {
            Int32.parse(startStr)
        } catch (e: Exception) {
            0i32
        }
        let count = try {
            Int32.parse(countStr)
        } catch (e: Exception) {
            20i32
        }

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
            w.writeName("recordsFiltered").writeValue(totalTankCount)
            w.writeName("recordsTotal").writeValue(totalTankCount)
            w.endObject()
            w.flush()
            ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
            return
        }

        let (archives, totalCount) = ArchiveModel.searchArchives(filter, category, Int32(start), Int32(count), sortby, order, newOnly, untaggedOnly, favoriteOnly, dateFrom, dateTo, userId, tankoubonId)

        // 如果启用了Tankoubon分组，获取归档到Tankoubon的映射
        var tankoubonMapping: HashMap<String, String> = HashMap<String, String>()
        var processedTankoubons: HashMap<String, Bool> = HashMap<String, Bool>()
        var tankoubonDataCache: HashMap<String, TankoubonAggregatedData> = HashMap<String, TankoubonAggregatedData>()
        var tankoubonIdsList: ArrayList<String> = ArrayList<String>()

        if (groupByTanks) {
            // 收集所有归档的arcid
            var arcids: ArrayList<String> = ArrayList<String>()
            for (archive in archives) {
                arcids.add(archive.id)
            }

            // 获取归档到Tankoubon的映射
            tankoubonMapping = ArchiveDao.getArchiveTankoubonMapping(arcids.toArray())

            // 收集所有唯一的 Tankoubon ID
            for ((_, tankoubonId) in tankoubonMapping) {
                match (processedTankoubons.get(tankoubonId)) {
                    case Some(_) => ()  // 已处理，跳过
                    case None =>
                        processedTankoubons[tankoubonId] = true
                        tankoubonIdsList.add(tankoubonId)
                }
            }

            // 批量获取所有 Tankoubon 的聚合数据
            tankoubonDataCache = TankoubonDao.getBatchAggregatedMetadata(tankoubonIdsList.toArray(), userId)
        }

        // 批量获取Tankoubon收藏状态和收藏时间
        let tankFavoriteMap = UserTankoubonFavoriteDao.getBatchFavoriteStatus(userId, tankoubonIdsList.toArray())
        let tankFavoriteTimeMap = UserTankoubonFavoriteDao.getBatchFavoriteTime(userId, tankoubonIdsList.toArray())

        // 批量获取用户的 isNew 状态、收藏状态和收藏时间
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

        // 使用 JsonWriter 构建响应，避免手写 JSON/转义。
        var alreadyAddedTankoubons: HashMap<String, Bool> = HashMap<String, Bool>()

        // 批量获取所有 Tankoubon 的归档列表
        let tankoubonArchivesCache = TankoubonDao.getBatchArchivesInTankoubon(tankoubonIdsList.toArray())

        // 批量获取标签翻译映射（按请求维度一次查询）
        var tagTranslations: HashMap<String, String> = HashMap<String, String>()
        if (lang.size > 0) {
            var uniqueTags = ArrayList<String>()
            var seenTags: HashMap<String, Bool> = HashMap<String, Bool>()
            for (archive in archives) {
                collectUniqueTags(archive.tags, seenTags, uniqueTags)
            }
            if (groupByTanks) {
                for ((_, tank) in tankoubonDataCache) {
                    collectUniqueTags(tank.tags, seenTags, uniqueTags)
                }
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
        for (archive in archives) {
            // 检查此归档是否属于某个Tankoubon
            var belongsToTankoubon = false
            var tankoubonId = ""

            if (groupByTanks) {
                match (tankoubonMapping.get(archive.id)) {
                    case Some(tid) =>
                        tankoubonId = tid
                        belongsToTankoubon = true
                    case None => ()
                }
            }

            // 如果归档属于Tankoubon且该Tankoubon尚未添加，则添加Tankoubon
            var tankoubonAlreadyAdded = false
            if (belongsToTankoubon) {
                match (alreadyAddedTankoubons.get(tankoubonId)) {
                    case Some(_) => tankoubonAlreadyAdded = true
                    case None => ()
                }
            }

            if (belongsToTankoubon && !tankoubonAlreadyAdded) {
                var tankoubonInserted = false
                match (tankoubonDataCache.get(tankoubonId)) {
                    case Some(tankoubon) =>
                        // 翻译标签
                        let translatedTankTags = if (lang.size > 0) {
                            TagDao.translateTagsString(tankoubon.tags, lang, tagTranslations)
                        } else {
                            tankoubon.tags
                        }

                        var isTankFavorite = false
                        match (tankFavoriteMap.get(tankoubonId)) {
                            case Some(status) => isTankFavorite = status
                            case None => isTankFavorite = false
                        }
                        var tankFavoriteTime = 0
                        match (tankFavoriteTimeMap.get(tankoubonId)) {
                            case Some(time) => tankFavoriteTime = time
                            case None => tankFavoriteTime = 0
                        }
                        // 添加Tankoubon条目
                        w.startObject()
                        w.writeName("type").writeValue("tankoubon")
                        w.writeName("tankoubon_id").writeValue(tankoubon.tankoubon_id)
                        w.writeName("name").writeValue(tankoubon.name)
                        w.writeName("summary").writeValue(tankoubon.summary)
                        w.writeName("tags").writeValue(translatedTankTags)
                        w.writeName("archives")
                        w.startArray()
                        match (tankoubonArchivesCache.get(tankoubonId)) {
                            case Some(tankoubonArchives) =>
                                for (archiveId in tankoubonArchives) {
                                    w.writeValue(archiveId)
                                }
                            case None => ()
                        }
                        w.endArray()
                        w.writeName("pagecount").writeValue(tankoubon.pagecount)
                        w.writeName("progress").writeValue(tankoubon.progress)
                        // Keep consistent with other endpoints: lastreadtime is a number.
                        w.writeName("lastreadtime").writeValue(tankoubon.last_read_time)
                        w.writeName("isnew").writeValue(tankoubon.isnew)
                        w.writeName("archive_count").writeValue(tankoubon.archive_count)
                        w.writeName("isfavorite").writeValue(isTankFavorite)
                        w.writeName("favoritetime").writeValue(tankFavoriteTime)
                        w.endObject()

                        alreadyAddedTankoubons[tankoubonId] = true
                        tankoubonInserted = true
                    case None => ()
                }
                // 只有当成功插入Tankoubon条目时才跳过当前归档；否则回退为普通归档展示
                if (tankoubonInserted) {
                    continue
                }
            }

            // 如果归档属于已添加的Tankoubon，跳过
            if (belongsToTankoubon && tankoubonAlreadyAdded) {
                continue
            }

            // 获取用户级别的 isNew 状态、收藏状态和收藏时间
            let internalId = archive.internalId
            var isNew = true  // 默认为新
            var isFavorite = false  // 默认未收藏
            var favoriteTime: Int64 = 0  // 收藏时间，默认为0
            var progress: Int32 = 0  // 阅读进度，默认为0
            var lastReadTime: Int64 = 0  // 最后阅读时间，默认为0
            if (internalId > 0) {
                match (isNewMap.get(internalId)) {
                    case Some(status) => isNew = status
                    case None => isNew = true  // 没有记录，默认为新
                }
                match (isFavoriteMap.get(internalId)) {
                    case Some(status) => isFavorite = status
                    case None => isFavorite = false  // 没有记录，默认未收藏
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

            // 翻译标签
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
            w.writeName("summary").writeValue(archive.summary)
            w.writeName("tags").writeValue(translatedArchiveTags)
            w.writeName("title").writeValue(archive.title)
            w.endObject()
        }
        w.endArray()
        w.writeName("draw").writeValue(0)
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
        let lang = ctx.getQuery("lang") ?? ""

        let count = try {
            Int32.parse(countStr)
        } catch (e: Exception) {
            5i32
        }
        let newOnly = newOnlyStr == "true"
        let untaggedOnly = untaggedOnlyStr == "true"

        // 使用数据库级别的随机排序和过滤条件来获取随机归档
        // 将过滤条件移到SQL查询中，提高性能
        let (resultArchives, _) = ArchiveModel.searchArchives(filter, category, 0, count, "RANDOM()", "desc", newOnly, untaggedOnly)

        // 获取用户ID（可选）
        let userIdOpt = AuthMiddleware.optionalUser(ctx)

        // 批量获取用户的 isNew 状态和收藏状态
        var isNewMap = HashMap<Int64, Bool>()
        var isFavoriteMap = HashMap<Int64, Bool>()
        var progressMap = HashMap<Int64, Int32>()
        var lastReadTimeMap = HashMap<Int64, Int64>()
        match (userIdOpt) {
            case Some(userId) =>
                // 使用 archive.internalId，无需额外查询
                var archiveIds = ArrayList<Int64>()
                for (archive in resultArchives) {
                    if (archive.internalId > 0) {
                        archiveIds.add(archive.internalId)
                    }
                }
                if (archiveIds.size > 0) {
                    isNewMap = UserArchiveStatusDao.getBatchStatus(userId, archiveIds.toArray())
                    isFavoriteMap = UserFavoriteDao.getBatchFavoriteStatus(userId, archiveIds.toArray())
                    let (progressMapResult, lastReadTimeMapResult) = UserArchiveStatusDao.getBatchProgressAndTime(userId, archiveIds.toArray())
                    progressMap = progressMapResult
                    lastReadTimeMap = lastReadTimeMapResult
                }
            case None => ()
        }

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("data")
        w.startArray()
        for (archive in resultArchives) {
            // 获取用户级别的 isNew 状态和收藏状态
            let internalId = archive.internalId
            var isNew = true  // 默认为新
            var isFavorite = false  // 默认未收藏
            var progress: Int32 = 0  // 阅读进度，默认为0
            var lastReadTime: Int64 = 0  // 最后阅读时间，默认为0
            if (internalId > 0) {
                match (isNewMap.get(internalId)) {
                    case Some(status) => isNew = status
                    case None => isNew = true  // 没有记录，默认为新
                }
                match (isFavoriteMap.get(internalId)) {
                    case Some(status) => isFavorite = status
                    case None => isFavorite = false  // 没有记录，默认未收藏
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

            // 翻译标签
            let translatedRandomTags = if (lang.size > 0) {
                TagDao.translateTagsString(archive.tags, lang)
            } else {
                archive.tags
            }

            w.startObject()
            w.writeName("arcid").writeValue(archive.id)
            w.writeName("archivetype").writeValue(archive.archive_type)
            w.writeName("filename").writeValue(archive.filename)
            w.writeName("isnew").writeValue(isNew)
            w.writeName("isfavorite").writeValue(isFavorite)
            w.writeName("lastreadtime").writeValue(lastReadTime)
            w.writeName("pagecount").writeValue(archive.pagecount)
            w.writeName("progress").writeValue(progress)
            w.writeName("size").writeValue(archive.size())
            w.writeName("summary").writeValue(archive.summary)
            w.writeName("tags").writeValue(translatedRandomTags)
            w.writeName("title").writeValue(archive.title)
            w.endObject()
        }
        w.endArray()
        w.writeName("recordsTotal").writeValue(count)
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
