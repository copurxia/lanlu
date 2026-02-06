package lanlu.controllers

import cjoy.*
import std.convert.*
import lanlu.dao.*
import lanlu.middleware.*

/**
 * 用户统计控制器
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
     * GET /api/user/trend?days=30
     */
    public static func getTrend(ctx: JoyContext): Unit {
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

                let result = "{\"operation\":\"get_user_trend\",\"data\":${dataJson},\"success\":1}"
                ctx.json(result)
            case None =>
                let errorResponse = "{\"operation\":\"get_user_trend\",\"error\":\"未登录\",\"success\":0}"
                ctx.json(errorResponse)
        }
    }
}
