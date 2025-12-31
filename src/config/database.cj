package lrr4cj.config

import std.database.sql.*
import std.convert.*
import stdx.log.*
import cjdotenv.load
import std.env.getVariable
import lrr4cj.utils.*
import opengauss.driver.*
import std.fs.exists

/**
 * 数据库配置类
 */
public class DatabaseConfig {
    public static var dbString: String
    public static var dbType: String

    /**
     * 静态初始化器，从环境变量读取配置
     */
    static init() {
        if (exists(".env")) {
            load()
        }
        // 从环境变量中读取数据库配置
        dbString = getVariable("DB_STRING") ?? "postgres://lgr:lgr@127.0.0.1:5432/lgr?sslmode=disable"
        // 从连接字符串中解析数据库类型
        dbType = parseDbType(dbString)
    }

    /**
     * 从连接字符串中解析数据库类型
     */
    private static func parseDbType(connStr: String): String {
        if (connStr.isEmpty()) {
            return "postgres"
        }
        // 提取协议部分，如 "postgres://" -> "postgres"
        let parts = connStr.split("://")
        if (parts.size >= 2) {
            return parts[0]
        }
        return "postgres"
    }

    /**
     * 获取数据库连接字符串
     */
    public static func getConnectionString(): String {
        let logger = getLogger("database")
        logger.debug("Using database connection string from DB_STRING")
        logger.debug("DB type: ${dbType}")
        return dbString
    }

    /**
     * 获取数据库驱动
     */
    public static func getDriver(): Option<Driver> {
        return DriverManager.getDriver(dbType)
    }
    
    /**
     * 创建数据库连接
     */
    public static func createConnection(): Option<Connection> {
        let drvopt = getDriver()
        match (drvopt) {
            case Some(drv) =>
                let connStr = getConnectionString()
                let ds = drv.open(connStr)
                try {
                    let conn = ds.connect()
                    return Some(conn)
                } catch (e: Exception) {
                    let logger = getLogger("database")
                    logger.error("数据库连接失败: ${e.toString()}")
                    logger.error("连接异常详细信息: ${e.message}")
                    return None
                }
            case None =>
                getLogger("database").error("无法获取 ${dbType} 驱动")
                return None
        }
    }

    /**
     * 从连接池获取连接（推荐使用）
     * 复用连接以提升性能
     */
    public static func getPooledConnection(): Option<Connection> {
        return ConnectionPool.getInstance().getConnection()
    }

    /**
     * 释放连接回连接池
     */
    public static func releasePooledConnection(conn: Connection): Unit {
        ConnectionPool.getInstance().releaseConnection(conn)
    }

    /**
     * 初始化连接池
     */
    public static func initializePool(): Bool {
        return ConnectionPool.getInstance().initialize()
    }

    /**
     * 初始化数据库表结构
     */
    public static func initializeDatabase(): Bool {
        let logger = getLogger("database")
        logger.debug("开始初始化数据库")

        let connOpt = createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    logger.debug("数据库连接成功，跳过测试查询直接创建表")

                    logger.debug("开始创建或更新插件表")
                    // 检查插件表是否存在
                    let checkTable = conn.prepareStatement("SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'plugins')")
                    let rs = checkTable.query()
                    var tableExists = false
                    if (rs.next()) {
                        tableExists = rs.getOrNull<Bool>(0) ?? false
                    }
                    rs.close()
                    checkTable.close()

                    if (!tableExists) {
                        logger.debug("插件表不存在，创建新的插件表")
                        // 创建基础表结构，不使用SERIAL
                        let createPluginsTable = "CREATE TABLE plugins (id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY, name VARCHAR(255) NOT NULL, version VARCHAR(50) NOT NULL)"

                        logger.debug("准备执行插件表创建语句")
                        let stmt = conn.prepareStatement(createPluginsTable)
                        stmt.update()
                        stmt.close()
                        logger.debug("插件表创建成功")
                    } else {
                        logger.debug("插件表已存在，跳过创建")
                    }

                    // 检查并添加缺失的列
                    logger.debug("检查并添加缺失的列")

                    // 检查 namespace 列
                    try {
                        let checkNamespace = conn.prepareStatement("SELECT column_name FROM information_schema.columns WHERE table_name = 'plugins' AND column_name = 'namespace'")
                        let rsNamespace = checkNamespace.query()
                        if (!rsNamespace.next()) {
                                logger.debug("添加 namespace 列")
                                let addNamespace = conn.prepareStatement("ALTER TABLE plugins ADD COLUMN namespace VARCHAR(100) NOT NULL DEFAULT ''")
                                addNamespace.update()
                                addNamespace.close()
                                logger.debug("namespace 列添加成功")
                            }
                        rsNamespace.close()
                        checkNamespace.close()
                    } catch (e: Exception) {
                        logger.error("检查或添加 namespace 列失败: ${e.message}")
                    }

                    // 添加其他缺失的列
                    let columnsToAdd = [
                        ("description", "TEXT DEFAULT ''"),
                        ("author", "VARCHAR(255) DEFAULT ''"),
                        ("entry", "VARCHAR(255) DEFAULT ''"),
                        ("plugin_type", "VARCHAR(50) DEFAULT ''"),
                    ("tags", "TEXT DEFAULT ''"),
                    ("url_regex", "TEXT DEFAULT ''"),
                    ("login_from", "VARCHAR(100) DEFAULT ''"),
                    ("permissions", "TEXT DEFAULT ''"),
                        ("icon", "TEXT DEFAULT ''"),  // 插件图标，Base64编码的图片数据
                        ("enabled", "BOOLEAN DEFAULT false"),
                        ("installed", "BOOLEAN DEFAULT false"),
                        ("has_schema", "BOOLEAN DEFAULT false"),
                        ("parameters", "TEXT DEFAULT '[]'"),  // 存储带value的参数数组
                        ("created_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"),
                        ("updated_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
                    ]

                    for ((column, definition) in columnsToAdd) {
                        try {
                            let checkColumn = conn.prepareStatement("SELECT column_name FROM information_schema.columns WHERE table_name = 'plugins' AND column_name = '${column}'")
                            let rs = checkColumn.query()
                            if (!rs.next()) {
                                logger.debug("添加 ${column} 列")
                                let addColumn = conn.prepareStatement("ALTER TABLE plugins ADD COLUMN ${column} ${definition}")
                                addColumn.update()
                                addColumn.close()
                                logger.debug("${column} 列添加成功")
                            }
                            rs.close()
                            checkColumn.close()
                        } catch (e: Exception) {
                            logger.error("检查或添加 ${column} 列失败: ${e.message}")
                        }
                    }

                    // 约束修复已完成，跳过约束修改逻辑以避免启动时阻塞
                    logger.debug("约束配置检查跳过 - 假设约束已正确配置为namespace唯一键")

                    logger.debug("插件表结构更新完成")

                    logger.debug("开始创建或更新归档/标签相关表与视图")
                    let archiveOk = initializeArchiveSchema(conn)
                    if (!archiveOk) {
                        logger.error("归档/标签相关表与视图初始化失败")
                        conn.close()
                        return false
                    }

                    conn.close()
                    return true
                } catch (e: Exception) {
                    logger.error("数据库初始化失败: ${e.toString()}")
                    logger.error("异常详细信息: ${e.message}")
                    try {
                        conn.close()
                    } catch (closeException: Exception) {
                        logger.warn("关闭数据库连接失败: ${closeException.message}")
                    }
                    return false
                }
            case None =>
                logger.error("无法连接到数据库")
                return false
        }
    }

    private static func tableExists(conn: Connection, tableName: String): Bool {
        let stmt = conn.prepareStatement("SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ?)")
        try {
            stmt.set(0, tableName)
            let rs = stmt.query()
            try {
                var exists = false
                if (rs.next()) {
                    // openGauss / PostgreSQL typically return BOOLEAN for EXISTS; some drivers may map it as integer.
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

    private static func viewExists(conn: Connection, viewName: String): Bool {
        let stmt = conn.prepareStatement("SELECT EXISTS (SELECT FROM information_schema.views WHERE table_schema = 'public' AND table_name = ?)")
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

    private static func columnExists(conn: Connection, tableName: String, columnName: String): Bool {
        let stmt = conn.prepareStatement("SELECT EXISTS (SELECT FROM information_schema.columns WHERE table_schema = 'public' AND table_name = ? AND column_name = ?)")
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

    private static func indexExists(conn: Connection, indexName: String): Bool {
        // pg_indexes is available in PostgreSQL/openGauss.
        let stmt = conn.prepareStatement("SELECT EXISTS (SELECT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ?)")
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

    private static func execUpdate(conn: Connection, sql: String): Unit {
        let stmt = conn.prepareStatement(sql)
        try {
            stmt.update()
        } finally {
            stmt.close()
        }
    }

    /**
     * 初始化归档、标签表与archives_with_tags视图（幂等）
     */
    private static func initializeArchiveSchema(conn: Connection): Bool {
        let logger = getLogger("database")
        try {
            // users 表
            if (!tableExists(conn, "users")) {
                logger.debug("users表不存在，创建新的users表")
                execUpdate(conn, """
                    CREATE TABLE users (
                        id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                        username VARCHAR(64) NOT NULL UNIQUE,
                        password_salt VARCHAR(64) NOT NULL,
                        password_hash VARCHAR(64) NOT NULL,
                        is_admin BOOLEAN DEFAULT false,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)
                logger.debug("users表创建成功")
            } else {
                logger.debug("users表已存在，检查并补全缺失列")
                // 检查 password_salt 列是否存在
                if (!columnExists(conn, "users", "password_salt")) {
                    logger.debug("users表缺少列 password_salt，添加中")
                    execUpdate(conn, "ALTER TABLE users ADD COLUMN password_salt VARCHAR(64) NOT NULL DEFAULT ''")
                }
                // 检查 updated_at 列是否存在
                if (!columnExists(conn, "users", "updated_at")) {
                    logger.debug("users表缺少列 updated_at，添加中")
                    execUpdate(conn, "ALTER TABLE users ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
                }
            }

            // categories 表（必须在 archives 表之前创建，因为 archives 依赖它）
            if (!tableExists(conn, "categories")) {
                logger.debug("categories表不存在，创建新的categories表")
                execUpdate(conn, """
                    CREATE TABLE categories (
                        id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                        catid VARCHAR(255) NOT NULL UNIQUE,
                        name VARCHAR(255) NOT NULL,
                        scan_path TEXT NOT NULL,
                        description TEXT DEFAULT '',
                        icon VARCHAR(64) DEFAULT '',
                        sort_order INTEGER DEFAULT 0,
                        enabled BOOLEAN DEFAULT true,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)
                // 创建索引
                try {
                    execUpdate(conn, "CREATE INDEX idx_categories_catid ON categories (catid)")
                } catch (_: Exception) {}
                try {
                    execUpdate(conn, "CREATE INDEX idx_categories_enabled ON categories (enabled)")
                } catch (_: Exception) {}
                try {
                    execUpdate(conn, "CREATE INDEX idx_categories_sort_order ON categories (sort_order)")
                } catch (_: Exception) {}
                logger.debug("categories表创建成功")
            } else {
                logger.debug("categories表已存在，检查是否需要迁移到新结构")
                // 检查是否是旧结构（有 search 列但没有 scan_path 列）
                let hasOldStructure = columnExists(conn, "categories", "search") && !columnExists(conn, "categories", "scan_path")
                if (hasOldStructure) {
                    logger.debug("检测到旧的categories表结构，需要重建")
                    try {
                        // 先删除依赖的 archive_categories 表（如果存在）
                        if (tableExists(conn, "archive_categories")) {
                            execUpdate(conn, "DROP TABLE archive_categories")
                            logger.debug("已删除旧的archive_categories表")
                        }
                        // 删除旧 categories 表
                        execUpdate(conn, "DROP TABLE categories")
                        // 创建新 categories 表
                        execUpdate(conn, """
                            CREATE TABLE categories (
                                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                                catid VARCHAR(255) NOT NULL UNIQUE,
                                name VARCHAR(255) NOT NULL,
                                scan_path TEXT NOT NULL,
                                description TEXT DEFAULT '',
                                icon VARCHAR(64) DEFAULT '',
                                sort_order INTEGER DEFAULT 0,
                                enabled BOOLEAN DEFAULT true,
                                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                            )
                        """)
                        try {
                            execUpdate(conn, "CREATE INDEX idx_categories_catid ON categories (catid)")
                        } catch (_: Exception) {}
                        try {
                            execUpdate(conn, "CREATE INDEX idx_categories_enabled ON categories (enabled)")
                        } catch (_: Exception) {}
                        try {
                    execUpdate(conn, "CREATE INDEX idx_categories_sort_order ON categories (sort_order)")
                } catch (_: Exception) {}
                logger.debug("categories表重建成功")
                    } catch (e: Exception) {
                        logger.error("categories表重建失败: ${e.toString()}")
                    }
                }
            }

            // 删除旧的 archive_categories 表（如果存在）
            if (tableExists(conn, "archive_categories")) {
                logger.debug("检测到旧的archive_categories表，正在删除")
                execUpdate(conn, "DROP TABLE archive_categories")
                logger.debug("archive_categories表已删除")
            }

            // archives 表
            if (!tableExists(conn, "archives")) {
                logger.debug("archives表不存在，创建新的archives表")
                execUpdate(conn, """
                    CREATE TABLE archives (
                        id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                        arcid VARCHAR(255) NOT NULL UNIQUE,
                        title VARCHAR(1024) DEFAULT '',
                        filename VARCHAR(1024) NOT NULL,
                        summary TEXT DEFAULT '',
                        thumbhash TEXT DEFAULT '',
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        relative_path TEXT DEFAULT '',
                        file_size BIGINT DEFAULT 0,
                        pagecount INTEGER DEFAULT 0,
                        archive_type VARCHAR(20) DEFAULT 'archive',
                        category_id INTEGER NOT NULL,
                        FOREIGN KEY (category_id) REFERENCES categories(id)
                    )
                """)
                // 创建 category_id 索引
                try {
                    execUpdate(conn, "CREATE INDEX idx_archives_category_id ON archives (category_id)")
                } catch (_: Exception) {}
                logger.debug("archives表创建成功")
            } else {
                logger.debug("archives表已存在，检查并补全缺失列")
                let columnsToAdd = [
                    ("arcid", "VARCHAR(255) NOT NULL"),
                    ("title", "VARCHAR(1024) DEFAULT ''"),
                    ("filename", "VARCHAR(1024) NOT NULL DEFAULT ''"),
                    ("summary", "TEXT DEFAULT ''"),
                    ("thumbhash", "TEXT DEFAULT ''"),
                    ("created_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"),
                    ("updated_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"),
                    ("relative_path", "TEXT DEFAULT ''"),
                    ("file_size", "BIGINT DEFAULT 0"),
                    ("pagecount", "INTEGER DEFAULT 0"),
                    ("archive_type", "VARCHAR(20) DEFAULT 'archive'"),
                    ("category_id", "INTEGER NOT NULL")
                ]

                for ((column, definition) in columnsToAdd) {
                    if (!columnExists(conn, "archives", column)) {
                        logger.debug("archives表缺少列 ${column}，添加中")
                        execUpdate(conn, "ALTER TABLE archives ADD COLUMN ${column} ${definition}")
                    }
                }

                // 移除旧的 isnew 列（如果存在）
                if (columnExists(conn, "archives", "isnew")) {
                    logger.debug("archives表存在旧的isnew列，准备移除")
                    try {
                        execUpdate(conn, "ALTER TABLE archives DROP COLUMN isnew")
                        logger.debug("archives表的isnew列已成功移除")
                    } catch (e: Exception) {
                        logger.warn("移除archives表的isnew列失败: ${e.toString()}")
                    }
                }

                // 移除旧的 last_read_time 列（如果存在）- 数据已迁移到 user_archive_status
                if (columnExists(conn, "archives", "last_read_time")) {
                    logger.debug("archives表存在旧的last_read_time列，准备移除（数据已迁移到user_archive_status）")
                    try {
                        execUpdate(conn, "ALTER TABLE archives DROP COLUMN last_read_time")
                        logger.debug("archives表的last_read_time列已成功移除")
                    } catch (e: Exception) {
                        logger.warn("移除archives表的last_read_time列失败: ${e.toString()}")
                    }
                }

                // 移除旧的 progress 列（如果存在）- 数据已迁移到 user_archive_status
                if (columnExists(conn, "archives", "progress")) {
                    logger.debug("archives表存在旧的progress列，准备移除（数据已迁移到user_archive_status）")
                    try {
                        execUpdate(conn, "ALTER TABLE archives DROP COLUMN progress")
                        logger.debug("archives表的progress列已成功移除")
                    } catch (e: Exception) {
                        logger.warn("移除archives表的progress列失败: ${e.toString()}")
                    }
                }

                // arcid 唯一约束（如果不存在）
                try {
                    let createSql = "CREATE UNIQUE INDEX archives_arcid_key ON archives (arcid)"
                    try {
                        if (!indexExists(conn, "archives_arcid_key")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        // Fallback: if index existence check fails, attempt create and ignore errors.
                        execUpdate(conn, createSql)
                    }
                } catch (e: Exception) {
                    logger.warn("创建archives.arcid唯一索引失败（可忽略）: ${e.toString()}")
                }

                // category_id 索引（如果不存在）
                try {
                    let createSql = "CREATE INDEX idx_archives_category_id ON archives (category_id)"
                    try {
                        if (!indexExists(conn, "idx_archives_category_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
            }

            // tags 表（新结构：namespace + name + translations JSONB）
            if (!tableExists(conn, "tags")) {
                logger.debug("tags表不存在，创建新的tags表")
                execUpdate(conn, """
                    CREATE TABLE tags (
                        id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                        namespace VARCHAR(64) NOT NULL DEFAULT '',
                        name VARCHAR(255) NOT NULL,
                        translations JSONB NOT NULL DEFAULT '{}',
                        links TEXT DEFAULT '',
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        UNIQUE (namespace, name)
                    )
                """)
                // 创建索引
                try {
                    execUpdate(conn, "CREATE INDEX idx_tags_namespace ON tags (namespace)")
                } catch (_: Exception) {}
                try {
                    execUpdate(conn, "CREATE INDEX idx_tags_name ON tags (name)")
                } catch (_: Exception) {}
                logger.debug("tags表创建成功")
            } else {
                logger.debug("tags表已存在，检查是否需要迁移到新结构")
                // 检查是否是旧结构（有 value 列但没有 translations 列）
                let hasOldStructure = columnExists(conn, "tags", "value") && !columnExists(conn, "tags", "translations")
                if (hasOldStructure) {
                    logger.debug("检测到旧的tags表结构，需要迁移")
                    // 删除旧表，创建新表
                    try {
                        // 先删除依赖的视图
                        if (viewExists(conn, "archives_with_tags")) {
                            execUpdate(conn, "DROP VIEW archives_with_tags")
                        }
                        // 删除 archive_tags 表（因为有外键约束）
                        if (tableExists(conn, "archive_tags")) {
                            execUpdate(conn, "DROP TABLE archive_tags")
                        }
                        // 删除旧 tags 表
                        execUpdate(conn, "DROP TABLE tags")
                        // 创建新 tags 表
                        execUpdate(conn, """
                            CREATE TABLE tags (
                                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                                namespace VARCHAR(64) NOT NULL DEFAULT '',
                                name VARCHAR(255) NOT NULL,
                                translations JSONB NOT NULL DEFAULT '{}',
                                links TEXT DEFAULT '',
                                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                                UNIQUE (namespace, name)
                            )
                        """)
                        try {
                            execUpdate(conn, "CREATE INDEX idx_tags_namespace ON tags (namespace)")
                        } catch (_: Exception) {}
                        try {
                            execUpdate(conn, "CREATE INDEX idx_tags_name ON tags (name)")
                        } catch (_: Exception) {}
                        logger.debug("tags表迁移成功")
                    } catch (e: Exception) {
                        logger.error("tags表迁移失败: ${e.toString()}")
                    }
                } else if (!columnExists(conn, "tags", "translations")) {
                    // 新结构但缺少某些列
                    logger.debug("tags表结构不完整，添加缺失列")
                    try {
                        execUpdate(conn, "ALTER TABLE tags ADD COLUMN translations JSONB NOT NULL DEFAULT '{}'")
                    } catch (_: Exception) {}
                    try {
                        execUpdate(conn, "ALTER TABLE tags ADD COLUMN links TEXT DEFAULT ''")
                    } catch (_: Exception) {}
                }
            }

            // 删除旧的 tag_i18n 表（如果存在）
            if (tableExists(conn, "tag_i18n")) {
                logger.debug("检测到旧的tag_i18n表，正在删除（数据已合并到tags表）")
                execUpdate(conn, "DROP TABLE tag_i18n")
                logger.debug("tag_i18n表已删除")
            }

            // user_archive_status 表（用户级别的归档状态）
            if (!tableExists(conn, "user_archive_status")) {
                logger.debug("user_archive_status表不存在，创建新的user_archive_status表")
                execUpdate(conn, """
                    CREATE TABLE user_archive_status (
                        id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                        user_id INTEGER NOT NULL,
                        archive_id INTEGER NOT NULL,
                        is_new BOOLEAN DEFAULT true,
                        progress INTEGER DEFAULT 0,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        UNIQUE (user_id, archive_id),
                        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                        FOREIGN KEY (archive_id) REFERENCES archives(id) ON DELETE CASCADE
                    )
                """)
                try {
                    let createSql = "CREATE INDEX idx_user_archive_status_user_id ON user_archive_status (user_id)"
                    try {
                        if (!indexExists(conn, "idx_user_archive_status_user_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_user_archive_status_archive_id ON user_archive_status (archive_id)"
                    try {
                        if (!indexExists(conn, "idx_user_archive_status_archive_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                logger.debug("user_archive_status表创建成功")
            } else {
                logger.debug("user_archive_status表已存在，检查并补全索引")
                // 检查并添加 progress 字段
                try {
                    if (!columnExists(conn, "user_archive_status", "progress")) {
                        execUpdate(conn, "ALTER TABLE user_archive_status ADD COLUMN progress INTEGER DEFAULT 0")
                        logger.debug("已为 user_archive_status 表添加 progress 字段")
                    }
                    // 为 progress 字段创建索引
                    let indexSql = "CREATE INDEX idx_user_archive_status_progress ON user_archive_status (progress)"
                    try {
                        if (!indexExists(conn, "idx_user_archive_status_progress")) {
                            execUpdate(conn, indexSql)
                            logger.debug("已为 user_archive_status.progress 创建索引")
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, indexSql)
                    }
                } catch (_: Exception) {
                    logger.debug("检查/添加 progress 字段时出错，可能已存在")
                }
                try {
                    let createSql = "CREATE INDEX idx_user_archive_status_user_id ON user_archive_status (user_id)"
                    try {
                        if (!indexExists(conn, "idx_user_archive_status_user_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_user_archive_status_archive_id ON user_archive_status (archive_id)"
                    try {
                        if (!indexExists(conn, "idx_user_archive_status_archive_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
            }

            // user_favorites 表（用户收藏）
            if (!tableExists(conn, "user_favorites")) {
                logger.debug("user_favorites表不存在，创建新的user_favorites表")
                execUpdate(conn, """
                    CREATE TABLE user_favorites (
                        id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                        user_id INTEGER NOT NULL,
                        archive_id INTEGER NOT NULL,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        UNIQUE (user_id, archive_id),
                        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                        FOREIGN KEY (archive_id) REFERENCES archives(id) ON DELETE CASCADE
                    )
                """)
                try {
                    let createSql = "CREATE INDEX idx_user_favorites_user_id ON user_favorites (user_id)"
                    try {
                        if (!indexExists(conn, "idx_user_favorites_user_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_user_favorites_archive_id ON user_favorites (archive_id)"
                    try {
                        if (!indexExists(conn, "idx_user_favorites_archive_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_user_favorites_created_at ON user_favorites (created_at)"
                    try {
                        if (!indexExists(conn, "idx_user_favorites_created_at")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                logger.debug("user_favorites表创建成功")
            } else {
                logger.debug("user_favorites表已存在，检查并补全索引")
                try {
                    let createSql = "CREATE INDEX idx_user_favorites_user_id ON user_favorites (user_id)"
                    try {
                        if (!indexExists(conn, "idx_user_favorites_user_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_user_favorites_archive_id ON user_favorites (archive_id)"
                    try {
                        if (!indexExists(conn, "idx_user_favorites_archive_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_user_favorites_created_at ON user_favorites (created_at)"
                    try {
                        if (!indexExists(conn, "idx_user_favorites_created_at")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
            }

            // smart_filters 表（智能分类/快速筛选）
            if (!tableExists(conn, "smart_filters")) {
                logger.debug("smart_filters表不存在，创建新的smart_filters表")
                execUpdate(conn, """
                    CREATE TABLE smart_filters (
                        id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                        name VARCHAR(255) NOT NULL,
                        translations JSONB NOT NULL DEFAULT '{}',
                        icon VARCHAR(64) DEFAULT '',
                        query TEXT DEFAULT '',
                        sort_by VARCHAR(64) DEFAULT '',
                        sort_order VARCHAR(16) DEFAULT 'desc',
                        date_from VARCHAR(32) DEFAULT '',
                        date_to VARCHAR(32) DEFAULT '',
                        newonly BOOLEAN DEFAULT false,
                        untaggedonly BOOLEAN DEFAULT false,
                        sort_order_num INTEGER DEFAULT 0,
                        enabled BOOLEAN DEFAULT true,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)
                // 插入默认的智能分类
                execUpdate(conn, """
                    INSERT INTO smart_filters (name, translations, icon, newonly, sort_order_num)
                    VALUES ('未读档案', '{"en": {"text": "Unread Archives"}}', 'BookOpen', true, 1)
                """)
                execUpdate(conn, """
                    INSERT INTO smart_filters (name, translations, icon, untaggedonly, sort_order_num)
                    VALUES ('无标签档案', '{"en": {"text": "Untagged Archives"}}', 'Tag', true, 2)
                """)
                execUpdate(conn, """
                    INSERT INTO smart_filters (name, translations, icon, date_from, sort_by, sort_order, sort_order_num)
                    VALUES ('最近一周', '{"en": {"text": "Last Week"}}', 'Calendar', '-7', 'date_added', 'desc', 3)
                """)
                logger.debug("smart_filters表创建成功，已插入默认分类")
            } else {
                logger.debug("smart_filters表已存在")
            }

            // archive_tags 表（archives.id <-> tags.id）
            if (!tableExists(conn, "archive_tags")) {
                logger.debug("archive_tags表不存在，创建新的archive_tags表")
                execUpdate(conn, """
                    CREATE TABLE archive_tags (
                        archive_id INTEGER NOT NULL,
                        tag_id INTEGER NOT NULL,
                        PRIMARY KEY (archive_id, tag_id),
                        FOREIGN KEY (archive_id) REFERENCES archives(id) ON DELETE CASCADE,
                        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
                    )
                """)
                try {
                    let createSql = "CREATE INDEX idx_archive_tags_archive_id ON archive_tags (archive_id)"
                    try {
                        if (!indexExists(conn, "idx_archive_tags_archive_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_archive_tags_tag_id ON archive_tags (tag_id)"
                    try {
                        if (!indexExists(conn, "idx_archive_tags_tag_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                logger.debug("archive_tags表创建成功")
            } else {
                logger.debug("archive_tags表已存在，检查并补全索引")
                try {
                    let createSql = "CREATE INDEX idx_archive_tags_archive_id ON archive_tags (archive_id)"
                    try {
                        if (!indexExists(conn, "idx_archive_tags_archive_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_archive_tags_tag_id ON archive_tags (tag_id)"
                    try {
                        if (!indexExists(conn, "idx_archive_tags_tag_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
            }

            // tankoubons 表
            if (!tableExists(conn, "tankoubons")) {
                logger.debug("tankoubons表不存在，创建新的tankoubons表")
                execUpdate(conn, """
                    CREATE TABLE tankoubons (
                        id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                        tankoubon_id VARCHAR(255) NOT NULL UNIQUE,
                        name VARCHAR(1024) NOT NULL,
                        summary TEXT DEFAULT '',
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)
                // 创建索引
                try {
                    let createSql = "CREATE INDEX idx_tankoubons_tankoubon_id ON tankoubons (tankoubon_id)"
                    try {
                        if (!indexExists(conn, "idx_tankoubons_tankoubon_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_tankoubons_name ON tankoubons (name)"
                    try {
                        if (!indexExists(conn, "idx_tankoubons_name")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                logger.debug("tankoubons表创建成功")
            } else {
                logger.debug("tankoubons表已存在，检查并补全索引")
                try {
                    let createSql = "CREATE INDEX idx_tankoubons_tankoubon_id ON tankoubons (tankoubon_id)"
                    try {
                        if (!indexExists(conn, "idx_tankoubons_tankoubon_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_tankoubons_name ON tankoubons (name)"
                    try {
                        if (!indexExists(conn, "idx_tankoubons_name")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
            }

            // tankoubon_archives 表（junction table）
            if (!tableExists(conn, "tankoubon_archives")) {
                logger.debug("tankoubon_archives表不存在，创建新的tankoubon_archives表")
                execUpdate(conn, """
                    CREATE TABLE tankoubon_archives (
                        id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                        tankoubon_id INTEGER NOT NULL,
                        archive_id INTEGER NOT NULL,
                        sort_order INTEGER DEFAULT 0,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        UNIQUE (tankoubon_id, archive_id),
                        FOREIGN KEY (tankoubon_id) REFERENCES tankoubons(id) ON DELETE CASCADE,
                        FOREIGN KEY (archive_id) REFERENCES archives(id) ON DELETE CASCADE
                    )
                """)
                // 创建索引
                try {
                    let createSql = "CREATE INDEX idx_tankoubon_archives_tankoubon_id ON tankoubon_archives (tankoubon_id)"
                    try {
                        if (!indexExists(conn, "idx_tankoubon_archives_tankoubon_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_tankoubon_archives_archive_id ON tankoubon_archives (archive_id)"
                    try {
                        if (!indexExists(conn, "idx_tankoubon_archives_archive_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_tankoubon_archives_sort_order ON tankoubon_archives (sort_order)"
                    try {
                        if (!indexExists(conn, "idx_tankoubon_archives_sort_order")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                logger.debug("tankoubon_archives表创建成功")
            } else {
                logger.debug("tankoubon_archives表已存在，检查并补全索引")
                try {
                    let createSql = "CREATE INDEX idx_tankoubon_archives_tankoubon_id ON tankoubon_archives (tankoubon_id)"
                    try {
                        if (!indexExists(conn, "idx_tankoubon_archives_tankoubon_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_tankoubon_archives_archive_id ON tankoubon_archives (archive_id)"
                    try {
                        if (!indexExists(conn, "idx_tankoubon_archives_archive_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_tankoubon_archives_sort_order ON tankoubon_archives (sort_order)"
                    try {
                        if (!indexExists(conn, "idx_tankoubon_archives_sort_order")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
            }

            // tankoubon_tags 表（tankoubon 与 tag 的关联表）
            if (!tableExists(conn, "tankoubon_tags")) {
                logger.debug("tankoubon_tags表不存在，创建新的tankoubon_tags表")
                execUpdate(conn, """
                    CREATE TABLE tankoubon_tags (
                        tankoubon_id INTEGER NOT NULL,
                        tag_id INTEGER NOT NULL,
                        PRIMARY KEY (tankoubon_id, tag_id),
                        FOREIGN KEY (tankoubon_id) REFERENCES tankoubons(id) ON DELETE CASCADE,
                        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
                    )
                """)
                // 创建索引
                try {
                    execUpdate(conn, "CREATE INDEX idx_tankoubon_tags_tankoubon_id ON tankoubon_tags (tankoubon_id)")
                } catch (_: Exception) {}
                try {
                    execUpdate(conn, "CREATE INDEX idx_tankoubon_tags_tag_id ON tankoubon_tags (tag_id)")
                } catch (_: Exception) {}
                logger.debug("tankoubon_tags表创建成功")
            }

            // user_tankoubon_favorites 表（用户收藏的合集）- 必须在tankoubons表之后创建
            if (!tableExists(conn, "user_tankoubon_favorites")) {
                logger.debug("user_tankoubon_favorites表不存在，创建新的user_tankoubon_favorites表")
                execUpdate(conn, """
                    CREATE TABLE user_tankoubon_favorites (
                        id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                        user_id INTEGER NOT NULL,
                        tankoubon_id INTEGER NOT NULL,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        UNIQUE (user_id, tankoubon_id),
                        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                        FOREIGN KEY (tankoubon_id) REFERENCES tankoubons(id) ON DELETE CASCADE
                    )
                """)
                try {
                    let createSql = "CREATE INDEX idx_user_tankoubon_favorites_user_id ON user_tankoubon_favorites (user_id)"
                    try {
                        if (!indexExists(conn, "idx_user_tankoubon_favorites_user_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_user_tankoubon_favorites_tankoubon_id ON user_tankoubon_favorites (tankoubon_id)"
                    try {
                        if (!indexExists(conn, "idx_user_tankoubon_favorites_tankoubon_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_user_tankoubon_favorites_created_at ON user_tankoubon_favorites (created_at)"
                    try {
                        if (!indexExists(conn, "idx_user_tankoubon_favorites_created_at")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                logger.debug("user_tankoubon_favorites表创建成功")
            } else {
                logger.debug("user_tankoubon_favorites表已存在，检查并补全索引")
                try {
                    let createSql = "CREATE INDEX idx_user_tankoubon_favorites_user_id ON user_tankoubon_favorites (user_id)"
                    try {
                        if (!indexExists(conn, "idx_user_tankoubon_favorites_user_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_user_tankoubon_favorites_tankoubon_id ON user_tankoubon_favorites (tankoubon_id)"
                    try {
                        if (!indexExists(conn, "idx_user_tankoubon_favorites_tankoubon_id")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
                try {
                    let createSql = "CREATE INDEX idx_user_tankoubon_favorites_created_at ON user_tankoubon_favorites (created_at)"
                    try {
                        if (!indexExists(conn, "idx_user_tankoubon_favorites_created_at")) {
                            execUpdate(conn, createSql)
                        }
                    } catch (_: Exception) {
                        execUpdate(conn, createSql)
                    }
                } catch (_: Exception) {}
            }

            // archives_with_tags 视图
            if (viewExists(conn, "archives_with_tags")) {
                logger.debug("archives_with_tags视图已存在，重建以确保结构正确")
                execUpdate(conn, "DROP VIEW archives_with_tags")
            } else {
                logger.debug("archives_with_tags视图不存在，创建新视图")
            }

            execUpdate(conn, """
                CREATE VIEW archives_with_tags AS
                SELECT
                    a.id,
                    a.arcid,
                    a.filename,
                    a.title,
                    a.summary,
                    a.thumbhash,
                    a.created_at,
                    a.updated_at,
                    a.relative_path,
                    a.file_size,
                    a.pagecount,
                    a.archive_type,
                    a.category_id,
                    COALESCE(string_agg(
                        CASE WHEN t.namespace != '' AND t.namespace IS NOT NULL
                             THEN t.namespace || ':' || t.name
                             ELSE t.name
                        END, ',' ORDER BY t.namespace, t.name), '') AS tags
                FROM archives a
                LEFT JOIN archive_tags atg ON atg.archive_id = a.id
                LEFT JOIN tags t ON t.id = atg.tag_id
                GROUP BY
                    a.id, a.arcid, a.filename, a.title, a.summary, a.thumbhash,
                    a.created_at, a.updated_at, a.relative_path, a.file_size,
                    a.pagecount, a.archive_type, a.category_id
            """)

            logger.debug("归档/标签相关表与视图初始化完成")
            return true
        } catch (e: Exception) {
            logger.error("初始化归档/标签相关表与视图失败: ${e.toString()}")
            return false
        }
    }

    /**
     * 读取配置值（优先从系统设置读取，回退到环境变量）
     * 注意：此方法主要用于向后兼容，新代码应直接使用 SystemSettingsService
     */
    public static func readConfig(key: String): String {
        // 尝试从系统设置读取（如果可用）
        try {
            // 这里不能直接导入 SystemSettingsService，避免循环依赖
            // 暂时直接使用环境变量
            return getVariable(key) ?? ""
        } catch (_: Exception) {
            return ""
        }
    }

    /**
     * 读取配置值（带默认值）
     */
    public static func readConfigWithDefault(key: String, defaultValue: String): String {
        try {
            return getVariable(key) ?? defaultValue
        } catch (_: Exception) {
            return defaultValue
        }
    }

    /**
     * 读取缩略图路径
     */
    public static func getThumbnailPath(): String {
        return readConfigWithDefault("THUMBNAIL_PATH", "./data/thumb")
    }

    /**
     * 读取缓存路径
     */
    public static func getCachePath(): String {
        return readConfigWithDefault("CACHE_PATH", "./data/cache")
    }

    /**
     * 读取插件路径
     */
    public static func getPluginPath(): String {
        return readConfigWithDefault("PLUGIN_PATH", "./plugins")
    }
}
