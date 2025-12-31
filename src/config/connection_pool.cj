package lrr4cj.config

import std.database.sql.*
import std.sync.*
import std.collection.*
import lrr4cj.utils.*

/**
 * 连接池中的连接包装器
 */
public class PooledConnection {
    public var connection: Connection
    public var isInUse: Bool
    public var id: Int64  // 唯一标识符

    public init(conn: Connection, id: Int64) {
        this.connection = conn
        this.isInUse = false
        this.id = id
    }
}

/**
 * 连接句柄，用于追踪从连接池获取的连接
 * 包含连接本身和连接池内部ID，用于精确释放
 */
public class ConnectionHandle {
    public let connection: Connection
    public let poolId: Int64  // 连接池内部ID，用于释放时精确匹配

    public init(conn: Connection, poolId: Int64) {
        this.connection = conn
        this.poolId = poolId
    }
}

/**
 * 数据库连接池
 * 线程安全的连接池实现，复用数据库连接以提升性能
 */
public class ConnectionPool {
    // 单例实例
    private static var instance: Option<ConnectionPool> = Option<ConnectionPool>.None
    private static let instanceMutex: Mutex = Mutex()

    // 连接池配置
    private var minConnections: Int64 = 2
    private var maxConnections: Int64 = 10

    // 连接池状态
    private var connections: ArrayList<PooledConnection> = ArrayList<PooledConnection>()
    private let poolMutex: Mutex = Mutex()
    private var isInitialized: Bool = false
    private var nextConnectionId: Int64 = 0  // 连接ID计数器

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
        poolMutex.lock()
        if (isInitialized) {
            poolMutex.unlock()
            return true
        }

        let logger = getLogger("connection_pool")
        logger.info("初始化连接池", ("min", minConnections.toString()), ("max", maxConnections.toString()))

        // 预创建最小连接数
        for (_ in 0..minConnections) {
            match (createNewConnection()) {
                case Some(conn) =>
                    let pooled = PooledConnection(conn, nextConnectionId)
                    nextConnectionId += 1
                    connections.add(pooled)
                case None =>
                    logger.error("初始化连接池失败：无法创建连接")
                    poolMutex.unlock()
                    return false
            }
        }

        isInitialized = true
        poolMutex.unlock()
        logger.info("连接池初始化完成", ("connections", connections.size.toString()))
        return true
    }

    /**
     * 获取连接（返回 ConnectionHandle 以支持精确释放）
     */
    public func getConnection(): Option<ConnectionHandle> {
        poolMutex.lock()
        let logger = getLogger("connection_pool")

        // 1. 查找空闲连接（不在锁内验证连接，直接标记使用）
        for (pooled in connections) {
            if (!pooled.isInUse) {
                pooled.isInUse = true
                let handle = ConnectionHandle(pooled.connection, pooled.id)
                poolMutex.unlock()
                logger.debug("复用现有连接", ("id", pooled.id.toString()))
                return Some(handle)
            }
        }

        // 2. 如果没有空闲连接且未达上限，创建新连接
        if (connections.size < maxConnections) {
            // 先释放锁再创建连接，避免长时间持有锁
            let connId = nextConnectionId
            nextConnectionId += 1
            poolMutex.unlock()

            match (createNewConnection()) {
                case Some(conn) =>
                    poolMutex.lock()
                    let pooled = PooledConnection(conn, connId)
                    pooled.isInUse = true
                    connections.add(pooled)
                    poolMutex.unlock()
                    let handle = ConnectionHandle(conn, connId)
                    logger.debug("创建新连接", ("id", connId.toString()))
                    return Some(handle)
                case None =>
                    logger.error("无法创建新连接")
                    return None
            }
        }

        // 3. 达到上限，返回失败
        poolMutex.unlock()
        logger.warn("连接池已满，无可用连接")
        return None
    }

    /**
     * 释放连接（归还到池中）
     * 通过连接池内部ID精确匹配要释放的连接
     */
    public func releaseConnection(poolId: Int64): Unit {
        poolMutex.lock()
        let logger = getLogger("connection_pool")
        for (pooled in connections) {
            if (pooled.id == poolId && pooled.isInUse) {
                pooled.isInUse = false
                logger.debug("释放连接", ("id", poolId.toString()))
                break
            }
        }
        poolMutex.unlock()
    }

    /**
     * 释放连接句柄（便捷方法）
     */
    public func releaseHandle(handle: ConnectionHandle): Unit {
        releaseConnection(handle.poolId)
    }

    /**
     * 检查连接有效性
     */
    private func isConnectionValid(conn: Connection): Bool {
        try {
            let stmt = conn.prepareStatement("SELECT 1")
            let rs = stmt.query()
            rs.close()
            stmt.close()
            return true
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * 创建新的数据库连接
     */
    private func createNewConnection(): Option<Connection> {
        let drvopt = DatabaseConfig.getDriver()
        match (drvopt) {
            case Some(drv) =>
                let connStr = DatabaseConfig.getConnectionString()
                let ds = drv.open(connStr)
                try {
                    let conn = ds.connect()
                    return Some(conn)
                } catch (e: Exception) {
                    getLogger("connection_pool").error("创建连接失败", ("error", e.message))
                    return None
                }
            case None =>
                return None
        }
    }

    /**
     * 关闭连接池
     */
    public func shutdown(): Unit {
        poolMutex.lock()
        let logger = getLogger("connection_pool")
        for (pooled in connections) {
            try {
                pooled.connection.close()
            } catch (_: Exception) {}
        }
        connections.clear()
        isInitialized = false
        poolMutex.unlock()
        logger.info("连接池已关闭")
    }
}
