package lanlu_client_next.storage

import rocksdb_ffi.{RocksDb, RocksDbOperationResult, RocksDbError, RocksDbErrorKind, RocksDbWriteBatch}
import std.collection.ArrayList
import std.fs.{Directory, Path}

private class StringObjectCodec <: ObjectCodec<String> {
    public func typeName(): String {
        "test-string"
    }
    public func schemaVersion(): UInt32 {
        1u32
    }

    public func encode(value: String): RocksDbOperationResult<Array<UInt8>> {
        RocksDbOperationResult<Array<UInt8>>.Ok(value.toArray())
    }

    public func decode(payload: Array<UInt8>, schemaVersion: UInt32): RocksDbOperationResult<String> {
        if (schemaVersion != 1u32) {
            return RocksDbOperationResult<String>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "unsupported test schema"))
        }
        try {
            return RocksDbOperationResult<String>.Ok(String.fromUtf8(payload))
        } catch (_: Exception) {
            return RocksDbOperationResult<String>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "invalid test payload"))
        }
    }
}

private func openObjectStoreTestDb(): RocksDb {
    let dir = Directory.createTemp(Path("/tmp"))
    let (ok, db, error) = RocksDb.openLowMemory(dir.toString())
    if (!ok) {
        throw Exception(error)
    }
    return db.getOrThrow()
}

private func unwrapStore<T>(result: RocksDbOperationResult<T>): T {
    match (result) {
        case RocksDbOperationResult<T>.Ok(value) => value
        case RocksDbOperationResult<T>.NotFound => throw Exception("unexpected object-store NotFound")
        case RocksDbOperationResult<T>.Err(error) => throw Exception(error.message)
    }
}

// 带 schema 迁移的 codec：v1 载荷是 "old:" 前缀字符串，migrate 把 v1→v2 加 "new:" 前缀。
private class MigratingObjectCodec <: ObjectCodec<String> {
    public func typeName(): String {
        "migrating-string"
    }
    public func schemaVersion(): UInt32 {
        2u32
    }

    public func encode(value: String): RocksDbOperationResult<Array<UInt8>> {
        RocksDbOperationResult<Array<UInt8>>.Ok(value.toArray())
    }

    public func decode(payload: Array<UInt8>, schemaVersion: UInt32): RocksDbOperationResult<String> {
        try {
            let text = String.fromUtf8(payload)
            return RocksDbOperationResult<String>.Ok(
                if (text.startsWith("new:")) {
                    text.removePrefix("new:")
                } else {
                    text
                })
        } catch (_: Exception) {
            return RocksDbOperationResult<String>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "invalid migrating payload"))
        }
    }

    public func migrate(payload: Array<UInt8>, fromSchema: UInt32): RocksDbOperationResult<Array<UInt8>> {
        if (fromSchema == 1u32) {
            // v1 → v2：payload 前置 "new:" 标记。
            let out = "new:".toArray()
            let combined = ArrayList<UInt8>(out.size + payload.size)
            for (b in out) {
                combined.add(b)
            }
            for (b in payload) {
                combined.add(b)
            }
            return RocksDbOperationResult<Array<UInt8>>.Ok(combined.toArray())
        }
        if (fromSchema == 2u32) {
            return RocksDbOperationResult<Array<UInt8>>.Ok(payload)
        }
        return RocksDbOperationResult<Array<UInt8>>.Err(
            RocksDbError(RocksDbErrorKind.DecodeFailure, "unsupported migrating schema ${fromSchema}"))
    }
}

@Test
func objectRepositoryMigratesOldSchemaBeforeDecode(): Unit {
    let db = openObjectStoreTestDb()
    let repo = ObjectRepository<String>(db, StorageScope("srv:1", "acct:1"), MigratingObjectCodec())
    try {
        // v1 记录：schemaVersion=1，payload="legacy"。
        let envelope = RecordEnvelope(1u32, "migrating-string", 1000, 0, "legacy".toArray())
        let key = repo.entityKey("id:1")
        let _ = db.putBytesResult(key, envelope.encode())
        // 读路径经 migrate v1→v2 后解码：值应等于去掉 "new:" 前缀的 "legacy"。
        @Expect(unwrapStore(repo.get("id:1")), "legacy")
        // v2 记录直接解码。
        let _ = unwrapStore(repo.put("id:2", "fresh"))
        @Expect(unwrapStore(repo.get("id:2")), "fresh")
    } finally {
        db.close()
    }
}

@Test
func storageKeyComponentsAreBinarySafeAndRoundTrip(): Unit {
    let parts = ["server:a".toArray(), [0u8, 255u8, 58u8], Array<UInt8>()]
    let decoded = StorageKeyCodec.decode(StorageKeyCodec.encode(parts)).getOrThrow()
    @Expect(decoded.size, 3)
    @Expect(String.fromUtf8(decoded[0]), "server:a")
    @Expect(decoded[1].size, 3)
    @Expect(decoded[1][0], 0u8)
    @Expect(decoded[1][1], 255u8)
    @Expect(decoded[2].size, 0)
}

@Test
func objectRepositoryHandlesTtlAndBadRecordSelfHealing(): Unit {
    let db = openObjectStoreTestDb()
    let repo = ObjectRepository<String>(db, StorageScope("srv:1", "acct\u{0000}1"), StringObjectCodec())
    try {
        let _ = unwrapStore(repo.put("id:1", "payload", ttlMs: 100, savedAtMs: 1000))
        @Expect(unwrapStore(repo.get("id:1", nowMs: 1050)), "payload")
        match (repo.get("id:1", nowMs: 1100)) {
            case RocksDbOperationResult<String>.NotFound => ()
            case _ => throw Exception("expired record should be removed")
        }

        let _ = unwrapStore(db.putBytesResult(repo.entityKey("bad"), [1u8, 2u8, 3u8]))
        match (repo.get("bad", nowMs: 0)) {
            case RocksDbOperationResult<String>.Err(_) => ()
            case _ => throw Exception("malformed envelope should report DecodeFailure")
        }
        match (db.getBytesResult(repo.entityKey("bad"))) {
            case RocksDbOperationResult<Array<UInt8>>.NotFound => ()
            case _ => throw Exception("malformed envelope should be self-healed")
        }
    } finally {
        db.close()
    }
}

@Test
func objectAndQueryMembershipCommitInOneBatchAndPageByToken(): Unit {
    let db = openObjectStoreTestDb()
    let scope = StorageScope("srv-1", "account-1")
    let repo = ObjectRepository<String>(db, scope, StringObjectCodec())
    let queries = QueryRepository(db, scope)
    try {
        let batch = unwrapStore(RocksDbWriteBatch.create())
        try {
            for (i in 0..5) {
                let id = "id-${i}"
                let _ = unwrapStore(repo.putInto(batch, id, "value-${i}", savedAtMs: 1000))
                let _ = unwrapStore(queries.addInto(batch, "search:a:b", UInt64(i), "test-string", id))
            }
            let _ = unwrapStore(db.commitWriteBatchResult(batch))
        } finally {
            batch.close()
        }

        let first = unwrapStore(queries.readPage("search:a:b", limit: 2))
        @Expect(first.members.size, 2)
        @Expect(first.members[0].entityId, "id-0")
        @Expect(first.members[1].entityId, "id-1")
        @Expect(unwrapStore(repo.get(first.members[1].entityId, nowMs: 1000)), "value-1")

        let second = unwrapStore(queries.readPage("search:a:b", startAfter: first.nextToken, limit: 2))
        @Expect(second.members.size, 2)
        @Expect(second.members[0].entityId, "id-2")
        @Expect(second.members[1].entityId, "id-3")
        @Expect(unwrapStore(queries.readMemberAt("search:a:b", 3u64)).entityId, "id-3")
        match (queries.readMemberAt("search:a:b", 99u64)) {
            case RocksDbOperationResult<QueryMember>.NotFound => ()
            case _ => throw Exception("missing rank should return NotFound")
        }

        let objects = unwrapStore(repo.multiGet(["id-0", "missing", "id-2"], nowMs: 1000))
        @Expect(objects[0].getOrThrow(), "value-0")
        @Expect(objects[1].isNone(), true)
        @Expect(objects[2].getOrThrow(), "value-2")

        let view = PagedObjectView<String>(repo, queries)
        let _ = unwrapStore(view.load("search:a:b", limit: 2, nowMs: 1000))
        @Expect(view.count(), 2)
        @Expect(view.itemAt(0).getOrThrow(), "value-0")
        let _ = unwrapStore(view.load("search:a:b", startAfter: view.nextToken(), limit: 2, nowMs: 1000))
        @Expect(view.count(), 2)
        @Expect(view.itemAt(0).getOrThrow(), "value-2")
        @Expect(view.version(), 2)

        let _ = unwrapStore(queries.deleteQuery("search:a:b"))
        @Expect(unwrapStore(queries.readPage("search:a:b")).members.size, 0)
        @Expect(unwrapStore(repo.get("id-4", nowMs: 1000)), "value-4")
    } finally {
        db.close()
    }
}

@Test
func objectAndQueryRangesCanBeReplacedInOneBatch(): Unit {
    let db = openObjectStoreTestDb()
    let scope = StorageScope("srv-2", "account-2")
    let repo = ObjectRepository<String>(db, scope, StringObjectCodec())
    let queries = QueryRepository(db, scope)
    try {
        let first = unwrapStore(RocksDbWriteBatch.create())
        try {
            for (i in 0..3) {
                let _ = unwrapStore(repo.putInto(first, "old-${i}", "value-${i}"))
                let _ = unwrapStore(queries.addInto(first, "replace", UInt64(i), repo.objectType(), "old-${i}"))
            }
            let _ = unwrapStore(db.commitWriteBatchResult(first))
        } finally {
            first.close()
        }

        let replacement = unwrapStore(RocksDbWriteBatch.create())
        try {
            let _ = unwrapStore(repo.deleteAllInto(replacement))
            let _ = unwrapStore(queries.deleteQueryInto(replacement, "replace"))
            let _ = unwrapStore(repo.putInto(replacement, "new", "replacement"))
            let _ = unwrapStore(queries.addInto(replacement, "replace", 0u64, repo.objectType(), "new"))
            let _ = unwrapStore(db.commitWriteBatchResult(replacement))
        } finally {
            replacement.close()
        }

        match (repo.get("old-0")) {
            case RocksDbOperationResult<String>.NotFound => ()
            case _ => throw Exception("range replacement should remove stale objects")
        }
        @Expect(unwrapStore(repo.get("new")), "replacement")
        @Expect(unwrapStore(queries.readMemberAt("replace", 0u64)).entityId, "new")
        match (queries.readMemberAt("replace", 1u64)) {
            case RocksDbOperationResult<QueryMember>.NotFound => ()
            case _ => throw Exception("range replacement should remove stale memberships")
        }
    } finally {
        db.close()
    }
}

@Test
func objectRepositoryOpenCursorPagesByEntityId(): Unit {
    let db = openObjectStoreTestDb()
    let scope = StorageScope("srv-1", "account-1")
    let repo = ObjectRepository<String>(db, scope, StringObjectCodec())
    try {
        for (i in 0..5) {
            let _ = unwrapStore(repo.put("id-${i}", "value-${i}", savedAtMs: 1000))
        }
        // 每页 2 条，按 id 顺序翻页。
        let page1 = unwrapStore(repo.openCursor(limit: 2))
        @Expect(page1.values.size, 2)
        let (p1k0, _) = page1.values[0]
        let (p1k1, _) = page1.values[1]
        @Expect(p1k0, "id-0")
        @Expect(p1k1, "id-1")
        let page2 = unwrapStore(repo.openCursor(startAfter: page1.nextAfter, limit: 2))
        @Expect(page2.values.size, 2)
        let (p2k0, _) = page2.values[0]
        @Expect(p2k0, "id-2")
        // 5 个对象（0..5 排除上界）：页3 只有 id-4。
        let page3 = unwrapStore(repo.openCursor(startAfter: page2.nextAfter, limit: 2))
        @Expect(page3.values.size, 1)
        let (p3k0, _) = page3.values[0]
        @Expect(p3k0, "id-4")
        let page4 = unwrapStore(repo.openCursor(startAfter: page3.nextAfter, limit: 2))
        @Expect(page4.values.size, 0)
    } finally {
        db.close()
    }
}

@Test
func queryMetadataTracksLastUpdatedAndPurgesEntityMemberships(): Unit {
    let db = openObjectStoreTestDb()
    let scope = StorageScope("srv-1", "account-1")
    let queries = QueryRepository(db, scope)
    let repo = ObjectRepository<String>(db, scope, StringObjectCodec())
    try {
        // query metadata：touch 后读回。
        match (queries.lastUpdatedAt("search:x")) {
            case RocksDbOperationResult<Int64>.NotFound => ()
            case _ => throw Exception("fresh query should have no metadata")
        }
        let _ = unwrapStore(queries.touchQuery("search:x", atMs: 123456))
        @Expect(unwrapStore(queries.lastUpdatedAt("search:x")), 123456)
        let _ = unwrapStore(queries.deleteQueryMeta("search:x"))
        match (queries.lastUpdatedAt("search:x")) {
            case RocksDbOperationResult<Int64>.NotFound => ()
            case _ => throw Exception("deleted query metadata should be gone")
        }

        // 索引自愈：坏对象被删后，purge 移除引用它的所有 membership。
        let batch = unwrapStore(RocksDbWriteBatch.create())
        try {
            let _ = unwrapStore(repo.putInto(batch, "id:bad", "x", savedAtMs: 1000))
            let _ = unwrapStore(queries.addInto(batch, "q1", 0u64, "test-string", "id:bad"))
            let _ = unwrapStore(queries.addInto(batch, "q2", 3u64, "test-string", "id:bad"))
            let _ = unwrapStore(queries.addInto(batch, "q1", 1u64, "test-string", "id:good"))
            let _ = unwrapStore(db.commitWriteBatchResult(batch))
        } finally {
            batch.close()
        }
        @Expect(queries.purgeEntityMemberships("test-string", "id:bad"), 2)
        // q1 只剩 id:good。
        let q1 = unwrapStore(queries.readPage("q1"))
        @Expect(q1.members.size, 1)
        @Expect(q1.members[0].entityId, "id:good")
        // q2 已空。
        let q2 = unwrapStore(queries.readPage("q2"))
        @Expect(q2.members.size, 0)
        // 再次 purge 幂等（无引用）。
        @Expect(queries.purgeEntityMemberships("test-string", "id:bad"), 0)
    } finally {
        db.close()
    }
}

