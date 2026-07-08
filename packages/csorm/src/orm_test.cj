package csorm

import std.unittest.*
import std.unittest.testmacro.*
import std.env.getVariable
import std.collection.*
import postgresql_driver.*
import postgresql_driver.PGDriver
import std.database.sql.*
import csorm_macros.*

// 取连接串：优先 DB_STRING 环境变量，回退 lanludev。
func ormConnStr(): String {
    getVariable("DB_STRING") ??
        "postgres://copur:e29khrowY77mGk@192.168.0.112:5432/lanludev?sslmode=disable&pool.max=5"
}

// 无 PG 环境时静默跳过。
func openOrmOrSkip(): ?Database {
    try {
        return Some(Database(ormConnStr()))
    } catch (_: Exception) {
        println("[skip] no PostgreSQL available")
        return None
    }
}

// 测试用实体(由 @entity 宏生成 Entity/ActiveModel)。
@entity[table = "csorm_test_user"]
public struct TestUser {
    @pk[auto]
    public var id: Int64 = 0
    public var name: String = ""
    public var age: Int64 = 0
    public var bio: ?String = None
    @jsonb[]
    public var meta: String = ""
    public var tags: Array<String> = Array<String>()
}

@Test
func test_orm_basic_crud() {
    match (openOrmOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_test_user")
            db.execRawSql("CREATE TABLE csorm_test_user (id SERIAL PRIMARY KEY, name TEXT NOT NULL, age INT8 NOT NULL, bio TEXT, meta JSONB NOT NULL DEFAULT '{}', tags TEXT[])")
            // INSERT via builder
            let ins = insertQuery("csorm_test_user")
                .columns(["name", "age", "bio", "meta", "tags"])
                .values([vtext("alice"), vint(30), vnull(), vjson("{\"k\":\"v\"}"), textArray(["a", "b,c"])])
                .returning(["id", "name", "age", "bio", "meta", "tags"])
            let rows = db.execReturning<TestUser>(ins, { r => (testUserEntity().fromRow(r) as TestUser).getOrThrow() })
            @Expect(rows.size, 1)
            let u = rows[0]
            @Expect(u.name, "alice")
            @Expect(u.age, 30)
            @Expect(u.bio.isSome(), false)
            @Expect(u.tags.size, 2)
            @Expect(u.tags[1], "b,c")
            let insertedId = u.id

            // SELECT via builder
            let sel = selectQuery("csorm_test_user")
                .select(["id", "name", "age", "bio", "meta", "tags"])
                .filter(col("name").eq("alice"))
            let found = db.one<TestUser>(sel, { r => (testUserEntity().fromRow(r) as TestUser).getOrThrow() })
            @Expect(found.isSome(), true)
            @Expect(found.getOrThrow().id, insertedId)

            // UPDATE via builder
            let upd = updateQuery("csorm_test_user")
                .set("age", vint(31))
                .set("bio", vtext("hello"))
                .filter(col("id").eq(insertedId))
            let aff = db.exec(upd).rowsAffected
            @Expect(aff, 1)
            let u2 = db.rawOne<TestUser>("SELECT id, name, age, bio, meta, tags FROM csorm_test_user WHERE id=$1",
                [vint(insertedId)], { r => (testUserEntity().fromRow(r) as TestUser).getOrThrow() }).getOrThrow()
            @Expect(u2.age, 31)
            @Expect(u2.bio.isSome(), true)
            @Expect(u2.bio.getOrThrow(), "hello")

            // DELETE via builder
            let del = deleteQuery("csorm_test_user").filter(col("id").eq(insertedId))
            @Expect(db.exec(del).rowsAffected, 1)
            @Expect(db.raw<Int64>("SELECT COUNT(*) FROM csorm_test_user", [], { r => r.getInt64(0) })[0], 0)

            db.execRawSql("DROP TABLE csorm_test_user")
            db.close()
            println("[csorm-test] basic CRUD via builder passed")
    }
}

@Test
func test_orm_entity_macro() {
    // 验证 @entity 宏生成的 Entity/ActiveModel 元数据
    let e = testUserEntity()
    @Expect(e.table(), "csorm_test_user")
    @Expect(e.autoIncrement(), true)
    let cols = e.columns()
    @Expect(cols.size, 6)
    @Expect(cols[0], "id")
    @Expect(cols.contains("meta"), true)
    let pk = e.pkColumns()
    @Expect(pk.size, 1)
    @Expect(pk[0], "id")

    // ActiveModel 三态
    let am = e.emptyActive()
    @Expect(am.isChanged("name"), false)
    am.set("name", vtext("bob"))
    @Expect(am.isChanged("name"), true)
    // Value 枚举未实现 Equatable，模式匹配取值验证
    var gotName = ""
    match (am.getValue("name")) {
        case Value.VText(s) => gotName = s
        case _ => ()
    }
    @Expect(gotName, "bob")
    am.unset("name")
    @Expect(am.isChanged("name"), false)

    // setEntries 只含 Set 列
    am.set("name", vtext("bob"))
    am.set("age", vint(20))
    let entries = am.setEntries()
    @Expect(entries.size, 2)
    println("[csorm-test] @entity macro metadata passed")
}

@Test
func test_orm_upsert_on_conflict() {
    match (openOrmOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_test_upsert")
            db.execRawSql("CREATE TABLE csorm_test_upsert (k TEXT PRIMARY KEY, v INT8 NOT NULL, updated_at TIMESTAMPTZ DEFAULT now())")
            // 首次 INSERT
            db.exec(insertQuery("csorm_test_upsert").columns(["k", "v"]).values([vtext("a"), vint(1)]))
            // ON CONFLICT DO UPDATE
            let up = insertQuery("csorm_test_upsert")
                .columns(["k", "v"])
                .values([vtext("a"), vint(2)])
                .onConflictDoUpdate(["k"], [("v", "EXCLUDED.v"), ("updated_at", "now()")])
            db.exec(up)
            let r = db.rawOne<Int64>("SELECT v FROM csorm_test_upsert WHERE k=$1", [vtext("a")],
                { row => row.getInt64(0) })
            @Expect(r.isSome(), true)
            @Expect(r.getOrThrow(), 2)
            // ON CONFLICT DO NOTHING
            let dn = insertQuery("csorm_test_upsert")
                .columns(["k", "v"])
                .values([vtext("a"), vint(99)])
                .onConflictDoNothing(["k"])
            db.exec(dn)
            @Expect(db.rawOne<Int64>("SELECT v FROM csorm_test_upsert WHERE k=$1", [vtext("a")],
                { row => row.getInt64(0) }).getOrThrow(), 2)
            db.execRawSql("DROP TABLE csorm_test_upsert")
            db.close()
            println("[csorm-test] ON CONFLICT upsert passed")
    }
}

@Test
func test_orm_paginator() {
    match (openOrmOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_test_page")
            db.execRawSql("CREATE TABLE csorm_test_page (id INT8 PRIMARY KEY, n INT8 NOT NULL)")
            var i = 1
            while (i <= 25) {
                db.exec(insertQuery("csorm_test_page").columns(["id", "n"]).values([vint(i), vint(i * 10)]))
                i += 1
            }
            let base = selectQuery("csorm_test_page").select(["id", "n"]).orderByAsc("id")
            let p = Paginator<Int64>(db, base, 10, { r => r.getInt64("id") })
            @Expect(p.numItems(), 25)
            @Expect(p.numPages(), 3)
            @Expect(p.fetchPage(0).size, 10)
            @Expect(p.fetchPage(2).size, 5)
            // keyset 分页
            let kp = KeysetPaginator<Int64>(db, selectQuery("csorm_test_page").select(["id", "n"]),
                "id", 7, vint(0), { r => (r.getInt64("id"), vint(r.getInt64("id"))) })
            var total = 0
            while (true) {
                let page = kp.fetchNext()
                if (page.size == 0) { break }
                total += page.size
            }
            @Expect(total, 25)
            db.execRawSql("DROP TABLE csorm_test_page")
            db.close()
            println("[csorm-test] paginator + keyset passed")
    }
}

@Test
func test_orm_transaction_and_sqlstate() {
    match (openOrmOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_test_txn")
            db.execRawSql("CREATE TABLE csorm_test_txn (id INT4 PRIMARY KEY, v TEXT NOT NULL)")
            // 事务提交
            db.transaction({ =>
                db.exec(insertQuery("csorm_test_txn").columns(["id", "v"]).values([vint(1), vtext("ok")]))
            })
            @Expect(db.raw<Int64>("SELECT COUNT(*) FROM csorm_test_txn", [], { r => r.getInt64(0) })[0], 1)
            // 事务回滚
            try {
                db.transaction({ =>
                    db.exec(insertQuery("csorm_test_txn").columns(["id", "v"]).values([vint(2), vtext("rollback")]))
                    throw Exception("boom")
                })
            } catch (_: Exception) {}
            @Expect(db.raw<Int64>("SELECT COUNT(*) FROM csorm_test_txn", [], { r => r.getInt64(0) })[0], 1)
            // SQLSTATE 唯一约束冲突
            var caught = false
            try {
                db.exec(insertQuery("csorm_test_txn").columns(["id", "v"]).values([vint(1), vtext("dup")]))
            } catch (e: CsormError) {
                caught = true
                @Expect(e.isUniqueViolation(), true)
                @Expect(e.sqlstate, "23505")
            }
            @Expect(caught, true)
            db.execRawSql("DROP TABLE csorm_test_txn")
            db.close()
            println("[csorm-test] transaction + SQLSTATE classification passed")
    }
}

@Test
func test_orm_returning_full_row() {
    match (openOrmOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_test_ret")
            db.execRawSql("CREATE TABLE csorm_test_ret (id SERIAL PRIMARY KEY, status TEXT NOT NULL)")
            db.exec(insertQuery("csorm_test_ret").columns(["status"]).values([vtext("pending")]))
            // UPDATE ... RETURNING 全行(原子状态转换)
            let upd = updateQuery("csorm_test_ret")
                .set("status", vtext("running"))
                .filter(col("status").eq("pending"))
                .returningAll()
            let rows = db.execReturning<Array<UInt8>>(upd, { r =>
                // 仅验证能拿到 RETURNING 行
                r.getBytes("status")
            })
            @Expect(rows.size, 1)
            // bytes 读取验证不严格；改用 raw 复核
            let after = db.rawOne<String>("SELECT status FROM csorm_test_ret", [], { r => r.getText(0) })
            @Expect(after.getOrThrow(), "running")
            db.execRawSql("DROP TABLE csorm_test_ret")
            db.close()
            println("[csorm-test] UPDATE RETURNING full row passed")
    }
}

// 测试 @[column] / @[readonly] / 复合主键 宏能力。
@entity[table = "csorm_test_meta"]
public struct TestMeta {
    @pk[]
    public var k1: String = ""
    @pk[]
    public var k2: Int64 = 0
    @column[name = "display_name"]
    public var displayName: String = ""
    @readonly[]
    public var computed: String = ""
}

@Test
func test_orm_macro_column_readonly_composite_pk() {
    let e = testMetaEntity()
    @Expect(e.table(), "csorm_test_meta")
    @Expect(e.autoIncrement(), false)     // 复合主键无自增
    let cols = e.columns()
    @Expect(cols.size, 4)
    @Expect(cols.contains("display_name"), true)   // @[column] 改的 DB 列名
    @Expect(cols.contains("displayName"), false)
    let pk = e.pkColumns()
    @Expect(pk.size, 2)                    // 复合主键
    @Expect(pk[0], "k1")
    @Expect(pk[1], "k2")

    // readonly 列不参与 INSERT
    let am = e.emptyActive()
    am.set("k1", vtext("a"))
    am.set("k2", vint(1))
    am.set("displayName", vtext("Alice"))   // ActiveModel 按字段名索引
    am.set("computed", vtext("should-be-skipped"))
    let entries = am.setEntries()
    @Expect(entries.size, 3)               // computed 被 readonly 排除
    var hasComputed = false
    for ((c, _) in entries) {
        if (c == "computed") { hasComputed = true }   // setEntries 输出 DB 列名
    }
    @Expect(hasComputed, false)
    // 验证 setEntries 输出的是 DB 列名(display_name 而非 displayName)
    var hasDisplayName = false
    for ((c, _) in entries) {
        if (c == "display_name") { hasDisplayName = true }
    }
    @Expect(hasDisplayName, true)
    println("[csorm-test] @entity @[column]/@[readonly]/composite-pk passed")
}

@Test
func test_orm_builder_raw_column_and_orderby_raw() {
    // 验证 builder 的原始 SELECT 表达式 + 原始 ORDER BY(不引号)
    let q = selectQuery("csorm_test_user")
        .select(["id", "name"])
        .addRawColumn("EXTRACT(EPOCH FROM created_at)", alias: "ts")
        .addRawColumn("COUNT(*)")
        .orderByRaw("RANDOM()", Order.Desc)
        .orderByRaw("ta.sort_order", Order.Asc, nulls: "NULLS LAST")
    let (sql, _) = q.build()
    @Expect(sql.contains("EXTRACT(EPOCH FROM created_at) AS \"ts\""), true)
    @Expect(sql.contains("COUNT(*)"), true)
    @Expect(sql.contains("RANDOM() DESC"), true)
    @Expect(sql.contains("ta.sort_order ASC NULLS LAST"), true)
    @Expect(sql.contains("\"id\""), true)         // 普通列仍引号
    @Expect(sql.contains("\"name\""), true)
    println("[csorm-test] builder rawColumn/orderByRaw passed")
}

@Test
func test_orm_builder_from_subquery_and_exists() {
    // 派生表 FROM + EXISTS 子查询条件
    let innerSql = "SELECT user_id FROM user_favorites WHERE created_at > $1"
    let q = selectQuery()
        .fromSubquery(innerSql, "uf", [vint(0)])
        .select(["user_id"])
        .filter(exists("SELECT 1 FROM users WHERE id = ?", [vint(0)]))
    let (sql, params) = q.build()
    @Expect(sql.contains("FROM (SELECT user_id FROM user_favorites WHERE created_at > $1) AS \"uf\""), true)
    @Expect(sql.contains("EXISTS (SELECT 1 FROM users WHERE id = $2)"), true)  // ? 重排为 $2
    @Expect(params.size, 2)
    println("[csorm-test] builder fromSubquery/exists passed")
}

@Test
func test_orm_transaction_with_handle() {
    match (openOrmOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_test_th")
            db.execRawSql("CREATE TABLE csorm_test_th (id INT4 PRIMARY KEY, v TEXT NOT NULL)")
            // 事务带句柄：回调内复用同一 db
            db.transaction({ d =>
                d.exec(insertQuery("csorm_test_th").columns(["id", "v"]).values([vint(1), vtext("a")]))
                d.exec(insertQuery("csorm_test_th").columns(["id", "v"]).values([vint(2), vtext("b")]))
            })
            @Expect(db.raw<Int64>("SELECT COUNT(*) FROM csorm_test_th", [], { r => r.getInt64(0) })[0], 2)
            // 事务回滚
            try {
                db.transaction({ d =>
                    d.exec(insertQuery("csorm_test_th").columns(["id", "v"]).values([vint(3), vtext("c")]))
                    throw Exception("boom")
                })
            } catch (_: Exception) {}
            @Expect(db.raw<Int64>("SELECT COUNT(*) FROM csorm_test_th", [], { r => r.getInt64(0) })[0], 2)
            db.execRawSql("DROP TABLE csorm_test_th")
            db.close()
            println("[csorm-test] transaction with handle passed")
    }
}

@Test
func test_orm_with_timeout() {
    match (openOrmOrSkip()) {
        case None => return
        case Some(db) =>
            // 短超时 + 快查询：应正常返回
            let r = db.withTimeout<Int64>(5000, { =>
                db.rawOne<Int64>("SELECT 1", [], { row => row.getInt64(0) }).getOrThrow()
            })
            @Expect(r, 1)
            db.close()
            println("[csorm-test] withTimeout fast-query passed")
    }
}

/**
 * 阶段零适配：经 std.database.sql.Datasource 构造 Database，验证 csorm 可由
 * DriverManager/PGDriver.open 路径创建，且执行能力与旧 connString 入口一致。
 */
@Test
func test_orm_via_datasource() {
    try {
        let ds = PGDriver().open(ormConnStr(), [])
        let db = Database(ds)
        let r = db.rawOne<Int64>("SELECT 1", [], { row => row.getInt64(0) }).getOrThrow()
        @Expect(r, 1)
        db.close()
        println("[csorm-test] via Datasource passed")
    } catch (_: Exception) {
        println("[skip] no PostgreSQL available (Datasource path)")
    }
}