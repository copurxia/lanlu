package lanlu.infrastructure.kv

import std.sync.*
import std.collection.*
import std.convert.*
import std.time.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.contexts.task.domain.*
import lanlu.contexts.task.infrastructure.persistence.TaskDao
import lanlu.shared.utils.*

private class TaskGroupKVRecord {
    public var value: String = ""
    public var createdAt: Int64 = 0
    public var ttlSeconds: Int64 = 0
}

private class TaskGroupKVRecordCodec {
    public static func encode(record: TaskGroupKVRecord): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("value").writeValue(record.value)
        w.writeName("created_at").writeValue(record.createdAt)
        w.writeName("ttl_seconds").writeValue(record.ttlSeconds)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    public static func decode(payload: String): Option<TaskGroupKVRecord> {
        let trimmed = payload.trimAscii()
        if (trimmed.size == 0) {
            return None
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let reader = JsonReader(buf)
            if (reader.peek() != Some(BeginObject)) {
                return None
            }

            let record = TaskGroupKVRecord()
            reader.startObject()
            while (reader.peek() != EndObject) {
                let name = reader.readName()
                match (name) {
                    case "value" => record.value = reader.readValue<String>()
                    case "created_at" => record.createdAt = reader.readValue<Int64>()
                    case "ttl_seconds" => record.ttlSeconds = reader.readValue<Int64>()
                    case _ => reader.skip()
                }
            }
            reader.endObject()
            return Some(record)
        } catch (_: Exception) {
            return None
        }
    }
}

/**
 * Task 组 KV 存储（RocksDB-backed）
 *
 * - 使用 LocalKVService 统一复用共享的 RocksDB 实例
 * - 通过 RocksDB iterator 前缀扫描实现 getKeys/deleteGroup
 * - acquire/release 仅负责组生命周期引用计数，不再限制 CRUD 访问
 */
public class TaskGroupKVStore <: TaskKVStore {
    private static let logger = getLogger("task_group_kv_store")
    private static let namespace = "task_group_kv"
    private static var instance: Option<TaskGroupKVStore> = None
    private static let instanceMutex: Mutex = Mutex()

    private let refCountMutex: Mutex = Mutex()
    private let operationMutexMapGuard: Mutex = Mutex()
    private var operationMutexMap: HashMap<String, Mutex>
    private var groupRefCounts: HashMap<String, Int32>

    private init() {
        operationMutexMap = HashMap<String, Mutex>()
        groupRefCounts = HashMap<String, Int32>()
    }

    public static func getInstance(): TaskGroupKVStore {
        instanceMutex.lock()
        match (instance) {
            case Some(s) =>
                instanceMutex.unlock()
                return s
            case None =>
                let s = TaskGroupKVStore()
                instance = Some(s)
                instanceMutex.unlock()
                return s
        }
    }

    public func acquireGroup(groupId: String): Unit {
        let normalizedGroupId = normalizeGroupId(groupId)
        if (normalizedGroupId.size == 0) {
            return
        }

        refCountMutex.lock()
        match (groupRefCounts.get(normalizedGroupId)) {
            case Some(count) => groupRefCounts[normalizedGroupId] = count + 1
            case None => groupRefCounts[normalizedGroupId] = 1
        }
        refCountMutex.unlock()
    }

    public func releaseGroup(groupId: String): Unit {
        let normalizedGroupId = normalizeGroupId(groupId)
        if (normalizedGroupId.size == 0) {
            return
        }

        var shouldDeleteGroup = false
        refCountMutex.lock()
        match (groupRefCounts.get(normalizedGroupId)) {
            case Some(count) =>
                if (count <= 1) {
                    groupRefCounts.remove(normalizedGroupId)
                    shouldDeleteGroup = true
                } else {
                    groupRefCounts[normalizedGroupId] = count - 1
                }
            case None => ()
        }
        refCountMutex.unlock()

        if (shouldDeleteGroup && !TaskDao.existsNonTerminalTasksByGroupId(normalizedGroupId)) {
            deleteGroup(normalizedGroupId)
        }
    }

    public func set(groupId: String, key: String, value: String, ttlSeconds: Int64): Bool {
        let normalizedGroupId = normalizeGroupId(groupId)
        let normalizedKey = normalizeKey(key)
        if (normalizedGroupId.size == 0 || normalizedKey.size == 0) {
            return false
        }

        let groupMutex = getOperationMutex(normalizedGroupId)
        groupMutex.lock()
        try {
            return putRecordNormalized(normalizedGroupId, normalizedKey, value, ttlSeconds)
        } finally {
            groupMutex.unlock()
        }
    }

    public func get(groupId: String, key: String): Option<String> {
        let normalizedGroupId = normalizeGroupId(groupId)
        let normalizedKey = normalizeKey(key)
        if (normalizedGroupId.size == 0 || normalizedKey.size == 0) {
            return None
        }

        let groupMutex = getOperationMutex(normalizedGroupId)
        groupMutex.lock()
        try {
            return getValueNormalized(normalizedGroupId, normalizedKey)
        } finally {
            groupMutex.unlock()
        }
    }

    public func delete(groupId: String, key: String): Bool {
        let normalizedGroupId = normalizeGroupId(groupId)
        let normalizedKey = normalizeKey(key)
        if (normalizedGroupId.size == 0 || normalizedKey.size == 0) {
            return false
        }

        let groupMutex = getOperationMutex(normalizedGroupId)
        groupMutex.lock()
        try {
            return deleteNormalizedKey(buildStorageKey(normalizedGroupId, normalizedKey))
        } finally {
            groupMutex.unlock()
        }
    }

    public func deleteGroup(groupId: String): Unit {
        let normalizedGroupId = normalizeGroupId(groupId)
        if (normalizedGroupId.size == 0) {
            return
        }

        let groupMutex = getOperationMutex(normalizedGroupId)
        groupMutex.lock()
        try {
            let prefix = buildGroupPrefix(normalizedGroupId)
            let deleted = deleteGroupEntriesNormalized(normalizedGroupId, prefix)
            if (!deleted) {
                logger.warn("task kv group delete failed", ("group_id", normalizedGroupId))
            }
        } finally {
            groupMutex.unlock()
        }

        refCountMutex.lock()
        try {
            groupRefCounts.remove(normalizedGroupId)
        } finally {
            refCountMutex.unlock()
        }
    }

    /**
     * 批量写入同一 group 内的多个 key
     *
     * 一次加锁 + N 次 putRecord + 一次解锁，避免 N 次独立 set 导致的重复加锁。
     */
    public func setMulti(groupId: String, keys: Array<String>, values: Array<String>, ttlSeconds: Int64): Bool {
        if (keys.size == 0 || keys.size != values.size) {
            return false
        }
        let normalizedGroupId = normalizeGroupId(groupId)
        if (normalizedGroupId.size == 0) {
            return false
        }

        let groupMutex = getOperationMutex(normalizedGroupId)
        groupMutex.lock()
        try {
            var allOk = true
            var i: Int64 = 0
            while (i < keys.size) {
                let normalizedKey = normalizeKey(keys[i])
                if (normalizedKey.size > 0) {
                    if (!putRecordNormalized(normalizedGroupId, normalizedKey, values[i], ttlSeconds)) {
                        allOk = false
                    }
                }
                i += 1
            }
            return allOk
        } finally {
            groupMutex.unlock()
        }
    }

    public func insertIfAbsent(groupId: String, key: String, value: String, ttlSeconds: Int64): Bool {
        let normalizedGroupId = normalizeGroupId(groupId)
        let normalizedKey = normalizeKey(key)
        if (normalizedGroupId.size == 0 || normalizedKey.size == 0) {
            return false
        }

        let groupMutex = getOperationMutex(normalizedGroupId)
        groupMutex.lock()
        try {
            match (getRecordNormalized(normalizedGroupId, normalizedKey)) {
                case Some(_) => return false
                case None => return putRecordNormalized(normalizedGroupId, normalizedKey, value, ttlSeconds)
            }
        } finally {
            groupMutex.unlock()
        }
    }

    public func increment(groupId: String, key: String, delta: Int64, ttlSeconds: Int64): Int64 {
        let normalizedGroupId = normalizeGroupId(groupId)
        let normalizedKey = normalizeKey(key)
        if (normalizedGroupId.size == 0 || normalizedKey.size == 0) {
            return -1
        }

        let groupMutex = getOperationMutex(normalizedGroupId)
        groupMutex.lock()
        try {
            var currentValue: Int64 = 0
            match (getRecordNormalized(normalizedGroupId, normalizedKey)) {
                case Some(record) =>
                    try {
                        currentValue = Int64.parse(record.value)
                    } catch (_: Exception) {
                        return -1
                    }
                case None => currentValue = 0
            }

            let nextValue = currentValue + delta
            if (!putRecordNormalized(normalizedGroupId, normalizedKey, nextValue.toString(), ttlSeconds)) {
                return -1
            }
            return nextValue
        } finally {
            groupMutex.unlock()
        }
    }

    public func commitUploadChunk(
        groupId: String,
        chunkKey: String,
        newOffset: Int64,
        uploadedProgress: Int64,
        shouldUpdateProgress: Bool,
        shouldUpdateTimeoutTs: Bool,
        nowTs: Int64,
        ttlSeconds: Int64
    ): UploadChunkCommitResult {
        let result = UploadChunkCommitResult()
        let normalizedGroupId = normalizeGroupId(groupId)
        let normalizedChunkKey = normalizeKey(chunkKey)
        if (normalizedGroupId.size == 0 || normalizedChunkKey.size == 0) {
            return result
        }

        let t0 = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let groupMutex = getOperationMutex(normalizedGroupId)
        logger.debug(
            "[KV] commitUploadChunk waiting for lock",
            ("group_id", normalizedGroupId),
            ("chunk_key", normalizedChunkKey)
        )
        groupMutex.lock()
        let t1 = DateTime.now().toUnixTimeStamp().toMilliseconds()
        logger.debug(
            "[KV] commitUploadChunk acquired lock",
            ("group_id", normalizedGroupId),
            ("chunk_key", normalizedChunkKey),
            ("wait_lock_ms", (t1 - t0).toString())
        )

        try {
            match (getRecordNormalized(normalizedGroupId, normalizedChunkKey)) {
                case Some(_) =>
                    result.inserted = false
                case None =>
                    if (putRecordNormalized(normalizedGroupId, normalizedChunkKey, "1", ttlSeconds)) {
                        result.inserted = true
                    }
            }

            if (result.inserted) {
                var currentValue: Int64 = 0
                match (getRecordNormalized(normalizedGroupId, "uploaded_count")) {
                    case Some(record) =>
                        try {
                            currentValue = Int64.parse(record.value)
                        } catch (_: Exception) {
                            currentValue = 0
                        }
                    case None => currentValue = 0
                }
                result.uploadedChunkCount = currentValue + 1
                let _ = putRecordNormalized(normalizedGroupId, "uploaded_count", result.uploadedChunkCount.toString(), ttlSeconds)
            } else {
                match (getRecordNormalized(normalizedGroupId, "uploaded_count")) {
                    case Some(record) =>
                        try {
                            result.uploadedChunkCount = Int64.parse(record.value)
                        } catch (_: Exception) {
                            result.uploadedChunkCount = 0
                        }
                    case None => result.uploadedChunkCount = 0
                }
            }

            result.writtenOffset = newOffset
            let _ = putRecordNormalized(normalizedGroupId, "written_offset", newOffset.toString(), ttlSeconds)
            if (shouldUpdateProgress) {
                result.updatedProgress = putRecordNormalized(normalizedGroupId, "last_reported_progress", uploadedProgress.toString(), ttlSeconds)
            }
            if (shouldUpdateTimeoutTs) {
                result.updatedTimeoutTs = putRecordNormalized(normalizedGroupId, "last_timeout_extend_ts", nowTs.toString(), ttlSeconds)
            }

            let t2 = DateTime.now().toUnixTimeStamp().toMilliseconds()
            logger.debug(
                "[KV] commitUploadChunk completed",
                ("group_id", normalizedGroupId),
                ("chunk_key", normalizedChunkKey),
                ("inserted", result.inserted.toString()),
                ("uploaded_count", result.uploadedChunkCount.toString()),
                ("wait_lock_ms", (t1 - t0).toString()),
                ("store_call_ms", (t2 - t1).toString())
            )
            return result
        } finally {
            groupMutex.unlock()
        }
    }

    public func hasGroup(groupId: String): Bool {
        let normalizedGroupId = normalizeGroupId(groupId)
        if (normalizedGroupId.size == 0) {
            return false
        }

        refCountMutex.lock()
        try {
            return groupRefCounts.contains(normalizedGroupId)
        } finally {
            refCountMutex.unlock()
        }
    }

    public func getKeys(groupId: String): Array<String> {
        let normalizedGroupId = normalizeGroupId(groupId)
        if (normalizedGroupId.size == 0) {
            return []
        }

        let groupMutex = getOperationMutex(normalizedGroupId)
        groupMutex.lock()
        try {
            let prefix = buildGroupPrefix(normalizedGroupId)
            let entries = scanGroupEntriesNormalized(normalizedGroupId)
            let keys = ArrayList<String>()
            for ((storageKey, payload) in entries) {
                if (storageKey.size <= prefix.size) {
                    continue
                }

                let key = storageKey[prefix.size..storageKey.size]
                match (TaskGroupKVRecordCodec.decode(payload)) {
                    case Some(record) =>
                        if (isExpired(record)) {
                            let _ = deleteNormalizedKey(storageKey)
                        } else {
                            keys.add(key)
                        }
                    case None =>
                        let _ = deleteNormalizedKey(storageKey)
                        logger.warn("task kv record decode failed during key scan; evicted key", ("group_id", normalizedGroupId), ("key", key))
                }
            }
            return keys.toArray()
        } finally {
            groupMutex.unlock()
        }
    }

    /**
     * 批量读取同一 group 内的多个 key
     * 
     * 优化说明：
     * - 一次加锁、一次 multiGet、一次解锁
     * - 避免多次独立 get 导致的重复加锁和 RocksDB 调用
     * - 6次独立读 → 1次批量读，RocksDB I/O 减少83%
     *
     * @param groupId 分组ID
     * @param keys 需要读取的key数组
     * @return 与keys对应的值数组，缺失或过期的key返回None
     */
    public func getMulti(groupId: String, keys: Array<String>): Array<Option<String>> {
        let normalizedGroupId = normalizeGroupId(groupId)
        if (normalizedGroupId.size == 0 || keys.size == 0) {
            return Array<Option<String>>(keys.size, { _ => None })
        }

        let t0 = DateTime.now().toUnixTimeStamp().toMilliseconds()
        
        // 构建完整的存储key
        let storageKeys = Array<String>(keys.size, { i =>
            buildStorageKey(normalizedGroupId, normalizeKey(keys[i]))
        })

        let t1 = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let groupMutex = getOperationMutex(normalizedGroupId)
        
        logger.debug(
            "[KV] getMulti waiting for lock",
            ("group_id", normalizedGroupId),
            ("key_count", keys.size.toString()),
            ("build_keys_ms", (t1 - t0).toString())
        )
        
        groupMutex.lock()
        let t2 = DateTime.now().toUnixTimeStamp().toMilliseconds()
        logger.debug(
            "[KV] getMulti acquired lock",
            ("group_id", normalizedGroupId),
            ("wait_lock_ms", (t2 - t1).toString())
        )
        
        try {
            let storeOpt = LocalKVService.getStore()
            match (storeOpt) {
                case Some(store) =>
                    let t3 = DateTime.now().toUnixTimeStamp().toMilliseconds()
                    // 一次性批量读取
                    let rawValues = store.multiGet(namespace, storageKeys)
                    let t4 = DateTime.now().toUnixTimeStamp().toMilliseconds()
                    
                    logger.debug(
                        "[KV] getMulti multiGet completed",
                        ("group_id", normalizedGroupId),
                        ("key_count", keys.size.toString()),
                        ("rocksdb_ms", (t4 - t3).toString()),
                        ("found_count", rawValues.filter({ v => v.isSome() }).size.toString())
                    )
                    
                    // 解码并检查过期
                    let results = Array<Option<String>>(rawValues.size, { i =>
                        match (rawValues[i]) {
                            case Some(payload) =>
                                match (TaskGroupKVRecordCodec.decode(payload)) {
                                    case Some(record) =>
                                        if (isExpired(record)) {
                                            let _ = deleteNormalizedKey(storageKeys[i])
                                            None
                                        } else {
                                            Some(record.value)
                                        }
                                    case None =>
                                        let _ = deleteNormalizedKey(storageKeys[i])
                                        logger.warn("task kv record decode failed during multiGet", ("group_id", normalizedGroupId), ("key", keys[i]))
                                        None
                                }
                            case None => None
                        }
                    })
                    
                    let t5 = DateTime.now().toUnixTimeStamp().toMilliseconds()
                    logger.debug(
                        "[KV] getMulti completed",
                        ("group_id", normalizedGroupId),
                        ("key_count", keys.size.toString()),
                        ("total_ms", (t5 - t0).toString()),
                        ("build_keys_ms", (t1 - t0).toString()),
                        ("wait_lock_ms", (t2 - t1).toString()),
                        ("store_call_ms", (t4 - t3).toString()),
                        ("post_process_ms", (t5 - t4).toString())
                    )
                    
                    return results
                case None =>
                    logger.warn("task kv unavailable because LocalKVService is not ready")
                    return Array<Option<String>>(keys.size, { _ => None })
            }
        } finally {
            groupMutex.unlock()
        }
    }

    private func getValueNormalized(groupId: String, key: String): Option<String> {
        match (getRecordNormalized(groupId, key)) {
            case Some(record) => return Some(record.value)
            case None => return None
        }
    }

    private func getRecordNormalized(groupId: String, key: String): Option<TaskGroupKVRecord> {
        let storeOpt = LocalKVService.getStore()
        match (storeOpt) {
            case Some(store) =>
                match (store.get(namespace, buildStorageKey(groupId, key))) {
                    case Some(payload) =>
                        match (TaskGroupKVRecordCodec.decode(payload)) {
                            case Some(record) =>
                                if (isExpired(record)) {
                                    let _ = deleteNormalizedKey(buildStorageKey(groupId, key))
                                    return None
                                }
                                return Some(record)
                            case None =>
                                let _ = deleteNormalizedKey(buildStorageKey(groupId, key))
                                logger.warn("task kv record decode failed; evicted key", ("group_id", groupId), ("key", key))
                                return None
                        }
                    case None => return None
                }
            case None =>
                logger.warn("task kv unavailable because LocalKVService is not ready")
                return None
        }
    }

    private func putRecordNormalized(groupId: String, key: String, value: String, ttlSeconds: Int64): Bool {
        let storeOpt = LocalKVService.getStore()
        match (storeOpt) {
            case Some(store) =>
                let record = TaskGroupKVRecord()
                record.value = value
                record.createdAt = nowSeconds()
                record.ttlSeconds = ttlSeconds
                return store.put(namespace, buildStorageKey(groupId, key), TaskGroupKVRecordCodec.encode(record))
            case None =>
                logger.warn("task kv unavailable because LocalKVService is not ready")
                return false
        }
    }

    private func deleteNormalizedKey(storageKey: String): Bool {
        let storeOpt = LocalKVService.getStore()
        match (storeOpt) {
            case Some(store) => return store.delete(namespace, storageKey)
            case None =>
                logger.warn("task kv unavailable because LocalKVService is not ready")
                return false
        }
    }

    private func scanGroupEntriesNormalized(groupId: String): Array<(String, String)> {
        let storeOpt = LocalKVService.getStore()
        match (storeOpt) {
            case Some(store) => return store.scan(namespace, buildGroupPrefix(groupId))
            case None =>
                logger.warn("task kv unavailable because LocalKVService is not ready")
                return []
        }
    }

    private func deleteGroupEntriesNormalized(groupId: String, groupPrefix: String): Bool {
        let storeOpt = LocalKVService.getStore()
        match (storeOpt) {
            case Some(store) =>
                match (nextPrefixUpperBound(groupPrefix)) {
                    case Some(endKey) => return store.deleteRange(namespace, groupPrefix, endKey)
                    case None =>
                        let entries = store.scan(namespace, groupPrefix)
                        if (entries.size == 0) {
                            return true
                        }
                        let keys = Array<String>(entries.size, { i => entries[i][0] })
                        return store.deleteMany(namespace, keys)
                }
            case None =>
                logger.warn("task kv unavailable because LocalKVService is not ready")
                return false
        }
    }

    private static func normalizeGroupId(groupId: String): String {
        return groupId.trimAscii()
    }

    private static func normalizeKey(key: String): String {
        return key.trimAscii()
    }

    private static func buildGroupPrefix(groupId: String): String {
        return "${groupId}:"
    }

    private static func buildStorageKey(groupId: String, key: String): String {
        return "${groupId}:${key}"
    }

    private static func nextPrefixUpperBound(prefix: String): Option<String> {
        let bytes = prefix.toArray()
        if (bytes.size == 0) {
            return None
        }

        var pos = bytes.size - 1
        while (pos >= 0) {
            if (bytes[pos] < 255u8) {
                let upperBoundPos = pos
                let out = Array<UInt8>(Int64(upperBoundPos + 1), { i =>
                    if (i == upperBoundPos) {
                        bytes[i] + 1u8
                    } else {
                        bytes[i]
                    }
                })
                return Some(String.fromUtf8(out))
            }
            pos -= 1
        }
        return None
    }

    private func getOperationMutex(groupId: String): Mutex {
        operationMutexMapGuard.lock()
        try {
            match (operationMutexMap.get(groupId)) {
                case Some(groupMutex) => return groupMutex
                case None =>
                    let groupMutex = Mutex()
                    operationMutexMap[groupId] = groupMutex
                    return groupMutex
            }
        } finally {
            operationMutexMapGuard.unlock()
        }
    }

    private static func nowSeconds(): Int64 {
        return DateTime.now().toUnixTimeStamp().toSeconds()
    }

    private static func isExpired(record: TaskGroupKVRecord): Bool {
        return record.ttlSeconds > 0 && (nowSeconds() - record.createdAt) > record.ttlSeconds
    }
}

public class TaskKVService {
    public static func getStore(): TaskKVStore {
        return TaskGroupKVStore.getInstance()
    }
}
