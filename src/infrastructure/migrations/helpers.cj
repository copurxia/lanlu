package lanlu.infrastructure.migrations

import std.database.sql.*
import lanlu.shared.config.*
import lanlu.shared.utils.*

/**
 * 迁移辅助函数
 * 从 database.cj 提取的通用数据库操作函数
 */
public class MigrationHelpers {
    private static let logger = getLogger("migration_helpers")

    /**
     * 检查表是否存在
     */
    public static func tableExists(conn: Connection, tableName: String): Bool {
        let stmt = conn.prepareStatement(
            "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ?)"
        )
        try {
            stmt.set(0, tableName)
            let rs = stmt.query()
            try {
                var exists = false
                if (rs.next()) {
                    try {
                        exists = rs.getOrNull<Bool>(0) ?? false
                    } catch (_: Exception) {
                        let result = rs.getOrNull<Int32>(0) ?? 0
                        exists = result != 0
                    }
                }
                return exists
            } finally {
                rs.close()
            }
        } finally {
            stmt.close()
        }
    }

    /**
     * 检查列是否存在
     */
    public static func columnExists(conn: Connection, tableName: String, columnName: String): Bool {
        let stmt = conn.prepareStatement(
            "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = ? AND column_name = ?)"
        )
        try {
            stmt.set(0, tableName)
            stmt.set(1, columnName)
            let rs = stmt.query()
            try {
                var exists = false
                if (rs.next()) {
                    try {
                        exists = rs.getOrNull<Bool>(0) ?? false
                    } catch (_: Exception) {
                        let result = rs.getOrNull<Int32>(0) ?? 0
                        exists = result != 0
                    }
                }
                return exists
            } finally {
                rs.close()
            }
        } finally {
            stmt.close()
        }
    }

    /**
     * 检查索引是否存在
     */
    public static func indexExists(conn: Connection, indexName: String): Bool {
        let stmt = conn.prepareStatement(
            "SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = ?)"
        )
        try {
            stmt.set(0, indexName)
            let rs = stmt.query()
            try {
                var exists = false
                if (rs.next()) {
                    try {
                        exists = rs.getOrNull<Bool>(0) ?? false
                    } catch (_: Exception) {
                        let result = rs.getOrNull<Int32>(0) ?? 0
                        exists = result != 0
                    }
                }
                return exists
            } finally {
                rs.close()
            }
        } finally {
            stmt.close()
        }
    }

    /**
     * 检查数据库扩展是否已安装
     */
    public static func extensionInstalled(conn: Connection, extensionName: String): Bool {
        let stmt = conn.prepareStatement(
            "SELECT 1 FROM pg_extension WHERE extname = ? LIMIT 1"
        )
        try {
            stmt.set(0, extensionName)
            let rs = stmt.query()
            try {
                return rs.next()
            } finally {
                rs.close()
            }
        } catch (e: Exception) {
            logger.warn("Failed to query pg_extension", ("error", e.message), ("extension", extensionName))
            return false
        } finally {
            stmt.close()
        }
    }

    /**
     * 尝试自动安装数据库扩展
     * 使用独立连接执行，避免污染主迁移连接
     */
    public static func ensureExtensionInstalled(extensionName: String): Bool {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    if (extensionInstalled(conn, extensionName)) {
                        return true
                    }

                    logger.info("Attempting to install database extension ${extensionName}")
                    if (!execUpdate(conn, "CREATE EXTENSION IF NOT EXISTS ${extensionName}")) {
                        logger.warn("Failed to auto-install database extension", ("extension", extensionName))
                        return false
                    }

                    let installed = extensionInstalled(conn, extensionName)
                    if (!installed) {
                        logger.warn(
                            "Extension still unavailable after CREATE EXTENSION",
                            ("extension", extensionName)
                        )
                    }
                    return installed
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.warn("Cannot get DB connection for extension installation", ("extension", extensionName))
                return false
        }
    }

    /**
     * 检查视图是否存在
     */
    public static func viewExists(conn: Connection, viewName: String): Bool {
        let stmt = conn.prepareStatement(
            "SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'public' AND table_name = ?)"
        )
        try {
            stmt.set(0, viewName)
            let rs = stmt.query()
            try {
                var exists = false
                if (rs.next()) {
                    try {
                        exists = rs.getOrNull<Bool>(0) ?? false
                    } catch (_: Exception) {
                        let result = rs.getOrNull<Int32>(0) ?? 0
                        exists = result != 0
                    }
                }
                return exists
            } finally {
                rs.close()
            }
        } finally {
            stmt.close()
        }
    }

    /**
     * 执行更新语句
     */
    public static func execUpdate(conn: Connection, sql: String): Bool {
        try {
            let stmt = conn.prepareStatement(sql)
            try {
                stmt.update()
                return true
            } finally {
                stmt.close()
            }
        } catch (e: Exception) {
            logger.error("SQL execution failed: ${e.message}")
            return false
        }
    }

    /**
     * 如果列不存在则添加
     */
    public static func addColumnIfNotExists(
        conn: Connection,
        tableName: String,
        columnName: String,
        columnDef: String
    ): Bool {
        if (columnExists(conn, tableName, columnName)) {
            logger.debug("Column ${columnName} already exists in ${tableName}")
            return true
        }
        logger.debug("Adding column ${columnName} to ${tableName}")
        return execUpdate(conn, "ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${columnDef}")
    }

    /**
     * 如果索引不存在则创建
     */
    public static func createIndexIfNotExists(
        conn: Connection,
        indexName: String,
        tableName: String,
        columns: String
    ): Bool {
        if (indexExists(conn, indexName)) {
            logger.debug("Index ${indexName} already exists")
            return true
        }
        logger.debug("Creating index ${indexName} on ${tableName}")
        return execUpdate(conn, "CREATE INDEX ${indexName} ON ${tableName} (${columns})")
    }

    /**
     * 如果表不存在则创建
     */
    public static func createTableIfNotExists(
        conn: Connection,
        tableName: String,
        createSql: String
    ): Bool {
        if (tableExists(conn, tableName)) {
            logger.debug("Table ${tableName} already exists")
            return true
        }
        logger.debug("Creating table ${tableName}")
        return execUpdate(conn, createSql)
    }
}
