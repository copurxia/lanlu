package lanlu.infrastructure.migrations.versions

import csorm.*
import lanlu.infrastructure.migrations.*

/**
 * V027: 删除 user_tankoubon_favorites 表
 *
 * 合集收藏不再使用独立表，改为复用 user_favorites：
 * 收藏合集 = 批量收藏其下所有子 archive。
 */
public class V027_DropUserTankoubonFavorites <: Migration {
    public func version(): String {
        return "V027"
    }

    public func description(): String {
        return "Drop user_tankoubon_favorites table (merged into user_favorites)"
    }

    public func up(db: Database): Bool {
        // 删除相关索引（如果存在）
        try {
            db.execRaw("DROP INDEX IF EXISTS idx_user_tankoubon_favorites_user_id")
        } catch (_: Exception) {}
        try {
            db.execRaw("DROP INDEX IF EXISTS idx_user_tankoubon_favorites_tankoubon_id")
        } catch (_: Exception) {}
        try {
            db.execRaw("DROP INDEX IF EXISTS idx_user_tank_favorites_user_created")
        } catch (_: Exception) {}

        // 删除表
        try {
            db.execRaw("DROP TABLE IF EXISTS user_tankoubon_favorites")
        } catch (_: Exception) {}

        return true
    }
}