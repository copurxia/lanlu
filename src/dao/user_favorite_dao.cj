package lrr4cj.dao

import std.database.sql.*
import std.collection.*
import lrr4cj.config.*
import lrr4cj.utils.*
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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    // 使用 INSERT OR IGNORE 避免重复收藏
                    let stmt = conn.prepareStatement("""
                        INSERT INTO user_favorites (user_id, archive_id, created_at)
                        VALUES (?, ?, CURRENT_TIMESTAMP)
                        ON CONFLICT (user_id, archive_id) DO NOTHING
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, archiveId)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("添加收藏失败", ("error", e.message))
                    return false
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("""
                        DELETE FROM user_favorites
                        WHERE user_id = ? AND archive_id = ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, archiveId)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("取消收藏失败", ("error", e.message))
                    return false
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT COUNT(*) FROM user_favorites
                        WHERE user_id = ? AND archive_id = ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, archiveId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let count = rs.getOrNull<Int64>(0) ?? 0
                                return count > 0
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return false
                } catch (_: Exception) {
                    return false
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * 获取用户的所有收藏（返回 archive_id 列表）
     */
    public static func getUserFavorites(userId: Int64): Array<Int64> {
        let result = ArrayList<Int64>()
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT archive_id FROM user_favorites
                        WHERE user_id = ?
                        ORDER BY created_at DESC
                    """)
                    try {
                        stmt.set(0, userId)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let archiveId = rs.getOrNull<Int64>(0) ?? 0
                                if (archiveId > 0) {
                                    result.add(archiveId)
                                }
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("user_favorite_dao").error("获取用户收藏失败", ("error", e.message))
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT a.arcid FROM user_favorites uf
                        JOIN archives a ON uf.archive_id = a.id
                        WHERE uf.user_id = ?
                        ORDER BY uf.created_at DESC
                    """)
                    try {
                        stmt.set(0, userId)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let arcid = rs.getOrNull<String>(0) ?? ""
                                if (arcid.size > 0) {
                                    result.add(arcid)
                                }
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("user_favorite_dao").error("获取用户收藏arcid失败", ("error", e.message))
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
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

        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    // 构建 IN 子句的占位符
                    var inClause = ""
                    for (i in 0..archiveIds.size) {
                        if (i > 0) {
                            inClause += ","
                        }
                        inClause += "?"
                    }

                    let sql = """
                        SELECT archive_id FROM user_favorites
                        WHERE user_id = ? AND archive_id IN (${inClause})
                    """

                    let stmt = conn.prepareStatement(sql)
                    try {
                        stmt.set(0, userId)
                        var idx = 1
                        for (archiveId in archiveIds) {
                            stmt.set(idx, archiveId)
                            idx = idx + 1
                        }

                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let archiveId = rs.getOrNull<Int64>(0) ?? 0
                                result[archiveId] = true
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }

                    // 对于没有收藏的档案，设置为 false
                    for (archiveId in archiveIds) {
                        if (!result.contains(archiveId)) {
                            result[archiveId] = false
                        }
                    }
                } catch (_: Exception) {
                    // 出错时，所有档案默认为未收藏
                    for (archiveId in archiveIds) {
                        result[archiveId] = false
                    }
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                // 无法连接时，所有档案默认为未收藏
                for (archiveId in archiveIds) {
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

        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    // 构建 IN 子句的占位符
                    var inClause = ""
                    for (i in 0..archiveIds.size) {
                        if (i > 0) {
                            inClause += ","
                        }
                        inClause += "?"
                    }

                    let sql = """
                        SELECT archive_id, COALESCE(CAST(EXTRACT(EPOCH FROM created_at) AS BIGINT), 0) as unix_timestamp FROM user_favorites
                        WHERE user_id = ? AND archive_id IN (${inClause})
                    """

                    let stmt = conn.prepareStatement(sql)
                    try {
                        stmt.set(0, userId)
                        var idx = 1
                        for (archiveId in archiveIds) {
                            stmt.set(idx, archiveId)
                            idx = idx + 1
                        }

                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let archiveId = rs.getOrNull<Int64>(0) ?? 0
                                let unixTimestamp = rs.getOrNull<Int64>(1) ?? 0
                                if (archiveId > 0) {
                                    result[archiveId] = unixTimestamp
                                }
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    // 出错时返回空结果
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None => ()
        }

        return result
    }

    /**
     * 删除用户的所有收藏记录
     */
    public static func deleteByUserId(userId: Int64): Bool {
        let logger = getLogger("user_favorite_dao")
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("DELETE FROM user_favorites WHERE user_id = ?")
                    try {
                        stmt.set(0, userId)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("删除用户收藏失败", ("error", e.message))
                    return false
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * 删除特定档案的所有收藏记录
     */
    public static func deleteByArchiveId(archiveId: Int64): Bool {
        let logger = getLogger("user_favorite_dao")
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("DELETE FROM user_favorites WHERE archive_id = ?")
                    try {
                        stmt.set(0, archiveId)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("删除档案收藏失败", ("error", e.message))
                    return false
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * 获取收藏数量
     */
    public static func getFavoriteCount(userId: Int64): Int64 {
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT COUNT(*) FROM user_favorites WHERE user_id = ?
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
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None => return 0
        }
    }

    /**
     * 获取用户收藏的档案详情列表（带分页）
     * 返回完整的档案信息，包括标签
     */
    public static func getUserFavoriteArchives(userId: Int64, start: Int32, count: Int32): (Array<ArchiveData>, Int64) {
        let result = ArrayList<ArchiveData>()
        var totalCount: Int64 = 0
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    // 先获取总数
                    let countStmt = conn.prepareStatement("""
                        SELECT COUNT(*) FROM user_favorites WHERE user_id = ?
                    """)
                    try {
                        countStmt.set(0, userId)
                        let countRs = countStmt.query()
                        try {
                            if (countRs.next()) {
                                totalCount = countRs.getOrNull<Int64>(0) ?? 0
                            }
                        } finally {
                            countRs.close()
                        }
                    } finally {
                        countStmt.close()
                    }

                    // 获取分页数据，使用标准 JOIN 获取用户特定数据
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
                        LIMIT ? OFFSET ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, count)
                        stmt.set(2, start)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let archive = ArchiveData()
                                archive.id = rs.getOrNull<String>(0) ?? ""
                                archive.filename = rs.getOrNull<String>(1) ?? ""
                                archive.title = rs.getOrNull<String>(2) ?? ""
                                archive.summary = rs.getOrNull<String>(3) ?? ""
                                archive.thumbhash = rs.getOrNull<String>(4) ?? ""
                                archive.created_at = rs.getOrNull<String>(5) ?? ""
                                archive.updated_at = rs.getOrNull<String>(6) ?? ""
                                archive.relative_path = rs.getOrNull<String>(7) ?? ""
                                archive.file_size = rs.getOrNull<Int64>(8) ?? 0
                                archive.pagecount = rs.getOrNull<Int32>(9) ?? 0
                                archive.last_read_time = rs.getOrNull<String>(10) ?? ""
                                archive.progress = rs.getOrNull<Int32>(11) ?? 0
                                archive.tags = rs.getOrNull<String>(12) ?? ""
                                result.add(archive)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("user_favorite_dao").error("获取用户收藏档案详情失败", ("error", e.message), ("stack", e.toString()))
                    getLogger("user_favorite_dao").error("查询参数", ("userId", userId.toString()), ("start", start.toString()), ("count", count.toString()))
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                getLogger("user_favorite_dao").error("无法连接到数据库")
        }
        return (result.toArray(), totalCount)
    }
}
