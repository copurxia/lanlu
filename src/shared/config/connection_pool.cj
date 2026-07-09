package lanlu.shared.config

import std.sync.*
import std.env.getVariable
import std.convert.*
import lanlu.shared.utils.*
import csorm.*
import postgresql_driver.PgConn
import postgresql_driver.PGDriver
import postgresql_driver.PGDatasource
import std.database.sql.*

/**
 * 连接池配置(从环境变量读取)。
 * postgresql-driver 原生支持连接串中的 pool.max/pool.min/pool.idleTimeout，
 * 故本配置只读环境变量后拼接到连接串。
 */
public class PoolConfig {
    public var maxConnections: Int32 = 10
    public var minConnections: Int32 = 0
    public var idleTimeoutMs: Int64 = 300000          // 空闲超时 ms（5分钟）

    public init() {
        let maxStr = getVariable("POOL_MAX") ?? ""
        if (!maxStr.isEmpty()) {
            try { this.maxConnections = Int32.parse(maxStr) } catch (_: Exception) {}
        }
        let minStr = getVariable("POOL_MIN") ?? ""
        if (!minStr.isEmpty()) {
            try { this.minConnections = Int32.parse(minStr) } catch (_: Exception) {}
        }
        let idleStr = getVariable("POOL_IDLE_TIMEOUT") ?? ""
        if (!idleStr.isEmpty()) {
            try { this.idleTimeoutMs = Int64.parse(idleStr) } catch (_: Exception) {}
        }
    }
}

public class ConnectionPoolStats {
    public var open: Int64 = 0
    public var idle: Int64 = 0
    public var inUse: Int64 = 0
    public var broken: Int64 = 0
    public var closed: Int64 = 0

    public init() {}
}

/**
 * 数据库连接池：基于 csorm.Database 的单例封装。
 * 经 PGDriver(DriverManager) → PGDatasource → Database(ds) 路径构造，
 * 底层复用 postgresql-driver 的 ConnectionPool(PGconn 句柄池)。
 * 若 Datasource 路径失败则回退到 Database(connStr) 旧入口。
 */
public class ConnectionPool {
    private static var instance: Option<ConnectionPool> = Option<ConnectionPool>.None
    private static let instanceMutex: Mutex = Mutex()

    private var config: PoolConfig = PoolConfig()
    private var db: Option<Database> = None
    private var isInitialized: Bool = false

    private init() {}

    public static func getInstance(): ConnectionPool {
        instanceMutex.lock()
        match (instance) {
            case Some(pool) =>
                instanceMutex.unlock()
                return pool
            case None =>
                let pool = ConnectionPool()
                instance = Some(pool)
                instanceMutex.unlock()
                return pool
        }
    }

    /**
     * 初始化连接池：经 PgConn 构造 csorm.Database。
     * 优先走 PGDriver().open() → PGDatasource → PgConn(pgDatabase) → Database，
     * 失败则回退 Database(PgConn(connStr))。
     */
    public func initialize(): Bool {
        if (isInitialized) {
            return true
        }
        let logger = getLogger("connection_pool")
        logger.info("初始化连接池: max=${config.maxConnections}, min=${config.minConnections}, idleTimeout=${config.idleTimeoutMs}ms")

        try {
            let connStr = buildConnStr()
            var database: ?Database = None
            try {
                let ds = PGDriver().open(connStr, Array<(String, String)>())
                match (ds as PGDatasource) {
                    case Some(pds) =>
                        database = Some(Database(PgConn(pds.pgDatabase())))
                        logger.info("连接池经 PGDriver/Datasource 构造")
                    case None =>
                        throw Exception("not a PGDatasource")
                }
            } catch (dsErr: Exception) {
                logger.warn("Datasource 路径失败，回退到 Database(PgConn(connStr)): ${dsErr.message}")
                database = Some(Database(PgConn(connStr)))
            }
            match (database) {
                case Some(d) =>
                    db = Some(d)
                    isInitialized = true
                    let _ = healthCheck()
                    logger.info("连接池初始化完成")
                    return true
                case None =>
                    logger.error("连接池构造返回 None")
                    return false
            }
        } catch (e: Exception) {
            logger.error("初始化连接池失败: ${e.message}")
            return false
        }
    }

    /** 用 ConnectOptions 把 pool.* 参数拼到连接串(postgresql-driver conninfo.cj 解析 pool.max/pool.min/pool.idleTimeout)。 */
    func buildConnStr(): String {
        let base = DatabaseConfig.getConnectionString()
        var opts = ConnectOptions(base)
        opts.poolSize = Int64(config.maxConnections)
        opts.minPoolSize = Int64(config.minConnections)
        opts.idleTimeoutMs = config.idleTimeoutMs
        opts.toConnectionString()
    }

    /**
     * 获取 Database 句柄(单例，事务/查询均复用同一 Database)。
     * 底层 PGDatabase 的连接池负责并发借还 PGconn。
     */
    public func getDatabase(): Option<Database> {
        match (db) {
            case Some(d) => Some(d)
            case None =>
                getLogger("connection_pool").error("连接池未初始化")
                None
        }
    }

    public func shutdown(): Unit {
        let logger = getLogger("connection_pool")
        match (db) {
            case Some(d) =>
                d.close()
                db = None
                isInitialized = false
                logger.info("连接池已关闭")
            case None => ()
        }
    }

    public func isClosed(): Bool { !isInitialized }

    public func stats(): ConnectionPoolStats {
        let s = ConnectionPoolStats()
        match (db) {
            case Some(d) =>
                s.open = d.poolSize()
                s.idle = 0   // driver 未暴露 idle 计数，置 0
            case None => ()
        }
        s
    }

    public func healthCheck(): Bool {
        match (getDatabase()) {
            case Some(d) =>
                try {
                    match (d.rawOne<Int64>("SELECT 1", [], { r => r.getInt64(0) })) {
                        case Some(_) => return true
                        case None => return false
                    }
                } catch (e: Exception) {
                    getLogger("connection_pool").warn("连接池健康检查失败", ("error", e.message))
                    return false
                }
            case None => return false
        }
    }
}