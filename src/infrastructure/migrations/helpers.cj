package lanlu.infrastructure.migrations

import lanlu.shared.config.*
import lanlu.shared.utils.*
import csorm.*

/**
 * 迁移辅助函数 —— 基于 csorm.Database 的通用 DDL/检查操作。
 * 替代旧 std.database.sql.Connection 版本：conn: Connection → db: Database，
 * ? 占位符 → $1..$n，rs.getOrNull<T>(i) → row.getOrNullXxx(i)。
 */
public class MigrationHelpers {
    private static let logger = getLogger("migration_helpers")

    /**
     * 检查表是否存在
     */
    public static func tableExists(db: Database, tableName: String): Bool {
        match (db.rawOne<Bool>(
            "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = $1)",
            [vtext(tableName)],
            { row => row.getOrNullBool(0) ?? false }
        )) {
            case Some(b) => b
            case None => false
        }
    }

    /**
     * 检查列是否存在
     */
    public static func columnExists(db: Database, tableName: String, columnName: String): Bool {
        match (db.rawOne<Bool>(
            "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1 AND column_name = $2)",
            [vtext(tableName), vtext(columnName)],
            { row => row.getOrNullBool(0) ?? false }
        )) {
            case Some(b) => b
            case None => false
        }
    }

    /**
     * 检查索引是否存在
     */
    public static func indexExists(db: Database, indexName: String): Bool {
        match (db.rawOne<Bool>(
            "SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = $1)",
            [vtext(indexName)],
            { row => row.getOrNullBool(0) ?? false }
        )) {
            case Some(b) => b
            case None => false
        }
    }

    /**
     * 检查数据库扩展是否已安装
     */
    public static func extensionInstalled(db: Database, extensionName: String): Bool {
        try {
            db.rawOne<Int64>(
                "SELECT 1 FROM pg_extension WHERE extname = $1 LIMIT 1",
                [vtext(extensionName)],
                { row => row.getInt64(0) }
            ).isSome()
        } catch (e: Exception) {
            logger.warn("Failed to query pg_extension", ("error", e.message), ("extension", extensionName))
            false
        }
    }

    /**
     * 尝试自动安装数据库扩展(使用从连接池借的 Database 句柄)。
     */
    public static func ensureExtensionInstalled(extensionName: String): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                if (extensionInstalled(db, extensionName)) {
                    return true
                }
                logger.info("Attempting to install database extension ${extensionName}")
                if (!execUpdate(db, "CREATE EXTENSION IF NOT EXISTS ${extensionName}")) {
                    logger.warn("Failed to auto-install database extension", ("extension", extensionName))
                    return false
                }
                let installed = extensionInstalled(db, extensionName)
                if (!installed) {
                    logger.warn("Extension still unavailable after CREATE EXTENSION", ("extension", extensionName))
                }
                installed
            case None =>
                logger.warn("Cannot get DB connection for extension installation", ("extension", extensionName))
                false
        }
    }

    /**
     * 检查视图是否存在
     */
    public static func viewExists(db: Database, viewName: String): Bool {
        match (db.rawOne<Bool>(
            "SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'public' AND table_name = $1)",
            [vtext(viewName)],
            { row => row.getOrNullBool(0) ?? false }
        )) {
            case Some(b) => b
            case None => false
        }
    }

    /**
     * 执行更新/DDL 语句(无参数)。
     */
    public static func execUpdate(db: Database, sql: String): Bool {
        try {
            db.execRawSql(sql)
            true
        } catch (e: Exception) {
            logger.error("SQL execution failed: ${e.message}")
            false
        }
    }

    /**
     * 如果列不存在则添加
     */
    public static func addColumnIfNotExists(
        db: Database,
        tableName: String,
        columnName: String,
        columnDef: String
    ): Bool {
        if (columnExists(db, tableName, columnName)) {
            logger.debug("Column ${columnName} already exists in ${tableName}")
            return true
        }
        logger.debug("Adding column ${columnName} to ${tableName}")
        execUpdate(db, "ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${columnDef}")
    }

    /**
     * 如果索引不存在则创建
     */
    public static func createIndexIfNotExists(
        db: Database,
        indexName: String,
        tableName: String,
        columns: String
    ): Bool {
        if (indexExists(db, indexName)) {
            logger.debug("Index ${indexName} already exists")
            return true
        }
        logger.debug("Creating index ${indexName} on ${tableName}")
        execUpdate(db, "CREATE INDEX ${indexName} ON ${tableName} (${columns})")
    }

    /**
     * 如果表不存在则创建
     */
    public static func createTableIfNotExists(
        db: Database,
        tableName: String,
        createSql: String
    ): Bool {
        if (tableExists(db, tableName)) {
            logger.debug("Table ${tableName} already exists")
            return true
        }
        logger.debug("Creating table ${tableName}")
        execUpdate(db, createSql)
    }
}