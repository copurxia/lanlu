package lrr4cj.config

import std.database.sql.*
import std.sync.*
import std.collection.*
import std.time.*
import std.env.getVariable
import std.convert.*
import lrr4cj.utils.*

/**
 * 连接池配置
 */
public class PoolConfig {
    public var minConnections: Int64 = 2
    public var maxConnections: Int64 = 10
    public var acquireTimeoutMs: Int64 = 5000         // 获取连接超时 ms
    public var idleTimeoutMs: Int64 = 300000          // 空闲超时 ms（5分钟）
    public var leakDetectionThresholdMs: Int64 = 60000 // 泄漏检测阈值 ms（1分钟）
    public var validationEnabled: Bool = true          // 是否启用连接验证

    public init() {
        // 从环境变量读取配置
        let minStr = getVariable("POOL_MIN") ?? ""
        if (!minStr.isEmpty()) {
            try { this.minConnections = Int64.parse(minStr) } catch (_: Exception) {}
        }
        let maxStr = getVariable("POOL_MAX") ?? ""
        if (!maxStr.isEmpty()) {
            try { this.maxConnections = Int64.parse(maxStr) } catch (_: Exception) {}
        }
        let timeoutStr = getVariable("POOL_ACQUIRE_TIMEOUT") ?? ""
        if (!timeoutStr.isEmpty()) {
            try { this.acquireTimeoutMs = Int64.parse(timeoutStr) } catch (_: Exception) {}
        }
        let idleStr = getVariable("POOL_IDLE_TIMEOUT") ?? ""
        if (!idleStr.isEmpty()) {
            try { this.idleTimeoutMs = Int64.parse(idleStr) } catch (_: Exception) {}
        }
        let leakStr = getVariable("POOL_LEAK_THRESHOLD") ?? ""
        if (!leakStr.isEmpty()) {
            try { this.leakDetectionThresholdMs = Int64.parse(leakStr) } catch (_: Exception) {}
        }
        let validStr = getVariable("POOL_VALIDATION_ENABLED") ?? ""
        if (!validStr.isEmpty()) {
            this.validationEnabled = validStr == "true" || validStr == "1"
        }
    }
}

/**
 * 连接池统计信息
 */
public class PoolStats {
    public var totalConnections: Int64 = 0
    public var activeConnections: Int64 = 0
    public var idleConnections: Int64 = 0
    public var totalCreated: Int64 = 0
    public var totalDestroyed: Int64 = 0
    public var acquireWaitCount: Int64 = 0
    public var acquireTimeoutCount: Int64 = 0
}

/**
 * 连接池中的连接包装器
 */
public class PooledConnection {
    public var connection: Connection
    public var isInUse: Bool
    public var id: Int64               // 唯一标识符
    public var lastUsedTime: Int64     // 最后使用时间戳（毫秒）
    public var acquiredTime: Int64     // 获取时间戳（毫秒），用于泄漏检测

    public init(conn: Connection, id: Int64) {
        this.connection = conn
        this.isInUse = false
        this.id = id
        let now = DateTime.now().toUnixTimeStamp().toMilliseconds()
        this.lastUsedTime = now
        this.acquiredTime = 0
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
    private var config: PoolConfig = PoolConfig()

    // 连接池状态
    private var connections: ArrayList<PooledConnection> = ArrayList<PooledConnection>()
    private let poolMutex: Mutex = Mutex()
    private var isInitialized: Bool = false
    private var nextConnectionId: Int64 = 0       // 连接ID计数器
    private var pendingCreations: Int64 = 0       // 正在创建的连接数（防止并发超限）

    // 统计信息
    private var stats: PoolStats = PoolStats()

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
        logger.info("初始化连接池: min=${config.minConnections}, max=${config.maxConnections}")

        // 预创建最小连接数
        for (_ in 0..config.minConnections) {
            match (createNewConnection()) {
                case Some(conn) =>
                    let pooled = PooledConnection(conn, nextConnectionId)
                    nextConnectionId += 1
                    connections.add(pooled)
                    stats.totalCreated += 1
                case None =>
                    logger.error("初始化连接池失败：无法创建连接")
                    poolMutex.unlock()
                    return false
            }
        }

        stats.totalConnections = connections.size
        stats.idleConnections = connections.size
        isInitialized = true
        poolMutex.unlock()
        logger.info("连接池初始化完成: connections=${connections.size}")
        return true
    }

    /**
     * 获取连接（返回 ConnectionHandle 以支持精确释放）
     * 支持超时等待、连接验证和并发控制
     */
    public func getConnection(): Option<ConnectionHandle> {
        let logger = getLogger("connection_pool")
        let startTime = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let deadline = startTime + config.acquireTimeoutMs

        var attempts = 0
        let maxAttempts = (config.acquireTimeoutMs / 50) + 1  // 最大尝试次数

        while (attempts < maxAttempts) {
            attempts += 1
            poolMutex.lock()
            let now = DateTime.now().toUnixTimeStamp().toMilliseconds()

            // 检查超时
            if (now >= deadline) {
                stats.acquireTimeoutCount += 1
                poolMutex.unlock()
                logger.warn("获取连接超时: timeout=${config.acquireTimeoutMs}ms")
                return None
            }

            // 1. 查找空闲连接
            var foundIndex: Int64 = -1
            var invalidIndices = ArrayList<Int64>()

            for (i in 0..connections.size) {
                let pooled = connections[i]
                if (!pooled.isInUse) {
                    // 可选：验证连接有效性
                    if (config.validationEnabled && !isConnectionValid(pooled.connection)) {
                        invalidIndices.add(i)
                        continue
                    }
                    foundIndex = i
                    break
                }
            }

            // 移除无效连接
            if (!invalidIndices.isEmpty()) {
                var newConnections = ArrayList<PooledConnection>()
                for (i in 0..connections.size) {
                    var isInvalid = false
                    for (invalidIdx in invalidIndices) {
                        if (i == invalidIdx) {
                            isInvalid = true
                            break
                        }
                    }
                    if (isInvalid) {
                        let pooled = connections[i]
                        try { pooled.connection.close() } catch (_: Exception) {}
                        stats.totalDestroyed += 1
                        stats.totalConnections -= 1
                        logger.debug("移除无效连接: id=${pooled.id}")
                    } else {
                        newConnections.add(connections[i])
                    }
                }
                connections = newConnections
                // 重新查找空闲连接
                foundIndex = -1
                for (i in 0..connections.size) {
                    let pooled = connections[i]
                    if (!pooled.isInUse) {
                        foundIndex = i
                        break
                    }
                }
            }

            // 找到有效空闲连接
            if (foundIndex >= 0) {
                let pooled = connections[foundIndex]
                pooled.isInUse = true
                pooled.acquiredTime = now
                stats.activeConnections += 1
                stats.idleConnections -= 1
                let handle = ConnectionHandle(pooled.connection, pooled.id)
                poolMutex.unlock()
                logger.debug("复用现有连接: id=${pooled.id}")
                return Some(handle)
            }

            // 2. 检查是否可以创建新连接（含正在创建的）
            let totalPending = connections.size + pendingCreations
            if (totalPending < config.maxConnections) {
                let connId = nextConnectionId
                nextConnectionId += 1
                pendingCreations += 1
                poolMutex.unlock()

                match (createNewConnection()) {
                    case Some(conn) =>
                        poolMutex.lock()
                        pendingCreations -= 1
                        // 再次检查是否超限（防御性）
                        if (connections.size >= config.maxConnections) {
                            poolMutex.unlock()
                            try { conn.close() } catch (_: Exception) {}
                            logger.warn("创建连接后发现池已满，关闭新连接")
                            continue  // 重新尝试获取
                        }
                        let pooled = PooledConnection(conn, connId)
                        pooled.isInUse = true
                        pooled.acquiredTime = DateTime.now().toUnixTimeStamp().toMilliseconds()
                        connections.add(pooled)
                        stats.totalCreated += 1
                        stats.totalConnections += 1
                        stats.activeConnections += 1
                        poolMutex.unlock()
                        let handle = ConnectionHandle(conn, connId)
                        logger.debug("创建新连接: id=${connId}")
                        return Some(handle)
                    case None =>
                        poolMutex.lock()
                        pendingCreations -= 1
                        poolMutex.unlock()
                        logger.error("无法创建新连接")
                        return None
                }
            }

            // 3. 达到上限，等待后重试
            stats.acquireWaitCount += 1
            poolMutex.unlock()

            // 等待一小段时间后重试
            let remainingMs = deadline - DateTime.now().toUnixTimeStamp().toMilliseconds()
            if (remainingMs <= 0) {
                stats.acquireTimeoutCount += 1
                logger.warn("连接池已满，无可用连接")
                return None
            }

            // 简单等待 50ms 后重试
            let waitMs = if (remainingMs < 50) { remainingMs } else { 50 }
            sleep(Duration.millisecond * waitMs)
        }

        // 超过最大尝试次数
        stats.acquireTimeoutCount += 1
        logger.warn("连接池已满，获取连接失败")
        return None
    }

    /**
     * 释放连接（归还到池中）
     * 通过连接池内部ID精确匹配要释放的连接
     */
    public func releaseConnection(poolId: Int64): Unit {
        poolMutex.lock()
        let logger = getLogger("connection_pool")
        let now = DateTime.now().toUnixTimeStamp().toMilliseconds()
        for (pooled in connections) {
            if (pooled.id == poolId && pooled.isInUse) {
                pooled.isInUse = false
                pooled.lastUsedTime = now
                pooled.acquiredTime = 0
                stats.activeConnections -= 1
                stats.idleConnections += 1
                logger.debug("释放连接: id=${poolId}")
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
     * 获取连接池统计信息
     */
    public func getStats(): PoolStats {
        poolMutex.lock()
        let result = PoolStats()
        result.totalConnections = stats.totalConnections
        result.activeConnections = stats.activeConnections
        result.idleConnections = stats.idleConnections
        result.totalCreated = stats.totalCreated
        result.totalDestroyed = stats.totalDestroyed
        result.acquireWaitCount = stats.acquireWaitCount
        result.acquireTimeoutCount = stats.acquireTimeoutCount
        poolMutex.unlock()
        return result
    }

    /**
     * 检测连接泄漏（返回可能泄漏的连接数）
     */
    public func detectLeaks(): Int64 {
        poolMutex.lock()
        let logger = getLogger("connection_pool")
        let now = DateTime.now().toUnixTimeStamp().toMilliseconds()
        var leakCount: Int64 = 0

        for (pooled in connections) {
            if (pooled.isInUse && pooled.acquiredTime > 0) {
                let holdTime = now - pooled.acquiredTime
                if (holdTime > config.leakDetectionThresholdMs) {
                    leakCount += 1
                    logger.warn("检测到可能的连接泄漏: id=${pooled.id}, holdTime=${holdTime}ms")
                }
            }
        }

        poolMutex.unlock()
        return leakCount
    }

    /**
     * 清理空闲连接（回收超时的空闲连接）
     * 保留至少 minConnections 个连接
     */
    public func cleanupIdleConnections(): Int64 {
        poolMutex.lock()
        let logger = getLogger("connection_pool")
        let now = DateTime.now().toUnixTimeStamp().toMilliseconds()
        var cleanedCount: Int64 = 0

        // 只有当连接数超过最小值时才清理
        if (connections.size <= config.minConnections) {
            poolMutex.unlock()
            return 0
        }

        var newConnections = ArrayList<PooledConnection>()
        var keptCount: Int64 = 0

        for (pooled in connections) {
            let shouldKeep = pooled.isInUse ||
                keptCount < config.minConnections ||
                (now - pooled.lastUsedTime) < config.idleTimeoutMs

            if (shouldKeep) {
                newConnections.add(pooled)
                keptCount += 1
            } else {
                try { pooled.connection.close() } catch (_: Exception) {}
                stats.totalDestroyed += 1
                stats.totalConnections -= 1
                stats.idleConnections -= 1
                cleanedCount += 1
                logger.debug("清理空闲连接: id=${pooled.id}")
            }
        }

        connections = newConnections
        poolMutex.unlock()

        if (cleanedCount > 0) {
            logger.info("清理了 ${cleanedCount} 个空闲连接")
        }
        return cleanedCount
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
