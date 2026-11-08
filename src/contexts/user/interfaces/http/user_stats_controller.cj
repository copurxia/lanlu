package lanlu.contexts.user.interfaces.http

import ignite.*
import std.convert.*
import stdx.encoding.json.stream.*
import lanlu.contexts.user.infrastructure.persistence.*
import lanlu.infrastructure.middleware.*
import lanlu.shared.views.*

class UserStatsDataView <: JsonSerializable {
    let favoriteCount: Int64
    let readCount: Int64
    let totalPagesRead: Int64
    let totalArchives: Int64

    public init(favoriteCount: Int64, readCount: Int64, totalPagesRead: Int64, totalArchives: Int64) {
        this.favoriteCount = favoriteCount
        this.readCount = readCount
        this.totalPagesRead = totalPagesRead
        this.totalArchives = totalArchives
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("favoriteCount").writeValue(favoriteCount)
        w.writeName("readCount").writeValue(readCount)
        w.writeName("totalPagesRead").writeValue(totalPagesRead)
        w.writeName("totalArchives").writeValue(totalArchives)
        w.endObject()
    }
}

class UserTrendItemView <: JsonSerializable {
    let date: String
    let count: Int64

    public init(date: String, count: Int64) {
        this.date = date
        this.count = count
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("date").writeValue(date)
        w.writeName("count").writeValue(count)
        w.endObject()
    }
}

class UserTrendDataView <: JsonSerializable {
    let items: Array<UserTrendItemView>

    public init(items: Array<UserTrendItemView>) {
        this.items = items
    }

    public func toJson(w: JsonWriter): Unit {
        w.startArray()
        for (item in items) {
            w.writeValue(item)
        }
        w.endArray()
    }
}

/**
 * 用户统计控制器
 */
public class UserStatsController {
    /**
     * 获取用户统计数据
     * GET /api/user/stats
     * 返回: favoriteCount, readCount, totalPagesRead, totalArchives
     */
    public static func getUserStats(ctx: Ctx): Unit {
        let userIdOpt = AuthMiddleware.optionalUser(ctx)
        match (userIdOpt) {
            case Some(userId) =>
                let favoriteCount = UserFavoriteDao.getFavoriteCount(userId)
                let readCount = UserStatsDao.getReadCount(userId)
                let totalPagesRead = UserStatsDao.getTotalPagesRead(userId)
                let totalArchives = UserStatsDao.getTotalArchives()
                ResponseView.json(ctx, ApiResponse<UserStatsDataView>(
                    200,
                    "ok",
                    Some(UserStatsDataView(favoriteCount, readCount, totalPagesRead, totalArchives))
                ))
            case None =>
                ResponseView.json(ctx, ApiResponse<String>(401, "未登录", None))
        }
    }

    /**
     * 获取阅读趋势
     * GET /api/user/trend?days=30
     */
    public static func getTrend(ctx: Ctx): Unit {
        let userIdOpt = AuthMiddleware.optionalUser(ctx)
        match (userIdOpt) {
            case Some(userId) =>
                let daysStr = ctx.query("days") ?? "30"
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
                var items = Array<UserTrendItemView>(trendData.size, { _ => UserTrendItemView("", 0) })
                for (i in 0..trendData.size) {
                    items[i] = UserTrendItemView(trendData[i].date, trendData[i].count)
                }
                ResponseView.json(ctx, ApiResponse<UserTrendDataView>(200, "ok", Some(UserTrendDataView(items))))
            case None =>
                ResponseView.json(ctx, ApiResponse<String>(401, "未登录", None))
        }
    }
}
