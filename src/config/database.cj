package lrr4cj.config

import std.database.sql.*
import opengauss.driver.*
import std.io.*
import std.fs.*
import std.time.*
import std.env.*
import std.convert.*
import stdx.log.*
import dotenv.Dotenv
import lrr4cj.utils.*

/**
 * 数据库配置类
 */
public class DatabaseConfig {
    public static var dbType: String
    public static var host: String
    public static var port: Int32
    public static var database: String
    public static var username: String
    public static var password: String
    public static var ssl: String
    
    /**
     * 静态初始化器，从环境变量读取配置
     */
    static init() {
        // 确保先加载 .env 文件
        let config = Dotenv.createConfig()

        // 从配置中读取数据库配置
        dbType = config.read("DB_TYPE", "postgres")
        host = config.read("DB_HOST", "127.0.0.1")

        let portStr = config.read("DB_PORT", "5432")
        port = Int32.parse(portStr)

        database = config.read("DB_NAME", "lgr")
        username = config.read("DB_USER", "lgr")
        password = config.read("DB_PASSWORD", "lgr")
        ssl = config.read("DB_SSL", "disable")
    }
    
    /**
     * 获取数据库连接字符串
     */
    public static func getConnectionString(): String {
        let logger = getLogger("database")
        logger.info("Creating database connection string")
        logger.info("DB config: type=${dbType}, host=${host}, port=${port.toString()}, database=${database}, user=${username}")
        let connStr = dbType + "://" + username + ":" + password + "@" + host + ":" + port.toString() + "/" + database + "?sslmode=" + ssl
        // logger.info("Connection string created: ${connStr}")
        return connStr
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
                let ds = drv.open(getConnectionString())
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
                getLogger("database").error("无法获取opengauss驱动")
                return None
        }
    }
    
    /**
     * 初始化数据库表结构
     */
    public static func initializeDatabase(): Bool {
        let logger = getLogger("database")
        logger.info("开始初始化数据库")

        let connOpt = createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    logger.info("数据库连接成功，跳过测试查询直接创建表")

                    logger.info("开始创建或更新插件表")
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
                        logger.info("插件表不存在，创建新的插件表")
                        // 创建基础表结构，不使用SERIAL
                        let createPluginsTable = "CREATE TABLE plugins (id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY, name VARCHAR(255) NOT NULL, version VARCHAR(50) NOT NULL)"

                        logger.info("准备执行插件表创建语句")
                        let stmt = conn.prepareStatement(createPluginsTable)
                        let result = stmt.update()
                        stmt.close()
                        logger.info("插件表创建成功")
                    } else {
                        logger.info("插件表已存在，跳过创建")
                    }

                    // 检查并添加缺失的列
                    logger.info("检查并添加缺失的列")

                    // 检查 namespace 列
                    try {
                        let checkNamespace = conn.prepareStatement("SELECT column_name FROM information_schema.columns WHERE table_name = 'plugins' AND column_name = 'namespace'")
                        let rsNamespace = checkNamespace.query()
                        if (!rsNamespace.next()) {
                            logger.info("添加 namespace 列")
                            let addNamespace = conn.prepareStatement("ALTER TABLE plugins ADD COLUMN namespace VARCHAR(100) NOT NULL DEFAULT ''")
                            addNamespace.update()
                            addNamespace.close()
                            logger.info("namespace 列添加成功")
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
                                logger.info("添加 ${column} 列")
                                let addColumn = conn.prepareStatement("ALTER TABLE plugins ADD COLUMN ${column} ${definition}")
                                addColumn.update()
                                addColumn.close()
                                logger.info("${column} 列添加成功")
                            }
                            rs.close()
                            checkColumn.close()
                        } catch (e: Exception) {
                            logger.error("检查或添加 ${column} 列失败: ${e.message}")
                        }
                    }

                    // 约束修复已完成，跳过约束修改逻辑以避免启动时阻塞
                    logger.info("约束配置检查跳过 - 假设约束已正确配置为namespace唯一键")

                    logger.info("插件表结构更新完成")

                    logger.info("开始创建或更新归档/标签相关表与视图")
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
                    exists = rs.getOrNull<Bool>(0) ?? false
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
                    exists = rs.getOrNull<Bool>(0) ?? false
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
                    exists = rs.getOrNull<Bool>(0) ?? false
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
            // archives 表
            if (!tableExists(conn, "archives")) {
                logger.info("archives表不存在，创建新的archives表")
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
                        isnew BOOLEAN DEFAULT true,
                        pagecount INTEGER DEFAULT 0,
                        last_read_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        progress INTEGER DEFAULT 0
                    )
                """)
                logger.info("archives表创建成功")
            } else {
                logger.info("archives表已存在，检查并补全缺失列")
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
                    ("isnew", "BOOLEAN DEFAULT true"),
                    ("pagecount", "INTEGER DEFAULT 0"),
                    ("last_read_time", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"),
                    ("progress", "INTEGER DEFAULT 0")
                ]

                for ((column, definition) in columnsToAdd) {
                    if (!columnExists(conn, "archives", column)) {
                        logger.info("archives表缺少列 ${column}，添加中")
                        execUpdate(conn, "ALTER TABLE archives ADD COLUMN ${column} ${definition}")
                    }
                }

                // arcid 唯一约束（如果不存在）
                try {
                    execUpdate(conn, "CREATE UNIQUE INDEX IF NOT EXISTS archives_arcid_key ON archives (arcid)")
                } catch (e: Exception) {
                    logger.warn("创建archives.arcid唯一索引失败（可忽略）: ${e.toString()}")
                }
            }

            // tags 表
            if (!tableExists(conn, "tags")) {
                logger.info("tags表不存在，创建新的tags表")
                execUpdate(conn, """
                    CREATE TABLE tags (
                        id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                        name VARCHAR(255) NOT NULL UNIQUE,
                        namespace VARCHAR(255) DEFAULT '',
                        value TEXT DEFAULT '',
                        weight INTEGER DEFAULT 1,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)
                logger.info("tags表创建成功")
            } else {
                logger.info("tags表已存在，检查并补全缺失列")
                let columnsToAdd = [
                    ("namespace", "VARCHAR(255) DEFAULT ''"),
                    ("value", "TEXT DEFAULT ''"),
                    ("weight", "INTEGER DEFAULT 1"),
                    ("created_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"),
                    ("updated_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
                ]
                for ((column, definition) in columnsToAdd) {
                    if (!columnExists(conn, "tags", column)) {
                        logger.info("tags表缺少列 ${column}，添加中")
                        execUpdate(conn, "ALTER TABLE tags ADD COLUMN ${column} ${definition}")
                    }
                }
                try {
                    execUpdate(conn, "CREATE UNIQUE INDEX IF NOT EXISTS tags_name_key ON tags (name)")
                } catch (e: Exception) {
                    logger.warn("创建tags.name唯一索引失败（可忽略）: ${e.toString()}")
                }
            }

            // archive_tags 表（archives.id <-> tags.id）
            if (!tableExists(conn, "archive_tags")) {
                logger.info("archive_tags表不存在，创建新的archive_tags表")
                execUpdate(conn, """
                    CREATE TABLE archive_tags (
                        archive_id INTEGER NOT NULL,
                        tag_id INTEGER NOT NULL,
                        PRIMARY KEY (archive_id, tag_id),
                        FOREIGN KEY (archive_id) REFERENCES archives(id) ON DELETE CASCADE,
                        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
                    )
                """)
                execUpdate(conn, "CREATE INDEX IF NOT EXISTS idx_archive_tags_archive_id ON archive_tags (archive_id)")
                execUpdate(conn, "CREATE INDEX IF NOT EXISTS idx_archive_tags_tag_id ON archive_tags (tag_id)")
                logger.info("archive_tags表创建成功")
            } else {
                logger.info("archive_tags表已存在，检查并补全索引")
                try { execUpdate(conn, "CREATE INDEX IF NOT EXISTS idx_archive_tags_archive_id ON archive_tags (archive_id)") } catch (e: Exception) {}
                try { execUpdate(conn, "CREATE INDEX IF NOT EXISTS idx_archive_tags_tag_id ON archive_tags (tag_id)") } catch (e: Exception) {}
            }

            // archives_with_tags 视图
            if (viewExists(conn, "archives_with_tags")) {
                logger.info("archives_with_tags视图已存在，重建以确保结构正确")
                execUpdate(conn, "DROP VIEW archives_with_tags")
            } else {
                logger.info("archives_with_tags视图不存在，创建新视图")
            }

            execUpdate(conn, """
                CREATE VIEW archives_with_tags AS
                SELECT
                    a.arcid,
                    a.filename,
                    a.title,
                    a.summary,
                    a.thumbhash,
                    a.created_at,
                    a.updated_at,
                    a.relative_path,
                    a.file_size,
                    a.isnew,
                    a.pagecount,
                    a.last_read_time,
                    a.progress,
                    COALESCE(string_agg(t.name, ',' ORDER BY t.name), '') AS tags
                FROM archives a
                LEFT JOIN archive_tags atg ON atg.archive_id = a.id
                LEFT JOIN tags t ON t.id = atg.tag_id
                GROUP BY
                    a.arcid, a.filename, a.title, a.summary, a.thumbhash,
                    a.created_at, a.updated_at, a.relative_path, a.file_size,
                    a.isnew, a.pagecount, a.last_read_time, a.progress
            """)

            logger.info("归档/标签相关表与视图初始化完成")
            return true
        } catch (e: Exception) {
            logger.error("初始化归档/标签相关表与视图失败: ${e.toString()}")
            return false
        }
    }
}
