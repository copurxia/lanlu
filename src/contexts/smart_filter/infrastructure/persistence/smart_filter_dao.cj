package lanlu.contexts.smart_filter.infrastructure.persistence

import ace_orm.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import std.collection.*
import stdx.log.*

/**
 * 智能分类数据结构
 * 用于存储管理员预设的快速筛选条件
 */
public class SmartFilterData {
    public var id: Int64 = 0
    public var name: String = ""           // 分类名称（默认名称）
    public var translations: String = "{}" // 多语言翻译 (JSONB)
    public var icon: String = ""           // 图标名称 (lucide-react 图标)
    public var query: String = ""          // 搜索关键词
    public var sort_by: String = ""        // 排序字段
    public var sort_order: String = "desc" // 排序顺序
    public var date_from: String = ""      // 开始日期 (相对天数，如 -7 表示7天前)
    public var date_to: String = ""        // 结束日期
    public var newonly: Bool = false       // 仅新档案
    public var untaggedonly: Bool = false  // 仅无标签档案
    public var sort_order_num: Int32 = 0   // 显示顺序
    public var enabled: Bool = true        // 是否启用
    public var created_at: String = ""
    public var updated_at: String = ""
}

/**
 * 智能分类数据访问对象 (DAO)
 */
public class SmartFilterDao {

    /**
     * 获取所有启用的智能分类（按排序顺序）
     */
    public static func getEnabledFilters(): Array<SmartFilterData> {
        try {
            let rows = DatabaseConfig.driver().query(
                "SELECT id, name, translations, icon, query, sort_by, sort_order, date_from, date_to, newonly, untaggedonly, sort_order_num, enabled, created_at, updated_at FROM smart_filters WHERE enabled = true ORDER BY sort_order_num ASC, id ASC", [])
            var filters = ArrayList<SmartFilterData>()
            for (r in rows) {
                let filter = readFilterFromRow(r)
                filters.add(filter)
            }
            return filters.toArray()
        } catch (e: Exception) {
            getLogger("smart_filter_dao").error("查询智能分类失败", ("error", e.message))
            return Array<SmartFilterData>()
        }
    }

    /**
     * 获取所有智能分类（管理用）
     */
    public static func getAllFilters(): Array<SmartFilterData> {
        try {
            let rows = DatabaseConfig.driver().query(
                "SELECT id, name, translations, icon, query, sort_by, sort_order, date_from, date_to, newonly, untaggedonly, sort_order_num, enabled, created_at, updated_at FROM smart_filters ORDER BY sort_order_num ASC, id ASC", [])
            var filters = ArrayList<SmartFilterData>()
            for (r in rows) {
                let filter = readFilterFromRow(r)
                filters.add(filter)
            }
            return filters.toArray()
        } catch (e: Exception) {
            getLogger("smart_filter_dao").error("查询智能分类失败", ("error", e.message))
            return Array<SmartFilterData>()
        }
    }

    /**
     * 根据 ID 获取智能分类
     */
    public static func getById(id: Int64): Option<SmartFilterData> {
        try {
            let rows = DatabaseConfig.driver().query(
                "SELECT id, name, translations, icon, query, sort_by, sort_order, date_from, date_to, newonly, untaggedonly, sort_order_num, enabled, created_at, updated_at FROM smart_filters WHERE id = $1",
                [DbInt(id)])
            if (rows.size > 0) {
                return Some(readFilterFromRow(rows[0]))
            }
            return None
        } catch (e: Exception) {
            getLogger("smart_filter_dao").error("查询智能分类失败", ("error", e.message))
            return None
        }
    }

    /**
     * 创建智能分类
     */
    public static func create(filter: SmartFilterData): Option<Int64> {
        try {
            let rows = DatabaseConfig.driver().query(
                "INSERT INTO smart_filters (name, translations, icon, query, sort_by, sort_order, date_from, date_to, newonly, untaggedonly, sort_order_num, enabled) VALUES ($1, $2::jsonb, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) RETURNING id",
                [DbText(filter.name), DbText(filter.translations), DbText(filter.icon), DbText(filter.query), DbText(filter.sort_by), DbText(filter.sort_order), DbText(filter.date_from), DbText(filter.date_to), DbBool(filter.newonly), DbBool(filter.untaggedonly), DbInt(Int64(filter.sort_order_num)), DbBool(filter.enabled)])
            if (rows.size > 0) {
                let id = rows[0].getInt("id")
                return Some(id)
            }
            return None
        } catch (e: Exception) {
            getLogger("smart_filter_dao").error("创建智能分类失败", ("error", e.message))
            return None
        }
    }

    /**
     * 更新智能分类
     */
    public static func update(filter: SmartFilterData): Bool {
        try {
            DatabaseConfig.driver().exec(
                "UPDATE smart_filters SET name = $1, translations = $2::jsonb, icon = $3, query = $4, sort_by = $5, sort_order = $6, date_from = $7, date_to = $8, newonly = $9, untaggedonly = $10, sort_order_num = $11, enabled = $12, updated_at = CURRENT_TIMESTAMP WHERE id = $13",
                [DbText(filter.name), DbText(filter.translations), DbText(filter.icon), DbText(filter.query), DbText(filter.sort_by), DbText(filter.sort_order), DbText(filter.date_from), DbText(filter.date_to), DbBool(filter.newonly), DbBool(filter.untaggedonly), DbInt(Int64(filter.sort_order_num)), DbBool(filter.enabled), DbInt(filter.id)])
            return true
        } catch (e: Exception) {
            getLogger("smart_filter_dao").error("更新智能分类失败", ("error", e.message))
            return false
        }
    }

    /**
     * 删除智能分类
     */
    public static func delete(id: Int64): Bool {
        try {
            DatabaseConfig.driver().exec("DELETE FROM smart_filters WHERE id = $1", [DbInt(id)])
            return true
        } catch (e: Exception) {
            getLogger("smart_filter_dao").error("删除智能分类失败", ("error", e.message))
            return false
        }
    }

    /**
     * 批量更新排序顺序
     */
    public static func batchUpdateSortOrder(orders: Array<(Int64, Int32)>): Bool {
        try {
            for ((id, sortOrder) in orders) {
                DatabaseConfig.driver().exec(
                    "UPDATE smart_filters SET sort_order_num = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2",
                    [DbInt(Int64(sortOrder)), DbInt(id)])
            }
            return true
        } catch (e: Exception) {
            getLogger("smart_filter_dao").error("批量更新排序顺序失败", ("error", e.message))
            return false
        }
    }

    /**
     * 切换启用状态
     */
    public static func toggleEnabled(id: Int64): Bool {
        try {
            DatabaseConfig.driver().exec(
                "UPDATE smart_filters SET enabled = NOT enabled, updated_at = CURRENT_TIMESTAMP WHERE id = $1",
                [DbInt(id)])
            return true
        } catch (e: Exception) {
            getLogger("smart_filter_dao").error("切换智能分类状态失败", ("error", e.message))
            return false
        }
    }

    /**
     * 从 Row 读取智能分类数据
     */
    private static func readFilterFromRow(r: Row): SmartFilterData {
        let filter = SmartFilterData()
        filter.id = r.getInt("id")
        filter.name = r.getText("name")
        filter.translations = r.getJson("translations")
        if (filter.translations.size == 0) {
            filter.translations = "{}"
        }
        filter.icon = r.getText("icon")
        filter.query = r.getText("query")
        filter.sort_by = r.getText("sort_by")
        filter.sort_order = r.getText("sort_order")
        if (filter.sort_order.size == 0) {
            filter.sort_order = "desc"
        }
        filter.date_from = r.getText("date_from")
        filter.date_to = r.getText("date_to")
        filter.newonly = r.getBool("newonly")
        filter.untaggedonly = r.getBool("untaggedonly")
        filter.sort_order_num = Int32(r.getInt("sort_order_num"))
        filter.enabled = r.getBool("enabled")
        filter.created_at = r.getText("created_at")
        filter.updated_at = r.getText("updated_at")
        return filter
    }
}