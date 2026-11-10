package postgresql_driver

import std.time.*
import std.env.getVariable

// ORM 物化层微基准：13k 行 × 16 列结果集的端到端 query() 耗时，
// 与 psql 侧 ~2ms 对照，差值即 materialize+PgRowData+String 转换的仓颉侧成本。
// 无 DB 时跳过。
func ormBenchConnOrSkip(): ?PGDatabase {
    let cs = getVariable("DB_STRING") ?? ""
    if (cs.isEmpty()) { println("[skip] orm bench: no DB_STRING"); return None }
    try { return Some(PGDatabase(cs)) } catch (_: Exception) {
        println("[skip] orm bench: no PostgreSQL"); return None
    }
}

@Test
func benchMaterialize13kRows() {
    match (ormBenchConnOrSkip()) {
        case None => return
        case Some(db) =>
            // 表是否存在由外部迁移保证；不存在则跳过
            var exists = false
            try {
                let probe: ?PgRowData = db.queryOne("SELECT 1 FROM archive_search_docs LIMIT 1", [])
                exists = probe.isSome()
            } catch (_: Exception) { exists = false }
            if (!exists) { println("[skip] orm bench: archive_search_docs not present"); db.close(); return }

            let sql = "SELECT id, arcid, filename, title, summary, tags, thumbhash, cover_asset_id, created_at, updated_at, release_at, relative_path, file_size, pagecount, archive_type, category_id FROM archive_search_docs"
            let runs = 3
            var best: Int64 = -1
            var rowsTotal = 0i64
            for (_ in 0..runs) {
                let start = MonoTime.now()
                let rows = db.query(sql, [])
                let ms = (MonoTime.now() - start).toMilliseconds()
                rowsTotal = rows.size
                if (best < 0 || ms < best) { best = ms }
            }
            println("[orm-bench] ${rowsTotal.toString()} rows x 16 cols: best ${best.toString()} ms (of ${runs.toString()})")
            db.close()
    }
}
