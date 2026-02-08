package lanlu.dao

import std.database.sql.*
import lanlu.config.*
import std.collection.*
import stdx.log.*
import std.time.*
import lanlu.utils.*

/**
 * Tankoubon数据结构
 * 为了避免循环依赖，这个数据结构独立于 Tankoubon 模型类
 */
public class TankoubonData {
    public var id: Int64 = 0
    public var tankoubon_id: String = ""
    public var name: String = ""
    public var summary: String = ""
    public var cover_asset_id: Int64 = 0
    public var auto_created: Bool = false
    public var source_category_id: Int64 = 0
    public var source_relative_path: String = ""
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
    public var cover_asset_id: Int64 = 0
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                var tankoubons: ArrayList<TankoubonData> = ArrayList<TankoubonData>()
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, tankoubon_id, name, summary, COALESCE(cover_asset_id, 0), COALESCE(auto_created, false), COALESCE(source_category_id, 0), COALESCE(source_relative_path, ''), created_at, updated_at FROM tankoubons ORDER BY id")
                    try {
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let tankoubon = TankoubonData()
                                tankoubon.id = rs.getOrNull<Int64>(0) ?? 0
                                tankoubon.tankoubon_id = rs.getOrNull<String>(1) ?? ""
                                tankoubon.name = rs.getOrNull<String>(2) ?? ""
                                tankoubon.summary = rs.getOrNull<String>(3) ?? ""
                                tankoubon.cover_asset_id = rs.getOrNull<Int64>(4) ?? 0
                                tankoubon.auto_created = rs.getOrNull<Bool>(5) ?? false
                                tankoubon.source_category_id = rs.getOrNull<Int64>(6) ?? 0
                                tankoubon.source_relative_path = rs.getOrNull<String>(7) ?? ""
                                tankoubon.created_at = rs.getOrNull<String>(8) ?? ""
                                tankoubon.updated_at = rs.getOrNull<String>(9) ?? ""
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, tankoubon_id, name, summary, COALESCE(cover_asset_id, 0), COALESCE(auto_created, false), COALESCE(source_category_id, 0), COALESCE(source_relative_path, ''), created_at, updated_at FROM tankoubons WHERE tankoubon_id = ?")
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
                                tankoubon.cover_asset_id = rs.getOrNull<Int64>(4) ?? 0
                                tankoubon.auto_created = rs.getOrNull<Bool>(5) ?? false
                                tankoubon.source_category_id = rs.getOrNull<Int64>(6) ?? 0
                                tankoubon.source_relative_path = rs.getOrNull<String>(7) ?? ""
                                tankoubon.created_at = rs.getOrNull<String>(8) ?? ""
                                tankoubon.updated_at = rs.getOrNull<String>(9) ?? ""
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
        let connOpt = DatabaseConfig.getPooledConnection()
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    // 生成tankoubon_id: TANK_ + 时间戳（毫秒，避免并发冲突）
                    let timestamp = DateTime.now().toUnixTimeStamp().toMilliseconds().toString()
                    let tankoubonId = "TANK_${timestamp}"

                    let stmt = conn.prepareStatement(
                        "INSERT INTO tankoubons (tankoubon_id, name, summary) VALUES (?, ?, '')")
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
    public static func updateTankoubon(tankoubonId: String, name: String, summary: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement(
                        "UPDATE tankoubons SET name = ?, summary = ?, updated_at = CURRENT_TIMESTAMP WHERE tankoubon_id = ?")
                    try {
                        stmt.set(0, name)
                        stmt.set(1, summary)
                        stmt.set(2, tankoubonId)
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
        let connOpt = DatabaseConfig.getPooledConnection()
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
        let connOpt = DatabaseConfig.getPooledConnection()
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
        let connOpt = DatabaseConfig.getPooledConnection()
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
     * 添加归档到 Tankoubon（追加到末尾，不改变已有顺序）
     */
    public static func addArchiveToTankoubonAppend(tankoubonId: String, archiveArcid: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let tankInternalId = getTankoubonInternalId(conn, tankoubonId)
                    let archiveInternalId = getArchiveInternalId(conn, archiveArcid)
                    if (tankInternalId == 0 || archiveInternalId == 0) {
                        return false
                    }

                    // Compute next sort order.
                    var nextOrder: Int32 = 0
                    let maxStmt = conn.prepareStatement("SELECT COALESCE(MAX(sort_order), 0)::INT FROM tankoubon_archives WHERE tankoubon_id = ?")
                    try {
                        maxStmt.set(0, tankInternalId)
                        let rs = maxStmt.query()
                        try {
                            if (rs.next()) {
                                nextOrder = (rs.getOrNull<Int32>(0) ?? 0) + 1
                            } else {
                                nextOrder = 1
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        maxStmt.close()
                    }

                    let stmt = conn.prepareStatement(
                        "INSERT INTO tankoubon_archives (tankoubon_id, archive_id, sort_order) VALUES (?, ?, ?) ON CONFLICT (tankoubon_id, archive_id) DO NOTHING")
                    try {
                        stmt.set(0, tankInternalId)
                        stmt.set(1, archiveInternalId)
                        stmt.set(2, nextOrder)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("append archive to tank failed",
                        ("tankoubonId", tankoubonId), ("archiveArcid", archiveArcid), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * Get or create an auto-created Tankoubon for a directory source mapping.
     * Returns tankoubons.tankoubon_id.
     */
    public static func getOrCreateAutoTankoubon(categoryInternalId: Int64, sourceRelativePath: String, name: String): String {
        if (categoryInternalId <= 0) { return "" }
        let rel = sourceRelativePath.trimAscii()
        if (rel.size == 0) { return "" }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // Try to find existing.
                    let sel = conn.prepareStatement("""
                        SELECT tankoubon_id
                        FROM tankoubons
                        WHERE auto_created = true AND source_category_id = ? AND COALESCE(source_relative_path, '') = ?
                        LIMIT 1
                    """)
                    try {
                        sel.set(0, categoryInternalId)
                        sel.set(1, rel)
                        let rs = sel.query()
                        try {
                            if (rs.next()) {
                                let tid = rs.getOrNull<String>(0) ?? ""
                                if (tid.size > 0) { return tid }
                            }
                        } finally { rs.close() }
                    } finally { sel.close() }

                    // Create new.
                    let timestamp = DateTime.now().toUnixTimeStamp().toMilliseconds().toString()
                    let tid = "TANK_${timestamp}"

                    let ins = conn.prepareStatement("""
                        INSERT INTO tankoubons (tankoubon_id, name, summary, cover_asset_id, auto_created, source_category_id, source_relative_path)
                        VALUES (?, ?, '', 0, true, ?, ?)
                    """)
                    try {
                        ins.set(0, tid)
                        ins.set(1, name)
                        ins.set(2, categoryInternalId)
                        ins.set(3, rel)
                        ins.update()
                        return tid
                    } finally { ins.close() }
                } catch (e: Exception) {
                    // If concurrent creation raced, try select again.
                    getLogger("tankoubon_dao").warn("getOrCreateAutoTankoubon create failed, retrying select",
                        ("categoryInternalId", categoryInternalId.toString()), ("rel", rel), ("error", e.message))
                    try {
                        let stmt2 = conn.prepareStatement("""
                            SELECT tankoubon_id
                            FROM tankoubons
                            WHERE auto_created = true AND source_category_id = ? AND COALESCE(source_relative_path, '') = ?
                            LIMIT 1
                        """)
                        try {
                            stmt2.set(0, categoryInternalId)
                            stmt2.set(1, rel)
                            let rs2 = stmt2.query()
                            try {
                                if (rs2.next()) {
                                    return rs2.getOrNull<String>(0) ?? ""
                                }
                            } finally { rs2.close() }
                        } finally { stmt2.close() }
                    } catch (_: Exception) {}
                    return ""
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return ""
        }
    }

    /**
     * Update Tankoubon cover.
     */
    public static func updateTankoubonCover(tankoubonId: String, coverAssetId: Int64): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement(
                        "UPDATE tankoubons SET cover_asset_id = ?, updated_at = CURRENT_TIMESTAMP WHERE tankoubon_id = ?")
                    try {
                        stmt.set(0, coverAssetId)
                        stmt.set(1, tankoubonId)
                        stmt.update()
                        return true
                    } finally { stmt.close() }
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * Update Tankoubon tags (tankoubon_tags relation).
     */
    public static func updateTankoubonTags(tankoubonId: String, tagsString: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return false
            case Some(conn) =>
                try {
                    let tankInternalId = getTankoubonInternalId(conn, tankoubonId)
                    if (tankInternalId <= 0) { return false }

                    // Remove existing relations.
                    let del = conn.prepareStatement("DELETE FROM tankoubon_tags WHERE tankoubon_id = ?")
                    try {
                        del.set(0, tankInternalId)
                        del.update()
                    } finally { del.close() }

                    let trimmed = tagsString.trimAscii()
                    if (trimmed.size == 0) { return true }

                    let parts = trimmed.split(",")
                    for (p in parts) {
                        let t = p.trimAscii()
                        if (t.size == 0) { continue }
                        let (namespace, name) = TagDao.parseTagName(t)
                        if (name.trimAscii().size == 0) { continue }

                        // Upsert tag within the same connection to avoid extra pool usage.
                        var tagId: Int64 = 0
                        let tagStmt = conn.prepareStatement("""
                            INSERT INTO tags (namespace, name)
                            VALUES (?, ?)
                            ON CONFLICT (namespace, name) DO UPDATE SET updated_at = CURRENT_TIMESTAMP
                            RETURNING id
                        """)
                        try {
                            tagStmt.set(0, namespace)
                            tagStmt.set(1, name)
                            let rs = tagStmt.query()
                            try {
                                if (rs.next()) {
                                    tagId = rs.getOrNull<Int64>(0) ?? 0
                                }
                            } finally { rs.close() }
                        } finally { tagStmt.close() }
                        if (tagId <= 0) { continue }
                        let ins = conn.prepareStatement("""
                            INSERT INTO tankoubon_tags (tankoubon_id, tag_id) VALUES (?, ?) ON CONFLICT DO NOTHING
                        """)
                        try {
                            ins.set(0, tankInternalId)
                            ins.set(1, tagId)
                            ins.update()
                        } finally { ins.close() }
                    }
                    return true
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("updateTankoubonTags failed", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }

    /**
     * Get merged tags string for a Tankoubon (tankoubon tags + all archive tags).
     */
    public static func getMergedTagsForTankoubon(tankoubonId: String): String {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return ""
            case Some(conn) =>
                try {
                    let tankTags = getTankoubonTagsForTankoubon(conn, tankoubonId)
                    let archiveTags = getArchiveTagsForTankoubon(conn, tankoubonId)
                    return mergeTags(tankTags, archiveTags)
                } catch (_: Exception) {
                    return ""
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }

    public static func getTankoubonCoverAssetId(tankoubonId: String): Int64 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return 0
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("SELECT COALESCE(cover_asset_id, 0) FROM tankoubons WHERE tankoubon_id = ?")
                    try {
                        stmt.set(0, tankoubonId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<Int64>(0) ?? 0
                            }
                        } finally { rs.close() }
                    } finally { stmt.close() }
                    return 0
                } catch (_: Exception) {
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }

    /**
     * 获取Tankoubon中的所有归档arcids
     */
    public static func getArchivesInTankoubon(tankoubonId: String): Array<String> {
        let connOpt = DatabaseConfig.getPooledConnection()
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
        let connOpt = DatabaseConfig.getPooledConnection()
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
     * 获取归档所属的所有Tankoubon（返回tankoubon_id列表）
     */
    public static func getTankoubonsForArchive(archiveArcid: String): Array<String> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT t.tankoubon_id
                        FROM tankoubon_archives ta
                        JOIN tankoubons t ON t.id = ta.tankoubon_id
                        JOIN archives a ON a.id = ta.archive_id
                        WHERE a.arcid = ?
                        ORDER BY t.name, t.tankoubon_id
                    """)
                    try {
                        stmt.set(0, archiveArcid)
                        let rs = stmt.query()
                        try {
                            var list: ArrayList<String> = ArrayList<String>()
                            while (rs.next()) {
                                let tid = rs.getOrNull<String>(0) ?? ""
                                if (tid != "") {
                                    list.add(tid)
                                }
                            }
                            return list.toArray()
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("获取归档所属Tankoubon列表失败",
                        ("archiveArcid", archiveArcid), ("error", e.message))
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
     * 获取Tankoubon的聚合元数据（用于搜索结果）
     */
    public static func getAggregatedMetadata(tankoubonId: String, userId: Int64): Option<TankoubonAggregatedData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT
                            t.tankoubon_id,
                            t.name,
                            t.summary,
                            COALESCE(t.cover_asset_id, 0) as cover_asset_id,
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
                        GROUP BY t.id, t.tankoubon_id, t.name, t.summary, t.cover_asset_id
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, tankoubonId)
                        var dataOpt: Option<TankoubonAggregatedData> = None

                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let data = TankoubonAggregatedData()
                                data.tankoubon_id = rs.getOrNull<String>(0) ?? ""
                                data.name = rs.getOrNull<String>(1) ?? ""
                                data.summary = rs.getOrNull<String>(2) ?? ""
                                data.cover_asset_id = rs.getOrNull<Int64>(3) ?? 0
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
                                let tankoubonTags = getTankoubonTagsForTankoubon(conn, tankoubonId)
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
    public static func getTankoubonInternalId(conn: Connection, tankoubonId: String): Int64 {
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
     * 获取Tankoubon自身的标签（从tankoubon_tags关联表）
     */
    private static func getTankoubonTagsForTankoubon(conn: Connection, tankoubonId: String): String {
        try {
            let stmt = conn.prepareStatement("""
                SELECT CASE WHEN tg.namespace != '' AND tg.namespace IS NOT NULL
                            THEN tg.namespace || ':' || tg.name
                            ELSE tg.name
                       END as tag_str
                FROM tankoubon_tags tt
                JOIN tankoubons t ON t.id = tt.tankoubon_id
                JOIN tags tg ON tg.id = tt.tag_id
                WHERE t.tankoubon_id = ?
            """)
            try {
                stmt.set(0, tankoubonId)
                let rs = stmt.query()
                try {
                    var allTags: ArrayList<String> = ArrayList<String>()
                    while (rs.next()) {
                        let tag = rs.getOrNull<String>(0) ?? ""
                        if (tag != "") {
                            allTags.add(tag)
                        }
                    }
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
     * 获取Tankoubon中所有归档的标签
     */
    private static func getArchiveTagsForTankoubon(conn: Connection, tankoubonId: String): String {
        try {
            let stmt = conn.prepareStatement("""
                SELECT COALESCE(string_agg(DISTINCT
                    CASE
                        WHEN tg.namespace != '' AND tg.namespace IS NOT NULL
                        THEN tg.namespace || ':' || tg.name
                        ELSE tg.name
                    END, ','), '')
                FROM tankoubon_archives ta
                JOIN tankoubons t ON t.id = ta.tankoubon_id
                JOIN archive_tags atg ON atg.archive_id = ta.archive_id
                JOIN tags tg ON tg.id = atg.tag_id
                WHERE t.tankoubon_id = ?
            """)
            try {
                stmt.set(0, tankoubonId)
                let rs = stmt.query()
                try {
                    if (rs.next()) {
                        return rs.getOrNull<String>(0) ?? ""
                    }
                    return ""
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

        // 添加tankoubon标签（保留 source 标签）
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
                if (trimmed != "" && !TagDao.isSourceTag(trimmed)) {
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

    /**
     * 批量获取Tankoubon自身的标签（从tankoubon_tags关联表）
     */
    private static func getBatchTankoubonTagsForTankoubons(conn: Connection, tankoubonIds: Array<String>): HashMap<String, String> {
        var result: HashMap<String, String> = HashMap<String, String>()
        if (tankoubonIds.size == 0) {
            return result
        }

        try {
            var placeholders = ""
            for (i in 0..tankoubonIds.size) {
                if (i > 0) { placeholders += "," }
                placeholders += "?"
            }

            let stmt = conn.prepareStatement("""
                SELECT t.tankoubon_id,
                       CASE WHEN tg.namespace != '' AND tg.namespace IS NOT NULL
                            THEN tg.namespace || ':' || tg.name
                            ELSE tg.name
                       END as tag_str
                FROM tankoubon_tags tt
                JOIN tankoubons t ON t.id = tt.tankoubon_id
                JOIN tags tg ON tg.id = tt.tag_id
                WHERE t.tankoubon_id IN (${placeholders})
            """)
            try {
                for (i in 0..tankoubonIds.size) {
                    stmt.set(i, tankoubonIds[i])
                }
                let rs = stmt.query()
                try {
                    var tagsMap: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
                    while (rs.next()) {
                        let tid = rs.getOrNull<String>(0) ?? ""
                        let tag = rs.getOrNull<String>(1) ?? ""
                        if (tid != "" && tag != "") {
                            match (tagsMap.get(tid)) {
                                case Some(list) => list.add(tag)
                                case None =>
                                    let list = ArrayList<String>()
                                    list.add(tag)
                                    tagsMap[tid] = list
                            }
                        }
                    }
                    for ((tid, tagsList) in tagsMap) {
                        var combined = ""
                        for (i in 0..tagsList.size) {
                            if (i > 0) { combined += "," }
                            combined += tagsList[i]
                        }
                        result[tid] = combined
                    }
                } finally {
                    rs.close()
                }
            } finally {
                stmt.close()
            }
        } catch (_: Exception) {}
        return result
    }

    /**
     * 批量获取Tankoubon的归档标签
     */
    private static func getBatchArchiveTagsForTankoubons(conn: Connection, tankoubonIds: Array<String>): HashMap<String, String> {
        var result: HashMap<String, String> = HashMap<String, String>()
        if (tankoubonIds.size == 0) {
            return result
        }

        try {
            var placeholders = ""
            for (i in 0..tankoubonIds.size) {
                if (i > 0) { placeholders += "," }
                placeholders += "?"
            }

            let stmt = conn.prepareStatement("""
                SELECT
                    t.tankoubon_id,
                    COALESCE(string_agg(DISTINCT
                        CASE
                            WHEN tg.namespace != '' AND tg.namespace IS NOT NULL
                            THEN tg.namespace || ':' || tg.name
                            ELSE tg.name
                        END, ','), '') AS tags
                FROM tankoubon_archives ta
                JOIN tankoubons t ON t.id = ta.tankoubon_id
                JOIN archive_tags atg ON atg.archive_id = ta.archive_id
                JOIN tags tg ON tg.id = atg.tag_id
                WHERE t.tankoubon_id IN (${placeholders})
                GROUP BY t.tankoubon_id
            """)
            try {
                for (i in 0..tankoubonIds.size) {
                    stmt.set(i, tankoubonIds[i])
                }
                let rs = stmt.query()
                try {
                    while (rs.next()) {
                        let tid = rs.getOrNull<String>(0) ?? ""
                        let tags = rs.getOrNull<String>(1) ?? ""
                        if (tid != "") {
                            result[tid] = tags
                        }
                    }
                } finally {
                    rs.close()
                }
            } finally {
                stmt.close()
            }
        } catch (e: Exception) {
            getLogger("tankoubon_dao").error("批量获取归档标签失败", ("error", e.message))
        }
        return result
    }

    /**
     * 批量获取Tankoubon的聚合元数据
     */
    public static func getBatchAggregatedMetadata(tankoubonIds: Array<String>, userId: Int64): HashMap<String, TankoubonAggregatedData> {
        var result: HashMap<String, TankoubonAggregatedData> = HashMap<String, TankoubonAggregatedData>()
        if (tankoubonIds.size == 0) {
            return result
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    // 构建 IN 子句的占位符
                    var placeholders = ""
                    for (i in 0..tankoubonIds.size) {
                        if (i > 0) { placeholders += "," }
                        placeholders += "?"
                    }

                    let stmt = conn.prepareStatement("""
                        SELECT
                            t.tankoubon_id,
                            t.name,
                            t.summary,
                            COALESCE(t.cover_asset_id, 0) as cover_asset_id,
                            COALESCE(SUM(a.pagecount), 0)::INT as total_pagecount,
                            COUNT(a.id)::INT as archive_count,
                            COALESCE(MAX(uas.updated_at)::TEXT, '') as last_read_time,
                            COALESCE(AVG(uas.progress), 0)::INT as avg_progress,
                            COALESCE(BOOL_OR(uas.is_new), true) as has_new_archives
                        FROM tankoubons t
                        JOIN tankoubon_archives ta ON ta.tankoubon_id = t.id
                        JOIN archives a ON a.id = ta.archive_id
                        LEFT JOIN user_archive_status uas ON uas.archive_id = a.id AND uas.user_id = ?
                        WHERE t.tankoubon_id IN (${placeholders})
                        GROUP BY t.id, t.tankoubon_id, t.name, t.summary, t.cover_asset_id
                    """)
                    try {
                        stmt.set(0, userId)
                        for (i in 0..tankoubonIds.size) {
                            stmt.set(i + 1, tankoubonIds[i])
                        }

                        // 临时存储，用于后续获取标签
                        var tempData: HashMap<String, TankoubonAggregatedData> = HashMap<String, TankoubonAggregatedData>()

                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let data = TankoubonAggregatedData()
                                data.tankoubon_id = rs.getOrNull<String>(0) ?? ""
                                data.name = rs.getOrNull<String>(1) ?? ""
                                data.summary = rs.getOrNull<String>(2) ?? ""
                                data.cover_asset_id = rs.getOrNull<Int64>(3) ?? 0
                                data.pagecount = rs.getOrNull<Int32>(4) ?? 0
                                data.archive_count = rs.getOrNull<Int32>(5) ?? 0
                                data.last_read_time = rs.getOrNull<String>(6) ?? ""
                                data.progress = rs.getOrNull<Int32>(7) ?? 0
                                data.isnew = rs.getOrNull<Bool>(8) ?? true
                                tempData[data.tankoubon_id] = data
                            }
                        } finally {
                            rs.close()
                        }

                        // 批量获取 tankoubon 自身标签和归档标签并合并
                        let tankoubonTagsMap = getBatchTankoubonTagsForTankoubons(conn, tankoubonIds)
                        let archiveTagsMap = getBatchArchiveTagsForTankoubons(conn, tankoubonIds)
                        for ((tid, data) in tempData) {
                            var tankoubonTags = ""
                            var archiveTags = ""
                            match (tankoubonTagsMap.get(tid)) {
                                case Some(tags) => tankoubonTags = tags
                                case None => ()
                            }
                            match (archiveTagsMap.get(tid)) {
                                case Some(tags) => archiveTags = tags
                                case None => ()
                            }
                            data.tags = mergeTags(tankoubonTags, archiveTags)
                            result[tid] = data
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("批量获取Tankoubon聚合元数据失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                getLogger("tankoubon_dao").error("无法连接到数据库")
        }
        return result
    }

    /**
     * 批量获取Tankoubon中的所有归档arcids
     */
    public static func getBatchArchivesInTankoubon(tankoubonIds: Array<String>): HashMap<String, Array<String>> {
        var result: HashMap<String, Array<String>> = HashMap<String, Array<String>>()
        if (tankoubonIds.size == 0) {
            return result
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    var placeholders = ""
                    for (i in 0..tankoubonIds.size) {
                        if (i > 0) { placeholders += "," }
                        placeholders += "?"
                    }

                    let stmt = conn.prepareStatement("""
                        SELECT t.tankoubon_id, a.arcid
                        FROM tankoubon_archives ta
                        JOIN tankoubons t ON t.id = ta.tankoubon_id
                        JOIN archives a ON a.id = ta.archive_id
                        WHERE t.tankoubon_id IN (${placeholders})
                        ORDER BY t.tankoubon_id, ta.sort_order, ta.id
                    """)
                    try {
                        for (i in 0..tankoubonIds.size) {
                            stmt.set(i, tankoubonIds[i])
                        }
                        let rs = stmt.query()
                        try {
                            var tempMap: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
                            while (rs.next()) {
                                let tid = rs.getOrNull<String>(0) ?? ""
                                let arcid = rs.getOrNull<String>(1) ?? ""
                                if (tid != "" && arcid != "") {
                                    match (tempMap.get(tid)) {
                                        case Some(list) => list.add(arcid)
                                        case None =>
                                            let list = ArrayList<String>()
                                            list.add(arcid)
                                            tempMap[tid] = list
                                    }
                                }
                            }
                            for ((tid, list) in tempMap) {
                                result[tid] = list.toArray()
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tankoubon_dao").error("批量获取Tankoubon归档列表失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                getLogger("tankoubon_dao").error("无法连接到数据库")
        }
        return result
    }
}
