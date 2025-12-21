package lrr4cj.dao

import std.database.sql.*
import std.collection.*
import lrr4cj.config.*
import lrr4cj.utils.*

/**
 * 用户收藏 Tankoubon 数据访问对象
 * 管理用户级别的合集收藏功能
 */
public class UserTankoubonFavoriteDao {
    /**
     * 根据 tankoubon_id 获取 tankoubons 表内部 ID
     */
    private static func getTankoubonInternalId(conn: Connection, tankoubonId: String): Int64 {
        try {
            let stmt = conn.prepareStatement("SELECT id FROM tankoubons WHERE tankoubon_id = ?")
            try {
                stmt.set(0, tankoubonId)
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
        } catch (_: Exception) {}
        return 0
    }

    /**
     * 添加收藏
     */
    public static func addFavorite(userId: Int64, tankoubonId: String): Bool {
        let logger = getLogger("user_tankoubon_favorite_dao")
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let tankInternalId = getTankoubonInternalId(conn, tankoubonId)
                    if (tankInternalId <= 0) {
                        return false
                    }

                    let stmt = conn.prepareStatement("""
                        INSERT INTO user_tankoubon_favorites (user_id, tankoubon_id, created_at)
                        VALUES (?, ?, CURRENT_TIMESTAMP)
                        ON CONFLICT (user_id, tankoubon_id) DO NOTHING
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, tankInternalId)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("添加Tankoubon收藏失败", ("tankoubonId", tankoubonId), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
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
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let tankInternalId = getTankoubonInternalId(conn, tankoubonId)
                    if (tankInternalId <= 0) {
                        return false
                    }

                    let stmt = conn.prepareStatement("""
                        DELETE FROM user_tankoubon_favorites
                        WHERE user_id = ? AND tankoubon_id = ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, tankInternalId)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("取消Tankoubon收藏失败", ("tankoubonId", tankoubonId), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
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
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let tankInternalId = getTankoubonInternalId(conn, tankoubonId)
                    if (tankInternalId <= 0) {
                        return false
                    }

                    let stmt = conn.prepareStatement("""
                        SELECT COUNT(*) FROM user_tankoubon_favorites
                        WHERE user_id = ? AND tankoubon_id = ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, tankInternalId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let count = rs.getOrNull<Int64>(0) ?? 0
                                return count > 0
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
        return false
    }

    /**
     * 获取用户收藏的 Tankoubon id 列表（返回 tankoubons.tankoubon_id）
     */
    public static func getUserFavoriteTankoubonIds(userId: Int64): Array<String> {
        let result = ArrayList<String>()
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT t.tankoubon_id
                        FROM user_tankoubon_favorites utf
                        JOIN tankoubons t ON t.id = utf.tankoubon_id
                        WHERE utf.user_id = ?
                        ORDER BY utf.created_at DESC
                    """)
                    try {
                        stmt.set(0, userId)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let tid = rs.getOrNull<String>(0) ?? ""
                                if (tid.size > 0) {
                                    result.add(tid)
                                }
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("user_tankoubon_favorite_dao").error("获取Tankoubon收藏列表失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
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

        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // total count
                    try {
                        let countStmt = conn.prepareStatement("SELECT COUNT(*) FROM user_tankoubon_favorites WHERE user_id = ?")
                        try {
                            countStmt.set(0, userId)
                            let rs = countStmt.query()
                            try {
                                if (rs.next()) {
                                    totalCount = Int32(rs.getOrNull<Int64>(0) ?? 0)
                                }
                            } finally {
                                rs.close()
                            }
                        } finally {
                            countStmt.close()
                        }
                    } catch (_: Exception) {}

                    let stmt = conn.prepareStatement("""
                        SELECT t.tankoubon_id
                        FROM user_tankoubon_favorites utf
                        JOIN tankoubons t ON t.id = utf.tankoubon_id
                        WHERE utf.user_id = ?
                        ORDER BY utf.created_at DESC
                        LIMIT ? OFFSET ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, count)
                        stmt.set(2, start)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let tid = rs.getOrNull<String>(0) ?? ""
                                if (tid.size > 0) {
                                    ids.add(tid)
                                }
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("user_tankoubon_favorite_dao").error("获取Tankoubon收藏分页失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                getLogger("user_tankoubon_favorite_dao").error("无法连接到数据库")
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

        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    var inClause = ""
                    for (i in 0..tankoubonIds.size) {
                        if (i > 0) {
                            inClause += ","
                        }
                        inClause += "?"
                    }

                    let stmt = conn.prepareStatement("""
                        SELECT t.tankoubon_id
                        FROM user_tankoubon_favorites utf
                        JOIN tankoubons t ON t.id = utf.tankoubon_id
                        WHERE utf.user_id = ? AND t.tankoubon_id IN (${inClause})
                    """)
                    try {
                        stmt.set(0, userId)
                        for (i in 0..tankoubonIds.size) {
                            stmt.set(i + 1, tankoubonIds[i])
                        }
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let tid = rs.getOrNull<String>(0) ?? ""
                                if (tid.size > 0) {
                                    result[tid] = true
                                }
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    // ignore
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => ()
        }

        return result
    }
}
