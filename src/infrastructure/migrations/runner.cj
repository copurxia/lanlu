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
}