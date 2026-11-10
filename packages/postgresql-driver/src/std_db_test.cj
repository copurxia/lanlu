package postgresql_driver

/**
 * std.database.sql 标准库路径测试：经 DriverManager/Datasource/Connection/Statement/
 * QueryResult 走通 CRUD，验证 libpq FFI 驱动已正确接入仓颉标准库 DB 抽象。
 *
 * 无 PG 环境时静默跳过(连不上即 return)。
 */
import std.unittest.*
import std.unittest.testmacro.*
import std.env.getVariable
import std.collection.*
import std.database.sql.*

func connStr2(): String {
    getVariable("DB_STRING") ?? "postgres://copur:e29khrowY77mGk@192.168.0.112:5432/lanludev?sslmode=disable&pool.max=5"
}

// 经 DriverManager 取驱动；无 PG 环境时静默跳过。
func openDs(): ?Datasource {
    try {
        let driverName = "postgresql"
        match (DriverManager.getDriver(driverName)) {
            case Some(driver) => return Some(driver.open(connStr2(), []))
            case None =>
                // 未注册时回退直接 new
                return Some(PGDriver().open(connStr2(), []))
        }
    } catch (_: Exception) {
        println("[skip] no PostgreSQL available (std.database.sql path)")
        return None
    }
}

@Test
func test_std_db_select_basic() {
    match (openDs()) {
        case None => return
        case Some(ds) =>
            try (conn = ds.connect()) {
                try (stmt = conn.prepareStatement("SELECT ?::int8 AS a, ?::text AS b, ?::bool AS c")) {
                    stmt.set<Int64>(1, 1)
                    stmt.set<String>(2, "hello")
                    stmt.set<Bool>(3, true)
                    try (rs = stmt.query()) {
                        @Expect(rs.next(), true)
                        @Expect(rs.get<Int64>(0), 1)
                        @Expect(rs.get<String>(1), "hello")
                        @Expect(rs.get<Bool>(2), true)
                        @Expect(rs.next(), false)
                    }
                }
            }
            ds.close()
            println("[std-db-test] select basic passed")
    }
}

@Test
func test_std_db_crud() {
    match (openDs()) {
        case None => return
        case Some(ds) =>
            try (conn = ds.connect()) {
                // DDL via prepareStatement + update
                try (stmt = conn.prepareStatement("DROP TABLE IF EXISTS std_db_test")) {
                    stmt.update()
                }
                try (stmt = conn.prepareStatement(
                    "CREATE TABLE std_db_test (id SERIAL PRIMARY KEY, name TEXT NOT NULL, n INT8 NOT NULL)")) {
                    stmt.update()
                }
                // INSERT
                try (stmt = conn.prepareStatement(
                    "INSERT INTO std_db_test (name, n) VALUES (?, ?)")) {
                    stmt.set<String>(1, "alice")
                    stmt.set<Int64>(2, 30)
                    let r = stmt.update()
                    @Expect(r.rowCount, 1)
                }
                try (stmt = conn.prepareStatement(
                    "INSERT INTO std_db_test (name, n) VALUES (?, ?)")) {
                    stmt.set<String>(1, "bob")
                    stmt.set<Int64>(2, 7)
                    stmt.update()
                }
                // SELECT
                try (stmt = conn.prepareStatement(
                    "SELECT id, name, n FROM std_db_test ORDER BY id")) {
                    try (rs = stmt.query()) {
                        @Expect(rs.next(), true)
                        @Expect(rs.get<String>(1), "alice")
                        @Expect(rs.get<Int64>(2), 30)
                        @Expect(rs.next(), true)
                        @Expect(rs.get<String>(1), "bob")
                        @Expect(rs.next(), false)
                    }
                }
                // UPDATE
                try (stmt = conn.prepareStatement(
                    "UPDATE std_db_test SET n = ? WHERE name = ?")) {
                    stmt.set<Int64>(1, 99)
                    stmt.set<String>(2, "bob")
                    let r = stmt.update()
                    @Expect(r.rowCount, 1)
                }
                // DELETE
                try (stmt = conn.prepareStatement(
                    "DELETE FROM std_db_test WHERE name = ?")) {
                    stmt.set<String>(1, "alice")
                    let r = stmt.update()
                    @Expect(r.rowCount, 1)
                }
                // Cleanup
                try (stmt = conn.prepareStatement("DROP TABLE std_db_test")) {
                    stmt.update()
                }
            }
            ds.close()
            println("[std-db-test] crud passed")
    }
}

@Test
func test_std_db_transaction() {
    match (openDs()) {
        case None => return
        case Some(ds) =>
            try (conn = ds.connect()) {
                try (stmt = conn.prepareStatement("DROP TABLE IF EXISTS std_db_txn_test")) {
                    stmt.update()
                }
                try (stmt = conn.prepareStatement(
                    "CREATE TABLE std_db_txn_test (id SERIAL PRIMARY KEY, v INT8 NOT NULL)")) {
                    stmt.update()
                }
                // 事务：插入后回滚，应无数据
                let tx = conn.createTransaction()
                tx.begin()
                try (stmt = conn.prepareStatement("INSERT INTO std_db_txn_test (v) VALUES (?)")) {
                    stmt.set<Int64>(1, 42)
                    stmt.update()
                }
                tx.rollback()
                try (stmt = conn.prepareStatement("SELECT count(*) AS c FROM std_db_txn_test")) {
                    try (rs = stmt.query()) {
                        @Expect(rs.next(), true)
                        @Expect(rs.get<Int64>(0), 0)
                    }
                }
                // 事务：插入后提交，应有 1 条
                let tx2 = conn.createTransaction()
                tx2.isoLevel = TransactionIsoLevel.ReadCommitted
                tx2.begin()
                try (stmt = conn.prepareStatement("INSERT INTO std_db_txn_test (v) VALUES (?)")) {
                    stmt.set<Int64>(1, 7)
                    stmt.update()
                }
                tx2.commit()
                try (stmt = conn.prepareStatement("SELECT count(*) AS c FROM std_db_txn_test")) {
                    try (rs = stmt.query()) {
                        @Expect(rs.next(), true)
                        @Expect(rs.get<Int64>(0), 1)
                    }
                }
                // Savepoint
                let tx3 = conn.createTransaction()
                tx3.begin()
                try (stmt = conn.prepareStatement("INSERT INTO std_db_txn_test (v) VALUES (?)")) {
                    stmt.set<Int64>(1, 100)
                    stmt.update()
                }
                tx3.save("sp1")
                try (stmt = conn.prepareStatement("INSERT INTO std_db_txn_test (v) VALUES (?)")) {
                    stmt.set<Int64>(1, 200)
                    stmt.update()
                }
                tx3.rollback("sp1")
                tx3.commit()
                try (stmt = conn.prepareStatement("SELECT count(*) AS c FROM std_db_txn_test")) {
                    try (rs = stmt.query()) {
                        @Expect(rs.next(), true)
                        @Expect(rs.get<Int64>(0), 2)  // 1 (committed) + 1 (before savepoint)
                    }
                }
                try (stmt = conn.prepareStatement("DROP TABLE std_db_txn_test")) {
                    stmt.update()
                }
            }
            ds.close()
            println("[std-db-test] transaction passed")
    }
}

@Test
func test_std_db_null_and_column_infos() {
    match (openDs()) {
        case None => return
        case Some(ds) =>
            try (conn = ds.connect()) {
                try (stmt = conn.prepareStatement("DROP TABLE IF EXISTS std_db_null_test")) {
                    stmt.update()
                }
                try (stmt = conn.prepareStatement(
                    "CREATE TABLE std_db_null_test (id SERIAL PRIMARY KEY, name TEXT, n INT8)")) {
                    stmt.update()
                }
                try (stmt = conn.prepareStatement(
                    "INSERT INTO std_db_null_test (name, n) VALUES (?, ?)")) {
                    stmt.setNull(1)
                    stmt.setNull(2)
                    stmt.update()
                }
                try (stmt = conn.prepareStatement(
                    "SELECT id, name, n FROM std_db_null_test")) {
                    try (rs = stmt.query()) {
                        @Expect(rs.next(), true)
                        // NULL 列经 getOrNull 返回 None
                        match (rs.getOrNull<String>(1)) {
                            case None => @Expect(true, true)
                            case Some(_) => @Expect(true, false)  // 不应到这
                        }
                        match (rs.getOrNull<Int64>(2)) {
                            case None => @Expect(true, true)
                            case Some(_) => @Expect(true, false)
                        }
                        // columnInfos
                        let cis = rs.columnInfos
                        @Expect(cis.size, 3)
                        @Expect(cis[0].name, "id")
                        @Expect(cis[1].name, "name")
                        @Expect(cis[2].name, "n")
                    }
                }
                try (stmt = conn.prepareStatement("DROP TABLE std_db_null_test")) {
                    stmt.update()
                }
            }
            ds.close()
            println("[std-db-test] null + columnInfos passed")
    }
}