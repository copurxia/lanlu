package lanlu.contexts.user.infrastructure.persistence

import csorm.*
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
        let params: Array<Value> = [vint(userId), vtext(targetType), vtext(targetId)]
        let sql = """
            INSERT INTO user_target_status (user_id, target_type, target_id, is_new, updated_at)
            VALUES ($1, $2, $3, true, CURRENT_TIMESTAMP)
            ON CONFLICT (user_id, target_type, target_id)
            DO UPDATE SET is_new = true, updated_at = CURRENT_TIMESTAMP
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("设置isNew标记失败", ("error", e.message))
                    return false
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
        let params: Array<Value> = [vint(userId), vtext(targetType), vtext(targetId)]
        let sql = """
            INSERT INTO user_target_status (user_id, target_type, target_id, is_new, updated_at)
            VALUES ($1, $2, $3, false, CURRENT_TIMESTAMP)
            ON CONFLICT (user_id, target_type, target_id)
            DO UPDATE SET is_new = false, updated_at = CURRENT_TIMESTAMP
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("清除isNew标记失败", ("error", e.message))
                    return false
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
        let progressI64 = Int64(progress)
        let params: Array<Value> = [
            vint(userId),
            vtext(targetType),
            vtext(targetId),
            vint(progressI64),
            vint(progressI64)
        ]
        let sql = """
            INSERT INTO user_target_status (user_id, target_type, target_id, is_new, progress, last_read_time, updated_at)
            VALUES ($1, $2, $3, false, $4, CAST(EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) AS BIGINT), CURRENT_TIMESTAMP)
            ON CONFLICT (user_id, target_type, target_id)
            DO UPDATE SET is_new = false,
                          progress = $5,
                          last_read_time = CAST(EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) AS BIGINT),
                          updated_at = CURRENT_TIMESTAMP
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("更新阅读进度失败", ("error", e.message))
                    return false
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
        let params: Array<Value> = [vint(userId), vtext(targetType), vtext(targetId)]
        let sql = """
            SELECT is_new FROM user_target_status
            WHERE user_id = $1 AND target_type = $2 AND target_id = $3
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Bool>(sql, params, { r => r.getOrNullBool(0) ?? true })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return true
                } catch (_: Exception) {
                    return true
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
        let params: Array<Value> = [vint(userId), vtext(targetType), vtext(targetId)]
        let sql = """
            SELECT progress FROM user_target_status
            WHERE user_id = $1 AND target_type = $2 AND target_id = $3
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Int32>(sql, params, { r =>
                        match (r.getOrNullInt32(0)) {
                            case Some(v) => v
                            case None => 0
                        }
                    })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return 0
                } catch (_: Exception) {
                    return 0
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
        let params: Array<Value> = [vint(userId), vtext(targetType), vtext(targetId)]
        let sql = """
            SELECT last_read_time FROM user_target_status
            WHERE user_id = $1 AND target_type = $2 AND target_id = $3
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Int64>(sql, params, { r => r.getOrNullInt64(0) ?? 0 })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return 0
                } catch (_: Exception) {
                    return 0
                }
            case None => return 0
        }
    }
}