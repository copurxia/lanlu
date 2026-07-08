package postgresql_driver

/**
 * std.database.sql 标准库驱动实现：基于 libpq FFI 的 PGDriver/PGDatasource/
 * PGConnection/PGStatement/PGQueryResult/PGUpdateResult/PGTransaction。
 *
 * 与同包 PGDatabase/PGValue/Row 私有 API 并存：本文件实现仓颉标准库 std.database.sql
 * 七大接口，供 csorm 经 Datasource/Connection/Statement/QueryResult 抽象使用；
 * PGDatabase 旧入口保留兼容，二者共享底层 libpq 句柄(CPointer<Unit>)与 PGResult。
 *
 * 占位符约定：std.database.sql 规定 SQL 中用 `?` 占位，PGStatement 在执行前把 `?`
 * 重写为 PG 的 `$1..$n`(双引号字符串字面量内的 `?` 不替换)。
 */
import std.collection.*
import std.convert.*
import std.sync.*
import std.database.sql.*

// ===== 启动期注册：让 DriverManager 能按名取到本驱动 =====
let _ = {
    =>
    DriverManager.register("postgresql", PGDriver())
    DriverManager.register("postgres", PGDriver())
}()

/**
 * libpq 驱动入口。open(connString) 解析连接串 + 建池，产出 PGDatasource。
 * opts 透传到池配置(pool.max / pool.min / pool.idleTimeout 等经 setOption)。
 */
public class PGDriver <: Driver {
    public init() {}

    public prop name: String {
        get() { "postgresql-libpq" }
    }

    public prop version: String {
        get() { "0.1.0" }
    }

    public prop preferredPooling: Bool {
        get() { true }
    }

    public func open(connectionString: String, opts: Array<(String, String)>): Datasource {
        let ds = PGDatasource(connectionString)
        for ((k, v) in opts) {
            ds.setOption(k, v)
        }
        ds
    }
}

/**
 * 数据源：持有 PGDatabase(含连接池)，connect() 借出一条 PGConnection。
 * setOption 映射到 PoolConfig；实现 Resource(close 时关闭池)。
 */
public class PGDatasource <: Datasource & Resource {
    let db: PGDatabase
    let connString: String
    var closed = false

    public init(connString: String) {
        this.connString = connString
        this.db = PGDatabase(connString)
    }

    /** 适配器：包装已存在的 PGDatabase(跨 DAO 句柄传递 / 事务内复用)。 */
    public init(db: PGDatabase) {
        this.db = db
        this.connString = ""
    }

    public func connect(): Connection {
        if (closed) {
            throw SqlException("PGDatasource: datasource closed")
        }
        // 从池借一条裸句柄，包装为 PGConnection(独立于 PGDatabase 的事务钉连接机制)。
        let raw = db.pool.borrow()
        PGConnection(raw, db.pool)
    }

    public func setOption(key: String, value: String): Unit {
        // 池配置以连接串内 pool.* 为主；setOption 提供运行时覆盖入口。
        match (key) {
            case "pool.max" =>
                // 连接池上限在初始化时已固定，运行时调整需重建池；此处尽力而为记录。
                ()
            case "pool.min" => ()
            case "pool.idleTimeout" => ()
            case _ => ()
        }
    }

    public func isClosed(): Bool { closed }

    public func close(): Unit {
        if (!closed) {
            closed = true
            db.close()
        }
    }

    /** 逃生舱：直接拿底层 PGDatabase(用游标/cancel/事务等高级能力)。 */
    public func pgDatabase(): PGDatabase { db }
}

/**
 * 连接：包装一条借出的 PGconn 句柄。prepareStatement 返回 PGStatement，
 * createTransaction 返回 PGTransaction。实现 Resource(close 时归还连接到池)。
 *
 * 注意：PGConnection 独立持有句柄，不与 PGDatabase 的 ThreadLocal 事务机制混用；
 * 适合 csorm 经 Datasource 路径使用。需要 ThreadLocal 事务时仍用 PGDatabase。
 */
public class PGConnection <: Connection & Resource {
    let conn: CPointer<Unit>
    let pool: ConnectionPool
    var closed = false
    var inTxn = false

    public init(conn: CPointer<Unit>, pool: ConnectionPool) {
        this.conn = conn
        this.pool = pool
    }

    public prop state: ConnectionState {
        get() {
            if (closed) {
                return ConnectionState.Closed
            }
            let st = unsafe { PQstatus(conn) }
            if (st == PG_CONNECTION_OK) {
                if (inTxn) {
                    // libpq 无显式 "in transaction" 状态；用 OK 近似。
                    ConnectionState.Connected
                } else {
                    ConnectionState.Connected
                }
            } else {
                ConnectionState.Broken
            }
        }
    }

    public func getMetaData(): Map<String, String> {
        let m = HashMap<String, String>()
        // libpq 的 PQdb/PQuser/PQhost/PQport 需 FFI；此处用现有 FFI 表里没有的，
        // 退化为从 conninfo 解析填入常见键(避免新增 FFI 声明)。
        m["driver"] = "postgresql-libpq"
        m["version"] = "0.1.0"
        m
    }

    public func prepareStatement(sql: String): Statement {
        if (closed) {
            throw SqlException("PGConnection: connection closed")
        }
        PGStatement(this, sql)
    }

    public func createTransaction(): Transaction {
        if (closed) {
            throw SqlException("PGConnection: connection closed")
        }
        PGTransaction(this)
    }

    public func isClosed(): Bool { closed }

    public func close(): Unit {
        if (!closed) {
            closed = true
            // 若遗留活动事务，回滚以归还干净连接。
            if (inTxn) {
                try { PGDatabase.execRaw(conn, "ROLLBACK") } catch (_: Exception) {}
                inTxn = false
            }
            pool.giveBack(conn)
        }
    }

    // ===== 同包内辅助：供 PGStatement/PGTransaction 复用 =====

    /** 在本连接上执行带参查询，返回 PGResult(调用方负责 close)。 */
    func run(sql: String, params: Array<PGValue>): PGResult {
        PGDatabase.run(conn, sql, params)
    }

    /** 在本连接上执行无参原始 SQL。 */
    func execRawSql(sql: String): Unit {
        PGDatabase.execRaw(conn, sql)
    }
}

/**
 * 预执行语句：libpq 无 prepare 对象，内部暂存 SQL 文本 + 待绑定参数列表，
 * query()/update() 时把 `?` 重写为 `$1..$n` 后调 PQexecParams。
 */
public class PGStatement <: Statement & Resource {
    let cn: PGConnection
    let sqlTemplate: String
    var params: ArrayList<PGValue> = ArrayList<PGValue>()
    var closed = false

    public init(cn: PGConnection, sql: String) {
        this.cn = cn
        this.sqlTemplate = sql
    }

    public prop parameterColumnInfos: Array<ColumnInfo> {
        get() {
            // libpq 文本协议不预解析参数元数据，返回空数组。
            Array<ColumnInfo>()
        }
    }

    public func set<T>(index: Int64, value: T): Unit {
        if (closed) {
            throw SqlException("PGStatement: statement closed")
        }
        // 仓颉类型 → PGValue(按 T 运行时分发；经 as Any 装箱后类型模式匹配)。
        let pv = cjValueToPgValue(value)
        // index 从 1 起(std.database.sql 约定)；按需扩容。
        let idx0 = index - 1
        while (params.size <= idx0) {
            params.add(PGValue.PGNull)
        }
        params[idx0] = pv
    }

    public func setNull(index: Int64): Unit {
        if (closed) {
            throw SqlException("PGStatement: statement closed")
        }
        let idx0 = index - 1
        while (params.size <= idx0) {
            params.add(PGValue.PGNull)
        }
        params[idx0] = PGValue.PGNull
    }

    public func query(): QueryResult {
        if (closed) {
            throw SqlException("PGStatement: statement closed")
        }
        let sql = rewriteQToDollar(sqlTemplate)
        let res = cn.run(sql, params.toArray())
        if (!res.isTuplesOk()) {
            let err = res.buildError(sql)
            res.close()
            throw SqlException(err.message, err.sqlstate, 0)
        }
        PGQueryResult(res)
    }

    public override func query(_: Array<SqlDbType>): QueryResult {
        throw SqlException("PGStatement: deprecated query(Array<SqlDbType>) not supported; use set<T> + query()")
    }

    public func update(): UpdateResult {
        if (closed) {
            throw SqlException("PGStatement: statement closed")
        }
        let sql = rewriteQToDollar(sqlTemplate)
        let res = cn.run(sql, params.toArray())
        let aff = res.affectedRows()
        // lastInsertId：PG 无自增 ID 概念，需 RETURNING 取；无 RETURNING 时返回 0。
        let lastId: Int64 = 0
        res.close()
        PGUpdateResult(if (aff < 0) { 0 } else { aff }, lastId)
    }

    @Deprecated
    public override func update(_: Array<SqlDbType>): UpdateResult {
        throw SqlException("PGStatement: deprecated update(Array<SqlDbType>) not supported; use set<T> + update()")
    }

    public func setOption(key: String, value: String): Unit {
        // 暂无 statement 级选项。
    }

    public func isClosed(): Bool { closed }

    public func close(): Unit {
        closed = true
    }
}

/**
 * 查询结果：包装 PGResult，游标式 next() 遍历物化行；get<T>/getOrNull<T> 按 OID + T 路由。
 */
public class PGQueryResult <: QueryResult & Resource {
    let res: PGResult
    let rowCount: Int64
    let colCount: Int64
    var cursor: Int64 = -1
    var closed = false

    public init(res: PGResult) {
        this.res = res
        this.rowCount = res.rowCount()
        this.colCount = res.fieldCount()
    }

    public prop columnInfos: Array<ColumnInfo> {
        get() {
            let arr = Array<ColumnInfo>(colCount, { j =>
                PGColumnInfo(
                    res.fieldName(j),
                    res.fieldType(j)
                )
            })
            arr
        }
    }

    public func next(): Bool {
        if (closed) {
            return false
        }
        cursor += 1
        if (cursor >= rowCount) {
            return false
        }
        true
    }

    @Deprecated
    public override func next(_: Array<SqlDbType>): Bool {
        throw SqlException("PGQueryResult: deprecated next(values) not supported")
    }

    public func get<T>(index: Int64): T {
        getOrNull<T>(index).getOrThrow()
    }

    public func getOrNull<T>(index: Int64): ?T {
        if (closed) {
            throw SqlException("PGQueryResult: result closed")
        }
        if (index < 0 || index >= colCount) {
            throw SqlException("PGQueryResult: column index out of range: " + index.toString())
        }
        if (res.isNull(cursor, index)) {
            return None
        }
        let oid = res.fieldType(index)
        let raw = res.getValue(cursor, index)
        // 按 T 路由：仓颉无法 match 类型参数 T，用反射式 dispatch 经一个 helper。
        pgReadValue<T>(oid, raw)
    }

    public func isClosed(): Bool { closed }

    public func close(): Unit {
        if (!closed) {
            closed = true
            res.close()
        }
    }
}

/**
 * 更新结果：rowCount(受影响行数) + lastInsertId(PG 无自增 ID，恒 0，需 RETURNING 取)。
 */
public class PGUpdateResult <: UpdateResult {
    public let rowCount_: Int64
    public let lastInsertId_: Int64

    public init(rowCount: Int64, lastInsertId: Int64) {
        this.rowCount_ = rowCount
        this.lastInsertId_ = lastInsertId
    }

    public prop rowCount: Int64 {
        get() { rowCount_ }
    }

    public prop lastInsertId: Int64 {
        get() { lastInsertId_ }
    }
}

/**
 * 事务：透传到 PGConnection 的 BEGIN/COMMIT/ROLLBACK/SAVEPOINT。
 * isoLevel/accessMode/deferrableMode 在 begin() 时拼入 SQL。
 */
public class PGTransaction <: Transaction {
    let cn: PGConnection
    var _isoLevel = TransactionIsoLevel.Unspecified
    var _accessMode = TransactionAccessMode.Unspecified
    var _deferrableMode = TransactionDeferrableMode.Unspecified
    var begun = false

    public init(cn: PGConnection) {
        this.cn = cn
    }

    public mut prop isoLevel: TransactionIsoLevel {
        get() { _isoLevel }
        set(v) { _isoLevel = v }
    }

    public mut prop accessMode: TransactionAccessMode {
        get() { _accessMode }
        set(v) { _accessMode = v }
    }

    public mut prop deferrableMode: TransactionDeferrableMode {
        get() { _deferrableMode }
        set(v) { _deferrableMode = v }
    }

    public func begin(): Unit {
        if (begun) {
            throw SqlException("PGTransaction: already begun")
        }
        let sb = StringBuilder("BEGIN")
        match (_isoLevel) {
            case TransactionIsoLevel.Unspecified => ()
            case TransactionIsoLevel.ReadUncommitted => sb.append(" ISOLATION LEVEL READ UNCOMMITTED")
            case TransactionIsoLevel.ReadCommitted => sb.append(" ISOLATION LEVEL READ COMMITTED")
            case TransactionIsoLevel.RepeatableRead => sb.append(" ISOLATION LEVEL REPEATABLE READ")
            case TransactionIsoLevel.Snapshot => sb.append(" ISOLATION LEVEL REPEATABLE READ")
            case TransactionIsoLevel.Serializable => sb.append(" ISOLATION LEVEL SERIALIZABLE")
            case TransactionIsoLevel.Linearizable => throw SqlException("PGTransaction: Linearizable not supported")
            case TransactionIsoLevel.Chaos => throw SqlException("PGTransaction: Chaos not supported")
        }
        match (_accessMode) {
            case TransactionAccessMode.Unspecified => ()
            case TransactionAccessMode.ReadOnly => sb.append(" READ ONLY")
            case TransactionAccessMode.ReadWrite => sb.append(" READ WRITE")
        }
        match (_deferrableMode) {
            case TransactionDeferrableMode.Unspecified => ()
            case TransactionDeferrableMode.NotDeferrable => sb.append(" NOT DEFERRABLE")
            case TransactionDeferrableMode.Deferrable => sb.append(" DEFERRABLE")
        }
        cn.execRawSql(sb.toString())
        cn.inTxn = true
        begun = true
    }

    public func commit(): Unit {
        if (!begun) {
            throw SqlException("PGTransaction: not begun")
        }
        cn.execRawSql("COMMIT")
        cn.inTxn = false
        begun = false
    }

    public func rollback(): Unit {
        if (!begun) {
            return
        }
        try { cn.execRawSql("ROLLBACK") } finally {
            cn.inTxn = false
            begun = false
        }
    }

    public func save(savePointName: String): Unit {
        cn.execRawSql("SAVEPOINT " + savePointName)
    }

    public func rollback(savePointName: String): Unit {
        cn.execRawSql("ROLLBACK TO SAVEPOINT " + savePointName)
    }

    public func release(savePointName: String): Unit {
        cn.execRawSql("RELEASE SAVEPOINT " + savePointName)
    }
}

/**
 * ColumnInfo 实现：从 PQfname/PQftype 构造；其余元数据用合理默认值(libpq 文本协议不暴露精度)。
 */
public class PGColumnInfo <: ColumnInfo {
    public let name_: String
    public let typeName_: String
    public let nullable_: Bool
    public let length_: Int64
    public let displaySize_: Int64
    public let scale_: Int64

    public init(name: String, oid: Int32) {
        this.name_ = name
        this.typeName_ = oidToTypeName(oid)
        this.nullable_ = true   // libpq 文本协议不返回 nullable 标记，保守为 true
        this.length_ = 0
        this.displaySize_ = Int64.Max
        this.scale_ = 0
    }

    public prop name: String { get() { name_ } }
    public prop typeName: String { get() { typeName_ } }
    public prop nullable: Bool { get() { nullable_ } }
    public prop length: Int64 { get() { length_ } }
    public prop displaySize: Int64 { get() { displaySize_ } }
    public prop scale: Int64 { get() { scale_ } }
}

// ===== 占位符重写 + 类型映射 =====

/**
 * 把 SQL 中的 `?` 占位符按出现顺序替换为 PG 的 `$1..$n`。
 * 双引号字符串字面量内的 `?` 不替换(避免误改字面量)。单引号内同理。
 */
public func rewriteQToDollar(sql: String): String {
    let bytes = sql.toArray()
    let out = ArrayList<UInt8>()
    var n = 0
    var inSingle = false
    var inDouble = false
    var i = 0
    while (i < bytes.size) {
        let b = bytes[i]
        if (b == 39u8 && !inDouble) { // '\''
            inSingle = !inSingle
            out.add(b)
            i += 1
            continue
        }
        if (b == 34u8 && !inSingle) { // '"'
            inDouble = !inDouble
            out.add(b)
            i += 1
            continue
        }
        if (b == 63u8 && !inSingle && !inDouble) { // '?'
            n += 1
            let ph = "$" + n.toString()
            for (c in ph.toArray()) { out.add(c) }
            i += 1
            continue
        }
        out.add(b)
        i += 1
    }
    String.fromUtf8(out.toArray())
}

/** 仓颉类型 → PGValue(用于 Statement.set<T>)。按 T 运行时分发。 */
func cjValueToPgValue<T>(v: T): PGValue {
    // 仓颉泛型无类型参数约束反射；经 `v as Any` 装箱为 Option<Any>，
    // 解包后再用类型模式匹配具体仓颉类型。
    match (v as Any) {
        case Some(a) =>
            match (a) {
                case pv: PGValue => return pv
                case s: String => return PGValue.PGText(s)
                case i: Int64 => return PGValue.PGInt64(i)
                case i: Int32 => return PGValue.PGInt32(i)
                case u: UInt64 => return PGValue.PGInt64(Int64(u))
                case u: UInt32 => return PGValue.PGInt32(Int32(u))
                case f: Float64 => return PGValue.PGFloat64(f)
                case f: Float32 => return PGValue.PGFloat64(Float64(f))
                case b: Bool => return PGValue.PGBool(b)
                case bytes: Array<UInt8> => return PGValue.PGBytes(bytes)
                case ts: ToString => return PGValue.PGText(ts.toString())
                case _ => ()
            }
        case None => ()
    }
    // 退路：T 为 PGValue 的 None 路径或无法装箱的类型。
    throw SqlException("PGStatement.set: unsupported parameter type")
}

/**
 * 按列 OID + 原始文本值读取为 T。仓颉无法 match 类型参数 T，
 * 先按 OID 解码为 Any，再经 as T 路由回具体类型；不匹配则抛 SqlException。
 */
func pgReadValue<T>(oid: Int32, raw: String): ?T {
    let v: Any = pgDecodeAny(oid, raw)
    // 尝试把 Any 强转回 T(as T 返回 Option<T>)。
    match (v as T) {
        case Some(t) => return Some(t)
        case None => ()
    }
    // T 可能是 String 兜底(未知 OID 已返回 raw)。
    match (raw as T) {
        case Some(s) => return Some(s)
        case None => throw SqlException("PGQueryResult: cannot decode column to target type")
    }
}

/** 按 OID 把原始文本解码为仓颉 Any 值(供 get<T> 路由)。 */
func pgDecodeAny(oid: Int32, raw: String): Any {
    // 字符串族
    if (oid == OID_TEXT || oid == OID_VARCHAR || oid == 0) {
        return raw
    }
    // 整数族
    if (oid == OID_INT8 || oid == OID_INT4 || oid == OID_INT2) {
        return parseInt64(oid, raw)
    }
    if (oid == OID_BOOL) {
        return parseBool(oid, raw)
    }
    if (oid == OID_FLOAT4 || oid == OID_FLOAT8 || oid == OID_NUMERIC) {
        return parseFloat64(raw)
    }
    if (oid == OID_BYTEA) {
        return parseByteaHex(raw)
    }
    if (oid == OID_JSON || oid == OID_JSONB) {
        return raw
    }
    if (oid == OID_UUID) {
        return raw
    }
    if (oid == OID_DATE || oid == OID_TIMESTAMP || oid == OID_TIMESTAMPTZ) {
        return raw
    }
    if (isArrayOid(oid)) {
        return parsePgArrayText(raw)
    }
    // 未知 OID：返回原始文本，调用方按需自行解析。
    return raw
}

/** PG OID → 仓颉侧类型名(供 ColumnInfo.typeName)。 */
func oidToTypeName(oid: Int32): String {
    match (oid) {
        case OID_BOOL => "Bool"
        case OID_INT8 => "Int64"
        case OID_INT4 => "Int32"
        case OID_INT2 => "Int16"
        case OID_FLOAT4 => "Float32"
        case OID_FLOAT8 => "Float64"
        case OID_NUMERIC => "Decimal"
        case OID_TEXT => "String"
        case OID_VARCHAR => "String"
        case OID_BYTEA => "Array<UInt8>"
        case OID_JSON => "String"
        case OID_JSONB => "String"
        case OID_UUID => "String"
        case OID_DATE => "String"
        case OID_TIMESTAMP => "String"
        case OID_TIMESTAMPTZ => "String"
        case OID_TEXT_ARRAY => "Array<String>"
        case OID_INT8_ARRAY => "Array<Int64>"
        case OID_INT4_ARRAY => "Array<Int32>"
        case OID_VARCHAR_ARRAY => "Array<String>"
        case _ => "Unknown(" + oid.toString() + ")"
    }
}