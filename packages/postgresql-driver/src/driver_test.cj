package postgresql_driver

import std.unittest.*
import std.unittest.testmacro.*
import std.env.getVariable
import std.collection.*

// 取连接串：优先 DB_STRING 环境变量，回退 lanludev。
func connStr(): String {
    getVariable("DB_STRING") ?? "postgres://copur:e29khrowY77mGk@192.168.0.112:5432/lanludev?sslmode=disable&pool.max=5"
}

// 无 PG 环境时静默跳过(连不上即 return true 表示跳过)。
func openOrSkip(): ?PGDatabase {
    try {
        return Some(PGDatabase(connStr()))
    } catch (_: Exception) {
        println("[skip] no PostgreSQL available")
        return None
    }
}

@Test
func test_pg_basic_query() {
    match (openOrSkip()) {
        case None => return
        case Some(db) =>
            let rows = db.query("SELECT 1::int8 AS a, 'hello' AS b, true AS c, 3.14::float8 AS d", [])
            @Expect(rows.size, 1)
            let r = rows[0]
            @Expect(r.getInt64(0), 1)
            @Expect(r.getText("b"), "hello")
            @Expect(r.getBool("c"), true)
            let pi = r.getFloat64("d")
            @Expect(pi > 3.13 && pi < 3.15, true)
            db.close()
            println("[pg-test] basic query passed")
    }
}

@Test
func test_pg_crud_params() {
    match (openOrSkip()) {
        case None => return
        case Some(db) =>
            db.execSql("DROP TABLE IF EXISTS pgdrv_test")
            db.execSql("CREATE TABLE pgdrv_test (id SERIAL PRIMARY KEY, name TEXT NOT NULL, n INT8 NOT NULL, active BOOL DEFAULT true)")
            let aff = db.exec("INSERT INTO pgdrv_test (name, n, active) VALUES ($1, $2, $3)",
                [PGText("alice"), PGInt64(30), PGBool(true)])
            @Expect(aff, 1)
            db.exec("INSERT INTO pgdrv_test (name, n) VALUES ($1, $2)", [PGText("bob"), PGInt64(7)])
            @Expect(db.affectedRows(), 1)
            let rows = db.query("SELECT id, name, n, active FROM pgdrv_test ORDER BY id", [])
            @Expect(rows.size, 2)
            @Expect(rows[0].getText("name"), "alice")
            @Expect(rows[0].getInt64("n"), 30)
            @Expect(rows[0].getBool("active"), true)
            @Expect(rows[1].getText("name"), "bob")
            @Expect(rows[1].getBool("active"), true)   // DEFAULT true
            // UPDATE
            let u = db.exec("UPDATE pgdrv_test SET n=$1 WHERE name=$2", [PGInt64(99), PGText("bob")])
            @Expect(u, 1)
            @Expect(db.queryOne("SELECT n FROM pgdrv_test WHERE name=$1", [PGText("bob")]).getOrThrow().getInt64("n"), 99)
            // DELETE
            let d = db.exec("DELETE FROM pgdrv_test WHERE name=$1", [PGText("alice")])
            @Expect(d, 1)
            @Expect(db.query("SELECT * FROM pgdrv_test", []).size, 1)
            db.execSql("DROP TABLE pgdrv_test")
            db.close()
            println("[pg-test] CRUD with params passed")
    }
}

@Test
func test_pg_transaction() {
    match (openOrSkip()) {
        case None => return
        case Some(db) =>
            db.execSql("DROP TABLE IF EXISTS pgdrv_txn")
            db.execSql("CREATE TABLE pgdrv_txn (id SERIAL PRIMARY KEY, v TEXT)")
            // commit
            db.transaction({ =>
                db.exec("INSERT INTO pgdrv_txn (v) VALUES ($1)", [PGText("committed")])
            })
            @Expect(db.query("SELECT * FROM pgdrv_txn", []).size, 1)
            // rollback
            try {
                db.transaction({ =>
                    db.exec("INSERT INTO pgdrv_txn (v) VALUES ($1)", [PGText("rolledback")])
                    throw Exception("boom")
                })
            } catch (_: Exception) {}
            @Expect(db.query("SELECT * FROM pgdrv_txn", []).size, 1)   // rollback 生效
            // savepoint
            db.begin()
            db.exec("INSERT INTO pgdrv_txn (v) VALUES ($1)", [PGText("outer")])
            db.save("sp1")
            db.exec("INSERT INTO pgdrv_txn (v) VALUES ($1)", [PGText("inner")])
            db.rollback("sp1")
            db.commit()
            @Expect(db.query("SELECT * FROM pgdrv_txn", []).size, 2)   // committed + outer
            db.execSql("DROP TABLE pgdrv_txn")
            db.close()
            println("[pg-test] transaction commit/rollback/savepoint passed")
    }
}

@Test
func test_pg_sqlstate() {
    match (openOrSkip()) {
        case None => return
        case Some(db) =>
            db.execSql("DROP TABLE IF EXISTS pgdrv_uq")
            db.execSql("CREATE TABLE pgdrv_uq (id INT4 PRIMARY KEY)")
            db.exec("INSERT INTO pgdrv_uq VALUES ($1)", [PGInt32(1)])
            var caught = false
            try {
                db.exec("INSERT INTO pgdrv_uq VALUES ($1)", [PGInt32(1)])   // duplicate PK
            } catch (e: PGError) {
                caught = true
                @Expect(e.isUniqueViolation(), true)
                @Expect(e.sqlstate, "23505")
            }
            @Expect(caught, true)
            db.execSql("DROP TABLE pgdrv_uq")
            db.close()
            println("[pg-test] SQLSTATE unique-violation passed")
    }
}

@Test
func test_pg_array_and_jsonb() {
    match (openOrSkip()) {
        case None => return
        case Some(db) =>
            db.execSql("DROP TABLE IF EXISTS pgdrv_arr")
            db.execSql("CREATE TABLE pgdrv_arr (id SERIAL PRIMARY KEY, tags TEXT[], nums INT8[], meta JSONB)")
            // 写侧数组绑定：PGArray + $n::text[]
            db.exec("INSERT INTO pgdrv_arr (tags, nums, meta) VALUES ($1::text[], $2::int8[], $3::jsonb)",
                [PGArray([PGText("a"), PGText("b,c"), PGText("quote\"q")]),
                 PGArray([PGInt64(1), PGInt64(2), PGInt64(3)]),
                 PGJson("{\"k\":\"v\"}")])
            // 读侧数组
            let r = db.queryOne("SELECT tags, nums, meta FROM pgdrv_arr", []).getOrThrow()
            let tags = r.getTextArray("tags")
            @Expect(tags.size, 3)
            @Expect(tags[0], "a")
            @Expect(tags[1], "b,c")           // 含逗号的元素被正确引用/反转义
            @Expect(tags[2], "quote\"q")
            let nums = r.getInt64Array("nums")
            @Expect(nums.size, 3)
            @Expect(nums[0], 1)
            @Expect(nums[2], 3)
            @Expect(r.getJson("meta"), "{\"k\": \"v\"}")  // PG 回显 JSONB 会规范化空格
            // ANY 查询(数组绑定做 IN)
            let found = db.queryOne("SELECT id FROM pgdrv_arr WHERE 'b,c' = ANY($1::text[])",
                [PGArray([PGText("a"), PGText("b,c")])])
            @Expect(found.isSome(), true)
            db.execSql("DROP TABLE pgdrv_arr")
            db.close()
            println("[pg-test] array + JSONB read/write passed")
    }
}

@Test
func test_pg_cursor_stream() {
    match (openOrSkip()) {
        case None => return
        case Some(db) =>
            db.execSql("DROP TABLE IF EXISTS pgdrv_stream")
            db.execSql("CREATE TABLE pgdrv_stream (id INT8 PRIMARY KEY)")
            var i = 1
            while (i <= 25) {
                db.exec("INSERT INTO pgdrv_stream VALUES ($1)", [PGInt64(i)])
                i += 1
            }
            var total = 0
            // 用数组单元格绕过「lambda 不能捕获 var」限制
            let totalCell = Array<Int64>(1, { _ => 0 })
            db.streamQuery("SELECT id FROM pgdrv_stream ORDER BY id", [], 10, { chunk =>
                totalCell[0] += chunk.size
            })
            total = Int64(totalCell[0])
            @Expect(total, 25)
            // 事务内游标
            let txnCell = Array<Int64>(1, { _ => 0 })
            db.transaction({ =>
                db.streamQuery("SELECT id FROM pgdrv_stream", [], 7, { chunk =>
                    txnCell[0] += chunk.size
                })
            })
            @Expect(txnCell[0], 25)
            db.execSql("DROP TABLE pgdrv_stream")
            db.close()
            println("[pg-test] cursor streaming passed")
    }
}

@Test
func test_pg_null_handling() {
    match (openOrSkip()) {
        case None => return
        case Some(db) =>
            db.execSql("DROP TABLE IF EXISTS pgdrv_null")
            db.execSql("CREATE TABLE pgdrv_null (id INT4 PRIMARY KEY, opt TEXT, optn INT8)")
            db.exec("INSERT INTO pgdrv_null (id, opt, optn) VALUES ($1, $2, $3)",
                [PGInt32(1), PGNull, PGNull])
            let r = db.queryOne("SELECT opt, optn FROM pgdrv_null WHERE id=$1", [PGInt32(1)]).getOrThrow()
            @Expect(r.isNull("opt"), true)
            @Expect(r.getOrNullText("opt").isSome(), false)
            @Expect(r.getOrNullInt64("optn").isSome(), false)
            @Expect(r.getText("opt"), "")   // NULL 读文本回退空串
            db.execSql("DROP TABLE pgdrv_null")
            db.close()
            println("[pg-test] NULL handling passed")
    }
}
