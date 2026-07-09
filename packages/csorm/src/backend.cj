package csorm

import std.collection.*

/**
 * 后端抽象层(对标 SeaORM DatabaseBackend + ConnectionTrait + QueryBuilder)。
 *
 * 核心包定义接口，各 driver 包(如 postgresql-driver)实现。
 * csorm 核心不依赖任何具体 driver——driver 包依赖 csorm 获取接口并实现。
 *
 * 分层：
 * - DbBackend：方言标识 enum(决定占位符/引号/DDL 语法差异)
 * - PlaceholderStyle / Placeholder：占位符编号器(按方言产出 ?/$n/:n)
 * - Dialect：渲染能力接口(占位符/标识符引号/DDL 类型文本/upsert/returning)
 * - Row：后端无关行读取接口(各 driver 的 Row 类实现)
 * - DbError：后端无关错误诊断接口
 * - DriverConn：执行能力接口(查询/执行/事务/取消)，方法签名用 Value/Row 接口
 * - PgCompatDialect：PG 兼容默认方言(供 build() 无参版本与测试使用)
 * - MockRow / MockDatabase：测试用 mock(实现 DriverConn)
 */

// ===== DbBackend =====

/** SQL 方言标识(对标 SeaORM DatabaseBackend)。 */
public enum DbBackend {
    | Postgres
    | MySql
    | Sqlite
}

// ===== PlaceholderStyle =====

/** 占位符风格：? = MySQL/SQLite，$n = Postgres，:n = Oracle(预留)。 */
public enum PlaceholderStyle {
    | QuestionMark
    | DollarNumber
    | ColonNumber
}

// ===== Placeholder =====

/** 占位符编号自增器：按 PlaceholderStyle 产出 ?/$n/:n。 */
public class Placeholder {
    let style: PlaceholderStyle
    var n: Int64 = 0

    public init(style: PlaceholderStyle) { this.style = style }
    public init(style: PlaceholderStyle, start!: Int64) {
        this.style = style
        n = start
    }
    public func next(): String {
        n += 1
        match (style) {
            case QuestionMark => "?"
            case DollarNumber => "$" + n.toString()
            case ColonNumber => ":" + n.toString()
        }
    }
    public func current(): Int64 { n }
}

// ===== Dialect =====

/**
 * 渲染方言接口(对标 sea_query QueryBuilder + backend-specific rendering)。
 * 各 driver 包提供一个实现(PgDialect/MySqlDialect/SqliteDialect)。
 */
public interface Dialect {
    func backend(): DbBackend
    func placeholderStyle(): PlaceholderStyle
    func quoteIdent(s: String): String
    func quoteTable(schema: ?String, table: String): String
    func renderColType(t: SqlColType): String
    func renderCreateEnumType(typeName: String, values: Array<String>): String
    func renderDropEnumType(typeName: String): String
    func renderOnConflictDoNothing(target: Array<String>): String
    func renderOnConflictDoUpdate(target: Array<String>, setExprs: Array<(String, String)>): String
    func supportReturning(): Bool
}

// ===== Row =====

/**
 * 后端无关行读取接口(对标 SeaORM QueryResult)。
 * 方法名与 postgresql_driver.Row 一致，各 driver 的 Row 类实现此接口。
 * 宏生成体调用的 getInt64/getText/getJson/... 均在此接口声明。
 */
public interface Row {
    func columnCount(): Int64
    func columnName(i: Int64): String
    func columnOid(i: Int64): Int32
    func isNull(col: Int64): Bool
    func isNull(col: String): Bool
    func rawValue(col: Int64): String
    func rawValue(col: String): String

    func getText(col: Int64): String
    func getText(col: String): String
    func getOrNullText(col: Int64): ?String
    func getOrNullText(col: String): ?String

    func getInt64(col: Int64): Int64
    func getInt64(col: String): Int64
    func getOrNullInt64(col: Int64): ?Int64
    func getOrNullInt64(col: String): ?Int64

    func getInt32(col: Int64): Int32
    func getInt32(col: String): Int32
    func getOrNullInt32(col: Int64): ?Int32
    func getOrNullInt32(col: String): ?Int32

    func getBool(col: Int64): Bool
    func getBool(col: String): Bool
    func getOrNullBool(col: Int64): ?Bool
    func getOrNullBool(col: String): ?Bool

    func getFloat64(col: Int64): Float64
    func getFloat64(col: String): Float64
    func getOrNullFloat64(col: Int64): ?Float64
    func getOrNullFloat64(col: String): ?Float64

    func getBytes(col: Int64): Array<UInt8>
    func getBytes(col: String): Array<UInt8>
    func getOrNullBytes(col: Int64): ?Array<UInt8>
    func getOrNullBytes(col: String): ?Array<UInt8>

    func getJson(col: Int64): String
    func getJson(col: String): String
    func getOrNullJson(col: Int64): ?String
    func getOrNullJson(col: String): ?String

    func getTextArray(col: Int64): Array<String>
    func getTextArray(col: String): Array<String>
    func getInt64Array(col: Int64): Array<Int64>
    func getInt64Array(col: String): Array<Int64>
    func getInt32Array(col: Int64): Array<Int32>
    func getInt32Array(col: String): Array<Int32>
}

// ===== DbError =====

/**
 * 后端无关错误诊断接口(对标 SeaORM DbErr)。
 * 各 driver 包装原生错误并实现此接口；CsormError 持有 DbError 做判定。
 */
public interface DbError {
    func message(): String
    func sqlstate(): String
    func severity(): String
    func detail(): String
    func hint(): String
    func schemaName(): String
    func tableName(): String
    func columnName(): String
    func constraintName(): String
    func isUniqueViolation(): Bool
    func isForeignKeyViolation(): Bool
    func isNotNullViolation(): Bool
    func isCheckViolation(): Bool
    func isDeadlockOrSerializationFailure(): Bool
    func isConnectionError(): Bool
}

// ===== DriverConn =====

/**
 * 执行能力接口(对标 SeaORM ConnectionTrait)。
 * 方法签名全部用 Value 和 Row 接口，不出现任何 driver 专属类型。
 * 各 driver 实现此类，内部做 Value→原生参数 / 原生错误→CsormError 的转换。
 */
public interface DriverConn {
    func backend(): DbBackend
    func dialect(): Dialect

    func queryAll(sql: String, params: Array<Value>): Array<Row>
    func queryOne(sql: String, params: Array<Value>): ?Row
    func streamQuery(sql: String, params: Array<Value>, chunkSize: Int64, cb: (Array<Row>) -> Unit): Unit

    func exec(sql: String, params: Array<Value>): Int64
    func execSql(sql: String): Unit

    func begin(): Unit
    func commit(): Unit
    func rollback(): Unit
    func inTransaction(): Bool
    func transaction(body: () -> Unit): Unit
    func save(name: String): Unit
    func rollback(name: String): Unit
    func release(name: String): Unit

    func cancel(): Bool
    func close(): Unit
    func poolSize(): Int64
}

// ===== PgCompatDialect =====

/**
 * PG 兼容默认方言：$n 占位符、双引号标识符、PG DDL 类型文本。
 * 供 build() 无参版本与 Schema 默认使用；driver 包的 PgDialect 可继承或独立实现。
 */
public class PgCompatDialect <: Dialect {
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

/** 默认 PG 兼容方言实例(供 build() 无参版本使用)。 */
public let defaultDialect: Dialect = PgCompatDialect()