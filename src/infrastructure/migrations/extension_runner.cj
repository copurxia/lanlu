package lanlu.infrastructure.migrations

import lanlu.shared.config.*
import lanlu.shared.utils.*
import csorm.*

/**
 * 扩展迁移执行器 - 仅在所需数据库扩展已启用时执行迁移
 */
public class ExtensionMigrationRunner {
    private static let logger = getLogger("extension_migration_runner")

    /**
     * 运行所有已满足前置条件的扩展迁移
     * @return true 如果所有可执行迁移成功或当前无需执行
     */
    public static func runReadyMigrations(): Bool {
        let dbOpt = DatabaseConfig.getDatabase()
        match (dbOpt) {
            case Some(db) =>
                try {
                    if (!MigrationRunner.ensureMigrationsTable(db)) {
                        logger.error("Failed to create schema_migrations table")
                        return false
                    }

                    let applied = MigrationRunner.getAppliedVersions(db)
                    let allMigrations = ExtensionMigrationRegistry.getAll()
                    if (allMigrations.size == 0) {
                        logger.debug("No registered extension migrations")
                        return true
                    }

                    var ranAny = false
                    for (migration in allMigrations) {
                        if (applied.contains(migration.version())) {
                            continue
                        }

                        if (!applied.contains(migration.targetSchemaVersion())) {
                            logger.error(
                                "Extension migration ${migration.version()} requires base schema ${migration.targetSchemaVersion()} but it is not applied"
                            )
                            return false
                        }

                        if (!hasRequiredExtensions(db, migration)) {
                            logger.info(
                                "Skipping extension migration ${migration.version()} until required extensions are enabled"
                            )
                            continue
                        }

                        logger.info(
                            "Running extension migration ${migration.version()}: ${migration.description()}"
                        )
                        let success = migration.up(db)
                        if (!success) {
                            logger.error("Extension migration ${migration.version()} failed")
                            return false
                        }

                        if (!MigrationRunner.recordMigration(db, migration.version(), migration.description())) {
                            logger.error("Failed to record extension migration ${migration.version()}")
                            return false
                        }

                        logger.info("Extension migration ${migration.version()} completed successfully")
                        ranAny = true
                    }

                    if (!ranAny) {
                        logger.info("No ready extension migrations")
                    }
                    return true
                } catch (e: Exception) {
                    logger.error("Extension migration error: ${e.message}")
                    return false
                }
            case None =>
                logger.error("Cannot connect to database")
                return false
        }
    }

    private static func hasRequiredExtensions(db: Database, migration: ExtensionMigration): Bool {
        for (extName in migration.requiredExtensions()) {
            if (MigrationHelpers.extensionInstalled(db, extName)) {
                continue
            }

            if (MigrationHelpers.ensureExtensionInstalled(extName)) {
                logger.info(
                    "Auto-installed required extension ${extName} for migration ${migration.version()}"
                )
                continue
            }

            logger.info(
                "Extension migration ${migration.version()} is waiting for extension ${extName}"
            )
            return false
        }
        true
    }
}