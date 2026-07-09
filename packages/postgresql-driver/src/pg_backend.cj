package postgresql_driver

import std.collection.*
import std.convert.*
import std.time.*
import csorm.Value
import csorm.DbBackend
import csorm.Dialect
import csorm.DriverConn
import csorm.DbError
import csorm.PlaceholderStyle
import csorm.SqlColType
import csorm.CsormError
import csorm.sqlColTypeToPg
import csorm.timestampUsToPgText
import csorm.timestampTzUsToPgText
import csorm.dateDaysToPgText
import csorm.timeUsToPgText
import csorm.Row as CsormRow

/** csorm.Value → PGValue(驱动绑定边界)。 */
public func valueToPG(v: Value): PGValue {
    match (v) {
        case VInt(x) => PGValue.PGInt64(x)
        case VFloat(x) => PGValue.PGFloat64(x)
        case VText(s) => PGValue.PGText(s)
        case VBool(b) => PGValue.PGBool(b)
        case VBytes(b) => PGValue.PGBytes(b)
        case VJson(s) => PGValue.PGJson(s)
        case VArr(elems) => PGValue.PGArray(Array<PGValue>(elems.size, { i => valueToPG(elems[i]) }))
        case VTimestamp(us) => PGValue.PGText(timestampUsToPgText(us))
        case VTimestampTz(us) => PGValue.PGText(timestampTzUsToPgText(us))
        case VDate(days) => PGValue.PGText(dateDaysToPgText(days))
        case VTime(us) => PGValue.PGText(timeUsToPgText(us))
        case VUuid(s) => PGValue.PGText(s)
        case VDecimal(s) => PGValue.PGText(s)
        case VEnum(_, raw) => PGValue.PGText(raw)
        case VNull => PGValue.PGNull
    }
}

/** PGValue → csorm.Value(读侧回包)。 */
public func pgValueToValue(v: PGValue): Value {
    match (v) {
        case PGInt64(x) => Value.VInt(x)
        case PGInt32(x) => Value.VInt(Int64(x))
        case PGFloat64(x) => Value.VFloat(x)
        case PGBool(b) => Value.VBool(b)
        case PGText(s) => Value.VText(s)
        case PGBytes(b) => Value.VBytes(b)
        case PGJson(s) => Value.VJson(s)
        case PGArray(elems) =>
            Value.VArr(Array<Value>(elems.size, { i => pgValueToValue(elems[i]) }))
        case PGNull => Value.VNull
    }
}

// ===== PgDialect：实现 csorm.Dialect =====

/**
 * PG 方言实现：$n 占位符、双引号标识符、PG DDL 类型文本。
 */
public class PgDialect <: Dialect {
    public init() {}

    public func backend(): DbBackend { DbBackend.Postgres }
    public func placeholderStyle(): PlaceholderStyle { PlaceholderStyle.DollarNumber }

    public func quoteIdent(s: String): String { doQuoteIdent(s) }
    public func quoteTable(schema: ?String, table: String): String { doQuoteTable(schema, table) }

    public func renderColType(t: SqlColType): String { sqlColTypeToPg(t) }

    public func renderCreateEnumType(typeName: String, values: Array<String>): String {
        let parts = ArrayList<String>()
        for (v in values) {
            parts.add("'" + v.replace("'", "''") + "'")
        }
        "CREATE TYPE " + doQuoteIdent(typeName) + " AS ENUM (" + joinComma(parts.toArray()) + ")"
    }

    public func renderDropEnumType(typeName: String): String {
        "DROP TYPE IF EXISTS " + doQuoteIdent(typeName)
    }

    public func renderOnConflictDoNothing(target: Array<String>): String {
        let q = Array<String>(target.size, { i => doQuoteIdent(target[i]) })
        " ON CONFLICT (" + joinComma(q) + ") DO NOTHING"
    }

    public func renderOnConflictDoUpdate(target: Array<String>, setExprs: Array<(String, String)>): String {
        let q = Array<String>(target.size, { i => doQuoteIdent(target[i]) })
        var s = " ON CONFLICT (" + joinComma(q) + ") DO UPDATE SET "
        let setParts = ArrayList<String>()
        for ((col, expr) in setExprs) {
            setParts.add(doQuoteIdent(col) + " = " + expr)
        }
        s + joinComma(setParts.toArray())
    }

    public func supportReturning(): Bool { true }
}

// 内部引号工具(与 csorm 的 doQuoteIdent/doQuoteTable 逻辑一致，避免循环依赖)
func doQuoteIdent(s: String): String {
    let bytes = s.toArray()
    let out = ArrayList<UInt8>()
    out.add(34u8) // '"'
    for (b in bytes) {
        if (b == 34u8) {
            out.add(34u8) // 双引号转义
        }
        out.add(b)
    }
    out.add(34u8) // '"'
    String.fromUtf8(out.toArray())
}

func doQuoteTable(schema: ?String, table: String): String {
    match (schema) {
        case Some(s) => doQuoteIdent(s) + "." + doQuoteIdent(table)
        case None => doQuoteIdent(table)
    }
}

func joinComma(parts: Array<String>): String {
    let sb = StringBuilder()
    var first = true
    for (p in parts) {
        if (!first) { sb.append(", ") }
        sb.append(p)
        first = false
    }
    sb.toString()
}

// ===== PgErrorImpl：实现 csorm.DbError =====

/**
 * PG 错误适配：包装 PGError 实现 csorm.DbError 接口。
 */
public class PgErrorImpl <: DbError {
    public let raw: PGError

    public init(raw: PGError) {
        this.raw = raw
    }

    public func message(): String { raw.message }
    public func sqlstate(): String { raw.sqlstate }
    public func severity(): String { raw.severity }
    public func detail(): String { raw.detail }
    public func hint(): String { raw.hint }
    public func schemaName(): String { raw.schemaName }
    public func tableName(): String { raw.tableName }
    public func columnName(): String { raw.columnName }
    public func constraintName(): String { raw.constraintName }
    public func isUniqueViolation(): Bool { raw.isUniqueViolation() }
    public func isForeignKeyViolation(): Bool { raw.isForeignKeyViolation() }
    public func isNotNullViolation(): Bool { raw.isNotNullViolation() }
    public func isCheckViolation(): Bool { raw.isCheckViolation() }
    public func isDeadlockOrSerializationFailure(): Bool { raw.isDeadlockOrSerializationFailure() }
    public func isConnectionError(): Bool { raw.isConnectionError() }
}

// ===== PgRow：包装 PG Row 实现 csorm.Row =====

/**
 * PG Row 适配：包装 postgresql_driver.Row 实现 csorm.Row(CsormRow) 接口。
 */
public class PgRow <: CsormRow {
    public let raw: PgRowData   // postgresql_driver.Row

    public init(raw: PgRowData) {
        this.raw = raw
    }

    public func columnCount(): Int64 { raw.columnCount() }
    public func columnName(i: Int64): String { raw.columnName(i) }
    public func columnOid(i: Int64): Int32 { raw.columnOid(i) }
    public func isNull(col: Int64): Bool { raw.isNull(col) }
    public func isNull(col: String): Bool { raw.isNull(col) }
    public func rawValue(col: Int64): String { raw.rawValue(col) }
    public func rawValue(col: String): String { raw.rawValue(col) }

    public func getText(col: Int64): String { raw.getText(col) }
    public func getText(col: String): String { raw.getText(col) }
    public func getOrNullText(col: Int64): ?String { raw.getOrNullText(col) }
    public func getOrNullText(col: String): ?String { raw.getOrNullText(col) }

    public func getInt64(col: Int64): Int64 { raw.getInt64(col) }
    public func getInt64(col: String): Int64 { raw.getInt64(col) }
    public func getOrNullInt64(col: Int64): ?Int64 { raw.getOrNullInt64(col) }
    public func getOrNullInt64(col: String): ?Int64 { raw.getOrNullInt64(col) }

    public func getInt32(col: Int64): Int32 { raw.getInt32(col) }
    public func getInt32(col: String): Int32 { raw.getInt32(col) }
    public func getOrNullInt32(col: Int64): ?Int32 { raw.getOrNullInt32(col) }
    public func getOrNullInt32(col: String): ?Int32 { raw.getOrNullInt32(raw.idx(col)) }

    public func getBool(col: Int64): Bool { raw.getBool(col) }
    public func getBool(col: String): Bool { raw.getBool(col) }
    public func getOrNullBool(col: Int64): ?Bool { raw.getOrNullBool(col) }
    public func getOrNullBool(col: String): ?Bool { raw.getOrNullBool(col) }

    public func getFloat64(col: Int64): Float64 { raw.getFloat64(col) }
    public func getFloat64(col: String): Float64 { raw.getFloat64(col) }
    public func getOrNullFloat64(col: Int64): ?Float64 { raw.getOrNullFloat64(col) }
    public func getOrNullFloat64(col: String): ?Float64 { raw.getOrNullFloat64(col) }

    public func getBytes(col: Int64): Array<UInt8> { raw.getBytes(col) }
    public func getBytes(col: String): Array<UInt8> { raw.getBytes(col) }
    public func getOrNullBytes(col: Int64): ?Array<UInt8> { raw.getOrNullBytes(col) }
    public func getOrNullBytes(col: String): ?Array<UInt8> { raw.getOrNullBytes(col) }

    public func getJson(col: Int64): String { raw.getJson(col) }
    public func getJson(col: String): String { raw.getJson(col) }
    public func getOrNullJson(col: Int64): ?String { raw.getOrNullJson(col) }
    public func getOrNullJson(col: String): ?String { raw.getOrNullJson(col) }

    public func getTextArray(col: Int64): Array<String> { raw.getTextArray(col) }
    public func getTextArray(col: String): Array<String> { raw.getTextArray(col) }
    public func getInt64Array(col: Int64): Array<Int64> { raw.getInt64Array(col) }
    public func getInt64Array(col: String): Array<Int64> { raw.getInt64Array(col) }
    public func getInt32Array(col: Int64): Array<Int32> { raw.getInt32Array(col) }
    public func getInt32Array(col: String): Array<Int32> { raw.getInt32Array(col) }
}

// ===== PgConn：实现 csorm.DriverConn =====

/**
 * PG 连接适配：包装 PGDatabase 实现 csorm.DriverConn 接口。
 * 内部完成 Value→PGValue 转换与 PGError→CsormError 包装。
 */
public class PgConn <: DriverConn {
    public let pg: PGDatabase
    let dialectImpl: PgDialect

    public init(connString: String) {
        pg = PGDatabase(connString)
        dialectImpl = PgDialect()
    }

    /** 适配器：包装已存在的 PGDatabase。 */
    public init(pg: PGDatabase) {
        this.pg = pg
        dialectImpl = PgDialect()
    }

    public func backend(): DbBackend { DbBackend.Postgres }
    public func dialect(): Dialect { dialectImpl }

    // ===== 内部工具 =====

    func toPgParams(vals: Array<Value>): Array<PGValue> {
        Array<PGValue>(vals.size, { i => valueToPG(vals[i]) })
    }

    func wrapRun<T>(ctx: String, body: () -> T): T {
        try {
            body()
        } catch (e: PGError) {
            throw CsormError(ctx + ": " + e.message, PgErrorImpl(e))
        }
    }

    // ===== 查询 =====

    public func queryAll(sql: String, params: Array<Value>): Array<CsormRow> {
        wrapRun("queryAll", { =>
            let pgRows = pg.query(sql, toPgParams(params))
            Array<CsormRow>(pgRows.size, { i => PgRow(pgRows[i]) })
        })
    }

    public func queryOne(sql: String, params: Array<Value>): ?CsormRow {
        wrapRun("queryOne", { =>
            match (pg.queryOne(sql, toPgParams(params))) {
                case Some(r) => Some(PgRow(r))
                case None => None
            }
        })
    }

    public func streamQuery(sql: String, params: Array<Value>, chunkSize: Int64, cb: (Array<CsormRow>) -> Unit): Unit {
        wrapRun("streamQuery", { =>
            pg.streamQuery(sql, toPgParams(params), chunkSize, { pgRows =>
                cb(Array<CsormRow>(pgRows.size, { i => PgRow(pgRows[i]) }))
            })
        })
    }

    public func exec(sql: String, params: Array<Value>): Int64 {
        wrapRun("exec", { => pg.exec(sql, toPgParams(params)) })
    }

    public func execSql(sql: String): Unit {
        wrapRun("execSql", { => pg.execSql(sql) })
    }

    // ===== 事务 =====

    public func begin(): Unit { wrapRun("begin", { => pg.begin() }) }
    public func commit(): Unit { wrapRun("commit", { => pg.commit() }) }
    public func rollback(): Unit { wrapRun("rollback", { => pg.rollback() }) }
    public func inTransaction(): Bool { pg.inTransaction() }

    public func transaction(body: () -> Unit): Unit {
        wrapRun("transaction", { => pg.transaction(body) })
    }

    public func save(name: String): Unit { wrapRun("savepoint", { => pg.save(name) }) }
    public func rollback(name: String): Unit { wrapRun("rollback savepoint", { => pg.rollback(name) }) }
    public func release(name: String): Unit { wrapRun("release savepoint", { => pg.release(name) }) }

    public func cancel(): Bool { pg.cancel() }
    public func close(): Unit { pg.close() }
    public func poolSize(): Int64 { pg.poolSize() }
}