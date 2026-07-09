package lanlu.contexts.user.infrastructure.persistence

import csorm.*
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
        let updateSql = """
            UPDATE user_archive_status
            SET is_new = true, updated_at = CURRENT_TIMESTAMP
            WHERE user_id = $1 AND archive_id = $2
        """
        let updateParams: Array<Value> = [vint(userId), vint(archiveId)]
        let insertSql = """
            INSERT INTO user_archive_status (user_id, archive_id, is_new, updated_at)
            SELECT $1, $2, true, CURRENT_TIMESTAMP
            WHERE NOT EXISTS (
                SELECT 1 FROM user_archive_status WHERE user_id = $3 AND archive_id = $4
            )
        """
        let insertParams: Array<Value> = [vint(userId), vint(archiveId), vint(userId), vint(archiveId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let updated = db.execRaw(updateSql, updateParams)
                    if (updated <= 0) {
                        db.execRaw(insertSql, insertParams)
                    }
                    let _ = DerivedCacheUtils.bumpTankoubonAggregatedUserVersion(userId, "setIsNew:${archiveId.toString()}")
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
     * 清除新状态/标记为已读（针对特定用户）
     */
    public static func clearIsNew(userId: Int64, archiveId: Int64): Bool {
        let logger = getLogger("user_archive_status_dao")
        let updateSql = """
            UPDATE user_archive_status
            SET is_new = false, updated_at = CURRENT_TIMESTAMP
            WHERE user_id = $1 AND archive_id = $2
        """
        let updateParams: Array<Value> = [vint(userId), vint(archiveId)]
        let insertSql = """
            INSERT INTO user_archive_status (user_id, archive_id, is_new, updated_at)
            SELECT $1, $2, false, CURRENT_TIMESTAMP
            WHERE NOT EXISTS (
                SELECT 1 FROM user_archive_status WHERE user_id = $3 AND archive_id = $4
            )
        """
        let insertParams: Array<Value> = [vint(userId), vint(archiveId), vint(userId), vint(archiveId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let updated = db.execRaw(updateSql, updateParams)
                    if (updated <= 0) {
                        db.execRaw(insertSql, insertParams)
                    }
                    let _ = DerivedCacheUtils.bumpTankoubonAggregatedUserVersion(userId, "clearIsNew:${archiveId.toString()}")
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
     * 更新用户阅读进度并自动标记为已读
     * @param userId 用户ID
     * @param archiveId 归档ID
     * @param progress 阅读页数/进度值
     * @return 更新是否成功
     */
    public static func updateProgress(userId: Int64, archiveId: Int64, progress: Int32): Bool {
        let logger = getLogger("user_archive_status_dao")
        let updateSql = """
            UPDATE user_archive_status
            SET is_new = false,
                progress = $1,
                updated_at = CURRENT_TIMESTAMP
            WHERE user_id = $2 AND archive_id = $3
        """
        let updateParams: Array<Value> = [vint(Int64(progress)), vint(userId), vint(archiveId)]
        let insertSql = """
            INSERT INTO user_archive_status (user_id, archive_id, is_new, progress, updated_at)
            SELECT $1, $2, false, $3, CURRENT_TIMESTAMP
            WHERE NOT EXISTS (
                SELECT 1 FROM user_archive_status WHERE user_id = $4 AND archive_id = $5
            )
        """
        let insertParams: Array<Value> = [vint(userId), vint(archiveId), vint(Int64(progress)), vint(userId), vint(archiveId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let updated = db.execRaw(updateSql, updateParams)
                    if (updated <= 0) {
                        db.execRaw(insertSql, insertParams)
                    }
                    let _ = DerivedCacheUtils.bumpTankoubonAggregatedUserVersion(userId, "updateProgress:${archiveId.toString()}")
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
     * 获取用户对特定归档的状态
     */
    public static func getStatus(userId: Int64, archiveId: Int64): Option<UserArchiveStatusRow> {
        let sql = """
            SELECT id, user_id, archive_id, is_new, progress, created_at, updated_at
            FROM user_archive_status
            WHERE user_id = $1 AND archive_id = $2
        """
        let params: Array<Value> = [vint(userId), vint(archiveId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<UserArchiveStatusRow>(sql, params, { row =>
                        let r = UserArchiveStatusRow()
                        r.id = row.getOrNullInt64(0) ?? 0
                        r.userId = row.getOrNullInt64(1) ?? 0
                        r.archiveId = row.getOrNullInt64(2) ?? 0
                        r.isNew = row.getOrNullBool(3) ?? true
                        r.progress = row.getOrNullInt32(4) ?? 0
                        r.createdAt = row.getOrNullText(5) ?? ""
                        r.updatedAt = row.getOrNullText(6) ?? ""
                        return r
                    })
                } catch (_: Exception) {
                    return None
                }
            case None => return None
        }
    }

    /**
     * 获取用户对特定归档的最后阅读时间
     * @param userId 用户ID
     * @param archiveId 归档ID
     * @return 最后阅读时间的Unix时间戳，如果没有记录返回 0
     */
    public static func getLastReadTime(userId: Int64, archiveId: Int64): Int64 {
        let sql = """
            SELECT COALESCE(CAST(EXTRACT(EPOCH FROM updated_at) AS BIGINT), 0)
            FROM user_archive_status
            WHERE user_id = $1 AND archive_id = $2
        """
        let params: Array<Value> = [vint(userId), vint(archiveId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<Int64>(sql, params, { r => r.getOrNullInt64(0) ?? 0 }) ?? 0
                } catch (_: Exception) {
                    return 0
                }
            case None => return 0
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

        let sql = """
            SELECT archive_id, is_new, progress
            FROM user_archive_status
            WHERE user_id = $1 AND archive_id = ANY($2::bigint[])
        """
        let params: Array<Value> = [vint(userId), int64Array(archiveIds)]
        var ok = false
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<(Int64, Bool)>(sql, params, { r =>
                        (r.getOrNullInt64(0) ?? 0, r.getOrNullBool(1) ?? true)
                    })
                    for (pair in rows) {
                        let (archiveId, isNew) = pair
                        result[archiveId] = isNew
                    }
                    ok = true
                } catch (e: Exception) {
                    getLogger("user_archive_status_dao").error("批量获取用户归档状态失败", ("error", e.message))
                }
            case None =>
                getLogger("user_archive_status_dao").error("无法连接到数据库")
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

        let sql = """
            SELECT archive_id, progress, COALESCE(CAST(EXTRACT(EPOCH FROM updated_at) AS BIGINT), 0) as unix_timestamp
            FROM user_archive_status
            WHERE user_id = $1 AND archive_id = ANY($2::bigint[])
        """
        let params: Array<Value> = [vint(userId), int64Array(archiveIds)]
        var ok = false
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<(Int64, Int32, Int64)>(sql, params, { r =>
                        (r.getOrNullInt64(0) ?? 0, r.getOrNullInt32(1) ?? 0, r.getOrNullInt64(2) ?? 0)
                    })
                    for (triple in rows) {
                        let (archiveId, progress, timestamp) = triple
                        progressMap[archiveId] = progress
                        lastReadTimeMap[archiveId] = timestamp
                    }
                    ok = true
                } catch (e: Exception) {
                    getLogger("user_archive_status_dao").error("批量获取用户归档进度失败", ("error", e.message))
                }
            case None =>
                getLogger("user_archive_status_dao").error("无法连接到数据库")
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
        let sql = "DELETE FROM user_archive_status WHERE user_id = $1"
        let params: Array<Value> = [vint(userId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("删除用户归档状态失败", ("error", e.message))
                    return false
                }
            case None => return false
        }
    }

    /**
     * 删除特定归档的所有用户状态记录
     */
    public static func deleteByArchiveId(archiveId: Int64): Bool {
        let logger = getLogger("user_archive_status_dao")
        let sql = "DELETE FROM user_archive_status WHERE archive_id = $1"
        let params: Array<Value> = [vint(archiveId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("删除归档状态失败", ("error", e.message))
                    return false
                }
            case None => return false
        }
    }

    /**
     * 将 archive_metadata_search 行（含 tags、last_read_time、progress）映射为 ArchiveData。
     * 列顺序需与 getUserReadArchives 的 SELECT 一致。
     */
    private static func mapArchivesWithTagsRow(row: Row): ArchiveData {
        let archive = ArchiveData()
        archive.id = row.getOrNullText(0) ?? ""
        archive.filename = row.getOrNullText(1) ?? ""
        archive.title = row.getOrNullText(2) ?? ""
        archive.summary = row.getOrNullText(3) ?? ""
        archive.thumbhash = row.getOrNullText(4) ?? ""
        archive.cover_asset_id = row.getOrNullInt64(5) ?? 0
        archive.created_at = row.getOrNullText(6) ?? ""
        archive.updated_at = row.getOrNullText(7) ?? ""
        archive.release_at = row.getOrNullText(8) ?? ""
        archive.relative_path = row.getOrNullText(9) ?? ""
        archive.file_size = row.getOrNullInt64(10) ?? 0
        archive.pagecount = row.getOrNullInt32(11) ?? 0
        archive.last_read_time = row.getOrNullText(12) ?? ""
        archive.progress = row.getOrNullInt32(13) ?? 0
        archive.tags = row.getOrNullText(14) ?? ""
        return archive
    }

    /**
     * 获取用户已读的档案列表（带分页）
     * 返回 is_new = false 的档案详情
     */
    public static func getUserReadArchives(userId: Int64, start: Int32, count: Int32): (Array<ArchiveData>, Int64) {
        let result = ArrayList<ArchiveData>()
        var totalCount: Int64 = 0
        let logger = getLogger("user_archive_status_dao")

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    // 先获取总数
                    let countSql = """
                        SELECT COUNT(*) FROM user_archive_status
                        WHERE user_id = $1 AND is_new = false
                    """
                    let countParams: Array<Value> = [vint(userId)]
                    let countRows = db.raw<Int64>(countSql, countParams, { r => r.getOrNullInt64(0) ?? 0 })
                    if (countRows.size > 0) {
                        totalCount = countRows[0]
                    }

                    // 获取分页数据，使用标准 JOIN 获取用户特定数据
                    let sql = """
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
                    """
                    let params: Array<Value> = [vint(userId), vint(Int64(count)), vint(Int64(start))]
                    let rows = db.raw<ArchiveData>(sql, params, { row => mapArchivesWithTagsRow(row) })
                    for (archive in rows) {
                        result.add(archive)
                    }
                } catch (e: Exception) {
                    logger.error("获取用户已读档案失败", ("error", e.message))
                }
            case None =>
                logger.error("无法连接到数据库")
        }
        return (result.toArray(), totalCount)
    }
}