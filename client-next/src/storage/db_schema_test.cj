package lanlu_client_next.storage

import rocksdb_ffi.{RocksDb, RocksDbColumnFamily, RocksDbOperationResult}
import std.fs.{Directory, Path}

// 记录最近打开的 DB 路径（测试辅助：RocksDB 单进程内同一目录只能开一个实例）。
private var lastDbPath = ""

private func ensureMeta(db: RocksDb): RocksDbColumnFamily {
    match (db.ensureColumnFamilyResult("meta")) {
        case RocksDbOperationResult<RocksDbColumnFamily>.Ok(value) => return value
        case _ => throw Exception("meta cf missing")
    }
}

private func openTrackedDb(): RocksDb {
    let dir = Directory.createTemp(Path("/tmp"))
    lastDbPath = dir.toString()
    match (RocksDb.openLowMemory(dir.toString())) {
        case (true, Some(value), _) => value
        case _ => throw Exception("db open failed")
    }
}

private func reopenLastDb(): RocksDb {
    if (lastDbPath.size == 0) {
        throw Exception("no tracked db path")
    }
    match (RocksDb.openLowMemory(lastDbPath)) {
        case (true, Some(value), _) => value
        case _ => throw Exception("reopen failed")
    }
}

@Test
func dbSchemaVersionWritesAndReopensIdempotently(): Unit {
    let db = openTrackedDb()
    let schema = DbSchema(db, ensureMeta(db))
    @Expect(schema.currentVersion(), 0) // 全新库
    @Expect(schema.writeVersion(3), true)
    @Expect(schema.currentVersion(), 3)
    db.close()

    // 重开：版本保持。
    let reopened = reopenLastDb()
    let schema2 = DbSchema(reopened, ensureMeta(reopened))
    @Expect(schema2.currentVersion(), 3)
    // 幂等写：再写同版本不报错。
    @Expect(schema2.writeVersion(3), true)
    @Expect(schema2.currentVersion(), 3)
    reopened.close()
}

@Test
func dbSchemaStepsAreIdempotentAndMarkersPersist(): Unit {
    let db = openTrackedDb()
    let schema = DbSchema(db, ensureMeta(db))
    @Expect(schema.stepDone("cache:v1"), false)
    @Expect(schema.markStepDone("cache:v1"), true)
    @Expect(schema.stepDone("cache:v1"), true)
    // 重复标记幂等。
    @Expect(schema.markStepDone("cache:v1"), true)
    @Expect(schema.stepDone("cache:v1"), true)
    db.close()

    // 崩溃重跑：已完成的步骤 marker 仍在，直接跳过。
    let reopened = reopenLastDb()
    let schema2 = DbSchema(reopened, ensureMeta(reopened))
    @Expect(schema2.stepDone("cache:v1"), true)
    @Expect(schema2.stepDone("cache:v2"), false)
    reopened.close()
}

@Test
func dbSchemaConstantsMatchCurrentPlan(): Unit {
    @Expect(CACHE_DB_SCHEMA, 1)
    @Expect(SETTINGS_DB_SCHEMA, 3)
}
