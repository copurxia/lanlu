package lanlu.contexts.user.infrastructure.persistence

import csorm.*
import std.collection.*
import stdx.log.*
import lanlu.shared.config.*
import lanlu.shared.utils.*

/**
 * 用户收藏 Tankoubon 数据访问对象
 *
 * 策略变更：不再使用独立的 user_tankoubon_favorites 表。
 * 收藏合集 = 批量收藏其下所有子 archive 到 user_favorites；
 * 取消收藏合集 = 批量删除其下所有子 archive 的 user_favorites 记录。
 * 合集 isfavorite 判定 = 任一子 archive 被收藏即为 true。
 * 合集 favoritetime = 子 archive 中最新的收藏时间。
 */
public class UserTankoubonFavoriteDao {
    /**
     * 添加收藏：把合集下所有子 archive 批量写入 user_favorites
     */
    public static func addFavorite(userId: Int64, tankoubonId: String): Bool {
        let logger = getLogger("user_tankoubon_favorite_dao")
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    // 批量插入：合集下所有子 archive 的 user_favorites 记录
                    // 使用 INSERT ... SELECT ... WHERE NOT EXISTS 实现幂等
                    let sql = """
                        INSERT INTO user_favorites (user_id, archive_id, created_at)
                        SELECT $1, ta.archive_id, CURRENT_TIMESTAMP
                        FROM tankoubon_archives ta
                        JOIN tankoubons t ON t.id = ta.tankoubon_id
                        WHERE t.tankoubon_id = $2
                          AND NOT EXISTS (
                              SELECT 1 FROM user_favorites uf
                              WHERE uf.user_id = $3 AND uf.archive_id = ta.archive_id
                          )
                    """
                    let params: Array<Value> = [vint(userId), vtext(tankoubonId), vint(userId)]
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("添加Tankoubon收藏失败", ("tankoubonId", tankoubonId), ("error", e.message))
                    return false
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    /**
     * 取消收藏：删除合集下所有子 archive 的 user_favorites 记录
     */
    public static func removeFavorite(userId: Int64, tankoubonId: String): Bool {
        let logger = getLogger("user_tankoubon_favorite_dao")
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = """
                        DELETE FROM user_favorites
                        WHERE user_id = $1
                          AND archive_id IN (
                              SELECT ta.archive_id
                              FROM tankoubon_archives ta
                              JOIN tankoubons t ON t.id = ta.tankoubon_id
                              WHERE t.tankoubon_id = $2
                          )
                    """
                    let params: Array<Value> = [vint(userId), vtext(tankoubonId)]
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("取消Tankoubon收藏失败", ("tankoubonId", tankoubonId), ("error", e.message))
                    return false
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    /**
     * 检查是否已收藏：合集下任一子 archive 被收藏即为 true
     */
    public static func isFavorite(userId: Int64, tankoubonId: String): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = """
                        SELECT COUNT(*)
                        FROM user_favorites uf
                        JOIN tankoubon_archives ta ON ta.archive_id = uf.archive_id
                        JOIN tankoubons t ON t.id = ta.tankoubon_id
                        WHERE uf.user_id = $1 AND t.tankoubon_id = $2
                    """
                    let params: Array<Value> = [vint(userId), vtext(tankoubonId)]
                    let rows = db.raw<Int64>(sql, params, { r => r.getOrNullInt64(0) ?? 0 })
                    if (rows.size > 0) {
                        return rows[0] > 0
                    }
                    return false
                } catch (_: Exception) {
                    return false
                }
            case None => return false
        }
    }

    /**
     * 获取用户收藏的 Tankoubon id 列表
     * 返回包含被收藏 archive 的合集 tankoubon_id，按子 archive 最新收藏时间降序
     */
    public static func getUserFavoriteTankoubonIds(userId: Int64): Array<String> {
        let result = ArrayList<String>()
        let sql = """
            SELECT t.tankoubon_id
            FROM user_favorites uf
            JOIN tankoubon_archives ta ON ta.archive_id = uf.archive_id
            JOIN tankoubons t ON t.id = ta.tankoubon_id
            WHERE uf.user_id = $1
            GROUP BY t.tankoubon_id
            ORDER BY MAX(uf.created_at) DESC
        """
        let params: Array<Value> = [vint(userId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<String>(sql, params, { r => r.getOrNullText(0) ?? "" })
                    for (tid in rows) {
                        if (tid.size > 0) {
                            result.add(tid)
                        }
                    }
                } catch (e: Exception) {
                    getLogger("user_tankoubon_favorite_dao").error("获取Tankoubon收藏列表失败", ("error", e.message))
                }
            case None =>
                getLogger("user_tankoubon_favorite_dao").error("无法连接到数据库")
        }
        return result.toArray()
    }

    /**
     * 获取分页后的 Tankoubon 收藏 id 列表
     * 返回包含被收藏 archive 的合集，按子 archive 最新收藏时间降序
     */
    public static func getUserFavoriteTankoubonIdsPaged(userId: Int64, start: Int32, count: Int32): (Array<String>, Int32) {
        let ids = ArrayList<String>()
        var totalCount: Int32 = 0
        let logger = getLogger("user_tankoubon_favorite_dao")

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    // total count: 有多少个合集包含被收藏的 archive
                    try {
                        let countSql = """
                            SELECT COUNT(DISTINCT t.tankoubon_id)
                            FROM user_favorites uf
                            JOIN tankoubon_archives ta ON ta.archive_id = uf.archive_id
                            JOIN tankoubons t ON t.id = ta.tankoubon_id
                            WHERE uf.user_id = $1
                        """
                        let countParams: Array<Value> = [vint(userId)]
                        let countRows = db.raw<Int64>(countSql, countParams, { r => r.getOrNullInt64(0) ?? 0 })
                        if (countRows.size > 0) {
                            totalCount = Int32(countRows[0])
                        }
                    } catch (_: Exception) {}

                    let sql = """
                        SELECT t.tankoubon_id
                        FROM user_favorites uf
                        JOIN tankoubon_archives ta ON ta.archive_id = uf.archive_id
                        JOIN tankoubons t ON t.id = ta.tankoubon_id
                        WHERE uf.user_id = $1
                        GROUP BY t.tankoubon_id
                        ORDER BY MAX(uf.created_at) DESC
                        LIMIT $2 OFFSET $3
                    """
                    let params: Array<Value> = [vint(userId), vint(Int64(count)), vint(Int64(start))]
                    let rows = db.raw<String>(sql, params, { r => r.getOrNullText(0) ?? "" })
                    for (tid in rows) {
                        if (tid.size > 0) {
                            ids.add(tid)
                        }
                    }
                } catch (e: Exception) {
                    logger.error("获取Tankoubon收藏分页失败", ("error", e.message))
                }
            case None =>
                logger.error("无法连接到数据库")
        }

        return (ids.toArray(), totalCount)
    }

    /**
     * 批量检查 Tankoubon 收藏状态
     * 返回 Map<tankoubon_id, isFavorite>
     * isFavorite = 合集下任一子 archive 被收藏
     */
    public static func getBatchFavoriteStatus(userId: Int64, tankoubonIds: Array<String>): HashMap<String, Bool> {
        let result = HashMap<String, Bool>()
        if (userId <= 0 || tankoubonIds.size == 0) {
            return result
        }

        let sql = """
            SELECT DISTINCT t.tankoubon_id
            FROM user_favorites uf
            JOIN tankoubon_archives ta ON ta.archive_id = uf.archive_id
            JOIN tankoubons t ON t.id = ta.tankoubon_id
            WHERE uf.user_id = $1 AND t.tankoubon_id = ANY($2::text[])
        """
        let params: Array<Value> = [vint(userId), textArray(tankoubonIds)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<String>(sql, params, { r => r.getOrNullText(0) ?? "" })
                    for (tid in rows) {
                        if (tid.size > 0) {
                            result[tid] = true
                        }
                    }
                } catch (e: Exception) {
                    getLogger("user_tankoubon_favorite_dao").error("批量检查 Tankoubon 收藏状态失败", ("error", e.message))
                }
            case None =>
                getLogger("user_tankoubon_favorite_dao").error("无法连接到数据库")
        }

        // 对于没有收藏的合集，设置为 false
        for (tid in tankoubonIds) {
            if (!result.contains(tid)) {
                result[tid] = false
            }
        }

        return result
    }

    /**
     * 批量获取 Tankoubon 收藏时间
     * 返回 Map<tankoubon_id, favoriteTime> (Unix时间戳)
     * favoriteTime = 子 archive 中最新的收藏时间
     */
    public static func getBatchFavoriteTime(userId: Int64, tankoubonIds: Array<String>): HashMap<String, Int64> {
        let result = HashMap<String, Int64>()
        if (userId <= 0 || tankoubonIds.size == 0) {
            return result
        }

        let sql = """
            SELECT t.tankoubon_id, COALESCE(CAST(EXTRACT(EPOCH FROM MAX(uf.created_at)) AS BIGINT), 0) as unix_timestamp
            FROM user_favorites uf
            JOIN tankoubon_archives ta ON ta.archive_id = uf.archive_id
            JOIN tankoubons t ON t.id = ta.tankoubon_id
            WHERE uf.user_id = $1 AND t.tankoubon_id = ANY($2::text[])
            GROUP BY t.tankoubon_id
        """
        let params: Array<Value> = [vint(userId), textArray(tankoubonIds)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<(String, Int64)>(sql, params, { r =>
                        (r.getOrNullText(0) ?? "", r.getOrNullInt64(1) ?? 0)
                    })
                    for (pair in rows) {
                        let (tid, unixTimestamp) = pair
                        if (tid.size > 0) {
                            result[tid] = unixTimestamp
                        }
                    }
                } catch (e: Exception) {
                    getLogger("user_tankoubon_favorite_dao").error("批量获取 Tankoubon 收藏时间失败", ("error", e.message))
                }
            case None =>
                getLogger("user_tankoubon_favorite_dao").error("无法连接到数据库")
        }

        return result
    }
}