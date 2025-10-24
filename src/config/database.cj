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
        Dotenv.config()
        
        // 从环境变量读取配置
        dbType = getVariable("DB_TYPE") ?? "postgres"
        host = getVariable("DB_HOST") ?? "127.0.0.1"
        
        let portStr = getVariable("DB_PORT") ?? "5432"
        port = Int32.parse(portStr)
        
        database = getVariable("DB_NAME") ?? "lgr"
        username = getVariable("DB_USER") ?? "lgr"
        password = getVariable("DB_PASSWORD") ?? "lgr"
        ssl = getVariable("DB_SSL") ?? "disable"
    }
    
    /**
     * 获取数据库连接字符串
     */
    public static func getConnectionString(): String {
        return dbType + "://" + username + ":" + password + "@" + host + ":" + port.toString() + "/" + database + "?sslmode=" + ssl
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
                    getLogger("database").error("数据库连接失败")
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
        let connOpt = createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // 创建归档表
                    let createArchivesTable = "CREATE TABLE IF NOT EXISTS archives (id SERIAL PRIMARY KEY, arcid VARCHAR(40) NOT NULL UNIQUE, filename TEXT NOT NULL, title TEXT, summary TEXT, thumbhash VARCHAR(40), created_at TIMESTAMP DEFAULT now(), updated_at TIMESTAMP DEFAULT now(), relative_path TEXT, file_size BIGINT, isnew BOOLEAN DEFAULT false, pagecount INTEGER, last_read_time TIMESTAMP WITH TIME ZONE, progress INTEGER DEFAULT 0)"
                    
                    // 创建分类表
                    let createCategoriesTable = "CREATE TABLE IF NOT EXISTS categories (id SERIAL PRIMARY KEY, catid VARCHAR(20) NOT NULL UNIQUE, name VARCHAR(255) NOT NULL, search TEXT, is_static BOOLEAN DEFAULT false, created_at TIMESTAMP DEFAULT now(), pinned BOOLEAN DEFAULT false, updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP)"
                    
                    // 创建标签表
                    let createTagsTable = "CREATE TABLE IF NOT EXISTS tags (id SERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL, namespace VARCHAR(100), value TEXT, weight INTEGER DEFAULT 1)"
                    
                    // 创建归档分类关联表
                    let createArchiveCategoriesTable = "CREATE TABLE IF NOT EXISTS archive_categories (archive_id INTEGER REFERENCES archives(id) ON DELETE CASCADE, category_id INTEGER REFERENCES categories(id) ON DELETE CASCADE, PRIMARY KEY (archive_id, category_id))"
                    
                    // 创建归档标签关联表
                    let createArchiveTagsTable = "CREATE TABLE IF NOT EXISTS archive_tags (archive_id INTEGER REFERENCES archives(id) ON DELETE CASCADE, tag_id INTEGER REFERENCES tags(id) ON DELETE CASCADE, PRIMARY KEY (archive_id, tag_id))"
                    
                    // 创建单行本表
                    let createTankoubonsTable = "CREATE TABLE IF NOT EXISTS tankoubons (id SERIAL PRIMARY KEY, tankid VARCHAR(40) NOT NULL UNIQUE, name VARCHAR(255) NOT NULL, summary TEXT, tags TEXT, locked BOOLEAN DEFAULT false, created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP)"
                    
                    // 创建单行本归档关联表
                    let createTankoubonArchivesTable = "CREATE TABLE IF NOT EXISTS tankoubon_archives (tankoubon_id INTEGER REFERENCES tankoubons(id) ON DELETE CASCADE, archive_id INTEGER REFERENCES archives(id) ON DELETE CASCADE, position INTEGER NOT NULL, PRIMARY KEY (tankoubon_id, archive_id))"
                    
                    // 创建任务队列表
                    let createMinionJobsTable = "CREATE TABLE IF NOT EXISTS minion_jobs (id VARCHAR(40) PRIMARY KEY, task VARCHAR(50) NOT NULL, state VARCHAR(20) DEFAULT 'inactive', notes TEXT, error TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"
                    
                    // 执行建表语句
                    let stmt1 = conn.prepareStatement(createArchivesTable)
                    stmt1.update()
                    
                    let stmt2 = conn.prepareStatement(createCategoriesTable)
                    stmt2.update()
                    
                    let stmt3 = conn.prepareStatement(createTagsTable)
                    stmt3.update()
                    
                    let stmt4 = conn.prepareStatement(createArchiveCategoriesTable)
                    stmt4.update()
                    
                    let stmt5 = conn.prepareStatement(createArchiveTagsTable)
                    stmt5.update()
                    
                    let stmt6 = conn.prepareStatement(createTankoubonsTable)
                    stmt6.update()
                    
                    let stmt7 = conn.prepareStatement(createTankoubonArchivesTable)
                    stmt7.update()
                    
                    let stmt8 = conn.prepareStatement(createMinionJobsTable)
                    stmt8.update()
                    
                    // 创建archives_with_tags视图
                    let createArchivesWithTagsView = """
                    CREATE OR REPLACE VIEW archives_with_tags AS
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
                        COALESCE(
                            STRING_AGG(
                                CASE
                                    WHEN t.namespace IS NOT NULL AND t.namespace != ''
                                    THEN t.namespace || ':' || t.value
                                    ELSE t.value
                                END,
                                ', '
                            ),
                            ''
                        ) as tags
                    FROM archives a
                    LEFT JOIN archive_tags at ON a.id = at.archive_id
                    LEFT JOIN tags t ON at.tag_id = t.id
                    GROUP BY a.arcid, a.filename, a.title, a.summary, a.thumbhash, a.created_at, a.updated_at, a.relative_path, a.file_size, a.isnew, a.pagecount, a.last_read_time, a.progress
                    """
                    
                    let stmt9 = conn.prepareStatement(createArchivesWithTagsView)
                    stmt9.update()
                    
                    conn.close()
                    return true
                } catch (e: Exception) {
                    getLogger("database").error("数据库初始化失败")
                    return false
                }
            case None =>
                getLogger("database").error("无法连接到数据库")
                return false
        }
    }
}