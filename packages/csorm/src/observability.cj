package csorm

/**
 * 可观测性 / Mock / 连接选项(对标 sea-orm metric.rs / mock.rs / ConnectOptions)。
 *
 * - MetricInfo + setMetricCallback：每次 query/exec 的耗时/失败回调。
 * - MockDatabase：预设 (sql → rows) 映射，无需真实 DB 即可单测 DAO 层。
 * - ConnectOptions：通用连接选项(poolSize / timeout 等)，具体连接串格式由 driver 决定。
 */
import std.collection.*
import std.convert.*
import std.sync.*
import std.time.*

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
 * 在执行内记录耗时与失败状态，回调给用户。
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
 * Mock 行：实现后端无关 Row 接口，供 MockDatabase 返回预设行。
 * 通过列名索引读取值。
 */
public class MockRow <: Row {
    let data: HashMap<String, String>
    let nullCols: HashSet<String>
    let colNames: Array<String>
    let nameIndex: HashMap<String, Int64>

    public init(data: HashMap<String, String>, nullCols: HashSet<String>,
        colNames: Array<String>) {
        this.data = data
        this.nullCols = nullCols
        this.colNames = colNames
        let m = HashMap<String, Int64>()
        for (i in 0..colNames.size) {
            m[colNames[i]] = Int64(i)
        }
        this.nameIndex = m
    }

    /** 便捷构造：列名 + 值(均非空)。 */
    public init(names: Array<String>, values: Array<String>) {
        let d = HashMap<String, String>()
        let nc = HashSet<String>()
        for (i in 0..names.size) {
            if (i < values.size) {
                d[names[i]] = values[i]
            }
        }
        this.data = d
        this.nullCols = nc
        this.colNames = names
        let m = HashMap<String, Int64>()
        for (i in 0..names.size) {
            m[names[i]] = Int64(i)
        }
        this.nameIndex = m
    }

    func idx(col: String): Int64 {
        match (nameIndex.get(col)) {
            case Some(i) => i
            case None => throw CsormError("MockRow: column not found: " + col)
        }
    }

    public func columnCount(): Int64 { Int64(colNames.size) }
    public func columnName(i: Int64): String { colNames[i] }
    public func columnOid(i: Int64): Int32 { 0 }
    public func isNull(col: Int64): Bool { nullCols.contains(colNames[col]) }
    public func isNull(col: String): Bool { nullCols.contains(col) }
    public func rawValue(col: Int64): String {
        match (data.get(colNames[col])) { case Some(s) => s; case None => "" }
    }
    public func rawValue(col: String): String {
        match (data.get(col)) { case Some(s) => s; case None => "" }
    }

    public func getText(col: Int64): String { rawValue(col) }
    public func getText(col: String): String { rawValue(col) }
    public func getOrNullText(col: Int64): ?String {
        if (isNull(col)) { None } else { Some(rawValue(col)) }
    }
    public func getOrNullText(col: String): ?String {
        if (isNull(col)) { None } else { Some(rawValue(col)) }
    }

    public func getInt64(col: Int64): Int64 {
        try { Int64.parse(rawValue(col).trimAscii()) } catch (_: Exception) { 0 }
    }
    public func getInt64(col: String): Int64 { getInt64(idx(col)) }
    public func getOrNullInt64(col: Int64): ?Int64 {
        if (isNull(col)) { None } else {
            try { Some(Int64.parse(rawValue(col).trimAscii())) } catch (_: Exception) { Some(0) }
        }
    }
    public func getOrNullInt64(col: String): ?Int64 { getOrNullInt64(idx(col)) }

    public func getInt32(col: Int64): Int32 { Int32(getInt64(col)) }
    public func getInt32(col: String): Int32 { Int32(getInt64(col)) }
    public func getOrNullInt32(col: Int64): ?Int32 {
        match (getOrNullInt64(col)) { case Some(v) => Some(Int32(v)); case None => None }
    }
    public func getOrNullInt32(col: String): ?Int32 { getOrNullInt32(idx(col)) }

    public func getBool(col: Int64): Bool {
        let s = rawValue(col).trimAscii()
        s == "t" || s == "true" || s == "TRUE" || s == "1"
    }
    public func getBool(col: String): Bool { getBool(idx(col)) }
    public func getOrNullBool(col: Int64): ?Bool {
        if (isNull(col)) { None } else { Some(getBool(col)) }
    }
    public func getOrNullBool(col: String): ?Bool { getOrNullBool(idx(col)) }

    public func getFloat64(col: Int64): Float64 {
        try { Float64.parse(rawValue(col).trimAscii()) } catch (_: Exception) { 0.0 }
    }
    public func getFloat64(col: String): Float64 { getFloat64(idx(col)) }
    public func getOrNullFloat64(col: Int64): ?Float64 {
        if (isNull(col)) { None } else {
            try { Some(Float64.parse(rawValue(col).trimAscii())) } catch (_: Exception) { Some(0.0) }
        }
    }
    public func getOrNullFloat64(col: String): ?Float64 { getOrNullFloat64(idx(col)) }

    public func getBytes(col: Int64): Array<UInt8> { rawValue(col).toArray() }
    public func getBytes(col: String): Array<UInt8> { getBytes(idx(col)) }
    public func getOrNullBytes(col: Int64): ?Array<UInt8> {
        if (isNull(col)) { None } else { Some(rawValue(col).toArray()) }
    }
    public func getOrNullBytes(col: String): ?Array<UInt8> { getOrNullBytes(idx(col)) }

    public func getJson(col: Int64): String { getText(col) }
    public func getJson(col: String): String { getText(col) }
    public func getOrNullJson(col: Int64): ?String { getOrNullText(col) }
    public func getOrNullJson(col: String): ?String { getOrNullText(col) }

    public func getTextArray(col: Int64): Array<String> {
        let s = rawValue(col)
        // 简化：按逗号分割(去掉花括号)
        let trimmed = s.trimAscii()
        if (trimmed == "{}" || trimmed.isEmpty()) { return Array<String>() }
        var inner = trimmed
        if (trimmed.startsWith("{")) {
            inner = trimmed[1..trimmed.size - 1]
        }
        inner.split(",")
    }
    public func getTextArray(col: String): Array<String> { getTextArray(idx(col)) }

    public func getInt64Array(col: Int64): Array<Int64> {
        let toks = getTextArray(col)
        Array<Int64>(toks.size, { i =>
            try { Int64.parse(toks[i].trimAscii()) } catch (_: Exception) { 0 }
        })
    }
    public func getInt64Array(col: String): Array<Int64> { getInt64Array(idx(col)) }

    public func getInt32Array(col: Int64): Array<Int32> {
        let arr = getInt64Array(col)
        Array<Int32>(arr.size, { i => Int32(arr[i]) })
    }
    public func getInt32Array(col: String): Array<Int32> { getInt32Array(idx(col)) }
}

/**
 * Mock 数据库：预设 (sql → rows) 映射，无需真实 DB 即可单测 DAO 层。
 * 实现后端无关 DriverConn 接口，让 DAO 层无感切换。
 */
public class MockDatabase <: DriverConn {
    // 预设响应：(sql 包含匹配串) → (rows, affected)
    let queryResponses = ArrayList<(String, Array<Row>)>()
    let execResponses = ArrayList<(String, Int64)>()
    // 记录所有调用(供测试断言)
    let callLog = ArrayList<String>()
    let mockDialect: Dialect

    public init() {
        mockDialect = PgCompatDialect()
    }

    public init(dialect: Dialect) {
        mockDialect = dialect
    }

    public func backend(): DbBackend { mockDialect.backend() }
    public func dialect(): Dialect { mockDialect }

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

    func logCall(sql: String): Unit { callLog.add(sql) }

    public func queryAll(sql: String, params: Array<Value>): Array<Row> {
        logCall(sql)
        for ((matchStr, rows) in queryResponses) {
            if (sql.contains(matchStr)) {
                return rows
            }
        }
        Array<Row>()
    }

    public func queryOne(sql: String, params: Array<Value>): ?Row {
        let rows = queryAll(sql, params)
        if (rows.size == 0) { return None }
        Some(rows[0])
    }

    public func streamQuery(sql: String, params: Array<Value>, chunkSize: Int64, cb: (Array<Row>) -> Unit): Unit {
        let rows = queryAll(sql, params)
        if (rows.size > 0) { cb(rows) }
    }

    public func exec(sql: String, params: Array<Value>): Int64 {
        logCall(sql)
        for ((matchStr, affected) in execResponses) {
            if (sql.contains(matchStr)) {
                return affected
            }
        }
        0
    }

    public func execSql(sql: String): Unit { logCall(sql) }

    public func begin(): Unit { logCall("BEGIN") }
    public func commit(): Unit { logCall("COMMIT") }
    public func rollback(): Unit { logCall("ROLLBACK") }
    public func inTransaction(): Bool { false }

    public func transaction(body: () -> Unit): Unit {
        begin()
        try {
            body()
            commit()
        } catch (e: Exception) {
            rollback()
            throw e
        }
    }

    public func save(name: String): Unit { logCall("SAVEPOINT " + name) }
    public func rollback(name: String): Unit { logCall("ROLLBACK TO " + name) }
    public func release(name: String): Unit { logCall("RELEASE " + name) }

    public func cancel(): Bool { false }
    public func close(): Unit { callLog.clear() }
    public func poolSize(): Int64 { 1 }

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
 * 通用连接选项：集中管理 poolSize / timeout 等。
 * 具体连接串格式由各 driver 自行处理。
 */
public struct ConnectOptions {
    public let connString: String
    public var poolSize: Int64 = 10
    public var minPoolSize: Int64 = 0
    public var idleTimeoutMs: Int64 = 0
    public var statementTimeoutMs: Int64 = 0     // 0 = 不设
    public var connectTimeoutMs: Int64 = 0       // 0 = 不设
    public var sslMode: String = ""

    public init(connString: String) {
        this.connString = connString
    }

    /** 生成带 options 覆盖的连接串(把 pool.* 和 libpq 选项拼入——PG 专用)。 */
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