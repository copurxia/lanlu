package lanlu.shared.config

import ace_orm.*
import std.collection.*
import std.convert.*
import std.sync.*
import stdx.log.*
import cjdotenv.load
import std.env.getVariable
import lanlu.shared.utils.*
import std.fs.exists

/**
 * 数据库配置与访问门面(ACE-ORM 后端)。
 *
 * 持有全局 DataSource(单例,经 DataSourceManager 管理),提供 DAO 用的查询/写入/事务封装。
 * SQL 占位符统一用 PG 规范 $n(经 ParamList 构造或手写),绑定值用 DbValue 数组。
 * 查询结果用 ACE Row 按列名读取(getText/getInt/getBool/getJson)。
 *
 * 旧 std.database.sql.Connection/Statement/QueryResult 接口已彻底移除;
 * 旧 opengauss 驱动已移除。取消查询走 ACE PostgresDriver.cancel()(PQcancel FFI)。
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
        if (connStr.isEmpty()) {
            return "postgres"
        }
        let parts = connStr.split("://")
        if (parts.size >= 2) {
            return parts[0]
        }
        return "postgres"
    }

    public static func getConnectionString(): String {
        let logger = getLogger("database")
        logger.debug("Using database connection string from DB_STRING")
        logger.debug("DB type: ${dbType}")
        return dbString
    }

    /** 获取 ACE Driver(便捷,等价 DataSourceManager.driver())。 */
    public static func driver(): Driver {
        return DataSourceManager.driver()
    }

    /** 获取 DataSource(供 transaction 等用)。 */
    public static func dataSource(): DataSource {
        return DataSourceManager.getInstance()
    }

    /**
     * 在查询超时保护下执行操作。timeoutMs > 0 时起看门狗线程,到期调 driver().cancel()
     * 发送 PostgreSQL CancelRequest;timeoutMs <= 0 时不启用取消。
     * ACE PostgresDriver.query/exec 是同步阻塞的,看门狗在另一线程取消正在跑的连接。
     */
    public static func withTimeout<T>(timeoutMs: Int64, operation: () -> T): T {
        if (timeoutMs <= 0) {
            return operation()
        }
        let completed = AtomicBool(false)
        let _ = spawn {
            sleep(Duration.millisecond * timeoutMs)
            if (!completed.load()) {
                try { let _ = driver().cancel() } catch (_: Exception) {}
            }
        }
        try {
            let r = operation()
            completed.store(true)
            return r
        } catch (e: Exception) {
            completed.store(true)
            throw e
        }
    }

    /**
     * 查询单行。无结果或异常时返回 defaultValue。
     * - sql 用 $n 占位符,params 为对应 DbValue 数组。
     * - map 接收 Row(首行),按列名读取。
     */
    public static func queryOne<T>(
        loggerName: String,
        errorMessage: String,
        sql: String,
        params: Array<DbValue>,
        defaultValue: T,
        map: (Row) -> T
    ): T {
        let logger = getLogger(loggerName)
        try {
            return withTimeout<T>(queryTimeoutMs, { =>
                let rows = driver().query(sql, params)
                if (rows.size > 0) {
                    return map(rows[0])
                }
                return defaultValue
            })
        } catch (e: Exception) {
            logger.error(errorMessage, ("error", e.message))
            return defaultValue
        }
    }

    /**
     * 查询多行。异常时返回空数组。
     */
    public static func queryList<T>(
        loggerName: String,
        errorMessage: String,
        sql: String,
        params: Array<DbValue>,
        map: (Row) -> T
    ): Array<T> {
        let logger = getLogger(loggerName)
        try {
            return withTimeout<Array<T>>(queryTimeoutMs, { =>
                let rows = driver().query(sql, params)
                let out = ArrayList<T>()
                for (r in rows) {
                    out.add(map(r))
                }
                out.toArray()
            })
        } catch (e: Exception) {
            logger.error(errorMessage, ("error", e.message))
            return Array<T>()
        }
    }

    /**
     * 执行写语句(INSERT/UPDATE/DELETE/DDL)。异常时返回 false。
     */
    public static func execute(
        loggerName: String,
        errorMessage: String,
        sql: String,
        params: Array<DbValue>
    ): Bool {
        let logger = getLogger(loggerName)
        try {
            withTimeout<Unit>(queryTimeoutMs, { =>
                driver().exec(sql, params)
            })
            return true
        } catch (e: Exception) {
            logger.error(errorMessage, ("error", e.message))
            return false
        }
    }

    /**
     * 执行 RETURNING id 模式的写入,返回首行 id。异常或无返回时 None。
     */
    public static func executeReturningId(
        loggerName: String,
        errorMessage: String,
        sql: String,
        params: Array<DbValue>
    ): Option<Int64> {
        let logger = getLogger(loggerName)
        try {
            return withTimeout<Option<Int64>>(queryTimeoutMs, { =>
                let rows = driver().query(sql, params)
                if (rows.size > 0) {
                    let id = rows[0].getInt("id")
                    if (id > 0) {
                        return Some(id)
                    }
                }
                None
            })
        } catch (e: Exception) {
            logger.error(errorMessage, ("error", e.message))
            return None
        }
    }

    /**
     * 事务:operation 返回 false 或抛异常时回滚。
     * operation 不再接收 conn 参数(ACE 用 ThreadLocal 钉事务连接,内部 driver.exec/query 自动走该连接)。
     */
    public static func withTransaction(
        loggerName: String,
        errorMessage: String,
        operation: () -> Bool
    ): Bool {
        let logger = getLogger(loggerName)
        // 用容器包装结果(lambda 不能捕获 mutable 变量,也不能直接 return 外层)。
        let result = ArrayList<Bool>(0)
        try {
            dataSource().transaction({
                =>
                let ok = operation()
                if (!ok) {
                    throw Exception("transaction rolled back by operation returning false")
                }
                result.add(true)
            })
            if (result.size > 0) {
                return result[0]
            }
            // transaction 体未添加(理论上不会到这,因 operation 成功必 add,失败必抛)
            return false
        } catch (e: Exception) {
            logger.error(errorMessage, ("error", e.message))
            return false
        }
    }

    /**
     * 在事务连接上执行写语句(事务内复用,供 withTransaction 的 operation 体调用)。
     * ACE 下 driver.exec 自动走 ThreadLocal 钉的事务连接,故等价于 execute。
     */
    public static func executeInTxn(
        loggerName: String,
        errorMessage: String,
        sql: String,
        params: Array<DbValue>
    ): Bool {
        return execute(loggerName, errorMessage, sql, params)
    }

    /**
     * 批量执行(同一 SQL 多次绑定)。返回总受影响行数。异常时返回 0。
     * ACE 无 PreparedStatement 复用,每次 exec 独立调用(连接池复用连接)。
     */
    public static func executeBatch(
        loggerName: String,
        errorMessage: String,
        sql: String,
        binds: Array<Array<DbValue>>
    ): Int64 {
        let logger = getLogger(loggerName)
        try {
            var total: Int64 = 0
            for (params in binds) {
                driver().exec(sql, params)
                let aff = driver().affectedRows()
                if (aff > 0) {
                    total += aff
                }
            }
            return total
        } catch (e: Exception) {
            logger.error(errorMessage, ("error", e.message))
            return 0
        }
    }

    // ===== PG 特定类型便捷绑定(返回 DbValue,供 params 数组用) =====

    /** 构造 PG text[] 绑定值。 */
    public static func textArray(values: Array<String>): DbValue {
        DbArray(Array<DbValue>(values.size, { i => DbText(values[i]) }))
    }

    /** 构造 PG bigint[] 绑定值。 */
    public static func int64Array(values: Array<Int64>): DbValue {
        DbArray(Array<DbValue>(values.size, { i => DbInt(values[i]) }))
    }

    /** 构造 JSONB 绑定值(text 协议承载 JSON 文本)。空串归一为 {}。 */
    public static func jsonb(json: String): DbValue {
        let normalized = json.trimAscii()
        return DbText(if (normalized.size > 0) { normalized } else { "{}" })
    }

    /** 构造 JSONB 数组绑定值。空串归一为 []。 */
    public static func jsonbArray(json: String): DbValue {
        let normalized = json.trimAscii()
        return DbText(if (normalized.size > 0) { normalized } else { "[]" })
    }

    /** Option<String> → DbValue。 */
    public static func optionText(v: Option<String>): DbValue {
        match (v) {
            case Some(s) => DbText(s)
            case None => DbNull
        }
    }

    /** Option<Int64> → DbValue。 */
    public static func optionInt64(v: Option<Int64>): DbValue {
        match (v) {
            case Some(i) => DbInt(i)
            case None => DbNull
        }
    }

    // ===== SQLSTATE 错误判定(从 OrmException.code 读取) =====

    public static func sqlStateOf(e: Exception): String {
        match (e) {
            case oe: OrmException => oe.code
            case _ => ""
        }
    }

    public static func isUniqueViolation(e: Exception): Bool {
        sqlStateOf(e) == "23505"
    }

    public static func isForeignKeyViolation(e: Exception): Bool {
        sqlStateOf(e) == "23503"
    }

    public static func isDeadlockOrSerializationFailure(e: Exception): Bool {
        let state = sqlStateOf(e)
        return state == "40P01" || state == "40001"
    }

    public static func isConnectionFailure(e: Exception): Bool {
        sqlStateOf(e).startsWith("08")
    }

    // ===== Row 便捷读取(按列名,缺列/类型不符回退默认) =====

    public static func getString(row: Row, col: String): String {
        row.getText(col)
    }

    public static func getInt64(row: Row, col: String): Int64 {
        row.getInt(col)
    }

    public static func getInt32(row: Row, col: String): Int32 {
        Int32(row.getInt(col))
    }

    public static func getBool(row: Row, col: String): Bool {
        row.getBool(col)
    }

    public static func getJson(row: Row, col: String): String {
        row.getJson(col)
    }

    /** 初始化数据源(主入口,main.cj 调用)。 */
    public static func initializePool(): Bool {
        return DataSourceManager.initialize(getConnectionString())
    }

    /** 查询取消(供外部超时控制;通常经 withTimeout 自动调用)。 */
    public static func cancelStatement(): Bool {
        return driver().cancel()
    }
}