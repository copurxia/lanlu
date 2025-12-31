package lrr4cj.dao

import std.database.sql.*
import stdx.log.*
import std.collection.*
import std.time.*
import lrr4cj.config.*
import lrr4cj.utils.*

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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    // 使用 UPSERT 语法（INSERT ... ON CONFLICT）
                    let stmt = conn.prepareStatement("""
                        INSERT INTO user_archive_status (user_id, archive_id, is_new, updated_at)
                        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                        ON CONFLICT (user_id, archive_id)
                        DO UPDATE SET is_new = true, updated_at = CURRENT_TIMESTAMP
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, archiveId)
                        stmt.set(2, true)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("设置isNew标记失败", ("error", e.message))
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
     * 清除新状态/标记为已读（针对特定用户）
     */
    public static func clearIsNew(userId: Int64, archiveId: Int64): Bool {
        let logger = getLogger("user_archive_status_dao")
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    // 使用 UPSERT 语法
                    let stmt = conn.prepareStatement("""
                        INSERT INTO user_archive_status (user_id, archive_id, is_new, updated_at)
                        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                        ON CONFLICT (user_id, archive_id)
                        DO UPDATE SET is_new = false, updated_at = CURRENT_TIMESTAMP
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, archiveId)
                        stmt.set(2, false)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("清除isNew标记失败", ("error", e.message))
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
     * 更新用户阅读进度并自动标记为已读
     * @param userId 用户ID
     * @param archiveId 归档ID
     * @param progress 阅读页数/进度值
     * @return 更新是否成功
     */
    public static func updateProgress(userId: Int64, archiveId: Int64, progress: Int32): Bool {
        let logger = getLogger("user_archive_status_dao")
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    // 使用 UPSERT 语法，同时更新 progress 和 is_new
                    let stmt = conn.prepareStatement("""
                        INSERT INTO user_archive_status (user_id, archive_id, is_new, progress, updated_at)
                        VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
                        ON CONFLICT (user_id, archive_id)
                        DO UPDATE SET
                            is_new = false,
                            progress = ?,
                            updated_at = CURRENT_TIMESTAMP
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, archiveId)
                        stmt.set(2, false)  // is_new = false，自动标记为已读
                        stmt.set(3, progress)
                        stmt.set(4, progress)  // 第二个 ? 用于 ON CONFLICT
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("更新阅读进度失败", ("error", e.message))
                    return false
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) { /* ignore */ }
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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, user_id, archive_id, is_new, progress, created_at, updated_at
                        FROM user_archive_status
                        WHERE user_id = ? AND archive_id = ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, archiveId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let row = UserArchiveStatusRow()
                                row.id = rs.getOrNull<Int64>(0) ?? 0
                                row.userId = rs.getOrNull<Int64>(1) ?? 0
                                row.archiveId = rs.getOrNull<Int64>(2) ?? 0
                                row.isNew = rs.getOrNull<Bool>(3) ?? true
                                row.progress = rs.getOrNull<Int32>(4) ?? 0
                                row.createdAt = rs.getOrNull<String>(5) ?? ""
                                row.updatedAt = rs.getOrNull<String>(6) ?? ""
                                return Some(row)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return None
                } catch (_: Exception) {
                    return None
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT COALESCE(CAST(EXTRACT(EPOCH FROM updated_at) AS BIGINT), 0)
                        FROM user_archive_status
                        WHERE user_id = ? AND archive_id = ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, archiveId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<Int64>(0) ?? 0
                            }
                            return 0
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return 0
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
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
                        SELECT archive_id, is_new, progress
                        FROM user_archive_status
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
                                let isNew = rs.getOrNull<Bool>(1) ?? true
                                result[archiveId] = isNew
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }

                    // 对于没有记录的归档，默认为新
                    for (archiveId in archiveIds) {
                        if (!result.contains(archiveId)) {
                            result[archiveId] = true
                        }
                    }
                } catch (_: Exception) {
                    // 出错时，所有归档默认为新
                    for (archiveId in archiveIds) {
                        result[archiveId] = true
                    }
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                // 无法连接时，所有归档默认为新
                for (archiveId in archiveIds) {
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
                        SELECT archive_id, progress, COALESCE(CAST(EXTRACT(EPOCH FROM updated_at) AS BIGINT), 0) as unix_timestamp
                        FROM user_archive_status
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
                                let progress = rs.getOrNull<Int32>(1) ?? 0
                                let timestamp = rs.getOrNull<Int64>(2) ?? 0

                                progressMap[archiveId] = progress
                                lastReadTimeMap[archiveId] = timestamp
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }

                    // 对于没有记录的归档，设置默认值
                    for (archiveId in archiveIds) {
                        if (!progressMap.contains(archiveId)) {
                            progressMap[archiveId] = 0
                        }
                        if (!lastReadTimeMap.contains(archiveId)) {
                            lastReadTimeMap[archiveId] = 0
                        }
                    }
                } catch (_: Exception) {
                    // 出错时，设置默认值
                    for (archiveId in archiveIds) {
                        progressMap[archiveId] = 0
                        lastReadTimeMap[archiveId] = 0
                    }
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                // 无法连接时，设置默认值
                for (archiveId in archiveIds) {
                    progressMap[archiveId] = 0
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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("DELETE FROM user_archive_status WHERE user_id = ?")
                    try {
                        stmt.set(0, userId)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("删除用户归档状态失败", ("error", e.message))
                    return false
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * 删除特定归档的所有用户状态记录
     */
    public static func deleteByArchiveId(archiveId: Int64): Bool {
        let logger = getLogger("user_archive_status_dao")
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("DELETE FROM user_archive_status WHERE archive_id = ?")
                    try {
                        stmt.set(0, archiveId)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("删除归档状态失败", ("error", e.message))
                    return false
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * 获取用户已读的档案列表（带分页）
     * 返回 is_new = false 的档案详情
     */
    public static func getUserReadArchives(userId: Int64, start: Int32, count: Int32): (Array<ArchiveData>, Int64) {
        let result = ArrayList<ArchiveData>()
        var totalCount: Int64 = 0
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    // 先获取总数
                    let countStmt = conn.prepareStatement("""
                        SELECT COUNT(*) FROM user_archive_status
                        WHERE user_id = ? AND is_new = false
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
                               awt.pagecount, uas.updated_at as last_read_time,
                               COALESCE(uas.progress, 0) as progress, awt.tags
                        FROM archives_with_tags awt
                        INNER JOIN archives a ON awt.arcid = a.arcid
                        INNER JOIN user_archive_status uas ON a.id = uas.archive_id
                        WHERE uas.user_id = ? AND uas.is_new = false
                        ORDER BY uas.updated_at DESC
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
                    getLogger("user_archive_status_dao").error("获取用户已读档案失败", ("error", e.message))
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                getLogger("user_archive_status_dao").error("无法连接到数据库")
        }
        return (result.toArray(), totalCount)
    }
}
