package lanlu.infrastructure.migrations

import ace_orm.*
import std.collection.*
import lanlu.shared.config.*
import lanlu.shared.utils.*

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
        if (!DataSourceManager.isInitialized()) {
            logger.error("DataSource not initialized")
            return false
        }
        let drv = DatabaseConfig.driver()
        try {
            // 1. 确保 schema_migrations 表存在
            if (!ensureMigrationsTable(drv)) {
                logger.error("Failed to create schema_migrations table")
                return false
            }

            // 2. 获取已执行的版本
            let applied = getAppliedVersions(drv)

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

                let success = migration.up(drv)
                if (!success) {
                    logger.error("Migration ${migration.version()} failed")
                    return false
                }

                // 记录成功的迁移
                if (!recordMigration(drv, migration.version(), migration.description())) {
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
    }

    /**
     * 确保 schema_migrations 表存在
     */
    public static func ensureMigrationsTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "schema_migrations")) {
            return true
        }

        logger.debug("Creating schema_migrations table")
        return MigrationHelpers.execUpdate(drv, """
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
    public static func getAppliedVersions(drv: Driver): HashSet<String> {
        var versions = HashSet<String>()
        try {
            let rows = drv.query("SELECT version FROM schema_migrations", [])
            for (r in rows) {
                let version = r.getText("version")
                if (version.size > 0) {
                    versions.add(version)
                }
            }
        } catch (e: Exception) {
            logger.error("getAppliedVersions failed: ${e.message}")
        }
        return versions
    }

    /**
     * 记录成功的迁移
     */
    public static func recordMigration(drv: Driver, version: String, description: String): Bool {
        try {
            drv.exec(
                "INSERT INTO schema_migrations (version, description) VALUES ($1, $2)",
                [DbText(version), DbText(description)]
            )
            return true
        } catch (e: Exception) {
            logger.error("Failed to record migration: ${e.message}")
            return false
        }
    }
}