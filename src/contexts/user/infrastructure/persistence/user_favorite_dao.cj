package lanlu.contexts.user.infrastructure.persistence

import csorm.*
import std.collection.*
import stdx.log.*
import lanlu.shared.config.*
import lanlu.contexts.archive.infrastructure.persistence.ArchiveData
import lanlu.contexts.archive.infrastructure.persistence.ArchiveDataMappers
import lanlu.shared.utils.*

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
        let sql = """
            INSERT INTO user_favorites (user_id, archive_id, created_at)
            SELECT $1, $2, CURRENT_TIMESTAMP
            WHERE NOT EXISTS (
                SELECT 1 FROM user_favorites WHERE user_id = $3 AND archive_id = $4
            )
        """
        let params: Array<Value> = [vint(userId), vint(archiveId), vint(userId), vint(archiveId)]
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
     */
    public static func removeFavorite(userId: Int64, archiveId: Int64): Bool {
        let logger = getLogger("user_favorite_dao")
        let sql = """
            DELETE FROM user_favorites
            WHERE user_id = $1 AND archive_id = $2
        """
        let params: Array<Value> = [vint(userId), vint(archiveId)]
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
     */
    public static func isFavorite(userId: Int64, archiveId: Int64): Bool {
        let sql = """
            SELECT COUNT(*) FROM user_favorites
            WHERE user_id = $1 AND archive_id = $2
        """
        let params: Array<Value> = [vint(userId), vint(archiveId)]
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

    /**
     * 获取用户的所有收藏（返回 archive_id 列表）
     */
    public static func getUserFavorites(userId: Int64): Array<Int64> {
        let result = ArrayList<Int64>()
        let sql = """
            SELECT archive_id FROM user_favorites
            WHERE user_id = $1
            ORDER BY created_at DESC
        """
        let params: Array<Value> = [vint(userId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Int64>(sql, params, { r => r.getOrNullInt64(0) ?? 0 })
                    for (archiveId in rows) {
                        if (archiveId > 0) {
                            result.add(archiveId)
                        }
                    }
                } catch (e: Exception) {
                    getLogger("user_favorite_dao").error("获取用户收藏失败", ("error", e.message))
                }
            case None =>
                getLogger("user_favorite_dao").error("无法连接到数据库")
        }
        return result.toArray()
    }

    /**
     * 获取用户收藏的档案 arcid 列表
     */
    public static func getUserFavoriteArcids(userId: Int64): Array<String> {
        let result = ArrayList<String>()
        let sql = """
            SELECT a.arcid FROM user_favorites uf
            JOIN archives a ON uf.archive_id = a.id
            WHERE uf.user_id = $1
            ORDER BY uf.created_at DESC
        """
        let params: Array<Value> = [vint(userId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<String>(sql, params, { r => r.getOrNullText(0) ?? "" })
                    for (arcid in rows) {
                        if (arcid.size > 0) {
                            result.add(arcid)
                        }
                    }
                } catch (e: Exception) {
                    getLogger("user_favorite_dao").error("获取用户收藏arcid失败", ("error", e.message))
                }
            case None =>
                getLogger("user_favorite_dao").error("无法连接到数据库")
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

        let sql = """
            SELECT archive_id FROM user_favorites
            WHERE user_id = $1 AND archive_id = ANY($2::bigint[])
        """
        let params: Array<Value> = [vint(userId), int64Array(archiveIds)]
        var ok = false
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Int64>(sql, params, { r => r.getOrNullInt64(0) ?? 0 })
                    for (archiveId in rows) {
                        result[archiveId] = true
                    }
                    ok = true
                } catch (e: Exception) {
                    getLogger("user_favorite_dao").error("批量检查收藏状态失败", ("error", e.message))
                }
            case None =>
                getLogger("user_favorite_dao").error("无法连接到数据库")
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

        let sql = """
            SELECT archive_id, COALESCE(CAST(EXTRACT(EPOCH FROM created_at) AS BIGINT), 0) as unix_timestamp FROM user_favorites
            WHERE user_id = $1 AND archive_id = ANY($2::bigint[])
        """
        let params: Array<Value> = [vint(userId), int64Array(archiveIds)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<(Int64, Int64)>(sql, params, { r =>
                        (r.getOrNullInt64(0) ?? 0, r.getOrNullInt64(1) ?? 0)
                    })
                    for (pair in rows) {
                        let (archiveId, unixTimestamp) = pair
                        if (archiveId > 0) {
                            result[archiveId] = unixTimestamp
                        }
                    }
                } catch (e: Exception) {
                    getLogger("user_favorite_dao").error("批量获取收藏时间失败", ("error", e.message))
                }
            case None =>
                getLogger("user_favorite_dao").error("无法连接到数据库")
        }

        return result
    }

    /**
     * 删除用户的所有收藏记录
     */
    public static func deleteByUserId(userId: Int64): Bool {
        let logger = getLogger("user_favorite_dao")
        let sql = "DELETE FROM user_favorites WHERE user_id = $1"
        let params: Array<Value> = [vint(userId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("删除用户收藏失败", ("error", e.message))
                    return false
                }
            case None => return false
        }
    }

    /**
     * 删除特定档案的所有收藏记录
     */
    public static func deleteByArchiveId(archiveId: Int64): Bool {
        let logger = getLogger("user_favorite_dao")
        let sql = "DELETE FROM user_favorites WHERE archive_id = $1"
        let params: Array<Value> = [vint(archiveId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("删除档案收藏失败", ("error", e.message))
                    return false
                }
            case None => return false
        }
    }

    /**
     * 获取收藏数量
     */
    public static func getFavoriteCount(userId: Int64): Int64 {
        let sql = """
            SELECT COUNT(*) FROM user_favorites WHERE user_id = $1
        """
        let params: Array<Value> = [vint(userId)]
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

    /**
     * 将 archive_metadata_search 行（含 tags、last_read_time、progress）映射为 ArchiveData。
     * 列顺序需与 getUserFavoriteArchives 的 SELECT 一致。
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
        archive.last_read_time = row.getOrNullInt64(12) ?? 0
        archive.progress = row.getOrNullInt32(13) ?? 0
        archive.tags = row.getOrNullText(14) ?? ""
        return archive
    }

    /**
     * 获取用户收藏的档案详情列表（带分页）
     * 返回完整的档案信息，包括标签
     */
    public static func getUserFavoriteArchives(userId: Int64, start: Int32, count: Int32): (Array<ArchiveData>, Int64) {
        let result = ArrayList<ArchiveData>()
        var totalCount: Int64 = 0
        let logger = getLogger("user_favorite_dao")

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    // 先获取总数
                    let countSql = """
                        SELECT COUNT(*) FROM user_favorites WHERE user_id = $1
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
                               awt.pagecount,
                               COALESCE(EXTRACT(EPOCH FROM uas.updated_at)::BIGINT, 0) as last_read_time,
                               COALESCE(uas.progress, 0) as progress, awt.tags
                        FROM archive_metadata_search awt
                        INNER JOIN archives a ON awt.arcid = a.arcid
                        INNER JOIN user_favorites uf ON a.id = uf.archive_id
                        LEFT JOIN user_archive_status uas ON a.id = uas.archive_id AND uas.user_id = uf.user_id
                        WHERE uf.user_id = $1
                        ORDER BY uf.created_at DESC
                        LIMIT $2 OFFSET $3
                    """
                    let params: Array<Value> = [vint(userId), vint(Int64(count)), vint(Int64(start))]
                    let rows = db.raw<ArchiveData>(sql, params, { row => mapArchivesWithTagsRow(row) })
                    for (archive in rows) {
                        result.add(archive)
                    }
                } catch (e: Exception) {
                    logger.error("获取用户收藏档案详情失败", ("error", e.message), ("stack", e.toString()))
                    logger.error("查询参数", ("userId", userId.toString()), ("start", start.toString()), ("count", count.toString()))
                }
            case None =>
                logger.error("无法连接到数据库")
        }
        return (result.toArray(), totalCount)
    }
}