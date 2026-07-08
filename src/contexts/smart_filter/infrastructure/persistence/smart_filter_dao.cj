package lanlu.contexts.smart_filter.infrastructure.persistence

import csorm.*
import postgresql_driver.*
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
        let sql = "SELECT id, name, translations, icon, query, sort_by, sort_order, date_from, date_to, newonly, untaggedonly, sort_order_num, enabled, created_at, updated_at FROM smart_filters WHERE enabled = true ORDER BY sort_order_num ASC, id ASC"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.raw<SmartFilterData>(sql, [], { row => readFilterFromRow(row) })
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("查询智能分类失败", ("error", e.message))
                    return Array<SmartFilterData>()
                }
            case None =>
                getLogger("smart_filter_dao").error("无法连接到数据库")
                return Array<SmartFilterData>()
        }
    }

    /**
     * 获取所有智能分类（管理用）
     */
    public static func getAllFilters(): Array<SmartFilterData> {
        let sql = "SELECT id, name, translations, icon, query, sort_by, sort_order, date_from, date_to, newonly, untaggedonly, sort_order_num, enabled, created_at, updated_at FROM smart_filters ORDER BY sort_order_num ASC, id ASC"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.raw<SmartFilterData>(sql, [], { row => readFilterFromRow(row) })
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("查询智能分类失败", ("error", e.message))
                    return Array<SmartFilterData>()
                }
            case None =>
                getLogger("smart_filter_dao").error("无法连接到数据库")
                return Array<SmartFilterData>()
        }
    }

    /**
     * 根据 ID 获取智能分类
     */
    public static func getById(id: Int64): Option<SmartFilterData> {
        let sql = "SELECT id, name, translations, icon, query, sort_by, sort_order, date_from, date_to, newonly, untaggedonly, sort_order_num, enabled, created_at, updated_at FROM smart_filters WHERE id = $1"
        let params: Array<Value> = [vint(id)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<SmartFilterData>(sql, params, { row => readFilterFromRow(row) })
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("查询智能分类失败", ("error", e.message))
                    return None
                }
            case None =>
                getLogger("smart_filter_dao").error("无法连接到数据库")
                return None
        }
    }

    /**
     * 创建智能分类
     */
    public static func create(filter: SmartFilterData): Option<Int64> {
        let sql = "INSERT INTO smart_filters (name, translations, icon, query, sort_by, sort_order, date_from, date_to, newonly, untaggedonly, sort_order_num, enabled) VALUES ($1, $2::jsonb, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) RETURNING id"
        let params: Array<Value> = [
            vtext(filter.name),
            vjson(filter.translations),
            vtext(filter.icon),
            vtext(filter.query),
            vtext(filter.sort_by),
            vtext(filter.sort_order),
            vtext(filter.date_from),
            vtext(filter.date_to),
            vbool(filter.newonly),
            vbool(filter.untaggedonly),
            vint(Int64(filter.sort_order_num)),
            vbool(filter.enabled)
        ]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let idOpt = db.rawOne<Int64>(sql, params, { r => r.getInt64(0) })
                    return idOpt
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("创建智能分类失败", ("error", e.message))
                    return None
                }
            case None =>
                getLogger("smart_filter_dao").error("无法连接到数据库")
                return None
        }
    }

    /**
     * 更新智能分类
     */
    public static func update(filter: SmartFilterData): Bool {
        let sql = "UPDATE smart_filters SET name = $1, translations = $2::jsonb, icon = $3, query = $4, sort_by = $5, sort_order = $6, date_from = $7, date_to = $8, newonly = $9, untaggedonly = $10, sort_order_num = $11, enabled = $12, updated_at = CURRENT_TIMESTAMP WHERE id = $13"
        let params: Array<Value> = [
            vtext(filter.name),
            vjson(filter.translations),
            vtext(filter.icon),
            vtext(filter.query),
            vtext(filter.sort_by),
            vtext(filter.sort_order),
            vtext(filter.date_from),
            vtext(filter.date_to),
            vbool(filter.newonly),
            vbool(filter.untaggedonly),
            vint(Int64(filter.sort_order_num)),
            vbool(filter.enabled),
            vint(filter.id)
        ]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("更新智能分类失败", ("error", e.message))
                    return false
                }
            case None =>
                getLogger("smart_filter_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 删除智能分类
     */
    public static func delete(id: Int64): Bool {
        let sql = "DELETE FROM smart_filters WHERE id = $1"
        let params: Array<Value> = [vint(id)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("删除智能分类失败", ("error", e.message))
                    return false
                }
            case None =>
                getLogger("smart_filter_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 批量更新排序顺序
     */
    public static func batchUpdateSortOrder(orders: Array<(Int64, Int32)>): Bool {
        let sql = "UPDATE smart_filters SET sort_order_num = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    for ((id, sortOrder) in orders) {
                        db.execRaw(sql, [vint(Int64(sortOrder)), vint(id)])
                    }
                    return true
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("批量更新排序顺序失败", ("error", e.message))
                    return false
                }
            case None =>
                getLogger("smart_filter_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 切换启用状态
     */
    public static func toggleEnabled(id: Int64): Bool {
        let sql = "UPDATE smart_filters SET enabled = NOT enabled, updated_at = CURRENT_TIMESTAMP WHERE id = $1"
        let params: Array<Value> = [vint(id)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("切换智能分类状态失败", ("error", e.message))
                    return false
                }
            case None =>
                getLogger("smart_filter_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 从 Row 读取智能分类数据
     */
    private static func readFilterFromRow(row: Row): SmartFilterData {
        let filter = SmartFilterData()
        filter.id = row.getOrNullInt64(0) ?? 0
        filter.name = row.getOrNullText(1) ?? ""
        filter.translations = row.getOrNullJson(2) ?? "{}"
        filter.icon = row.getOrNullText(3) ?? ""
        filter.query = row.getOrNullText(4) ?? ""
        filter.sort_by = row.getOrNullText(5) ?? ""
        filter.sort_order = row.getOrNullText(6) ?? "desc"
        filter.date_from = row.getOrNullText(7) ?? ""
        filter.date_to = row.getOrNullText(8) ?? ""
        filter.newonly = row.getOrNullBool(9) ?? false
        filter.untaggedonly = row.getOrNullBool(10) ?? false
        filter.sort_order_num = row.getOrNullInt32(11) ?? 0
        filter.enabled = row.getOrNullBool(12) ?? true
        filter.created_at = row.getOrNullText(13) ?? ""
        filter.updated_at = row.getOrNullText(14) ?? ""
        return filter
    }

    // ===== 阶段三 Expr 落地：用 Expr 构建动态筛选查询 =====

    /**
     * 根据智能筛选条件，用 csorm Expr 构建归档查询的 WHERE 子句。
     * 返回 (sql_fragment, params)，可拼入主查询。
     * 占位符由 Expr 自动续编，消除手拼 $n 错位风险。
     */
    public static func buildExprFilter(filter: SmartFilterData): (String, Array<Value>) {
        var conds = ArrayList<Cond>()
        // newonly：只显示未读
        if (filter.newonly) {
            conds.add(rawCond("NOT EXISTS (SELECT 1 FROM user_archive_status uas JOIN archives a ON a.id=uas.archive_id WHERE a.arcid=archive_metadata_search.arcid AND uas.user_id=? AND uas.is_new=false)", [vint(0)]))
        }
        // untaggedonly：只显示无标签
        if (filter.untaggedonly) {
            conds.add(rawCond("NOT EXISTS (SELECT 1 FROM metadata_objects mo JOIN metadata_tags mt ON mt.metadata_id=mo.id WHERE mo.entity_type='archive' AND mo.entity_id=archive_metadata_search.arcid)", []))
        }
        // 日期范围
        if (filter.date_from.size > 0) {
            conds.add(exprCond(expr("release_at").gte(vtext(filter.date_from))))
        }
        if (filter.date_to.size > 0) {
            conds.add(exprCond(expr("release_at").lte(vtext(filter.date_to))))
        }
        if (conds.size == 0) {
            return ("", Array<Value>())
        }
        // 合并条件
        var combined = conds[0]
        for (i in 1..conds.size) {
            combined = all([combined, conds[i]])
        }
        let params = ArrayList<Value>()
        let ph = Placeholder()
        let frag = renderCond(combined, params, ph)
        // ArrayList → Array
        let sz = params.size
        var outParams: Array<Value> = Array<Value>(sz, { _ => vnull() })
        var idx = 0
        for (p in params) {
            if (idx < sz) {
                outParams[idx] = p
            }
            idx++
        }
        (frag, outParams)
    }
}