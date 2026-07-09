package postgresql_driver

import std.collection.*
import std.convert.*
import std.sync.*

/**
 * PostgreSQL 数据源：持有连接池，提供 query/exec/事务/游标/取消。
 *
 * 连接池化：每次操作从池借一条连接、用完归还，并发请求不再串行(libpq 单连接非并发安全)。
 * 事务期间(begin..commit/rollback)用 ThreadLocal 把同一条连接钉在当前线程，
 * 保证 BEGIN/中间语句/COMMIT 走同一连接——天然支持多线程各自独立事务。
 *
 * 文本协议($n 占位符经 PQexecParams 绑定)，杜绝 SQL 注入。
 */
public class PGDatabase {
    let pool: ConnectionPool
    let conninfo: String
    let txn = ThreadLocal<CPointer<Unit>>()
    // 当前正在执行的连接(跨线程可见，供 cancel() 从另一线程取消查询)。
    let activeConnMu = Mutex()
    var activeConn: ?CPointer<Unit> = None
    var lastAffected: Int64 = -1

    public init(connString: String) {
        let (ci, cfg) = parseConnString(connString)
        this.conninfo = ci
        this.pool = ConnectionPool(cfg, { => PGDatabase.openConn(ci) },
            { c => unsafe { PQfinish(c) } })
        // 立即借一条验证连通性
        let c = pool.borrow()
        pool.giveBack(c)
    }

    static func openConn(conninfo: String): CPointer<Unit> {
        let ci = unsafe { LibC.mallocCString(conninfo) }
        let c = unsafe { PQconnectdb(ci) }
        unsafe { LibC.free(ci) }
        if (unsafe { PQstatus(c) } != PG_CONNECTION_OK) {
            let msg = unsafe { PQerrorMessage(c) }.toString()
            unsafe { PQfinish(c) }
            throw PGError("postgres connect failed: " + msg)
        }
        return c
    }

    public func close(): Unit {
        pool.closeAll()
    }

    public func poolSize(): Int64 { pool.size() }

    // ===== 活动连接跟踪(供跨线程 cancel)=====
    func setActiveConn(c: CPointer<Unit>): Unit {
        synchronized(activeConnMu) { activeConn = Some(c) }
    }

    func clearActiveConn(): Unit {
        synchronized(activeConnMu) { activeConn = None }
    }

    // ===== 核心：PQexecParams 执行 + 状态校验 =====
    // 返回 PGResult(调用方负责 close)。失败抛 PGError(携带 SQLSTATE)。
    static func run(conn: CPointer<Unit>, sql: String, params: Array<PGValue>): PGResult {
        let n = params.size
        let csql = unsafe { LibC.mallocCString(sql) }
        // 构造参数值指针数组：PGNull → null 指针(SQL NULL)，其余 → toText 的 CString
        let cstrs = Array<CString>(n, { i =>
            match (params[i]) {
                case PGNull => CString(CPointer())
                case _ => unsafe { LibC.mallocCString(pgValueToText(params[i])) }
            }
        })
        let rawRes = if (n == 0) {
            unsafe {
                PQexecParams(conn, csql, 0, CPointer<UInt32>(), CPointer<CString>(),
                    CPointer<Int32>(), CPointer<Int32>(), 0)
            }
        } else {
            let handle = unsafe { acquireArrayRawData(cstrs) }
            let r = unsafe {
                PQexecParams(conn, csql, Int32(n), CPointer<UInt32>(), handle.pointer,
                    CPointer<Int32>(), CPointer<Int32>(), 0)
            }
            unsafe { releaseArrayRawData(handle) }
            r
        }
        unsafe { LibC.free(csql) }
        for (cs in cstrs) {
            unsafe { LibC.free(cs) }
        }
        let res = PGResult(rawRes)
        if (!res.isCommandOk() && !res.isTuplesOk()) {
            let err = res.buildError(sql)
            res.close()
            throw err
        }
        return res
    }

    // 原始 SQL 执行(无参数，DDL / 迁移脚本)。用 PQexec。
    static func execRaw(conn: CPointer<Unit>, sql: String): Unit {
        let csql = unsafe { LibC.mallocCString(sql) }
        let rawRes = unsafe { PQexec(conn, csql) }
        unsafe { LibC.free(csql) }
        let res = PGResult(rawRes)
        if (!res.isCommandOk() && !res.isTuplesOk()) {
            let err = res.buildError(sql)
            res.close()
            throw err
        }
        res.close()
    }

    // 在指定连接上物化结果集为 PgRowData 数组。
    static func materialize(res: PGResult): Array<PgRowData> {
        let nrows = res.rowCount()
        let ncols = res.fieldCount()
        let names = Array<String>(ncols, { j => res.fieldName(j) })
        let oids = Array<Int32>(ncols, { j => res.fieldType(j) })
        let rows = ArrayList<PgRowData>()
        for (i in 0..nrows) {
            let vals = Array<String>(ncols, { j => if (res.isNull(i, j)) { "" } else { res.getValue(i, j) } })
            let nulls = Array<Bool>(ncols, { j => res.isNull(i, j) })
            rows.add(PgRowData(names, oids, vals, nulls))
        }
        return rows.toArray()
    }

    // ===== 公共 API =====

    /** 执行查询，物化全部行为 PgRowData 数组。 */
    public func query(sql: String, params: Array<PGValue>): Array<PgRowData> {
        match (txn.get()) {
            case Some(c) =>
                setActiveConn(c)
                try {
                    let res = PGDatabase.run(c, sql, params)
                    let rows = PGDatabase.materialize(res)
                    res.close()
                    return rows
                } finally { clearActiveConn() }
            case None =>
                let c = pool.borrow()
                try {
                    setActiveConn(c)
                    let res = PGDatabase.run(c, sql, params)
                    let rows = PGDatabase.materialize(res)
                    res.close()
                    return rows
                } finally {
                    clearActiveConn()
                    pool.giveBack(c)
                }
        }
    }

    /** 执行查询，返回首行(无结果返回 None)。 */
    public func queryOne(sql: String, params: Array<PGValue>): ?PgRowData {
        let rows = query(sql, params)
        if (rows.size == 0) {
            return None
        }
        Some(rows[0])
    }

    /** 执行写语句(INSERT/UPDATE/DELETE)，返回受影响行数。 */
    public func exec(sql: String, params: Array<PGValue>): Int64 {
        let aff = match (txn.get()) {
            case Some(c) =>
                setActiveConn(c)
                try {
                    let res = PGDatabase.run(c, sql, params)
                    let a = res.affectedRows()
                    res.close()
                    a
                } finally { clearActiveConn() }
            case None =>
                let c = pool.borrow()
                try {
                    setActiveConn(c)
                    let res = PGDatabase.run(c, sql, params)
                    let a = res.affectedRows()
                    res.close()
                    a
                } finally {
                    clearActiveConn()
                    pool.giveBack(c)
                }
        }
        lastAffected = aff
        return aff
    }

    /** 执行原始 SQL(无参数，DDL/迁移脚本)。 */
    public func execSql(sql: String): Unit {
        match (txn.get()) {
            case Some(c) =>
                setActiveConn(c)
                try { PGDatabase.execRaw(c, sql) } finally { clearActiveConn() }
            case None =>
                let c = pool.borrow()
                try {
                    setActiveConn(c)
                    PGDatabase.execRaw(c, sql)
                } finally {
                    clearActiveConn()
                    pool.giveBack(c)
                }
        }
    }

    /** 上一条 exec 影响的行数(非 DML 返回 -1)。 */
    public func affectedRows(): Int64 { lastAffected }

    // ===== 事务 =====

    public func begin(): Unit {
        let c = pool.borrow()
        try {
            PGDatabase.execRaw(c, "BEGIN")
            txn.set(Some(c))
        } catch (e: Exception) {
            pool.giveBack(c)
            throw e
        }
    }

    public func commit(): Unit {
        endTxn("COMMIT")
    }

    public func rollback(): Unit {
        endTxn("ROLLBACK")
    }

    func endTxn(verb: String): Unit {
        match (txn.get()) {
            case Some(c) =>
                try {
                    PGDatabase.execRaw(c, verb)
                } finally {
                    txn.set(None)
                    pool.giveBack(c)
                }
            case None => ()
        }
    }

    /** 当前线程是否处于活动事务中。 */
    public func inTransaction(): Bool {
        match (txn.get()) {
            case Some(_) => true
            case None => false
        }
    }

    /** SAVEPOINT。 */
    public func save(name: String): Unit { execInTxn("SAVEPOINT " + name) }

    public func rollback(name: String): Unit { execInTxn("ROLLBACK TO SAVEPOINT " + name) }

    public func release(name: String): Unit { execInTxn("RELEASE SAVEPOINT " + name) }

    func execInTxn(sql: String): Unit {
        match (txn.get()) {
            case Some(c) => PGDatabase.execRaw(c, sql)
            case None => throw PGError("not in transaction: " + sql)
        }
    }

    /**
     * 原子执行(传播 REQUIRED)：未在事务中则 begin/commit/rollback；已在事务中则直接执行 body。
     */
    public func transaction(body: () -> Unit): Unit {
        if (inTransaction()) {
            body()
            return
        }
        begin()
        try {
            body()
            commit()
        } catch (e: Exception) {
            rollback()
            throw e
        }
    }

    // ===== 查询取消 =====
    /**
     * 取消当前正在执行的查询(从另一线程调用，如超时看门狗)。
     * 无活动查询时静默返回 false。PQcancel 失败返回 false(尽力而为)。
     */
    public func cancel(): Bool {
        let connOpt = synchronized(activeConnMu) { activeConn }
        match (connOpt) {
            case Some(c) =>
                let pgcancel = unsafe { PQgetCancel(c) }
                if (pgcancel.isNull()) {
                    return false
                }
                var errbuf = Array<UInt8>(256, { _ => 0u8 })
                let handle = unsafe { acquireArrayRawData(errbuf) }
                let r = unsafe { PQcancel(pgcancel, handle.pointer, 256) }
                unsafe { releaseArrayRawData(handle) }
                unsafe { PQfreeCancel(pgcancel) }
                return r != 0
            case None => return false
        }
    }

    // ===== 游标流式读取 =====
    /**
     * 使用 PG 原生游标(DECLARE/FETCH/CLOSE)流式分批读取。
     * - 事务内：用钉住的连接，游标名带时间戳后缀防嵌套冲突。
     * - 事务外：借新连接，自建事务包裹游标生命周期，异常时 ROLLBACK。
     */
    public func streamQuery(sql: String, params: Array<PGValue>, chunkSize: Int64,
        cb: (Array<PgRowData>) -> Unit): Unit {
        match (txn.get()) {
            case Some(c) =>
                let cursorName = "pgc_stream_" + nowMillis().toString()
                let declRes = PGDatabase.run(c, "DECLARE " + cursorName + " CURSOR FOR " + sql, params)
                declRes.close()
                let fetchSql = "FETCH " + chunkSize.toString() + " FROM " + cursorName
                while (true) {
                    let res = PGDatabase.run(c, fetchSql, [])
                    let rows = PGDatabase.materialize(res)
                    res.close()
                    if (rows.size == 0) {
                        break
                    }
                    cb(rows)
                    if (rows.size < chunkSize) {
                        break
                    }
                }
                PGDatabase.execRaw(c, "CLOSE " + cursorName)
            case None =>
                let conn = pool.borrow()
                try {
                    PGDatabase.execRaw(conn, "BEGIN")
                    let declRes = PGDatabase.run(conn, "DECLARE pgc_stream_cur CURSOR FOR " + sql, params)
                    declRes.close()
                    let fetchSql = "FETCH " + chunkSize.toString() + " FROM pgc_stream_cur"
                    while (true) {
                        let res = PGDatabase.run(conn, fetchSql, [])
                        let rows = PGDatabase.materialize(res)
                        res.close()
                        if (rows.size == 0) {
                            break
                        }
                        cb(rows)
                        if (rows.size < chunkSize) {
                            break
                        }
                    }
                    PGDatabase.execRaw(conn, "CLOSE pgc_stream_cur")
                    PGDatabase.execRaw(conn, "COMMIT")
                    pool.giveBack(conn)
                } catch (e: Exception) {
                    try { PGDatabase.execRaw(conn, "ROLLBACK") } catch (_: Exception) {}
                    pool.giveBack(conn)
                    throw e
                }
        }
    }
}
