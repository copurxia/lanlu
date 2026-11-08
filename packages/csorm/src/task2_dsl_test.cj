package csorm

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.*

// ===== task-2 阶段2 SQL DSL 单测（纯单测，不依赖 DB）=====

// ---------- LockBehavior / forUpdate ----------

@Test
func test_lock_behavior_suffix() {
    @Assert(lockBehaviorSuffix(LockBehavior.Wait), "")
    @Assert(lockBehaviorSuffix(LockBehavior.SkipLocked), " SKIP LOCKED")
    @Assert(lockBehaviorSuffix(LockBehavior.NoWait), " NOWAIT")
}

@Test
func test_for_update_render_position() {
    // FOR UPDATE 必须渲染在 LIMIT/OFFSET 之后（PG 子句顺序硬约束）
    let q = selectQuery("tasks").filter(col("status").eq("pending"))
        .orderByAsc("id").limit(10).forUpdate(behavior: LockBehavior.SkipLocked)
    let (sql, params) = q.build()
    let lockIdx = indexOfSub(sql, "FOR UPDATE SKIP LOCKED")
    let limitIdx = indexOfSub(sql, "LIMIT")
    @Assert(lockIdx >= 0, true)
    @Assert(limitIdx >= 0, true)
    @Assert(lockIdx > limitIdx, true)
    @Assert(params.size, 2)
}

@Test
func test_for_update_variants() {
    let (sql1, _) = selectQuery("t").forUpdate().build()
    @Assert(indexOfSub(sql1, "FOR UPDATE") >= 0, true)
    @Assert(indexOfSub(sql1, "SKIP LOCKED"), -1)
    let (sql2, _) = selectQuery("t").forUpdate(behavior: LockBehavior.NoWait).build()
    @Assert(indexOfSub(sql2, "FOR UPDATE NOWAIT") >= 0, true)
    let (sql3, _) = selectQuery("t").forShare(behavior: LockBehavior.SkipLocked).build()
    @Assert(indexOfSub(sql3, "FOR SHARE SKIP LOCKED") >= 0, true)
}

// ---------- Expr.over ----------

@Test
func test_over_basic() {
    let e = exprCount().over(partitionBy: ["user_id"], orderBy: [("created_at", Order.Desc)])
    @Assert(indexOfSub(e.sql, "COUNT(*) OVER (PARTITION BY \"user_id\" ORDER BY \"created_at\" DESC") >= 0, true)
    @Assert(e.params.size, 0)
}

@Test
func test_over_frame() {
    // 4.8 running total 场景：SUM over + ROWS frame
    let e = exprSum(expr("amount")).over(
        partitionBy: ["uid"],
        frame: "ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW")
    @Assert(indexOfSub(e.sql, "SUM(\"amount\") OVER (PARTITION BY \"uid\" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)") >= 0, true)
}

@Test
func test_over_empty() {
    let e = exprCount().over()
    @Assert(indexOfSub(e.sql, "OVER ()") >= 0, true)
}

@Test
func test_over_in_query() {
    // over 结果作为 SELECT 列进入 builder，参数编号连续
    let e = exprSum(expr("amount")).over(partitionBy: ["uid"])
    let q = selectQuery("orders").selectExpr(e, alias: "running")
        .filter(col("uid").eq(42)).limit(5)
    let (sql, params) = q.build()
    @Assert(indexOfSub(sql, "OVER (PARTITION BY \"uid\")") >= 0, true)
    @Assert(params.size, 2)
}

// ---------- helper ----------

func indexOfSub(hay: String, needle: String): Int64 {
    let h = hay.toArray()
    let n = needle.toArray()
    if (n.size == 0 || h.size < n.size) { return -1 }
    for (i in 0..h.size - n.size + 1) {
        var ok = true
        for (j in 0..n.size) {
            if (h[i + j] != n[j]) { ok = false; break }
        }
        if (ok) { return i }
    }
    -1
}
// ---------- CTE（withCte）----------

@Test
func test_with_cte_basic() {
    let sub = selectQuery("users").filter(col("active").eq(true))
    let q = selectQuery("t").withCte("active_users", sub).filter(col("uid").gt(10))
    let (sql, params) = q.build()
    @Assert(indexOfSub(sql, "WITH \"active_users\" AS (SELECT") >= 0, true)
    @Assert(indexOfSub(sql, "$1") >= 0, true)
    // sub 的 $1 与 where 的 $2 连续
    @Assert(params.size, 2)
    @Assert(indexOfSub(sql, "WHERE") > indexOfSub(sql, "WITH"), true)
}

@Test
func test_with_cte_recursive_list_level() {
    // 多个 with 聚合：任一 recursive → 单个 WITH RECURSIVE
    let s1 = selectQuery("seed").filter(col("id").eq(1))
    let s2 = selectQuery("child").filter(col("n").lt(5))
    let q = selectQuery("t")
        .withCte("a", s1)
        .withCte("b", s2, recursive: true)
    let (sql, _) = q.build()
    @Assert(indexOfSub(sql, "WITH RECURSIVE \"a\" AS (") >= 0, true)
    @Assert(indexOfSub(sql, "WITH \"a\"") , -1)
    @Assert(indexOfSub(sql, ", \"b\" AS (") >= 0, true)
}

@Test
func test_with_cte_placeholder_chain() {
    // 编号链矩阵：2 个 CTE 各带参数 + rawPrefix 混用 + 主 where
    let s1 = selectQuery("t1").filter(col("a").eq(1))
    let s2 = selectQuery("t2").filter(col("b").eq(2))
    let q = selectQuery("main")
        .withCte("c1", s1)
        .withCte("c2", s2)
        .filter(col("x").eq(3))
    let (sql, params) = q.build()
    @Assert(params.size, 3)
    // CTE 内部 $1/$2 连续，主 WHERE 为 $3
    @Assert(indexOfSub(sql, "$1") >= 0, true)
    @Assert(indexOfSub(sql, "$2") >= 0, true)
    @Assert(indexOfSub(sql, "$3") >= 0, true)
    let p1 = indexOfSub(sql, "$1")
    let p2 = indexOfSub(sql, "$2")
    let p3 = indexOfSub(sql, "$3")
    @Assert(p1 < p2 && p2 < p3, true)
}

// ---------- distinctOn ----------

@Test
func test_distinct_on_valid_prefix() {
    let q = selectQuery("events")
        .distinctOn(["user_id"])
        .orderByAsc("user_id")
        .orderByDesc("created_at")
    let (sql, _) = q.build()
    @Assert(indexOfSub(sql, "DISTINCT ON (\"user_id\")") >= 0, true)
    @Assert(indexOfSub(sql, "ORDER BY \"user_id\" ASC, \"created_at\" DESC") >= 0, true)
}

@Test
func test_distinct_on_rejects_non_prefix() {
    let q = selectQuery("events").distinctOn(["user_id"]).orderByAsc("created_at")
    var threw = false
    try {
        let (_, _) = q.build()
    } catch (e: CsormError) {
        threw = true
        @Assert(e.message.contains("prefix of ORDER BY"), true)
    }
    @Assert(threw, true)
}

@Test
func test_distinct_on_mutually_exclusive() {
    let q = selectQuery("events").distinct().distinctOn(["user_id"]).orderByAsc("user_id")
    var threw = false
    try {
        let (_, _) = q.build()
    } catch (e: CsormError) {
        threw = true
        @Assert(e.message.contains("mutually exclusive"), true)
    }
    @Assert(threw, true)
}

// ---------- joinLateral ----------

@Test
func test_join_lateral_cross() {
    let sub = selectQuery("children").filter(col("parent_id").eq(1))
    let q = selectQuery("parents").joinLateral(JoinKind.Inner, sub, "c")
    let (sql, params) = q.build()
    @Assert(indexOfSub(sql, "CROSS JOIN LATERAL (SELECT") >= 0, true)
    @Assert(indexOfSub(sql, "AS \"c\"") >= 0, true)
    @Assert(params.size, 1)
}

@Test
func test_join_lateral_with_on_and_placeholder_chain() {
    // LATERAL sub 占位符 $1 续编 + 主 WHERE $2
    let sub = selectQuery("orders").filter(col("uid").eq(7))
    let q = selectQuery("users")
        .joinLateral(JoinKind.Left, sub, "o", on: "o.uid = users.id")
        .filter(col("active").eq(true))
    let (sql, params) = q.build()
    @Assert(indexOfSub(sql, "LEFT JOIN LATERAL (SELECT") >= 0, true)
    @Assert(indexOfSub(sql, "ON o.uid = users.id") >= 0, true)
    @Assert(params.size, 2)
    @Assert(indexOfSub(sql, "$1") < indexOfSub(sql, "$2"), true)
}

// ---------- onConflictDoUpdateExcluded ----------

@Test
func test_on_conflict_excluded_sugar() {
    let q = insertQuery("t")
        .columns(["id", "name"]).values([vint(1), vtext("a")])
        .onConflictDoUpdateExcluded(["id"], ["name"])
    let (sql, _) = q.build()
    @Assert(indexOfSub(sql, "ON CONFLICT (\"id\") DO UPDATE SET \"name\" = \"excluded\".\"name\"") >= 0, true)
}

@Test
func test_excluded_helper() {
    @Assert(Excluded("count"), "\"excluded\".\"count\"")
}

// ---------- createIndex ----------

@Test
func test_create_index_basic() {
    let sb = SchemaBuilder().createIndex("idx_users_email", "users", ["email"])
    let sqls = sb.build()
    @Assert(sqls.size, 1)
    @Assert(sqls[0], "CREATE INDEX \"idx_users_email\" ON \"users\" USING btree (\"email\")")
}

@Test
func test_create_index_full_options() {
    let sql = createIndexSql("idx_gin_tags", "archives", ["tags"],
        method: IndexMethod.Gin, predicate: Some("active = true"),
        include: ["id"], unique: false, ifNotExists: true)
    @Assert(indexOfSub(sql, "CREATE INDEX IF NOT EXISTS \"idx_gin_tags\"") >= 0, true)
    @Assert(indexOfSub(sql, "USING gin (\"tags\")") >= 0, true)
    @Assert(indexOfSub(sql, "INCLUDE (\"id\")") >= 0, true)
    @Assert(indexOfSub(sql, "WHERE active = true") >= 0, true)
}

@Test
func test_create_index_unique_and_method_validation() {
    let sql = createIndexSql("idx_u", "t", ["a"], unique: true)
    @Assert(indexOfSub(sql, "CREATE UNIQUE INDEX") >= 0, true)
    @Assert(IndexMethod.isValid("gin"), true)
    @Assert(IndexMethod.isValid("evil; DROP TABLE"), false)
    var threw = false
    try {
        let _ = createIndexSql("idx", "t", ["a"], method: "btree; DROP TABLE t")
    } catch (e: CsormError) {
        threw = true
        @Assert(e.message.contains("invalid index method"), true)
    }
    @Assert(threw, true)
}

