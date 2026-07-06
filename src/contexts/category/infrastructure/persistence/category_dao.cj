package lanlu.contexts.category.infrastructure.persistence

import csorm.*
import postgresql_driver.*
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

    private static func readCategoryFromRow(row: Row): CategoryData {
        let cat = CategoryData()
        cat.id = row.getOrNullInt64(0) ?? 0
        cat.catid = row.getOrNullText(1) ?? ""
        cat.name = row.getOrNullText(2) ?? ""
        cat.scanPath = row.getOrNullText(3) ?? ""
        cat.description = row.getOrNullText(4) ?? ""
        cat.icon = row.getOrNullText(5) ?? ""
        cat.sortOrder = row.getOrNullInt32(6) ?? 0
        cat.enabled = row.getOrNullBool(7) ?? true
        cat.plugins = row.getOrNullText(8) ?? "[]"
        cat.coverAssetId = row.getOrNullInt64(9) ?? 0
        cat.createdAt = row.getOrNullText(10) ?? ""
        cat.updatedAt = row.getOrNullText(11) ?? ""
        cat.archiveCount = row.getOrNullInt64(12) ?? 0
        return cat
    }

    private static func readCategoryLiteFromRow(row: Row): CategoryData {
        let cat = CategoryData()
        cat.id = row.getOrNullInt64(0) ?? 0
        cat.catid = row.getOrNullText(1) ?? ""
        cat.scanPath = row.getOrNullText(2) ?? ""
        cat.plugins = row.getOrNullText(3) ?? "[]"
        return cat
    }

    /**
     * Update generated cover asset id for a category.
     */
    public static func updateCoverAssetId(catid: String, coverAssetId: Int64): Bool {
        let trimmedCatid = catid.trimAscii()
        if (trimmedCatid.size == 0) { return false }

        let params: Array<Value> = [vint(coverAssetId), vtext(trimmedCatid)]
        let sql = """
            UPDATE categories
            SET cover_asset_id = $1, updated_at = CURRENT_TIMESTAMP
            WHERE catid = $2
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let affected = db.execRaw(sql, params)
                    return affected > 0
                } catch (e: Exception) {
                    logger.error("更新分类封面资源ID失败", ("error", e.message))
                    return false
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
        let sql = "${CATEGORY_SELECT_WITH_COUNT}\n${CATEGORY_GROUP_BY}\nORDER BY c.sort_order, c.id"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.raw<CategoryData>(sql, [], { row => readCategoryFromRow(row) })
                } catch (e: Exception) {
                    logger.error("查询分类失败", ("error", e.message))
                    return Array<CategoryData>()
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
        let sql = "${CATEGORY_SELECT_WITH_COUNT}\nWHERE c.enabled = true\n${CATEGORY_GROUP_BY}\nORDER BY c.sort_order, c.id"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.raw<CategoryData>(sql, [], { row => readCategoryFromRow(row) })
                } catch (e: Exception) {
                    logger.error("查询启用分类失败", ("error", e.message))
                    return Array<CategoryData>()
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
        let sql = "${CATEGORY_SELECT_WITH_COUNT}\nWHERE c.catid = $1\n${CATEGORY_GROUP_BY}"
        let params: Array<Value> = [vtext(catid)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<CategoryData>(sql, params, { row => readCategoryFromRow(row) })
                } catch (e: Exception) {
                    logger.error("查询分类失败", ("error", e.message))
                    return None
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
        let sql = "${CATEGORY_SELECT_WITH_COUNT}\nWHERE c.id = $1\n${CATEGORY_GROUP_BY}"
        let params: Array<Value> = [vint(id)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<CategoryData>(sql, params, { row => readCategoryFromRow(row) })
                } catch (e: Exception) {
                    logger.error("查询分类失败", ("error", e.message))
                    return None
                }
            case None =>
                logger.error("无法连接到数据库")
                return None
        }
    }

    /**
     * 根据 catid 获取分类（轻量字段：id/catid/scan_path/plugins）
     */
    public static func getCategoryByIdLite(catid: String): Option<CategoryData> {
        let sql = "${CATEGORY_SELECT_LITE}\nWHERE catid = $1"
        let params: Array<Value> = [vtext(catid)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<CategoryData>(sql, params, { row => readCategoryLiteFromRow(row) })
                } catch (e: Exception) {
                    logger.error("查询分类轻量字段失败", ("error", e.message))
                    return None
                }
            case None =>
                logger.error("无法连接到数据库")
                return None
        }
    }

    /**
     * 根据内部 ID 获取分类（轻量字段：id/catid/scan_path/plugins）
     */
    public static func getCategoryByInternalIdLite(id: Int64): Option<CategoryData> {
        let sql = "${CATEGORY_SELECT_LITE}\nWHERE id = $1"
        let params: Array<Value> = [vint(id)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<CategoryData>(sql, params, { row => readCategoryLiteFromRow(row) })
                } catch (e: Exception) {
                    logger.error("查询分类轻量字段失败", ("error", e.message))
                    return None
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
        let params: Array<Value> = [
            vtext(data.catid),
            vtext(data.name),
            vtext(data.scanPath),
            vtext(data.description),
            vtext(data.icon),
            vint(Int64(data.sortOrder)),
            vbool(data.enabled),
            vtext(data.plugins)
        ]
        let sql = """
            INSERT INTO categories (catid, name, scan_path, description, icon, sort_order, enabled, plugins)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING id, created_at, updated_at
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rowOpt = db.rawOne<Row>(sql, params, { r => r })
                    match (rowOpt) {
                        case Some(row) =>
                            data.id = row.getOrNullInt64(0) ?? 0
                            data.createdAt = row.getOrNullText(1) ?? ""
                            data.updatedAt = row.getOrNullText(2) ?? ""
                            data.archiveCount = 0
                            invalidateArchiveBasePath("categoryCreate:${data.catid}")
                            return Some(data)
                        case None =>
                            return None
                    }
                } catch (e: Exception) {
                    logger.error("创建分类失败", ("error", e.message))
                    return None
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
        let params: Array<Value> = [
            vtext(data.name),
            vtext(data.scanPath),
            vtext(data.description),
            vtext(data.icon),
            vint(Int64(data.sortOrder)),
            vbool(data.enabled),
            vtext(data.plugins),
            vtext(catid)
        ]
        let sql = """
            UPDATE categories
            SET name = $1, scan_path = $2, description = $3, icon = $4,
                sort_order = $5, enabled = $6, plugins = $7, updated_at = CURRENT_TIMESTAMP
            WHERE catid = $8
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let affected = db.execRaw(sql, params)
                    if (affected > 0) {
                        invalidateArchiveBasePath("categoryUpdate:${catid}")
                    }
                    return affected > 0
                } catch (e: Exception) {
                    logger.error("更新分类失败", ("error", e.message))
                    return false
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
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    // 先获取分类内部ID
                    var categoryInternalId: Int64 = 0
                    let idOpt = db.rawOne<Int64>("SELECT id FROM categories WHERE catid = $1", [vtext(catid)], { r => r.getOrNullInt64(0) ?? 0 })
                    match (idOpt) {
                        case Some(id) => categoryInternalId = id
                        case None => return (false, 0, "Category not found")
                    }

                    // 先删除该分类下的档案记录（依赖 DB 约束级联清理关联表：收藏/状态/标签/合集关联等）
                    let deletedArchives = db.execRaw("DELETE FROM archives WHERE category_id = $1", [vint(categoryInternalId)])

                    // 删除分类本身（不删除磁盘文件）
                    let affected = db.execRaw("DELETE FROM categories WHERE id = $1", [vint(categoryInternalId)])
                    if (affected <= 0) {
                        return (false, deletedArchives, "Failed to delete category")
                    }
                    invalidateArchiveBasePath("categoryDelete:${catid}")
                    return (true, deletedArchives, "")
                } catch (e: Exception) {
                    logger.error("删除分类失败", ("error", e.message))
                    return (false, 0, e.message)
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
        let sql = "SELECT COUNT(*) FROM archives WHERE category_id = $1"
        let params: Array<Value> = [vint(categoryId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Int64>(sql, params, { r => r.getOrNullInt64(0) ?? 0 })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return 0
                } catch (e: Exception) {
                    logger.error("获取档案数量失败", ("error", e.message))
                    return 0
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
        let sql = "SELECT id, scan_path FROM categories WHERE enabled = true ORDER BY sort_order, id"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.raw<(Int64, String)>(sql, [], { row =>
                        let id = row.getOrNullInt64(0) ?? 0
                        let path = row.getOrNullText(1) ?? ""
                        return (id, path)
                    })
                } catch (e: Exception) {
                    logger.error("获取扫描路径失败", ("error", e.message))
                    return Array<(Int64, String)>()
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
        let sql = "SELECT id FROM categories WHERE catid = $1"
        let params: Array<Value> = [vtext(catid)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Int64>(sql, params, { r => r.getOrNullInt64(0) ?? 0 })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return 0
                } catch (e: Exception) {
                    logger.error("获取分类内部ID失败", ("error", e.message))
                    return 0
                }
            case None =>
                logger.error("无法连接到数据库")
                return 0
        }
    }

    // NOTE: category cover is stored as assets(kind='category_cover', file ext avif),
    // and referenced by categories.cover_asset_id.

}