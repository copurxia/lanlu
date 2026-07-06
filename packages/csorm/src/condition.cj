package csorm

import std.collection.*
import std.convert.*

/**
 * WHERE 条件树(对标 sea_query::Condition)。渲染为 PG SQL + 参数。
 * - Cmp: column OP value(=, <>, >, >=, <, <=)
 * - IsNull/IsNotNull
 * - InVals/NotInVals: column IN (v1, v2, ...)
 * - Like: column LIKE pattern
 * - Between: column BETWEEN a AND b
 * - RawCond: 原始 SQL 片段 + 参数(复杂场景兜底)
 */
public enum Cond {
    | And(Array<Cond>)
    | Or(Array<Cond>)
    | Cmp(String, String, Value)         // column, op, value
    | IsNull(String)
    | IsNotNull(String)
    | InVals(String, Array<Value>)
    | NotInVals(String, Array<Value>)
    | Like(String, String)               // column, pattern
    | NotLike(String, String)
    | Between(String, Value, Value)
    | RawCond(String, Array<Value>)      // 原始 SQL 片段，占位符用 ? (渲染时重排为 $n)
    | Exists(String, Array<Value>)       // EXISTS (subquery)，subquery 占位符用 ?
    | NotExists(String, Array<Value>)    // NOT EXISTS (subquery)
}

/** AND 多个条件。 */
public func all(conds: Array<Cond>): Cond { Cond.And(conds) }

/** OR 多个条件。 */
public func any(conds: Array<Cond>): Cond { Cond.Or(conds) }

/**
 * 列引用：提供类型化的比较操作符，生成 Cond。
 * 用法：col("name").eq("alice")、col("age").gt(18)、col("id").isIn([1,2,3])
 */
public class Column {
    public let name: String
    public init(name: String) { this.name = name }

    public func eq<T>(v: T): Cond where T <: IntoValue { Cond.Cmp(name, "=", v.intoValue()) }
    public func ne<T>(v: T): Cond where T <: IntoValue { Cond.Cmp(name, "<>", v.intoValue()) }
    public func gt<T>(v: T): Cond where T <: IntoValue { Cond.Cmp(name, ">", v.intoValue()) }
    public func gte<T>(v: T): Cond where T <: IntoValue { Cond.Cmp(name, ">=", v.intoValue()) }
    public func lt<T>(v: T): Cond where T <: IntoValue { Cond.Cmp(name, "<", v.intoValue()) }
    public func lte<T>(v: T): Cond where T <: IntoValue { Cond.Cmp(name, "<=", v.intoValue()) }

    public func isNull(): Cond { Cond.IsNull(name) }
    public func isNotNull(): Cond { Cond.IsNotNull(name) }

    public func isIn<T>(vals: Array<T>): Cond where T <: IntoValue {
        Cond.InVals(name, Array<Value>(vals.size, { i => vals[i].intoValue() }))
    }

    public func notIn<T>(vals: Array<T>): Cond where T <: IntoValue {
        Cond.NotInVals(name, Array<Value>(vals.size, { i => vals[i].intoValue() }))
    }

    public func like(pattern: String): Cond { Cond.Like(name, pattern) }
    public func notLike(pattern: String): Cond { Cond.NotLike(name, pattern) }

    public func between<T>(a: T, b: T): Cond where T <: IntoValue {
        Cond.Between(name, a.intoValue(), b.intoValue())
    }
}

/** 构造列引用。 */
public func col(name: String): Column { Column(name) }

/** 原始条件片段。占位符用 ? (渲染时自动重排为 $n)。 */
public func rawCond(sql: String, params: Array<Value>): Cond { Cond.RawCond(sql, params) }

/** EXISTS (subquery)，subquery 占位符用 ?。 */
public func exists(subSql: String, params: Array<Value>): Cond { Cond.Exists(subSql, params) }

/** NOT EXISTS (subquery)，subquery 占位符用 ?。 */
public func notExists(subSql: String, params: Array<Value>): Cond { Cond.NotExists(subSql, params) }

// ===== 条件渲染 =====

/**
 * 渲染条件树为 PG SQL 片段，参数压入 params 列表，占位符由 ph 编号。
 * 返回的字符串可直接拼入 WHERE 子句(外层不加括号；And/Or 自带括号)。
 */
public func renderCond(cond: Cond, params: ArrayList<Value>, ph: Placeholder): String {
    match (cond) {
        case And(conds) =>
            if (conds.size == 0) { return "1=1" }
            let parts = ArrayList<String>()
            for (c in conds) { parts.add(renderCond(c, params, ph)) }
            "(" + joinAnd(parts.toArray()) + ")"
        case Or(conds) =>
            if (conds.size == 0) { return "1=1" }
            let parts = ArrayList<String>()
            for (c in conds) { parts.add(renderCond(c, params, ph)) }
            "(" + joinOr(parts.toArray()) + ")"
        case Cmp(col, op, v) =>
            if (match (v) { case VNull => true; case _ => false }) {
                // NULL 比较：= NULL → IS NULL，<> NULL → IS NOT NULL
                if (op == "<>") {
                    quoteIdent(col) + " IS NOT NULL"
                } else {
                    quoteIdent(col) + " IS NULL"
                }
            } else {
                params.add(v)
                quoteIdent(col) + " " + op + " " + ph.next()
            }
        case IsNull(col) => quoteIdent(col) + " IS NULL"
        case IsNotNull(col) => quoteIdent(col) + " IS NOT NULL"
        case InVals(col, vals) =>
            if (vals.size == 0) { return "1=0" } // IN () 非法，回落恒假
            let phs = ArrayList<String>()
            for (v in vals) {
                params.add(v)
                phs.add(ph.next())
            }
            quoteIdent(col) + " IN (" + joinComma(phs.toArray()) + ")"
        case NotInVals(col, vals) =>
            if (vals.size == 0) { return "1=1" }
            let phs = ArrayList<String>()
            for (v in vals) {
                params.add(v)
                phs.add(ph.next())
            }
            quoteIdent(col) + " NOT IN (" + joinComma(phs.toArray()) + ")"
        case Like(col, pattern) =>
            params.add(Value.VText(pattern))
            quoteIdent(col) + " LIKE " + ph.next()
        case NotLike(col, pattern) =>
            params.add(Value.VText(pattern))
            quoteIdent(col) + " NOT LIKE " + ph.next()
        case Between(col, a, b) =>
            params.add(a)
            params.add(b)
            quoteIdent(col) + " BETWEEN " + ph.next() + " AND " + ph.next()
        case RawCond(sql, rawParams) =>
            // 原始片段中的 ? 占位符按出现顺序替换为 $n(续编号)，参数压入 params
            for (p in rawParams) { params.add(p) }
            rewriteQPlaceholders(sql, ph)
        case Exists(subSql, subParams) =>
            for (p in subParams) { params.add(p) }
            "EXISTS (" + rewriteQPlaceholders(subSql, ph) + ")"
        case NotExists(subSql, subParams) =>
            for (p in subParams) { params.add(p) }
            "NOT EXISTS (" + rewriteQPlaceholders(subSql, ph) + ")"
    }
}

/** 把 SQL 片段中的 ? 占位符按出现顺序替换为 $n(由 ph 续编号)。双引号内的 ? 不替换。 */
public func rewriteQPlaceholders(sql: String, ph: Placeholder): String {
    let bytes = sql.toArray()
    let out = ArrayList<UInt8>()
    var inQ = false
    var i = 0
    while (i < bytes.size) {
        let b = bytes[i]
        if (b == 34u8) { // '"'
            inQ = !inQ
            out.add(b)
            i += 1
            continue
        }
        if (b == 63u8 && !inQ) { // '?'
            let phStr = ph.next().toArray()
            for (c in phStr) { out.add(c) }
            i += 1
            continue
        }
        out.add(b)
        i += 1
    }
    String.fromUtf8(out.toArray())
}

func joinAnd(parts: Array<String>): String {
    let sb = StringBuilder()
    var first = true
    for (p in parts) {
        if (!first) { sb.append(" AND ") }
        sb.append(p)
        first = false
    }
    sb.toString()
}

func joinOr(parts: Array<String>): String {
    let sb = StringBuilder()
    var first = true
    for (p in parts) {
        if (!first) { sb.append(" OR ") }
        sb.append(p)
        first = false
    }
    sb.toString()
}
