package lanlu.contexts.category.infrastructure.persistence

import ace_orm.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import lanlu.infrastructure.kv.*
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

    private static func invalidateArchiveBasePath(reason: String): Unit {
        let _ = DerivedCacheUtils.bumpArchiveBasePathVersion(reason)
    }

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

    private static let CATEGORY_SELECT_LITE = """
        SELECT id, catid, scan_path, plugins
        FROM categories
    """

    private static func readCategoryFromRow(r: Row): CategoryData {
        let cat = CategoryData()
        cat.id = r.getInt("id")
        cat.catid = r.getText("catid")
        cat.name = r.getText("name")
        cat.scanPath = r.getText("scan_path")
        cat.description = r.getText("description")
        cat.icon = r.getText("icon")
        cat.sortOrder = Int32(r.getInt("sort_order"))
        cat.enabled = r.getBool("enabled")
        cat.plugins = r.getText("plugins")
        cat.coverAssetId = r.getInt("cover_asset_id")
        cat.createdAt = r.getText("created_at")
        cat.updatedAt = r.getText("updated_at")
        cat.archiveCount = r.getInt("archive_count")
        return cat
    }

    private static func readCategoryLiteFromRow(r: Row): CategoryData {
        let cat = CategoryData()
        cat.id = r.getInt("id")
        cat.catid = r.getText("catid")
        cat.scanPath = r.getText("scan_path")
        cat.plugins = r.getText("plugins")
        return cat
    }

    /**
     * Update generated cover asset id for a category.
     */
    public static func updateCoverAssetId(catid: String, coverAssetId: Int64): Bool {
        let trimmedCatid = catid.trimAscii()
        if (trimmedCatid.size == 0) { return false }

        try {
            let result = DatabaseConfig.driver().exec("""
                UPDATE categories
                SET cover_asset_id = $1, updated_at = CURRENT_TIMESTAMP
                WHERE catid = $2
            """, [DbInt(coverAssetId), DbText(trimmedCatid)])
            return result > 0
        } catch (e: Exception) {
            logger.error("更新分类封面资源ID失败", ("error", e.message))
            return false
        }
    }

    /**
     * 获取所有分类
     */
    public static func getAllCategories(): Array<CategoryData> {
        try {
            let rows = DatabaseConfig.driver().query("${CATEGORY_SELECT_WITH_COUNT}\n${CATEGORY_GROUP_BY}\nORDER BY c.sort_order, c.id", [])
            var categories = ArrayList<CategoryData>()
            for (r in rows) {
                categories.add(readCategoryFromRow(r))
            }
            return categories.toArray()
        } catch (e: Exception) {
            logger.error("查询分类失败", ("error", e.message))
            return Array<CategoryData>()
        }
    }

    /**
     * 获取启用的分类
     */
    public static func getEnabledCategories(): Array<CategoryData> {
        try {
            let rows = DatabaseConfig.driver().query(
                "${CATEGORY_SELECT_WITH_COUNT}\nWHERE c.enabled = true\n${CATEGORY_GROUP_BY}\nORDER BY c.sort_order, c.id", [])
            var categories = ArrayList<CategoryData>()
            for (r in rows) {
                categories.add(readCategoryFromRow(r))
            }
            return categories.toArray()
        } catch (e: Exception) {
            logger.error("查询启用分类失败", ("error", e.message))
            return Array<CategoryData>()
        }
    }

    /**
     * 根据 catid 获取分类
     */
    public static func getCategoryById(catid: String): Option<CategoryData> {
        try {
            let rows = DatabaseConfig.driver().query("${CATEGORY_SELECT_WITH_COUNT}\nWHERE c.catid = $1\n${CATEGORY_GROUP_BY}", [DbText(catid)])
            if (rows.size > 0) {
                return Some(readCategoryFromRow(rows[0]))
            }
            return None
        } catch (e: Exception) {
            logger.error("查询分类失败", ("error", e.message))
            return None
        }
    }

    /**
     * 根据内部 ID 获取分类
     */
    public static func getCategoryByInternalId(id: Int64): Option<CategoryData> {
        try {
            let rows = DatabaseConfig.driver().query("${CATEGORY_SELECT_WITH_COUNT}\nWHERE c.id = $1\n${CATEGORY_GROUP_BY}", [DbInt(id)])
            if (rows.size > 0) {
                return Some(readCategoryFromRow(rows[0]))
            }
            return None
        } catch (e: Exception) {
            logger.error("查询分类失败", ("error", e.message))
            return None
        }
    }

    /**
     * 根据 catid 获取分类（轻量字段：id/catid/scan_path/plugins）
     */
    public static func getCategoryByIdLite(catid: String): Option<CategoryData> {
        try {
            let rows = DatabaseConfig.driver().query("${CATEGORY_SELECT_LITE}\nWHERE catid = $1", [DbText(catid)])
            if (rows.size > 0) {
                return Some(readCategoryLiteFromRow(rows[0]))
            }
            return None
        } catch (e: Exception) {
            logger.error("查询分类轻量字段失败", ("error", e.message))
            return None
        }
    }

    /**
     * 根据内部 ID 获取分类（轻量字段：id/catid/scan_path/plugins）
     */
    public static func getCategoryByInternalIdLite(id: Int64): Option<CategoryData> {
        try {
            let rows = DatabaseConfig.driver().query("${CATEGORY_SELECT_LITE}\nWHERE id = $1", [DbInt(id)])
            if (rows.size > 0) {
                return Some(readCategoryLiteFromRow(rows[0]))
            }
            return None
        } catch (e: Exception) {
            logger.error("查询分类轻量字段失败", ("error", e.message))
            return None
        }
    }

    /**
     * 创建分类
     */
    public static func createCategory(data: CategoryData): Option<CategoryData> {
        try {
            let rows = DatabaseConfig.driver().query("""
                INSERT INTO categories (catid, name, scan_path, description, icon, sort_order, enabled, plugins)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                RETURNING id, created_at, updated_at
            """, [DbText(data.catid), DbText(data.name), DbText(data.scanPath), DbText(data.description), DbText(data.icon), DbInt(Int64(data.sortOrder)), DbBool(data.enabled), DbText(data.plugins)])
            if (rows.size > 0) {
                let r = rows[0]
                data.id = r.getInt("id")
                data.createdAt = r.getText("created_at")
                data.updatedAt = r.getText("updated_at")
                data.archiveCount = 0
                invalidateArchiveBasePath("categoryCreate:${data.catid}")
                return Some(data)
            }
            return None
        } catch (e: Exception) {
            logger.error("创建分类失败", ("error", e.message))
            return None
        }
    }

    /**
     * 更新分类
     */
    public static func updateCategory(catid: String, data: CategoryData): Bool {
        try {
            let result = DatabaseConfig.driver().exec("""
                UPDATE categories
                SET name = $1, scan_path = $2, description = $3, icon = $4,
                    sort_order = $5, enabled = $6, plugins = $7, updated_at = CURRENT_TIMESTAMP
                WHERE catid = $8
            """, [DbText(data.name), DbText(data.scanPath), DbText(data.description), DbText(data.icon), DbInt(Int64(data.sortOrder)), DbBool(data.enabled), DbText(data.plugins), DbText(catid)])
            if (result > 0) {
                invalidateArchiveBasePath("categoryUpdate:${catid}")
            }
            return result > 0
        } catch (e: Exception) {
            logger.error("更新分类失败", ("error", e.message))
            return false
        }
    }

    /**
     * 删除分类（同时从数据库删除该分类下的档案记录；不删除原始档案文件，仅清理缩略图缓存）
     */
    public static func deleteCategory(catid: String): (Bool, Int64, String) {
        try {
            // 先获取分类内部ID
            let idRows = DatabaseConfig.driver().query("SELECT id FROM categories WHERE catid = $1", [DbText(catid)])
            if (idRows.size == 0) {
                return (false, 0, "Category not found")
            }
            let categoryInternalId = idRows[0].getInt("id")

            // 先删除该分类下的档案记录（依赖 DB 约束级联清理关联表：收藏/状态/标签/合集关联等）
            let deletedArchives = DatabaseConfig.driver().exec("DELETE FROM archives WHERE category_id = $1", [DbInt(categoryInternalId)])

            // 删除分类本身（不删除磁盘文件）
            let delResult = DatabaseConfig.driver().exec("DELETE FROM categories WHERE id = $1", [DbInt(categoryInternalId)])
            if (delResult <= 0) {
                return (false, deletedArchives, "Failed to delete category")
            }
            invalidateArchiveBasePath("categoryDelete:${catid}")
            return (true, deletedArchives, "")
        } catch (e: Exception) {
            logger.error("删除分类失败", ("error", e.message))
            return (false, 0, e.message)
        }
    }

    /**
     * 获取分类的档案数量
     */
    public static func getArchiveCount(categoryId: Int64): Int64 {
        try {
            let rows = DatabaseConfig.driver().query("SELECT COUNT(*) FROM archives WHERE category_id = $1", [DbInt(categoryId)])
            if (rows.size > 0) {
                return rows[0].getInt("count")
            }
            return 0
        } catch (e: Exception) {
            logger.error("获取档案数量失败", ("error", e.message))
            return 0
        }
    }

    /**
     * 获取所有分类的扫描路径
     */
    public static func getAllScanPaths(): Array<(Int64, String)> {
        try {
            let rows = DatabaseConfig.driver().query("SELECT id, scan_path FROM categories WHERE enabled = true ORDER BY sort_order, id", [])
            var paths = ArrayList<(Int64, String)>()
            for (r in rows) {
                let id = r.getInt("id")
                let path = r.getText("scan_path")
                paths.add((id, path))
            }
            return paths.toArray()
        } catch (e: Exception) {
            logger.error("获取扫描路径失败", ("error", e.message))
            return Array<(Int64, String)>()
        }
    }

    /**
     * 根据 catid 获取内部 ID
     */
    public static func getInternalId(catid: String): Int64 {
        try {
            let rows = DatabaseConfig.driver().query("SELECT id FROM categories WHERE catid = $1", [DbText(catid)])
            if (rows.size > 0) {
                return rows[0].getInt("id")
            }
            return 0
        } catch (e: Exception) {
            logger.error("获取分类内部ID失败", ("error", e.message))
            return 0
        }
    }

    // NOTE: category cover is stored as assets(kind='category_cover', file ext avif),
    // and referenced by categories.cover_asset_id.

}