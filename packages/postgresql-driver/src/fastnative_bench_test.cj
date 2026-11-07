package postgresql_driver

import std.time.*
import std.env.getVariable

// A/B 微基准：测量纯访问器 foreign 调用的单次开销。
// openOrSkip 同 driver_test 模式；结果只打印不设硬阈值（CI 抖动大），
// 由人工对比加 @FastNative 前后两次运行输出。
func benchConnOrSkip(): ?PGDatabase {
    let cs = getVariable("DB_STRING") ?? "postgres://copur:x@127.0.0.1:5432/lanludev?sslmode=disable&pool.max=1"
    try {
        return Some(PGDatabase(cs))
    } catch (_: Exception) {
        println("[skip] bench: no PostgreSQL available")
        return None
    }
}

@Test
func benchPqAccessors() {
    match (benchConnOrSkip()) {
        case None => return
        case Some(db) =>
            let rows = db.query("SELECT 'a'::text AS c1, 123::int8 AS c2, true AS c3, NULL::text AS c4", [])
            @Assert(rows.size, 1)
            // 拿底层 PGResult 不可行（PGDatabase 封装了），改用查询路径整体计时：
            // 单行 4 列小查询 = 连接池借还 + PQexecParams + 物化（4 格 × 3 次 FFI），
            // 访问器占比通过与大结果集对比体现。此处直接循环小查询测整体。
            let n = 20000
            let start = MonoTime.now()
            var checksum = 0i64
            for (_ in 0..n) {
                let r = db.query("SELECT 'a'::text, 123::int8, true, 1::int4", [])
                checksum += r[0].getInt64(1)
            }
            let elapsedNs = (MonoTime.now() - start).toNanoseconds()
            println("[bench] per-query: ${(elapsedNs / n).toString()} ns (checksum=${checksum.toString()})")

            // 纯物化放大：50 行 × 8 列 = 400 格/查询，循环 2000 次，
            // FFI 访问器调用量 = 400×3×2000 = 240 万次，放大后差异可辨。
            let m = 2000
            let start2 = MonoTime.now()
            var rowsTotal = 0i64
            for (_ in 0..m) {
                let big = db.query("SELECT i, i::text, i::int8, i::float8, true, 'x', NULL, i%7 FROM generate_series(1,50) i", [])
                rowsTotal += big.size
            }
            let elapsed2Ns = (MonoTime.now() - start2).toNanoseconds()
            println("[bench] per-50row-query: ${(elapsed2Ns / m).toString()} ns (rows=${rowsTotal.toString()}, ffi-calls≈2400000)")
            db.close()
    }
}
