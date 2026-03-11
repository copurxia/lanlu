package lanlu.infrastructure.migrations

import std.database.sql.*

/**
 * 扩展迁移接口 - 依赖数据库扩展启用后再执行的迁移
 */
public interface ExtensionMigration {
    /**
     * 获取版本标识符 (如 "V006")
     */
    func version(): String

    /**
     * 获取人类可读的描述
     */
    func description(): String

    /**
     * 获取所需的数据库扩展列表
     */
    func requiredExtensions(): Array<String>

    /**
     * 获取该扩展迁移所对齐的常规数据库 schema 版本
     */
    func targetSchemaVersion(): String

    /**
     * 执行迁移
     * @param conn 数据库连接（调用者管理事务）
     * @return true 如果成功，false 否则
     */
    func up(conn: Connection): Bool
}
