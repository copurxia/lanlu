package csorm

/**
 * 阶段七测试：metric callback、MockDatabase、ConnectOptions。
 */
import std.unittest.*
import std.unittest.testmacro.*
import std.env.getVariable
import std.collection.*
import std.time.*
import postgresql_driver.*

@Test
func test_metric_callback() {
    // 记录 metric 调用(用可变单元格避免闭包捕获 var)
    let records = ArrayList<MetricInfo>()
    DatabaseMetric.setMetricCallback({ info =>
        records.add(info)
    })

    // 直接测试 record(不经真实 DB)
    DatabaseMetric.record("SELECT 1", [], Duration.microsecond * 100, false, "test-ctx")
    DatabaseMetric.record("SELECT bad", [], Duration.microsecond * 200, true, "test-fail")

    @Expect(records.size, 2)
    @Expect(records[0].sql, "SELECT 1")
    @Expect(records[0].failed, false)
    @Expect(records[0].context, "test-ctx")
    @Expect(records[0].elapsed.toMicroseconds(), 100)
    @Expect(records[1].sql, "SELECT bad")
    @Expect(records[1].failed, true)
    @Expect(records[1].context, "test-fail")

    DatabaseMetric.clearMetricCallback()
    // 清除后 record 不再回调
    DatabaseMetric.record("SELECT 2", [], Duration.microsecond * 50, false, "after-clear")
    @Expect(records.size, 2)  // 仍为 2

    println("[obs-test] metric callback passed")
}

@Test
func test_mock_database() {
    let mock = MockDatabase()

    // 预设查询响应：SQL 包含 "FROM users" 时返回 2 行(用便捷 Row 构造)
    let row1 = Row(["id", "name"], ["1", "alice"])
    let row2 = Row(["id", "name"], ["2", "bob"])
    mock.expectQuery("FROM users", [row1, row2])
    mock.expectExec("INSERT INTO users", 1)

    // 查询：SQL 包含 matchStr 返回预设行
    let rows = mock.query("SELECT id, name FROM users WHERE active = true", [])
    @Expect(rows.size, 2)
    @Expect(rows[0].getText("name"), "alice")
    @Expect(rows[1].getText("name"), "bob")

    // 写语句：返回预设 affected
    let aff = mock.exec("INSERT INTO users (name) VALUES ($1)", [PGText("carol")])
    @Expect(aff, 1)

    // 未匹配的查询返回空数组
    let empty = mock.query("SELECT * FROM unknown_table", [])
    @Expect(empty.size, 0)

    // 调用记录
    @Expect(mock.callCount(), 3)
    let calls = mock.calls()
    @Expect(calls[0].contains("FROM users"), true)
    @Expect(calls[1].contains("INSERT"), true)

    // queryOne
    match (mock.queryOne("SELECT id, name FROM users", [])) {
        case Some(r) => @Expect(r.getText("name"), "alice")
        case None => @Expect(true, false)
    }

    mock.reset()
    @Expect(mock.callCount(), 0)
    println("[obs-test] MockDatabase passed")
}

@Test
func test_connect_options() {
    // 基本构造
    var opts = ConnectOptions("postgres://user:pass@localhost:5432/mydb")
    @Expect(opts.poolSize, 10)  // 默认
    opts.poolSize = 20
    opts.statementTimeoutMs = 5000
    opts.sslMode = "require"

    let connStr = opts.toConnectionString()
    @Expect(connStr.contains("pool.max=20"), true)
    @Expect(connStr.contains("statement_timeout=5000"), true)
    @Expect(connStr.contains("sslmode=require"), true)

    // parse：从含 pool.max 的连接串提取
    let parsed = ConnectOptions.parse("postgres://u:p@h:5432/db?pool.max=30&pool.min=5")
    @Expect(parsed.poolSize, 30)

    println("[obs-test] ConnectOptions passed")
}

@Test
func test_query_log() {
    QueryLog.enable()
    // log 应输出到 stdout(此处仅验证不抛异常)
    QueryLog.log("SELECT 1", Duration.microsecond * 100, false)
    QueryLog.log("SELECT bad", Duration.microsecond * 200, true)
    QueryLog.disable()
    println("[obs-test] QueryLog passed")
}