package csorm

import std.collection.*
import std.convert.*

/**
 * 查询构建器(对标 sea_query SelectStatement/InsertStatement/...)。
 * 四个 builder class，各持状态 + 参数列表，链式调用后 build() 输出 (SQL, Array<Value>)。
 * 占位符与引号风格由 Dialect 决定(默认 PG：$n + 双引号)。标识符加引号防注入。
 */

// ===== Order =====
public enum Order {
    | Asc
    | Desc
}
public func orderKeyword(o: Order): String {
    match (o) {
        case Asc => "ASC"
        case Desc => "DESC"
    }
}

// ===== CTE 定义 =====
/**
 * WITH 子句的单个 CTE（对标 sea_query WithClause/WithQuery）。
 * subQuery 为结构化 SelectQuery；build() 时先渲染 sub，占位符经 rewriteDollarSeq
 * 结构性续编到主查询编号链（禁止沿用 rawPrefixFragment 手写 $n 模式）。
 * columnList 非空时输出 name(col1,col2,...)（RECURSIVE 常用）。
 */
public struct CTEDef {
    public let name: String
    public let recursive: Bool
    public let subQuery: SelectQuery
    public let columnList: Array<String>

    public init(name: String, subQuery: SelectQuery, recursive!: Bool = false,
        columnList!: Array<String> = Array<String>()) {
        this.name = name
        this.subQuery = subQuery
        this.recursive = recursive
        this.columnList = columnList
    }
}

/**
 * LATERAL JOIN 定义：JOIN kind LATERAL (subQuery) AS alias [ON cond]。
 * on 为空 → CROSS JOIN LATERAL（无 ON 子句）。sub 占位符在 build 时结构性续编。
 */
public struct LateralJoin {
    public let kind: JoinKind
    public let subQuery: SelectQuery
    public let alias: String
    public let onSql: String   // 空 = CROSS JOIN LATERAL

    public init(kind: JoinKind, subQuery: SelectQuery, alias: String, onSql!: String = "") {
        this.kind = kind
        this.subQuery = subQuery
        this.alias = alias
        this.onSql = onSql
    }
}

/**
 * 把 SQL 中按出现顺序的 $1..$k 局部占位符重写为 $(offset+1)..$(offset+k)
 * （CTE/派生表从子查询续编主查询占位符链）。返回 (新SQL, 局部占位符个数)。
 */
public func rewriteDollarSeq(sql: String, offset: Int64): (String, Int64) {
    let bytes = sql.toArray()
    let out = ArrayList<UInt8>()
    var seq: Int64 = 0
    var i = 0
    while (i < bytes.size) {
        let b = bytes[i]
        if (b == 36u8 && i + 1 < bytes.size) { // '$'
            var j = i + 1
            let numStart = j
            while (j < bytes.size && bytes[j] >= 48u8 && bytes[j] <= 57u8) {
                j += 1
            }
            if (j > numStart) {
                seq += 1
                let newNum = "$" + (offset + seq).toString()
                for (c in newNum.toArray()) { out.add(c) }
                i = j
                continue
            }
        }
        out.add(b)
        i += 1
    }
    (String.fromUtf8(out.toArray()), seq)
}

// ===== JoinType =====
public enum JoinKind {
    | Inner
    | Left
    | Right
    | Full
}
func joinKeyword(k: JoinKind): String {
    match (k) {
        case Inner => "INNER JOIN"
        case Left => "LEFT JOIN"
        case Right => "RIGHT JOIN"
        case Full => "FULL JOIN"
    }
}

// ===== OnConflict =====
/**
 * ON CONFLICT 子句(_upsert_)。
 * - DoNothing(target) → ON CONFLICT (target) DO NOTHING
 * - DoUpdate(target, setExprs) → ON CONFLICT (target) DO UPDATE SET col = expr, ...
 *   setExprs 中可用 "EXCLUDED.col" 引用插入值；expr 中的占位符 $n 由本子句编号续接。
 */
public enum OnConflict {
    | DoNothing(Array<String>)
    | DoUpdate(Array<String>, Array<(String, String)>)  // (targetCols, [(setCol, setExpr)])
}

/**
 * EXCLUDED.col 引用（upsert setExprs 用）：返回 "excluded"."col" 原始片段。
 * 用法：insert.onConflictDoUpdate(["id"], [("updated_at", "CURRENT_TIMESTAMP"), ("count", "excluded".\"count\")])
 * 或直接与其他字符串表达式拼接。
 */
public func Excluded(col: String): String {
    defaultDialect.quoteIdent("excluded") + "." + defaultDialect.quoteIdent(col)
}

// ===== LockBehavior =====
/**
 * 行锁行为（对标 sea_query SelectForUpdate）。
 * - Wait:        FOR UPDATE（等待锁，默认）
 * - SkipLocked:  FOR UPDATE SKIP LOCKED（跳过已锁行，任务队列领取场景）
 * - NoWait:      FOR UPDATE NOWAIT（抢不到锁立即报错）
 * 渲染位置：LIMIT/OFFSET 之后（PG 语法硬约束）。
 */
public enum LockBehavior {
    | Wait
    | SkipLocked
    | NoWait
}

/** LockBehavior → SQL 片段（不含 FOR UPDATE 前缀）。 */
public func lockBehaviorSuffix(b: LockBehavior): String {
    match (b) {
        case Wait => ""
        case SkipLocked => " SKIP LOCKED"
        case NoWait => " NOWAIT"
    }
}

// ===== SelectQuery =====
/**
 * SELECT 构建。columns 留空表示 SELECT *。
 * rawFragment(sql, params) 追加原始 SQL 片段(如 CTE/窗口函数),拼在 SELECT 主体前作为前缀片段
 * (典型用法：cte 片段 + 主体 SELECT；具体前/后位置由调用方决定，这里统一前置)。
 */
public class SelectQuery {
    var schema: ?String = None
    var table: String = ""
    var cols: Array<String> = Array<String>()           // 留空 → *
    // 原始(不引号)SELECT 表达式，与 cols 并存；build() 时先 cols 后 rawCols。
    // (expr, alias) — expr 原样输出，alias 非空时输出 `expr AS "alias"`。
    var rawCols: ArrayList<(String, String)> = ArrayList<(String, String)>()
    // 类型化 Expr 列：(Expr, alias)；build 时在 rawCols 之后渲染。
    var exprCols: ArrayList<(Expr, String)> = ArrayList<(Expr, String)>()
    var distinctFlag: Bool = false
    // DISTINCT ON (cols)：PG 专属；与 distinctFlag 互斥；cols 必须是最左 ORDER BY 前缀
    var distinctOnCols: Array<String> = Array<String>()
    var joins: ArrayList<(JoinKind, String, String)> = ArrayList<(JoinKind, String, String)>()   // (kind, table, onSql)
    var joinParams: ArrayList<Value> = ArrayList<Value>()
    // JOIN ON 子句的参数(按 join 顺序累积；build 时在 WHERE 之前续编号压入)。
    var joinOnParams: ArrayList<Value> = ArrayList<Value>()
    var whereCond: ?Cond = None
    var groupByCols: Array<String> = Array<String>()
    var groupByRaw: String = ""                          // 原始 GROUP BY(覆盖 groupByCols)
    var havingCond: ?Cond = None
    // orderBys: (expr, order, nullsClause, isRaw) — isRaw=true 时 expr 原样输出，否则 build 时由 dialect 引号
    var orderBys: ArrayList<(String, Order, String, Bool)> = ArrayList<(String, Order, String, Bool)>()
    var limitVal: ?Int64 = None
    var offsetVal: ?Int64 = None
    var lockClause: String = ""                          // FOR UPDATE / FOR SHARE
    var rawPrefix: String = ""                           // 前置原始片段(CTE 等)
    var rawPrefixParams: ArrayList<Value> = ArrayList<Value>()
    // 派生表 FROM：subSql + alias；设了则忽略 schema/table。
    var fromSubSql: String = ""
    var fromSubAlias: String = ""
    var fromSubParams: ArrayList<Value> = ArrayList<Value>()
    // UNION / UNION ALL 尾随查询（暂存原始 SQL + 参数，build 时拼在末尾）。
    var unions: ArrayList<(String, Array<Value>, Bool)> = ArrayList<(String, Array<Value>, Bool)>()  // (sql, params, all)
    // CTE（WITH 子句）：结构化 SelectQuery 传入，build 时占位符结构性自动续编。
    var ctes: ArrayList<CTEDef> = ArrayList<CTEDef>()
    // LATERAL JOIN：JOIN [CROSS] LATERAL (sub) AS alias [ON ...]；sub 为结构化 SelectQuery。
    var lateralJoins: ArrayList<LateralJoin> = ArrayList<LateralJoin>()

    public init() {}

    public func from(s: String, table!: String): SelectQuery {
        this.schema = s
        this.table = table
        this
    }
    public func from(table: String): SelectQuery {
        this.table = table
        this
    }
    public func withSchema(s: String): SelectQuery { this.schema = s; this }

    /** 派生表 FROM：FROM (subSql) AS alias，subSql 中的 $n 占位符由调用方写好，params 按序对应。 */
    public func fromSubquery(subSql: String, alias: String, params: Array<Value>): SelectQuery {
        this.fromSubSql = subSql
        this.fromSubAlias = alias
        for (p in params) { this.fromSubParams.add(p) }
        this
    }
    /** 原始 FROM(不引号)，用于视图名/函数调用等。 */
    public func fromRaw(sql: String): SelectQuery {
        this.table = sql
        this.schema = None
        this
    }

    public func select(cols: Array<String>): SelectQuery { this.cols = cols; this }
    public func addColumn(c: String): SelectQuery {
        let arr = ArrayList<String>()
        for (x in cols) { arr.add(x) }
        arr.add(c)
        this.cols = arr.toArray()
        this
    }
    /** 追加原始(不引号)SELECT 表达式，可带别名。如 EXTRACT(EPOCH FROM x)、COUNT(*)、COALESCE(...)。 */
    public func addRawColumn(expr: String, alias!: String = ""): SelectQuery {
        rawCols.add((expr, alias))
        this
    }
    /** 追加类型化 Expr 列，可带别名。占位符在 build 时续编号压入。 */
    public func selectExpr(e: Expr, alias!: String = ""): SelectQuery {
        exprCols.add((e, alias))
        this
    }
    /** whereExpr：用类型化 Expr 作 WHERE 条件(覆盖已有 where)。 */
    public func whereExpr(e: Expr): SelectQuery {
        whereCond = Some(Cond.ExprCond(e))
        this
    }
    /** andWhereExpr：在已有 WHERE 上 AND 一个 Expr 条件。 */
    public func andWhereExpr(e: Expr): SelectQuery {
        whereCond = match (whereCond) {
            case Some(existing) => Some(Cond.And([existing, Cond.ExprCond(e)]))
            case None => Some(Cond.ExprCond(e))
        }
        this
    }
    /** havingExpr：用类型化 Expr 作 HAVING 条件。 */
    public func havingExpr(e: Expr): SelectQuery {
        havingCond = Some(Cond.ExprCond(e))
        this
    }
    /** orderByExpr：按 Expr 排序(原样输出，不引号)。 */
    public func orderByExpr(e: Expr, o: Order, nulls!: String = ""): SelectQuery {
        orderBys.add((e.sql, o, nulls, true))
        for (p in e.params) { /* Expr 参数在 ORDER BY 处无占位符编号；简化：ORDER BY 不带参数 */ }
        this
    }
    public func distinct(): SelectQuery { distinctFlag = true; this }

    /**
     * DISTINCT ON (cols)（PG 专属）：与 distinct() 互斥；cols 必须是最左 ORDER BY 前缀
     * （PG 硬约束：SELECT DISTINCT ON 表达式必须匹配初始 ORDER BY 表达式），build() 时校验。
     */
    public func distinctOn(cols: Array<String>): SelectQuery {
        distinctOnCols = cols
        this
    }

    public func join(kind: JoinKind, table: String, on: String): SelectQuery {
        joins.add((kind, table, on))
        this
    }
    /** JOIN 带 ON 子句参数：on 中的 $n 占位符续编号，params 按序对应。 */
    public func joinWithParams(kind: JoinKind, table: String, on: String, params: Array<Value>): SelectQuery {
        joins.add((kind, table, on))
        for (p in params) { joinOnParams.add(p) }
        this
    }
    public func innerJoin(table: String, on: String): SelectQuery { join(JoinKind.Inner, table, on) }
    public func leftJoin(table: String, on: String): SelectQuery { join(JoinKind.Left, table, on) }
    public func leftJoinWithParams(table: String, on: String, params: Array<Value>): SelectQuery {
        joinWithParams(JoinKind.Left, table, on, params)
    }

    /**
     * LATERAL JOIN（PG 专属）：joinLateral(kind, subSelect, alias, on)。
     * - subSelect 为结构化 SelectQuery，占位符 build 时结构性续编（同 CTE 机制）。
     * - on 为空 → CROSS JOIN LATERAL（无 ON）；非空 → {kind} JOIN LATERAL (...) AS alias ON {on}。
     * - LATERAL 可引用左侧表的列（相关子查询），ON 条件常用于右表行过滤。
     */
    public func joinLateral(kind: JoinKind, subSelect: SelectQuery, alias: String,
        on!: String = ""): SelectQuery {
        lateralJoins.add(LateralJoin(kind, subSelect, alias, onSql: on))
        this
    }

    public func filter(c: Cond): SelectQuery { whereCond = Some(c); this }
    public func filterIf(cond: Bool, c: () -> Cond): SelectQuery {
        if (cond) { whereCond = Some(c()) }
        this
    }
    /** 在已有 WHERE 上 AND 一个条件(多次调用累积)。 */
    public func andFilter(c: Cond): SelectQuery {
        whereCond = match (whereCond) {
            case Some(existing) => Some(Cond.And([existing, c]))
            case None => Some(c)
        }
        this
    }

    public func groupBy(cols: Array<String>): SelectQuery { groupByCols = cols; this }
    public func setGroupByRaw(expr: String): SelectQuery { groupByRaw = expr; this }
    public func having(c: Cond): SelectQuery { havingCond = Some(c); this }

    public func orderBy(col: String, o: Order): SelectQuery {
        orderBys.add((col, o, "", false))   // 存原始列名，build 时由 dialect 引号
        this
    }
    public func orderByAsc(col: String): SelectQuery { orderBy(col, Order.Asc) }
    public func orderByDesc(col: String): SelectQuery { orderBy(col, Order.Desc) }
    /** 原始 ORDER BY 表达式(不引号)，支持 RANDOM()、子查询、表前缀 ta_order.sort_order。
     *  nulls 为 "NULLS LAST" / "NULLS FIRST" / ""。 */
    public func orderByRaw(expr: String, o: Order, nulls!: String = ""): SelectQuery {
        orderBys.add((expr, o, nulls, true))
        this
    }

    public func limit(n: Int64): SelectQuery { limitVal = Some(n); this }
    public func offset(n: Int64): SelectQuery { offsetVal = Some(n); this }

    /** FOR UPDATE：Wait → FOR UPDATE；SkipLocked → FOR UPDATE SKIP LOCKED；NoWait → FOR UPDATE NOWAIT。
     * 渲染位置在 LIMIT/OFFSET 之后（build() 内 LOCK 段，符合 PG 子句顺序）。 */
    public func forUpdate(behavior!: LockBehavior = LockBehavior.Wait): SelectQuery {
        lockClause = "FOR UPDATE" + lockBehaviorSuffix(behavior)
        this
    }
    /** FOR SHARE + 锁行为（同 forUpdate）。 */
    public func forShare(behavior!: LockBehavior = LockBehavior.Wait): SelectQuery {
        lockClause = "FOR SHARE" + lockBehaviorSuffix(behavior)
        this
    }

    /** 追加 UNION / UNION ALL 查询(原始 SQL + 参数)。 */
    public func union(sql: String, params: Array<Value>): SelectQuery {
        unions.add((sql, params, false))
        this
    }
    public func unionAll(sql: String, params: Array<Value>): SelectQuery {
        unions.add((sql, params, true))
        this
    }

    /** 追加前置原始片段(如 WITH ... AS (...)，CTE)。可多次调用。 */
    public func rawPrefixFragment(sql: String, params: Array<Value>): SelectQuery {
        rawPrefix = if (rawPrefix.isEmpty()) { sql } else { rawPrefix + " " + sql }
        for (p in params) { rawPrefixParams.add(p) }
        this
    }

    /**
     * 结构化 CTE（对标 sea_query WithQuery）：with("t", subSelect) → WITH "t" AS (sub) 前缀。
     * - subQuery 是 SelectQuery 对象；其占位符（$1..$k 局部编号）在 build() 时经
     *   rewriteDollarSeq 结构性续编到主查询编号链，调用方无需手写续接 $n。
     * - 多个 with() 聚合输出单个 WITH 子句；RECURSIVE 是列表级标志：任一 recursive
     *   即输出 WITH RECURSIVE（PG 语法要求，非逐 CTE 标志）。
     * - columnList 非空时输出 name("c1","c2")（递归 CTE 常用，列名经 quoteIdent 防注入）。
     * - 与旧 rawPrefixFragment 兼容：CTE 在前（WITH 必须最前），rawPrefix 紧随其后。
     */
    public func withCte(name: String, subQuery: SelectQuery, recursive!: Bool = false,
        columnList!: Array<String> = Array<String>()): SelectQuery {
        ctes.add(CTEDef(name, subQuery, recursive: recursive, columnList: columnList))
        this
    }

    /** 构建为 SQL + 参数(占位符跨片段连续编号，风格由 Dialect 决定)。 */
    public func build(dialect: Dialect): (String, Array<Value>) {
        let allParams = ArrayList<Value>()
        let ph = Placeholder(dialect.placeholderStyle())

        var sql = ""
        // 前置原始片段(CTE 等)的参数先编号
        // ===== CTE（WITH 子句，必须在最前）=====
        if (ctes.size > 0) {
            var withSql = ""
            // RECURSIVE 是列表级标志：任一 CTE 标记 recursive 即输出单个 WITH RECURSIVE
            var anyRecursive = false
            for (cte in ctes) {
                if (cte.recursive) { anyRecursive = true }
            }
            withSql += if (anyRecursive) { "WITH RECURSIVE " } else { "WITH " }
            var first = true
            for (cte in ctes) {
                if (!first) { withSql += ", " }
                first = false
                // 列名（可选）
                withSql += dialect.quoteIdent(cte.name)
                if (cte.columnList.size > 0) {
                    let q = Array<String>(cte.columnList.size, { i => dialect.quoteIdent(cte.columnList[i]) })
                    withSql += "(" + joinComma(q) + ")"
                }
                withSql += " AS ("
                // subQuery 占位符结构性续编：sub 局部 $1..$k 重写为 $(offset+1)..$(offset+k)，
                // 参数按序压入 allParams 并推进 ph（ph.current 即 offset）。
                let (subSql, subParams) = cte.subQuery.build(dialect)
                let offset = ph.current()
                let (rewritten, _) = rewriteDollarSeq(subSql, offset)
                for (p in subParams) {
                    allParams.add(p)
                    ph.next()
                }
                withSql += rewritten
                withSql += ")"
            }
            sql = withSql + " "
        }
        if (!rawPrefix.isEmpty()) {
            // rawPrefix 中的占位符假设已是续接编号（调用方手写）；CTE 已占用 $1..$k 时
            // rawPrefix 编号由调用方衔接（兼容保留，新代码建议用 with()）。
            if (!sql.isEmpty()) {
                sql += rawPrefix + " "
            } else {
                sql = rawPrefix + " "
            }
            for (_ in rawPrefixParams) { ph.next() }
            for (p in rawPrefixParams) { allParams.add(p) }
        }
        // 派生表 FROM 的参数编号(在 SELECT 列之后、FROM 之前压入参数列)
        // 注意：占位符在 SQL 文本中按出现顺序编号，派生表参数出现在 FROM 子句，
        // 而 SELECT 列通常无占位符(原始表达式)，故派生表参数从 $1 起编号与文本顺序一致。
        // 但若 rawPrefix 已占用 $1..$k，派生表参数应从 $k+1 起——此处先压入参数并推进编号，
        // 实际 SQL 文本中派生表占位符由调用方写为续接编号。
        // SELECT
        var sel = "SELECT "
        if (distinctOnCols.size > 0) {
            // PG 硬约束 1：与普通 distinct() 互斥
            if (distinctFlag) {
                throw CsormError("SelectQuery.build: distinct() and distinctOn() are mutually exclusive")
            }
            // PG 硬约束 2：distinctOn 的列必须是最左 ORDER BY 前缀
            if (orderBys.size < distinctOnCols.size) {
                throw CsormError("SelectQuery.build: DISTINCT ON columns must be a prefix of ORDER BY (ORDER BY has fewer columns)")
            }
            for (i in 0..distinctOnCols.size) {
                let (expr, _, _, isRaw) = orderBys[i]
                // orderBys[0] 存原始列名（isRaw=false 时 build 时才引号），直接与 distinctOnCols 比对原始名
                if (expr != distinctOnCols[i]) {
                    throw CsormError("SelectQuery.build: DISTINCT ON columns must be a leftmost prefix of ORDER BY; mismatch at index " + i.toString() + ": DISTINCT ON '" + distinctOnCols[i] + "' vs ORDER BY '" + expr + "'")
                }
            }
            sel += dialect.renderDistinctOn(distinctOnCols) + " "
        } else if (distinctFlag) {
            sel += "DISTINCT "
        }
        let selParts = ArrayList<String>()
        if (cols.size == 0 && rawCols.size == 0 && exprCols.size == 0) {
            selParts.add("*")
        } else {
            if (cols.size > 0) {
                for (c in cols) { selParts.add(dialect.quoteIdent(c)) }
            }
            for ((expr, alias) in rawCols) {
                if (alias.isEmpty()) {
                    selParts.add(expr)
                } else {
                    selParts.add(expr + " AS " + dialect.quoteIdent(alias))
                }
            }
            // 类型化 Expr 列：渲染并续编号压入参数
            for ((e, alias) in exprCols) {
                let rendered = renderExpr(e, allParams, ph)
                if (alias.isEmpty()) {
                    selParts.add(rendered)
                } else {
                    selParts.add(rendered + " AS " + dialect.quoteIdent(alias))
                }
            }
        }
        sel += joinComma(selParts.toArray())
        // FROM
        if (!fromSubSql.isEmpty()) {
            // 派生表参数压入(在 FROM 子句的占位符处)
            for (p in fromSubParams) {
                allParams.add(p)
                ph.next()
            }
            sel += " FROM (" + fromSubSql + ") AS " + dialect.quoteIdent(fromSubAlias)
        } else {
            sel += " FROM " + dialect.quoteTable(schema, table)
        }
        // JOIN(ON 子句参数压入并续编号)
        for ((k, t, on) in joins) {
            sel += " " + joinKeyword(k) + " " + dialect.quoteIdent(t) + " ON " + on
        }
        // LATERAL JOIN（sub 占位符结构性续编，参数在 ON/WHERE 之前压入）
        for (lj in lateralJoins) {
            let (subSql, subParams) = lj.subQuery.build(dialect)
            let offset = ph.current()
            let (rewritten, _) = rewriteDollarSeq(subSql, offset)
            for (p in subParams) {
                allParams.add(p)
                ph.next()
            }
            if (lj.onSql.isEmpty()) {
                sel += " CROSS JOIN LATERAL (" + rewritten + ") AS " + dialect.quoteIdent(lj.alias)
            } else {
                sel += " " + joinKeyword(lj.kind) + " LATERAL (" + rewritten + ") AS " +
                    dialect.quoteIdent(lj.alias) + " ON " + lj.onSql
            }
        }
        // joinOnParams 按 join 顺序累积；假设 ON 子句中的占位符已由调用方按续接编号写好
        for (p in joinOnParams) {
            allParams.add(p)
            ph.next()
        }
        sql += sel
        // WHERE
        match (whereCond) {
            case Some(c) =>
                let w = renderCond(c, allParams, ph, dialect)
                sql += " WHERE " + w
            case None => ()
        }
        // GROUP BY
        if (!groupByRaw.isEmpty()) {
            sql += " GROUP BY " + groupByRaw
        } else if (groupByCols.size > 0) {
            let quoted = Array<String>(groupByCols.size, { i => dialect.quoteIdent(groupByCols[i]) })
            sql += " GROUP BY " + joinComma(quoted)
        }
        // HAVING
        match (havingCond) {
            case Some(c) =>
                let h = renderCond(c, allParams, ph, dialect)
                sql += " HAVING " + h
            case None => ()
        }
        // ORDER BY(四元组：expr/order/nulls/isRaw；isRaw=false 时由 dialect 引号列名，isRaw=true 时原样)
        if (orderBys.size > 0) {
            let parts = ArrayList<String>()
            for ((expr, o, nulls, isRaw) in orderBys) {
                let qExpr = if (isRaw) { expr } else { dialect.quoteIdent(expr) }
                var p = qExpr + " " + orderKeyword(o)
                if (!nulls.isEmpty()) { p += " " + nulls }
                parts.add(p)
            }
            sql += " ORDER BY " + joinComma(parts.toArray())
        }
        // LIMIT / OFFSET
        match (limitVal) {
            case Some(n) =>
                allParams.add(Value.VInt(n))
                sql += " LIMIT " + ph.next()
            case None => ()
        }
        match (offsetVal) {
            case Some(n) =>
                allParams.add(Value.VInt(n))
                sql += " OFFSET " + ph.next()
            case None => ()
        }
        // LOCK
        if (!lockClause.isEmpty()) {
            sql += " " + lockClause
        }
        // UNION / UNION ALL
        for ((uSql, uParams, isAll) in unions) {
            sql += if (isAll) { " UNION ALL " } else { " UNION " } + uSql
            for (p in uParams) {
                allParams.add(p)
                ph.next()
            }
        }
        (sql, allParams.toArray())
    }

    /** 构建为 SQL + 参数(默认 PG 方言)。 */
    public func build(): (String, Array<Value>) { build(defaultDialect) }

    /** 克隆(供 Paginator 与 count+data 双查询使用)。深拷贝所有可变集合。 */
    public func clone(): SelectQuery {
        let q = SelectQuery()
        q.schema = schema
        q.table = table
        // 深拷贝 cols(Array)
        let colsCopy = ArrayList<String>()
        for (c in cols) { colsCopy.add(c) }
        q.cols = colsCopy.toArray()
        // 深拷贝 rawCols
        for (rc in rawCols) { q.rawCols.add(rc) }
        // 深拷贝 exprCols(Expr 引用语义，直接复用)
        for (ec in exprCols) { q.exprCols.add(ec) }
        q.distinctFlag = distinctFlag
        // 深拷贝 joins
        for (j in joins) { q.joins.add(j) }
        for (p in joinParams) { q.joinParams.add(p) }
        for (p in joinOnParams) { q.joinOnParams.add(p) }
        q.whereCond = whereCond
        // 深拷贝 groupByCols
        let gbcCopy = ArrayList<String>()
        for (c in groupByCols) { gbcCopy.add(c) }
        q.groupByCols = gbcCopy.toArray()
        q.groupByRaw = groupByRaw
        q.havingCond = havingCond
        // 深拷贝 orderBys
        for (o in orderBys) { q.orderBys.add(o) }
        q.limitVal = limitVal
        q.offsetVal = offsetVal
        q.lockClause = lockClause
        q.rawPrefix = rawPrefix
        for (p in rawPrefixParams) { q.rawPrefixParams.add(p) }
        q.fromSubSql = fromSubSql
        q.fromSubAlias = fromSubAlias
        for (p in fromSubParams) { q.fromSubParams.add(p) }
        for (u in unions) { q.unions.add(u) }
        q
    }
}

// ===== InsertQuery =====
public class InsertQuery {
    var schema: ?String = None
    var table: String = ""
    var cols: Array<String> = Array<String>()
    var rows: ArrayList<ArrayList<Value>> = ArrayList<ArrayList<Value>>()
    var conflict: ?OnConflict = None
    var returningCols: Array<String> = Array<String>()  // 留空 → 无 RETURNING

    public init() {}

    public func into(table: String): InsertQuery { this.table = table; this }
    public func intoSchema(s: String, table!: String): InsertQuery {
        this.schema = s; this.table = table; this
    }

    public func columns(cols: Array<String>): InsertQuery { this.cols = cols; this }

    /** 追加一行值(顺序需与 columns 对齐)。可多次调用实现多行插入。 */
    public func values(vals: Array<Value>): InsertQuery {
        let l = ArrayList<Value>()
        for (v in vals) { l.add(v) }
        rows.add(l)
        this
    }

    public func onConflictDoNothing(target: Array<String>): InsertQuery {
        conflict = Some(OnConflict.DoNothing(target))
        this
    }
    /** upsert：setExprs 中可用 EXCLUDED.col 引用插入值；expr 可含 $n 占位符(续编号)。 */
    public func onConflictDoUpdate(target: Array<String>, setExprs: Array<(String, String)>): InsertQuery {
        conflict = Some(OnConflict.DoUpdate(target, setExprs))
        this
    }

    /**
     * upsert 语法糖：SET "col" = "excluded"."col"（col 列表逐个自赋值为冲突候选行的对应值）。
     * 基于 onConflictDoUpdate；需要混合自定义表达式时用 Excluded(col) 拼进 setExprs。
     */
    public func onConflictDoUpdateExcluded(target: Array<String>, cols: Array<String>): InsertQuery {
        let setExprs = Array<(String, String)>(cols.size, { i => (cols[i], Excluded(cols[i])) })
        conflict = Some(OnConflict.DoUpdate(target, setExprs))
        this
    }

    public func returning(cols: Array<String>): InsertQuery { returningCols = cols; this }
    public func returningAll(): InsertQuery { returningCols = ["*"]; this }
    public func returningId(col: String): InsertQuery { returningCols = [col]; this }

    public func build(dialect: Dialect): (String, Array<Value>) {
        if (table.isEmpty()) { throw CsormError("InsertQuery: table not set") }
        if (rows.size == 0) { throw CsormError("InsertQuery: no rows") }
        if (cols.size == 0 && rows[0].size > 0) {
            // 未指定列名，按位置插入(假定全列)
            throw CsormError("InsertQuery: columns not set")
        }
        let allParams = ArrayList<Value>()
        let ph = Placeholder(dialect.placeholderStyle())
        var sql = "INSERT INTO " + dialect.quoteTable(schema, table)
        // 列名
        let quotedCols = Array<String>(cols.size, { i => dialect.quoteIdent(cols[i]) })
        sql += " (" + joinComma(quotedCols) + ")"
        // VALUES
        let rowSqls = ArrayList<String>()
        for (row in rows) {
            let phs = ArrayList<String>()
            for (v in row) {
                allParams.add(v)
                phs.add(ph.next())
            }
            rowSqls.add("(" + joinComma(phs.toArray()) + ")")
        }
        sql += " VALUES " + joinComma(rowSqls.toArray())
        // ON CONFLICT(经 Dialect 渲染，支持各后端 upsert 语法)
        match (conflict) {
            case Some(DoNothing(target)) =>
                sql += dialect.renderOnConflictDoNothing(target)
            case Some(DoUpdate(target, setExprs)) =>
                sql += dialect.renderOnConflictDoUpdate(target, setExprs)
            case None => ()
        }
        // RETURNING
        if (returningCols.size > 0) {
            if (dialect.supportReturning()) {
                if (returningCols.size == 1 && returningCols[0] == "*") {
                    sql += " RETURNING *"
                } else {
                    let q = Array<String>(returningCols.size, { i => dialect.quoteIdent(returningCols[i]) })
                    sql += " RETURNING " + joinComma(q)
                }
            }
        }
        (sql, allParams.toArray())
    }

    public func build(): (String, Array<Value>) { build(defaultDialect) }
}

// ===== UpdateQuery =====
public class UpdateQuery {
    var schema: ?String = None
    var table: String = ""
    var setColVals: ArrayList<(String, Value)> = ArrayList<(String, Value)>()
    var setColExprs: ArrayList<(String, String, ArrayList<Value>)> = ArrayList<(String, String, ArrayList<Value>)>()
    var whereCond: ?Cond = None
    var returningCols: Array<String> = Array<String>()

    public init() {}

    public func updateTable(t: String): UpdateQuery { this.table = t; this }
    public func tableSchema(s: String, table!: String): UpdateQuery { this.schema = s; this.table = table; this }

    /** SET col = value(参数绑定)。 */
    public func set(col: String, v: Value): UpdateQuery { setColVals.add((col, v)); this }
    /** SET col = expr，expr 可含 $n 占位符(续编号),params 为对应参数。 */
    public func setExpr(col: String, expr: String, params: Array<Value>): UpdateQuery {
        let l = ArrayList<Value>()
        for (p in params) { l.add(p) }
        setColExprs.add((col, expr, l))
        this
    }
    /** SET col = 类型化 Expr(占位符续编号)。 */
    public func setExprTyped(col: String, e: Expr): UpdateQuery {
        let l = ArrayList<Value>()
        for (p in e.params) { l.add(p) }
        setColExprs.add((col, e.sql, l))
        this
    }

    public func filter(c: Cond): UpdateQuery { whereCond = Some(c); this }
    public func filterIf(cond: Bool, c: () -> Cond): UpdateQuery {
        if (cond) { whereCond = Some(c()) }
        this
    }

    public func returning(cols: Array<String>): UpdateQuery { returningCols = cols; this }
    public func returningAll(): UpdateQuery { returningCols = ["*"]; this }

    public func build(dialect: Dialect): (String, Array<Value>) {
        if (table.isEmpty()) { throw CsormError("UpdateQuery: table not set") }
        let allParams = ArrayList<Value>()
        let ph = Placeholder(dialect.placeholderStyle())
        var sql = "UPDATE " + dialect.quoteTable(schema, table) + " SET "
        let setParts = ArrayList<String>()
        for ((col, v) in setColVals) {
            allParams.add(v)
            setParts.add(dialect.quoteIdent(col) + " = " + ph.next())
        }
        for ((col, expr, params) in setColExprs) {
            for (p in params) {
                allParams.add(p)
                ph.next()
            }
            setParts.add(dialect.quoteIdent(col) + " = " + expr)
        }
        if (setParts.size == 0) { throw CsormError("UpdateQuery: no SET clause") }
        sql += joinComma(setParts.toArray())
        match (whereCond) {
            case Some(c) => sql += " WHERE " + renderCond(c, allParams, ph, dialect)
            case None => ()
        }
        if (returningCols.size > 0) {
            if (dialect.supportReturning()) {
                if (returningCols.size == 1 && returningCols[0] == "*") {
                    sql += " RETURNING *"
                } else {
                    let q = Array<String>(returningCols.size, { i => dialect.quoteIdent(returningCols[i]) })
                    sql += " RETURNING " + joinComma(q)
                }
            }
        }
        (sql, allParams.toArray())
    }

    public func build(): (String, Array<Value>) { build(defaultDialect) }
}

// ===== DeleteQuery =====
public class DeleteQuery {
    var schema: ?String = None
    var table: String = ""
    var whereCond: ?Cond = None
    var returningCols: Array<String> = Array<String>()

    public init() {}

    public func from(t: String): DeleteQuery { this.table = t; this }
    public func fromSchema(s: String, table!: String): DeleteQuery { this.schema = s; this.table = table; this }

    public func filter(c: Cond): DeleteQuery { whereCond = Some(c); this }
    public func filterIf(cond: Bool, c: () -> Cond): DeleteQuery {
        if (cond) { whereCond = Some(c()) }
        this
    }

    public func returning(cols: Array<String>): DeleteQuery { returningCols = cols; this }
    public func returningAll(): DeleteQuery { returningCols = ["*"]; this }

    public func build(dialect: Dialect): (String, Array<Value>) {
        if (table.isEmpty()) { throw CsormError("DeleteQuery: table not set") }
        let allParams = ArrayList<Value>()
        let ph = Placeholder(dialect.placeholderStyle())
        var sql = "DELETE FROM " + dialect.quoteTable(schema, table)
        match (whereCond) {
            case Some(c) => sql += " WHERE " + renderCond(c, allParams, ph, dialect)
            case None => ()
        }
        if (returningCols.size > 0) {
            if (dialect.supportReturning()) {
                if (returningCols.size == 1 && returningCols[0] == "*") {
                    sql += " RETURNING *"
                } else {
                    let q = Array<String>(returningCols.size, { i => dialect.quoteIdent(returningCols[i]) })
                    sql += " RETURNING " + joinComma(q)
                }
            }
        }
        (sql, allParams.toArray())
    }

    public func build(): (String, Array<Value>) { build(defaultDialect) }
}

// ===== 便捷构造函数 =====
public func selectQuery(): SelectQuery { SelectQuery() }
public func selectQuery(table: String): SelectQuery { SelectQuery().from(table) }
public func insertQuery(): InsertQuery { InsertQuery() }
public func insertQuery(table: String): InsertQuery { InsertQuery().into(table) }
public func updateQuery(): UpdateQuery { UpdateQuery() }
public func updateQuery(table: String): UpdateQuery { UpdateQuery().updateTable(table) }
public func deleteQuery(): DeleteQuery { DeleteQuery() }
public func deleteQuery(table: String): DeleteQuery { DeleteQuery().from(table) }