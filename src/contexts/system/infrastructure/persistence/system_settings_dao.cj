package lanlu.contexts.system.infrastructure.persistence

import csorm.*
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

    private static let logger = getLogger("system_settings_dao")

    private static let SETTINGS_SELECT = """
        SELECT id, key, value, value_type, category, description,
               is_encrypted, created_at, updated_at
        FROM system_settings
    """

    private static func readSettingFromRow(row: Row): SystemSettingData {
        let data = SystemSettingData()
        data.id = row.getOrNullInt64(0) ?? 0
        data.key = row.getOrNullText(1) ?? ""
        data.value = row.getOrNullText(2) ?? ""
        data.valueType = row.getOrNullText(3) ?? "string"
        data.category = row.getOrNullText(4) ?? ""
        data.description = row.getOrNullJson(5) ?? ""
        data.isEncrypted = row.getOrNullBool(6) ?? false
        data.createdAt = row.getOrNullText(7) ?? ""
        data.updatedAt = row.getOrNullText(8) ?? ""
        return data
    }

    /**
     * 创建设置表
     */
    public static func createTable(): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    // 检查表是否存在
                    let checkSql = """
                        SELECT EXISTS (
                            SELECT 1 FROM information_schema.tables
                            WHERE table_name = 'system_settings'
                        )
                    """
                    let rows = db.raw<Bool>(checkSql, [], { r => r.getOrNullBool(0) ?? false })
                    var tableExists = false
                    if (rows.size > 0) {
                        tableExists = rows[0]
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
                        db.execRawSql(createTableSql)

                        // 创建索引
                        let indexSqls = [
                            "CREATE INDEX idx_system_settings_category ON system_settings (category)",
                            "CREATE INDEX idx_system_settings_key ON system_settings (key)"
                        ]
                        for (sql in indexSqls) {
                            try {
                                db.execRawSql(sql)
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
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 获取所有设置
     */
    public static func getAllSettings(): Array<SystemSettingData> {
        let sql = "${SETTINGS_SELECT} ORDER BY category, key"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.raw<SystemSettingData>(sql, [], { row => readSettingFromRow(row) })
                } catch (e: Exception) {
                    logger.error("获取所有设置失败", ("error", e.message))
                    return Array<SystemSettingData>()
                }
            case None =>
                logger.error("无法创建数据库连接")
                return Array<SystemSettingData>()
        }
    }

    /**
     * 根据键获取设置
     */
    public static func getSetting(key: String): Option<SystemSettingData> {
        let sql = "${SETTINGS_SELECT} WHERE key = $1"
        let params: Array<Value> = [vtext(key)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<SystemSettingData>(sql, params, { row => readSettingFromRow(row) })
                } catch (e: Exception) {
                    logger.error("获取设置失败", ("key", key), ("error", e.message))
                    return Option<SystemSettingData>.None
                }
            case None =>
                logger.error("无法创建数据库连接")
                return Option<SystemSettingData>.None
        }
    }

    /**
     * 启动阶段直接读取设置值。
     * - 不依赖 SystemSettingsService
     * - system_settings 表不存在时静默回退
     */
    public static func getBootstrapValue(key: String): Option<String> {
        let sql = """
            SELECT value
            FROM system_settings
            WHERE key = $1
            LIMIT 1
        """
        let params: Array<Value> = [vtext(key)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<String>(sql, params, { r => r.getOrNullText(0) ?? "" })
                } catch (e: Exception) {
                    logger.debug("启动阶段读取系统设置失败，回退到默认值", ("key", key), ("error", e.message))
                    return None
                }
            case None => return None
        }
    }

    /**
     * 根据分类获取设置
     */
    public static func getSettingsByCategory(category: String): Array<SystemSettingData> {
        let sql = "${SETTINGS_SELECT} WHERE category = $1 ORDER BY key"
        let params: Array<Value> = [vtext(category)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.raw<SystemSettingData>(sql, params, { row => readSettingFromRow(row) })
                } catch (e: Exception) {
                    logger.error("根据分类获取设置失败", ("category", category), ("error", e.message))
                    return Array<SystemSettingData>()
                }
            case None =>
                logger.error("无法创建数据库连接")
                return Array<SystemSettingData>()
        }
    }

    /**
     * 插入或更新设置
     */
    public static func upsertSetting(data: SystemSettingData): Bool {
        let updateSql = """
            UPDATE system_settings
            SET value = $1, value_type = $2, category = $3, description = $4::jsonb, is_encrypted = $5, updated_at = CURRENT_TIMESTAMP
            WHERE key = $6
        """
        let updateParams: Array<Value> = [
            vtext(data.value),
            vtext(data.valueType),
            vtext(data.category),
            vjson(data.description),
            vbool(data.isEncrypted),
            vtext(data.key)
        ]
        let insertSql = """
            INSERT INTO system_settings (key, value, value_type, category, description, is_encrypted, updated_at)
            SELECT $1, $2, $3, $4, $5::jsonb, $6, CURRENT_TIMESTAMP
            WHERE NOT EXISTS (
                SELECT 1 FROM system_settings WHERE key = $7
            )
        """
        let insertParams: Array<Value> = [
            vtext(data.key),
            vtext(data.value),
            vtext(data.valueType),
            vtext(data.category),
            vjson(data.description),
            vbool(data.isEncrypted),
            vtext(data.key)
        ]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let updated = db.execRaw(updateSql, updateParams)
                    if (updated <= 0) {
                        db.execRaw(insertSql, insertParams)
                    }
                    logger.info("更新设置", ("key", data.key))
                    return true
                } catch (e: Exception) {
                    logger.error("更新设置失败", ("key", data.key), ("error", e.message))
                    return false
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 批量插入或更新设置
     */
    public static func upsertSettings(settings: Array<SystemSettingData>): Bool {
        let updateSql = """
            UPDATE system_settings
            SET value = $1, value_type = $2, category = $3, description = $4::jsonb, is_encrypted = $5, updated_at = CURRENT_TIMESTAMP
            WHERE key = $6
        """
        let insertSql = """
            INSERT INTO system_settings (key, value, value_type, category, description, is_encrypted, updated_at)
            SELECT $1, $2, $3, $4, $5::jsonb, $6, CURRENT_TIMESTAMP
            WHERE NOT EXISTS (
                SELECT 1 FROM system_settings WHERE key = $7
            )
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    for (data in settings) {
                        let updateParams: Array<Value> = [
                            vtext(data.value),
                            vtext(data.valueType),
                            vtext(data.category),
                            vjson(data.description),
                            vbool(data.isEncrypted),
                            vtext(data.key)
                        ]
                        let updated = db.execRaw(updateSql, updateParams)
                        if (updated <= 0) {
                            let insertParams: Array<Value> = [
                                vtext(data.key),
                                vtext(data.value),
                                vtext(data.valueType),
                                vtext(data.category),
                                vjson(data.description),
                                vbool(data.isEncrypted),
                                vtext(data.key)
                            ]
                            db.execRaw(insertSql, insertParams)
                        }
                    }
                    logger.info("批量更新设置", ("count", settings.size.toString()))
                    return true
                } catch (e: Exception) {
                    logger.error("批量更新设置失败", ("error", e.message))
                    return false
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 删除设置
     */
    public static func deleteSetting(key: String): Bool {
        let sql = "DELETE FROM system_settings WHERE key = $1"
        let params: Array<Value> = [vtext(key)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    logger.info("删除设置", ("key", key))
                    return true
                } catch (e: Exception) {
                    logger.error("删除设置失败", ("key", key), ("error", e.message))
                    return false
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 检查设置是否存在
     */
    public static func settingExists(key: String): Bool {
        let sql = "SELECT COUNT(*) FROM system_settings WHERE key = $1"
        let params: Array<Value> = [vtext(key)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Int64>(sql, params, { r => r.getOrNullInt64(0) ?? 0 })
                    if (rows.size > 0) {
                        return rows[0] > 0
                    }
                    return false
                } catch (e: Exception) {
                    logger.error("检查设置存在性失败", ("key", key), ("error", e.message))
                    return false
                }
            case None =>
                logger.error("无法创建数据库连接")
                return false
        }
    }

    /**
     * 获取设置数量
     */
    public static func getSettingCount(): Int32 {
        let sql = "SELECT COUNT(*) FROM system_settings"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Int64>(sql, [], { r => r.getOrNullInt64(0) ?? 0 })
                    if (rows.size > 0) {
                        return Int32(rows[0])
                    }
                    return 0
                } catch (e: Exception) {
                    logger.error("获取设置数量失败", ("error", e.message))
                    return 0
                }
            case None =>
                logger.error("无法创建数据库连接")
                return 0
        }
    }
}