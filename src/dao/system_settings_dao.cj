package lrr4cj.dao

import std.database.sql.*
import std.collection.*
import stdx.log.*
import lrr4cj.config.*
import lrr4cj.utils.*

/**
 * 系统设置数据模型
 */
public class SystemSettingData {
    public var id: Int64 = 0
    public var key: String = ""
    public var value: String = ""
    public var valueType: String = "string" // string, boolean, integer, long, path
    public var category: String = ""
    public var description: String = ""
    public var isEncrypted: Bool = false
    public var createdAt: String = ""
    public var updatedAt: String = ""

    public init() {}
}

/**
 * 系统设置数据访问对象 (DAO)
 */
public class SystemSettingsDao {

    /**
     * 创建设置表
     */
    public static func createTable(): Bool {
        let logger = getLogger("system_settings_dao")
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // 检查表是否存在
                    let checkTable = conn.prepareStatement("""
                        SELECT EXISTS (
                            SELECT FROM information_schema.tables
                            WHERE table_name = 'system_settings'
                        )
                    """)
                    let rs = checkTable.query()
                    var tableExists = false
                    try {
                        if (rs.next()) {
                            tableExists = rs.getOrNull<Bool>(0) ?? false
                        }
                    } finally {
                        rs.close()
                        checkTable.close()
                    }

                    if (!tableExists) {
                        logger.info("system_settings表不存在，创建新表")
                        let createTableSql = """
                            CREATE TABLE system_settings (
                                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                                key VARCHAR(255) NOT NULL UNIQUE,
                                value TEXT NOT NULL,
                                value_type VARCHAR(50) NOT NULL DEFAULT 'string',
                                category VARCHAR(100) NOT NULL,
                                description JSONB DEFAULT '{}',
                                is_encrypted BOOLEAN DEFAULT false,
                                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                            )
                        """
                        let stmt = conn.prepareStatement(createTableSql)
                        stmt.update()
                        stmt.close()

                        // 创建索引
                        let indexSqls = [
                            "CREATE INDEX idx_system_settings_category ON system_settings (category)",
                            "CREATE INDEX idx_system_settings_key ON system_settings (key)"
                        ]
                        for (sql in indexSqls) {
                            try {
                                let idxStmt = conn.prepareStatement(sql)
                                idxStmt.update()
                                idxStmt.close()
                            } catch (_: Exception) {
                                // 忽略索引创建错误
                            }
                        }
                        logger.info("system_settings表创建成功")
                    }
                    return true
                } catch (e: Exception) {
                    logger.error("创建system_settings表失败", ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        logger.warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 获取所有设置
     */
    public static func getAllSettings(): Array<SystemSettingData> {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, key, value, value_type, category, description,
                               is_encrypted, created_at, updated_at
                        FROM system_settings
                        ORDER BY category, key
                    """)
                    let rs = stmt.query()
                    var settingsList = ArrayList<SystemSettingData>()
                    try {
                        while (rs.next()) {
                            let data = SystemSettingData()
                            data.id = rs.getOrNull<Int64>(0) ?? 0
                            data.key = rs.getOrNull<String>(1) ?? ""
                            data.value = rs.getOrNull<String>(2) ?? ""
                            data.valueType = rs.getOrNull<String>(3) ?? "string"
                            data.category = rs.getOrNull<String>(4) ?? ""
                            data.description = rs.getOrNull<String>(5) ?? ""
                            data.isEncrypted = rs.getOrNull<Bool>(6) ?? false
                            data.createdAt = rs.getOrNull<String>(7) ?? ""
                            data.updatedAt = rs.getOrNull<String>(8) ?? ""
                            settingsList.add(data)
                        }
                        let size = settingsList.size
                        if (size > 0) {
                            var result = Array<SystemSettingData>(size, { _ => SystemSettingData() })
                            for (i in 0..size) {
                                result[i] = settingsList[i]
                            }
                            return result
                        }
                        return Array<SystemSettingData>()
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("system_settings_dao").error("获取所有设置失败", ("error", e.message))
                    return Array<SystemSettingData>()
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("system_settings_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("system_settings_dao").error("无法创建数据库连接")
                return Array<SystemSettingData>()
        }
    }

    /**
     * 根据键获取设置
     */
    public static func getSetting(key: String): Option<SystemSettingData> {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, key, value, value_type, category, description,
                               is_encrypted, created_at, updated_at
                        FROM system_settings WHERE key = ?
                    """)
                    stmt.set(0, key)
                    let rs = stmt.query()
                    try {
                        if (rs.next()) {
                            let data = SystemSettingData()
                            data.id = rs.getOrNull<Int64>(0) ?? 0
                            data.key = rs.getOrNull<String>(1) ?? ""
                            data.value = rs.getOrNull<String>(2) ?? ""
                            data.valueType = rs.getOrNull<String>(3) ?? "string"
                            data.category = rs.getOrNull<String>(4) ?? ""
                            data.description = rs.getOrNull<String>(5) ?? ""
                            data.isEncrypted = rs.getOrNull<Bool>(6) ?? false
                            data.createdAt = rs.getOrNull<String>(7) ?? ""
                            data.updatedAt = rs.getOrNull<String>(8) ?? ""
                            return Option<SystemSettingData>.Some(data)
                        }
                        return Option<SystemSettingData>.None
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("system_settings_dao").error("获取设置失败", ("key", key), ("error", e.message))
                    return Option<SystemSettingData>.None
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("system_settings_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("system_settings_dao").error("无法创建数据库连接")
                return Option<SystemSettingData>.None
        }
    }

    /**
     * 根据分类获取设置
     */
    public static func getSettingsByCategory(category: String): Array<SystemSettingData> {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, key, value, value_type, category, description,
                               is_encrypted, created_at, updated_at
                        FROM system_settings WHERE category = ?
                        ORDER BY key
                    """)
                    stmt.set(0, category)
                    let rs = stmt.query()
                    var settingsList = ArrayList<SystemSettingData>()
                    try {
                        while (rs.next()) {
                            let data = SystemSettingData()
                            data.id = rs.getOrNull<Int64>(0) ?? 0
                            data.key = rs.getOrNull<String>(1) ?? ""
                            data.value = rs.getOrNull<String>(2) ?? ""
                            data.valueType = rs.getOrNull<String>(3) ?? "string"
                            data.category = rs.getOrNull<String>(4) ?? ""
                            data.description = rs.getOrNull<String>(5) ?? ""
                            data.isEncrypted = rs.getOrNull<Bool>(6) ?? false
                            data.createdAt = rs.getOrNull<String>(7) ?? ""
                            data.updatedAt = rs.getOrNull<String>(8) ?? ""
                            settingsList.add(data)
                        }
                        let size = settingsList.size
                        if (size > 0) {
                            var result = Array<SystemSettingData>(size, { _ => SystemSettingData() })
                            for (i in 0..size) {
                                result[i] = settingsList[i]
                            }
                            return result
                        }
                        return Array<SystemSettingData>()
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("system_settings_dao").error("根据分类获取设置失败", ("category", category), ("error", e.message))
                    return Array<SystemSettingData>()
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("system_settings_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("system_settings_dao").error("无法创建数据库连接")
                return Array<SystemSettingData>()
        }
    }

    /**
     * 插入或更新设置
     */
    public static func upsertSetting(data: SystemSettingData): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO system_settings (key, value, value_type, category, description, is_encrypted, updated_at)
                        VALUES (?, ?, ?, ?, ?::jsonb, ?, CURRENT_TIMESTAMP)
                        ON CONFLICT (key)
                        DO UPDATE SET
                            value = EXCLUDED.value,
                            value_type = EXCLUDED.value_type,
                            category = EXCLUDED.category,
                            description = EXCLUDED.description,
                            is_encrypted = EXCLUDED.is_encrypted,
                            updated_at = CURRENT_TIMESTAMP
                    """)
                    stmt.set(0, data.key)
                    stmt.set(1, data.value)
                    stmt.set(2, data.valueType)
                    stmt.set(3, data.category)
                    stmt.set(4, data.description)
                    stmt.set(5, data.isEncrypted)
                    stmt.update()
                    stmt.close()
                    getLogger("system_settings_dao").info("更新设置", ("key", data.key))
                    return true
                } catch (e: Exception) {
                    getLogger("system_settings_dao").error("更新设置失败", ("key", data.key), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("system_settings_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("system_settings_dao").error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 批量插入或更新设置
     */
    public static func upsertSettings(settings: Array<SystemSettingData>): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO system_settings (key, value, value_type, category, description, is_encrypted, updated_at)
                        VALUES (?, ?, ?, ?, ?::jsonb, ?, CURRENT_TIMESTAMP)
                        ON CONFLICT (key)
                        DO UPDATE SET
                            value = EXCLUDED.value,
                            value_type = EXCLUDED.value_type,
                            category = EXCLUDED.category,
                            description = EXCLUDED.description,
                            is_encrypted = EXCLUDED.is_encrypted,
                            updated_at = CURRENT_TIMESTAMP
                    """)
                    for (data in settings) {
                        stmt.set(0, data.key)
                        stmt.set(1, data.value)
                        stmt.set(2, data.valueType)
                        stmt.set(3, data.category)
                        stmt.set(4, data.description)
                        stmt.set(5, data.isEncrypted)
                        stmt.update()
                    }
                    stmt.close()
                    getLogger("system_settings_dao").info("批量更新设置", ("count", settings.size.toString()))
                    return true
                } catch (e: Exception) {
                    getLogger("system_settings_dao").error("批量更新设置失败", ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("system_settings_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("system_settings_dao").error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 删除设置
     */
    public static func deleteSetting(key: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("DELETE FROM system_settings WHERE key = ?")
                    stmt.set(0, key)
                    stmt.update()
                    stmt.close()
                    getLogger("system_settings_dao").info("删除设置", ("key", key))
                    return true
                } catch (e: Exception) {
                    getLogger("system_settings_dao").error("删除设置失败", ("key", key), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("system_settings_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("system_settings_dao").error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 检查设置是否存在
     */
    public static func settingExists(key: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("SELECT COUNT(*) FROM system_settings WHERE key = ?")
                    stmt.set(0, key)
                    let rs = stmt.query()
                    try {
                        if (rs.next()) {
                            let count = rs.getOrNull<Int32>(0) ?? 0
                            return count > 0
                        }
                        return false
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("system_settings_dao").error("检查设置存在性失败", ("key", key), ("error", e.message))
                    return false
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("system_settings_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("system_settings_dao").error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 获取设置数量
     */
    public static func getSettingCount(): Int32 {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("SELECT COUNT(*) FROM system_settings")
                    let rs = stmt.query()
                    try {
                        if (rs.next()) {
                            return rs.getOrNull<Int32>(0) ?? 0
                        }
                        return 0
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("system_settings_dao").error("获取设置数量失败", ("error", e.message))
                    return 0
                } finally {
                    try {
                        conn.close()
                    } catch (closeError: Exception) {
                        getLogger("system_settings_dao").warn("关闭Connection失败: ${closeError.message}")
                    }
                }
            case None =>
                getLogger("system_settings_dao").error("无法创建数据库连接")
                return 0
        }
    }
}
