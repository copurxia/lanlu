package lrr4cj.config

import std.database.sql.*
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
     * 使用完毕后需调用 conn.close() 归还连接到池中
     */
    public static func getPooledConnection(): Option<Connection> {
        return ConnectionPool.getInstance().getConnection()
    }

    /**
     * 初始化连接池
     */
    public static func initializePool(): Bool {
        return ConnectionPool.getInstance().initialize()
    }

    // 注意：数据库表初始化已由迁移系统处理
    // 原 initializeDatabase() 和 initializeArchiveSchema() 方法已移除
    // 请参考 src/migrations/ 目录下的迁移文件

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
