package lanlu.contexts.user.infrastructure.persistence

import ace_orm.*
import std.collection.*
import lanlu.shared.config.*
import lanlu.contexts.archive.infrastructure.persistence.ArchiveData
import lanlu.contexts.archive.infrastructure.persistence.ArchiveDataMappers
import lanlu.shared.utils.*
import stdx.log.*

/**
 * 用户收藏数据行
 */
public class UserFavoriteRow {
    public var id: Int64 = 0
    public var userId: Int64 = 0
    public var archiveId: Int64 = 0
    public var createdAt: String = ""

    public init() {}
}

/**
 * 用户收藏数据访问对象
 * 管理用户级别的档案收藏功能
 */
public class UserFavoriteDao {
    /**
     * 添加收藏
     */
    public static func addFavorite(userId: Int64, archiveId: Int64): Bool {
        let logger = getLogger("user_favorite_dao")
        try {
            DatabaseConfig.driver().exec("""
                INSERT INTO user_favorites (user_id, archive_id, created_at)
                SELECT $1, $2, CURRENT_TIMESTAMP
                WHERE NOT EXISTS (
                    SELECT 1 FROM user_favorites WHERE user_id = $3 AND archive_id = $4
                )
            """, [DbInt(userId), DbInt(archiveId), DbInt(userId), DbInt(archiveId)])
            return true
        } catch (e: Exception) {
            logger.error("添加收藏失败", ("error", e.message))
            return false
        }
    }

    /**
     * 取消收藏
     */
    public static func removeFavorite(userId: Int64, archiveId: Int64): Bool {
        let logger = getLogger("user_favorite_dao")
        try {
            DatabaseConfig.driver().exec("""
                DELETE FROM user_favorites
                WHERE user_id = $1 AND archive_id = $2
            """, [DbInt(userId), DbInt(archiveId)])
            return true
        } catch (e: Exception) {
            logger.error("取消收藏失败", ("error", e.message))
            return false
        }
    }

    /**
     * 检查是否已收藏
     */
    public static func isFavorite(userId: Int64, archiveId: Int64): Bool {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT COUNT(*) FROM user_favorites
                WHERE user_id = $1 AND archive_id = $2
            """, [DbInt(userId), DbInt(archiveId)])
            if (rows.size > 0) {
                let count = rows[0].getInt("count")
                return count > 0
            }
            return false
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * 获取用户的所有收藏（返回 archive_id 列表）
     */
    public static func getUserFavorites(userId: Int64): Array<Int64> {
        let result = ArrayList<Int64>()
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT archive_id FROM user_favorites
                WHERE user_id = $1
                ORDER BY created_at DESC
            """, [DbInt(userId)])
            for (r in rows) {
                let archiveId = r.getInt("archive_id")
                if (archiveId > 0) {
                    result.add(archiveId)
                }
            }
        } catch (e: Exception) {
            getLogger("user_favorite_dao").error("获取用户收藏失败", ("error", e.message))
        }
        return result.toArray()
    }

    /**
     * 获取用户收藏的档案 arcid 列表
     */
    public static func getUserFavoriteArcids(userId: Int64): Array<String> {
        let result = ArrayList<String>()
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT a.arcid FROM user_favorites uf
                JOIN archives a ON uf.archive_id = a.id
                WHERE uf.user_id = $1
                ORDER BY uf.created_at DESC
            """, [DbInt(userId)])
            for (r in rows) {
                let arcid = r.getText("arcid")
                if (arcid.size > 0) {
                    result.add(arcid)
                }
            }
        } catch (e: Exception) {
            getLogger("user_favorite_dao").error("获取用户收藏arcid失败", ("error", e.message))
        }
        return result.toArray()
    }

    /**
     * 批量检查收藏状态
     * 返回 Map<archiveId, isFavorite>
     */
    public static func getBatchFavoriteStatus(userId: Int64, archiveIds: Array<Int64>): HashMap<Int64, Bool> {
        let result = HashMap<Int64, Bool>()

        if (archiveIds.size == 0) {
            return result
        }

        var ok = true
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT archive_id FROM user_favorites
                WHERE user_id = $1 AND archive_id = ANY($2::bigint[])
            """, [DbInt(userId), DbArray(Array<DbValue>(archiveIds.size, { k => DbInt(archiveIds[k]) }))])
            for (r in rows) {
                let archiveId = r.getInt("archive_id")
                result[archiveId] = true
            }
        } catch (e: Exception) {
            getLogger("user_favorite_dao").error("批量检查收藏状态失败", ("error", e.message))
            ok = false
        }

        // 对于没有收藏或查询失败的档案，设置为 false
        for (archiveId in archiveIds) {
            if (!ok || !result.contains(archiveId)) {
                result[archiveId] = false
            }
        }

        return result
    }

    /**
     * 批量获取收藏时间
     * 返回 Map<archiveId, favoriteTime> (Unix时间戳)
     */
    public static func getBatchFavoriteTime(userId: Int64, archiveIds: Array<Int64>): HashMap<Int64, Int64> {
        let result = HashMap<Int64, Int64>()

        if (archiveIds.size == 0 || userId <= 0) {
            return result
        }

        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT archive_id, COALESCE(CAST(EXTRACT(EPOCH FROM created_at) AS BIGINT), 0) as unix_timestamp FROM user_favorites
                WHERE user_id = $1 AND archive_id = ANY($2::bigint[])
            """, [DbInt(userId), DbArray(Array<DbValue>(archiveIds.size, { k => DbInt(archiveIds[k]) }))])
            for (r in rows) {
                let archiveId = r.getInt("archive_id")
                let unixTimestamp = r.getInt("unix_timestamp")
                if (archiveId > 0) {
                    result[archiveId] = unixTimestamp
                }
            }
        } catch (e: Exception) {
            getLogger("user_favorite_dao").error("批量获取收藏时间失败", ("error", e.message))
        }

        return result
    }

    /**
     * 删除用户的所有收藏记录
     */
    public static func deleteByUserId(userId: Int64): Bool {
        let logger = getLogger("user_favorite_dao")
        try {
            DatabaseConfig.driver().exec("DELETE FROM user_favorites WHERE user_id = $1", [DbInt(userId)])
            return true
        } catch (e: Exception) {
            logger.error("删除用户收藏失败", ("error", e.message))
            return false
        }
    }

    /**
     * 删除特定档案的所有收藏记录
     */
    public static func deleteByArchiveId(archiveId: Int64): Bool {
        let logger = getLogger("user_favorite_dao")
        try {
            DatabaseConfig.driver().exec("DELETE FROM user_favorites WHERE archive_id = $1", [DbInt(archiveId)])
            return true
        } catch (e: Exception) {
            logger.error("删除档案收藏失败", ("error", e.message))
            return false
        }
    }

    /**
     * 获取收藏数量
     */
    public static func getFavoriteCount(userId: Int64): Int64 {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT COUNT(*) FROM user_favorites WHERE user_id = $1
            """, [DbInt(userId)])
            if (rows.size > 0) {
                return rows[0].getInt("count")
            }
            return 0
        } catch (_: Exception) {
            return 0
        }
    }

    /**
     * 获取用户收藏的档案详情列表（带分页）
     * 返回完整的档案信息，包括标签
     */
    public static func getUserFavoriteArchives(userId: Int64, start: Int32, count: Int32): (Array<ArchiveData>, Int64) {
        let result = ArrayList<ArchiveData>()
        var totalCount: Int64 = 0
        try {
            // 先获取总数
            let countRows = DatabaseConfig.driver().query("""
                SELECT COUNT(*) FROM user_favorites WHERE user_id = $1
            """, [DbInt(userId)])
            if (countRows.size > 0) {
                totalCount = countRows[0].getInt("count")
            }

            // 获取分页数据，使用标准 JOIN 获取用户特定数据
            let rows = DatabaseConfig.driver().query("""
                SELECT awt.arcid, awt.filename, awt.title, awt.summary, awt.thumbhash, awt.cover_asset_id,
                       awt.created_at, awt.updated_at, awt.release_at, awt.relative_path, awt.file_size,
                       awt.pagecount,
                       COALESCE(uas.updated_at, '1970-01-01 00:00:00') as last_read_time,
                       COALESCE(uas.progress, 0) as progress, awt.tags
                FROM archive_metadata_search awt
                INNER JOIN archives a ON awt.arcid = a.arcid
                INNER JOIN user_favorites uf ON a.id = uf.archive_id
                LEFT JOIN user_archive_status uas ON a.id = uas.archive_id AND uas.user_id = uf.user_id
                WHERE uf.user_id = $1
                ORDER BY uf.created_at DESC
                LIMIT $2 OFFSET $3
            """, [DbInt(userId), DbInt(Int64(count)), DbInt(Int64(start))])
            for (r in rows) {
                let archive = ArchiveDataMappers.fromArchivesWithTagsRow(r)
                result.add(archive)
            }
        } catch (e: Exception) {
            getLogger("user_favorite_dao").error("获取用户收藏档案详情失败", ("error", e.message), ("stack", e.toString()))
            getLogger("user_favorite_dao").error("查询参数", ("userId", userId.toString()), ("start", start.toString()), ("count", count.toString()))
        }
        return (result.toArray(), totalCount)
    }
}