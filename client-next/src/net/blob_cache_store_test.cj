package lanlu_client_next.net

import std.collection.ArrayList
import std.fs.{Directory, File, OpenMode, Path, exists, removeIfExists}
import std.time.DateTime

private func blobEntry(blobKey: String, path: String, size: Int64): BlobCacheEntry {
    let entry = BlobCacheEntry()
    entry.blobKey = blobKey
    entry.path = path
    entry.size = size
    entry.etag = "etag-${blobKey}"
    entry.checksum = "sum-${blobKey}"
    return entry
}

private func touchFile(path: String, size: Int64): Unit {
    let f = File(Path(path), OpenMode.Write)
    try {
        let bytes = Array<UInt8>(size, repeat: 0x41u8)
        f.write(bytes)
        f.flush()
    } finally {
        f.close()
    }
}

@Test
func blobPublishTouchAndLruOrdering(): Unit {
    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    let store = cache.blob()
    // 发布三条，访问时间递增。
    @Expect(store.publish("h1", "u1", blobEntry("img:a", "/tmp/img-a.img", 100), lastAccessMs: 100), true)
    @Expect(store.publish("h1", "u1", blobEntry("img:b", "/tmp/img-b.img", 200), lastAccessMs: 200), true)
    @Expect(store.publish("h1", "u1", blobEntry("img:c", "/tmp/img-c.img", 300), lastAccessMs: 300), true)

    // 读回元数据。
    let a = store.get("h1", "u1", "img:a").getOrThrow()
    @Expect(a.size, 100)
    @Expect(a.etag, "etag-img:a")
    @Expect(a.schema, "blob/1")

    // LRU 顺序：最旧在前。
    let oldest = store.evictOldestBatch("h1", "u1", limit: 2)
    @Expect(oldest.size, 2)
    @Expect(oldest[0].blobKey, "img:a")
    @Expect(oldest[1].blobKey, "img:b")

    // touch 把 img:a 推到最末（最近访问），节流：短间隔内不更新。
    @Expect(store.touch("h1", "u1", "img:a", nowMs: 350), true)
    @Expect(store.get("h1", "u1", "img:a").getOrThrow().lastAccessMs, 100) // 节流：未更新
    // 超过节流窗口后更新。
    @Expect(store.touch("h1", "u1", "img:a", nowMs: 350 + BLOB_TOUCH_THROTTLE_MS + 1), true)
    @Expect(store.get("h1", "u1", "img:a").getOrThrow().lastAccessMs, 350 + BLOB_TOUCH_THROTTLE_MS + 1)

    // touch 后 LRU：img:b 最旧。
    let after = store.evictOldestBatch("h1", "u1", limit: 3)
    @Expect(after[0].blobKey, "img:b")
    cache.close()
}

@Test
func blobEvictAcksRecordAndIndexAtomically(): Unit {
    let path = Directory.createTemp(Path("/tmp")).toString()
    let cache = OfflineCache.open(path).getOrThrow()
    let store = cache.blob()
    @Expect(store.publish("h1", "u1", blobEntry("img:a", "/tmp/img-a.img", 100), lastAccessMs: 100), true)
    @Expect(store.publish("h1", "u1", blobEntry("img:b", "/tmp/img-b.img", 200), lastAccessMs: 200), true)

    @Expect(store.ackEvicted("h1", "u1", "img:a"), true)
    @Expect(store.get("h1", "u1", "img:a").isNone(), true)
    // 剩余 LRU 从 img:b 开始。
    let rest = store.evictOldestBatch("h1", "u1", limit: 4)
    @Expect(rest.size, 1)
    @Expect(rest[0].blobKey, "img:b")
    // 账号隔离。
    @Expect(store.get("h1", "u2", "img:b").isNone(), true)
    cache.close()
}

@Test
func blobConsistencyCleanupRemovesMissingFilesInBatches(): Unit {
    let dir = Directory.createTemp(Path("/tmp"))
    let cache = OfflineCache.open(dir.toString()).getOrThrow()
    let store = cache.blob()
    // 创建真实文件 + 缺失文件的记录。
    let alivePath = "${dir.toString()}/alive.img"
    touchFile(alivePath, 64)
    @Expect(store.publish("h1", "u1", blobEntry("img:alive", alivePath, 64), lastAccessMs: 100), true)
    @Expect(store.publish("h1", "u1", blobEntry("img:missing", "${dir.toString()}/gone.img", 32),
        lastAccessMs: 200), true)
    @Expect(store.publish("h1", "u2", blobEntry("img:missing2", "${dir.toString()}/gone2.img", 16),
        lastAccessMs: 300), true)

    // 分批一致性清理：仅删缺失文件的记录（u1 的 missing，u2 的记录保留）。
    var removed: Int64 = store.cleanupMissingFiles("h1", "u1", limit: 1)
    @Expect(removed, 1)
    removed = store.cleanupMissingFiles("h1", "u1", limit: 4)
    @Expect(removed, 0) // 只剩 alive，文件存在
    @Expect(store.get("h1", "u1", "img:missing").isNone(), true)
    @Expect(store.get("h1", "u1", "img:alive").isSome(), true)
    @Expect(store.get("h1", "u2", "img:missing2").isSome(), true)
    cache.close()
}
