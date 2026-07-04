package lanlu.contexts.system.infrastructure.persistence

import ace_orm.*
import std.collection.*
import stdx.log.*
import lanlu.shared.config.*
import lanlu.shared.utils.*

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
        try {
            // 检查表是否存在
            let checkRows = DatabaseConfig.driver().query("""
                SELECT EXISTS (
                    SELECT 1 FROM information_schema.tables
                    WHERE table_name = 'system_settings'
                )
            """, [])
            var tableExists = false
            if (checkRows.size > 0) {
                tableExists = checkRows[0].getBool("exists")
            }

            if (!tableExists) {
                logger.debug("system_settings表不存在，创建新表")
                let createTableSql = """
                    CREATE TABLE system_settings (
                        id SERIAL PRIMARY KEY,
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
                DatabaseConfig.driver().exec(createTableSql, [])

                // 创建索引
                let indexSqls = [
                    "CREATE INDEX idx_system_settings_category ON system_settings (category)",
                    "CREATE INDEX idx_system_settings_key ON system_settings (key)"
                ]
                for (sql in indexSqls) {
                    try {
                        DatabaseConfig.driver().exec(sql, [])
                    } catch (_: Exception) {
                        // 忽略索引创建错误
                    }
                }
                logger.debug("system_settings表创建成功")
            }
            return true
        } catch (e: Exception) {
            logger.error("创建system_settings表失败", ("error", e.message))
            return false
        }
    }

    /**
     * 获取所有设置
     */
    public static func getAllSettings(): Array<SystemSettingData> {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, key, value, value_type, category, description,
                       is_encrypted, created_at, updated_at
                FROM system_settings
                ORDER BY category, key
            """, [])
            var settingsList = ArrayList<SystemSettingData>()
            for (r in rows) {
                let data = SystemSettingData()
                data.id = r.getInt("id")
                data.key = r.getText("key")
                data.value = r.getText("value")
                data.valueType = r.getText("value_type")
                data.category = r.getText("category")
                data.description = r.getJson("description")
                data.isEncrypted = r.getBool("is_encrypted")
                data.createdAt = r.getText("created_at")
                data.updatedAt = r.getText("updated_at")
                settingsList.add(data)
            }
            return settingsList.toArray()
        } catch (e: Exception) {
            getLogger("system_settings_dao").error("获取所有设置失败", ("error", e.message))
            return Array<SystemSettingData>()
        }
    }

    /**
     * 根据键获取设置
     */
    public static func getSetting(key: String): Option<SystemSettingData> {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, key, value, value_type, category, description,
                       is_encrypted, created_at, updated_at
                FROM system_settings WHERE key = $1
            """, [DbText(key)])
            if (rows.size > 0) {
                let r = rows[0]
                let data = SystemSettingData()
                data.id = r.getInt("id")
                data.key = r.getText("key")
                data.value = r.getText("value")
                data.valueType = r.getText("value_type")
                data.category = r.getText("category")
                data.description = r.getJson("description")
                data.isEncrypted = r.getBool("is_encrypted")
                data.createdAt = r.getText("created_at")
                data.updatedAt = r.getText("updated_at")
                return Option<SystemSettingData>.Some(data)
            }
            return Option<SystemSettingData>.None
        } catch (e: Exception) {
            getLogger("system_settings_dao").error("获取设置失败", ("key", key), ("error", e.message))
            return Option<SystemSettingData>.None
        }
    }

    /**
     * 启动阶段直接读取设置值。
     * - 不依赖 SystemSettingsService
     * - system_settings 表不存在时静默回退
     */
    public static func getBootstrapValue(key: String): Option<String> {
        let logger = getLogger("system_settings_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT value
                FROM system_settings
                WHERE key = $1
                LIMIT 1
            """, [DbText(key)])
            if (rows.size > 0) {
                let value = rows[0].getText("value")
                return Some(value)
            }
            return None
        } catch (e: Exception) {
            logger.debug("启动阶段读取系统设置失败，回退到默认值", ("key", key), ("error", e.message))
            return None
        }
    }

    /**
     * 根据分类获取设置
     */
    public static func getSettingsByCategory(category: String): Array<SystemSettingData> {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, key, value, value_type, category, description,
                       is_encrypted, created_at, updated_at
                FROM system_settings WHERE category = $1
                ORDER BY key
            """, [DbText(category)])
            var settingsList = ArrayList<SystemSettingData>()
            for (r in rows) {
                let data = SystemSettingData()
                data.id = r.getInt("id")
                data.key = r.getText("key")
                data.value = r.getText("value")
                data.valueType = r.getText("value_type")
                data.category = r.getText("category")
                data.description = r.getJson("description")
                data.isEncrypted = r.getBool("is_encrypted")
                data.createdAt = r.getText("created_at")
                data.updatedAt = r.getText("updated_at")
                settingsList.add(data)
            }
            return settingsList.toArray()
        } catch (e: Exception) {
            getLogger("system_settings_dao").error("根据分类获取设置失败", ("category", category), ("error", e.message))
            return Array<SystemSettingData>()
        }
    }

    /**
     * 插入或更新设置
     */
    public static func upsertSetting(data: SystemSettingData): Bool {
        try {
            let updated = DatabaseConfig.driver().exec("""
                UPDATE system_settings
                SET value = $1, value_type = $2, category = $3, description = $4::jsonb, is_encrypted = $5, updated_at = CURRENT_TIMESTAMP
                WHERE key = $6
            """, [DbText(data.value), DbText(data.valueType), DbText(data.category), DbText(data.description), DbBool(data.isEncrypted), DbText(data.key)])
            if (updated <= 0) {
                DatabaseConfig.driver().exec("""
                    INSERT INTO system_settings (key, value, value_type, category, description, is_encrypted, updated_at)
                    SELECT $1, $2, $3, $4, $5::jsonb, $6, CURRENT_TIMESTAMP
                    WHERE NOT EXISTS (
                        SELECT 1 FROM system_settings WHERE key = $7
                    )
                """, [DbText(data.key), DbText(data.value), DbText(data.valueType), DbText(data.category), DbText(data.description), DbBool(data.isEncrypted), DbText(data.key)])
            }
            getLogger("system_settings_dao").info("更新设置", ("key", data.key))
            return true
        } catch (e: Exception) {
            getLogger("system_settings_dao").error("更新设置失败", ("key", data.key), ("error", e.message))
            return false
        }
    }

    /**
     * 批量插入或更新设置
     */
    public static func upsertSettings(settings: Array<SystemSettingData>): Bool {
        try {
            for (data in settings) {
                let updated = DatabaseConfig.driver().exec("""
                    UPDATE system_settings
                    SET value = $1, value_type = $2, category = $3, description = $4::jsonb, is_encrypted = $5, updated_at = CURRENT_TIMESTAMP
                    WHERE key = $6
                """, [DbText(data.value), DbText(data.valueType), DbText(data.category), DbText(data.description), DbBool(data.isEncrypted), DbText(data.key)])
                if (updated <= 0) {
                    DatabaseConfig.driver().exec("""
                        INSERT INTO system_settings (key, value, value_type, category, description, is_encrypted, updated_at)
                        SELECT $1, $2, $3, $4, $5::jsonb, $6, CURRENT_TIMESTAMP
                        WHERE NOT EXISTS (
                            SELECT 1 FROM system_settings WHERE key = $7
                        )
                    """, [DbText(data.key), DbText(data.value), DbText(data.valueType), DbText(data.category), DbText(data.description), DbBool(data.isEncrypted), DbText(data.key)])
                }
            }
            getLogger("system_settings_dao").info("批量更新设置", ("count", settings.size.toString()))
            return true
        } catch (e: Exception) {
            getLogger("system_settings_dao").error("批量更新设置失败", ("error", e.message))
            return false
        }
    }

    /**
     * 删除设置
     */
    public static func deleteSetting(key: String): Bool {
        try {
            DatabaseConfig.driver().exec("DELETE FROM system_settings WHERE key = $1", [DbText(key)])
            getLogger("system_settings_dao").info("删除设置", ("key", key))
            return true
        } catch (e: Exception) {
            getLogger("system_settings_dao").error("删除设置失败", ("key", key), ("error", e.message))
            return false
        }
    }

    /**
     * 检查设置是否存在
     */
    public static func settingExists(key: String): Bool {
        try {
            let rows = DatabaseConfig.driver().query("SELECT COUNT(*) FROM system_settings WHERE key = $1", [DbText(key)])
            if (rows.size > 0) {
                let count = rows[0].getInt("count")
                return count > 0
            }
            return false
        } catch (e: Exception) {
            getLogger("system_settings_dao").error("检查设置存在性失败", ("key", key), ("error", e.message))
            return false
        }
    }

    /**
     * 获取设置数量
     */
    public static func getSettingCount(): Int32 {
        try {
            let rows = DatabaseConfig.driver().query("SELECT COUNT(*) FROM system_settings", [])
            if (rows.size > 0) {
                return Int32(rows[0].getInt("count"))
            }
            return 0
        } catch (e: Exception) {
            getLogger("system_settings_dao").error("获取设置数量失败", ("error", e.message))
            return 0
        }
    }
}