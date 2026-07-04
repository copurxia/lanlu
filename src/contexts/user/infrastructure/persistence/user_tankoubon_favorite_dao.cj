package lanlu.contexts.user.infrastructure.persistence
import lanlu.contexts.tankoubon.infrastructure.persistence.*

import ace_orm.*
import std.collection.*
import lanlu.shared.config.*
import lanlu.shared.utils.*

/**
 * 用户收藏 Tankoubon 数据访问对象
 * 管理用户级别的合集收藏功能
 */
public class UserTankoubonFavoriteDao {
    /**
     * 通过 tankoubon_id 查询 tankoubons.id（内部 ID）。
     * 内联查找：TankoubonDao.getTankoubonInternalId 仍基于 std.database.sql.Connection，
     * 而 ACE-ORM 不暴露连接句柄，故此处直接走 driver().query。
     */
    private static func getTankInternalId(tankoubonId: String): Int64 {
        try {
            let rows = DatabaseConfig.driver().query("SELECT id FROM tankoubons WHERE tankoubon_id = $1", [DbText(tankoubonId)])
            if (rows.size > 0) {
                return rows[0].getInt("id")
            }
        } catch (_: Exception) {}
        return 0
    }

    /**
     * 添加收藏
     */
    public static func addFavorite(userId: Int64, tankoubonId: String): Bool {
        let logger = getLogger("user_tankoubon_favorite_dao")
        try {
            let tankInternalId = getTankInternalId(tankoubonId)
            if (tankInternalId <= 0) {
                return false
            }

            DatabaseConfig.driver().exec("""
                INSERT INTO user_tankoubon_favorites (user_id, tankoubon_id, created_at)
                SELECT $1, $2, CURRENT_TIMESTAMP
                WHERE NOT EXISTS (
                    SELECT 1 FROM user_tankoubon_favorites WHERE user_id = $3 AND tankoubon_id = $4
                )
            """, [DbInt(userId), DbInt(tankInternalId), DbInt(userId), DbInt(tankInternalId)])
            return true
        } catch (e: Exception) {
            logger.error("添加Tankoubon收藏失败", ("tankoubonId", tankoubonId), ("error", e.message))
            return false
        }
    }

    /**
     * 取消收藏
     */
    public static func removeFavorite(userId: Int64, tankoubonId: String): Bool {
        let logger = getLogger("user_tankoubon_favorite_dao")
        try {
            let tankInternalId = getTankInternalId(tankoubonId)
            if (tankInternalId <= 0) {
                return false
            }

            DatabaseConfig.driver().exec("""
                DELETE FROM user_tankoubon_favorites
                WHERE user_id = $1 AND tankoubon_id = $2
            """, [DbInt(userId), DbInt(tankInternalId)])
            return true
        } catch (e: Exception) {
            logger.error("取消Tankoubon收藏失败", ("tankoubonId", tankoubonId), ("error", e.message))
            return false
        }
    }

    /**
     * 检查是否已收藏
     */
    public static func isFavorite(userId: Int64, tankoubonId: String): Bool {
        try {
            let tankInternalId = getTankInternalId(tankoubonId)
            if (tankInternalId <= 0) {
                return false
            }

            let rows = DatabaseConfig.driver().query("""
                SELECT COUNT(*) FROM user_tankoubon_favorites
                WHERE user_id = $1 AND tankoubon_id = $2
            """, [DbInt(userId), DbInt(tankInternalId)])
            if (rows.size > 0) {
                let count = rows[0].getInt("count")
                return count > 0
            }
        } catch (_: Exception) {
            return false
        }
        return false
    }

    /**
     * 获取用户收藏的 Tankoubon id 列表（返回 tankoubons.tankoubon_id）
     */
    public static func getUserFavoriteTankoubonIds(userId: Int64): Array<String> {
        let result = ArrayList<String>()
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT t.tankoubon_id
                FROM user_tankoubon_favorites utf
                JOIN tankoubons t ON t.id = utf.tankoubon_id
                WHERE utf.user_id = $1
                ORDER BY utf.created_at DESC
            """, [DbInt(userId)])
            for (r in rows) {
                let tid = r.getText("tankoubon_id")
                if (tid.size > 0) {
                    result.add(tid)
                }
            }
        } catch (e: Exception) {
            getLogger("user_tankoubon_favorite_dao").error("获取Tankoubon收藏列表失败", ("error", e.message))
        }
        return result.toArray()
    }

    /**
     * 获取分页后的 Tankoubon 收藏 id 列表
     */
    public static func getUserFavoriteTankoubonIdsPaged(userId: Int64, start: Int32, count: Int32): (Array<String>, Int32) {
        let ids = ArrayList<String>()
        var totalCount: Int32 = 0

        try {
            // total count
            try {
                let countRows = DatabaseConfig.driver().query("SELECT COUNT(*) FROM user_tankoubon_favorites WHERE user_id = $1", [DbInt(userId)])
                if (countRows.size > 0) {
                    totalCount = Int32(countRows[0].getInt("count"))
                }
            } catch (_: Exception) {}

            let rows = DatabaseConfig.driver().query("""
                SELECT t.tankoubon_id
                FROM user_tankoubon_favorites utf
                JOIN tankoubons t ON t.id = utf.tankoubon_id
                WHERE utf.user_id = $1
                ORDER BY utf.created_at DESC
                LIMIT $2 OFFSET $3
            """, [DbInt(userId), DbInt(Int64(count)), DbInt(Int64(start))])
            for (r in rows) {
                let tid = r.getText("tankoubon_id")
                if (tid.size > 0) {
                    ids.add(tid)
                }
            }
        } catch (e: Exception) {
            getLogger("user_tankoubon_favorite_dao").error("获取Tankoubon收藏分页失败", ("error", e.message))
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

        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT t.tankoubon_id
                FROM user_tankoubon_favorites utf
                JOIN tankoubons t ON t.id = utf.tankoubon_id
                WHERE utf.user_id = $1 AND t.tankoubon_id = ANY($2::text[])
            """, [DbInt(userId), DbArray(Array<DbValue>(tankoubonIds.size, { k => DbText(tankoubonIds[k]) }))])
            for (r in rows) {
                let tid = r.getText("tankoubon_id")
                if (tid.size > 0) {
                    result[tid] = true
                }
            }
        } catch (e: Exception) {
            getLogger("user_tankoubon_favorite_dao").error("批量检查 Tankoubon 收藏状态失败", ("error", e.message))
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

        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT t.tankoubon_id, COALESCE(CAST(EXTRACT(EPOCH FROM utf.created_at) AS BIGINT), 0) as unix_timestamp
                FROM user_tankoubon_favorites utf
                JOIN tankoubons t ON t.id = utf.tankoubon_id
                WHERE utf.user_id = $1 AND t.tankoubon_id = ANY($2::text[])
            """, [DbInt(userId), DbArray(Array<DbValue>(tankoubonIds.size, { k => DbText(tankoubonIds[k]) }))])
            for (r in rows) {
                let tid = r.getText("tankoubon_id")
                let unixTimestamp = r.getInt("unix_timestamp")
                if (tid.size > 0) {
                    result[tid] = unixTimestamp
                }
            }
        } catch (e: Exception) {
            getLogger("user_tankoubon_favorite_dao").error("批量获取 Tankoubon 收藏时间失败", ("error", e.message))
        }

        return result
    }
}