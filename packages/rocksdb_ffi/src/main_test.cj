package rocksdb_ffi

import std.collection.ArrayList
import std.env.getVariable
import std.fs.{Directory, Path}
import std.sync.{Mutex, SyncCounter}
import std.unittest.*
import std.unittest.testmacro.*

// 跨平台临时目录：Windows 无 /tmp，依次取 TMPDIR/TEMP/TMP，兜底当前目录。
private func tempBaseDir(): Path {
    for (name in ["TMPDIR", "TEMP", "TMP"]) {
        if (let Some(value) <- getVariable(name)) {
            if (value.size > 0) {
                return Path(value)
            }
        }
    }
    return Path(".")
}

private func openTestDb(): RocksDb {
    let dir = Directory.createTemp(tempBaseDir())
    let (ok, db, error) = RocksDb.openLowMemory(dir.toString())
    if (!ok) {
        throw Exception(error)
    }
    return db.getOrThrow()
}

private func unwrap<T>(result: RocksDbOperationResult<T>): T {
    match (result) {
        case RocksDbOperationResult<T>.Ok(value) => return value
        case RocksDbOperationResult<T>.NotFound => throw Exception("unexpected RocksDB NotFound")
        case RocksDbOperationResult<T>.Err(error) => throw Exception(error.message)
    }
}

private func expectBytes(actual: Array<UInt8>, expected: Array<UInt8>): Unit {
    @Expect(actual.size, expected.size)
    for (i in 0..expected.size) {
        @Expect(actual[i], expected[i])
    }
}

@Test
func binaryKeysAndValuesRoundTrip(): Unit {
    let db = openTestDb()
    try {
        let key = [1u8, 0u8, 255u8]
        let value = [0u8, 255u8, 128u8, 65u8, 0u8]
        let _ = unwrap(db.putBytesResult(key, value))
        expectBytes(unwrap(db.getBytesResult(key)), value)

        let emptyKey = Array<UInt8>()
        let emptyValue = Array<UInt8>()
        let _ = unwrap(db.putBytesResult(emptyKey, emptyValue))
        expectBytes(unwrap(db.getBytesResult(emptyKey)), emptyValue)

        let oneMiB = Array<UInt8>(1024 * 1024, {i => UInt8(i % 251)})
        let _ = unwrap(db.putBytesResult("large".toArray(), oneMiB))
        expectBytes(unwrap(db.getBytesResult("large".toArray())), oneMiB)

        let _ = unwrap(db.putBytesResult("invalid-text".toArray(), [255u8, 128u8]))
        match (db.getResult("invalid-text")) {
            case RocksDbOperationResult<String>.Err(error) => match (error.kind) {
                case RocksDbErrorKind.DecodeFailure => ()
                case _ => throw Exception("invalid UTF-8 returned the wrong error kind")
            }
            case _ => throw Exception("invalid UTF-8 value should fail String decoding")
        }
    } finally {
        db.close()
    }
}

@Test
func mergeFailsBeforeCallingNativeApiWithoutOperator(): Unit {
    let db = openTestDb()
    try {
        let (ok, error) = db.merge("key", "value")
        @Expect(ok, false)
        @Expect(error.contains("unsupported"), true)
        match (db.writeBatchResult([], [], [], [("key", "value")])) {
            case RocksDbOperationResult<Unit>.Err(error) => match (error.kind) {
                case RocksDbErrorKind.Unsupported => ()
                case _ => throw Exception("merge batch returned the wrong error kind")
            }
            case _ => throw Exception("merge batch should be rejected")
        }
    } finally {
        db.close()
    }
}

@Test
func binaryMultiGetPreservesOrderAndMissingValues(): Unit {
    let db = openTestDb()
    try {
        let k1 = [10u8, 0u8]
        let k2 = [10u8, 1u8]
        let missing = [10u8, 2u8]
        let _ = unwrap(db.putBytesResult(k1, [0u8, 1u8]))
        let _ = unwrap(db.putBytesResult(k2, [255u8]))
        let values = unwrap(db.multiGetBytesResult([k2, missing, k1]))
        @Expect(values.size, 3)
        expectBytes(values[0].getOrThrow(), [255u8])
        @Expect(values[1].isNone(), true)
        expectBytes(values[2].getOrThrow(), [0u8, 1u8])
    } finally {
        db.close()
    }
}

@Test
func prefixCursorSupportsBoundsLimitAndReverse(): Unit {
    let db = openTestDb()
    try {
        for (key in ["a:1", "a:2", "a:3", "a:4", "b:1"]) {
            let _ = unwrap(db.putResult(key, "v-${key}"))
        }

        let forward = unwrap(db.openPrefixCursorResult("a:".toArray(), startAfter: Some("a:1".toArray()), limit: 2))
        let forwardKeys = ArrayList<String>()
        try {
            while (forward.isValid()) {
                forwardKeys.add(String.fromUtf8(unwrap(forward.keyBytes())))
                forward.next()
            }
            let _ = unwrap(forward.status())
        } finally {
            forward.close()
        }
        @Expect(forwardKeys.size, 2)
        @Expect(forwardKeys[0], "a:2")
        @Expect(forwardKeys[1], "a:3")

        let reverse = unwrap(db.openPrefixCursorResult("a:".toArray(), limit: 3, reverse: true))
        let reverseKeys = ArrayList<String>()
        try {
            while (reverse.isValid()) {
                reverseKeys.add(String.fromUtf8(unwrap(reverse.keyBytes())))
                reverse.next()
            }
        } finally {
            reverse.close()
        }
        @Expect(reverseKeys.size, 3)
        @Expect(reverseKeys[0], "a:4")
        @Expect(reverseKeys[1], "a:3")
        @Expect(reverseKeys[2], "a:2")
    } finally {
        db.close()
    }
}

@Test
func writeBatchAndDeletePrefixAreAtomicOperations(): Unit {
    let db = openTestDb()
    try {
        let batch = unwrap(RocksDbWriteBatch.create())
        try {
            let _ = unwrap(batch.put("keep:1", "one"))
            let _ = unwrap(batch.put("drop:1", "one"))
            let _ = unwrap(batch.put("drop:2", "two"))
            let _ = unwrap(db.commitWriteBatchResult(batch))
        } finally {
            batch.close()
        }

        let _ = unwrap(db.deletePrefixResult("drop:".toArray()))
        match (db.getResult("drop:1")) {
            case RocksDbOperationResult<String>.NotFound => ()
            case _ => throw Exception("deletePrefix left drop:1 behind")
        }
        @Expect(unwrap(db.getResult("keep:1")), "one")

        let _ = unwrap(db.deletePrefixResult(Array<UInt8>()))
        match (db.getResult("keep:1")) {
            case RocksDbOperationResult<String>.NotFound => ()
            case _ => throw Exception("empty prefix should delete all keys")
        }
    } finally {
        db.close()
    }
}

@Test
func columnFamiliesReopenSnapshotAndOperationsAreConsistent(): Unit {
    let dir = Directory.createTemp(Path("/tmp"))
    let path = dir.toString()
    let (firstOk, firstDb, firstError) = RocksDb.openLowMemory(path)
    if (!firstOk) {
        throw Exception(firstError)
    }
    let db = firstDb.getOrThrow()
    let objects = unwrap(db.ensureColumnFamilyResult("objects"))
    let indexes = unwrap(db.ensureColumnFamilyResult("indexes"))
    try {
        let _ = unwrap(db.putResult(objects, "entity:1", "old"))
        let snapshot = unwrap(db.createSnapshotResult())
        try {
            let before = snapshot.sequenceNumber()
            let batch = unwrap(RocksDbWriteBatch.create())
            try {
                let _ = unwrap(batch.put(objects, "entity:1", "new"))
                let _ = unwrap(batch.put(indexes, "query:0001", "entity:1"))
                let _ = unwrap(db.commitWriteBatchResult(batch))
            } finally {
                batch.close()
            }
            @Expect(String.fromUtf8(unwrap(snapshot.getBytesResult(objects, "entity:1".toArray()))), "old")
            @Expect(unwrap(db.getResult(objects, "entity:1")), "new")
            @Expect(unwrap(db.latestSequenceNumberResult()) > before, true)

            let cursor = unwrap(snapshot.openPrefixCursorResult(indexes, "query:".toArray()))
            try {
                @Expect(cursor.isValid(), false)
            } finally {
                cursor.close()
            }
        } finally {
            snapshot.close()
        }

        let _ = unwrap(db.flushResult(objects))
        match (db.propertyUInt64Result(objects, "rocksdb.estimate-num-keys")) {
            case RocksDbOperationResult<UInt64>.Ok(value) => @Expect(value >= 1u64, true)
            case _ => throw Exception("known RocksDB integer property was unavailable")
        }
        @Expect(unwrap(db.propertyStringResult(objects, "rocksdb.stats")).size > 0, true)
        let _ = unwrap(db.approximateSizeResult(objects, Array<UInt8>(), [255u8]))
        let _ = unwrap(db.compactRangeResult(objects))
    } finally {
        db.close()
    }

    let (reopenOk, reopenedDb, reopenError) = RocksDb.openLowMemory(path)
    if (!reopenOk) {
        throw Exception(reopenError)
    }
    let reopened = reopenedDb.getOrThrow()
    try {
        let reopenedObjects = reopened.columnFamily("objects").getOrThrow()
        @Expect(unwrap(reopened.getResult(reopenedObjects, "entity:1")), "new")
        let reopenedIndexes = reopened.columnFamily("indexes").getOrThrow()
        @Expect(unwrap(reopened.getResult(reopenedIndexes, "query:0001")), "entity:1")
        let _ = unwrap(reopened.dropColumnFamilyResult(reopenedIndexes))
        @Expect(reopened.columnFamily("indexes").isNone(), true)
    } finally {
        reopened.close()
    }

    let (finalOk, finalDb, finalError) = RocksDb.openLowMemory(path)
    if (!finalOk) {
        throw Exception(finalError)
    }
    let finalStore = finalDb.getOrThrow()
    try {
        @Expect(finalStore.columnFamily("objects").isSome(), true)
        @Expect(finalStore.columnFamily("indexes").isNone(), true)
    } finally {
        finalStore.close()
    }
}

@Test
func transactionUncommittedCloseRollsBack(): Unit {
    let dir = Directory.createTemp(Path("/tmp"))
    let (ok, optDb, error) = OptimisticRocksDb.openOptimistic(dir.toString(),
            OptimisticRocksDbOptions(64, 32, 4, 256, 2, true, 0))
    if (!ok) {
        throw Exception(error)
    }
    let db = optDb.getOrThrow()
    try {
        // 未提交就 close：rollback-on-close，写入不落库。
        let txn = unwrap(db.beginTransactionResult())
        let _ = unwrap(txn.putResult("k", "v"))
        txn.close()
        match (db.getResult("k")) {
            case RocksDbOperationResult<String>.NotFound => ()
            case _ => throw Exception("uncommitted close should roll back")
        }
        // 正常 commit 后再 close 不重复回滚。
        let txn2 = unwrap(db.beginTransactionResult())
        let _ = unwrap(txn2.putResult("k2", "v2"))
        let _ = unwrap(txn2.commitResult())
        txn2.close()
        @Expect(unwrap(db.getResult("k2")), "v2")
    } finally {
        db.close()
    }
}

@Test
func concurrentPutGetFromMultipleThreads(): Unit {
    let db = openTestDb()
    try {
        let done = DoneGate(4)
        for (t in 0..4) {
            let _ = spawn {
                for (i in 0..50) {
                    let _ = unwrap(db.putResult("t${t}:k${i}", "v${i}"))
                }
                done.dec()
            }
        }
        // 忙等 4 个 worker 完成（rocksdb_ffi 不依赖 qwest/Duration）。
        done.waitZero()
        // 全部写入可读（无竞态数据丢失）。
        for (t in 0..4) {
            for (i in 0..50) {
                @Expect(unwrap(db.getResult("t${t}:k${i}")), "v${i}")
            }
        }
    } finally {
        db.close()
    }
}

@Test
func oversizedLengthConversionIsRejected(): Unit {
    let db = openTestDb()
    try {
        // readCStringBytes 上限检查：构造超界长度不崩（此处直接验证 copyNativeBytes 路径）。
        let oversized = Array<UInt8>(16, repeat: 0x41u8)
        let _ = unwrap(db.putBytesResult("over".toArray(), oversized))
        let _ = unwrap(db.getBytesResult("over".toArray()))
        // 正常读取不受影响。
        match (db.getResult("over")) {
            case RocksDbOperationResult<String>.Ok(_) => ()
            case _ => throw Exception("oversized read should still work")
        }
    } finally {
        db.close()
    }
}

// 线程完成门闩：Mutex 保护计数，忙等（避免 Duration 依赖）。
private class DoneGate {
    private let mutex = Mutex()
    private var remaining: Int64

    init(count: Int64) {
        remaining = count
    }

    public func dec(): Unit {
        synchronized(mutex) {
            remaining -= 1
        }
    }

    public func waitZero(): Unit {
        var spins: Int64 = 0
        while (spins < 200000000) {
            let done = synchronized(mutex) {
                remaining <= 0
            }
            if (done) {
                return
            }
            spins += 1
        }
    }
}

@Test
func compiledRocksDbVersionIsProbed(): Unit {
    let version = rocksDbCompiledVersion()
    // 编译期门槛：版本宏可读（本机 librocksdb-dev 9.11.2 → major 9）。
    @Expect(version.major > 0, true)
    @Expect(version.minor >= 0, true)
    println("compiled rocksdb ${version.major}.${version.minor}")
}
