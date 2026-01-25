package lanlu.migrations

import std.database.sql.*
import std.collection.*
import lanlu.config.*
import lanlu.utils.*

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
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // 1. 确保 schema_migrations 表存在
                    if (!ensureMigrationsTable(conn)) {
                        logger.error("Failed to create schema_migrations table")
                        return false
                    }

                    // 2. 获取已执行的版本
                    let applied = getAppliedVersions(conn)

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

                        let success = migration.up(conn)
                        if (!success) {
                            logger.error("Migration ${migration.version()} failed")
                            return false
                        }

                        // 记录成功的迁移
                        if (!recordMigration(conn, migration.version(), migration.description())) {
                            logger.error("Failed to record migration ${migration.version()}")
                            return false
                        }

                        logger.info("Migration ${migration.version()} completed successfully")
                    }

                    return true
                } catch (e: Exception) {
                    logger.error("Migration error: ${e.message}")
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("Cannot connect to database")
                return false
        }
    }

    /**
     * 确保 schema_migrations 表存在
     */
    private static func ensureMigrationsTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "schema_migrations")) {
            return true
        }

        logger.debug("Creating schema_migrations table")
        return MigrationHelpers.execUpdate(conn, """
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
    private static func getAppliedVersions(conn: Connection): HashSet<String> {
        var versions = HashSet<String>()
        let stmt = conn.prepareStatement("SELECT version FROM schema_migrations")
        try {
            let rs = stmt.query()
            try {
                while (rs.next()) {
                    let version = rs.getOrNull<String>(0) ?? ""
                    if (version.size > 0) {
                        versions.add(version)
                    }
                }
            } finally {
                rs.close()
            }
        } finally {
            stmt.close()
        }
        return versions
    }

    /**
     * 记录成功的迁移
     */
    private static func recordMigration(conn: Connection, version: String, description: String): Bool {
        let stmt = conn.prepareStatement(
            "INSERT INTO schema_migrations (version, description) VALUES (?, ?)"
        )
        try {
            stmt.set(0, version)
            stmt.set(1, description)
            stmt.update()
            return true
        } catch (e: Exception) {
            logger.error("Failed to record migration: ${e.message}")
            return false
        } finally {
            stmt.close()
        }
    }
}
