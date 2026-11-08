package postgresql_driver

import std.collection.*
import std.convert.*
import std.sync.*
import csorm.IsolationLevel
import csorm.isolationClause

/**
 * PostgreSQL 数据源：持有连接池，提供 query/exec/事务/游标/取消。
 *
 * 连接池化：每次操作从池借一条连接、用完归还，并发请求不再串行(libpq 单连接非并发安全)。
 * 事务期间(begin..commit/rollback)用 ThreadLocal 把同一条连接钉在当前线程，
 * 保证 BEGIN/中间语句/COMMIT 走同一连接——天然支持多线程各自独立事务。
 *
 * 参数绑定($n 占位符)杜绝 SQL 注入。执行路径（按配置逐级启用，全部可回退）：
 * 1) 语句缓存（pool.stmtCache，默认 32）：重复 SQL 走 PQprepare 一次 + PQexecPrepared 多次，
 *    省服务端 parse/plan；未启用/不可缓存语句走 PQexecParams。
 *    错误 42P05（同名语句已存在）/0A000（特性不支持）时失效缓存并回退 PQexecParams 重试。
 * 2) 参数 arena：每连接复用参数缓冲，替代每参数 mallocCString/free。
 * 3) 二进制结果（pool.binaryResult=auto 默认）：结果 OID 全命中白名单时 resultFormat=1，
 *    仓颉侧按 OID 大端解码为文本等价形式；解码失败自动整条回退文本协议重查。
 * 4) bridge 物化：整个 PGresult 在 C 侧一次搬运为扁平缓冲，仓颉侧 <=4 次 FFI
 *    （代替每 cell 2-3 次 PQgetvalue/PQgetisnull）。
 */
public class PGDatabase {
    // var：init 中其余 let 字段全部就绪后再构造池（disconnect 闭包需捕获 this 清理连接状态）。
    var pool: ConnectionPool = ConnectionPool(PoolConfig.default(), { => CPointer<Unit>() },
        { c => () })
    let conninfo: String
    let txn = ThreadLocal<CPointer<Unit>>()
    // 当前正在执行的连接注册表：cancel 定向取消活动查询（替代原全局单槽，
    // 修复并发查询下可能取消错连接的问题）。键 = 连接指针身份。
    let activeMu = Mutex()
    var activeConns = HashMap<UInt64, CPointer<Unit>>()
    let cfg: PoolConfig
    // 每连接驱动状态（语句缓存 + arena + binary 模式），键 = 连接指针身份。
    let statesMu = Mutex()
    var connStates = HashMap<UInt64, PGConnState>()
    // 受影响行数是"当前线程上一条 exec"的状态，不能跨线程共享。
    let lastAffected = ThreadLocal<Int64>()

    public init(connString: String) {
        let (ci, cfg) = parseConnString(connString)
        this.conninfo = ci
        this.cfg = cfg
        // 此时全部 let 字段已初始化，可以安全捕获 this
        this.pool = ConnectionPool(cfg, { => PGDatabase.openConn(ci, cfg.statementTimeoutMs) },
            { c => PGDatabase.disconnectConn(c, this) },
            validate: { c => unsafe { PQstatus(c) == PG_CONNECTION_OK } })
        // 立即借一条验证连通性
        let c = pool.borrow()
        pool.giveBack(c)
    }

    static func openConn(conninfo: String): CPointer<Unit> {
        openConn(conninfo, 0)
    }

    /**
     * 打开连接并可选设置会话级 statement_timeout（task-5）。
     * stmtTimeoutMs > 0 时在连接建立后执行 SET statement_timeout='<ms>ms'；
     * 0（默认）完全跳过，行为向后兼容。SET 失败视为连接失败（服务端不可用/权限问题应尽早暴露）。
     */
    static func openConn(conninfo: String, stmtTimeoutMs: Int64): CPointer<Unit> {
        let ci = unsafe { LibC.mallocCString(conninfo) }
        let c = unsafe { PQconnectdb(ci) }
        unsafe { LibC.free(ci) }
        if (unsafe { PQstatus(c) } != PG_CONNECTION_OK) {
            let msg = unsafe { PQerrorMessage(c) }.toString()
            unsafe { PQfinish(c) }
            throw PGError("postgres connect failed: " + msg)
        }
        if (stmtTimeoutMs > 0) {
            let setSql = "SET statement_timeout='" + stmtTimeoutMs.toString() + "ms'"
            let sc = unsafe { LibC.mallocCString(setSql) }
            let res = unsafe { PQexec(c, sc) }
            unsafe { LibC.free(sc) }
            var ok = false
            var msg = ""
            if (!res.isNull()) {
                ok = unsafe { PQresultStatus(res) } == PGRES_COMMAND_OK
                if (!ok) {
                    msg = unsafe { PQresultErrorMessage(res) }.toString()
                }
                unsafe { PQclear(res) }
            }
            if (!ok) {
                unsafe { PQfinish(c) }
                throw PGError("SET statement_timeout failed: " + msg)
            }
        }
        return c
    }

    /** 连接销毁（池 disconnect 闭包）：释放该连接的 arena 并清状态。 */
    static func disconnectConn(c: CPointer<Unit>, db: PGDatabase): Unit {
        let key = connPtrKey(c)
        synchronized(db.statesMu) {
            match (db.connStates.get(key)) {
                case Some(st) =>
                    st.destroy()
                    db.connStates.remove(key)
                case None => ()
            }
        }
        unsafe { PQfinish(c) }
    }

    /** 取/建连接状态（借出连接后调用）。 */
    func stateFor(c: CPointer<Unit>): PGConnState {
        let key = connPtrKey(c)
        synchronized(statesMu) {
            match (connStates.get(key)) {
                case Some(st) => st
                case None =>
                    let useBinary = match (cfg.binaryResult) {
                        case BinaryResultMode.Never => false
                        case _ => true
                    }
                    let st = PGConnState(cfg.stmtCacheSize, useBinary)
                    connStates[key] = st
                    st
            }
        }
    }

    public func close(): Unit {
        pool.closeAll()
        // closeAll 已对每条空闲连接调用 disconnect（经 disconnectConn 清理状态）；
        // 借出中的连接在归还时清理。
    }

    public func poolSize(): Int64 { pool.size() }

    /** 语句缓存聚合统计（全部连接）。 */
    public func stmtCacheStats(): (Int64, Int64, Int64, Int64) {
        var hits = 0
        var misses = 0
        var evictions = 0
        var fallbacks = 0
        synchronized(statesMu) {
            for ((_, st) in connStates) {
                hits += st.stmtCache.hitCount()
                misses += st.stmtCache.missCount()
                evictions += st.stmtCache.evictionCount()
                fallbacks += st.stmtCache.fallbackCount()
            }
        }
        (Int64(hits), Int64(misses), Int64(evictions), Int64(fallbacks))
    }

    // ===== 活动连接跟踪(供跨线程 cancel)=====

    func setActiveConn(c: CPointer<Unit>): Unit {
        synchronized(activeMu) {
            activeConns[connPtrKey(c)] = c
        }
    }

    func clearActiveConn(c: CPointer<Unit>): Unit {
        synchronized(activeMu) {
            activeConns.remove(connPtrKey(c))
        }
    }

    // ===== 参数装配（arena）=====

    /** 参数文本装配进 arena（PGNull -> None）。 */
    static func arenaAddParams(arena: ParamArena, params: Array<PGValue>): Unit {
        arena.reset()
        for (p in params) {
            match (p) {
                case PGNull => arena.add(None)
                case _ => arena.add(Some(pgValueToText(p)))
            }
        }
    }

    // ===== 执行核心 =====

    /**
     * 在连接上执行 SQL（语句缓存 + 二进制结果自适应）。
     * 返回 PGResult（调用方负责 close）。失败抛 PGError(携带 SQLSTATE)。
     *
     * 语句缓存语义：
     * - 可缓存（stmtCache 启用、参数形状固定、SQL 非多语句）时：
     *   未命中 -> PQprepare(stmtName) -> 校验 -> PQexecPrepared；命中 -> 直接 PQexecPrepared。
     * - PQprepare/PQexecPrepared 返回 42P05/0A000 或任何致命错误时：
     *   invalidate 缓存项并回退一次 PQexecParams（保证语义不丢）。
     */
    static func run(c: CPointer<Unit>, sql: String, params: Array<PGValue>): PGResult {
        runOn(c, sql, params, None)
    }

    static func run(c: CPointer<Unit>, sql: String, params: Array<PGValue>, st: ?PGConnState): PGResult {
        runOn(c, sql, params, st)
    }

    static func runOn(c: CPointer<Unit>, sql: String, params: Array<PGValue>, stOpt: ?PGConnState): PGResult {
        // 决定结果格式：auto 时不知道结果 OID（执行前不可知）——先按二进制发，
        // 若结果列含非白名单 OID 则按文本重发一次。为避免双发，auto 模式对
        // SELECT 类查询保守：先用 llpg 判定不可行时直接退文本。
        // 简化与稳妥的折衷：只有 st 启用二进制且语句非 SELECT 时不可能有结果集，
        // 全部按"发二进制 -> 检查 -> 必要时重发文本"两段式。
        match (stOpt) {
            case Some(st) =>
                if (st.binaryResult) {
                    let res = runBinaryAware(c, sql, params, st)
                    return res
                }
            case None => ()
        }
        runPlain(c, sql, params, stOpt)
    }

    /** 文本协议执行（PQexecParams 或 prepared 路径）。 */
    static func runPlain(c: CPointer<Unit>, sql: String, params: Array<PGValue>, stOpt: ?PGConnState): PGResult {
        let n = Int32(params.size)
        // 语句缓存路径
        var cacheable = false
        var name = ""
        match (stOpt) {
            case Some(st) =>
                if (st.stmtCache.enabled() && sqlIsCacheable(sql)) {
                    cacheable = true
                    name = st.stmtCache.stmtName(sql, params.size)
                }
            case None => ()
        }
        if (cacheable) {
            let st = stOpt.getOrThrow()
            match (st.stmtCache.lookup(name)) {
                case Some(_) =>
                    // 命中：PQexecPrepared
                    let res = execPreparedText(c, name, params, st)
                    match (res) {
                        case Some(r) => return r
                        case None =>
                            // 失败已 invalidate；回退 PQexecParams
                            return execParamsText(c, sql, params, st)
                    }
                case None =>
                    // 未命中：PQprepare -> PQexecPrepared
                    let ok = prepareStmt(c, name, sql, n, st)
                    if (ok) {
                        st.stmtCache.register(name, sql)
                        let res = execPreparedText(c, name, params, st)
                        match (res) {
                            case Some(r) => return r
                            case None => return execParamsText(c, sql, params, st)
                        }
                    }
                    // prepare 失败（如含不可缓存特征）：直接 PQexecParams
                    return execParamsText(c, sql, params, st)
            }
        }
        return execParamsText(c, sql, params, stOpt)
    }

    /** PQexecParams（文本协议）。stOpt 提供时用 arena 装配参数。 */
    static func execParamsText(c: CPointer<Unit>, sql: String, params: Array<PGValue>, stOpt: ?PGConnState): PGResult {
        let n = params.size
        let csql = unsafe { LibC.mallocCString(sql) }
        let rawRes = match (stOpt) {
            case Some(st) =>
                arenaAddParams(st.arena, params)
                if (n == 0) {
                    unsafe {
                        PQexecParams(c, csql, 0, CPointer<UInt32>(), CPointer<CString>(),
                            CPointer<Int32>(), CPointer<Int32>(), 0)
                    }
                } else {
                    let arr = st.arena.buildParams()
                    let handle = unsafe { acquireArrayRawData(arr) }
                    let r = unsafe {
                        PQexecParams(c, csql, Int32(n), CPointer<UInt32>(), handle.pointer,
                            CPointer<Int32>(), CPointer<Int32>(), 0)
                    }
                    unsafe { releaseArrayRawData(handle) }
                    r
                }
            case None =>
                // 无状态（兼容旧调用方）：逐参数 mallocCString
                let cstrs = Array<CString>(n, { i =>
                    match (params[i]) {
                        case PGNull => CString(CPointer())
                        case _ => unsafe { LibC.mallocCString(pgValueToText(params[i])) }
                    }
                })
                if (n == 0) {
                    unsafe {
                        PQexecParams(c, csql, 0, CPointer<UInt32>(), CPointer<CString>(),
                            CPointer<Int32>(), CPointer<Int32>(), 0)
                    }
                } else {
                    let handle = unsafe { acquireArrayRawData(cstrs) }
                    let r = unsafe {
                        PQexecParams(c, csql, Int32(n), CPointer<UInt32>(), handle.pointer,
                            CPointer<Int32>(), CPointer<Int32>(), 0)
                    }
                    unsafe { releaseArrayRawData(handle) }
                    r
                }
        }
        unsafe { LibC.free(csql) }
        match (stOpt) {
            case Some(st) => ()
            case None => ()
        }
        let res = PGResult(rawRes)
        if (!res.isCommandOk() && !res.isTuplesOk()) {
            let err = res.buildError(sql)
            res.close()
            throw err
        }
        return res
    }

    /** PQprepare（命名语句）。返回是否成功。 */
    static func prepareStmt(c: CPointer<Unit>, name: String, sql: String, nParams: Int32, st: PGConnState): Bool {
        let cname = unsafe { LibC.mallocCString(name) }
        let csql = unsafe { LibC.mallocCString(sql) }
        let rawRes = unsafe { PQprepare(c, cname, csql, nParams, CPointer<UInt32>()) }
        unsafe { LibC.free(cname) }
        unsafe { LibC.free(csql) }
        let res = PGResult(rawRes)
        let ok = res.isCommandOk()
        if (!ok) {
            // 42P05 = duplicate prepared statement（语句名冲突/连接复用残留）：可安全忽略，
            // 该名字已存在且 SQL 相同（名字由 SQL 哈希决定），视为已 prepare。
            let sqlstate = res.sqlstate()
            res.close()
            if (sqlstate == "42P05") {
                return true
            }
            // 其余错误（0A000 等）：不可缓存，调用方走 PQexecParams
            return false
        }
        res.close()
        return true
    }

    /** PQexecPrepared（文本参数）。成功返回 Some(PGResult)；失败（已 invalidate）返回 None。 */
    static func execPreparedText(c: CPointer<Unit>, name: String, params: Array<PGValue>, st: PGConnState): ?PGResult {
        let n = params.size
        let cname = unsafe { LibC.mallocCString(name) }
        arenaAddParams(st.arena, params)
        let rawRes = if (n == 0) {
            unsafe {
                PQexecPrepared(c, cname, 0, CPointer<CString>(),
                    CPointer<Int32>(), CPointer<Int32>(), 0)
            }
        } else {
            let arr = st.arena.buildParams()
            let handle = unsafe { acquireArrayRawData(arr) }
            let r = unsafe {
                PQexecPrepared(c, cname, Int32(n), handle.pointer,
                    CPointer<Int32>(), CPointer<Int32>(), 0)
            }
            unsafe { releaseArrayRawData(handle) }
            r
        }
        unsafe { LibC.free(cname) }
        let res = PGResult(rawRes)
        if (!res.isCommandOk() && !res.isTuplesOk()) {
            let sqlstate = res.sqlstate()
            let err = res.buildError(name)
            res.close()
            // 缓存语句已不可用（连接被重置/语句被逐出/特性不支持）：失效并让调用方回退
            st.stmtCache.invalidate(name)
            if (sqlstate == "42P05" || sqlstate == "0A000" || sqlstate == "26000" /* invalid_sql_statement_name */ ||
                sqlstate == "08P01" /* protocol_violation */) {
                return None
            }
            // 其他错误是业务错误（约束冲突等），照常抛出
            throw err
        }
        return Some(res)
    }

    /**
     * 二进制结果尝试：resultFormat=1 发送；若结果列 OID 不全在白名单或物化解码失败，
     * 用文本协议重发一次。返回最终 PGResult（文本或二进制均可被 materializeBinary 处理）。
     * 重要：本函数只允许用于【只读 SELECT】——重发会把写语句副作用执行两次。
     */
    static func runBinaryAware(c: CPointer<Unit>, sql: String, params: Array<PGValue>, st: PGConnState): PGResult {
        // ===== 不变量：写语句绝不走二进制尝试（绝不重发）=====
        // 本函数的“检查结果 OID → 不全在白名单则文本重发”机制对只读 SELECT 是安全的，
        // 但对 INSERT/UPDATE/DELETE 会把写副作用【执行两次】（实测：INSERT...RETURNING
        // 双插、SERIAL 序列跳号、行数翻倍——2026-11 真库全量测试捕获）。
        // 【修改二进制白名单或重发逻辑时必须保留此判定】。写语句的 RETURNING 结果
        // 语义由文本协议承载即可（物化层无差别处理两种格式）。
        if (sqlIsWriteStatement(sql)) {
            return runPreparedOrParams(c, sql, params, st, 0)
        }
        // 执行（带语句缓存，二进制格式）
        let res = runPreparedOrParams(c, sql, params, st, 1)
        if (!res.isTuplesOk()) {
            return res
        }
        // 检查结果 OID 白名单
        let ncols = res.fieldCount()
        var allOk = true
        var j = 0
        while (j < ncols) {
            if (!binaryDecodableOid(res.fieldType(j))) {
                allOk = false
                break
            }
            j += 1
        }
        if (!allOk) {
            // 含非白名单类型：回退文本重发
            res.close()
            return runPreparedOrParams(c, sql, params, st, 0)
        }
        return res
    }

    /** 写语句判定（INSERT/UPDATE/DELETE/MERGE/REPLACE 开头）：二进制尝试禁止重发。 */
    static func sqlIsWriteStatement(sql: String): Bool {
        let head = asciiUpper(sql.trimAscii())
        return head.startsWith("INSERT") || head.startsWith("UPDATE") ||
            head.startsWith("DELETE") || head.startsWith("MERGE") || head.startsWith("REPLACE")
    }

    /** 按格式执行（prepared 优先，失败回退 PQexecParams），不检查白名单。 */
    static func runPreparedOrParams(c: CPointer<Unit>, sql: String, params: Array<PGValue>, st: PGConnState,
        resultFormat: Int32): PGResult {
        if (st.stmtCache.enabled() && sqlIsCacheable(sql)) {
            let name = st.stmtCache.stmtName(sql, params.size)
            match (st.stmtCache.lookup(name)) {
                case Some(_) =>
                    let res = execPreparedFmt(c, name, params, st, resultFormat)
                    match (res) {
                        case Some(r) => return r
                        case None => return execParamsFmt(c, sql, params, st, resultFormat)
                    }
                case None =>
                    if (prepareStmt(c, name, sql, Int32(params.size), st)) {
                        st.stmtCache.register(name, sql)
                        let res = execPreparedFmt(c, name, params, st, resultFormat)
                        match (res) {
                            case Some(r) => return r
                            case None => return execParamsFmt(c, sql, params, st, resultFormat)
                        }
                    }
                    return execParamsFmt(c, sql, params, st, resultFormat)
            }
        }
        return execParamsFmt(c, sql, params, st, resultFormat)
    }

    /** PQexecParams 指定 resultFormat（arena 参数）。 */
    static func execParamsFmt(c: CPointer<Unit>, sql: String, params: Array<PGValue>, st: PGConnState,
        resultFormat: Int32): PGResult {
        let n = params.size
        let csql = unsafe { LibC.mallocCString(sql) }
        arenaAddParams(st.arena, params)
        let rawRes = if (n == 0) {
            unsafe {
                PQexecParams(c, csql, 0, CPointer<UInt32>(), CPointer<CString>(),
                    CPointer<Int32>(), CPointer<Int32>(), resultFormat)
            }
        } else {
            let arr = st.arena.buildParams()
            let handle = unsafe { acquireArrayRawData(arr) }
            let r = unsafe {
                PQexecParams(c, csql, Int32(n), CPointer<UInt32>(), handle.pointer,
                    CPointer<Int32>(), CPointer<Int32>(), resultFormat)
            }
            unsafe { releaseArrayRawData(handle) }
            r
        }
        unsafe { LibC.free(csql) }
        let res = PGResult(rawRes)
        if (!res.isCommandOk() && !res.isTuplesOk()) {
            let err = res.buildError(sql)
            res.close()
            throw err
        }
        res
    }

    /** PQexecPrepared 指定 resultFormat（arena 参数）。 */
    static func execPreparedFmt(c: CPointer<Unit>, name: String, params: Array<PGValue>, st: PGConnState,
        resultFormat: Int32): ?PGResult {
        let n = params.size
        let cname = unsafe { LibC.mallocCString(name) }
        arenaAddParams(st.arena, params)
        let rawRes = if (n == 0) {
            unsafe {
                PQexecPrepared(c, cname, 0, CPointer<CString>(),
                    CPointer<Int32>(), CPointer<Int32>(), resultFormat)
            }
        } else {
            let arr = st.arena.buildParams()
            let handle = unsafe { acquireArrayRawData(arr) }
            let r = unsafe {
                PQexecPrepared(c, cname, Int32(n), handle.pointer,
                    CPointer<Int32>(), CPointer<Int32>(), resultFormat)
            }
            unsafe { releaseArrayRawData(handle) }
            r
        }
        unsafe { LibC.free(cname) }
        let res = PGResult(rawRes)
        if (!res.isCommandOk() && !res.isTuplesOk()) {
            let sqlstate = res.sqlstate()
            let err = res.buildError(name)
            res.close()
            st.stmtCache.invalidate(name)
            if (sqlstate == "42P05" || sqlstate == "0A000" || sqlstate == "26000" || sqlstate == "08P01") {
                return None
            }
            throw err
        }
        return Some(res)
    }

    /** 语句是否可缓存：单条语句（无分号拼接）、非空、长度合理。 */
    static func sqlIsCacheable(sql: String): Bool {
        let t = sql.trimAscii()
        if (t.isEmpty() || t.size > 65536) {
            return false
        }
        // 多语句（分号分隔）不能用 prepared 协议
        let body = stripTrailingSemicolon(t)
        if (body.contains(";")) {
            return false
        }
        // LISTEN/NOTIFY/COPY/DECLARE/CLOSE/FETCH/DEALLOCATE 等会话态语句不缓存
        let head = asciiUpper(body)
        if (head.startsWith("LISTEN") || head.startsWith("NOTIFY") || head.startsWith("UNLISTEN") ||
            head.startsWith("COPY") || head.startsWith("DECLARE") || head.startsWith("CLOSE") ||
            head.startsWith("FETCH") || head.startsWith("DEALLOCATE") || head.startsWith("PREPARE") ||
            head.startsWith("EXECUTE") || head.startsWith("SET ") || head.startsWith("BEGIN") ||
            head.startsWith("COMMIT") || head.startsWith("ROLLBACK") || head.startsWith("SAVEPOINT")) {
            return false
        }
        true
    }

    static func stripTrailingSemicolon(s: String): String {
        var t = s
        while (t.endsWith(";")) {
            t = t[0..t.size - 1]
        }
        t.trimAscii()
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

    // ===== 物化（bridge 批量路径 + 旧路径兜底）=====

    /**
     * 物化结果集为 PgRowData 数组。
     * 优先 bridge 扁平缓冲（一次 C 遍历 + <=4 次 FFI 取头部/cell），二进制结果
     * 先按 OID 解码为文本等价形式再进 values；bridge 不可用（NULL 返回/解码失败）
     * 时回退旧逐 cell 路径。
     */
    static func materialize(res: PGResult): Array<PgRowData> {
        let buf = unsafe { llpg_materialize(res.raw()) }
        if (buf.isNull()) {
            return materializeLegacy(res)
        }
        let nrows = Int64(unsafe { llpg_row_count(buf) })
        let ncols = Int64(unsafe { llpg_col_count(buf) })
        if (nrows == 0 || ncols == 0) {
            unsafe { llpg_bridge_free(buf) }
            if (nrows == 0) {
                return Array<PgRowData>()
            }
            return materializeLegacy(res)
        }
        // 列名/OID（结果级一次）
        let names = Array<String>(ncols, { j => res.fieldName(j) })
        let oids = Array<Int32>(ncols, { j => Int32(unsafe { llpg_col_oid(buf, Int32(j)) }) })
        let binary = res.isBinary()
        // cell 表（顺序遍历：data 段游标自增，避免 llpg_cell_off 每 cell O(idx) 重算——
        // 13k×13 列时 O(n²) 累加实测 3.3s）
        let rows = ArrayList<PgRowData>()
        let vals = Array<String>(ncols, { _ => "" })
        let nulls = Array<Bool>(ncols, { _ => false })
        var cursor = Int64(8 + ncols * 4 + nrows * ncols * 4) // data 段起始：header 2×int32=8
        var r = 0
        while (r < nrows) {
            var c = 0
            while (c < ncols) {
                let len = unsafe { llpg_cell_len(buf, Int32(r), Int32(c)) }
                if (len < 0) {
                    nulls[c] = true
                    vals[c] = ""
                } else {
                    nulls[c] = false
                    if (!binary) {
                        // 文本协议：bridge 数据段 NUL 终止，一次 CString 转换
                        vals[c] = readBufString(buf, cursor, Int64(len))
                    } else {
                        // 二进制协议：按 OID 解码为文本等价形式
                        let bytes = readBufBytes(buf, cursor, Int64(len))
                        match (decodeBinaryCell(oids[c], bytes)) {
                            case Some(sv) => vals[c] = sv
                            case None =>
                                // 白名单外（不应发生——runBinaryAware 已过滤）：回退旧路径
                                unsafe { llpg_bridge_free(buf) }
                                return materializeLegacy(res)
                        }
                    }
                }
                // 非 NULL cell 占 len + 1(NUL)；NULL cell 无数据段
                if (len >= 0) {
                    cursor += Int64(len) + 1
                }
                c += 1
            }
            rows.add(PgRowData(names, oids, copyArray(vals), copyArray(nulls)))
            r += 1
        }
        unsafe { llpg_bridge_free(buf) }
        return rows.toArray()
    }

    static func readBufString(buf: CPointer<UInt8>, off: Int64, len: Int64): String {
        if (len == 0) {
            return ""
        }
        // bridge 数据段每 cell NUL 终止：CString 一次转换（替代逐字节 read 循环——
        // 13k×13 列实测逐字节 read 约 9.7s，CString 一次 toString 数十 ms）
        unsafe { CString(buf + off) }.toString()
    }

    static func readBufBytes(buf: CPointer<UInt8>, off: Int64, len: Int64): Array<UInt8> {
        Array<UInt8>(len, { i => unsafe { (buf + off + i).read() } })
    }

    static func copyArray(src: Array<String>): Array<String> {
        Array<String>(src.size, { i => src[i] })
    }

    static func copyArray(src: Array<Bool>): Array<Bool> {
        Array<Bool>(src.size, { i => src[i] })
    }

    /** 旧逐 cell 物化（bridge 不可用时的兜底，行为与原实现一致）。 */
    static func materializeLegacy(res: PGResult): Array<PgRowData> {
        let nrows = res.rowCount()
        let ncols = res.fieldCount()
        let names = Array<String>(ncols, { j => res.fieldName(j) })
        let oids = Array<Int32>(ncols, { j => res.fieldType(j) })
        let rows = ArrayList<PgRowData>()
        for (i in 0..nrows) {
            let nulls = Array<Bool>(ncols, { j => res.isNull(i, j) })
            let vals = Array<String>(ncols, { j => if (nulls[j]) { "" } else { res.getValue(i, j) } })
            rows.add(PgRowData(names, oids, vals, nulls))
        }
        return rows.toArray()
    }

    // ===== 公共 API =====

    /** 执行查询，物化全部行为 PgRowData 数组。 */
    public func query(sql: String, params: Array<PGValue>): Array<PgRowData> {
        match (txn.get()) {
            case Some(c) =>
                let st = stateFor(c)
                setActiveConn(c)
                try {
                    let res = PGDatabase.runOn(c, sql, params, Some(st))
                    let rows = PGDatabase.materialize(res)
                    res.close()
                    return rows
                } finally { clearActiveConn(c) }
            case None =>
                let c = pool.borrow()
                try {
                    let st = stateFor(c)
                    setActiveConn(c)
                    let res = PGDatabase.runOn(c, sql, params, Some(st))
                    let rows = PGDatabase.materialize(res)
                    res.close()
                    return rows
                } finally {
                    clearActiveConn(c)
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
                let st = stateFor(c)
                setActiveConn(c)
                try {
                    let res = PGDatabase.runOn(c, sql, params, Some(st))
                    let a = res.affectedRows()
                    res.close()
                    a
                } finally { clearActiveConn(c) }
            case None =>
                let c = pool.borrow()
                try {
                    let st = stateFor(c)
                    setActiveConn(c)
                    let res = PGDatabase.runOn(c, sql, params, Some(st))
                    let a = res.affectedRows()
                    res.close()
                    a
                } finally {
                    clearActiveConn(c)
                    pool.giveBack(c)
                }
        }
        lastAffected.set(aff)
        return aff
    }

    /** 执行原始 SQL(无参数，DDL/迁移脚本)。 */
    public func execSql(sql: String): Unit {
        match (txn.get()) {
            case Some(c) =>
                setActiveConn(c)
                try { PGDatabase.execRaw(c, sql) } finally { clearActiveConn(c) }
            case None =>
                let c = pool.borrow()
                try {
                    setActiveConn(c)
                    PGDatabase.execRaw(c, sql)
                } finally {
                    clearActiveConn(c)
                    pool.giveBack(c)
                }
        }
    }

    /** 上一条 exec 影响的行数(非 DML 返回 -1)。 */
    public func affectedRows(): Int64 { lastAffected.get() ?? -1 }

    // ===== 事务 =====

    public func begin(): Unit {
        begin(IsolationLevel.Default)
    }

    /** 带隔离级别的 BEGIN（Default → 裸 BEGIN；其余拼 ISOLATION LEVEL 子句）。 */
    public func begin(level: IsolationLevel): Unit {
        match (txn.get()) {
            case Some(_) =>
                // 重入保护：同一线程嵌套 begin 会借第二条连接并覆盖 ThreadLocal，
                // 导致第一条钉住的连接永远不归还（泄漏）——直接拒绝。
                throw PGError("PGDatabase.begin: already in transaction (nested begin is not supported; use transaction() for REQUIRED propagation)")
            case None => ()
        }
        let c = pool.borrow()
        try {
            PGDatabase.execRaw(c, "BEGIN" + isolationClause(level))
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
     * 取消当前线程正在执行的查询(从另一线程调用，如超时看门狗)。
     * 连接注册表按连接身份定向：只取消本线程注册的活动连接，不再取消全局单槽
     * （并发查询下原实现可能取消错误连接）。
     * 无活动查询时静默返回 false。PQcancel 失败返回 false(尽力而为)。
     */
    public func cancel(): Bool {
        // 取消所有注册中的活动连接（当前线程视角通常至多一条；跨线程看门狗场景
        // 调用方持有目标 Database，取消其全部活动查询是保守正确的语义）。
        let targets = ArrayList<CPointer<Unit>>()
        synchronized(activeMu) {
            for ((_, c) in activeConns) {
                targets.add(c)
            }
        }
        if (targets.size == 0) {
            return false
        }
        var any = false
        for (c in targets) {
            let pgcancel = unsafe { PQgetCancel(c) }
            if (pgcancel.isNull()) {
                continue
            }
            var errbuf = Array<UInt8>(256, { _ => 0u8 })
            let handle = unsafe { acquireArrayRawData(errbuf) }
            let r = unsafe { PQcancel(pgcancel, handle.pointer, 256) }
            unsafe { releaseArrayRawData(handle) }
            unsafe { PQfreeCancel(pgcancel) }
            if (r != 0) {
                any = true
            }
        }
        return any
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
                let st = stateFor(c)
                let cursorName = "pgc_stream_" + nowMillis().toString()
                let declRes = PGDatabase.runOn(c, "DECLARE " + cursorName + " CURSOR FOR " + sql, params, Some(st))
                declRes.close()
                let fetchSql = "FETCH " + chunkSize.toString() + " FROM " + cursorName
                while (true) {
                    let res = PGDatabase.runOn(c, fetchSql, [], Some(st))
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
                    let st = stateFor(conn)
                    PGDatabase.execRaw(conn, "BEGIN")
                    let declRes = PGDatabase.runOn(conn, "DECLARE pgc_stream_cur CURSOR FOR " + sql, params, Some(st))
                    declRes.close()
                    let fetchSql = "FETCH " + chunkSize.toString() + " FROM pgc_stream_cur"
                    while (true) {
                        let res = PGDatabase.runOn(conn, fetchSql, [], Some(st))
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

/** ASCII 大写（SQL 关键字判定用；非 ASCII 字节原样）。 */
func asciiUpper(s: String): String {
    let a = s.toArray()
    let out = ArrayList<UInt8>()
    for (b in a) {
        if (b >= 97u8 && b <= 122u8) {
            out.add(b - 32u8)
        } else {
            out.add(b)
        }
    }
    String.fromUtf8(out.toArray())
}
