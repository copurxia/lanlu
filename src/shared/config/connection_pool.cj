package lanlu.shared.config

import ace_orm.*
import std.sync.*
import std.env.getVariable
import std.convert.*
import lanlu.shared.utils.*

/**
 * 数据源管理(替代旧 ConnectionPool)。
 *
 * 基于 ACE PostgresDriver + DataSource,单例。连接池由 ACE ConnectionPool 内部管理
 * (max/min/idle 回收),事务由 DataSource.transaction + ThreadLocal 钉连接保证同连接。
 * 全局数据源经 setGlobalDataSource 注册,供 @Transactional 织入。
 */
public class DataSourceManager {
    private static var instance: Option<DataSource> = Option<DataSource>.None
    private static let instanceMutex = Mutex()

    private init() {}

    /** 获取单例 DataSource(未初始化时抛异常)。 */
    public static func getInstance(): DataSource {
        synchronized(instanceMutex) {
            match (instance) {
                case Some(ds) => return ds
                case None => throw OrmException("DataSourceManager not initialized")
            }
        }
    }

    /** 是否已初始化。 */
    public static func isInitialized(): Bool {
        synchronized(instanceMutex) {
            match (instance) {
                case Some(_) => return true
                case None => return false
            }
        }
    }

    /**
     * 初始化数据源:构造 PostgresDriver(含连接池) + DataSource,注册为全局数据源。
     * conninfo 形如 "postgres://user:pass@host:port/db?sslmode=disable"(libpq URI)。
     * 返回 true 表示成功。
     */
    public static func initialize(conninfo: String): Bool {
        synchronized(instanceMutex) {
            var alreadyInit = false
            match (instance) {
                case Some(_) => alreadyInit = true
                case None => ()
            }
            if (alreadyInit) {
                return true
            }
            let logger = getLogger("datasource_manager")
            logger.info("初始化数据源(ACE PostgresDriver)")
            // 从环境变量读取连接池配置,附加到 conninfo(pool.max/pool.min/pool.idleTimeout)。
            let poolMax = getVariable("POOL_MAX") ?? ""
            let fullConninfo = if (poolMax.size > 0) {
                "${conninfo} pool.max=${poolMax}"
            } else {
                conninfo
            }
            try {
                let drv = PostgresDriver(fullConninfo)
                let ds = DataSource(drv)
                setGlobalDataSource(ds)
                instance = Some(ds)
                logger.info("数据源初始化完成")
                return true
            } catch (e: Exception) {
                logger.error("数据源初始化失败", ("error", e.message))
                return false
            }
        }
    }

    /** 获取驱动(便捷,等价 getInstance().driver)。 */
    public static func driver(): Driver {
        getInstance().driver
    }

    /** 关闭数据源(关闭连接池)。 */
    public static func shutdown(): Unit {
        synchronized(instanceMutex) {
            match (instance) {
                case Some(ds) =>
                    ds.driver.close()
                    instance = None
                    getLogger("datasource_manager").info("数据源已关闭")
                case None => ()
            }
        }
    }

    /** 健康检查(SELECT 1)。 */
    public static func healthCheck(): Bool {
        if (!isInitialized()) {
            return false
        }
        try {
            let rows = driver().query("SELECT 1", [])
            return rows.size > 0
        } catch (e: Exception) {
            getLogger("datasource_manager").warn("健康检查失败", ("error", e.message))
            return false
        }
    }
}

/** 连接池统计(兼容旧 API,从 ACE ConnectionPool 读取,部分指标不可得返回 -1)。 */
public class ConnectionPoolStats {
    public var open: Int64 = -1
    public var idle: Int64 = -1
    public var inUse: Int64 = -1
    public var broken: Int64 = -1
    public var closed: Int64 = -1
    public init() {}
}