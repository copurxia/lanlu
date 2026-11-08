package csorm

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.*
import std.fs.*
import std.sync.*
import std.time.*

// ===== task-3 验收单测（纯单测，无 DB）=====

// 1) SqlCounter：builder 路径（all/one/exec/execReturning）计入 DatabaseMetric
@Test
func test_builder_metric_recorded() {
    // 仓颉闭包不能捕获 var：用单元素数组做可变单元格
    let cell = Array<(Int64, String)>(1, { _ => (0, "") })
    let cellMu = Mutex()
    DatabaseMetric.setMetricCallback({ info =>
        synchronized(cellMu) {
            let (c0, _) = cell[0]
            cell[0] = (c0 + 1, info.context)
        }
    })
    let mock = MockDatabase()
    let db = Database(mock)
    // all
    let _ = db.all<Row>(selectQuery("t"), { r => r })
    @Assert(cell[0][0] >= 1, true)
    @Assert(cell[0][1] == "select all", true)
    // one
    let _ = db.one<Row>(selectQuery("t"), { r => r })
    @Assert(cell[0][0] >= 2, true)
    @Assert(cell[0][1] == "select one", true)
    // insert（无 returning → exec 路径）
    let _ = db.exec(insertQuery("t").columns(["a"]).values([vint(1)]))
    @Assert(cell[0][0] >= 3, true)
    @Assert(cell[0][1] == "insert", true)
    // update / delete
    let _ = db.exec(updateQuery("t").set("a", vint(2)))
    @Assert(cell[0][1] == "update", true)
    let _ = db.exec(deleteQuery("t").filter(col("a").eq(1)))
    @Assert(cell[0][1] == "delete", true)
    DatabaseMetric.clearMetricCallback()
}

// 2) Migrator advisory lock：mock 断言 SQL 序列（xact lock 在事务体内、迁移 SQL 之前）
@Test
func test_migrator_advisory_lock_sequence() {
    let mock = MockDatabase()
    let db = Database(mock)
    // 元表查询/写入都走 mock 默认响应
    mock.expectExec("INSERT INTO schema_migrations", 1)
    mock.expectExec("DELETE FROM schema_migrations", 1)
    // raw 查询返回空（appliedVersions 空 → 全部迁移待执行）
    let mig = TestMigration("V001", db)
    let m = Migrator(db)
    let _ = m.up([mig])
    let calls = mock.calls()
    // 断言：advisory xact lock SQL 出现，且在 V001 迁移 SQL 之前
    var lockIdx = -1
    var migIdx = -1
    for (i in 0..calls.size) {
        if (indexOfSub(calls[i], "pg_advisory_xact_lock") >= 0 && lockIdx < 0) { lockIdx = i }
        if (indexOfSub(calls[i], "CREATE TABLE v001") >= 0 && migIdx < 0) { migIdx = i }
    }
    @Assert(lockIdx >= 0, true)
    @Assert(migIdx >= 0, true)
    @Assert(lockIdx < migIdx, true)
}

// 3) begin(isolation!)：mock 记录 BEGIN 子句
@Test
func test_begin_isolation_clause() {
    let mock = MockDatabase()
    let db = Database(mock)
    db.begin(level: IsolationLevel.Serializable)
    db.commit()
    let calls = mock.calls()
    var found = false
    for (c in calls) {
        if (indexOfSub(c, "BEGIN ISOLATION LEVEL SERIALIZABLE") >= 0) { found = true }
    }
    @Assert(found, true)
    // Default 保持裸 BEGIN
    db.begin()
    db.commit()
    var bare = false
    for (c in mock.calls()) {
        if (c == "BEGIN") { bare = true }
    }
    @Assert(bare, true)
}

// 4) poolStats：Mock 路径默认值
@Test
func test_pool_stats_default() {
    let mock = MockDatabase()
    let db = Database(mock)
    let (open, idle, waiting, timeouts) = db.poolStats()
    @Assert(open, 1)
    @Assert(idle, 0)
    @Assert(waiting, 0)
    @Assert(timeouts, 0)
}

// ---------- helper ----------
// 简单测试迁移：CREATE TABLE v001
class TestMigration <: CsormMigration {
    let v: String
    let d: Database
    init(v_: String, d_: Database) { v = v_; d = d_ }
    public func version(): String { v }
    public func description(): String { "test migration " + v }
    public func up(mgr: SchemaManager): Unit {
        mgr.execSql("CREATE TABLE v001 (id INT)")
    }
    public func down(mgr: SchemaManager): Unit {
        mgr.execSql("DROP TABLE v001")
    }
}

