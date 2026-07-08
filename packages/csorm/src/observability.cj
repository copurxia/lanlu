package csorm

/**
 * 可观测性 / Mock / 连接选项(对标 sea-orm metric.rs / mock.rs / ConnectOptions)。
 *
 * - MetricInfo + setMetricCallback：每次 query/exec 的耗时/失败回调。
 * - MockDatabase：预设 (sql → rows) 映射，无需真实 PG 即可单测 DAO 层。
 * - ConnectOptions：poolSize / statementTimeout / connectTimeout / sslMode 集中管理。
 */
import std.collection.*
import std.convert.*
import std.sync.*
import std.time.*
import postgresql_driver.*

// ===== 7.1 Metric callback =====

/**
 * 单次 query/exec 的度量信息(对标 sea-orm metric::Info)。
 */
public struct MetricInfo {
    public let sql: String
    public let params: Array<Value>
    public let elapsed: Duration
    public let failed: Bool
    public let context: String    // 操作上下文(如 "select all"、"insert")

    public init(sql: String, params: Array<Value>, elapsed: Duration, failed: Bool, context: String) {
        this.sql = sql
        this.params = params
        this.elapsed = elapsed
        this.failed = failed
        this.context = context
    }
}

/**
 * metric 回调类型：(MetricInfo) -> Unit。
 */
public type MetricCallback = (MetricInfo) -> Unit

/**
 * 扩展 Database：setMetricCallback 埋点。
 * 在 wrapRun 内记录耗时与失败状态，回调给用户。
 */
public class DatabaseMetric {
    static var callback: ?MetricCallback = None
    static let mu = Mutex()

    /** 设置全局 metric 回调(所有 Database 实例共享)。 */
    public static func setMetricCallback(cb: MetricCallback): Unit {
        synchronized(mu) { callback = Some(cb) }
    }

    /** 清除回调。 */
    public static func clearMetricCallback(): Unit {
        synchronized(mu) { callback = None }
    }

    /** 取当前回调(内部用)。 */
    static func getCallback(): ?MetricCallback {
        synchronized(mu) { callback }
    }

    /** 记录一次度量(若回调存在)。 */
    public static func record(sql: String, params: Array<Value>, elapsed: Duration, failed: Bool, context: String): Unit {
        match (getCallback()) {
            case Some(cb) => cb(MetricInfo(sql, params, elapsed, failed, context))
            case None => ()
        }
    }
}

// 给 Database 加 metric 便捷方法
extend Database {
    /** 设置 metric 回调(实例便捷入口，转发到全局)。 */
    public func setMetricCallback(cb: MetricCallback): Unit {
        DatabaseMetric.setMetricCallback(cb)
    }

    /** 带 metric 埋点执行(供内部或用户手动调用)。 */
    public func withMetric<T>(context: String, sql: String, params: Array<Value>, body: () -> T): T {
        let start = MonoTime.now()
        var failed = false
        try {
            let r = body()
            DatabaseMetric.record(sql, params, MonoTime.now() - start, false, context)
            r
        } catch (e: Exception) {
            failed = true
            DatabaseMetric.record(sql, params, MonoTime.now() - start, true, context)
            throw e
        }
    }
}

// ===== 7.2 Tracing 集成(可选，接 stdx.log) =====

/**
 * 简易 query 日志(若接入 stdx.log 可替换为 logger.debug)。
 * 当前仅 println，供调试；可经 setMetricCallback 接入正式 tracing。
 */
public class QueryLog {
    static var enabled = false

    public static func enable(): Unit { enabled = true }
    public static func disable(): Unit { enabled = false }

    public static func log(sql: String, elapsed: Duration, failed: Bool): Unit {
        if (enabled) {
            let status = if (failed) { "FAIL" } else { "OK" }
            println("[csorm-query] ${status} ${elapsed.toMicroseconds()}μs ${sql}")
        }
    }
}

// ===== 7.3 MockDatabase =====

/**
 * Mock 数据库：预设 (sql 模式 → rows) 映射，无需真实 PG 即可单测 DAO 层。
 * 实现 std.database.sql.Datasource 之外，也提供与 Database 一致的 raw/all/one/exec 接口，
 * 让 DAO 层无感切换。
 */
public class MockDatabase {
    // 预设响应：(sql 包含匹配串) → (rows, affected)
    let queryResponses = ArrayList<(String, Array<Row>)>()
    let execResponses = ArrayList<(String, Int64)>()
    // 记录所有调用(供测试断言)
    let callLog = ArrayList<String>()

    public init() {}

    /** 预设查询响应：当 SQL 包含 matchStr 时返回 rows。 */
    public func expectQuery(matchStr: String, rows: Array<Row>): MockDatabase {
        queryResponses.add((matchStr, rows))
        this
    }

    /** 预设写语句响应：当 SQL 包含 matchStr 时返回 affected。 */
    public func expectExec(matchStr: String, affected: Int64): MockDatabase {
        execResponses.add((matchStr, affected))
        this
    }

    /** 记录调用(内部)。 */
    func logCall(sql: String): Unit {
        callLog.add(sql)
    }

    /** 查询：按 matchStr 顺序匹配，返回预设 rows；未匹配则空数组。 */
    public func query(sql: String, params: Array<PGValue>): Array<Row> {
        logCall(sql)
        for ((matchStr, rows) in queryResponses) {
            if (sql.contains(matchStr)) {
                return rows
            }
        }
        Array<Row>()
    }

    /** 查询单行：返回首行或 None。 */
    public func queryOne(sql: String, params: Array<PGValue>): ?Row {
        let rows = query(sql, params)
        if (rows.size == 0) { return None }
        Some(rows[0])
    }

    /** 写语句：返回预设 affected；未匹配则 0。 */
    public func exec(sql: String, params: Array<PGValue>): Int64 {
        logCall(sql)
        for ((matchStr, affected) in execResponses) {
            if (sql.contains(matchStr)) {
                return affected
            }
        }
        0
    }

    /** 原始 SQL 执行(mock：记录但不执行)。 */
    public func execSql(sql: String): Unit {
        logCall(sql)
    }

    /** 原始 SQL 执行(mock：返回预设 affected 或 0)。 */
    public func execRaw(sql: String, params: Array<Value>): Int64 {
        logCall(sql)
        for ((matchStr, affected) in execResponses) {
            if (sql.contains(matchStr)) {
                return affected
            }
        }
        0
    }

    /** 原始 SQL 执行(mock：记录)。 */
    public func execRawSql(sql: String): Unit {
        logCall(sql)
    }

    /** 取调用记录(供测试断言)。 */
    public func calls(): Array<String> {
        callLog.toArray()
    }

    /** 调用次数。 */
    public func callCount(): Int64 {
        Int64(callLog.size)
    }

    /** 清空预设与调用记录。 */
    public func reset(): Unit {
        queryResponses.clear()
        execResponses.clear()
        callLog.clear()
    }
}

// ===== 7.4 ConnectOptions =====

/**
 * 连接选项：集中管理 poolSize / statementTimeout / connectTimeout / sslMode 等。
 * 解析连接串 + 覆盖，产出给 PGDatabase / PGDatasource 使用。
 */
public struct ConnectOptions {
    public let connString: String
    public var poolSize: Int64 = 10
    public var minPoolSize: Int64 = 0
    public var idleTimeoutMs: Int64 = 0
    public var statementTimeoutMs: Int64 = 0     // 0 = 不设
    public var connectTimeoutMs: Int64 = 0       // 0 = 不设
    public var sslMode: String = ""              // disable/allow/prefer/require/verify-ca/verify-full

    public init(connString: String) {
        this.connString = connString
    }

    /** 生成带 options 覆盖的连接串(把 pool.* 和 libpq 选项拼入)。 */
    public func toConnectionString(): String {
        let sb = StringBuilder()
        sb.append(connString)
        // 如果原串无 pool.max，追加
        if (!connString.contains("pool.max=")) {
            let sep = if (connString.contains("?")) { "&" } else { "?" }
            sb.append(sep)
            sb.append("pool.max=")
            sb.append(poolSize.toString())
            if (minPoolSize > 0) {
                sb.append("&pool.min=")
                sb.append(minPoolSize.toString())
            }
            if (idleTimeoutMs > 0) {
                sb.append("&pool.idleTimeout=")
                sb.append(idleTimeoutMs.toString())
            }
        }
        // statement_timeout / connect_timeout 作为 libpq session 参数
        if (statementTimeoutMs > 0 || connectTimeoutMs > 0 || sslMode != "") {
            var sep = if (connString.contains("?") || sb.toString().contains("?")) { "&" } else { "?" }
            if (statementTimeoutMs > 0) {
                sb.append(sep)
                sb.append("options=")
                sb.append("-c statement_timeout=")
                sb.append(statementTimeoutMs.toString())
                sep = "&"
            }
            if (connectTimeoutMs > 0) {
                sb.append(sep)
                sb.append("connect_timeout=")
                sb.append((connectTimeoutMs / 1000).toString())
                sep = "&"
            }
            if (sslMode != "") {
                sb.append(sep)
                sb.append("sslmode=")
                sb.append(sslMode)
            }
        }
        sb.toString()
    }

    /** 从连接串解析默认 ConnectOptions(pool.* 从串中提取)。 */
    public static func parse(connString: String): ConnectOptions {
        var opts = ConnectOptions(connString)
        // 简化：仅识别 pool.max
        let s = connString
        let needle = "pool.max="
        if (s.contains(needle)) {
            // 提取数字
            match (indexOfStr(s, needle)) {
                case Some(i) =>
                    let rest = s[i + needle.size..s.size]
                    var num = ""
                    for (c in rest.toArray()) {
                        if (c >= 48u8 && c <= 57u8) {
                            num += String.fromUtf8(Array<UInt8>(1, { _ => c }))
                        } else {
                            break
                        }
                    }
                    if (!num.isEmpty()) {
                        let parsed = parseInt64Safe(num)
                        if (parsed > 0) {
                            opts.poolSize = parsed
                        }
                    }
                case None => ()
            }
        }
        opts
    }
}

/** 在 hay 中查找 needle 的起始索引。 */
func indexOfStr(hay: String, needle: String): ?Int64 {
    let h = hay.toArray()
    let nd = needle.toArray()
    if (nd.size == 0 || h.size < nd.size) { return None }
    for (i in 0..h.size - nd.size + 1) {
        var matched = true
        for (j in 0..nd.size) {
            if (h[i + j] != nd[j]) { matched = false; break }
        }
        if (matched) { return Some(Int64(i)) }
    }
    None
}

/** 安全解析 Int64(失败返回 0)。 */
func parseInt64Safe(s: String): Int64 {
    var result: Int64 = 0
    try {
        result = Int64.parse(s.trimAscii())
    } catch (_: Exception) {
        result = 0
    }
    result
}