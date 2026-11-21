package lanlu.infrastructure.migrations

import csorm.*

/**
 * Migration 接口 - 所有迁移必须实现此接口
 */
public interface Migration {
    /**
     * 获取版本标识符 (如 "V001")
     */
    func version(): String

    /**
     * 获取人类可读的描述
     */
    func description(): String

    /**
     * 执行迁移
     * @param db csorm.Database 句柄(调用者管理事务)
     * @return true 如果成功，false 否则
     */
    func up(db: Database): Bool
}

/**
 * 适配器：把旧 Migration 包装为 csorm CsormMigration。
 * 保留旧迁移的 up(db) 逻辑原样，只改外壳，通过 SchemaManager.database() 取 db。
 * down() 抛不支持（旧迁移无 down）。
 */
public class MigrationAdapter <: CsormMigration {
    private let migration: Migration

    public init(migration: Migration) {
        this.migration = migration
    }

    public func version(): String { migration.version() }

    public func description(): String { migration.description() }

    public func up(mgr: SchemaManager): Unit {
        let db = mgr.database()
        let ok = migration.up(db)
        if (!ok) {
            throw Exception("Migration ${migration.version()} returned false")
        }
    }

    public func down(mgr: SchemaManager): Unit {
        throw Exception("Migration ${migration.version()} does not support down()")
    }
}

/**
 * 把旧 Migration 数组包装为 CsormMigration 数组。
 */
public func wrapMigrations(migrations: Array<Migration>): Array<CsormMigration> {
    Array<CsormMigration>(migrations.size, { i => MigrationAdapter(migrations[i]) })
}