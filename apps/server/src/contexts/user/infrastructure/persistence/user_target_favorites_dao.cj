package lanlu.contexts.user.infrastructure.persistence

import csorm.*
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
        let params: Array<Value> = [
            vint(userId),
            vtext(targetType),
            vtext(targetId),
            vint(userId),
            vtext(targetType),
            vtext(targetId)
        ]
        let sql = """
            INSERT INTO user_target_favorites (user_id, target_type, target_id, created_at)
            SELECT $1, $2, $3, CURRENT_TIMESTAMP
            WHERE NOT EXISTS (
                SELECT 1 FROM user_target_favorites WHERE user_id = $4 AND target_type = $5 AND target_id = $6
            )
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("添加收藏失败", ("error", e.message))
                    return false
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
        let params: Array<Value> = [vint(userId), vtext(targetType), vtext(targetId)]
        let sql = """
            DELETE FROM user_target_favorites
            WHERE user_id = $1 AND target_type = $2 AND target_id = $3
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("取消收藏失败", ("error", e.message))
                    return false
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
        let params: Array<Value> = [vint(userId), vtext(targetType), vtext(targetId)]
        let sql = """
            SELECT COUNT(*) FROM user_target_favorites
            WHERE user_id = $1 AND target_type = $2 AND target_id = $3
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
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
}