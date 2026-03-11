package lanlu.infrastructure.migrations

import std.database.sql.*
import lanlu.shared.config.*
import lanlu.shared.utils.*

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
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    if (!MigrationRunner.ensureMigrationsTable(conn)) {
                        logger.error("Failed to create schema_migrations table")
                        return false
                    }

                    let applied = MigrationRunner.getAppliedVersions(conn)
                    let allMigrations = ExtensionMigrationRegistry.getAll()
                    let latestSchemaVersion = latestRegularSchemaVersion()

                    if (allMigrations.size == 0) {
                        logger.debug("No registered extension migrations")
                        return true
                    }

                    var ranAny = false
                    for (migration in allMigrations) {
                        if (applied.contains(migration.version())) {
                            continue
                        }

                        if (migration.targetSchemaVersion() != latestSchemaVersion) {
                            logger.error(
                                "Extension migration ${migration.version()} targets ${migration.targetSchemaVersion()} but latest schema is ${latestSchemaVersion}"
                            )
                            return false
                        }

                        if (!hasRequiredExtensions(conn, migration)) {
                            logger.info(
                                "Skipping extension migration ${migration.version()} until required extensions are enabled"
                            )
                            continue
                        }

                        logger.info(
                            "Running extension migration ${migration.version()}: ${migration.description()}"
                        )
                        let success = migration.up(conn)
                        if (!success) {
                            logger.error("Extension migration ${migration.version()} failed")
                            return false
                        }

                        if (!MigrationRunner.recordMigration(conn, migration.version(), migration.description())) {
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
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("Cannot connect to database")
                return false
        }
    }

    private static func hasRequiredExtensions(conn: Connection, migration: ExtensionMigration): Bool {
        for (extName in migration.requiredExtensions()) {
            if (MigrationHelpers.extensionInstalled(conn, extName)) {
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
        return true
    }

    private static func latestRegularSchemaVersion(): String {
        var latest = ""
        for (migration in MigrationRegistry.getAll()) {
            latest = migration.version()
        }
        return latest
    }
}
