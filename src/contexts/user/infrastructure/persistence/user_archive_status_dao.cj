package lanlu.contexts.user.infrastructure.persistence

import ace_orm.*
import stdx.log.*
import std.collection.*
import lanlu.shared.config.*
import lanlu.infrastructure.kv.*
import lanlu.contexts.archive.infrastructure.persistence.ArchiveData
import lanlu.contexts.archive.infrastructure.persistence.ArchiveDataMappers
import lanlu.shared.utils.*

public class UserArchiveStatusRow {
    public var id: Int64 = 0
    public var userId: Int64 = 0
    public var archiveId: Int64 = 0
    public var isNew: Bool = true
    public var progress: Int32 = 0
    public var createdAt: String = ""
    public var updatedAt: String = ""

    public init() {}
}

public class UserArchiveStatusDao {
    /**
     * 设置归档为新状态（针对特定用户）
     */
    public static func setIsNew(userId: Int64, archiveId: Int64): Bool {
        let logger = getLogger("user_archive_status_dao")
        try {
            let updated = DatabaseConfig.driver().exec("""
                UPDATE user_archive_status
                SET is_new = true, updated_at = CURRENT_TIMESTAMP
                WHERE user_id = $1 AND archive_id = $2
            """, [DbInt(userId), DbInt(archiveId)])
            if (updated <= 0) {
                DatabaseConfig.driver().exec("""
                    INSERT INTO user_archive_status (user_id, archive_id, is_new, updated_at)
                    SELECT $1, $2, true, CURRENT_TIMESTAMP
                    WHERE NOT EXISTS (
                        SELECT 1 FROM user_archive_status WHERE user_id = $3 AND archive_id = $4
                    )
                """, [DbInt(userId), DbInt(archiveId), DbInt(userId), DbInt(archiveId)])
            }
            let _ = DerivedCacheUtils.bumpTankoubonAggregatedUserVersion(userId, "setIsNew:${archiveId.toString()}")
            return true
        } catch (e: Exception) {
            logger.error("设置isNew标记失败", ("error", e.message))
            return false
        }
    }

    /**
     * 清除新状态/标记为已读（针对特定用户）
     */
    public static func clearIsNew(userId: Int64, archiveId: Int64): Bool {
        let logger = getLogger("user_archive_status_dao")
        try {
            let updated = DatabaseConfig.driver().exec("""
                UPDATE user_archive_status
                SET is_new = false, updated_at = CURRENT_TIMESTAMP
                WHERE user_id = $1 AND archive_id = $2
            """, [DbInt(userId), DbInt(archiveId)])
            if (updated <= 0) {
                DatabaseConfig.driver().exec("""
                    INSERT INTO user_archive_status (user_id, archive_id, is_new, updated_at)
                    SELECT $1, $2, false, CURRENT_TIMESTAMP
                    WHERE NOT EXISTS (
                        SELECT 1 FROM user_archive_status WHERE user_id = $3 AND archive_id = $4
                    )
                """, [DbInt(userId), DbInt(archiveId), DbInt(userId), DbInt(archiveId)])
            }
            let _ = DerivedCacheUtils.bumpTankoubonAggregatedUserVersion(userId, "clearIsNew:${archiveId.toString()}")
            return true
        } catch (e: Exception) {
            logger.error("清除isNew标记失败", ("error", e.message))
            return false
        }
    }

    /**
     * 更新用户阅读进度并自动标记为已读
     * @param userId 用户ID
     * @param archiveId 归档ID
     * @param progress 阅读页数/进度值
     * @return 更新是否成功
     */
    public static func updateProgress(userId: Int64, archiveId: Int64, progress: Int32): Bool {
        let logger = getLogger("user_archive_status_dao")
        try {
            let updated = DatabaseConfig.driver().exec("""
                UPDATE user_archive_status
                SET is_new = false,
                    progress = $1,
                    updated_at = CURRENT_TIMESTAMP
                WHERE user_id = $2 AND archive_id = $3
            """, [DbInt(Int64(progress)), DbInt(userId), DbInt(archiveId)])
            if (updated <= 0) {
                DatabaseConfig.driver().exec("""
                    INSERT INTO user_archive_status (user_id, archive_id, is_new, progress, updated_at)
                    SELECT $1, $2, false, $3, CURRENT_TIMESTAMP
                    WHERE NOT EXISTS (
                        SELECT 1 FROM user_archive_status WHERE user_id = $4 AND archive_id = $5
                    )
                """, [DbInt(userId), DbInt(archiveId), DbInt(Int64(progress)), DbInt(userId), DbInt(archiveId)])
            }
            let _ = DerivedCacheUtils.bumpTankoubonAggregatedUserVersion(userId, "updateProgress:${archiveId.toString()}")
            return true
        } catch (e: Exception) {
            logger.error("更新阅读进度失败", ("error", e.message))
            return false
        }
    }

    /**
     * 获取用户对特定归档的状态
     */
    public static func getStatus(userId: Int64, archiveId: Int64): Option<UserArchiveStatusRow> {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, user_id, archive_id, is_new, progress, created_at, updated_at
                FROM user_archive_status
                WHERE user_id = $1 AND archive_id = $2
            """, [DbInt(userId), DbInt(archiveId)])
            if (rows.size > 0) {
                let r = rows[0]
                let row = UserArchiveStatusRow()
                row.id = r.getInt("id")
                row.userId = r.getInt("user_id")
                row.archiveId = r.getInt("archive_id")
                row.isNew = r.getBool("is_new")
                row.progress = Int32(r.getInt("progress"))
                row.createdAt = r.getText("created_at")
                row.updatedAt = r.getText("updated_at")
                return Some(row)
            }
            return None
        } catch (_: Exception) {
            return None
        }
    }

    /**
     * 获取用户对特定归档的最后阅读时间
     * @param userId 用户ID
     * @param archiveId 归档ID
     * @return 最后阅读时间的Unix时间戳，如果没有记录返回 0
     */
    public static func getLastReadTime(userId: Int64, archiveId: Int64): Int64 {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT COALESCE(CAST(EXTRACT(EPOCH FROM updated_at) AS BIGINT), 0) as unix_timestamp
                FROM user_archive_status
                WHERE user_id = $1 AND archive_id = $2
            """, [DbInt(userId), DbInt(archiveId)])
            if (rows.size > 0) {
                return rows[0].getInt("unix_timestamp")
            }
            return 0
        } catch (_: Exception) {
            return 0
        }
    }

    /**
     * 检查归档对于特定用户是否为新
     * 如果没有记录，默认返回 true（新归档）
     */
    public static func isNew(userId: Int64, archiveId: Int64): Bool {
        match (getStatus(userId, archiveId)) {
            case Some(row) => return row.isNew
            case None => return true  // 没有记录，默认为新
        }
    }

    /**
     * 获取用户对特定归档的阅读进度
     * @param userId 用户ID
     * @param archiveId 归档ID
     * @return 阅读进度（页数），如果没有记录返回 0
     */
    public static func getProgress(userId: Int64, archiveId: Int64): Int32 {
        match (getStatus(userId, archiveId)) {
            case Some(row) => return row.progress
            case None => return 0  // 没有记录，默认为 0
        }
    }

    /**
     * 批量获取用户对多个归档的状态
     * 返回 Map<archiveId, isNew>
     */
    public static func getBatchStatus(userId: Int64, archiveIds: Array<Int64>): HashMap<Int64, Bool> {
        let result = HashMap<Int64, Bool>()

        if (archiveIds.size == 0) {
            return result
        }

        var ok = true
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT archive_id, is_new, progress
                FROM user_archive_status
                WHERE user_id = $1 AND archive_id = ANY($2::bigint[])
            """, [DbInt(userId), DbArray(Array<DbValue>(archiveIds.size, { k => DbInt(archiveIds[k]) }))])
            for (r in rows) {
                let archiveId = r.getInt("archive_id")
                let isNew = r.getBool("is_new")
                result[archiveId] = isNew
            }
        } catch (e: Exception) {
            getLogger("user_archive_status_dao").error("批量获取用户归档状态失败", ("error", e.message))
            ok = false
        }

        // 对于没有记录或查询失败的归档，默认为新
        for (archiveId in archiveIds) {
            if (!ok || !result.contains(archiveId)) {
                result[archiveId] = true
            }
        }

        return result
    }

    /**
     * 批量获取用户对多个归档的进度和最后阅读时间
     * 返回包含进度和时间戳的元组 (progressMap, lastReadTimeMap)
     */
    public static func getBatchProgressAndTime(userId: Int64, archiveIds: Array<Int64>): (HashMap<Int64, Int32>, HashMap<Int64, Int64>) {
        let progressMap = HashMap<Int64, Int32>()
        let lastReadTimeMap = HashMap<Int64, Int64>()

        if (archiveIds.size == 0) {
            return (progressMap, lastReadTimeMap)
        }

        var ok = true
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT archive_id, progress, COALESCE(CAST(EXTRACT(EPOCH FROM updated_at) AS BIGINT), 0) as unix_timestamp
                FROM user_archive_status
                WHERE user_id = $1 AND archive_id = ANY($2::bigint[])
            """, [DbInt(userId), DbArray(Array<DbValue>(archiveIds.size, { k => DbInt(archiveIds[k]) }))])
            for (r in rows) {
                let archiveId = r.getInt("archive_id")
                let progress = Int32(r.getInt("progress"))
                let timestamp = r.getInt("unix_timestamp")

                progressMap[archiveId] = progress
                lastReadTimeMap[archiveId] = timestamp
            }
        } catch (e: Exception) {
            getLogger("user_archive_status_dao").error("批量获取用户归档进度失败", ("error", e.message))
            ok = false
        }

        // 对于没有记录或查询失败的归档，设置默认值
        for (archiveId in archiveIds) {
            if (!ok || !progressMap.contains(archiveId)) {
                progressMap[archiveId] = 0
            }
            if (!ok || !lastReadTimeMap.contains(archiveId)) {
                lastReadTimeMap[archiveId] = 0
            }
        }

        return (progressMap, lastReadTimeMap)
    }

    /**
     * 删除用户的所有归档状态记录
     */
    public static func deleteByUserId(userId: Int64): Bool {
        let logger = getLogger("user_archive_status_dao")
        try {
            DatabaseConfig.driver().exec("DELETE FROM user_archive_status WHERE user_id = $1", [DbInt(userId)])
            return true
        } catch (e: Exception) {
            logger.error("删除用户归档状态失败", ("error", e.message))
            return false
        }
    }

    /**
     * 删除特定归档的所有用户状态记录
     */
    public static func deleteByArchiveId(archiveId: Int64): Bool {
        let logger = getLogger("user_archive_status_dao")
        try {
            DatabaseConfig.driver().exec("DELETE FROM user_archive_status WHERE archive_id = $1", [DbInt(archiveId)])
            return true
        } catch (e: Exception) {
            logger.error("删除归档状态失败", ("error", e.message))
            return false
        }
    }

    /**
     * 获取用户已读的档案列表（带分页）
     * 返回 is_new = false 的档案详情
     */
    public static func getUserReadArchives(userId: Int64, start: Int32, count: Int32): (Array<ArchiveData>, Int64) {
        let result = ArrayList<ArchiveData>()
        var totalCount: Int64 = 0
        try {
            // 先获取总数
            let countRows = DatabaseConfig.driver().query("""
                SELECT COUNT(*) FROM user_archive_status
                WHERE user_id = $1 AND is_new = false
            """, [DbInt(userId)])
            if (countRows.size > 0) {
                totalCount = countRows[0].getInt("count")
            }

            // 获取分页数据，使用标准 JOIN 获取用户特定数据
            let rows = DatabaseConfig.driver().query("""
                SELECT awt.arcid, awt.filename, awt.title, awt.summary, awt.thumbhash, awt.cover_asset_id,
                       awt.created_at, awt.updated_at, awt.release_at, awt.relative_path, awt.file_size,
                       awt.pagecount, uas.updated_at as last_read_time,
                       COALESCE(uas.progress, 0) as progress, awt.tags
                FROM archive_metadata_search awt
                INNER JOIN archives a ON awt.arcid = a.arcid
                INNER JOIN user_archive_status uas ON a.id = uas.archive_id
                WHERE uas.user_id = $1 AND uas.is_new = false
                ORDER BY uas.updated_at DESC
                LIMIT $2 OFFSET $3
            """, [DbInt(userId), DbInt(Int64(count)), DbInt(Int64(start))])
            for (r in rows) {
                let archive = ArchiveDataMappers.fromArchivesWithTagsRow(r)
                result.add(archive)
            }
        } catch (e: Exception) {
            getLogger("user_archive_status_dao").error("获取用户已读档案失败", ("error", e.message))
        }
        return (result.toArray(), totalCount)
    }
}