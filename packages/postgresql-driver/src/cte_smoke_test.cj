package postgresql_driver

import csorm.*
import csorm
import std.unittest.*
import std.unittest.testmacro.*
import std.env.getVariable
import std.fs.*
import std.collection.*

// task-2 CTE/LATERAL 真库联调 smoke（本地 lanlutest.bench_rows）
@Test
func cte_smoke_real_db() {
    let cs = getVariable("DB_STRING") ?? ""
    if (cs.isEmpty()) { return }
    let f = File("cte_smoke.txt", OpenMode.Append)
    let db = Database(PgConn(cs))
    // CTE：WITH top AS (SELECT id,title FROM bench_rows ORDER BY id LIMIT 5) SELECT * FROM top
    let sub = selectQuery("bench_rows").select(["id", "title"]).orderByDesc("id").limit(5)
    let q = selectQuery("top").withCte("top", sub)
    let (sql, params) = q.build()
    f.write(("CTE SQL: " + sql + "\n").toArray())
    let rows = db.all<Row>(q, { r => r })
    f.write(("cte-rows=" + rows.size.toString() + "\n").toArray())
    // RECURSIVE 数字序列：WITH RECURSIVE seq(n) AS (VALUES(1) UNION ALL SELECT n+1 FROM seq WHERE n < 5) SELECT sum(n) FROM seq
    let rec = db.raw<Int64>(
        "WITH RECURSIVE seq(n) AS (VALUES (1) UNION ALL SELECT n + 1 FROM seq WHERE n < 5) SELECT sum(n) AS t FROM seq",
        [], { r => r.getInt64(0) })
    let recStr = if (rec.size > 0) { rec[0].toString() } else { "none" }
    f.write(("recursive-sum=" + recStr + "\n").toArray())
    // DISTINCT ON
    let don = selectQuery("bench_rows").distinctOn(["b1"]).select(["b1", "id"]).orderByAsc("b1").orderByDesc("id").limit(3)
    let drows = db.all<Row>(don, { r => r })
    f.write(("distinct-on-rows=" + drows.size.toString() + "\n").toArray())
    // LATERAL（左表 bench_rows 别名 l，右侧每行取最新 2 条）
    let lat = selectQuery("bench_rows").joinLateral(JoinKind.Inner,
        selectQuery("bench_rows").select(["id"]).orderByDesc("id").limit(2), "t")
    let lrows = db.all<Row>(lat, { r => r })
    f.write(("lateral-rows=" + lrows.size.toString() + "\n").toArray())
    db.close()
    f.close()
    @Assert(rows.size == 5, true)
    @Assert(rec.size == 1 && rec[0] == 15, true)
    @Assert(drows.size == 2, true)
    // LATERAL：bench_rows 每行（13,335）× 右侧 limit 2 = 26,670
    @Assert(lrows.size == 26670, true)
}