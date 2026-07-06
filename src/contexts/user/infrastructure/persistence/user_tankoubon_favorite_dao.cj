package lanlu.contexts.user.infrastructure.persistence
import lanlu.contexts.tankoubon.infrastructure.persistence.*

import csorm.*
import postgresql_driver.*
import std.collection.*
import stdx.log.*
import lanlu.shared.config.*
import lanlu.shared.utils.*

/**
 * 用户收藏 Tankoubon 数据访问对象
 * 管理用户级别的合集收藏功能
 */
public class UserTankoubonFavoriteDao {
    /**
     * 添加收藏
     */
    public static func addFavorite(userId: Int64, tankoubonId: String): Bool {
        let logger = getLogger("user_tankoubon_favorite_dao")
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let tankInternalId = TankoubonDao.getTankoubonInternalId(db, tankoubonId)
                    if (tankInternalId <= 0) {
                        return false
                    }

                    let sql = """
                        INSERT INTO user_tankoubon_favorites (user_id, tankoubon_id, created_at)
                        SELECT $1, $2, CURRENT_TIMESTAMP
                        WHERE NOT EXISTS (
                            SELECT 1 FROM user_tankoubon_favorites WHERE user_id = $3 AND tankoubon_id = $4
                        )
                    """
                    let params: Array<Value> = [
                        vint(userId),
                        vint(tankInternalId),
                        vint(userId),
                        vint(tankInternalId)
                    ]
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
     * 取消收藏
     */
    public static func removeFavorite(userId: Int64, tankoubonId: String): Bool {
        let logger = getLogger("user_tankoubon_favorite_dao")
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let tankInternalId = TankoubonDao.getTankoubonInternalId(db, tankoubonId)
                    if (tankInternalId <= 0) {
                        return false
                    }

                    let sql = """
                        DELETE FROM user_tankoubon_favorites
                        WHERE user_id = $1 AND tankoubon_id = $2
                    """
                    let params: Array<Value> = [vint(userId), vint(tankInternalId)]
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
     * 检查是否已收藏
     */
    public static func isFavorite(userId: Int64, tankoubonId: String): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let tankInternalId = TankoubonDao.getTankoubonInternalId(db, tankoubonId)
                    if (tankInternalId <= 0) {
                        return false
                    }

                    let sql = """
                        SELECT COUNT(*) FROM user_tankoubon_favorites
                        WHERE user_id = $1 AND tankoubon_id = $2
                    """
                    let params: Array<Value> = [vint(userId), vint(tankInternalId)]
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
     * 获取用户收藏的 Tankoubon id 列表（返回 tankoubons.tankoubon_id）
     */
    public static func getUserFavoriteTankoubonIds(userId: Int64): Array<String> {
        let result = ArrayList<String>()
        let sql = """
            SELECT t.tankoubon_id
            FROM user_tankoubon_favorites utf
            JOIN tankoubons t ON t.id = utf.tankoubon_id
            WHERE utf.user_id = $1
            ORDER BY utf.created_at DESC
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
     */
    public static func getUserFavoriteTankoubonIdsPaged(userId: Int64, start: Int32, count: Int32): (Array<String>, Int32) {
        let ids = ArrayList<String>()
        var totalCount: Int32 = 0
        let logger = getLogger("user_tankoubon_favorite_dao")

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    // total count
                    try {
                        let countSql = "SELECT COUNT(*) FROM user_tankoubon_favorites WHERE user_id = $1"
                        let countParams: Array<Value> = [vint(userId)]
                        let countRows = db.raw<Int64>(countSql, countParams, { r => r.getOrNullInt64(0) ?? 0 })
                        if (countRows.size > 0) {
                            totalCount = Int32(countRows[0])
                        }
                    } catch (_: Exception) {}

                    let sql = """
                        SELECT t.tankoubon_id
                        FROM user_tankoubon_favorites utf
                        JOIN tankoubons t ON t.id = utf.tankoubon_id
                        WHERE utf.user_id = $1
                        ORDER BY utf.created_at DESC
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
     */
    public static func getBatchFavoriteStatus(userId: Int64, tankoubonIds: Array<String>): HashMap<String, Bool> {
        let result = HashMap<String, Bool>()
        if (userId <= 0 || tankoubonIds.size == 0) {
            return result
        }

        let sql = """
            SELECT t.tankoubon_id
            FROM user_tankoubon_favorites utf
            JOIN tankoubons t ON t.id = utf.tankoubon_id
            WHERE utf.user_id = $1 AND t.tankoubon_id = ANY($2::text[])
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

        return result
    }

    /**
     * 批量获取 Tankoubon 收藏时间
     * 返回 Map<tankoubon_id, favoriteTime> (Unix时间戳)
     */
    public static func getBatchFavoriteTime(userId: Int64, tankoubonIds: Array<String>): HashMap<String, Int64> {
        let result = HashMap<String, Int64>()
        if (userId <= 0 || tankoubonIds.size == 0) {
            return result
        }

        let sql = """
            SELECT t.tankoubon_id, COALESCE(CAST(EXTRACT(EPOCH FROM utf.created_at) AS BIGINT), 0) as unix_timestamp
            FROM user_tankoubon_favorites utf
            JOIN tankoubons t ON t.id = utf.tankoubon_id
            WHERE utf.user_id = $1 AND t.tankoubon_id = ANY($2::text[])
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