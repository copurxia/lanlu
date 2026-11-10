package lanlu_client_next.net

import lanlu_client_next.storage.{ObjectCodec, ObjectRepository, StorageKeyCodec, StorageScope}
import rocksdb_ffi.{RocksDb, RocksDbColumnFamily, RocksDbOperationResult, RocksDbError, RocksDbErrorKind,
    RocksDbPrefixCursor, RocksDbWriteBatch}
import std.collection.ArrayList
import std.convert.Parsable
import std.fs.{Path, exists}
import std.time.DateTime

public let BLOB_TOUCH_THROTTLE_MS: Int64 = 10 * 60 * 1000 // 命中更新访问时间节流：每 10 分钟一次

// 文件缓存元数据记录：大块二进制本体继续走文件系统原子 rename，RocksDB 只管理元数据。
public class BlobCacheEntry {
    public var blobKey: String = "" // logical key（图片 relKey / 字幕 stableKey 等）
    public var path: String = "" // 定稿文件路径（相对缓存根或绝对路径）
    public var size: Int64 = 0
    public var lastAccessMs: Int64 = 0
    public var etag: String = "" // 媒体验证器（能取得时必须使用）
    public var lastModified: String = ""
    public var checksum: String = "" // 可选校验和
    public var state: String = "published" // published / orphan
    public var schema: String = "blob/1"
}

private class BlobCacheCodec <: ObjectCodec<BlobCacheEntry> {
    public func typeName(): String {
        return "blob"
    }

    public func schemaVersion(): UInt32 {
        return 1u32
    }

    public func encode(value: BlobCacheEntry): RocksDbOperationResult<Array<UInt8>> {
        return RocksDbOperationResult<Array<UInt8>>.Ok(
            StorageKeyCodec.encodeStrings(
                [
                    value.blobKey,
                    value.path,
                    "${value.size}",
                    "${value.lastAccessMs}",
                    value.etag,
                    value.lastModified,
                    value.checksum,
                    value.state,
                    value.schema
                ]
            )
        )
    }

    public func decode(payload: Array<UInt8>, schemaVersion: UInt32): RocksDbOperationResult<BlobCacheEntry> {
        if (schemaVersion != 1u32) {
            return decodeError("unsupported blob schema")
        }
        let raw = match (StorageKeyCodec.decode(payload)) {
            case Some(value) => value
            case None => return decodeError("malformed blob payload")
        }
        if (raw.size != 9) {
            return decodeError("blob payload field count is invalid")
        }
        try {
            let fields = Array<String>(raw.size, {i => String.fromUtf8(raw[i])})
            let entry = BlobCacheEntry()
            entry.blobKey = fields[0]
            entry.path = fields[1]
            entry.size = Int64.parse(fields[2])
            entry.lastAccessMs = Int64.parse(fields[3])
            entry.etag = fields[4]
            entry.lastModified = fields[5]
            entry.checksum = fields[6]
            entry.state = fields[7]
            entry.schema = fields[8]
            return RocksDbOperationResult<BlobCacheEntry>.Ok(entry)
        } catch (_: Exception) {
            return decodeError("blob payload contains invalid UTF-8 or numbers")
        }
    }

    private static func decodeError(message: String): RocksDbOperationResult<BlobCacheEntry> {
        return RocksDbOperationResult<BlobCacheEntry>.Err(RocksDbError(RocksDbErrorKind.DecodeFailure, message))
    }
}

// 文件缓存元数据仓库：对象主记录 + (lastAccess, blobKey) LRU 有序索引。
// LRU 索引 key = {server}/{account}/blob-lru/{lastAccess 大端 8 字节}/{blobKey}，
// RocksDB 字节序等于业务排序序，cursor 从最旧项分批淘汰，不再 Directory.readFrom + sort。
public class BlobCacheStore {
    private let db: RocksDb
    private let objects: RocksDbColumnFamily
    private let indexes: RocksDbColumnFamily

    init(db: RocksDb, objects: RocksDbColumnFamily, indexes: RocksDbColumnFamily) {
        this.db = db
        this.objects = objects
        this.indexes = indexes
    }

    // 定稿成功后发布 metadata + LRU 索引（同 batch 原子提交）。
    public func publish(
        serverHash: String,
        accountScope: String,
        entry: BlobCacheEntry,
        lastAccessMs!: Int64 = currentTimeMs()
    ): Bool {
        if (entry.blobKey.size == 0 || entry.path.size == 0) {
            return false
        }
        entry.lastAccessMs = if (lastAccessMs > 0) {
            lastAccessMs
        } else {
            currentTimeMs()
        }
        let scope = StorageScope(serverHash, accountScope)
        let repo = ObjectRepository<BlobCacheEntry>(db, scope, BlobCacheCodec(), columnFamily: Some(objects))
        let batch = match (RocksDbWriteBatch.create()) {
            case RocksDbOperationResult<RocksDbWriteBatch>.Ok(value) => value
            case _ => return false
        }
        try {
            match (repo.putInto(batch, entry.blobKey, entry)) {
                case RocksDbOperationResult<Unit>.Ok(_) => ()
                case _ =>
                    batch.close()
                    return false
            }
            let lruKey = lruIndexKey(serverHash, accountScope, entry.lastAccessMs, entry.blobKey)
            match (batch.putBytes(indexes, lruKey, Array<UInt8>())) {
                case RocksDbOperationResult<Unit>.Ok(_) => ()
                case _ =>
                    batch.close()
                    return false
            }
            return match (db.commitWriteBatchResult(batch)) {
                case RocksDbOperationResult<Unit>.Ok(_) => true
                case _ => false
            }
        } finally {
            batch.close()
        }
    }

    // 命中更新访问时间，节流：距上次不足 10 分钟不写 DB（避免每次绘制都写 RocksDB）。
    public func touch(
        serverHash: String,
        accountScope: String,
        blobKey: String,
        nowMs!: Int64 = currentTimeMs()
    ): Bool {
        let scope = StorageScope(serverHash, accountScope)
        let repo = ObjectRepository<BlobCacheEntry>(db, scope, BlobCacheCodec(), columnFamily: Some(objects))
        let current = match (repo.get(blobKey)) {
            case RocksDbOperationResult<BlobCacheEntry>.Ok(value) => value
            case _ => return false
        }
        if (nowMs - current.lastAccessMs < BLOB_TOUCH_THROTTLE_MS) {
            return true // 节流：不更新
        }
        let batch = match (RocksDbWriteBatch.create()) {
            case RocksDbOperationResult<RocksDbWriteBatch>.Ok(value) => value
            case _ => return false
        }
        try {
            // 删除旧 LRU 索引项，写新对象与新索引。
            let oldLru = lruIndexKey(serverHash, accountScope, current.lastAccessMs, blobKey)
            let _ = batch.deleteBytes(indexes, oldLru)
            let updated = BlobCacheEntry()
            updated.blobKey = current.blobKey
            updated.path = current.path
            updated.size = current.size
            updated.lastAccessMs = nowMs
            updated.etag = current.etag
            updated.lastModified = current.lastModified
            updated.checksum = current.checksum
            updated.state = current.state
            updated.schema = current.schema
            match (repo.putInto(batch, blobKey, updated)) {
                case RocksDbOperationResult<Unit>.Ok(_) => ()
                case _ =>
                    batch.close()
                    return false
            }
            let newLru = lruIndexKey(serverHash, accountScope, nowMs, blobKey)
            match (batch.putBytes(indexes, newLru, Array<UInt8>())) {
                case RocksDbOperationResult<Unit>.Ok(_) => ()
                case _ =>
                    batch.close()
                    return false
            }
            return match (db.commitWriteBatchResult(batch)) {
                case RocksDbOperationResult<Unit>.Ok(_) => true
                case _ => false
            }
        } finally {
            batch.close()
        }
    }

    public func get(
        serverHash: String,
        accountScope: String,
        blobKey: String
    ): Option<BlobCacheEntry> {
        let scope = StorageScope(serverHash, accountScope)
        let repo = ObjectRepository<BlobCacheEntry>(db, scope, BlobCacheCodec(), columnFamily: Some(objects))
        match (repo.get(blobKey)) {
            case RocksDbOperationResult<BlobCacheEntry>.Ok(value) => return Some(value)
            case _ => return None
        }
    }

    // LRU 淘汰：从最旧项开始分批返回候选（含 path/size），供调用方删文件后再 ack 删记录。
    public func evictOldestBatch(
        serverHash: String,
        accountScope: String,
        limit!: Int64 = 64
    ): ArrayList<BlobCacheEntry> {
        let out = ArrayList<BlobCacheEntry>()
        let prefix = lruPrefix(serverHash, accountScope)
        let cursor = match (db.openPrefixCursorResult(indexes, prefix, limit: limit)) {
            case RocksDbOperationResult<RocksDbPrefixCursor>.Ok(value) => value
            case _ => return out
        }
        try {
            while (cursor.isValid() && out.size < limit) {
                let key = match (cursor.keyBytes()) {
                    case RocksDbOperationResult<Array<UInt8>>.Ok(value) => value
                    case _ => break
                }
                match (blobKeyFromLruKey(key, serverHash, accountScope)) {
                    case Some(blobKey) =>
                        match (get(serverHash, accountScope, blobKey)) {
                            case Some(entry) => out.add(entry)
                            case None => ()
                        }
                    case None => ()
                }
                cursor.next()
            }
        } finally {
            cursor.close()
        }
        out
    }

    // 删除对象记录 + LRU 索引项（文件已由调用方删除）。
    public func ackEvicted(serverHash: String, accountScope: String, blobKey: String): Bool {
        let scope = StorageScope(serverHash, accountScope)
        let repo = ObjectRepository<BlobCacheEntry>(db, scope, BlobCacheCodec(), columnFamily: Some(objects))
        let current = match (repo.get(blobKey)) {
            case RocksDbOperationResult<BlobCacheEntry>.Ok(value) => value
            case _ => return false
        }
        let batch = match (RocksDbWriteBatch.create()) {
            case RocksDbOperationResult<RocksDbWriteBatch>.Ok(value) => value
            case _ => return false
        }
        try {
            let _ = batch.deleteBytes(indexes, lruIndexKey(serverHash, accountScope, current.lastAccessMs, blobKey))
            match (repo.deleteInto(batch, blobKey)) {
                case RocksDbOperationResult<Unit>.Ok(_) => ()
                case _ =>
                    batch.close()
                    return false
            }
            return match (db.commitWriteBatchResult(batch)) {
                case RocksDbOperationResult<Unit>.Ok(_) => true
                case _ => false
            }
        } finally {
            batch.close()
        }
    }

    // 启动一致性检查（分批）：metadata 指向缺失文件则删记录；返回删除条数。
    // 调用方分批调用直到返回 0，避免一次性把全部对象扫入数组；cursor 流式遍历
    // 不构造全量对象数组，已存在文件的记录快速跳过。
    public func cleanupMissingFiles(
        serverHash: String,
        accountScope: String,
        limit!: Int64 = 64
    ): Int64 {
        var removed: Int64 = 0
        let scope = StorageScope(serverHash, accountScope)
        let repo = ObjectRepository<BlobCacheEntry>(db, scope, BlobCacheCodec(), columnFamily: Some(objects))
        let cursor = match (db.openPrefixCursorResult(objects, repo.entityPrefix(), limit: 4096)) {
            case RocksDbOperationResult<RocksDbPrefixCursor>.Ok(value) => value
            case _ => return 0
        }
        try {
            while (cursor.isValid() && removed < limit) {
                let key = match (cursor.keyBytes()) {
                    case RocksDbOperationResult<Array<UInt8>>.Ok(value) => value
                    case _ => break
                }
                let id = blobKeyFromObjectKey(key)
                match (id) {
                    case Some(blobKey) =>
                        match (get(serverHash, accountScope, blobKey)) {
                            case Some(entry) =>
                                if (entry.path.size == 0 || !exists(Path(entry.path))) {
                                    if (ackEvicted(serverHash, accountScope, blobKey)) {
                                        removed += 1
                                    }
                                }
                            case None => ()
                        }
                    case None => ()
                }
                cursor.next()
            }
        } finally {
            cursor.close()
        }
        removed
    }

    public func clearScope(serverHash: String, accountScope: String): Unit {
        let _ = db.deletePrefixResult(objects, StorageKeyCodec.encodeStrings(["objects", serverHash, accountScope]))
        let _ = db.deletePrefixResult(indexes, StorageKeyCodec.encodeStrings(["indexes", serverHash, accountScope]))
    }

    private static func lruPrefix(serverHash: String, accountScope: String): Array<UInt8> {
        StorageKeyCodec.encodeStrings(["indexes", serverHash, accountScope, "blob-lru"])
    }

    private static func lruIndexKey(serverHash: String, accountScope: String, lastAccessMs: Int64,
        blobKey: String): Array<UInt8> {
        let normalized = if (lastAccessMs > 0) {
            lastAccessMs
        } else {
            0
        }
        StorageKeyCodec.encode(
            [
                "indexes".toArray(),
                serverHash.toArray(),
                accountScope.toArray(),
                "blob-lru".toArray(),
                StorageKeyCodec.rankBytes(UInt64(normalized)),
                blobKey.toArray()
            ]
        )
    }

    // 从 LRU 索引 key 反解 blobKey（第 6 个组件：indexes/{server}/{account}/blob-lru/{rank}/{blobKey}）。
    private static func blobKeyFromLruKey(key: Array<UInt8>, serverHash: String, accountScope: String): Option<String> {
        match (StorageKeyCodec.decode(key)) {
            case Some(parts) =>
                if (parts.size != 6) {
                    return None
                }
                try {
                    return Some(String.fromUtf8(parts[5]))
                } catch (_: Exception) {
                    return None
                }
            case None => return None
        }
    }

    // 从对象 key 反解 blobKey（第 5 个组件：objects/{server}/{account}/blob/{blobKey}）。
    private static func blobKeyFromObjectKey(key: Array<UInt8>): Option<String> {
        match (StorageKeyCodec.decode(key)) {
            case Some(parts) =>
                if (parts.size != 5) {
                    return None
                }
                let typeName = try {
                    String.fromUtf8(parts[3])
                } catch (_: Exception) {
                    ""
                }
                if (typeName != "blob") {
                    return None
                }
                try {
                    return Some(String.fromUtf8(parts[4]))
                } catch (_: Exception) {
                    return None
                }
            case None => return None
        }
    }

    private static func currentTimeMs(): Int64 {
        return DateTime.now().toUnixTimeStamp().toMilliseconds()
    }
}
