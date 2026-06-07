package lanlu.contexts.user.infrastructure.persistence

import std.database.sql.*
import stdx.log.*
import lanlu.shared.config.*
import lanlu.shared.utils.*

public class UserTargetFavoritesDao {
    /**
     * 添加收藏（防重复插入）
     * @param userId 用户ID
     * @param targetType 目标类型
     * @param targetId 目标ID
     * @return 操作是否成功
     */
    public static func addFavorite(userId: Int64, targetType: String, targetId: String): Bool {
        let logger = getLogger("user_target_favorites_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO user_target_favorites (user_id, target_type, target_id, created_at)
                        SELECT ?, ?, ?, CURRENT_TIMESTAMP
                        WHERE NOT EXISTS (
                            SELECT 1 FROM user_target_favorites WHERE user_id = ? AND target_type = ? AND target_id = ?
                        )
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, targetType)
                        stmt.set(2, targetId)
                        stmt.set(3, userId)
                        stmt.set(4, targetType)
                        stmt.set(5, targetId)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("添加收藏失败", ("error", e.message))
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
     * @param userId 用户ID
     * @param targetType 目标类型
     * @param targetId 目标ID
     * @return 操作是否成功
     */
    public static func removeFavorite(userId: Int64, targetType: String, targetId: String): Bool {
        let logger = getLogger("user_target_favorites_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        DELETE FROM user_target_favorites
                        WHERE user_id = ? AND target_type = ? AND target_id = ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, targetType)
                        stmt.set(2, targetId)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("取消收藏失败", ("error", e.message))
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
     * @param userId 用户ID
     * @param targetType 目标类型
     * @param targetId 目标ID
     * @return 是否已收藏
     */
    public static func isFavorite(userId: Int64, targetType: String, targetId: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT COUNT(*) FROM user_target_favorites
                        WHERE user_id = ? AND target_type = ? AND target_id = ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, targetType)
                        stmt.set(2, targetId)
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
                    return false
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }
}
