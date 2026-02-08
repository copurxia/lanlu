package lanlu.config

import std.database.sql.*
import std.sync.*
import std.env.getVariable
import std.convert.*
import lanlu.utils.*

/**
 * 连接池配置
 */
public class PoolConfig {
    public var maxConnections: Int32 = 10
    public var connectionTimeoutMs: Int64 = 5000      // 获取连接超时 ms
    public var idleTimeoutMs: Int64 = 300000          // 空闲超时 ms（5分钟）
    public var maxLifeTimeMs: Int64 = 1800000         // 连接最大生命周期 ms（30分钟）
    public var keepaliveTimeMs: Int64 = 60000         // 健康检查间隔 ms（1分钟）

    public init() {
        // 从环境变量读取配置
        let maxStr = getVariable("POOL_MAX") ?? ""
        if (!maxStr.isEmpty()) {
            try { this.maxConnections = Int32.parse(maxStr) } catch (_: Exception) {}
        }
        let timeoutStr = getVariable("POOL_ACQUIRE_TIMEOUT") ?? ""
        if (!timeoutStr.isEmpty()) {
            try { this.connectionTimeoutMs = Int64.parse(timeoutStr) } catch (_: Exception) {}
        }
        let idleStr = getVariable("POOL_IDLE_TIMEOUT") ?? ""
        if (!idleStr.isEmpty()) {
            try { this.idleTimeoutMs = Int64.parse(idleStr) } catch (_: Exception) {}
        }
        let lifeStr = getVariable("POOL_MAX_LIFETIME") ?? ""
        if (!lifeStr.isEmpty()) {
            try { this.maxLifeTimeMs = Int64.parse(lifeStr) } catch (_: Exception) {}
        }
        let keepaliveStr = getVariable("POOL_KEEPALIVE") ?? ""
        if (!keepaliveStr.isEmpty()) {
            try { this.keepaliveTimeMs = Int64.parse(keepaliveStr) } catch (_: Exception) {}
        }
    }
}

/**
 * 数据库连接池
 * 基于标准库 PooledDatasource 的封装
 */
public class ConnectionPool {
    // 单例实例
    private static var instance: Option<ConnectionPool> = Option<ConnectionPool>.None
    private static let instanceMutex: Mutex = Mutex()

    // 连接池配置
    private var config: PoolConfig = PoolConfig()

    // 标准库连接池
    private var pooledDs: Option<PooledDatasource> = None
    private var isInitialized: Bool = false

    private init() {}

    /**
     * 获取单例实例
     */
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
     * 初始化连接池
     */
    public func initialize(): Bool {
        if (isInitialized) {
            return true
        }

        let logger = getLogger("connection_pool")
        logger.info("初始化连接池: max=${config.maxConnections}, maxIdle=0(unlimited)")

        let drvopt = DatabaseConfig.getDriver()
        match (drvopt) {
            case Some(drv) =>
                let connStr = DatabaseConfig.getConnectionString()
                let ds = drv.open(connStr)
                let pool = PooledDatasource(ds)

                // 配置连接池参数
                pool.maxSize = config.maxConnections
                // 0 means no max-idle cap for this pool implementation.
                pool.maxIdleSize = 0
                pool.connectionTimeout = Duration.millisecond * config.connectionTimeoutMs
                pool.idleTimeout = Duration.millisecond * config.idleTimeoutMs
                pool.maxLifeTime = Duration.millisecond * config.maxLifeTimeMs
                pool.keepaliveTime = Duration.millisecond * config.keepaliveTimeMs

                pooledDs = Some(pool)
                isInitialized = true
                logger.info("连接池初始化完成")
                return true
            case None =>
                logger.error("初始化连接池失败：无法获取数据库驱动")
                return false
        }
    }

    /**
     * 获取连接
     */
    public func getConnection(): Option<Connection> {
        let logger = getLogger("connection_pool")
        match (pooledDs) {
            case Some(pool) =>
                try {
                    let conn = pool.connect()
                    return Some(conn)
                } catch (e: Exception) {
                    logger.error("获取连接失败: ${e.message}")
                    return None
                }
            case None =>
                logger.error("连接池未初始化")
                return None
        }
    }

    /**
     * 关闭连接池
     */
    public func shutdown(): Unit {
        let logger = getLogger("connection_pool")
        match (pooledDs) {
            case Some(pool) =>
                pool.close()
                pooledDs = None
                isInitialized = false
                logger.info("连接池已关闭")
            case None => ()
        }
    }

    /**
     * 检查连接池是否已关闭
     */
    public func isClosed(): Bool {
        match (pooledDs) {
            case Some(pool) => pool.isClosed()
            case None => true
        }
    }
}
