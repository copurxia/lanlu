package csorm

import std.collection.*
import std.sync.*
import std.time.*
import std.database.sql.*
import postgresql_driver.*

/**
 * csorm 执行入口：包装 PGDatabase，执行 builder/RawQuery，统一把 Value 转 PGValue 后下发。
 * 错误：捕获 PGError 包成 CsormError 抛出(保留 SQLSTATE)。
 * 事务：直接透传到底层 driver 的 ThreadLocal 钉连接事务，多线程各自独立事务。
 *
 * 阶段零适配：新增 Datasource 入口，让 csorm 可经 std.database.sql 抽象构造；
 * 内部仍复用 PGDatabase 的私有 API(查询/事务/游标)，保证现有 DAO 与测试不破坏。
 * 后续阶段逐步把执行路径迁移到 Datasource/Connection/Statement/QueryResult。
 */
public class Database {
    let pg: PGDatabase

    public init(connString: String) {
        pg = PGDatabase(connString)
    }

    /** 适配器：包装已存在的 PGDatabase(跨 DAO 句柄传递 / 事务内复用)。 */
    public init(pg: PGDatabase) {
        this.pg = pg
    }

    /**
     * 经 std.database.sql.Datasource 构造：从 PGDatasource 取底层 PGDatabase 复用。
     * 用法：`Database(PGDriver().open(connString, []))` 或经 DriverManager 取驱动后 open。
     * Datasource 仍持有池生命周期；close() 会一并关闭。
     */
    public init(ds: Datasource) {
        match (ds as PGDatasource) {
            case Some(pds) => this.pg = pds.pgDatabase()
            case None =>
                throw CsormError("Database(Datasource): only PGDatasource supported currently")
        }
    }

    /** 逃生舱：直接拿底层 PGDatabase(用游标/cancel 等高级能力)。 */
    public func pgdb(): PGDatabase { pg }

    public func close(): Unit { pg.close() }
    public func poolSize(): Int64 { pg.poolSize() }

    // ===== 内部工具 =====
    func toPgParams(vals: Array<Value>): Array<PGValue> {
        Array<PGValue>(vals.size, { i => valueToPG(vals[i]) })
    }

    func wrapRun<T>(ctx: String, body: () -> T): T {
        try {
            body()
        } catch (e: PGError) {
            throw wrapPgError(e, ctx)
        }
    }

    // ===== SELECT =====
    /** 执行 SelectQuery，物化全部行，按 map 映射为 T 数组。 */
    public func all<T>(q: SelectQuery, map: (Row) -> T): Array<T> {
        let (sql, params) = q.build()
        wrapRun("select all", { =>
            let rows = pg.query(sql, toPgParams(params))
            Array<T>(rows.size, { i => map(rows[i]) })
        })
    }

    /** 执行 SelectQuery，返回首行映射结果(无结果 None)。 */
    public func one<T>(q: SelectQuery, map: (Row) -> T): ?T {
        let (sql, params) = q.build()
        wrapRun("select one", { =>
            match (pg.queryOne(sql, toPgParams(params))) {
                case Some(r) => Some(map(r))
                case None => None
            }
        })
    }

    /** 游标流式读取 SelectQuery，分批回调。 */
    public func stream<T>(q: SelectQuery, chunkSize: Int64, map: (Row) -> T, cb: (Array<T>) -> Unit): Unit {
        let (sql, params) = q.build()
        wrapRun("stream", { =>
            pg.streamQuery(sql, toPgParams(params), chunkSize, { rows =>
                cb(Array<T>(rows.size, { i => map(rows[i]) }))
            })
        })
    }

    // ===== INSERT =====
    /**
     * 执行 InsertQuery。若带 RETURNING 单列，则 lastInsertId 取首行该列；
     * returningRows 携带全部 RETURNING 行供映射。
     */
    public func exec(q: InsertQuery): InsertResult {
        let (sql, params) = q.build()
        wrapRun("insert", { =>
            if (q.returningCols.size > 0) {
                let rows = pg.query(sql, toPgParams(params))
                // 受影响行数 = RETURNING 行数(写语句带 RETURNING 时 PG 不返回 cmdTuples)
                let aff = Int64(rows.size)
                var lastId: ?Int64 = None
                if (q.returningCols.size == 1 && rows.size > 0) {
                    lastId = Some(rows[0].getOrNullInt64(0) ?? 0)
                }
                InsertResult(aff, lastId, rows)
            } else {
                let aff = pg.exec(sql, toPgParams(params))
                InsertResult(aff, None, Array<Row>())
            }
        })
    }

    /** 执行 InsertQuery 并把 RETURNING 行映射为 T 数组(需带 RETURNING)。 */
    public func execReturning<T>(q: InsertQuery, map: (Row) -> T): Array<T> {
        let (sql, params) = q.build()
        wrapRun("insert returning", { =>
            if (q.returningCols.size == 0) {
                throw CsormError("InsertQuery.execReturning: no RETURNING clause")
            }
            let rows = pg.query(sql, toPgParams(params))
            Array<T>(rows.size, { i => map(rows[i]) })
        })
    }

    // ===== UPDATE =====
    public func exec(q: UpdateQuery): UpdateResult {
        let (sql, params) = q.build()
        wrapRun("update", { =>
            if (q.returningCols.size > 0) {
                let rows = pg.query(sql, toPgParams(params))
                UpdateResult(Int64(rows.size), rows)
            } else {
                let aff = pg.exec(sql, toPgParams(params))
                UpdateResult(aff, Array<Row>())
            }
        })
    }

    public func execReturning<T>(q: UpdateQuery, map: (Row) -> T): Array<T> {
        let (sql, params) = q.build()
        wrapRun("update returning", { =>
            if (q.returningCols.size == 0) {
                throw CsormError("UpdateQuery.execReturning: no RETURNING clause")
            }
            let rows = pg.query(sql, toPgParams(params))
            Array<T>(rows.size, { i => map(rows[i]) })
        })
    }

    // ===== DELETE =====
    public func exec(q: DeleteQuery): DeleteResult {
        let (sql, params) = q.build()
        wrapRun("delete", { =>
            if (q.returningCols.size > 0) {
                let rows = pg.query(sql, toPgParams(params))
                DeleteResult(Int64(rows.size), rows)
            } else {
                let aff = pg.exec(sql, toPgParams(params))
                DeleteResult(aff, Array<Row>())
            }
        })
    }

    public func execReturning<T>(q: DeleteQuery, map: (Row) -> T): Array<T> {
        let (sql, params) = q.build()
        wrapRun("delete returning", { =>
            if (q.returningCols.size == 0) {
                throw CsormError("DeleteQuery.execReturning: no RETURNING clause")
            }
            let rows = pg.query(sql, toPgParams(params))
            Array<T>(rows.size, { i => map(rows[i]) })
        })
    }

    // ===== RAW =====
    /** 执行原始 SQL 查询，物化全部行并映射。占位符 $1..$n 由调用方管理。 */
    public func raw<T>(sql: String, params: Array<Value>, map: (Row) -> T): Array<T> {
        wrapRun("raw all", { =>
            let rows = pg.query(sql, toPgParams(params))
            Array<T>(rows.size, { i => map(rows[i]) })
        })
    }

    /** 执行原始 SQL 查询，返回首行映射(无结果 None)。 */
    public func rawOne<T>(sql: String, params: Array<Value>, map: (Row) -> T): ?T {
        wrapRun("raw one", { =>
            match (pg.queryOne(sql, toPgParams(params))) {
                case Some(r) => Some(map(r))
                case None => None
            }
        })
    }

    /** 执行 RawQuery，物化全部行并映射。 */
    public func raw<T>(q: RawQuery, map: (Row) -> T): Array<T> {
        let (sql, params) = q.build()
        raw<T>(sql, params, map)
    }

    public func rawOne<T>(q: RawQuery, map: (Row) -> T): ?T {
        let (sql, params) = q.build()
        rawOne<T>(sql, params, map)
    }

    /** 执行原始写语句(无 RETURNING)，返回受影响行数。 */
    public func execRaw(sql: String, params: Array<Value>): Int64 {
        wrapRun("exec raw", { => pg.exec(sql, toPgParams(params)) })
    }

    /** 执行原始无参数语句(DDL/迁移)。 */
    public func execRawSql(sql: String): Unit {
        wrapRun("exec raw sql", { => pg.execSql(sql) })
    }

    // ===== 事务透传 =====
    public func begin(): Unit { wrapRun("begin", { => pg.begin() }) }
    public func commit(): Unit { wrapRun("commit", { => pg.commit() }) }
    public func rollback(): Unit { wrapRun("rollback", { => pg.rollback() }) }
    public func inTransaction(): Bool { pg.inTransaction() }

    /** 原子执行(传播 REQUIRED)：未在事务中则 begin/commit/rollback；已在事务中则直接执行 body。 */
    public func transaction(body: () -> Unit): Unit {
        wrapRun("transaction", { => pg.transaction(body) })
    }

    /** 事务带句柄：回调收到当前 Database(事务内复用同一底层连接)。返回 body 的结果。 */
    public func transaction<T>(body: (Database) -> T): T {
        // Cangjie 闭包不能捕获 var，用 1 元素 Array 做可变单元格
        let cell = Array<?T>(1, { _ => None })
        transaction({ =>
            cell[0] = Some(body(this))
        })
        match (cell[0]) {
            case Some(v) => v
            case None => throw CsormError("transaction: body did not produce result")
        }
    }

    /**
     * 超时执行：spawn 看门狗线程，ms 到期且未完成时调 cancel() 取消当前查询。
     * ms <= 0 时不启用看门狗。完成时置 completed 标志让看门狗静默退出。
     */
    public func withTimeout<T>(ms: Int64, body: () -> T): T {
        if (ms <= 0) { return wrapRun("withTimeout", { => body() }) }
        let completed = AtomicBool(false)
        let watchdog = spawn {
            sleep(Duration.millisecond * ms)
            if (!completed.load()) {
                try { let _ = cancel() } catch (_: Exception) {}
            }
        }
        try {
            let r = wrapRun("withTimeout", { => body() })
            completed.store(true)
            return r
        } catch (e: Exception) {
            completed.store(true)
            throw e
        }
    }

    public func save(name: String): Unit { wrapRun("savepoint", { => pg.save(name) }) }
    public func rollback(name: String): Unit { wrapRun("rollback savepoint", { => pg.rollback(name) }) }
    public func release(name: String): Unit { wrapRun("release savepoint", { => pg.release(name) }) }

    /** 跨线程取消当前正在执行的查询(超时看门狗用)。 */
    public func cancel(): Bool { pg.cancel() }
}