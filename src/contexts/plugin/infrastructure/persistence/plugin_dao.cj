package lanlu.contexts.plugin.infrastructure.persistence

import ace_orm.*
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

    /**
     * 获取所有插件
     */
    public static func getAllPlugins(): Array<PluginData> {
        try {
            let rows = DatabaseConfig.driver().query(
                "SELECT id, name, namespace, version, description, author, entry, plugin_type, tags, url_regex, source_id_regex, pre_hooks, after_hooks, permissions, icon, enabled, installed, has_schema, parameters, update_url, created_at, updated_at FROM plugins ORDER BY id", [])
            var plugins = ArrayList<PluginData>()
            for (r in rows) {
                let plugin = PluginData()
                plugin.id = Int32(r.getInt("id"))
                plugin.name = r.getText("name")
                plugin.namespace = r.getText("namespace")
                plugin.version = r.getText("version")
                plugin.description = r.getText("description")
                plugin.author = r.getText("author")
                plugin.entry = r.getText("entry")
                plugin.plugin_type = r.getText("plugin_type")
                plugin.tags = r.getText("tags")
                plugin.url_regex = r.getText("url_regex")
                plugin.source_id_regex = r.getText("source_id_regex")
                plugin.pre_hooks = r.getText("pre_hooks")
                plugin.after_hooks = r.getText("after_hooks")
                plugin.permissions = r.getText("permissions")
                plugin.icon = r.getText("icon")
                plugin.enabled = r.getBool("enabled")
                plugin.installed = r.getBool("installed")
                plugin.has_schema = r.getBool("has_schema")
                plugin.parameters = r.getText("parameters")
                plugin.update_url = r.getText("update_url")
                plugin.created_at = r.getText("created_at")
                plugin.updated_at = r.getText("updated_at")
                plugins.add(plugin)
            }
            return plugins.toArray()
        } catch (e: Exception) {
            getLogger("plugin_dao").error("查询插件失败", ("error", e.message))
            return Array<PluginData>()
        }
    }

    /**
     * 根据类型获取插件
     */
    public static func getPluginsByType(pluginType: String): Array<PluginData> {
        try {
            let rows = DatabaseConfig.driver().query(
                "SELECT id, name, namespace, version, description, author, entry, plugin_type, tags, url_regex, source_id_regex, pre_hooks, after_hooks, permissions, icon, enabled, installed, has_schema, parameters, update_url, created_at, updated_at FROM plugins WHERE LOWER(plugin_type) = LOWER($1) ORDER BY id", [DbText(pluginType)])
            var plugins = ArrayList<PluginData>()
            for (r in rows) {
                let plugin = PluginData()
                plugin.id = Int32(r.getInt("id"))
                plugin.name = r.getText("name")
                plugin.namespace = r.getText("namespace")
                plugin.version = r.getText("version")
                plugin.description = r.getText("description")
                plugin.author = r.getText("author")
                plugin.entry = r.getText("entry")
                plugin.plugin_type = r.getText("plugin_type")
                plugin.tags = r.getText("tags")
                plugin.url_regex = r.getText("url_regex")
                plugin.source_id_regex = r.getText("source_id_regex")
                plugin.pre_hooks = r.getText("pre_hooks")
                plugin.after_hooks = r.getText("after_hooks")
                plugin.permissions = r.getText("permissions")
                plugin.icon = r.getText("icon")
                plugin.enabled = r.getBool("enabled")
                plugin.installed = r.getBool("installed")
                plugin.has_schema = r.getBool("has_schema")
                plugin.parameters = r.getText("parameters")
                plugin.update_url = r.getText("update_url")
                plugin.created_at = r.getText("created_at")
                plugin.updated_at = r.getText("updated_at")
                plugins.add(plugin)
            }
            return plugins.toArray()
        } catch (e: Exception) {
            getLogger("plugin_dao").error("按类型查询插件失败", ("error", e.message), ("type", pluginType))
            return Array<PluginData>()
        }
    }

    /**
     * 根据namespace获取插件
     */
    public static func getPluginByNamespace(namespace: String): PluginData {
        try {
            let rows = DatabaseConfig.driver().query(
                "SELECT id, name, namespace, version, description, author, entry, plugin_type, tags, url_regex, source_id_regex, pre_hooks, after_hooks, permissions, icon, enabled, installed, has_schema, parameters, update_url, created_at, updated_at FROM plugins WHERE namespace = $1", [DbText(namespace)])
            if (rows.size > 0) {
                let r = rows[0]
                let plugin = PluginData()
                plugin.id = Int32(r.getInt("id"))
                plugin.name = r.getText("name")
                plugin.namespace = r.getText("namespace")
                plugin.version = r.getText("version")
                plugin.description = r.getText("description")
                plugin.author = r.getText("author")
                plugin.entry = r.getText("entry")
                plugin.plugin_type = r.getText("plugin_type")
                plugin.tags = r.getText("tags")
                plugin.url_regex = r.getText("url_regex")
                plugin.source_id_regex = r.getText("source_id_regex")
                plugin.pre_hooks = r.getText("pre_hooks")
                plugin.after_hooks = r.getText("after_hooks")
                plugin.permissions = r.getText("permissions")
                plugin.icon = r.getText("icon")
                plugin.enabled = r.getBool("enabled")
                plugin.installed = r.getBool("installed")
                plugin.has_schema = r.getBool("has_schema")
                plugin.parameters = r.getText("parameters")
                plugin.update_url = r.getText("update_url")
                plugin.created_at = r.getText("created_at")
                plugin.updated_at = r.getText("updated_at")
                return plugin
            }
        } catch (e: Exception) {
            getLogger("plugin_dao").error("根据namespace查询插件失败", ("error", e.message), ("namespace", namespace))
        }
        return PluginData()
    }

    /**
     * 创建插件记录
     */
    public static func create(plugin: PluginData): Bool {
        try {
            DatabaseConfig.driver().exec(
                "INSERT INTO plugins (name, namespace, version, description, author, entry, plugin_type, tags, url_regex, source_id_regex, pre_hooks, after_hooks, permissions, icon, enabled, installed, has_schema, parameters, update_url) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)",
                [DbText(plugin.name), DbText(plugin.namespace), DbText(plugin.version), DbText(plugin.description), DbText(plugin.author), DbText(plugin.entry), DbText(plugin.plugin_type), DbText(plugin.tags), DbText(plugin.url_regex), DbText(plugin.source_id_regex), DbText(plugin.pre_hooks), DbText(plugin.after_hooks), DbText(plugin.permissions), DbText(plugin.icon), DbBool(plugin.enabled), DbBool(plugin.installed), DbBool(plugin.has_schema), DbText(plugin.parameters), DbText(plugin.update_url)])
            return true
        } catch (e: Exception) {
            getLogger("plugin_dao").error("创建插件失败", ("error", e.message), ("namespace", plugin.namespace))
            return false
        }
    }

    /**
     * 更新插件记录
     */
    public static func update(plugin: PluginData): Bool {
        try {
            DatabaseConfig.driver().exec(
                "UPDATE plugins SET name = $1, version = $2, description = $3, author = $4, entry = $5, plugin_type = $6, tags = $7, url_regex = $8, source_id_regex = $9, pre_hooks = $10, after_hooks = $11, permissions = $12, icon = $13, enabled = $14, installed = $15, has_schema = $16, parameters = $17, update_url = $18, updated_at = CURRENT_TIMESTAMP WHERE namespace = $19",
                [DbText(plugin.name), DbText(plugin.version), DbText(plugin.description), DbText(plugin.author), DbText(plugin.entry), DbText(plugin.plugin_type), DbText(plugin.tags), DbText(plugin.url_regex), DbText(plugin.source_id_regex), DbText(plugin.pre_hooks), DbText(plugin.after_hooks), DbText(plugin.permissions), DbText(plugin.icon), DbBool(plugin.enabled), DbBool(plugin.installed), DbBool(plugin.has_schema), DbText(plugin.parameters), DbText(plugin.update_url), DbText(plugin.namespace)])
            return true
        } catch (e: Exception) {
            getLogger("plugin_dao").error("更新插件失败", ("error", e.message), ("namespace", plugin.namespace))
            return false
        }
    }

    /**
     * 删除插件记录
     */
    public static func delete(namespace: String): Bool {
        try {
            DatabaseConfig.driver().exec("DELETE FROM plugins WHERE namespace = $1", [DbText(namespace)])
            return true
        } catch (e: Exception) {
            getLogger("plugin_dao").error("删除插件失败", ("error", e.message), ("namespace", namespace))
            return false
        }
    }

    
    /**
     * 启用/禁用插件
     */
    public static func setEnabled(namespace: String, enabled: Bool): Bool {
        try {
            DatabaseConfig.driver().exec("UPDATE plugins SET enabled = $1, updated_at = CURRENT_TIMESTAMP WHERE namespace = $2", [DbBool(enabled), DbText(namespace)])
            return true
        } catch (e: Exception) {
            getLogger("plugin_dao").error("设置插件状态失败", ("error", e.message), ("namespace", namespace))
            return false
        }
    }

    /**
     * 检查插件是否存在
     */
    public static func exists(namespace: String): Bool {
        try {
            let rows = DatabaseConfig.driver().query("SELECT COUNT(*) FROM plugins WHERE namespace = $1", [DbText(namespace)])
            if (rows.size > 0) {
                let count = rows[0].getInt("count")
                return count > 0
            }
            return false
        } catch (e: Exception) {
            getLogger("plugin_dao").error("检查插件存在性失败", ("error", e.message), ("namespace", namespace))
            return false
        }
    }

    /**
     * 获取已启用的插件
     */
    public static func getEnabledPlugins(pluginType: String): Array<PluginData> {
        try {
            let rows = DatabaseConfig.driver().query(
                "SELECT id, name, namespace, version, description, author, entry, plugin_type, tags, url_regex, source_id_regex, pre_hooks, after_hooks, permissions, icon, enabled, installed, has_schema, parameters, update_url, created_at, updated_at FROM plugins WHERE LOWER(plugin_type) = LOWER($1) AND enabled = true ORDER BY id", [DbText(pluginType)])
            var plugins = ArrayList<PluginData>()
            for (r in rows) {
                let plugin = PluginData()
                plugin.id = Int32(r.getInt("id"))
                plugin.name = r.getText("name")
                plugin.namespace = r.getText("namespace")
                plugin.version = r.getText("version")
                plugin.description = r.getText("description")
                plugin.author = r.getText("author")
                plugin.entry = r.getText("entry")
                plugin.plugin_type = r.getText("plugin_type")
                plugin.tags = r.getText("tags")
                plugin.url_regex = r.getText("url_regex")
                plugin.source_id_regex = r.getText("source_id_regex")
                plugin.pre_hooks = r.getText("pre_hooks")
                plugin.after_hooks = r.getText("after_hooks")
                plugin.permissions = r.getText("permissions")
                plugin.icon = r.getText("icon")
                plugin.enabled = r.getBool("enabled")
                plugin.installed = r.getBool("installed")
                plugin.has_schema = r.getBool("has_schema")
                plugin.parameters = r.getText("parameters")
                plugin.update_url = r.getText("update_url")
                plugin.created_at = r.getText("created_at")
                plugin.updated_at = r.getText("updated_at")
                plugins.add(plugin)
            }
            return plugins.toArray()
        } catch (e: Exception) {
            getLogger("plugin_dao").error("查询已启用插件失败", ("error", e.message), ("type", pluginType))
            return Array<PluginData>()
        }
    }
}