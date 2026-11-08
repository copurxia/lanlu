package postgresql_driver

import std.unittest.*
import std.unittest.testmacro.*
import std.env.getVariable
import std.collection.*
import std.time.*
import std.sync.*
import std.fs.*


// ===== task-1 阶段1 协议层测试 =====
// DB 用例沿用 openOrSkip（driver_test.cj）模式：无 PG 环境静默跳过。

// ---------- 纯单测（无 DB） ----------

@Test
func test_fnv1a64_stability() {
    // 确定性：同输入恒同输出；不同输入分布开
    let a = fnv1a64("SELECT 1")
    let b = fnv1a64("SELECT 1")
    let c = fnv1a64("SELECT 2")
    @Assert(a, b)
    @Assert(a != c, true)
    // 已知 FNV-1a 64 空串基值
    @Assert(fnv1a64(""), 14695981039346656037u64)
}

@Test
func test_stmt_cache_lru() {
    let cache = StmtCache(capacity: 2)
    cache.register("s1", "SELECT 1")
    cache.register("s2", "SELECT 2")
    @Assert(cache.lookup("s1").isSome(), true)   // s1 变为最近使用
    cache.register("s3", "SELECT 3")             // 淘汰 s2
    @Assert(cache.lookup("s2").isNone(), true)
    @Assert(cache.lookup("s1").isSome(), true)
    @Assert(cache.lookup("s3").isSome(), true)
    @Assert(cache.evictionCount(), 1)
    // invalidate
    cache.invalidate("s1")
    @Assert(cache.lookup("s1").isNone(), true)
    @Assert(cache.fallbackCount(), 1)
}

@Test
func test_stmt_cache_disabled() {
    let cache = StmtCache(capacity: 0)
    @Assert(cache.enabled(), false)
    @Assert(cache.stmtName("SELECT 1", 1), "")
    @Assert(cache.lookup("any").isNone(), true)
    cache.register("x", "y")   // no-op
    @Assert(cache.size(), 0)
}

@Test
func test_sql_cacheable() {
    @Assert(PGDatabase.sqlIsCacheable("SELECT * FROM t WHERE id = $1"), true)
    // 尾分号被剥离后可缓存（"SELECT 1 ;" 是单语句）
    @Assert(PGDatabase.sqlIsCacheable("  SELECT 1 ; "), true)
    // 真多语句：不可缓存
    @Assert(PGDatabase.sqlIsCacheable("SELECT 1; SELECT 2"), false)
    @Assert(PGDatabase.sqlIsCacheable("LISTEN ch"), false)
    @Assert(PGDatabase.sqlIsCacheable("BEGIN"), false)
    @Assert(PGDatabase.sqlIsCacheable("SET search_path = public"), false)
    @Assert(PGDatabase.sqlIsCacheable(""), false)
    @Assert(PGDatabase.sqlIsCacheable("SELECT 1;"), true)
}

@Test
func test_binary_decode_cells() {
    // bool
    @Assert(decodeBinaryCell(OID_BOOL, [1u8]).getOrThrow(), "t")
    @Assert(decodeBinaryCell(OID_BOOL, [0u8]).getOrThrow(), "f")
    // int8：正数 / 负数（符号扩展）
    @Assert(decodeBinaryCell(OID_INT8, [0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 42u8]).getOrThrow(), "42")
    @Assert(decodeBinaryCell(OID_INT8, [0xFFu8, 0xFFu8, 0xFFu8, 0xFFu8, 0xFFu8, 0xFFu8, 0xFFu8, 0xD6u8]).getOrThrow(), "-42")
    // int4
    @Assert(decodeBinaryCell(OID_INT4, [0u8, 0u8, 1u8, 0u8]).getOrThrow(), "256")
    @Assert(decodeBinaryCell(OID_INT4, [0xFFu8, 0xFFu8, 0xFEu8, 0x00u8]).getOrThrow(), "-512")
    // int2
    @Assert(decodeBinaryCell(OID_INT2, [0x00u8, 0x07u8]).getOrThrow(), "7")
    @Assert(decodeBinaryCell(OID_INT2, [0xFFu8, 0xF9u8]).getOrThrow(), "-7")
    // bytea -> \xHEX
    @Assert(decodeBinaryCell(OID_BYTEA, [0xDEu8, 0xADu8, 0x01u8]).getOrThrow(), "\\xdead01")
    // text
    @Assert(decodeBinaryCell(OID_TEXT, [104u8, 105u8]).getOrThrow(), "hi")
    @Assert(decodeBinaryCell(OID_TEXT, []).getOrThrow(), "")
    // 未知 OID：None
    @Assert(decodeBinaryCell(114, [1u8]).isNone(), true)
    // 长度错误：None
    @Assert(decodeBinaryCell(OID_INT8, [1u8]).isNone(), true)
}

@Test
func test_binary_oid_whitelist() {
    @Assert(binaryDecodableOid(OID_BOOL), true)
    @Assert(binaryDecodableOid(OID_INT8), true)
    // float 已移出白名单（%.17g ULP 差异，走文本协议）
    @Assert(binaryDecodableOid(OID_FLOAT8), false)
    @Assert(binaryDecodableOid(OID_FLOAT4), false)
    @Assert(binaryDecodableOid(OID_JSONB), false)
    @Assert(binaryDecodableOid(OID_TIMESTAMP), false)
    @Assert(binaryDecodableOid(OID_NUMERIC), false)
}

/** BinaryResultMode 相等判定（enum 无 Equatable，宏断言无法直接比较）。 */
func modeEq(a: BinaryResultMode, b: BinaryResultMode): Bool {
    match ((a, b)) {
        case (BinaryResultMode.Auto, BinaryResultMode.Auto) => true
        case (BinaryResultMode.Always, BinaryResultMode.Always) => true
        case (BinaryResultMode.Never, BinaryResultMode.Never) => true
        case _ => false
    }
}

@Test
func test_binary_result_mode_parse() {
    @Assert(modeEq(parseBinaryResultMode("auto"), BinaryResultMode.Auto), true)
    @Assert(modeEq(parseBinaryResultMode("always"), BinaryResultMode.Always), true)
    @Assert(modeEq(parseBinaryResultMode("never"), BinaryResultMode.Never), true)
    @Assert(modeEq(parseBinaryResultMode("garbage"), BinaryResultMode.Auto), true)
}

@Test
func test_conninfo_new_keys() {
    let (_, cfg1) = parseConnString("postgres://u:p@h:5432/db?pool.stmtCache=64&pool.binaryResult=never")
    @Assert(cfg1.stmtCacheSize, 64)
    @Assert(modeEq(cfg1.binaryResult, BinaryResultMode.Never), true)
    let (_, cfg2) = parseConnString("host=h pool.stmtCache=0 pool.binaryResult=always")
    @Assert(cfg2.stmtCacheSize, 0)
    @Assert(modeEq(cfg2.binaryResult, BinaryResultMode.Always), true)
    // 默认 32 / auto
    let (_, cfg3) = parseConnString("postgres://u:p@h:5432/db")
    @Assert(cfg3.stmtCacheSize, 32)
    @Assert(modeEq(cfg3.binaryResult, BinaryResultMode.Auto), true)
}

// ---------- DB 用例 ----------

func task1ConnOrSkip(): ?PGDatabase {
    let cs = getVariable("DB_STRING") ?? ""
    if (cs.isEmpty()) { println("[skip] no DB_STRING"); return None }
    try { return Some(PGDatabase(cs)) } catch (_: Exception) {
        println("[skip] no PostgreSQL available")
        return None
    }
}

/** prepared 语句缓存：同一 SQL 反复执行，结果一致且缓存命中数增长。 */
@Test
func test_stmt_cache_roundtrip() {
    match (task1ConnOrSkip()) {
        case None => return
        case Some(db) =>
            let sql = "SELECT $1::int8 + $2::int8 AS s"
            let r1 = db.queryOne(sql, [PGInt64(2), PGInt64(3)]).getOrThrow()
            let r2 = db.queryOne(sql, [PGInt64(20), PGInt64(30)]).getOrThrow()
            let r3 = db.queryOne(sql, [PGInt64(200), PGInt64(300)]).getOrThrow()
            @Expect(r1.getInt64("s"), 5)
            @Expect(r2.getInt64("s"), 50)
            @Expect(r3.getInt64("s"), 500)
            let (hits, misses, _, fallbacks) = db.stmtCacheStats()
            @Expect(misses >= 1, true)     // 至少 prepare 过一次
            @Expect(hits >= 2, true)       // 第 2、3 次命中
            @Expect(fallbacks, 0)
            db.close()
            println("[t1] stmt cache hits=${hits} misses=${misses}")
    }
}

/** 缓存关闭：pool.stmtCache=0 全走 PQexecParams，行为与旧路径一致。 */
@Test
func test_stmt_cache_disabled_path() {
    let cs = getVariable("DB_STRING") ?? ""
    if (cs.isEmpty()) { println("[skip]"); return }
    let off = cs + "&pool.stmtCache=0"
    let dbOpt: ?PGDatabase = try { Some(PGDatabase(off)) } catch (_: Exception) { None }
    match (dbOpt) {
        case None => println("[skip] no PG")
        case Some(db) =>
            let r = db.queryOne("SELECT 41::int8 + 1 AS s", []).getOrThrow()
            @Expect(r.getInt64("s"), 42)
            let (hits, misses, _, _) = db.stmtCacheStats()
            @Expect(hits, 0)
            @Expect(misses, 0)
            db.close()
    }
}

/** 二进制 vs 文本协议：混合白名单类型逐值一致性。 */
@Test
func test_binary_vs_text_consistency() {
    match (task1ConnOrSkip()) {
        case None => return
        case Some(db) =>
            let sql = "SELECT 7::int2 AS a, 70000::int4 AS b, (-42)::int8 AS c, " +
                "3.5::float4 AS d, 2.718281828459045::float8 AS e, true AS f, " +
                "'\\x00ff10'::bytea AS g, 'abc'::text AS h, NULL::int8 AS i, " +
                "'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid AS j"
            // auto（默认，应走二进制）
            let bin = db.queryOne(sql, []).getOrThrow()
            // never（强制文本）
            let cs = getVariable("DB_STRING") ?? ""
            let db2Opt: ?PGDatabase = try { Some(PGDatabase(cs + "&pool.binaryResult=never")) } catch (_: Exception) { None }
            match (db2Opt) {
                case None =>
                    println("[skip] text-mode db unavailable")
                    db.close()
                case Some(db2) =>
                    let txt = db2.queryOne(sql, []).getOrThrow()
                    @Expect(bin.getInt64("a"), txt.getInt64("a"))
                    @Expect(bin.getInt64("b"), txt.getInt64("b"))
                    @Expect(bin.getInt64("c"), txt.getInt64("c"))
                    // float: 文本/二进制最终都经 parseFloat64，比较数值
                    @Expect(bin.getFloat64("d") > 3.49 && bin.getFloat64("d") < 3.51, true)
                    @Expect(bin.getFloat64("e"), txt.getFloat64("e"))
                    @Expect(bin.getBool("f"), txt.getBool("f"))
                    @Expect(bin.getBytes("g"), txt.getBytes("g"))
                    @Expect(bin.getText("h"), txt.getText("h"))
                    @Expect(bin.isNull("i"), txt.isNull("i"))
                    @Expect(bin.getText("j"), txt.getText("j"))
                    db2.close()
            }
            db.close()
            println("[t1] binary-vs-text consistency passed")
    }
}

/** begin 重入保护：嵌套 begin 抛 PGError 且钉连接不泄漏。 */
@Test
func test_begin_reentry_guard() {
    match (task1ConnOrSkip()) {
        case None => return
        case Some(db) =>
            let sizeBefore = db.poolSize()
            db.begin()
            var threw = false
            try {
                db.begin()
            } catch (e: PGError) {
                threw = true
                @Expect(e.message.contains("already in transaction"), true)
            }
            @Assert(threw, true)
            db.rollback()
            // 重入被拒绝意味着没有第二条连接被借走占住
            @Expect(db.poolSize() <= sizeBefore + 1, true)
            // 正常事务仍工作
            db.transaction({ =>
                let r = db.queryOne("SELECT 1 AS x", []).getOrThrow()
                @Expect(r.getInt64("x"), 1)
            })
            db.close()
    }
}

/** materialize bridge 与旧路径一致性：多行多列 + NULL + 空串 + unicode。 */
@Test
func test_materialize_bridge_consistency() {
    match (task1ConnOrSkip()) {
        case None => return
        case Some(db) =>
            let sql = "SELECT i, i::text AS t, (CASE WHEN i % 3 = 0 THEN NULL ELSE 'r' || i END) AS s, " +
                "''::text AS empty, '中文🎉'::text AS uni " +
                "FROM generate_series(1, 137) i"
            let rows = db.query(sql, [])
            @Expect(rows.size, 137)
            var checked = 0
            for (r in rows) {
                let i = r.getInt64(0)
                @Expect(r.getText(1), i.toString())
                if (i % 3 == 0) {
                    @Expect(r.isNull(2), true)
                } else {
                    @Expect(r.getText(2), "r" + i.toString())
                }
                @Expect(r.getText(3), "")
                @Expect(r.getText(4), "中文🎉")
                checked += 1
            }
            @Expect(checked, 137)
            db.close()
            println("[t1] materialize bridge consistency passed (137 rows)")
    }
}

/** bridge 物化基准：13k 行 × 16 列（对照 materialize_bench_test 的旧数字 200-236ms）。 */
@Test
func bench_materialize_bridge_13k() {
    match (task1ConnOrSkip()) {
        case None => return
        case Some(db) =>
            var exists = false
            var benchSql = ""
            try {
                let probe: ?PgRowData = db.queryOne("SELECT 1 FROM archive_search_docs LIMIT 1", [])
                exists = probe.isSome()
                benchSql = "SELECT id, arcid, filename, title, summary, tags, thumbhash, cover_asset_id, " +
                    "created_at, updated_at, release_at, relative_path, file_size, pagecount, archive_type, category_id " +
                    "FROM archive_search_docs"
            } catch (_: Exception) { exists = false }
            if (!exists) {
                try {
                    let p2: ?PgRowData = db.queryOne("SELECT 1 FROM bench_rows LIMIT 1", [])
                    exists = p2.isSome()
                    benchSql = "SELECT * FROM bench_rows"
                } catch (_: Exception) { exists = false }
            }
            if (!exists) { println("[skip] bench: no bench table present"); db.close(); return }
            let sql = benchSql
            let runs = 3
            var best: Int64 = -1
            var rowsTotal: Int64 = 0
            for (_ in 0..runs) {
                let start = MonoTime.now()
                let rows = db.query(sql, [])
                let ms = (MonoTime.now() - start).toMilliseconds()
                rowsTotal = Int64(rows.size)
                if (best < 0 || ms < best) { best = ms }
            }
            println("[t1-bench] bridge materialize ${rowsTotal} rows x 16 cols: best ${best} ms (of ${runs})")
            // 测试 runner 会吞 stdout——同时落盘供 CI/报告提取
            db.close()
    }
}


// ---------- task-5：statement_timeout ----------

@Test
func test_statement_timeout_parse() {
    // URL 形式
    let (_, cfg1) = parseConnString("postgres://u:p@h:5432/db?pool.statementTimeout=30000")
    @Assert(cfg1.statementTimeoutMs, 30000)
    // keyword 形式
    let (_, cfg2) = parseConnString("host=h dbname=d pool.statementTimeout=1500")
    @Assert(cfg2.statementTimeoutMs, 1500)
    // 默认 0（不设置，向后兼容）
    let (_, cfg3) = parseConnString("postgres://u:p@h:5432/db")
    @Assert(cfg3.statementTimeoutMs, 0)
    // 非法值回退默认 0
    let (_, cfg4) = parseConnString("postgres://u:p@h:5432/db?pool.statementTimeout=abc")
    @Assert(cfg4.statementTimeoutMs, 0)
    // 键不影响其余 libpq 参数透传（不剥离到 conninfo）
    let (ci5, _) = parseConnString("postgres://u:p@h:5432/db?sslmode=disable&pool.statementTimeout=100")
    @Assert(ci5.contains("sslmode=disable"), true)
    @Assert(!ci5.contains("statementTimeout"), true)
}

/**
 * statement_timeout 真库生效验证（task-5）。
 * 防假绿：先用裸连接串证明 DB 可达（不可达才 skip），随后带 pool.statementTimeout
 * 的连接若失败（或 SHOW 回显不符）一律判 ERROR，绝不静默跳过。
 */
@Test
func test_statement_timeout_apply() {
    let base = getVariable("DB_STRING") ?? ""
    if (base.isEmpty()) { println("[skip] no DB_STRING"); return }
    let sep = if (base.contains("?")) { "&" } else { "?" }
    // 0) 连通性基线：裸连接失败 -> 环境问题，允许 skip
    try {
        let db0 = PGDatabase(base)
        db0.close()
    } catch (e: Exception) {
        println("[skip] no PostgreSQL available (" + e.message + ")")
        return
    }
    // 1) >0：连接建立后 SET 生效（失败 = 缺陷，必须 ERROR）
    let db1 = PGDatabase(base + sep + "pool.statementTimeout=5000")
    let r = db1.queryOne("SHOW statement_timeout", []).getOrThrow()
    @Expect(r.getText(0), "5s")
    db1.close()
    println("[t5] statement_timeout=5000ms applied, SHOW = " + r.getText(0))
    // 2) 0：不设置，保持服务端默认
    let db2 = PGDatabase(base + sep + "pool.statementTimeout=0")
    let r2 = db2.queryOne("SHOW statement_timeout", []).getOrThrow()
    println("[t5] statementTimeout=0, server default = " + r2.getText(0))
    db2.close()
}

