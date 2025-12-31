package lrr4cj.dao

import std.database.sql.*
import lrr4cj.config.*
import lrr4cj.utils.*
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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                var filters: ArrayList<SmartFilterData> = ArrayList<SmartFilterData>()
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, name, translations, icon, query, sort_by, sort_order, date_from, date_to, newonly, untaggedonly, sort_order_num, enabled, created_at, updated_at FROM smart_filters WHERE enabled = true ORDER BY sort_order_num ASC, id ASC")
                    try {
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let filter = readFilterFromResultSet(rs)
                                filters.add(filter)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return filters.toArray()
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("查询智能分类失败", ("error", e.message))
                    return Array<SmartFilterData>()
                } finally {
                    DatabaseConfig.releasePooledConnection(handle)
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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                var filters: ArrayList<SmartFilterData> = ArrayList<SmartFilterData>()
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, name, translations, icon, query, sort_by, sort_order, date_from, date_to, newonly, untaggedonly, sort_order_num, enabled, created_at, updated_at FROM smart_filters ORDER BY sort_order_num ASC, id ASC")
                    try {
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let filter = readFilterFromResultSet(rs)
                                filters.add(filter)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return filters.toArray()
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("查询智能分类失败", ("error", e.message))
                    return Array<SmartFilterData>()
                } finally {
                    DatabaseConfig.releasePooledConnection(handle)
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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, name, translations, icon, query, sort_by, sort_order, date_from, date_to, newonly, untaggedonly, sort_order_num, enabled, created_at, updated_at FROM smart_filters WHERE id = ?")
                    try {
                        stmt.set(0, id)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return Some(readFilterFromResultSet(rs))
                            }
                            return None
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("查询智能分类失败", ("error", e.message))
                    return None
                } finally {
                    DatabaseConfig.releasePooledConnection(handle)
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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement(
                        "INSERT INTO smart_filters (name, translations, icon, query, sort_by, sort_order, date_from, date_to, newonly, untaggedonly, sort_order_num, enabled) VALUES (?, ?::jsonb, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id")
                    try {
                        stmt.set(0, filter.name)
                        stmt.set(1, filter.translations)
                        stmt.set(2, filter.icon)
                        stmt.set(3, filter.query)
                        stmt.set(4, filter.sort_by)
                        stmt.set(5, filter.sort_order)
                        stmt.set(6, filter.date_from)
                        stmt.set(7, filter.date_to)
                        stmt.set(8, filter.newonly)
                        stmt.set(9, filter.untaggedonly)
                        stmt.set(10, filter.sort_order_num)
                        stmt.set(11, filter.enabled)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let id = rs.getOrNull<Int64>(0) ?? 0
                                return Some(id)
                            }
                            return None
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("创建智能分类失败", ("error", e.message))
                    return None
                } finally {
                    DatabaseConfig.releasePooledConnection(handle)
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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement(
                        "UPDATE smart_filters SET name = ?, translations = ?::jsonb, icon = ?, query = ?, sort_by = ?, sort_order = ?, date_from = ?, date_to = ?, newonly = ?, untaggedonly = ?, sort_order_num = ?, enabled = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
                    try {
                        stmt.set(0, filter.name)
                        stmt.set(1, filter.translations)
                        stmt.set(2, filter.icon)
                        stmt.set(3, filter.query)
                        stmt.set(4, filter.sort_by)
                        stmt.set(5, filter.sort_order)
                        stmt.set(6, filter.date_from)
                        stmt.set(7, filter.date_to)
                        stmt.set(8, filter.newonly)
                        stmt.set(9, filter.untaggedonly)
                        stmt.set(10, filter.sort_order_num)
                        stmt.set(11, filter.enabled)
                        stmt.set(12, filter.id)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("更新智能分类失败", ("error", e.message))
                    return false
                } finally {
                    DatabaseConfig.releasePooledConnection(handle)
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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement("DELETE FROM smart_filters WHERE id = ?")
                    try {
                        stmt.set(0, id)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("删除智能分类失败", ("error", e.message))
                    return false
                } finally {
                    DatabaseConfig.releasePooledConnection(handle)
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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    for ((id, sortOrder) in orders) {
                        let stmt = conn.prepareStatement(
                            "UPDATE smart_filters SET sort_order_num = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
                        try {
                            stmt.set(0, sortOrder)
                            stmt.set(1, id)
                            stmt.update()
                        } finally {
                            stmt.close()
                        }
                    }
                    return true
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("批量更新排序顺序失败", ("error", e.message))
                    return false
                } finally {
                    DatabaseConfig.releasePooledConnection(handle)
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
        let handleOpt = DatabaseConfig.getPooledConnection()
        match (handleOpt) {
            case Some(handle) =>
                let conn = handle.connection
                try {
                    let stmt = conn.prepareStatement(
                        "UPDATE smart_filters SET enabled = NOT enabled, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
                    try {
                        stmt.set(0, id)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("smart_filter_dao").error("切换智能分类状态失败", ("error", e.message))
                    return false
                } finally {
                    DatabaseConfig.releasePooledConnection(handle)
                }
            case None =>
                getLogger("smart_filter_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 从 ResultSet 读取智能分类数据
     */
    private static func readFilterFromResultSet(rs: QueryResult): SmartFilterData {
        let filter = SmartFilterData()
        filter.id = rs.getOrNull<Int64>(0) ?? 0
        filter.name = rs.getOrNull<String>(1) ?? ""
        filter.translations = rs.getOrNull<String>(2) ?? "{}"
        filter.icon = rs.getOrNull<String>(3) ?? ""
        filter.query = rs.getOrNull<String>(4) ?? ""
        filter.sort_by = rs.getOrNull<String>(5) ?? ""
        filter.sort_order = rs.getOrNull<String>(6) ?? "desc"
        filter.date_from = rs.getOrNull<String>(7) ?? ""
        filter.date_to = rs.getOrNull<String>(8) ?? ""
        filter.newonly = rs.getOrNull<Bool>(9) ?? false
        filter.untaggedonly = rs.getOrNull<Bool>(10) ?? false
        filter.sort_order_num = rs.getOrNull<Int32>(11) ?? 0
        filter.enabled = rs.getOrNull<Bool>(12) ?? true
        filter.created_at = rs.getOrNull<String>(13) ?? ""
        filter.updated_at = rs.getOrNull<String>(14) ?? ""
        return filter
    }
}
