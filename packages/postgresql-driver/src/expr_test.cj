package postgresql_driver

/**
 * 阶段三 Expr 测试：验证类型化表达式渲染、查询构建器接入、Cond.ExprCond。
 */
import csorm.*
import csorm
import std.unittest.*
import std.unittest.testmacro.*
import std.env.getVariable
import std.collection.*

func exprConnStr(): String {
    getVariable("DB_STRING") ??
        "postgres://copur:e29khrowY77mGk@192.168.0.112:5432/lanludev?sslmode=disable&pool.max=5"
}

func openExprOrSkip(): ?Database {
    try {
        return Some(Database(PgConn(exprConnStr())))
    } catch (_: Exception) {
        println("[skip] no PostgreSQL available (expr test)")
        return None
    }
}

@Test
func test_expr_basic_render() {
    // col("age").gt(18) → "age" > $1
    let e = expr("age").gt(vint(18))
    @Expect(e.sql, "\"age\" > $1")
    @Expect(e.params.size, 1)
    match (e.params[0]) {
        case Value.VInt(x) => @Expect(x, 18)
        case _ => @Expect(true, false)
    }
    println("[expr-test] basic render passed")
}

@Test
func test_expr_arith_and_cmp() {
    // (age + 1) > 18 → ("age" + $1) > $2
    let e = expr("age").addVal(vint(1)).gt(vint(18))
    @Expect(e.sql, "(\"age\" + $1) > $2")
    @Expect(e.params.size, 2)
    println("[expr-test] arith+cmp passed: " + e.sql)
}

@Test
func test_expr_null_aware() {
    // = NULL → IS NULL
    let e1 = expr("name").eq(vnull())
    @Expect(e1.sql, "\"name\" IS NULL")
    // <> NULL → IS NOT NULL
    let e2 = expr("name").ne(vnull())
    @Expect(e2.sql, "\"name\" IS NOT NULL")
    println("[expr-test] null-aware passed")
}

@Test
func test_expr_functions() {
    let upper = expr("name").upper()
    @Expect(upper.sql, "UPPER(\"name\")")
    let cnt = exprCount()
    @Expect(cnt.sql, "COUNT(*)")
    let cntCol = exprCount(e: expr("id"))
    @Expect(cntCol.sql, "COUNT(\"id\")")
    let coalesce = exprCoalesce([expr("bio"), exprLit(vtext("N/A"))])
    @Expect(coalesce.sql.contains("COALESCE"), true)
    let now = exprNow()
    @Expect(now.sql, "CURRENT_TIMESTAMP")
    let extract = exprExtract("EPOCH", expr("created_at"))
    @Expect(extract.sql, "EXTRACT(EPOCH FROM \"created_at\")")
    println("[expr-test] functions passed")
}

@Test
func test_expr_in_query_builder() {
    match (openExprOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_expr_test")
            db.execRawSql("CREATE TABLE csorm_expr_test (id SERIAL PRIMARY KEY, name TEXT NOT NULL, age INT8 NOT NULL)")
            db.execRaw("INSERT INTO csorm_expr_test (name, age) VALUES ($1, $2)", [vtext("alice"), vint(30)])
            db.execRaw("INSERT INTO csorm_expr_test (name, age) VALUES ($1, $2)", [vtext("bob"), vint(20)])
            db.execRaw("INSERT INTO csorm_expr_test (name, age) VALUES ($1, $2)", [vtext("carol"), vint(25)])

            // selectExpr：UPPER(name) AS NAME + age
            let q = selectQuery("csorm_expr_test")
                .select(["id", "age"])
                .selectExpr(expr("name").upper(), alias: "name_upper")
                .whereExpr(expr("age").gt(vint(22)))
                .orderByExpr(expr("age"), Order.Desc)
            let (sql, params) = q.build()
            println("[expr-test] built SQL: " + sql)
            @Expect(sql.contains("UPPER"), true)
            @Expect(sql.contains("AS \"name_upper\""), true)
            @Expect(sql.contains("WHERE"), true)

            let rows = db.raw<csorm.Row>(sql, params, { r => r })
            @Expect(rows.size, 2)  // alice(30), carol(25) > 22
            // 按 age DESC：alice(30) 先于 carol(25)
            @Expect(rows[0].getInt64("age"), 30)
            @Expect(rows[1].getInt64("age"), 25)
            @Expect(rows[0].getText("name_upper"), "ALICE")

            // setExprTyped：age = age + 1
            let u = updateQuery("csorm_expr_test")
                .setExprTyped("age", expr("age").addVal(vint(1)))
                .filter(Cond.Cmp("name", "=", vtext("bob")))
            db.exec(u)

            // 验证 bob.age 从 20 → 21
            let r2 = db.rawOne<csorm.Row>("SELECT age FROM csorm_expr_test WHERE name = $1",
                [vtext("bob")], { r => r })
            match (r2) {
                case Some(row) => @Expect(row.getInt64("age"), 21)
                case None => @Expect(true, false)
            }

            // havingExpr：GROUP BY + HAVING COUNT(*) > 0
            let gq = selectQuery("csorm_expr_test")
                .select(["name"])
                .addRawColumn("COUNT(*)", alias: "cnt")
                .groupBy(["name"])
                .havingExpr(exprRaw("COUNT(*)").gt(vint(0)))
            let (gsql, _) = gq.build()
            @Expect(gsql.contains("HAVING"), true)
            println("[expr-test] group/having SQL: " + gsql)

            db.execRawSql("DROP TABLE IF EXISTS csorm_expr_test")
            db.close()
            println("[expr-test] query builder integration passed")
    }
}

@Test
func test_expr_cond_and_or() {
    // exprOr(expr("age").lt(vint(18)), expr("age").gt(vint(65)))
    let e = exprOr(expr("age").lt(vint(18)), expr("age").gt(vint(65)))
    let q = selectQuery("users").select(["*"]).whereExpr(e)
    let (sql, params) = q.build()
    @Expect(sql.contains("OR"), true)
    @Expect(sql.contains("WHERE"), true)
    @Expect(params.size, 2)
    println("[expr-test] OR cond passed: " + sql)
}

@Test
func test_expr_like_and_between() {
    let e = expr("name").like("%ali%")
    @Expect(e.sql, "\"name\" LIKE $1")
    let b = expr("age").between(vint(18), vint(65))
    @Expect(b.sql, "\"age\" BETWEEN $1 AND $2")
    @Expect(b.params.size, 2)
    let inE = expr("id").isIn([vint(1), vint(2), vint(3)])
    @Expect(inE.sql.contains("IN"), true)
    @Expect(inE.sql.contains("$1"), true)
    @Expect(inE.sql.contains("$3"), true)
    let notInE = expr("id").notIn([vint(1), vint(2)])
    @Expect(notInE.sql.contains("NOT IN"), true)
    // 空数组
    let emptyIn = expr("id").isIn([])
    @Expect(emptyIn.sql, "FALSE")
    let emptyNotIn = expr("id").notIn([])
    @Expect(emptyNotIn.sql, "TRUE")
    println("[expr-test] like/between/in passed")
}