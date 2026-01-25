package lrr4cj.controllers

import cjoy.*
import std.convert.*
import lrr4cj.dao.*
import lrr4cj.middleware.*
import lrr4cj.utils.*

/**
 * 用户统计控制器
 * 提供用户阅读统计、趋势分析等 API
 */
public class UserStatsController {
    /**
     * 获取用户统计数据
     * GET /api/user/stats
     * 返回: favoriteCount, readCount, totalPagesRead, totalArchives
     */
    public static func getUserStats(ctx: JoyContext): Unit {
        let userIdOpt = AuthMiddleware.optionalUser(ctx)
        match (userIdOpt) {
            case Some(userId) =>
                let favoriteCount = UserFavoriteDao.getFavoriteCount(userId)
                let readCount = UserStatsDao.getReadCount(userId)
                let totalPagesRead = UserStatsDao.getTotalPagesRead(userId)
                let totalArchives = UserStatsDao.getTotalArchives()

                var dataJson = "{"
                dataJson += "\"favoriteCount\":${favoriteCount},"
                dataJson += "\"readCount\":${readCount},"
                dataJson += "\"totalPagesRead\":${totalPagesRead},"
                dataJson += "\"totalArchives\":${totalArchives}"
                dataJson += "}"

                let result = "{\"operation\":\"get_user_stats\",\"data\":${dataJson},\"success\":1}"
                ctx.json(result)
            case None =>
                let errorResponse = "{\"operation\":\"get_user_stats\",\"error\":\"未登录\",\"success\":0}"
                ctx.json(errorResponse)
        }
    }

    /**
     * 获取阅读趋势
     * GET /api/user/reading-trend?days=30
     * 返回: [{date, count}, ...]
     */
    public static func getReadingTrend(ctx: JoyContext): Unit {
        let userIdOpt = AuthMiddleware.optionalUser(ctx)
        match (userIdOpt) {
            case Some(userId) =>
                let daysStr = ctx.getQuery("days") ?? "30"
                var days: Int32 = 30
                try {
                    days = Int32.parse(daysStr)
                    if (days <= 0 || days > 365) {
                        days = 30
                    }
                } catch (_: Exception) {
                    days = 30
                }

                let trendData = UserStatsDao.getReadingTrend(userId, days)

                var dataJson = "["
                var isFirst = true
                for (item in trendData) {
                    if (!isFirst) {
                        dataJson += ","
                    }
                    isFirst = false
                    dataJson += "{\"date\":\"${item.date}\",\"count\":${item.count}}"
                }
                dataJson += "]"

                let result = "{\"operation\":\"get_reading_trend\",\"data\":${dataJson},\"success\":1}"
                ctx.json(result)
            case None =>
                let errorResponse = "{\"operation\":\"get_reading_trend\",\"error\":\"未登录\",\"success\":0}"
                ctx.json(errorResponse)
        }
    }

    /**
     * 获取最近活动
     * GET /api/user/recent-activity?limit=5
     * 返回: {recentRead: [...], recentFavorites: [...]}
     */
    public static func getRecentActivity(ctx: JoyContext): Unit {
        let userIdOpt = AuthMiddleware.optionalUser(ctx)
        match (userIdOpt) {
            case Some(userId) =>
                let limitStr = ctx.getQuery("limit") ?? "5"
                var limit: Int32 = 5
                try {
                    limit = Int32.parse(limitStr)
                    if (limit <= 0 || limit > 20) {
                        limit = 5
                    }
                } catch (_: Exception) {
                    limit = 5
                }

                let recentRead = UserStatsDao.getRecentReadArchives(userId, limit)
                let recentFavorites = UserStatsDao.getRecentFavoriteArchives(userId, limit)

                var recentReadJson = "["
                var isFirst = true
                for (archive in recentRead) {
                    if (!isFirst) {
                        recentReadJson += ","
                    }
                    isFirst = false
                    recentReadJson += archiveToJson(archive)
                }
                recentReadJson += "]"

                var recentFavoritesJson = "["
                isFirst = true
                for (archive in recentFavorites) {
                    if (!isFirst) {
                        recentFavoritesJson += ","
                    }
                    isFirst = false
                    recentFavoritesJson += archiveToJson(archive)
                }
                recentFavoritesJson += "]"

                var dataJson = "{"
                dataJson += "\"recentRead\":${recentReadJson},"
                dataJson += "\"recentFavorites\":${recentFavoritesJson}"
                dataJson += "}"

                let result = "{\"operation\":\"get_recent_activity\",\"data\":${dataJson},\"success\":1}"
                ctx.json(result)
            case None =>
                let errorResponse = "{\"operation\":\"get_recent_activity\",\"error\":\"未登录\",\"success\":0}"
                ctx.json(errorResponse)
        }
    }

    /**
     * 将 ArchiveData 转换为 JSON 字符串
     */
    private static func archiveToJson(archive: ArchiveData): String {
        var json = "{"
        json += "\"arcid\":\"${escapeJson(archive.id)}\","
        json += "\"title\":\"${escapeJson(archive.title)}\","
        json += "\"filename\":\"${escapeJson(archive.filename)}\","
        json += "\"summary\":\"${escapeJson(archive.summary)}\","
        json += "\"thumbhash\":\"${escapeJson(archive.thumbhash)}\","
        json += "\"tags\":\"${escapeJson(archive.tags)}\","
        json += "\"pagecount\":${archive.pagecount},"
        json += "\"progress\":${archive.progress},"
        json += "\"file_size\":${archive.file_size},"
        json += "\"last_read_time\":\"${escapeJson(archive.last_read_time)}\","
        json += "\"created_at\":\"${escapeJson(archive.created_at)}\","
        json += "\"updated_at\":\"${escapeJson(archive.updated_at)}\""
        json += "}"
        return json
    }

}
