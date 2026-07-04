package lanlu.contexts.user.infrastructure.persistence

import ace_orm.*
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
        try {
            DatabaseConfig.driver().exec("""
                INSERT INTO user_target_favorites (user_id, target_type, target_id, created_at)
                SELECT $1, $2, $3, CURRENT_TIMESTAMP
                WHERE NOT EXISTS (
                    SELECT 1 FROM user_target_favorites WHERE user_id = $4 AND target_type = $5 AND target_id = $6
                )
            """, [DbInt(userId), DbText(targetType), DbText(targetId), DbInt(userId), DbText(targetType), DbText(targetId)])
            return true
        } catch (e: Exception) {
            logger.error("添加收藏失败", ("error", e.message))
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
        try {
            DatabaseConfig.driver().exec("""
                DELETE FROM user_target_favorites
                WHERE user_id = $1 AND target_type = $2 AND target_id = $3
            """, [DbInt(userId), DbText(targetType), DbText(targetId)])
            return true
        } catch (e: Exception) {
            logger.error("取消收藏失败", ("error", e.message))
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
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT COUNT(*) FROM user_target_favorites
                WHERE user_id = $1 AND target_type = $2 AND target_id = $3
            """, [DbInt(userId), DbText(targetType), DbText(targetId)])
            if (rows.size > 0) {
                let count = rows[0].getInt("count")
                return count > 0
            }
            return false
        } catch (_: Exception) {
            return false
        }
    }
}