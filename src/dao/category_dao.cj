package lrr4cj.dao

import std.database.sql.*
import lrr4cj.config.*
import lrr4cj.utils.*
import std.collection.*
import stdx.log.*

/**
 * 分类数据结构
 */
public class CategoryData {
    public var id: Int64 = 0
    public var catid: String = ""
    public var name: String = ""
    public var scanPath: String = ""
    public var description: String = ""
    public var icon: String = ""
    public var sortOrder: Int32 = 0
    public var enabled: Bool = true
    public var createdAt: String = ""
    public var updatedAt: String = ""
    public var archiveCount: Int64 = 0
}

/**
 * 分类数据访问对象 (DAO)
 */
public class CategoryDao {

    /**
     * 获取所有分类
     */
    public static func getAllCategories(): Array<CategoryData> {
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                var categories = ArrayList<CategoryData>()
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT c.id, c.catid, c.name, c.scan_path, c.description, c.icon,
                               c.sort_order, c.enabled, c.created_at, c.updated_at,
                               COUNT(a.id) as archive_count
                        FROM categories c
                        LEFT JOIN archives a ON a.category_id = c.id
                        GROUP BY c.id, c.catid, c.name, c.scan_path, c.description, c.icon,
                                 c.sort_order, c.enabled, c.created_at, c.updated_at
                        ORDER BY c.sort_order, c.id
                    """)
                    try {
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let cat = CategoryData()
                                cat.id = rs.getOrNull<Int64>(0) ?? 0
                                cat.catid = rs.getOrNull<String>(1) ?? ""
                                cat.name = rs.getOrNull<String>(2) ?? ""
                                cat.scanPath = rs.getOrNull<String>(3) ?? ""
                                cat.description = rs.getOrNull<String>(4) ?? ""
                                cat.icon = rs.getOrNull<String>(5) ?? ""
                                cat.sortOrder = rs.getOrNull<Int32>(6) ?? 0
                                cat.enabled = rs.getOrNull<Bool>(7) ?? true
                                cat.createdAt = rs.getOrNull<String>(8) ?? ""
                                cat.updatedAt = rs.getOrNull<String>(9) ?? ""
                                cat.archiveCount = rs.getOrNull<Int64>(10) ?? 0
                                categories.add(cat)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return categories.toArray()
                } catch (e: Exception) {
                    getLogger("category_dao").error("查询分类失败", ("error", e.message))
                    return Array<CategoryData>()
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                getLogger("category_dao").error("无法连接到数据库")
                return Array<CategoryData>()
        }
    }

    /**
     * 获取启用的分类
     */
    public static func getEnabledCategories(): Array<CategoryData> {
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                var categories = ArrayList<CategoryData>()
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT c.id, c.catid, c.name, c.scan_path, c.description, c.icon,
                               c.sort_order, c.enabled, c.created_at, c.updated_at,
                               COUNT(a.id) as archive_count
                        FROM categories c
                        LEFT JOIN archives a ON a.category_id = c.id
                        WHERE c.enabled = true
                        GROUP BY c.id, c.catid, c.name, c.scan_path, c.description, c.icon,
                                 c.sort_order, c.enabled, c.created_at, c.updated_at
                        ORDER BY c.sort_order, c.id
                    """)
                    try {
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let cat = CategoryData()
                                cat.id = rs.getOrNull<Int64>(0) ?? 0
                                cat.catid = rs.getOrNull<String>(1) ?? ""
                                cat.name = rs.getOrNull<String>(2) ?? ""
                                cat.scanPath = rs.getOrNull<String>(3) ?? ""
                                cat.description = rs.getOrNull<String>(4) ?? ""
                                cat.icon = rs.getOrNull<String>(5) ?? ""
                                cat.sortOrder = rs.getOrNull<Int32>(6) ?? 0
                                cat.enabled = rs.getOrNull<Bool>(7) ?? true
                                cat.createdAt = rs.getOrNull<String>(8) ?? ""
                                cat.updatedAt = rs.getOrNull<String>(9) ?? ""
                                cat.archiveCount = rs.getOrNull<Int64>(10) ?? 0
                                categories.add(cat)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return categories.toArray()
                } catch (e: Exception) {
                    getLogger("category_dao").error("查询启用分类失败", ("error", e.message))
                    return Array<CategoryData>()
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                getLogger("category_dao").error("无法连接到数据库")
                return Array<CategoryData>()
        }
    }

    /**
     * 根据 catid 获取分类
     */
    public static func getCategoryById(catid: String): Option<CategoryData> {
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT c.id, c.catid, c.name, c.scan_path, c.description, c.icon,
                               c.sort_order, c.enabled, c.created_at, c.updated_at,
                               COUNT(a.id) as archive_count
                        FROM categories c
                        LEFT JOIN archives a ON a.category_id = c.id
                        WHERE c.catid = ?
                        GROUP BY c.id, c.catid, c.name, c.scan_path, c.description, c.icon,
                                 c.sort_order, c.enabled, c.created_at, c.updated_at
                    """)
                    try {
                        stmt.set(0, catid)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let cat = CategoryData()
                                cat.id = rs.getOrNull<Int64>(0) ?? 0
                                cat.catid = rs.getOrNull<String>(1) ?? ""
                                cat.name = rs.getOrNull<String>(2) ?? ""
                                cat.scanPath = rs.getOrNull<String>(3) ?? ""
                                cat.description = rs.getOrNull<String>(4) ?? ""
                                cat.icon = rs.getOrNull<String>(5) ?? ""
                                cat.sortOrder = rs.getOrNull<Int32>(6) ?? 0
                                cat.enabled = rs.getOrNull<Bool>(7) ?? true
                                cat.createdAt = rs.getOrNull<String>(8) ?? ""
                                cat.updatedAt = rs.getOrNull<String>(9) ?? ""
                                cat.archiveCount = rs.getOrNull<Int64>(10) ?? 0
                                return Some(cat)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return None
                } catch (e: Exception) {
                    getLogger("category_dao").error("查询分类失败", ("error", e.message))
                    return None
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                getLogger("category_dao").error("无法连接到数据库")
                return None
        }
    }

    /**
     * 根据内部 ID 获取分类
     */
    public static func getCategoryByInternalId(id: Int64): Option<CategoryData> {
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT c.id, c.catid, c.name, c.scan_path, c.description, c.icon,
                               c.sort_order, c.enabled, c.created_at, c.updated_at,
                               COUNT(a.id) as archive_count
                        FROM categories c
                        LEFT JOIN archives a ON a.category_id = c.id
                        WHERE c.id = ?
                        GROUP BY c.id, c.catid, c.name, c.scan_path, c.description, c.icon,
                                 c.sort_order, c.enabled, c.created_at, c.updated_at
                    """)
                    try {
                        stmt.set(0, id)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let cat = CategoryData()
                                cat.id = rs.getOrNull<Int64>(0) ?? 0
                                cat.catid = rs.getOrNull<String>(1) ?? ""
                                cat.name = rs.getOrNull<String>(2) ?? ""
                                cat.scanPath = rs.getOrNull<String>(3) ?? ""
                                cat.description = rs.getOrNull<String>(4) ?? ""
                                cat.icon = rs.getOrNull<String>(5) ?? ""
                                cat.sortOrder = rs.getOrNull<Int32>(6) ?? 0
                                cat.enabled = rs.getOrNull<Bool>(7) ?? true
                                cat.createdAt = rs.getOrNull<String>(8) ?? ""
                                cat.updatedAt = rs.getOrNull<String>(9) ?? ""
                                cat.archiveCount = rs.getOrNull<Int64>(10) ?? 0
                                return Some(cat)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return None
                } catch (e: Exception) {
                    getLogger("category_dao").error("查询分类失败", ("error", e.message))
                    return None
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                getLogger("category_dao").error("无法连接到数据库")
                return None
        }
    }

    /**
     * 创建分类
     */
    public static func createCategory(data: CategoryData): Option<CategoryData> {
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO categories (catid, name, scan_path, description, icon, sort_order, enabled)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        RETURNING id, created_at, updated_at
                    """)
                    try {
                        stmt.set(0, data.catid)
                        stmt.set(1, data.name)
                        stmt.set(2, data.scanPath)
                        stmt.set(3, data.description)
                        stmt.set(4, data.icon)
                        stmt.set(5, data.sortOrder)
                        stmt.set(6, data.enabled)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                data.id = rs.getOrNull<Int64>(0) ?? 0
                                data.createdAt = rs.getOrNull<String>(1) ?? ""
                                data.updatedAt = rs.getOrNull<String>(2) ?? ""
                                data.archiveCount = 0
                                return Some(data)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return None
                } catch (e: Exception) {
                    getLogger("category_dao").error("创建分类失败", ("error", e.message))
                    return None
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                getLogger("category_dao").error("无法连接到数据库")
                return None
        }
    }

    /**
     * 更新分类
     */
    public static func updateCategory(catid: String, data: CategoryData): Bool {
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE categories
                        SET name = ?, scan_path = ?, description = ?, icon = ?,
                            sort_order = ?, enabled = ?, updated_at = CURRENT_TIMESTAMP
                        WHERE catid = ?
                    """)
                    try {
                        stmt.set(0, data.name)
                        stmt.set(1, data.scanPath)
                        stmt.set(2, data.description)
                        stmt.set(3, data.icon)
                        stmt.set(4, data.sortOrder)
                        stmt.set(5, data.enabled)
                        stmt.set(6, catid)
                        let result = stmt.update()
                        return result.rowCount > 0
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("category_dao").error("更新分类失败", ("error", e.message))
                    return false
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                getLogger("category_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 删除分类（仅当分类下没有档案时）
     */
    public static func deleteCategory(catid: String): Bool {
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    // 先检查是否有档案
                    let checkStmt = conn.prepareStatement("""
                        SELECT COUNT(*) FROM archives a
                        JOIN categories c ON c.id = a.category_id
                        WHERE c.catid = ?
                    """)
                    try {
                        checkStmt.set(0, catid)
                        let checkRs = checkStmt.query()
                        try {
                            if (checkRs.next()) {
                                let count = checkRs.getOrNull<Int64>(0) ?? 0
                                if (count > 0) {
                                    getLogger("category_dao").warn("无法删除分类，存在关联档案", ("catid", catid), ("count", count.toString()))
                                    return false
                                }
                            }
                        } finally {
                            checkRs.close()
                        }
                    } finally {
                        checkStmt.close()
                    }

                    // 删除分类
                    let stmt = conn.prepareStatement("DELETE FROM categories WHERE catid = ?")
                    try {
                        stmt.set(0, catid)
                        let result = stmt.update()
                        return result.rowCount > 0
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("category_dao").error("删除分类失败", ("error", e.message))
                    return false
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                getLogger("category_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 获取分类的档案数量
     */
    public static func getArchiveCount(categoryId: Int64): Int64 {
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("SELECT COUNT(*) FROM archives WHERE category_id = ?")
                    try {
                        stmt.set(0, categoryId)
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
                    getLogger("category_dao").error("获取档案数量失败", ("error", e.message))
                    return 0
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                getLogger("category_dao").error("无法连接到数据库")
                return 0
        }
    }

    /**
     * 获取所有分类的扫描路径
     */
    public static func getAllScanPaths(): Array<(Int64, String)> {
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                var paths = ArrayList<(Int64, String)>()
                try {
                    let stmt = conn.prepareStatement("SELECT id, scan_path FROM categories WHERE enabled = true ORDER BY sort_order, id")
                    try {
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let id = rs.getOrNull<Int64>(0) ?? 0
                                let path = rs.getOrNull<String>(1) ?? ""
                                paths.add((id, path))
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return paths.toArray()
                } catch (e: Exception) {
                    getLogger("category_dao").error("获取扫描路径失败", ("error", e.message))
                    return Array<(Int64, String)>()
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                getLogger("category_dao").error("无法连接到数据库")
                return Array<(Int64, String)>()
        }
    }

    /**
     * 根据 catid 获取内部 ID
     */
    public static func getInternalId(catid: String): Int64 {
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("SELECT id FROM categories WHERE catid = ?")
                    try {
                        stmt.set(0, catid)
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
                    getLogger("category_dao").error("获取分类内部ID失败", ("error", e.message))
                    return 0
                } finally {
                    try { DatabaseConfig.releasePooledConnection(handle) } catch (_: Exception) {}
                }
            case None =>
                getLogger("category_dao").error("无法连接到数据库")
                return 0
        }
    }
}
