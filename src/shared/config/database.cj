package lanlu.shared.config

import std.convert.*
import stdx.log.*
import cjdotenv.load
import std.env.getVariable
import lanlu.shared.utils.*
import std.fs.exists
import csorm.*

/**
 * 数据库配置类 —— csorm 薄封装。
 * DAO 层通过 DatabaseConfig.getDatabase() 拿到 csorm.Database，
 * 再用 builder/RawQuery/Repo/EEntity 进行 CRUD。
 * 事务走 db.transaction { ... }；超时走 db.withTimeout(ms) { ... }。
 */
public class DatabaseConfig {
    public static var dbString: String
    public static var dbType: String
    public static var queryTimeoutMs: Int64

    static init() {
        if (exists(".env")) {
            load()
        }
        dbString = getVariable("DB_STRING") ?? "postgres://lgr:lgr@127.0.0.1:5432/lgr?sslmode=disable"
        dbType = parseDbType(dbString)
        let queryTimeoutStr = getVariable("DB_QUERY_TIMEOUT_MS") ?? ""
        queryTimeoutMs = if (queryTimeoutStr.size > 0) {
            try { Int64.parse(queryTimeoutStr) } catch (_: Exception) { 0i64 }
        } else {
            0i64
        }
    }

    private static func parseDbType(connStr: String): String {
        if (connStr.isEmpty()) { return "postgres" }
        let parts = connStr.split("://")
        if (parts.size >= 2) { return parts[0] }
        "postgres"
    }

    public static func getConnectionString(): String {
        let logger = getLogger("database")
        logger.debug("Using database connection string from DB_STRING")
        logger.debug("DB type: ${dbType}")
        dbString
    }

    /**
     * 获取 csorm.Database 句柄(单例连接池)。
     * 替代旧 getPooledConnection / createConnection。
     */
    public static func getDatabase(): Option<Database> {
        ConnectionPool.getInstance().getDatabase()
    }

    /** 初始化连接池。 */
    public static func initializePool(): Bool {
        let ok = ConnectionPool.getInstance().initialize()
        if (ok) {
            setupObservability()
        }
        ok
    }

    // ===== 可观测性埋点（L6 落地） =====
    /**
     * 设置全局 metric 回调 + query 日志开关。
     * 慢查询(>500ms)与失败 SQL 统一记录到 logger；QueryLog 受 CSORM_QUERY_LOG 环境变量控制。
     */
    static func setupObservability(): Unit {
        let logger = getLogger("database_metric")
        // 全局 metric 回调：记录慢查询与失败 SQL
        DatabaseMetric.setMetricCallback({ info: MetricInfo =>
            if (info.failed) {
                logger.error("SQL 失败", ("context", info.context), ("elapsed_ms", info.elapsed.toMilliseconds().toString()), ("sql", info.sql))
            } else if (info.elapsed.toMilliseconds() > 500) {
                logger.warn("慢查询", ("context", info.context), ("elapsed_ms", info.elapsed.toMilliseconds().toString()), ("sql", info.sql))
            } else {
                logger.debug("SQL 执行", ("context", info.context), ("elapsed_ms", info.elapsed.toMilliseconds().toString()))
            }
        })
        // QueryLog 开关：CSORM_QUERY_LOG=true 时启用
        let logEnabled = getVariable("CSORM_QUERY_LOG") ?? ""
        if (logEnabled == "true" || logEnabled == "1") {
            QueryLog.enable()
        }
    }

    /** 启用 csorm query 日志(调试用)。 */
    public static func enableQueryLog(): Unit {
        QueryLog.enable()
    }

    /** 禁用 csorm query 日志。 */
    public static func disableQueryLog(): Unit {
        QueryLog.disable()
    }

    // ===== 事务封装 =====
    /**
     * 在事务中执行 operation。未在事务中则 BEGIN/COMMIT/ROLLBACK；已在事务中则直接执行。
     * operation 收到当前 Database 句柄(事务内复用同一底层连接)。
     * 返回 false 或抛异常时回滚。
     */
    public static func withTransaction(operation: (Database) -> Bool): Bool {
        match (getDatabase()) {
            case Some(db) =>
                let okCell = Array<Bool>(1, { _ => false })
                try {
                    db.transaction({ d =>
                        let r = operation(d)
                        okCell[0] = r
                        if (!r) { throw Exception("transaction: operation returned false") }
                    })
                    return okCell[0]
                } catch (e: Exception) {
                    getLogger("database").error("transaction failed: ${e.message}")
                    return false
                }
            case None =>
                getLogger("database").error("cannot connect to database")
                return false
        }
    }

    // ===== 超时封装 =====
    /**
     * 带全局查询超时执行 body。queryTimeoutMs <= 0 时不启用超时。
     */
    public static func withQueryTimeout<T>(body: () -> T): T {
        match (getDatabase()) {
            case Some(db) => db.withTimeout<T>(queryTimeoutMs, body)
            case None => throw Exception("cannot connect to database")
        }
    }

    // ===== 错误分类(基于 csorm.CsormError，供调用方判定约束冲突) =====
    public static func sqlStateOf(e: Exception): String {
        match (e) {
            case ce: CsormError => ce.sqlstate
            case _ => ""
        }
    }

    public static func isUniqueViolation(e: Exception): Bool {
        match (e) {
            case ce: CsormError => ce.isUniqueViolation()
            case _ => false
        }
    }

    public static func isForeignKeyViolation(e: Exception): Bool {
        match (e) {
            case ce: CsormError => ce.isForeignKeyViolation()
            case _ => false
        }
    }

    public static func isDeadlockOrSerializationFailure(e: Exception): Bool {
        match (e) {
            case ce: CsormError => ce.isDeadlockOrSerializationFailure()
            case _ => false
        }
    }

    public static func isConnectionFailure(e: Exception): Bool {
        match (e) {
            case ce: CsormError => ce.isConnectionError()
            case _ => false
        }
    }
}