package lanlu.infrastructure.migrations

import std.collection.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import csorm.*

/**
 * 迁移执行器 - 执行待处理的迁移
 */
public class MigrationRunner {
    private static let logger = getLogger("migration_runner")

    /**
     * 运行所有待处理的迁移
     * @return true 如果所有迁移成功或无需迁移
     */
    public static func runPendingMigrations(): Bool {
        let dbOpt = DatabaseConfig.getDatabase()
        match (dbOpt) {
            case Some(db) =>
                try {
                    // 1. 确保 schema_migrations 表存在
                    if (!ensureMigrationsTable(db)) {
                        logger.error("Failed to create schema_migrations table")
                        return false
                    }

                    // 2. 获取已执行的版本
                    let applied = getAppliedVersions(db)

                    // 3. 获取所有注册的迁移
                    let allMigrations = MigrationRegistry.getAll()

                    // 4. 过滤待执行的迁移
                    var pending = ArrayList<Migration>()
                    for (m in allMigrations) {
                        if (!applied.contains(m.version())) {
                            pending.add(m)
                        }
                    }

                    if (pending.size == 0) {
                        logger.info("No pending migrations")
                        return true
                    }

                    logger.info("Found ${pending.size} pending migrations")

                    // 5. 执行每个待处理的迁移
                    for (migration in pending) {
                        logger.info("Running migration ${migration.version()}: ${migration.description()}")

                        let success = migration.up(db)
                        if (!success) {
                            logger.error("Migration ${migration.version()} failed")
                            return false
                        }

                        // 记录成功的迁移
                        if (!recordMigration(db, migration.version(), migration.description())) {
                            logger.error("Failed to record migration ${migration.version()}")
                            return false
                        }

                        logger.info("Migration ${migration.version()} completed successfully")
                    }

                    return true
                } catch (e: Exception) {
                    logger.error("Migration error: ${e.message}")
                    return false
                }
            case None =>
                logger.error("Cannot connect to database")
                return false
        }
    }

    /**
     * 确保 schema_migrations 表存在
     */
    public static func ensureMigrationsTable(db: Database): Bool {
        if (MigrationHelpers.tableExists(db, "schema_migrations")) {
            return true
        }
        logger.debug("Creating schema_migrations table")
        MigrationHelpers.execUpdate(db, """
            CREATE TABLE schema_migrations (
                version VARCHAR(10) PRIMARY KEY,
                description VARCHAR(255) NOT NULL,
                applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
    }

    /**
     * 获取已执行的迁移版本列表
     */
    public static func getAppliedVersions(db: Database): HashSet<String> {
        let versions = HashSet<String>()
        let rows = db.raw<String>("SELECT version FROM schema_migrations", [], { row => row.getText(0) })
        for (v in rows) {
            if (v.size > 0) { versions.add(v) }
        }
        versions
    }

    /**
     * 记录成功的迁移
     */
    public static func recordMigration(db: Database, version: String, description: String): Bool {
        try {
            db.execRaw(
                "INSERT INTO schema_migrations (version, description) VALUES ($1, $2)",
                [vtext(version), vtext(description)]
            )
            true
        } catch (e: Exception) {
            logger.error("Failed to record migration: ${e.message}")
            false
        }
    }

    // ===== csorm Migrator 集成（阶段四 L4 落地） =====

    /**
     * 用 csorm.Migrator 执行待处理的迁移。
     * 把旧 Migration 包装为 CsormMigration，经 csorm Migrator.up() 执行。
     * csorm Migrator 自动在事务内执行每条迁移 + 写 schema_migrations。
     *
     * 兼容性：csorm Migrator 创建的 schema_migrations 表只有 (version, applied_at)，
     * 但旧 runner 和扩展 runner 的 recordMigration 要写 description 列。
     * 故此方法在执行前自动确保 description 列存在（ADD COLUMN IF NOT EXISTS）
     * 并允许 NULL（csorm Migrator 的 recordApplied 不写 description）。
     */
    public static func runPendingMigrationsViaCsorm(): Bool {
        let dbOpt = DatabaseConfig.getDatabase()
        match (dbOpt) {
            case Some(db) =>
                try {
                    // 先确保旧 runner 的 schema_migrations 表存在（含 description 列）
                    if (!ensureMigrationsTable(db)) {
                        logger.error("Failed to create schema_migrations table")
                        return false
                    }
                    // 确保 description 列存在且允许 NULL
                    // （csorm Migrator 可能创建了只有 version+applied_at 的表，
                    //  旧 runner 和扩展 runner 的 recordMigration 需要 description 列）
                    MigrationHelpers.execUpdate(db,
                        "ALTER TABLE schema_migrations ADD COLUMN IF NOT EXISTS description VARCHAR(255)")
                    MigrationHelpers.execUpdate(db,
                        "ALTER TABLE schema_migrations ALTER COLUMN description DROP NOT NULL")
                    // 用 csorm Migrator 执行
                    let migrator = Migrator(db)
                    let allMigrations = MigrationRegistry.getAll()
                    // 转为数组并包装
                    var migArr = Array<Migration>(allMigrations.size, { _ =>
                        allMigrations[0]
                    })
                    var idx = 0
                    for (m in allMigrations) {
                        migArr[idx] = m
                        idx++
                    }
                    let wrapped = wrapMigrations(migArr)
                    let applied = migrator.up(wrapped)
                    if (applied.size > 0) {
                        logger.info("csorm Migrator applied ${applied.size} migrations")
                    } else {
                        logger.info("No pending migrations (csorm Migrator)")
                    }
                    true
                } catch (e: Exception) {
                    logger.error("csorm Migrator error: ${e.message}")
                    // 回退到旧 runner
                    logger.info("Falling back to legacy MigrationRunner")
                    runPendingMigrations()
                }
            case None =>
                logger.error("Cannot connect to database")
                false
        }
    }
}