package lrr4cj.dao

import std.database.sql.*
import lrr4cj.config.*
import std.collection.*
import stdx.log.*
import std.time.*
import lrr4cj.utils.*

/**
 * Tankoubon数据结构
 * 为了避免循环依赖，这个数据结构独立于 Tankoubon 模型类
 */
public class TankoubonData {
    public var id: Int64 = 0
    public var tankoubon_id: String = ""
    public var name: String = ""
    public var summary: String = ""
    public var tags: String = ""
    public var created_at: String = ""
    public var updated_at: String = ""
    public var archives: Array<String> = Array<String>()  // Array of archive arcids
}

/**
 * Tankoubon聚合数据结构（用于搜索结果）
 */
public class TankoubonAggregatedData {
    public var tankoubon_id: String = ""
    public var name: String = ""
    public var summary: String = ""
    public var tags: String = ""  // 合并的标签：tankoubon tags + 所有 archive tags
    public var pagecount: Int32 = 0  // 所有归档的页数总和
    public var progress: Int32 = 0  // 所有归档的平均进度
    public var last_read_time: String = ""  // 最新的阅读时间
    public var isnew: Bool = true  // 如果任何归档是新的，则为true
    public var archive_count: Int32 = 0  // 归档数量
}

/**
 * Tankoubon数据访问对象 (DAO)
 * 负责处理所有与Tankoubon相关的数据库操作
 */
public class TankoubonDao {

    /**
     * 获取所有Tankoubons
     */
    public static func getAllTankoubons(): Array<TankoubonData> {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                var tankoubons: ArrayList<TankoubonData> = ArrayList<TankoubonData>()
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, tankoubon_id, name, summary, tags, created_at, updated_at FROM tankoubons ORDER BY id")
                    try {
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let tankoubon = TankoubonData()
                                tankoubon.id = rs.getOrNull<Int64>(0) ?? 0
                                tankoubon.tankoubon_id = rs.getOrNull<String>(1) ?? ""
                                tankoubon.name = rs.getOrNull<String>(2) ?? ""
                                tankoubon.summary = rs.getOrNull<String>(3) ?? ""
                                tankoubon.tags = rs.getOrNull<String>(4) ?? ""
                                tankoubon.created_at = rs.getOrNull<String>(5) ?? ""
                                tankoubon.updated_at = rs.getOrNull<String>(6) ?? ""
                                tankoubon.archives = getArchivesInTankoubon(tankoubon.tankoubon_id)
                                tankoubons.add(tankoubon)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return tankoubons.toArray()
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("查询Tankoubon失败", ("error", e.message))
                    return Array<TankoubonData>()
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("tankoubon_dao").error("无法连接到数据库")
                return Array<TankoubonData>()
        }
    }

    /**
     * 根据tankoubon_id获取Tankoubon
     */
    public static func getTankoubonById(tankoubonId: String): Option<TankoubonData> {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, tankoubon_id, name, summary, tags, created_at, updated_at FROM tankoubons WHERE tankoubon_id = ?")
                    try {
                        stmt.set(0, tankoubonId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let tankoubon = TankoubonData()
                                tankoubon.id = rs.getOrNull<Int64>(0) ?? 0
                                tankoubon.tankoubon_id = rs.getOrNull<String>(1) ?? ""
                                tankoubon.name = rs.getOrNull<String>(2) ?? ""
                                tankoubon.summary = rs.getOrNull<String>(3) ?? ""
                                tankoubon.tags = rs.getOrNull<String>(4) ?? ""
                                tankoubon.created_at = rs.getOrNull<String>(5) ?? ""
                                tankoubon.updated_at = rs.getOrNull<String>(6) ?? ""
                                tankoubon.archives = getArchivesInTankoubon(tankoubonId)
                                return Some(tankoubon)
                            }
                            return None
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("查询Tankoubon失败", ("tankoubonId", tankoubonId), ("error", e.message))
                    return None
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("tankoubon_dao").error("无法连接到数据库")
                return None
        }
    }

    /**
     * 获取Tankoubon的档案数量和总页数
     */
    public static func getTankoubonArchiveStats(tankoubonId: String): (Int32, Int32) {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT COUNT(a.id) as archive_count, COALESCE(SUM(a.pagecount), 0) as total_pages
                        FROM tankoubon_archives ta
                        JOIN tankoubons t ON t.id = ta.tankoubon_id
                        JOIN archives a ON a.id = ta.archive_id
                        WHERE t.tankoubon_id = ?
                        GROUP BY t.id
                    """)
                    try {
                        stmt.set(0, tankoubonId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let archiveCount = rs.getOrNull<Int32>(0) ?? 0
                                let totalPages = rs.getOrNull<Int32>(1) ?? 0
                                return (archiveCount, totalPages)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("获取Tankoubon档案统计失败", ("tankoubonId", tankoubonId), ("error", e.message))
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("tankoubon_dao").error("无法连接到数据库")
        }
        return (0, 0)
    }

    /**
     * 创建新的Tankoubon
     * 返回生成的tankoubon_id
     */
    public static func createTankoubon(name: String): String {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // 生成tankoubon_id: TANK_ + 时间戳
                    let timestamp = DateTime.now().toUnixTimeStamp().toSeconds().toString()
                    let tankoubonId = "TANK_${timestamp}"

                    let stmt = conn.prepareStatement(
                        "INSERT INTO tankoubons (tankoubon_id, name, summary, tags) VALUES (?, ?, '', '')")
                    try {
                        stmt.set(0, tankoubonId)
                        stmt.set(1, name)
                        stmt.update()
                        getLogger("tankoubon_dao").info("创建Tankoubon成功", ("tankoubonId", tankoubonId), ("name", name))
                        return tankoubonId
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("创建Tankoubon失败", ("name", name), ("error", e.message))
                    return ""
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("tankoubon_dao").error("无法连接到数据库")
                return ""
        }
    }

    /**
     * 更新Tankoubon元数据
     */
    public static func updateTankoubon(tankoubonId: String, name: String, summary: String, tags: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement(
                        "UPDATE tankoubons SET name = ?, summary = ?, tags = ?, updated_at = CURRENT_TIMESTAMP WHERE tankoubon_id = ?")
                    try {
                        stmt.set(0, name)
                        stmt.set(1, summary)
                        stmt.set(2, tags)
                        stmt.set(3, tankoubonId)
                        stmt.update()
                        getLogger("tankoubon_dao").info("更新Tankoubon成功", ("tankoubonId", tankoubonId))
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("更新Tankoubon失败", ("tankoubonId", tankoubonId), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("tankoubon_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 删除Tankoubon
     */
    public static func deleteTankoubon(tankoubonId: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("DELETE FROM tankoubons WHERE tankoubon_id = ?")
                    try {
                        stmt.set(0, tankoubonId)
                        stmt.update()
                        getLogger("tankoubon_dao").info("删除Tankoubon成功", ("tankoubonId", tankoubonId))
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("删除Tankoubon失败", ("tankoubonId", tankoubonId), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("tankoubon_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 添加归档到Tankoubon
     */
    public static func addArchiveToTankoubon(tankoubonId: String, archiveArcid: String, sortOrder: Int32): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // 首先获取tankoubon的内部ID和archive的内部ID
                    let tankoubonInternalId = getTankoubonInternalId(conn, tankoubonId)
                    let archiveInternalId = getArchiveInternalId(conn, archiveArcid)

                    if (tankoubonInternalId == 0 || archiveInternalId == 0) {
                        getLogger("tankoubon_dao").error("Tankoubon或Archive不存在",
                            ("tankoubonId", tankoubonId), ("archiveArcid", archiveArcid))
                        return false
                    }

                    let stmt = conn.prepareStatement(
                        "INSERT INTO tankoubon_archives (tankoubon_id, archive_id, sort_order) VALUES (?, ?, ?) ON CONFLICT (tankoubon_id, archive_id) DO UPDATE SET sort_order = EXCLUDED.sort_order")
                    try {
                        stmt.set(0, tankoubonInternalId)
                        stmt.set(1, archiveInternalId)
                        stmt.set(2, sortOrder)
                        stmt.update()
                        getLogger("tankoubon_dao").info("添加归档到Tankoubon成功",
                            ("tankoubonId", tankoubonId), ("archiveArcid", archiveArcid))
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("添加归档到Tankoubon失败",
                        ("tankoubonId", tankoubonId), ("archiveArcid", archiveArcid), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("tankoubon_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 从Tankoubon移除归档
     */
    public static func removeArchiveFromTankoubon(tankoubonId: String, archiveArcid: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // 获取内部ID
                    let tankoubonInternalId = getTankoubonInternalId(conn, tankoubonId)
                    let archiveInternalId = getArchiveInternalId(conn, archiveArcid)

                    if (tankoubonInternalId == 0 || archiveInternalId == 0) {
                        return false
                    }

                    let stmt = conn.prepareStatement(
                        "DELETE FROM tankoubon_archives WHERE tankoubon_id = ? AND archive_id = ?")
                    try {
                        stmt.set(0, tankoubonInternalId)
                        stmt.set(1, archiveInternalId)
                        stmt.update()
                        getLogger("tankoubon_dao").info("从Tankoubon移除归档成功",
                            ("tankoubonId", tankoubonId), ("archiveArcid", archiveArcid))
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("从Tankoubon移除归档失败",
                        ("tankoubonId", tankoubonId), ("archiveArcid", archiveArcid), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("tankoubon_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 获取Tankoubon中的所有归档arcids
     */
    public static func getArchivesInTankoubon(tankoubonId: String): Array<String> {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                var arcids: ArrayList<String> = ArrayList<String>()
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT a.arcid
                        FROM tankoubon_archives ta
                        JOIN tankoubons t ON t.id = ta.tankoubon_id
                        JOIN archives a ON a.id = ta.archive_id
                        WHERE t.tankoubon_id = ?
                        ORDER BY ta.sort_order, ta.id
                    """)
                    try {
                        stmt.set(0, tankoubonId)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let arcid = rs.getOrNull<String>(0) ?? ""
                                if (arcid != "") {
                                    arcids.add(arcid)
                                }
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return arcids.toArray()
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("获取Tankoubon中的归档失败",
                        ("tankoubonId", tankoubonId), ("error", e.message))
                    return Array<String>()
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("tankoubon_dao").error("无法连接到数据库")
                return Array<String>()
        }
    }

    /**
     * 检查归档是否在某个Tankoubon中
     * 返回tankoubon_id，如果不在任何Tankoubon中则返回None
     */
    public static func getTankoubonForArchive(archiveArcid: String): Option<String> {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT t.tankoubon_id
                        FROM tankoubon_archives ta
                        JOIN tankoubons t ON t.id = ta.tankoubon_id
                        JOIN archives a ON a.id = ta.archive_id
                        WHERE a.arcid = ?
                        LIMIT 1
                    """)
                    try {
                        stmt.set(0, archiveArcid)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let tankoubonId = rs.getOrNull<String>(0) ?? ""
                                if (tankoubonId != "") {
                                    return Some(tankoubonId)
                                }
                            }
                            return None
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("检查归档所属Tankoubon失败",
                        ("archiveArcid", archiveArcid), ("error", e.message))
                    return None
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("tankoubon_dao").error("无法连接到数据库")
                return None
        }
    }

    /**
     * 获取Tankoubon的聚合元数据（用于搜索结果）
     */
    public static func getAggregatedMetadata(tankoubonId: String, userId: Int64): Option<TankoubonAggregatedData> {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT
                            t.tankoubon_id,
                            t.name,
                            t.summary,
                            t.tags,
                            COALESCE(SUM(a.pagecount), 0)::INT as total_pagecount,
                            COUNT(a.id)::INT as archive_count,
                            COALESCE(MAX(uas.updated_at)::TEXT, '') as last_read_time,
                            COALESCE(AVG(uas.progress), 0)::INT as avg_progress,
                            COALESCE(BOOL_OR(uas.is_new), true) as has_new_archives
                        FROM tankoubons t
                        JOIN tankoubon_archives ta ON ta.tankoubon_id = t.id
                        JOIN archives a ON a.id = ta.archive_id
                        LEFT JOIN user_archive_status uas ON uas.archive_id = a.id AND uas.user_id = ?
                        WHERE t.tankoubon_id = ?
                        GROUP BY t.id, t.tankoubon_id, t.name, t.summary, t.tags
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, tankoubonId)
                        var dataOpt: Option<TankoubonAggregatedData> = None
                        var tankoubonTags = ""

                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let data = TankoubonAggregatedData()
                                data.tankoubon_id = rs.getOrNull<String>(0) ?? ""
                                data.name = rs.getOrNull<String>(1) ?? ""
                                data.summary = rs.getOrNull<String>(2) ?? ""
                                tankoubonTags = rs.getOrNull<String>(3) ?? ""
                                data.pagecount = rs.getOrNull<Int32>(4) ?? 0
                                data.archive_count = rs.getOrNull<Int32>(5) ?? 0
                                data.last_read_time = rs.getOrNull<String>(6) ?? ""
                                data.progress = rs.getOrNull<Int32>(7) ?? 0
                                data.isnew = rs.getOrNull<Bool>(8) ?? true
                                dataOpt = Some(data)
                            }
                        } finally {
                            rs.close()
                        }

                        // 注意：必须先关闭 ResultSet，再在同一连接上执行后续查询，否则会触发 conn busy
                        match (dataOpt) {
                            case Some(data) =>
                                let archiveTags = getArchiveTagsForTankoubon(conn, tankoubonId)
                                data.tags = mergeTags(tankoubonTags, archiveTags)
                                return Some(data)
                            case None => return None
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("获取Tankoubon聚合元数据失败",
                        ("tankoubonId", tankoubonId), ("error", e.message))
                    return None
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("tankoubon_dao").error("无法连接到数据库")
                return None
        }
    }

    /**
     * 获取Tankoubon内部ID（从tankoubon_id）
     */
    private static func getTankoubonInternalId(conn: Connection, tankoubonId: String): Int64 {
        try {
            let stmt = conn.prepareStatement("SELECT id FROM tankoubons WHERE tankoubon_id = ?")
            try {
                stmt.set(0, tankoubonId)
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
        } catch (_: Exception) {}
        return 0
    }

    /**
     * 获取Archive内部ID（从arcid）
     */
    private static func getArchiveInternalId(conn: Connection, arcid: String): Int64 {
        try {
            let stmt = conn.prepareStatement("SELECT id FROM archives WHERE arcid = ?")
            try {
                stmt.set(0, arcid)
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
        } catch (_: Exception) {}
        return 0
    }

    /**
     * 获取Tankoubon中所有归档的标签
     */
    private static func getArchiveTagsForTankoubon(conn: Connection, tankoubonId: String): String {
        try {
            let stmt = conn.prepareStatement("""
                SELECT DISTINCT awt.tags
                FROM tankoubon_archives ta
                JOIN tankoubons t ON t.id = ta.tankoubon_id
                JOIN archives a ON a.id = ta.archive_id
                JOIN archives_with_tags awt ON awt.arcid = a.arcid
                WHERE t.tankoubon_id = ? AND awt.tags != ''
            """)
            try {
                stmt.set(0, tankoubonId)
                let rs = stmt.query()
                try {
                    var allTags: ArrayList<String> = ArrayList<String>()
                    while (rs.next()) {
                        let tags = rs.getOrNull<String>(0) ?? ""
                        if (tags != "") {
                            allTags.add(tags)
                        }
                    }
                    // 合并所有标签字符串
                    var combined = ""
                    for (i in 0..allTags.size) {
                        if (i > 0) {
                            combined += ","
                        }
                        combined += allTags[i]
                    }
                    return combined
                } finally {
                    rs.close()
                }
            } finally {
                stmt.close()
            }
        } catch (_: Exception) {}
        return ""
    }

    /**
     * 合并并去重标签
     */
    private static func mergeTags(tankoubonTags: String, archiveTags: String): String {
        var tagSet: HashMap<String, Bool> = HashMap<String, Bool>()

        // 添加tankoubon标签
        if (tankoubonTags != "") {
            let tags = tankoubonTags.split(",")
            for (tag in tags) {
                let trimmed = tag.trimAscii()
                if (trimmed != "") {
                    tagSet[trimmed] = true
                }
            }
        }

        // 添加archive标签
        if (archiveTags != "") {
            let tags = archiveTags.split(",")
            for (tag in tags) {
                let trimmed = tag.trimAscii()
                if (trimmed != "") {
                    tagSet[trimmed] = true
                }
            }
        }

        // 转换回字符串
        var result = ""
        var isFirst = true
        for ((tag, _) in tagSet) {
            if (!isFirst) {
                result += ","
            }
            result += tag
            isFirst = false
        }

        return result
    }
}
