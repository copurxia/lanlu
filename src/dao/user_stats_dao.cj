package lanlu.dao

import std.database.sql.*
import std.collection.*
import lanlu.config.*
import lanlu.utils.*
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT COUNT(*) FROM user_archive_status
                        WHERE user_id = ? AND is_new = false
                    """)
                    try {
                        stmt.set(0, userId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<Int64>(0) ?? 0
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return 0
                } catch (_: Exception) {
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return 0
        }
    }

    /**
     * 获取全局总阅读页数（所有用户）
     * 计算所有用户的 progress 总和
     */
    public static func getGlobalTotalPagesRead(): Int64 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT COALESCE(SUM(progress), 0) as total_pages
                        FROM user_archive_status
                        WHERE is_new = false
                    """)
                    try {
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<Int64>(0) ?? 0
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return 0
                } catch (e: Exception) {
                    getLogger("user_stats_dao").error("获取全局总阅读页数失败", ("error", e.message))
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return 0
        }
    }

    /**
     * 获取用户总阅读页数
     * 计算用户已读档案的 progress 总和（从 user_archive_status.progress 获取）
     */
    public static func getTotalPagesRead(userId: Int64): Int64 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT COALESCE(SUM(uas.progress), 0) as total_pages
                        FROM user_archive_status uas
                        WHERE uas.user_id = ? AND uas.is_new = false
                    """)
                    try {
                        stmt.set(0, userId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<Int64>(0) ?? 0
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return 0
                } catch (e: Exception) {
                    getLogger("user_stats_dao").error("获取总阅读页数失败", ("error", e.message))
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) { /* ignore */ }
                }
            case None => return 0
        }
    }

    /**
     * 获取档案总数
     */
    public static func getTotalArchives(): Int64 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("SELECT COUNT(*) FROM archives")
                    try {
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<Int64>(0) ?? 0
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return 0
                } catch (_: Exception) {
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT DATE(updated_at) as date, COUNT(*) as count
                        FROM user_archive_status
                        WHERE user_id = ? AND is_new = false
                          AND updated_at >= CURRENT_DATE - (? || ' days')::INTERVAL
                        GROUP BY DATE(updated_at)
                        ORDER BY date ASC
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, days)
                        let rs = stmt.query()
                        try {
                            let trendMap = HashMap<String, Int64>()
                            // 构建日期到数量的映射
                            while (rs.next()) {
                                let date = rs.getOrNull<String>(0) ?? ""
                                let count = rs.getOrNull<Int64>(1) ?? 0
                                trendMap[date] = count
                            }

                            // 生成所有日期的数据，包括没有阅读记录的日期
                            for (offset in 0..=days-1) {
                                let item = ReadingTrendItem()
                                // 计算日期：从今天往前推 offset 天
                                let dateStmt = conn.prepareStatement("SELECT (CURRENT_DATE - (? || ' days')::INTERVAL)::DATE")
                                try {
                                    dateStmt.set(0, offset)
                                    let dateRs = dateStmt.query()
                                    try {
                                        if (dateRs.next()) {
                                            item.date = dateRs.getOrNull<String>(0) ?? ""
                                        }
                                    } finally {
                                        dateRs.close()
                                    }
                                } finally {
                                    dateStmt.close()
                                }
                                // 如果数据库中有该日期的数据则使用，否则为0
                                item.count = trendMap.get(item.date) ?? 0
                                result.add(item)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("user_stats_dao").error("获取阅读趋势失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT awt.arcid, awt.filename, awt.title, awt.summary, awt.thumbhash,
                               awt.created_at, awt.updated_at, awt.relative_path, awt.file_size,
                               awt.pagecount, uas.updated_at as last_read_time,
                               COALESCE(uas.progress, 0) as progress, awt.tags
                        FROM archives_with_tags awt
                        INNER JOIN archives a ON awt.arcid = a.arcid
                        INNER JOIN user_archive_status uas ON a.id = uas.archive_id
                        WHERE uas.user_id = ? AND uas.is_new = false
                        ORDER BY uas.updated_at DESC
                        LIMIT ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, limit)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let archive = ArchiveDataMappers.fromArchivesWithTagsRow(rs)
                                result.add(archive)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("user_stats_dao").error("获取最近阅读档案失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT awt.arcid, awt.filename, awt.title, awt.summary, awt.thumbhash,
                               awt.created_at, awt.updated_at, awt.relative_path, awt.file_size,
                               awt.pagecount,
                               COALESCE(uas.updated_at, '1970-01-01 00:00:00') as last_read_time,
                               COALESCE(uas.progress, 0) as progress, awt.tags
                        FROM archives_with_tags awt
                        INNER JOIN archives a ON awt.arcid = a.arcid
                        INNER JOIN user_favorites uf ON a.id = uf.archive_id
                        LEFT JOIN user_archive_status uas ON a.id = uas.archive_id AND uas.user_id = uf.user_id
                        WHERE uf.user_id = ?
                        ORDER BY uf.created_at DESC
                        LIMIT ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, limit)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let archive = ArchiveDataMappers.fromArchivesWithTagsRow(rs)
                                result.add(archive)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("user_stats_dao").error("获取最近收藏档案失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                getLogger("user_stats_dao").error("无法连接到数据库")
        }
        return result.toArray()
    }
}
