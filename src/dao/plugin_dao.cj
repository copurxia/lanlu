package lrr4cj.dao

import std.database.sql.*
import lrr4cj.config.*
import lrr4cj.utils.*
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
    public var login_from: String = ""
    public var permissions: String = ""
    public var icon: String = ""                   // 插件图标，Base64编码的图片数据
    public var enabled: Bool = false
    public var installed: Bool = false
    public var has_schema: Bool = false          // 是否包含参数
    public var parameters: String = "[]"          // 带value的参数数组
    public var update_url: String = ""            // 插件更新地址
    public var created_at: String = ""
    public var updated_at: String = ""

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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>

                var plugins: ArrayList<PluginData> = ArrayList<PluginData>()
                let stmt = conn.prepareStatement(
                    "SELECT id, name, namespace, version, description, author, entry, plugin_type, tags, url_regex, login_from, permissions, icon, enabled, installed, has_schema, parameters, update_url, created_at, updated_at FROM plugins ORDER BY id")
                try {
                    let rs = stmt.query()

                    try {
                        while (rs.next()) {
                            let plugin = PluginData()
                            plugin.id = rs.getOrNull<Int32>(0) ?? 0
                            plugin.name = rs.getOrNull<String>(1) ?? ""
                            plugin.namespace = rs.getOrNull<String>(2) ?? ""
                            plugin.version = rs.getOrNull<String>(3) ?? ""
                            plugin.description = rs.getOrNull<String>(4) ?? ""
                            plugin.author = rs.getOrNull<String>(5) ?? ""
                            plugin.entry = rs.getOrNull<String>(6) ?? ""
                            plugin.plugin_type = rs.getOrNull<String>(7) ?? ""
                            plugin.tags = rs.getOrNull<String>(8) ?? ""
                            plugin.url_regex = rs.getOrNull<String>(9) ?? ""
                            plugin.login_from = rs.getOrNull<String>(10) ?? ""
                            let permissionsOpt = rs.getOrNull<String>(11)
                            plugin.permissions = match (permissionsOpt) {
                                case Some(value) => value
                                case None => ""
                            }
                            plugin.icon = rs.getOrNull<String>(12) ?? ""
                            plugin.enabled = rs.getOrNull<Bool>(13) ?? false
                            plugin.installed = rs.getOrNull<Bool>(14) ?? false
                            plugin.has_schema = rs.getOrNull<Bool>(15) ?? false
                            plugin.parameters = rs.getOrNull<String>(16) ?? "[]"
                            plugin.update_url = rs.getOrNull<String>(17) ?? ""
                            plugin.created_at = rs.getOrNull<String>(18) ?? ""
                            plugin.updated_at = rs.getOrNull<String>(19) ?? ""
                            plugins.add(plugin)
                        }
                    } finally {
                        try {
                            rs.close()
                        } catch (closeError: Exception) {
                            getLogger("plugin_dao").warn("关闭ResultSet失败: ${closeError.message}")
                        }
                    }

                    return plugins.toArray()
                } catch (e: Exception) {
                    getLogger("plugin_dao").error("查询插件失败", ("error", e.message))
                    return Array<PluginData>()
                } finally {
                    try {
                        stmt.close()
                    } catch (closeError: Exception) {
                        getLogger("plugin_dao").warn("关闭PreparedStatement失败: ${closeError.message}")
                    }
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("plugin_dao").warn("关闭数据库连接失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("plugin_dao").error("无法连接到数据库")
                return Array<PluginData>()
        }
    }

    /**
     * 根据类型获取插件
     */
    public static func getPluginsByType(pluginType: String): Array<PluginData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                var plugins: ArrayList<PluginData> = ArrayList<PluginData>()
                let stmt = conn.prepareStatement(
                    "SELECT id, name, namespace, version, description, author, entry, plugin_type, tags, url_regex, login_from, permissions, icon, enabled, installed, has_schema, parameters, update_url, created_at, updated_at FROM plugins WHERE LOWER(plugin_type) = LOWER(?) ORDER BY id")
                try {
                    stmt.set(0, pluginType)
                    let rs = stmt.query()

                    try {
                        while (rs.next()) {
                            let plugin = PluginData()
                            plugin.id = rs.getOrNull<Int32>(0) ?? 0
                            plugin.name = rs.getOrNull<String>(1) ?? ""
                            plugin.namespace = rs.getOrNull<String>(2) ?? ""
                            plugin.version = rs.getOrNull<String>(3) ?? ""
                            plugin.description = rs.getOrNull<String>(4) ?? ""
                            plugin.author = rs.getOrNull<String>(5) ?? ""
                            plugin.entry = rs.getOrNull<String>(6) ?? ""
                            plugin.plugin_type = rs.getOrNull<String>(7) ?? ""
                            plugin.tags = rs.getOrNull<String>(8) ?? ""
                            plugin.url_regex = rs.getOrNull<String>(9) ?? ""
                            plugin.login_from = rs.getOrNull<String>(10) ?? ""
                            let permissionsOpt = rs.getOrNull<String>(11)
                            plugin.permissions = match (permissionsOpt) {
                                case Some(value) => value
                                case None => ""
                            }
                            plugin.icon = rs.getOrNull<String>(12) ?? ""
                            plugin.enabled = rs.getOrNull<Bool>(13) ?? false
                            plugin.installed = rs.getOrNull<Bool>(14) ?? false
                            plugin.has_schema = rs.getOrNull<Bool>(15) ?? false
                            plugin.parameters = rs.getOrNull<String>(16) ?? "[]"
                            plugin.update_url = rs.getOrNull<String>(17) ?? ""
                            plugin.created_at = rs.getOrNull<String>(18) ?? ""
                            plugin.updated_at = rs.getOrNull<String>(19) ?? ""
                            plugins.add(plugin)
                        }
                    } finally {
                        try {
                            rs.close()
                        } catch (closeError: Exception) {
                            getLogger("plugin_dao").warn("关闭ResultSet失败: ${closeError.message}")
                        }
                    }

                    return plugins.toArray()
                } catch (e: Exception) {
                    getLogger("plugin_dao").error("按类型查询插件失败", ("error", e.message), ("type", pluginType))
                    return Array<PluginData>()
                } finally {
                    try {
                        stmt.close()
                    } catch (closeError: Exception) {
                        getLogger("plugin_dao").warn("关闭PreparedStatement失败: ${closeError.message}")
                    }
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("plugin_dao").warn("关闭数据库连接失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("plugin_dao").error("无法连接到数据库")
                return Array<PluginData>()
        }
    }

    /**
     * 根据namespace获取插件
     */
    public static func getPluginByNamespace(namespace: String): PluginData {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, name, namespace, version, description, author, entry, plugin_type, tags, url_regex, login_from, permissions, icon, enabled, installed, has_schema, parameters, update_url, created_at, updated_at FROM plugins WHERE namespace = ?")
                    try {
                        stmt.set(0, namespace)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let plugin = PluginData()
                                plugin.id = rs.getOrNull<Int32>(0) ?? 0
                                plugin.name = rs.getOrNull<String>(1) ?? ""
                                plugin.namespace = rs.getOrNull<String>(2) ?? ""
                                plugin.version = rs.getOrNull<String>(3) ?? ""
                                plugin.description = rs.getOrNull<String>(4) ?? ""
                                plugin.author = rs.getOrNull<String>(5) ?? ""
                                plugin.entry = rs.getOrNull<String>(6) ?? ""
                                plugin.plugin_type = rs.getOrNull<String>(7) ?? ""
                                plugin.tags = rs.getOrNull<String>(8) ?? ""
                                plugin.url_regex = rs.getOrNull<String>(9) ?? ""
                                plugin.login_from = rs.getOrNull<String>(10) ?? ""
                                let permissionsOpt = rs.getOrNull<String>(11)
                                plugin.permissions = match (permissionsOpt) {
                                    case Some(value) => value
                                    case None => ""
                                }
                                plugin.icon = rs.getOrNull<String>(12) ?? ""
                                plugin.enabled = rs.getOrNull<Bool>(13) ?? false
                                plugin.installed = rs.getOrNull<Bool>(14) ?? false
                                plugin.has_schema = rs.getOrNull<Bool>(15) ?? false
                                plugin.parameters = rs.getOrNull<String>(16) ?? "[]"
                                plugin.update_url = rs.getOrNull<String>(17) ?? ""
                                plugin.created_at = rs.getOrNull<String>(18) ?? ""
                                plugin.updated_at = rs.getOrNull<String>(19) ?? ""

                                return plugin
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("plugin_dao").error("根据namespace查询插件失败", ("error", e.message), ("namespace", namespace))
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None => getLogger("plugin_dao").error("无法连接到数据库")
        }
        return PluginData()
    }

    /**
     * 创建插件记录
     */
    public static func create(plugin: PluginData): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement(
                        "INSERT INTO plugins (name, namespace, version, description, author, entry, plugin_type, tags, url_regex, login_from, permissions, icon, enabled, installed, has_schema, parameters, update_url) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
                    try {
                        stmt.set(0, plugin.name)
                        stmt.set(1, plugin.namespace)
                        stmt.set(2, plugin.version)
                        stmt.set(3, plugin.description)
                        stmt.set(4, plugin.author)
                        stmt.set(5, plugin.entry)
                        stmt.set(6, plugin.plugin_type)
                        stmt.set(7, plugin.tags)
                        stmt.set(8, plugin.url_regex)
                        stmt.set(9, plugin.login_from)
                        stmt.set(10, plugin.permissions)
                        stmt.set(11, plugin.icon)
                        stmt.set(12, plugin.enabled)
                        stmt.set(13, plugin.installed)
                        stmt.set(14, plugin.has_schema)
                        stmt.set(15, plugin.parameters)
                        stmt.set(16, plugin.update_url)

                        stmt.update()
                        return true
                    } finally {
                        try { stmt.close() } catch (_: Exception) {}
                    }
                } catch (e: Exception) {
                    getLogger("plugin_dao").error("创建插件失败", ("error", e.message), ("namespace", plugin.namespace))
                    return false
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("plugin_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 更新插件记录
     */
    public static func update(plugin: PluginData): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                let stmt = conn.prepareStatement(
                    "UPDATE plugins SET name = ?, version = ?, description = ?, author = ?, entry = ?, plugin_type = ?, tags = ?, url_regex = ?, login_from = ?, permissions = ?, icon = ?, enabled = ?, installed = ?, has_schema = ?, parameters = ?, update_url = ?, updated_at = CURRENT_TIMESTAMP WHERE namespace = ?")

                stmt.set(0, plugin.name)
                stmt.set(1, plugin.version)
                stmt.set(2, plugin.description)
                stmt.set(3, plugin.author)
                stmt.set(4, plugin.entry)
                stmt.set(5, plugin.plugin_type)
                stmt.set(6, plugin.tags)
                stmt.set(7, plugin.url_regex)
                stmt.set(8, plugin.login_from)
                stmt.set(9, plugin.permissions)
                stmt.set(10, plugin.icon)
                stmt.set(11, plugin.enabled)
                stmt.set(12, plugin.installed)
                stmt.set(13, plugin.has_schema)
                stmt.set(14, plugin.parameters)
                stmt.set(15, plugin.update_url)
                stmt.set(16, plugin.namespace)

                stmt.update()
                conn.close()
                return true
            } catch (e: Exception) {
                getLogger("plugin_dao").error("更新插件失败", ("error", e.message), ("namespace", plugin.namespace))
                conn.close()
                return false
            }
            case None =>
                getLogger("plugin_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 删除插件记录
     */
    public static func delete(namespace: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                let stmt = conn.prepareStatement("DELETE FROM plugins WHERE namespace = ?")
                stmt.set(0, namespace)

                stmt.update()
                conn.close()
                return true
            } catch (e: Exception) {
                getLogger("plugin_dao").error("删除插件失败", ("error", e.message), ("namespace", namespace))
                conn.close()
                return false
            }
            case None =>
                getLogger("plugin_dao").error("无法连接到数据库")
                return false
        }
    }

    
    /**
     * 启用/禁用插件
     */
    public static func setEnabled(namespace: String, enabled: Bool): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("UPDATE plugins SET enabled = ?, updated_at = CURRENT_TIMESTAMP WHERE namespace = ?")
                    try {
                        stmt.set(0, enabled)
                        stmt.set(1, namespace)

                        stmt.update()
                        return true
                    } finally {
                        try { stmt.close() } catch (_: Exception) {}
                    }
                } catch (e: Exception) {
                    getLogger("plugin_dao").error("设置插件状态失败", ("error", e.message), ("namespace", namespace))
                    return false
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("plugin_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 检查插件是否存在
     */
    public static func exists(namespace: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("SELECT COUNT(*) FROM plugins WHERE namespace = ?")
                    try {
                        stmt.set(0, namespace)
                        let rs = stmt.query()
                        try {
                            var count: Int64 = 0
                            if (rs.next()) {
                                count = rs.getOrNull<Int64>(0) ?? 0
                            }
                            return count > 0
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("plugin_dao").error("检查插件存在性失败", ("error", e.message), ("namespace", namespace))
                    return false
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                getLogger("plugin_dao").error("无法连接到数据库")
                return false
        }
    }

    /**
     * 获取已启用的插件
     */
    public static func getEnabledPlugins(pluginType: String): Array<PluginData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                var plugins: ArrayList<PluginData> = ArrayList<PluginData>()
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, name, namespace, version, description, author, entry, plugin_type, tags, url_regex, login_from, permissions, icon, enabled, installed, has_schema, parameters, update_url, created_at, updated_at FROM plugins WHERE LOWER(plugin_type) = LOWER(?) AND enabled = true ORDER BY id")
                    stmt.set(0, pluginType)
                    let rs = stmt.query()

                    while (rs.next()) {
                        let plugin = PluginData()
                        plugin.id = rs.getOrNull<Int32>(0) ?? 0
                        plugin.name = rs.getOrNull<String>(1) ?? ""
                        plugin.namespace = rs.getOrNull<String>(2) ?? ""
                        plugin.version = rs.getOrNull<String>(3) ?? ""
                        plugin.description = rs.getOrNull<String>(4) ?? ""
                        plugin.author = rs.getOrNull<String>(5) ?? ""
                        plugin.entry = rs.getOrNull<String>(6) ?? ""
                        plugin.plugin_type = rs.getOrNull<String>(7) ?? ""
                        plugin.tags = rs.getOrNull<String>(8) ?? ""
                        plugin.url_regex = rs.getOrNull<String>(9) ?? ""
                        plugin.login_from = rs.getOrNull<String>(10) ?? ""
                        let permissionsOpt = rs.getOrNull<String>(11)
                        plugin.permissions = match (permissionsOpt) {
                                case Some(value) => value
                                case None => ""
                            }
                        plugin.icon = rs.getOrNull<String>(12) ?? ""
                        plugin.enabled = rs.getOrNull<Bool>(13) ?? false
                        plugin.installed = rs.getOrNull<Bool>(14) ?? false
                        plugin.has_schema = rs.getOrNull<Bool>(15) ?? false
                        plugin.parameters = rs.getOrNull<String>(16) ?? "[]"
                        plugin.update_url = rs.getOrNull<String>(17) ?? ""
                        plugin.created_at = rs.getOrNull<String>(18) ?? ""
                        plugin.updated_at = rs.getOrNull<String>(19) ?? ""
                        plugins.add(plugin)
                    }

                    conn.close()
                    return plugins.toArray()
                } catch (e: Exception) {
                    getLogger("plugin_dao").error("查询已启用插件失败", ("error", e.message), ("type", pluginType))
                    conn.close()
                    return Array<PluginData>()
                }
            case None =>
                getLogger("plugin_dao").error("无法连接到数据库")
                return Array<PluginData>()
        }
    }
}
