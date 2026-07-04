package lanlu.infrastructure.migrations

import ace_orm.*
import lanlu.shared.config.*
import lanlu.shared.utils.*

/**
 * 迁移辅助函数(ACE-ORM 后端)。
 * 全部经 DatabaseConfig.driver() 执行 SQL,$n 占位符 + DbValue 绑定。
 */
public class MigrationHelpers {
    private static let logger = getLogger("migration_helpers")

    /**
     * 检查表是否存在
     */
    public static func tableExists(drv: Driver, tableName: String): Bool {
        try {
            let rows = drv.query(
                "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = $1)",
                [DbText(tableName)]
            )
            if (rows.size > 0) {
                return rows[0].getBool("exists")
            }
            return false
        } catch (e: Exception) {
            logger.error("tableExists failed: ${e.message}")
            return false
        }
    }

    /**
     * 检查列是否存在
     */
    public static func columnExists(drv: Driver, tableName: String, columnName: String): Bool {
        try {
            let rows = drv.query(
                "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1 AND column_name = $2)",
                [DbText(tableName), DbText(columnName)]
            )
            if (rows.size > 0) {
                return rows[0].getBool("exists")
            }
            return false
        } catch (e: Exception) {
            logger.error("columnExists failed: ${e.message}")
            return false
        }
    }

    /**
     * 检查索引是否存在
     */
    public static func indexExists(drv: Driver, indexName: String): Bool {
        try {
            let rows = drv.query(
                "SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = $1)",
                [DbText(indexName)]
            )
            if (rows.size > 0) {
                return rows[0].getBool("exists")
            }
            return false
        } catch (e: Exception) {
            logger.error("indexExists failed: ${e.message}")
            return false
        }
    }

    /**
     * 检查数据库扩展是否已安装
     */
    public static func extensionInstalled(drv: Driver, extensionName: String): Bool {
        try {
            let rows = drv.query(
                "SELECT 1 FROM pg_extension WHERE extname = $1 LIMIT 1",
                [DbText(extensionName)]
            )
            return rows.size > 0
        } catch (e: Exception) {
            logger.warn("Failed to query pg_extension", ("error", e.message), ("extension", extensionName))
            return false
        }
    }

    /**
     * 尝试自动安装数据库扩展。
     * 使用全局 driver(自带连接池),无需独立连接。
     */
    public static func ensureExtensionInstalled(extensionName: String): Bool {
        let drv = DatabaseConfig.driver()
        if (extensionInstalled(drv, extensionName)) {
            return true
        }
        logger.info("Attempting to install database extension ${extensionName}")
        if (!execUpdate(drv, "CREATE EXTENSION IF NOT EXISTS ${extensionName}")) {
            logger.warn("Failed to auto-install database extension", ("extension", extensionName))
            return false
        }
        let installed = extensionInstalled(drv, extensionName)
        if (!installed) {
            logger.warn("Extension still unavailable after CREATE EXTENSION", ("extension", extensionName))
        }
        return installed
    }

    /**
     * 检查视图是否存在
     */
    public static func viewExists(drv: Driver, viewName: String): Bool {
        try {
            let rows = drv.query(
                "SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'public' AND table_name = $1)",
                [DbText(viewName)]
            )
            if (rows.size > 0) {
                return rows[0].getBool("exists")
            }
            return false
        } catch (e: Exception) {
            logger.error("viewExists failed: ${e.message}")
            return false
        }
    }

    /**
     * 执行更新语句(DDL/INSERT/UPDATE/DELETE,无参数绑定)
     */
    public static func execUpdate(drv: Driver, sql: String): Bool {
        try {
            drv.exec(sql, [])
            return true
        } catch (e: Exception) {
            logger.error("SQL execution failed: ${e.message}")
            return false
        }
    }

    /**
     * 如果列不存在则添加
     */
    public static func addColumnIfNotExists(
        drv: Driver,
        tableName: String,
        columnName: String,
        columnDef: String
    ): Bool {
        if (columnExists(drv, tableName, columnName)) {
            logger.debug("Column ${columnName} already exists in ${tableName}")
            return true
        }
        logger.debug("Adding column ${columnName} to ${tableName}")
        return execUpdate(drv, "ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${columnDef}")
    }

    /**
     * 如果索引不存在则创建
     */
    public static func createIndexIfNotExists(
        drv: Driver,
        indexName: String,
        tableName: String,
        columns: String
    ): Bool {
        if (indexExists(drv, indexName)) {
            logger.debug("Index ${indexName} already exists")
            return true
        }
        logger.debug("Creating index ${indexName} on ${tableName}")
        return execUpdate(drv, "CREATE INDEX ${indexName} ON ${tableName} (${columns})")
    }

    /**
     * 如果表不存在则创建
     */
    public static func createTableIfNotExists(
        drv: Driver,
        tableName: String,
        createSql: String
    ): Bool {
        if (tableExists(drv, tableName)) {
            logger.debug("Table ${tableName} already exists")
            return true
        }
        logger.debug("Creating table ${tableName}")
        return execUpdate(drv, createSql)
    }
}