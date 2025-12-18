package lrr4cj.controllers

import cjoy.*
import cjoy.json.*
import lrr4cj.models.*
import lrr4cj.views.*
import lrr4cj.dao.*
import lrr4cj.middleware.*
import lrr4cj.config.*
import std.convert.*
import std.collection.*

/**
 * 搜索控制器
 */
public class SearchController {

    /**
     * JSON字符串转义函数
     */
    private static func escapeJson(s: String): String {
        var escaped = s
        escaped = escaped.replace("\\", "\\\\")
        escaped = escaped.replace("\"", "\\\"")
        escaped = escaped.replace("\b", "\\b")
        escaped = escaped.replace("\f", "\\f")
        escaped = escaped.replace("\n", "\\n")
        escaped = escaped.replace("\r", "\\r")
        escaped = escaped.replace("\t", "\\t")
        return escaped
    }
    /**
     * 根据 arcid 获取归档的数据库内部ID
     */
    private static func getArchiveInternalId(arcid: String): Int64 {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("SELECT id FROM archives WHERE arcid = ?")
                    try {
                        stmt.set(0, arcid)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<Int64>(0) ?? 0
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return 0
        }
        return 0
    }

    /**
     * 搜索归档
     */
    public static func searchArchives(ctx: JoyContext) {
        let category = ctx.getQuery("category") ?? ""
        let filter = ctx.getQuery("filter") ?? ""

        // 处理分页参数，设置默认值
        let startStr = ctx.getQuery("start") ?? "0"
        let countStr = ctx.getQuery("count") ?? "20"
        let sortby = ctx.getQuery("sortby") ?? "title"
        let order = ctx.getQuery("order") ?? "asc"

        // 处理过滤参数
        let newOnlyStr = ctx.getQuery("newonly") ?? "false"
        let untaggedOnlyStr = ctx.getQuery("untaggedonly") ?? "false"
        let newOnly = newOnlyStr == "true" || newOnlyStr == "1"
        let untaggedOnly = untaggedOnlyStr == "true" || untaggedOnlyStr == "1"

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

        let (archives, totalCount) = ArchiveModel.searchArchives(filter, category, Int32(start), Int32(count), sortby, order, newOnly, untaggedOnly, userId)

        // 批量获取用户的 isNew 状态和收藏状态
        var isNewMap = HashMap<Int64, Bool>()
        var isFavoriteMap = HashMap<Int64, Bool>()
        if (userId > 0) {
            // 收集所有归档的内部ID
            var archiveIds = ArrayList<Int64>()
            for (archive in archives) {
                let internalId = getArchiveInternalId(archive.id)
                if (internalId > 0) {
                    archiveIds.add(internalId)
                }
            }
            if (archiveIds.size > 0) {
                isNewMap = UserArchiveStatusDao.getBatchStatus(userId, archiveIds.toArray())
                isFavoriteMap = UserFavoriteDao.getBatchFavoriteStatus(userId, archiveIds.toArray())
            }
        }

        // 手动构建JSON数组，按照API文档要求的格式
        var archivesJson = "["
        var isFirst = true
        for (archive in archives) {
            if (!isFirst) {
                archivesJson += ","
            }
            isFirst = false

            // 获取用户级别的 isNew 状态和收藏状态
            let internalId = getArchiveInternalId(archive.id)
            var isNew = true  // 默认为新
            var isFavorite = false  // 默认未收藏
            if (internalId > 0) {
                match (isNewMap.get(internalId)) {
                    case Some(status) => isNew = status
                    case None => isNew = true  // 没有记录，默认为新
                }
                match (isFavoriteMap.get(internalId)) {
                    case Some(status) => isFavorite = status
                    case None => isFavorite = false  // 没有记录，默认未收藏
                }
            }

            archivesJson += "{"
            archivesJson = archivesJson + "\"arcid\":\"${escapeJson(archive.id)}\","
            archivesJson = archivesJson + "\"extension\":\"${escapeJson(archive.extension())}\","
            archivesJson = archivesJson + "\"filename\":\"${escapeJson(archive.filename)}\","
            archivesJson = archivesJson + "\"isnew\":${isNew},"
            archivesJson = archivesJson + "\"isfavorite\":${isFavorite},"
            archivesJson = archivesJson + "\"lastreadtime\":0,"  // lastreadtime 现在从 user_archive_status 获取，暂时返回 0
            archivesJson = archivesJson + "\"pagecount\":${archive.pagecount},"
            archivesJson = archivesJson + "\"progress\":0,"  // progress 现在从 user_archive_status 获取，暂时返回 0
            archivesJson = archivesJson + "\"size\":${archive.size()},"
            archivesJson = archivesJson + "\"summary\":\"${escapeJson(archive.summary)}\","
            archivesJson = archivesJson + "\"tags\":\"${escapeJson(archive.tags)}\","
            archivesJson = archivesJson + "\"title\":\"${escapeJson(archive.title)}\""
            archivesJson += "}"
        }
        archivesJson += "]"

        let result = "{\"data\":" + archivesJson + ",\"draw\":0,\"recordsFiltered\":" + totalCount.toString() + ",\"recordsTotal\":" + totalCount.toString() + "}"
        ctx.json(result)
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
        match (userIdOpt) {
            case Some(userId) =>
                // 收集所有归档的内部ID
                var archiveIds = ArrayList<Int64>()
                for (archive in resultArchives) {
                    let internalId = getArchiveInternalId(archive.id)
                    if (internalId > 0) {
                        archiveIds.add(internalId)
                    }
                }
                if (archiveIds.size > 0) {
                    isNewMap = UserArchiveStatusDao.getBatchStatus(userId, archiveIds.toArray())
                    isFavoriteMap = UserFavoriteDao.getBatchFavoriteStatus(userId, archiveIds.toArray())
                }
            case None => ()
        }

        // 手动构建JSON数组，按照API文档要求的格式
        var archivesJson = "["
        var isFirst = true
        for (archive in resultArchives) {
            if (!isFirst) {
                archivesJson += ","
            }
            isFirst = false

            // 获取用户级别的 isNew 状态和收藏状态
            let internalId = getArchiveInternalId(archive.id)
            var isNew = true  // 默认为新
            var isFavorite = false  // 默认未收藏
            if (internalId > 0) {
                match (isNewMap.get(internalId)) {
                    case Some(status) => isNew = status
                    case None => isNew = true  // 没有记录，默认为新
                }
                match (isFavoriteMap.get(internalId)) {
                    case Some(status) => isFavorite = status
                    case None => isFavorite = false  // 没有记录，默认未收藏
                }
            }

            archivesJson += "{"
            archivesJson = archivesJson + "\"arcid\":\"${escapeJson(archive.id)}\","
            archivesJson = archivesJson + "\"extension\":\"${escapeJson(archive.extension())}\","
            archivesJson = archivesJson + "\"filename\":\"${escapeJson(archive.filename)}\","
            archivesJson = archivesJson + "\"isnew\":${isNew},"
            archivesJson = archivesJson + "\"isfavorite\":${isFavorite},"
            archivesJson = archivesJson + "\"lastreadtime\":0,"  // lastreadtime 现在从 user_archive_status 获取，暂时返回 0
            archivesJson = archivesJson + "\"pagecount\":${archive.pagecount},"
            archivesJson = archivesJson + "\"progress\":0,"  // progress 现在从 user_archive_status 获取，暂时返回 0
            archivesJson = archivesJson + "\"size\":${archive.size()},"
            archivesJson = archivesJson + "\"summary\":\"${escapeJson(archive.summary)}\","
            archivesJson = archivesJson + "\"tags\":\"${escapeJson(archive.tags)}\","
            archivesJson = archivesJson + "\"title\":\"${escapeJson(archive.title)}\""
            archivesJson += "}"
        }
        archivesJson += "]"

        let result = "{\"data\":" + archivesJson + ",\"recordsTotal\":" + count.toString() + "}"
        ctx.json(result)
    }

    /**
     * 清除搜索缓存
     */
    public static func clearSearchCache(ctx: JoyContext) {
        let result = "{\"operation\":\"clear_cache\",\"success\":1}"
        ResponseView.successJson(ctx, result, "清除搜索缓存成功")
    }

    /**
     * 获取搜索建议
     */
    public static func getSearchSuggestions(ctx: JoyContext) {
        let suggestions = "[\"suggestion1\",\"suggestion2\",\"suggestion3\"]"
        ResponseView.successJson(ctx, suggestions, "获取搜索建议成功")
    }

}