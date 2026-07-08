package csorm

/**
 * 类型化表达式 Expr(对标 sea_query::Expr/ExprTrait)。
 *
 * 替代裸 SQL 拼装(addRawColumn/rawCond)：列引用 + 字面量 + 算子 + 函数，
 * 构成表达式树，build() 时渲染为 PG SQL 片段 + 参数(占位符续编号)。
 *
 * 用法：
 *   let e = expr("age").add(exprLit(1)).gt(exprLit(18))   // (age + 1) > 18
 *   q.whereExpr(e)
 *   q.selectExpr(expr("name").upper(), alias: "NAME")     // UPPER("name") AS "NAME"
 *   q.orderByExpr(expr("created_at"), Order.Desc)
 *
 * Expr 内部持有 sql 片段(已含列名引号)+ params 列表，build 时按出现顺序压入。
 * 复杂子表达式经 Expr 组合，避免人手对齐 $n 编号。
 */
import std.collection.*
import std.convert.*

/**
 * 表达式：持有 SQL 片段文本 + 参数列表。
 * 列名在构造时经 quoteIdent 加引号；字面量经占位符绑定。
 * 算子/函数返回新 Expr(不可变语义，链式调用不修改原 Expr)。
 */
public class Expr {
    public let sql: String
    public let params: ArrayList<Value>

    public init(sql: String) {
        this.sql = sql
        this.params = ArrayList<Value>()
    }

    public init(sql: String, params: Array<Value>) {
        this.sql = sql
        this.params = ArrayList<Value>()
        for (p in params) { this.params.add(p) }
    }

    public init(sql: String, params: ArrayList<Value>) {
        this.sql = sql
        this.params = params
    }

    // ===== 比较算子(返回新 Expr，片段为 "left OP $n") =====

    /** = 等于。NULL 值自动转 IS NULL。 */
    public func eq(v: Value): Expr { cmpNullAware("=", v) }
    /** <> 不等于。NULL 值自动转 IS NOT NULL。 */
    public func ne(v: Value): Expr { cmpNullAware("<>", v) }
    public func gt(v: Value): Expr { cmp(">", v) }
    public func gte(v: Value): Expr { cmp(">=", v) }
    public func lt(v: Value): Expr { cmp("<", v) }
    public func lte(v: Value): Expr { cmp("<=", v) }

    /** = 另一个 Expr(表达式间比较)。 */
    public func eqExpr(other: Expr): Expr { binCmp("=", other) }
    public func neExpr(other: Expr): Expr { binCmp("<>", other) }
    public func gtExpr(other: Expr): Expr { binCmp(">", other) }
    public func gteExpr(other: Expr): Expr { binCmp(">=", other) }
    public func ltExpr(other: Expr): Expr { binCmp("<", other) }
    public func lteExpr(other: Expr): Expr { binCmp("<=", other) }

    /** IS NULL / IS NOT NULL。 */
    public func isNull(): Expr { Expr(sql + " IS NULL", params) }
    public func isNotNull(): Expr { Expr(sql + " IS NOT NULL", params) }

    /** LIKE / NOT LIKE(pattern 绑定)。 */
    public func like(pattern: String): Expr {
        let p = ArrayList<Value>()
        for (v in params) { p.add(v) }
        p.add(Value.VText(pattern))
        Expr(sql + " LIKE $" + (p.size).toString(), p)
    }
    public func notLike(pattern: String): Expr {
        let p = ArrayList<Value>()
        for (v in params) { p.add(v) }
        p.add(Value.VText(pattern))
        Expr(sql + " NOT LIKE $" + (p.size).toString(), p)
    }

    /** BETWEEN a AND b。 */
    public func between(a: Value, b: Value): Expr {
        let p = ArrayList<Value>()
        for (v in params) { p.add(v) }
        let n1 = p.size + 1
        p.add(a)
        let n2 = p.size + 1
        p.add(b)
        Expr(sql + " BETWEEN $" + n1.toString() + " AND $" + n2.toString(), p)
    }

    /** IN (v1, v2, ...)。空数组返回 FALSE(恒假)。 */
    public func isIn(vals: Array<Value>): Expr {
        if (vals.size == 0) {
            return Expr("FALSE", params)
        }
        let p = ArrayList<Value>()
        for (v in params) { p.add(v) }
        let phs = ArrayList<String>()
        for (v in vals) {
            p.add(v)
            phs.add("$" + (p.size).toString())
        }
        Expr(sql + " IN (" + joinComma(phs.toArray()) + ")", p)
    }

    /** NOT IN (v1, v2, ...)。空数组返回 TRUE(恒真)。 */
    public func notIn(vals: Array<Value>): Expr {
        if (vals.size == 0) {
            return Expr("TRUE", params)
        }
        let p = ArrayList<Value>()
        for (v in params) { p.add(v) }
        let phs = ArrayList<String>()
        for (v in vals) {
            p.add(v)
            phs.add("$" + (p.size).toString())
        }
        Expr(sql + " NOT IN (" + joinComma(phs.toArray()) + ")", p)
    }

    // ===== 算术算子 =====

    public func add(other: Expr): Expr { arith("+", other) }
    public func sub(other: Expr): Expr { arith("-", other) }
    public func mul(other: Expr): Expr { arith("*", other) }
    public func div(other: Expr): Expr { arith("/", other) }

    public func addVal(v: Value): Expr { arithVal("+", v) }
    public func subVal(v: Value): Expr { arithVal("-", v) }
    public func mulVal(v: Value): Expr { arithVal("*", v) }
    public func divVal(v: Value): Expr { arithVal("/", v) }

    // ===== 函数(返回新 Expr) =====

    public func upper(): Expr { func0("UPPER") }
    public func lower(): Expr { func0("LOWER") }
    public func length(): Expr { func0("LENGTH") }
    public func abs(): Expr { func0("ABS") }
    public func not(): Expr { func0("NOT") }

    // ===== 内部工具 =====

    /** 比较算子(NULL 感知：= NULL → IS NULL，<> NULL → IS NOT NULL)。 */
    func cmpNullAware(op: String, v: Value): Expr {
        match (v) {
            case Value.VNull =>
                if (op == "<>") {
                    Expr(sql + " IS NOT NULL", params)
                } else {
                    Expr(sql + " IS NULL", params)
                }
            case _ => cmp(op, v)
        }
    }

    func cmp(op: String, v: Value): Expr {
        let p = ArrayList<Value>()
        for (x in params) { p.add(x) }
        p.add(v)
        Expr(sql + " " + op + " $" + (p.size).toString(), p)
    }

    func binCmp(op: String, other: Expr): Expr {
        let p = ArrayList<Value>()
        for (x in params) { p.add(x) }
        for (x in other.params) { p.add(x) }
        Expr(sql + " " + op + " " + other.sql, p)
    }

    func arith(op: String, other: Expr): Expr {
        let p = ArrayList<Value>()
        for (x in params) { p.add(x) }
        for (x in other.params) { p.add(x) }
        Expr("(" + sql + " " + op + " " + other.sql + ")", p)
    }

    func arithVal(op: String, v: Value): Expr {
        let p = ArrayList<Value>()
        for (x in params) { p.add(x) }
        p.add(v)
        Expr("(" + sql + " " + op + " $" + (p.size).toString() + ")", p)
    }

    func func0(name: String): Expr {
        Expr(name + "(" + sql + ")", params)
    }

    /** 渲染为带别名的 SELECT 列：expr AS "alias"。alias 空时返回裸 expr。 */
    public func asAlias(alias: String): Expr {
        if (alias.isEmpty()) { this } else { Expr(sql + " AS " + quoteIdent(alias), params) }
    }
}

// ===== 构造函数 =====

/** 列引用(加引号防注入)。 */
public func expr(col: String): Expr { Expr(quoteIdent(col)) }

/** 字面量表达式(参数绑定)。 */
public func exprLit(v: Value): Expr {
    let p = ArrayList<Value>()
    p.add(v)
    Expr("$1", p)
}

/** 原始表达式(直接 SQL 片段 + 参数，占位符用 ? 续编号时由调用方管理)。
 *  注意：原始 SQL 不加引号，调用方需自行防注入。 */
public func exprRaw(sql: String): Expr {
    Expr(sql, ArrayList<Value>())
}
public func exprRaw(sql: String, params: Array<Value>): Expr {
    Expr(sql, params)
}

// ===== 函数表达式(顶层工厂) =====

/** COUNT(*) / COUNT(expr)。 */
public func exprCount(e!: ?Expr = None): Expr {
    match (e) {
        case Some(x) => Expr("COUNT(" + x.sql + ")", x.params)
        case None => Expr("COUNT(*)", ArrayList<Value>())
    }
}

/** SUM(expr)。 */
public func exprSum(e: Expr): Expr { Expr("SUM(" + e.sql + ")", e.params) }
public func exprAvg(e: Expr): Expr { Expr("AVG(" + e.sql + ")", e.params) }
public func exprMin(e: Expr): Expr { Expr("MIN(" + e.sql + ")", e.params) }
public func exprMax(e: Expr): Expr { Expr("MAX(" + e.sql + ")", e.params) }

/** COALESCE(e1, e2, ...)。 */
public func exprCoalesce(es: Array<Expr>): Expr {
    let p = ArrayList<Value>()
    let parts = ArrayList<String>()
    for (e in es) {
        parts.add(e.sql)
        for (v in e.params) { p.add(v) }
    }
    Expr("COALESCE(" + joinComma(parts.toArray()) + ")", p)
}

/** NOW() / CURRENT_TIMESTAMP。 */
public func exprNow(): Expr { Expr("CURRENT_TIMESTAMP", ArrayList<Value>()) }

/** CAST(expr AS type)。 */
public func exprCast(e: Expr, pgType: String): Expr {
    Expr("CAST(" + e.sql + " AS " + pgType + ")", e.params)
}

/** EXTRACT(field FROM expr)，field 如 "EPOCH"、"YEAR"。 */
public func exprExtract(field: String, e: Expr): Expr {
    Expr("EXTRACT(" + field + " FROM " + e.sql + ")", e.params)
}

/** 表达式 AND/OR 组合(返回 Expr，可用于 WHERE)。 */
public func exprAnd(left: Expr, right: Expr): Expr {
    let p = ArrayList<Value>()
    for (v in left.params) { p.add(v) }
    for (v in right.params) { p.add(v) }
    Expr("(" + left.sql + " AND " + right.sql + ")", p)
}
public func exprOr(left: Expr, right: Expr): Expr {
    let p = ArrayList<Value>()
    for (v in left.params) { p.add(v) }
    for (v in right.params) { p.add(v) }
    Expr("(" + left.sql + " OR " + right.sql + ")", p)
}

// ===== Cond.ExprCmp：表达式间比较条件 =====
// 在 condition.cj 的 Cond 枚举新增 ExprCmp 变体后，renderCond 渲染它。

/**
 * 把 Expr 渲染为 WHERE 片段，参数压入 params，占位符由 ph 续编号。
 * Expr 内部占位符为 $1..$n(局部编号)，渲染时需重映射到 ph 的全局编号。
 */
public func renderExpr(e: Expr, params: ArrayList<Value>, ph: Placeholder): String {
    // Expr 的占位符是 $1..$k 局部编号；按 params 顺序压入并用 ph 重编号。
    let localParams = e.params
    // 用正则把 $n 替换为 ph.next()：简化为按 $ 后数字顺序替换。
    rewriteExprPlaceholders(e.sql, localParams, params, ph)
}

/** 把 Expr SQL 中的 $n 按出现顺序替换为 ph 的全局 $m，参数压入 params。 */
func rewriteExprPlaceholders(sql: String, localParams: ArrayList<Value>,
    params: ArrayList<Value>, ph: Placeholder): String {
    let bytes = sql.toArray()
    let out = ArrayList<UInt8>()
    var i = 0
    while (i < bytes.size) {
        let b = bytes[i]
        if (b == 36u8 && i + 1 < bytes.size) { // '$'
            // 读后面的数字
            var j = i + 1
            let numStart = j
            while (j < bytes.size && bytes[j] >= 48u8 && bytes[j] <= 57u8) {
                j += 1
            }
            if (j > numStart) {
                let numStr = String.fromUtf8(bytes[numStart..j])
                var localIdx: Int64 = 0
                try { localIdx = Int64.parse(numStr) } catch (_: Exception) { localIdx = 0 }
                // 压入对应参数(从 localParams 取第 localIdx-1 个)
                if (localIdx - 1 >= 0 && localIdx - 1 < localParams.size) {
                    params.add(localParams[localIdx - 1])
                    let phStr = ph.next().toArray()
                    for (c in phStr) { out.add(c) }
                }
                i = j
                continue
            }
        }
        out.add(b)
        i += 1
    }
    String.fromUtf8(out.toArray())
}