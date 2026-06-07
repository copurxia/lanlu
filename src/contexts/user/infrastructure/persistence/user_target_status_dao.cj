package lanlu.contexts.user.infrastructure.persistence

import std.database.sql.*
import stdx.log.*
import lanlu.shared.config.*
import lanlu.shared.utils.*

public class UserTargetStatusDao {
    /**
     * 标记为"新"（未读），upsert 模式
     * @param userId 用户ID
     * @param targetType 目标类型
     * @param targetId 目标ID
     * @return 操作是否成功
     */
    public static func setIsNew(userId: Int64, targetType: String, targetId: String): Bool {
        let logger = getLogger("user_target_status_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO user_target_status (user_id, target_type, target_id, is_new, updated_at)
                        VALUES (?, ?, ?, true, CURRENT_TIMESTAMP)
                        ON CONFLICT (user_id, target_type, target_id)
                        DO UPDATE SET is_new = true, updated_at = CURRENT_TIMESTAMP
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
                    logger.error("设置isNew标记失败", ("error", e.message))
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
     * 清除"新"状态为已读，upsert 模式
     * @param userId 用户ID
     * @param targetType 目标类型
     * @param targetId 目标ID
     * @return 操作是否成功
     */
    public static func clearIsNew(userId: Int64, targetType: String, targetId: String): Bool {
        let logger = getLogger("user_target_status_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO user_target_status (user_id, target_type, target_id, is_new, updated_at)
                        VALUES (?, ?, ?, false, CURRENT_TIMESTAMP)
                        ON CONFLICT (user_id, target_type, target_id)
                        DO UPDATE SET is_new = false, updated_at = CURRENT_TIMESTAMP
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
                    logger.error("清除isNew标记失败", ("error", e.message))
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
     * 更新阅读进度并自动标记 is_new = false，upsert 模式
     * @param userId 用户ID
     * @param targetType 目标类型
     * @param targetId 目标ID
     * @param progress 阅读进度值
     * @return 操作是否成功
     */
    public static func updateProgress(userId: Int64, targetType: String, targetId: String, progress: Int32): Bool {
        let logger = getLogger("user_target_status_dao")
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO user_target_status (user_id, target_type, target_id, is_new, progress, last_read_time, updated_at)
                        VALUES (?, ?, ?, false, ?, CAST(EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) AS BIGINT), CURRENT_TIMESTAMP)
                        ON CONFLICT (user_id, target_type, target_id)
                        DO UPDATE SET is_new = false,
                                      progress = ?,
                                      last_read_time = CAST(EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) AS BIGINT),
                                      updated_at = CURRENT_TIMESTAMP
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, targetType)
                        stmt.set(2, targetId)
                        stmt.set(3, progress)
                        stmt.set(4, progress)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("更新阅读进度失败", ("error", e.message))
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
     * 是否为新（无记录默认 true）
     * @param userId 用户ID
     * @param targetType 目标类型
     * @param targetId 目标ID
     * @return 是否为"新"状态
     */
    public static func isNew(userId: Int64, targetType: String, targetId: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT is_new FROM user_target_status
                        WHERE user_id = ? AND target_type = ? AND target_id = ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, targetType)
                        stmt.set(2, targetId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<Bool>(0) ?? true
                            }
                            return true
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return true
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return true
        }
    }

    /**
     * 获取当前阅读进度（无记录默认 0）
     * @param userId 用户ID
     * @param targetType 目标类型
     * @param targetId 目标ID
     * @return 阅读进度值
     */
    public static func getProgress(userId: Int64, targetType: String, targetId: String): Int32 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT progress FROM user_target_status
                        WHERE user_id = ? AND target_type = ? AND target_id = ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, targetType)
                        stmt.set(2, targetId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<Int32>(0) ?? 0
                            }
                            return 0
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
    }

    /**
     * 获取最后阅读时间（UNIX 时间戳，无记录默认 0）
     * @param userId 用户ID
     * @param targetType 目标类型
     * @param targetId 目标ID
     * @return 最后阅读时间的Unix时间戳
     */
    public static func getLastReadTime(userId: Int64, targetType: String, targetId: String): Int64 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT last_read_time FROM user_target_status
                        WHERE user_id = ? AND target_type = ? AND target_id = ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, targetType)
                        stmt.set(2, targetId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<Int64>(0) ?? 0
                            }
                            return 0
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
    }
}
