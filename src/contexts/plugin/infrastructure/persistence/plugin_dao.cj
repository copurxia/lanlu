package lanlu.contexts.plugin.infrastructure.persistence

import csorm.*
import lanlu.contexts.plugin.domain.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import std.collection.*
import stdx.log.*

/**
 * 插件数据结构
 */
public class PluginData {
    public var id: Int32 = 0
    public var name: String = ""
    public var namespace: String = ""
    public var version: String = ""
    public var description: String = ""
    public var author: String = ""
    public var entry: String = ""                  // 插件文件路径（相对于存储根目录，支持子目录）
    public var plugin_type: String = ""
    public var tags: String = ""
    public var url_regex: String = ""
    public var source_id_regex: String = ""
    public var pre_hooks: String = "[]"
    public var after_hooks: String = "[]"
    public var permissions: String = ""
    public var icon: String = ""                   // 插件图标，Base64编码的图片数据
    public var enabled: Bool = false
    public var installed: Bool = false
    public var has_schema: Bool = false          // 是否包含参数
    public var parameters: String = "[]"          // 带value的参数数组
    public var update_url: String = ""            // 插件更新地址
    public var created_at: String = ""
    public var updated_at: String = ""

    public mut prop pluginType: PluginType {
        get() {
            PluginType.fromDb(plugin_type)
        }
        set(value) {
            plugin_type = value.toDb()
        }
    }

    }

/**
 * 插件数据访问对象 (DAO)
 * 遵循ArchiveDao模式，负责处理所有与插件相关的数据库操作
 */
public class PluginDao {

    private static let logger = getLogger("plugin_dao")

    private static let PLUGIN_SELECT = "SELECT id, name, namespace, version, description, author, entry, plugin_type, tags, url_regex, source_id_regex, pre_hooks, after_hooks, permissions, icon, enabled, installed, has_schema, parameters, update_url, created_at, updated_at FROM plugins"

    private static func readPluginFromRow(row: Row): PluginData {
        let plugin = PluginData()
        plugin.id = row.getOrNullInt32(0) ?? 0
        plugin.name = row.getOrNullText(1) ?? ""
        plugin.namespace = row.getOrNullText(2) ?? ""
        plugin.version = row.getOrNullText(3) ?? ""
        plugin.description = row.getOrNullText(4) ?? ""
        plugin.author = row.getOrNullText(5) ?? ""
        plugin.entry = row.getOrNullText(6) ?? ""
        plugin.plugin_type = row.getOrNullText(7) ?? ""
        plugin.tags = row.getOrNullText(8) ?? ""
        plugin.url_regex = row.getOrNullText(9) ?? ""
        plugin.source_id_regex = row.getOrNullText(10) ?? ""
        plugin.pre_hooks = row.getOrNullText(11) ?? "[]"
        plugin.after_hooks = row.getOrNullText(12) ?? "[]"
        let permissionsOpt = row.getOrNullText(13)
        plugin.permissions = match (permissionsOpt) {
            case Some(value) => value
            case None => ""
        }
        plugin.icon = row.getOrNullText(14) ?? ""
        plugin.enabled = row.getOrNullBool(15) ?? false
        plugin.installed = row.getOrNullBool(16) ?? false
        plugin.has_schema = row.getOrNullBool(17) ?? false
        plugin.parameters = row.getOrNullText(18) ?? "[]"
        plugin.update_url = row.getOrNullText(19) ?? ""
        plugin.created_at = row.getOrNullText(20) ?? ""
        plugin.updated_at = row.getOrNullText(21) ?? ""
        return plugin
    }

    /**
     * 获取所有插件
     */
    public static func getAllPlugins(): Array<PluginData> {
        let sql = "${PLUGIN_SELECT} ORDER BY id"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.raw<PluginData>(sql, [], { row => readPluginFromRow(row) })
                } catch (e: Exception) {
                    logger.error("查询插件失败", ("error", e.message))
                    return Array<PluginData>()
                }
            case None =>
                logger.error("无法连接到数据库")
                return Array<PluginData>()
        }
    }

    /**
     * 根据类型获取插件
     */
    public static func getPluginsByType(pluginType: String): Array<PluginData> {
        let sql = "${PLUGIN_SELECT} WHERE LOWER(plugin_type) = LOWER($1) ORDER BY id"
        let params: Array<Value> = [vtext(pluginType)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.raw<PluginData>(sql, params, { row => readPluginFromRow(row) })
                } catch (e: Exception) {
                    logger.error("按类型查询插件失败", ("error", e.message), ("type", pluginType))
                    return Array<PluginData>()
                }
            case None =>
                logger.error("无法连接到数据库")
                return Array<PluginData>()
        }
    }

    /**
     * 根据namespace获取插件
     */
    public static func getPluginByNamespace(namespace: String): PluginData {
        let sql = "${PLUGIN_SELECT} WHERE namespace = $1"
        let params: Array<Value> = [vtext(namespace)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<PluginData>(sql, params, { row => readPluginFromRow(row) })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return PluginData()
                } catch (e: Exception) {
                    logger.error("根据namespace查询插件失败", ("error", e.message), ("namespace", namespace))
                    return PluginData()
                }
            case None =>
                logger.error("无法连接到数据库")
                return PluginData()
        }
    }

    /**
     * 创建插件记录
     */
    public static func create(plugin: PluginData): Bool {
        let params: Array<Value> = [
            vtext(plugin.name),
            vtext(plugin.namespace),
            vtext(plugin.version),
            vtext(plugin.description),
            vtext(plugin.author),
            vtext(plugin.entry),
            vtext(plugin.plugin_type),
            vtext(plugin.tags),
            vtext(plugin.url_regex),
            vtext(plugin.source_id_regex),
            vtext(plugin.pre_hooks),
            vtext(plugin.after_hooks),
            vtext(plugin.permissions),
            vtext(plugin.icon),
            vbool(plugin.enabled),
            vbool(plugin.installed),
            vbool(plugin.has_schema),
            vtext(plugin.parameters),
            vtext(plugin.update_url)
        ]
        let sql = "INSERT INTO plugins (name, namespace, version, description, author, entry, plugin_type, tags, url_regex, source_id_regex, pre_hooks, after_hooks, permissions, icon, enabled, installed, has_schema, parameters, update_url) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("创建插件失败", ("error", e.message), ("namespace", plugin.namespace))
                    return false
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    /**
     * 更新插件记录
     */
    public static func update(plugin: PluginData): Bool {
        let params: Array<Value> = [
            vtext(plugin.name),
            vtext(plugin.version),
            vtext(plugin.description),
            vtext(plugin.author),
            vtext(plugin.entry),
            vtext(plugin.plugin_type),
            vtext(plugin.tags),
            vtext(plugin.url_regex),
            vtext(plugin.source_id_regex),
            vtext(plugin.pre_hooks),
            vtext(plugin.after_hooks),
            vtext(plugin.permissions),
            vtext(plugin.icon),
            vbool(plugin.enabled),
            vbool(plugin.installed),
            vbool(plugin.has_schema),
            vtext(plugin.parameters),
            vtext(plugin.update_url),
            vtext(plugin.namespace)
        ]
        let sql = "UPDATE plugins SET name = $1, version = $2, description = $3, author = $4, entry = $5, plugin_type = $6, tags = $7, url_regex = $8, source_id_regex = $9, pre_hooks = $10, after_hooks = $11, permissions = $12, icon = $13, enabled = $14, installed = $15, has_schema = $16, parameters = $17, update_url = $18, updated_at = CURRENT_TIMESTAMP WHERE namespace = $19"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("更新插件失败", ("error", e.message), ("namespace", plugin.namespace))
                    return false
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    /**
     * 删除插件记录
     */
    public static func delete(namespace: String): Bool {
        let sql = "DELETE FROM plugins WHERE namespace = $1"
        let params: Array<Value> = [vtext(namespace)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("删除插件失败", ("error", e.message), ("namespace", namespace))
                    return false
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    
    /**
     * 启用/禁用插件
     */
    public static func setEnabled(namespace: String, enabled: Bool): Bool {
        let params: Array<Value> = [vbool(enabled), vtext(namespace)]
        let sql = "UPDATE plugins SET enabled = $1, updated_at = CURRENT_TIMESTAMP WHERE namespace = $2"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("设置插件状态失败", ("error", e.message), ("namespace", namespace))
                    return false
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    /**
     * 检查插件是否存在
     */
    public static func exists(namespace: String): Bool {
        let sql = "SELECT COUNT(*) FROM plugins WHERE namespace = $1"
        let params: Array<Value> = [vtext(namespace)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Int64>(sql, params, { r => r.getOrNullInt64(0) ?? 0 })
                    if (rows.size > 0) {
                        return rows[0] > 0
                    }
                    return false
                } catch (e: Exception) {
                    logger.error("检查插件存在性失败", ("error", e.message), ("namespace", namespace))
                    return false
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    /**
     * 获取已启用的插件
     */
    public static func getEnabledPlugins(pluginType: String): Array<PluginData> {
        let sql = "${PLUGIN_SELECT} WHERE LOWER(plugin_type) = LOWER($1) AND enabled = true ORDER BY id"
        let params: Array<Value> = [vtext(pluginType)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.raw<PluginData>(sql, params, { row => readPluginFromRow(row) })
                } catch (e: Exception) {
                    logger.error("查询已启用插件失败", ("error", e.message), ("type", pluginType))
                    return Array<PluginData>()
                }
            case None =>
                logger.error("无法连接到数据库")
                return Array<PluginData>()
        }
    }
}