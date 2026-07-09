package lanlu.contexts.user.infrastructure.persistence

import csorm.*
import std.collection.*
import std.time.DateTime
import lanlu.shared.config.*
import lanlu.contexts.archive.infrastructure.persistence.ArchiveData
import lanlu.shared.utils.*
import stdx.log.*

/**
 * 阅读趋势数据项
 */
public class ReadingTrendItem {
    public var date: String = ""
    public var count: Int64 = 0

    public init() {}

    public init(date: String, count: Int64) {
        this.date = date
        this.count = count
    }
}

/**
 * 用户统计数据访问对象
 * 提供用户阅读统计、趋势分析等功能
 */
public class UserStatsDao {
    /**
     * 获取用户已读档案数量
     */
    public static func getReadCount(userId: Int64): Int64 {
        let params: Array<Value> = [vint(userId)]
        let sql = """
            SELECT COUNT(*) FROM user_archive_status
            WHERE user_id = $1 AND is_new = false
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

    /**
     * 获取全局总阅读页数（所有用户）
     * 计算所有用户的 progress 总和
     */
    public static func getGlobalTotalPagesRead(): Int64 {
        let sql = """
            SELECT COALESCE(SUM(progress), 0) as total_pages
            FROM user_archive_status
            WHERE is_new = false
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Int64>(sql, [], { r => r.getOrNullInt64(0) ?? 0 })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return 0
                } catch (e: Exception) {
                    getLogger("user_stats_dao").error("获取全局总阅读页数失败", ("error", e.message))
                    return 0
                }
            case None => return 0
        }
    }

    /**
     * 获取用户总阅读页数
     * 计算用户已读档案的 progress 总和（从 user_archive_status.progress 获取）
     */
    public static func getTotalPagesRead(userId: Int64): Int64 {
        let params: Array<Value> = [vint(userId)]
        let sql = """
            SELECT COALESCE(SUM(uas.progress), 0) as total_pages
            FROM user_archive_status uas
            WHERE uas.user_id = $1 AND uas.is_new = false
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Int64>(sql, params, { r => r.getOrNullInt64(0) ?? 0 })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return 0
                } catch (e: Exception) {
                    getLogger("user_stats_dao").error("获取总阅读页数失败", ("error", e.message))
                    return 0
                }
            case None => return 0
        }
    }

    /**
     * 获取档案总数
     */
    public static func getTotalArchives(): Int64 {
        let sql = "SELECT COUNT(*) FROM archives"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Int64>(sql, [], { r => r.getOrNullInt64(0) ?? 0 })
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
     * 获取阅读趋势（按日期分组统计）
     * @param userId 用户ID
     * @param days 统计天数
     * @return 按日期分组的阅读数量列表，包含所有日期（缺失日期填充0）
     */
    public static func getReadingTrend(userId: Int64, days: Int32): Array<ReadingTrendItem> {
        let result = ArrayList<ReadingTrendItem>()
        let params: Array<Value> = [vint(userId), vint(Int64(days))]
        let sql = """
            SELECT DATE(updated_at) as date, COUNT(*) as count
            FROM user_archive_status
            WHERE user_id = $1 AND is_new = false
              AND updated_at >= CURRENT_DATE - (($2::text) || ' days')::INTERVAL
            GROUP BY DATE(updated_at)
            ORDER BY date ASC
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<ReadingTrendItem>(sql, params, { row =>
                        let item = ReadingTrendItem()
                        item.date = row.getOrNullText(0) ?? ""
                        item.count = row.getOrNullInt64(1) ?? 0
                        return item
                    })

                    // 构建日期到数量的映射
                    let trendMap = HashMap<String, Int64>()
                    for (item in rows) {
                        trendMap[item.date] = item.count
                    }

                    // 生成所有日期的数据，包括没有阅读记录的日期
                    // 在应用层用 DateTime 计算日期，避免循环内逐天查询数据库
                    let today = DateTime.now()
                    for (offset in 0..=days-1) {
                        let item = ReadingTrendItem()
                        // 计算日期：从今天往前推 offset 天
                        item.date = today.addDays(Int64(0 - offset)).format("yyyy-MM-dd")
                        // 如果数据库中有该日期的数据则使用，否则为0
                        item.count = trendMap.get(item.date) ?? 0
                        result.add(item)
                    }
                } catch (e: Exception) {
                    getLogger("user_stats_dao").error("获取阅读趋势失败", ("error", e.message))
                }
            case None =>
                getLogger("user_stats_dao").error("无法连接到数据库")
        }
        return result.toArray()
    }

    /**
     * 获取最近阅读的档案
     * @param userId 用户ID
     * @param limit 返回数量限制
     * @return 最近阅读的档案列表
     */
    public static func getRecentReadArchives(userId: Int64, limit: Int32): Array<ArchiveData> {
        let result = ArrayList<ArchiveData>()
        let params: Array<Value> = [vint(userId), vint(Int64(limit))]
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
            LIMIT $2
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<ArchiveData>(sql, params, { row => mapArchivesWithTagsRow(row) })
                    for (row in rows) {
                        result.add(row)
                    }
                } catch (e: Exception) {
                    getLogger("user_stats_dao").error("获取最近阅读档案失败", ("error", e.message))
                }
            case None =>
                getLogger("user_stats_dao").error("无法连接到数据库")
        }
        return result.toArray()
    }

    /**
     * 获取最近收藏的档案
     * @param userId 用户ID
     * @param limit 返回数量限制
     * @return 最近收藏的档案列表
     */
    public static func getRecentFavoriteArchives(userId: Int64, limit: Int32): Array<ArchiveData> {
        let result = ArrayList<ArchiveData>()
        let params: Array<Value> = [vint(userId), vint(Int64(limit))]
        let sql = """
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
            LIMIT $2
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<ArchiveData>(sql, params, { row => mapArchivesWithTagsRow(row) })
                    for (row in rows) {
                        result.add(row)
                    }
                } catch (e: Exception) {
                    getLogger("user_stats_dao").error("获取最近收藏档案失败", ("error", e.message))
                }
            case None =>
                getLogger("user_stats_dao").error("无法连接到数据库")
        }
        return result.toArray()
    }

    /**
     * 将 archive_metadata_search 行（含 tags、last_read_time、progress）映射为 ArchiveData。
     * 列顺序需与 getRecentReadArchives/getRecentFavoriteArchives 的 SELECT 一致。
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
}