package lanlu.infrastructure.migrations

import ace_orm.*

/**
 * 扩展迁移接口 - 依赖数据库扩展启用后再执行的迁移
 */
public interface ExtensionMigration {
    func version(): String
    func description(): String
    func requiredExtensions(): Array<String>
    func targetSchemaVersion(): String

    /**
     * 执行迁移
     * @param drv 数据库驱动(ACE-ORM,调用者管理事务)
     * @return true 如果成功，false 否则
     */
    func up(drv: Driver): Bool
}
