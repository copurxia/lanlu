package lanlu.dao

import std.database.sql.*
import lanlu.config.*
import lanlu.utils.*
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
    public var plugins: String = "[]"
    // Generated cover asset id stored on categories table.
    public var coverAssetId: Int64 = 0
    public var createdAt: String = ""
    public var updatedAt: String = ""
    public var archiveCount: Int64 = 0
}

/**
 * 分类数据访问对象 (DAO)
 */
public class CategoryDao {
    private static let logger = getLogger("category_dao")

    private static let CATEGORY_SELECT_WITH_COUNT = """
        SELECT c.id, c.catid, c.name, c.scan_path, c.description, c.icon,
               c.sort_order, c.enabled, c.plugins,
               COALESCE(c.cover_asset_id, 0) AS cover_asset_id,
               c.created_at, c.updated_at,
               COUNT(a.id) as archive_count
        FROM categories c
        LEFT JOIN archives a ON a.category_id = c.id
    """

    private static let CATEGORY_GROUP_BY = """
        GROUP BY c.id, c.catid, c.name, c.scan_path, c.description, c.icon,
                 c.sort_order, c.enabled, c.plugins, c.cover_asset_id, c.created_at, c.updated_at
    """

    private static func readCategoryFromResultSet(rs: QueryResult): CategoryData {
        let cat = CategoryData()
        cat.id = rs.getOrNull<Int64>(0) ?? 0
        cat.catid = rs.getOrNull<String>(1) ?? ""
        cat.name = rs.getOrNull<String>(2) ?? ""
        cat.scanPath = rs.getOrNull<String>(3) ?? ""
        cat.description = rs.getOrNull<String>(4) ?? ""
        cat.icon = rs.getOrNull<String>(5) ?? ""
        cat.sortOrder = rs.getOrNull<Int32>(6) ?? 0
        cat.enabled = rs.getOrNull<Bool>(7) ?? true
        cat.plugins = rs.getOrNull<String>(8) ?? "[]"
        cat.coverAssetId = rs.getOrNull<Int64>(9) ?? 0
        cat.createdAt = rs.getOrNull<String>(10) ?? ""
        cat.updatedAt = rs.getOrNull<String>(11) ?? ""
        cat.archiveCount = rs.getOrNull<Int64>(12) ?? 0
        return cat
    }

    /**
     * Update generated cover asset id for a category.
     */
    public static func updateCoverAssetId(catid: String, coverAssetId: Int64): Bool {
        let trimmedCatid = catid.trimAscii()
        if (trimmedCatid.size == 0) { return false }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE categories
                        SET cover_asset_id = ?, updated_at = CURRENT_TIMESTAMP
                        WHERE catid = ?
                    """)
                    try {
                        stmt.set(0, coverAssetId)
                        stmt.set(1, trimmedCatid)
                        let result = stmt.update()
                        return result.rowCount > 0
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("更新分类封面资源ID失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    /**
     * 获取所有分类
     */
    public static func getAllCategories(): Array<CategoryData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                var categories = ArrayList<CategoryData>()
                try {
                    let stmt = conn.prepareStatement("${CATEGORY_SELECT_WITH_COUNT}\n${CATEGORY_GROUP_BY}\nORDER BY c.sort_order, c.id")
                    try {
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                categories.add(readCategoryFromResultSet(rs))
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return categories.toArray()
                } catch (e: Exception) {
                    logger.error("查询分类失败", ("error", e.message))
                    return Array<CategoryData>()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法连接到数据库")
                return Array<CategoryData>()
        }
    }

    /**
     * 获取启用的分类
     */
    public static func getEnabledCategories(): Array<CategoryData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                var categories = ArrayList<CategoryData>()
                try {
                    let stmt = conn.prepareStatement(
                        "${CATEGORY_SELECT_WITH_COUNT}\nWHERE c.enabled = true\n${CATEGORY_GROUP_BY}\nORDER BY c.sort_order, c.id"
                    )
                    try {
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                categories.add(readCategoryFromResultSet(rs))
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return categories.toArray()
                } catch (e: Exception) {
                    logger.error("查询启用分类失败", ("error", e.message))
                    return Array<CategoryData>()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法连接到数据库")
                return Array<CategoryData>()
        }
    }

    /**
     * 根据 catid 获取分类
     */
    public static func getCategoryById(catid: String): Option<CategoryData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("${CATEGORY_SELECT_WITH_COUNT}\nWHERE c.catid = ?\n${CATEGORY_GROUP_BY}")
                    try {
                        stmt.set(0, catid)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return Some(readCategoryFromResultSet(rs))
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return None
                } catch (e: Exception) {
                    logger.error("查询分类失败", ("error", e.message))
                    return None
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法连接到数据库")
                return None
        }
    }

    /**
     * 根据内部 ID 获取分类
     */
    public static func getCategoryByInternalId(id: Int64): Option<CategoryData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("${CATEGORY_SELECT_WITH_COUNT}\nWHERE c.id = ?\n${CATEGORY_GROUP_BY}")
                    try {
                        stmt.set(0, id)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return Some(readCategoryFromResultSet(rs))
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return None
                } catch (e: Exception) {
                    logger.error("查询分类失败", ("error", e.message))
                    return None
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法连接到数据库")
                return None
        }
    }

    /**
     * 创建分类
     */
    public static func createCategory(data: CategoryData): Option<CategoryData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO categories (catid, name, scan_path, description, icon, sort_order, enabled, plugins)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
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
                        stmt.set(7, data.plugins)
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
                    logger.error("创建分类失败", ("error", e.message))
                    return None
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法连接到数据库")
                return None
        }
    }

    /**
     * 更新分类
     */
    public static func updateCategory(catid: String, data: CategoryData): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE categories
                        SET name = ?, scan_path = ?, description = ?, icon = ?,
                            sort_order = ?, enabled = ?, plugins = ?, updated_at = CURRENT_TIMESTAMP
                        WHERE catid = ?
                    """)
                    try {
                        stmt.set(0, data.name)
                        stmt.set(1, data.scanPath)
                        stmt.set(2, data.description)
                        stmt.set(3, data.icon)
                        stmt.set(4, data.sortOrder)
                        stmt.set(5, data.enabled)
                        stmt.set(6, data.plugins)
                        stmt.set(7, catid)
                        let result = stmt.update()
                        return result.rowCount > 0
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("更新分类失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    /**
     * 删除分类（同时从数据库删除该分类下的档案记录；不删除原始档案文件，仅清理缩略图缓存）
     */
    public static func deleteCategory(catid: String): (Bool, Int64, String) {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    // 先获取分类内部ID
                    let getStmt = conn.prepareStatement("SELECT id FROM categories WHERE catid = ?")
                    var categoryInternalId: Int64 = 0
                    try {
                        getStmt.set(0, catid)
                        let rs = getStmt.query()
                        try {
                            if (!rs.next()) {
                                return (false, 0, "Category not found")
                            }
                            categoryInternalId = rs.getOrNull<Int64>(0) ?? 0
                        } finally {
                            rs.close()
                        }
                    } finally {
                        getStmt.close()
                    }

                    // 先删除该分类下的档案记录（依赖 DB 约束级联清理关联表：收藏/状态/标签/合集关联等）
                    var deletedArchives: Int64 = 0
                    let delArchivesStmt = conn.prepareStatement("DELETE FROM archives WHERE category_id = ?")
                    try {
                        delArchivesStmt.set(0, categoryInternalId)
                        let result = delArchivesStmt.update()
                        deletedArchives = result.rowCount
                    } finally {
                        delArchivesStmt.close()
                    }

                    // 删除分类本身（不删除磁盘文件）
                    let delCatStmt = conn.prepareStatement("DELETE FROM categories WHERE id = ?")
                    try {
                        delCatStmt.set(0, categoryInternalId)
                        let result = delCatStmt.update()
                        if (result.rowCount <= 0) {
                            return (false, deletedArchives, "Failed to delete category")
                        }
                        return (true, deletedArchives, "")
                    } finally {
                        delCatStmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("删除分类失败", ("error", e.message))
                    return (false, 0, e.message)
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法连接到数据库")
                return (false, 0, "Unable to connect to database")
        }
    }

    /**
     * 获取分类的档案数量
     */
    public static func getArchiveCount(categoryId: Int64): Int64 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
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
                    logger.error("获取档案数量失败", ("error", e.message))
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法连接到数据库")
                return 0
        }
    }

    /**
     * 获取所有分类的扫描路径
     */
    public static func getAllScanPaths(): Array<(Int64, String)> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
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
                    logger.error("获取扫描路径失败", ("error", e.message))
                    return Array<(Int64, String)>()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法连接到数据库")
                return Array<(Int64, String)>()
        }
    }

    /**
     * 根据 catid 获取内部 ID
     */
    public static func getInternalId(catid: String): Int64 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
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
                    logger.error("获取分类内部ID失败", ("error", e.message))
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("无法连接到数据库")
                return 0
        }
    }

    // NOTE: category cover is stored as assets(kind='category_cover', file ext avif),
    // and referenced by categories.cover_asset_id.

}
