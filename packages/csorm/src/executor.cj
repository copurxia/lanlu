package csorm

import std.collection.*
import std.sync.*
import std.time.*

/**
 * csorm 执行入口：持有 DriverConn(后端无关执行接口)，执行 builder/RawQuery。
 * 查询构建器 build() 经 Database.dialect 渲染占位符与引号；DriverConn 负责值转换与原生调用。
 * 错误：DriverConn 实现内部捕获原生错误包成 CsormError 抛出。
 * 事务：透传到底层 DriverConn 的事务方法。
 */
public class Database {
    let conn: DriverConn
    let dialect: Dialect

    /** 经 DriverConn 构造(推荐入口：由 driver 包提供实现)。 */
    public init(conn: DriverConn) {
        this.conn = conn
        this.dialect = conn.dialect()
    }

    /** 逃生舱：直接拿底层 DriverConn(用游标/cancel 等高级能力)。 */
    public func driverConn(): DriverConn { conn }

    /** 当前方言(供 build() 渲染)。 */
    public func getDialect(): Dialect { dialect }

    public func close(): Unit { conn.close() }
    public func poolSize(): Int64 { conn.poolSize() }

    // ===== SELECT =====
    /** 执行 SelectQuery，物化全部行，按 map 映射为 T 数组。 */
    public func all<T>(q: SelectQuery, map: (Row) -> T): Array<T> {
        let (sql, params) = q.build(dialect)
        let rows = conn.queryAll(sql, params)
        Array<T>(rows.size, { i => map(rows[i]) })
    }

    /** 执行 SelectQuery，返回首行映射结果(无结果 None)。 */
    public func one<T>(q: SelectQuery, map: (Row) -> T): ?T {
        let (sql, params) = q.build(dialect)
        match (conn.queryOne(sql, params)) {
            case Some(r) => Some(map(r))
            case None => None
        }
    }

    /** 游标流式读取 SelectQuery，分批回调。 */
    public func stream<T>(q: SelectQuery, chunkSize: Int64, map: (Row) -> T, cb: (Array<T>) -> Unit): Unit {
        let (sql, params) = q.build(dialect)
        conn.streamQuery(sql, params, chunkSize, { rows =>
            cb(Array<T>(rows.size, { i => map(rows[i]) }))
        })
    }

    // ===== INSERT =====
    /**
     * 执行 InsertQuery。若带 RETURNING 单列，则 lastInsertId 取首行该列；
     * returningRows 携带全部 RETURNING 行供映射。
     */
    public func exec(q: InsertQuery): InsertResult {
        let (sql, params) = q.build(dialect)
        if (q.returningCols.size > 0 && dialect.supportReturning()) {
            let rows = conn.queryAll(sql, params)
            // 受影响行数 = RETURNING 行数(写语句带 RETURNING 时 PG 不返回 cmdTuples)
            let aff = Int64(rows.size)
            var lastId: ?Int64 = None
            if (q.returningCols.size == 1 && rows.size > 0) {
                lastId = Some(rows[0].getOrNullInt64(0) ?? 0)
            }
            InsertResult(aff, lastId, rows)
        } else {
            let aff = conn.exec(sql, params)
            InsertResult(aff, None, Array<Row>())
        }
    }

    /** 执行 InsertQuery 并把 RETURNING 行映射为 T 数组(需带 RETURNING 且后端支持)。 */
    public func execReturning<T>(q: InsertQuery, map: (Row) -> T): Array<T> {
        let (sql, params) = q.build(dialect)
        if (q.returningCols.size == 0) {
            throw CsormError("InsertQuery.execReturning: no RETURNING clause")
        }
        if (!dialect.supportReturning()) {
            throw CsormError("InsertQuery.execReturning: backend does not support RETURNING")
        }
        let rows = conn.queryAll(sql, params)
        Array<T>(rows.size, { i => map(rows[i]) })
    }

    // ===== UPDATE =====
    public func exec(q: UpdateQuery): UpdateResult {
        let (sql, params) = q.build(dialect)
        if (q.returningCols.size > 0 && dialect.supportReturning()) {
            let rows = conn.queryAll(sql, params)
            UpdateResult(Int64(rows.size), rows)
        } else {
            let aff = conn.exec(sql, params)
            UpdateResult(aff, Array<Row>())
        }
    }

    public func execReturning<T>(q: UpdateQuery, map: (Row) -> T): Array<T> {
        let (sql, params) = q.build(dialect)
        if (q.returningCols.size == 0) {
            throw CsormError("UpdateQuery.execReturning: no RETURNING clause")
        }
        if (!dialect.supportReturning()) {
            throw CsormError("UpdateQuery.execReturning: backend does not support RETURNING")
        }
        let rows = conn.queryAll(sql, params)
        Array<T>(rows.size, { i => map(rows[i]) })
    }

    // ===== DELETE =====
    public func exec(q: DeleteQuery): DeleteResult {
        let (sql, params) = q.build(dialect)
        if (q.returningCols.size > 0 && dialect.supportReturning()) {
            let rows = conn.queryAll(sql, params)
            DeleteResult(Int64(rows.size), rows)
        } else {
            let aff = conn.exec(sql, params)
            DeleteResult(aff, Array<Row>())
        }
    }

    public func execReturning<T>(q: DeleteQuery, map: (Row) -> T): Array<T> {
        let (sql, params) = q.build(dialect)
        if (q.returningCols.size == 0) {
            throw CsormError("DeleteQuery.execReturning: no RETURNING clause")
        }
        if (!dialect.supportReturning()) {
            throw CsormError("DeleteQuery.execReturning: backend does not support RETURNING")
        }
        let rows = conn.queryAll(sql, params)
        Array<T>(rows.size, { i => map(rows[i]) })
    }

    // ===== RAW =====
    /** 执行原始 SQL 查询，物化全部行并映射。占位符风格由调用方按后端方言管理。 */
    public func raw<T>(sql: String, params: Array<Value>, map: (Row) -> T): Array<T> {
        let rows = conn.queryAll(sql, params)
        Array<T>(rows.size, { i => map(rows[i]) })
    }

    /** 执行原始 SQL 查询，返回首行映射(无结果 None)。 */
    public func rawOne<T>(sql: String, params: Array<Value>, map: (Row) -> T): ?T {
        match (conn.queryOne(sql, params)) {
            case Some(r) => Some(map(r))
            case None => None
        }
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
        conn.exec(sql, params)
    }

    /** 执行原始无参数语句(DDL/迁移)。 */
    public func execRawSql(sql: String): Unit {
        conn.execSql(sql)
    }

    // ===== 事务透传 =====
    public func begin(): Unit { conn.begin() }
    public func commit(): Unit { conn.commit() }
    public func rollback(): Unit { conn.rollback() }
    public func inTransaction(): Bool { conn.inTransaction() }

    /** 原子执行(传播 REQUIRED)：未在事务中则 begin/commit/rollback；已在事务中则直接执行 body。 */
    public func transaction(body: () -> Unit): Unit {
        conn.transaction(body)
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
        if (ms <= 0) { return body() }
        let completed = AtomicBool(false)
        let watchdog = spawn {
            sleep(Duration.millisecond * ms)
            if (!completed.load()) {
                try { let _ = cancel() } catch (_: Exception) {}
            }
        }
        try {
            let r = body()
            completed.store(true)
            return r
        } catch (e: Exception) {
            completed.store(true)
            throw e
        }
    }

    public func save(name: String): Unit { conn.save(name) }
    public func rollback(name: String): Unit { conn.rollback(name) }
    public func release(name: String): Unit { conn.release(name) }

    /** 跨线程取消当前正在执行的查询(超时看门狗用)。 */
    public func cancel(): Bool { conn.cancel() }
}