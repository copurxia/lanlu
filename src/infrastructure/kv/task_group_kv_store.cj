package lanlu.infrastructure.kv

import std.sync.*
import std.collection.*
import std.convert.*
import std.time.*
import lanlu.contexts.task.domain.*
import lanlu.contexts.task.infrastructure.persistence.TaskDao
import lanlu.shared.utils.*

private class TaskGroupKVKeys {
    public static func groupPrefix(groupId: String): String {
        return "${groupId}:"
    }

    public static func storageKey(groupId: String, key: String): String {
        return "${groupId}:${key}"
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
    private static let maxTxnRetries: Int64 = 8
    private static var instance: Option<TaskGroupKVStore> = None
    private static let instanceMutex: Mutex = Mutex()

    private let refCountMutex: Mutex = Mutex()
    private var groupRefCounts: HashMap<String, Int32>

    private init() {
        groupRefCounts = HashMap<String, Int32>()
    }

    public static func getInstance(): TaskGroupKVStore {
        return synchronized(instanceMutex) {
            match (instance) {
                case Some(s) => s
                case None =>
                    let s = TaskGroupKVStore()
                    instance = Some(s)
                    s
            }
        }
    }

    public func acquireGroup(groupId: String): Unit {
        let normalizedGroupId = normalizeGroupId(groupId)
        if (normalizedGroupId.size == 0) {
            return
        }

        synchronized(refCountMutex) {
            match (groupRefCounts.get(normalizedGroupId)) {
                case Some(count) => groupRefCounts[normalizedGroupId] = count + 1
                case None => groupRefCounts[normalizedGroupId] = 1
            }
        }
    }

    public func releaseGroup(groupId: String): Unit {
        let normalizedGroupId = normalizeGroupId(groupId)
        if (normalizedGroupId.size == 0) {
            return
        }

        var shouldDeleteGroup = false
        synchronized(refCountMutex) {
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
        }

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
        return putRecordNormalized(normalizedGroupId, normalizedKey, value, ttlSeconds)
    }

    public func get(groupId: String, key: String): Option<String> {
        let normalizedGroupId = normalizeGroupId(groupId)
        let normalizedKey = normalizeKey(key)
        if (normalizedGroupId.size == 0 || normalizedKey.size == 0) {
            return None
        }
        return getValueNormalized(normalizedGroupId, normalizedKey)
    }

    public func delete(groupId: String, key: String): Bool {
        let normalizedGroupId = normalizeGroupId(groupId)
        let normalizedKey = normalizeKey(key)
        if (normalizedGroupId.size == 0 || normalizedKey.size == 0) {
            return false
        }
        return deleteNormalizedKey(TaskGroupKVKeys.storageKey(normalizedGroupId, normalizedKey))
    }

    public func deleteGroup(groupId: String): Unit {
        let normalizedGroupId = normalizeGroupId(groupId)
        if (normalizedGroupId.size == 0) {
            return
        }

        let prefix = TaskGroupKVKeys.groupPrefix(normalizedGroupId)
        let deleted = deleteGroupEntriesNormalized(prefix)
        if (!deleted) {
            logger.warn("task kv group delete failed", ("group_id", normalizedGroupId))
        }

        synchronized(refCountMutex) {
            groupRefCounts.remove(normalizedGroupId)
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

        let entries = ArrayList<(String, String)>()
        var i: Int64 = 0
        while (i < keys.size) {
            let normalizedKey = normalizeKey(keys[i])
            if (normalizedKey.size > 0) {
                entries.add(
                    (TaskGroupKVKeys.storageKey(normalizedGroupId, normalizedKey), encodeRecord(values[i], ttlSeconds)))
            }
            i += 1
        }
        return putEncodedRecords(entries.toArray())
    }

    public func insertIfAbsent(groupId: String, key: String, value: String, ttlSeconds: Int64): Bool {
        let normalizedGroupId = normalizeGroupId(groupId)
        let normalizedKey = normalizeKey(key)
        if (normalizedGroupId.size == 0 || normalizedKey.size == 0) {
            return false
        }

        match (LocalKVService.getTransactionalStore()) {
            case Some(txStore) =>
                var attempt: Int64 = 0
                while (attempt < maxTxnRetries) {
                    let txn = match (txStore.beginTransactionResult(namespace)) {
                        case LocalKVResult<LocalKVTransaction>.Ok(value) => value
                        case LocalKVResult<LocalKVTransaction>.Err(err) =>
                            logger.warn("task kv transaction begin failed",
                                [("group_id", normalizedGroupId), ("key", normalizedKey), ("error", err)])
                            break
                        case LocalKVResult<LocalKVTransaction>.NotFound =>
                            logger.warn("task kv transaction begin failed",
                                [("group_id", normalizedGroupId), ("key", normalizedKey), ("error", "not found")])
                            break
                    }
                    try {
                        match (getRecordNormalizedFromTxn(txn, normalizedGroupId, normalizedKey)) {
                            case Some(_) =>
                                rollbackTransactionQuietly(txn)
                                return false
                            case None =>
                                let putResult = putRecordNormalizedToTxn(txn, normalizedGroupId, normalizedKey, value,
                                    ttlSeconds)
                                match (putResult) {
                                    case LocalKVResult<Unit>.Ok(_) => ()
                                    case LocalKVResult<Unit>.Err(err) =>
                                        rollbackTransactionQuietly(txn)
                                        logger.warn("task kv transaction put failed",
                                            [("group_id", normalizedGroupId), ("key", normalizedKey), ("error", err)])
                                        return false
                                    case LocalKVResult<Unit>.NotFound =>
                                        rollbackTransactionQuietly(txn)
                                        logger.warn("task kv transaction put failed",
                                            [("group_id", normalizedGroupId), ("key", normalizedKey), ("error", "not found")])
                                        return false
                                }
                                match (txn.commitResult()) {
                                    case LocalKVResult<Unit>.Ok(_) => return true
                                    case LocalKVResult<Unit>.Err(err) =>
                                        rollbackTransactionQuietly(txn)
                                        if (!txStore.isConflictError(err)) {
                                            logger.warn("task kv transaction commit failed",
                                                [("group_id", normalizedGroupId), ("key", normalizedKey),
                                                    ("error", err)])
                                            return false
                                        }
                                    case LocalKVResult<Unit>.NotFound =>
                                        rollbackTransactionQuietly(txn)
                                        logger.warn("task kv transaction commit failed",
                                            [("group_id", normalizedGroupId), ("key", normalizedKey),
                                                ("error", "not found")])
                                        return false
                                }
                        }
                    } finally {
                        closeTransaction(txn)
                    }
                    attempt += 1
                }
                logger.warn(
                    "task kv transaction retries exhausted; falling back to non-transactional insertIfAbsent",
                    ("group_id", normalizedGroupId),
                    ("key", normalizedKey),
                    ("attempts", attempt.toString())
                )
            case None => ()
        }

        match (getRecordNormalized(normalizedGroupId, normalizedKey)) {
            case Some(_) => return false
            case None => return putRecordNormalized(normalizedGroupId, normalizedKey, value, ttlSeconds)
        }
    }

    public func increment(groupId: String, key: String, delta: Int64, ttlSeconds: Int64): Int64 {
        let normalizedGroupId = normalizeGroupId(groupId)
        let normalizedKey = normalizeKey(key)
        if (normalizedGroupId.size == 0 || normalizedKey.size == 0) {
            return -1
        }

        match (LocalKVService.getTransactionalStore()) {
            case Some(txStore) =>
                var attempt: Int64 = 0
                while (attempt < maxTxnRetries) {
                    let txn = match (txStore.beginTransactionResult(namespace)) {
                        case LocalKVResult<LocalKVTransaction>.Ok(value) => value
                        case LocalKVResult<LocalKVTransaction>.Err(err) =>
                            logger.warn("task kv transaction begin failed",
                                [("group_id", normalizedGroupId), ("key", normalizedKey), ("error", err)])
                            break
                        case LocalKVResult<LocalKVTransaction>.NotFound =>
                            logger.warn("task kv transaction begin failed",
                                [("group_id", normalizedGroupId), ("key", normalizedKey), ("error", "not found")])
                            break
                    }
                    try {
                        var currentValue: Int64 = 0
                        match (getRecordNormalizedFromTxn(txn, normalizedGroupId, normalizedKey)) {
                            case Some(record) => try {
                                currentValue = Int64.parse(record.value)
                            } catch (_: Exception) {
                                rollbackTransactionQuietly(txn)
                                return -1
                            }
                            case None => currentValue = 0
                        }

                        let nextValue = currentValue + delta
                        let putResult = putRecordNormalizedToTxn(txn, normalizedGroupId, normalizedKey,
                            nextValue.toString(), ttlSeconds)
                        match (putResult) {
                            case LocalKVResult<Unit>.Ok(_) => ()
                            case LocalKVResult<Unit>.Err(err) =>
                                rollbackTransactionQuietly(txn)
                                logger.warn("task kv transaction put failed",
                                    [("group_id", normalizedGroupId), ("key", normalizedKey), ("error", err)])
                                return -1
                            case LocalKVResult<Unit>.NotFound =>
                                rollbackTransactionQuietly(txn)
                                logger.warn("task kv transaction put failed",
                                    [("group_id", normalizedGroupId), ("key", normalizedKey), ("error", "not found")])
                                return -1
                        }
                        match (txn.commitResult()) {
                            case LocalKVResult<Unit>.Ok(_) => return nextValue
                            case LocalKVResult<Unit>.Err(err) =>
                                rollbackTransactionQuietly(txn)
                                if (!txStore.isConflictError(err)) {
                                    logger.warn("task kv transaction commit failed",
                                        [("group_id", normalizedGroupId), ("key", normalizedKey), ("error", err)])
                                    return -1
                                }
                            case LocalKVResult<Unit>.NotFound =>
                                rollbackTransactionQuietly(txn)
                                logger.warn("task kv transaction commit failed",
                                    [("group_id", normalizedGroupId), ("key", normalizedKey), ("error", "not found")])
                                return -1
                        }
                    } finally {
                        closeTransaction(txn)
                    }
                    attempt += 1
                }
                logger.warn(
                    "task kv transaction retries exhausted; falling back to non-transactional increment",
                    ("group_id", normalizedGroupId),
                    ("key", normalizedKey),
                    ("attempts", attempt.toString())
                )
            case None => ()
        }

        var currentValue: Int64 = 0
        match (getRecordNormalized(normalizedGroupId, normalizedKey)) {
            case Some(record) => try {
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

        match (LocalKVService.getTransactionalStore()) {
            case Some(txStore) =>
                let t0 = DateTime.now().toUnixTimeStamp().toMilliseconds()
                var attempt: Int64 = 0
                while (attempt < maxTxnRetries) {
                    let txn = match (txStore.beginTransactionResult(namespace)) {
                        case LocalKVResult<LocalKVTransaction>.Ok(value) => value
                        case LocalKVResult<LocalKVTransaction>.Err(err) =>
                            logger.warn("task kv upload transaction begin failed",
                                [("group_id", normalizedGroupId), ("chunk_key", normalizedChunkKey), ("error", err)])
                            break
                        case LocalKVResult<LocalKVTransaction>.NotFound =>
                            logger.warn("task kv upload transaction begin failed",
                                [("group_id", normalizedGroupId), ("chunk_key", normalizedChunkKey), ("error", "not found")])
                            break
                    }
                    try {
                        match (getRecordNormalizedFromTxn(txn, normalizedGroupId, normalizedChunkKey)) {
                            case Some(_) => result.inserted = false
                            case None =>
                                let putChunk = putRecordNormalizedToTxn(txn, normalizedGroupId, normalizedChunkKey, "1",
                                    ttlSeconds)
                                match (putChunk) {
                                    case LocalKVResult<Unit>.Ok(_) => ()
                                    case LocalKVResult<Unit>.Err(err) =>
                                        rollbackTransactionQuietly(txn)
                                        logger.warn("task kv upload transaction chunk put failed",
                                            [("group_id", normalizedGroupId), ("chunk_key", normalizedChunkKey),
                                                ("error", err)])
                                        return result
                                    case LocalKVResult<Unit>.NotFound =>
                                        rollbackTransactionQuietly(txn)
                                        logger.warn("task kv upload transaction chunk put failed",
                                            [("group_id", normalizedGroupId), ("chunk_key", normalizedChunkKey),
                                                ("error", "not found")])
                                        return result
                                }
                                result.inserted = true
                        }

                        var currentValue: Int64 = 0
                        match (getRecordNormalizedFromTxn(txn, normalizedGroupId, "uploaded_count")) {
                            case Some(record) => try {
                                currentValue = Int64.parse(record.value)
                            } catch (_: Exception) {
                                currentValue = 0
                            }
                            case None => currentValue = 0
                        }

                        result.uploadedChunkCount = if (result.inserted) {
                            currentValue + 1
                        } else {
                            currentValue
                        }
                        result.writtenOffset = newOffset

                        let putUploaded = putRecordNormalizedToTxn(txn, normalizedGroupId, "uploaded_count",
                            result.uploadedChunkCount.toString(), ttlSeconds)
                        match (putUploaded) {
                            case LocalKVResult<Unit>.Ok(_) => ()
                            case LocalKVResult<Unit>.Err(err) =>
                                rollbackTransactionQuietly(txn)
                                logger.warn("task kv upload transaction uploaded_count put failed",
                                    [("group_id", normalizedGroupId), ("error", err)])
                                return result
                            case LocalKVResult<Unit>.NotFound =>
                                rollbackTransactionQuietly(txn)
                                logger.warn("task kv upload transaction uploaded_count put failed",
                                    [("group_id", normalizedGroupId), ("error", "not found")])
                                return result
                        }

                        let putOffset = putRecordNormalizedToTxn(txn, normalizedGroupId, "written_offset",
                            newOffset.toString(), ttlSeconds)
                        match (putOffset) {
                            case LocalKVResult<Unit>.Ok(_) => ()
                            case LocalKVResult<Unit>.Err(err) =>
                                rollbackTransactionQuietly(txn)
                                logger.warn("task kv upload transaction written_offset put failed",
                                    [("group_id", normalizedGroupId), ("error", err)])
                                return result
                            case LocalKVResult<Unit>.NotFound =>
                                rollbackTransactionQuietly(txn)
                                logger.warn("task kv upload transaction written_offset put failed",
                                    [("group_id", normalizedGroupId), ("error", "not found")])
                                return result
                        }

                        if (shouldUpdateProgress) {
                            let putProgress = putRecordNormalizedToTxn(txn, normalizedGroupId, "last_reported_progress",
                                uploadedProgress.toString(), ttlSeconds)
                            match (putProgress) {
                                case LocalKVResult<Unit>.Ok(_) => ()
                                case LocalKVResult<Unit>.Err(err) =>
                                    rollbackTransactionQuietly(txn)
                                    logger.warn("task kv upload transaction progress put failed",
                                        [("group_id", normalizedGroupId), ("error", err)])
                                    return result
                                case LocalKVResult<Unit>.NotFound =>
                                    rollbackTransactionQuietly(txn)
                                    logger.warn("task kv upload transaction progress put failed",
                                        [("group_id", normalizedGroupId), ("error", "not found")])
                                    return result
                            }
                            result.updatedProgress = true
                        }
                        if (shouldUpdateTimeoutTs) {
                            let putTimeout = putRecordNormalizedToTxn(txn, normalizedGroupId, "last_timeout_extend_ts",
                                nowTs.toString(), ttlSeconds)
                            match (putTimeout) {
                                case LocalKVResult<Unit>.Ok(_) => ()
                                case LocalKVResult<Unit>.Err(err) =>
                                    rollbackTransactionQuietly(txn)
                                    logger.warn("task kv upload transaction timeout put failed",
                                        [("group_id", normalizedGroupId), ("error", err)])
                                    return result
                                case LocalKVResult<Unit>.NotFound =>
                                    rollbackTransactionQuietly(txn)
                                    logger.warn("task kv upload transaction timeout put failed",
                                        [("group_id", normalizedGroupId), ("error", "not found")])
                                    return result
                            }
                            result.updatedTimeoutTs = true
                        }

                        match (txn.commitResult()) {
                            case LocalKVResult<Unit>.Ok(_) =>
                                let t1 = DateTime.now().toUnixTimeStamp().toMilliseconds()
                                logger.debug(
                                    "[KV] commitUploadChunk completed",
                                    ("group_id", normalizedGroupId),
                                    ("chunk_key", normalizedChunkKey),
                                    ("inserted", result.inserted.toString()),
                                    ("uploaded_count", result.uploadedChunkCount.toString()),
                                    ("attempt", (attempt + 1).toString()),
                                    ("txn_ms", (t1 - t0).toString())
                                )
                                return result
                            case LocalKVResult<Unit>.Err(err) =>
                                rollbackTransactionQuietly(txn)
                                if (!txStore.isConflictError(err)) {
                                    logger.warn("task kv upload transaction commit failed",
                                        [("group_id", normalizedGroupId), ("chunk_key", normalizedChunkKey),
                                            ("error", err)])
                                    return result
                                }
                            case LocalKVResult<Unit>.NotFound =>
                                rollbackTransactionQuietly(txn)
                                logger.warn("task kv upload transaction commit failed",
                                    [("group_id", normalizedGroupId), ("chunk_key", normalizedChunkKey),
                                        ("error", "not found")])
                                return result
                        }
                    } finally {
                        closeTransaction(txn)
                    }
                    attempt += 1
                }
                logger.warn(
                    "task kv upload transaction retries exhausted; falling back to non-transactional commit",
                    ("group_id", normalizedGroupId),
                    ("chunk_key", normalizedChunkKey),
                    ("attempts", attempt.toString())
                )
            case None => ()
        }

        match (getRecordNormalized(normalizedGroupId, normalizedChunkKey)) {
            case Some(_) => result.inserted = false
            case None =>
                if (putRecordNormalized(normalizedGroupId, normalizedChunkKey, "1", ttlSeconds)) {
                    result.inserted = true
                }
        }

        if (result.inserted) {
            var currentValue: Int64 = 0
            match (getRecordNormalized(normalizedGroupId, "uploaded_count")) {
                case Some(record) => try {
                    currentValue = Int64.parse(record.value)
                } catch (_: Exception) {
                    currentValue = 0
                }
                case None => currentValue = 0
            }
            result.uploadedChunkCount = currentValue + 1
            let _ = putRecordNormalized(normalizedGroupId, "uploaded_count", result.uploadedChunkCount.toString(),
                ttlSeconds)
        } else {
            match (getRecordNormalized(normalizedGroupId, "uploaded_count")) {
                case Some(record) => try {
                    result.uploadedChunkCount = Int64.parse(record.value)
                } catch (_: Exception) {
                    result.uploadedChunkCount = 0
                }
                case None => result.uploadedChunkCount = 0
            }
        }

        result.writtenOffset = newOffset
        let writeOk = setMulti(
            normalizedGroupId,
            if (shouldUpdateProgress && shouldUpdateTimeoutTs) {
                ["uploaded_count", "written_offset", "last_reported_progress", "last_timeout_extend_ts"]
            } else if (shouldUpdateProgress) {
                ["uploaded_count", "written_offset", "last_reported_progress"]
            } else if (shouldUpdateTimeoutTs) {
                ["uploaded_count", "written_offset", "last_timeout_extend_ts"]
            } else {
                ["uploaded_count", "written_offset"]
            },
            if (shouldUpdateProgress && shouldUpdateTimeoutTs) {
                [result.uploadedChunkCount.toString(), newOffset.toString(), uploadedProgress.toString(),
                    nowTs.toString()]
            } else if (shouldUpdateProgress) {
                [result.uploadedChunkCount.toString(), newOffset.toString(), uploadedProgress.toString()]
            } else if (shouldUpdateTimeoutTs) {
                [result.uploadedChunkCount.toString(), newOffset.toString(), nowTs.toString()]
            } else {
                [result.uploadedChunkCount.toString(), newOffset.toString()]
            },
            ttlSeconds
        )
        if (shouldUpdateProgress) {
            result.updatedProgress = writeOk
        }
        if (shouldUpdateTimeoutTs) {
            result.updatedTimeoutTs = writeOk
        }
        return result
    }

    public func hasGroup(groupId: String): Bool {
        let normalizedGroupId = normalizeGroupId(groupId)
        if (normalizedGroupId.size == 0) {
            return false
        }

        return synchronized(refCountMutex) {
            groupRefCounts.contains(normalizedGroupId)
        }
    }

    public func getKeys(groupId: String): Array<String> {
        let normalizedGroupId = normalizeGroupId(groupId)
        if (normalizedGroupId.size == 0) {
            return []
        }

        let prefix = TaskGroupKVKeys.groupPrefix(normalizedGroupId)
        let entries = scanGroupEntriesNormalized(normalizedGroupId)
        let keys = ArrayList<String>()
        for ((storageKey, payload) in entries) {
            if (storageKey.size <= prefix.size) {
                continue
            }

            let key = storageKey[prefix.size..storageKey.size]
            match (KvTtlRecordCodec.decode(payload)) {
                case Some(record) =>
                    if (!isExpired(record)) {
                        keys.add(key)
                    }
                case None => logger.warn("task kv record decode failed during key scan", ("group_id", normalizedGroupId),
                    ("key", key))
            }
        }
        return keys.toArray()
    }

    /**
     * 批量读取同一 group 内的多个 key
     *
     * 优化说明：
     * - 一次 multiGet
     * - 6次独立读 → 1次批量读，RocksDB I/O 减少83%
     *
     * @param groupId 分组ID
     * @param keys 需要读取的key数组
     * @return 与keys对应的值数组，缺失或过期的key返回None
     */
    public func getMulti(groupId: String, keys: Array<String>): Array<Option<String>> {
        let normalizedGroupId = normalizeGroupId(groupId)
        if (normalizedGroupId.size == 0 || keys.size == 0) {
            return Array<Option<String>>(keys.size, {_ => None})
        }

        let t0 = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let storageKeys = Array<String>(keys.size, {
            i => TaskGroupKVKeys.storageKey(normalizedGroupId, normalizeKey(keys[i]))
        })

        let t1 = DateTime.now().toUnixTimeStamp().toMilliseconds()

        let storeOpt = LocalKVService.getStore()
        match (storeOpt) {
            case Some(store) =>
                let t2 = DateTime.now().toUnixTimeStamp().toMilliseconds()
                let rawValues = store.multiGet(namespace, storageKeys)
                let t3 = DateTime.now().toUnixTimeStamp().toMilliseconds()
                let results = Array<Option<String>>(rawValues.size, {
                    i => match (rawValues[i]) {
                        case Some(payload) => match (KvTtlRecordCodec.decode(payload)) {
                            case Some(record) =>
                                if (isExpired(record)) {
                                    None
                                } else {
                                    Some(record.value)
                                }
                            case None =>
                                logger.warn("task kv record decode failed during multiGet",
                                    ("group_id", normalizedGroupId), ("key", keys[i]))
                                None
                        }
                        case None => None
                    }
                })
                let t4 = DateTime.now().toUnixTimeStamp().toMilliseconds()
                logger.debug(
                    "[KV] getMulti completed",
                    ("group_id", normalizedGroupId),
                    ("key_count", keys.size.toString()),
                    ("total_ms", (t4 - t0).toString()),
                    ("build_keys_ms", (t1 - t0).toString()),
                    ("store_call_ms", (t3 - t2).toString()),
                    ("post_process_ms", (t4 - t3).toString())
                )
                return results
            case None =>
                logger.warn("task kv unavailable because LocalKVService is not ready")
                return Array<Option<String>>(keys.size, {_ => None})
        }
    }

    private func getValueNormalized(groupId: String, key: String): Option<String> {
        match (getRecordNormalized(groupId, key)) {
            case Some(record) => return Some(record.value)
            case None => return None
        }
    }

    private func getRecordNormalized(groupId: String, key: String): Option<KvTtlRecord> {
        let storeOpt = LocalKVService.getStore()
        match (storeOpt) {
            case Some(store) => match (store.get(namespace, TaskGroupKVKeys.storageKey(groupId, key))) {
                case Some(payload) => match (KvTtlRecordCodec.decode(payload)) {
                    case Some(record) =>
                        if (isExpired(record)) {
                            return None
                        }
                        return Some(record)
                    case None =>
                        logger.warn("task kv record decode failed", ("group_id", groupId), ("key", key))
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
        let encodedRecord = encodeRecord(value, ttlSeconds)
        return putEncodedRecord(TaskGroupKVKeys.storageKey(groupId, key), encodedRecord)
    }

    private func putEncodedRecord(storageKey: String, encodedRecord: String): Bool {
        let storeOpt = LocalKVService.getStore()
        match (storeOpt) {
            case Some(store) => return store.put(namespace, storageKey, encodedRecord)
            case None =>
                logger.warn("task kv unavailable because LocalKVService is not ready")
                return false
        }
    }

    private func putEncodedRecords(entries: Array<(String, String)>): Bool {
        if (entries.size == 0) {
            return true
        }

        let storeOpt = LocalKVService.getStore()
        match (storeOpt) {
            case Some(store) => return store.putMany(namespace, entries)
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
            case Some(store) => return store.scan(namespace, TaskGroupKVKeys.groupPrefix(groupId))
            case None =>
                logger.warn("task kv unavailable because LocalKVService is not ready")
                return []
        }
    }

    private func deleteGroupEntriesNormalized(groupPrefix: String): Bool {
        let storeOpt = LocalKVService.getStore()
        match (storeOpt) {
            case Some(store) => match (nextPrefixUpperBound(groupPrefix)) {
                case Some(endKey) => return store.deleteRange(namespace, groupPrefix, endKey)
                case None =>
                    let entries = store.scan(namespace, groupPrefix)
                    if (entries.size == 0) {
                        return true
                    }
                    let keys = Array<String>(entries.size, {i => entries[i][0]})
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

    private static func nextPrefixUpperBound(prefix: String): Option<String> {
        let bytes = prefix.toArray()
        if (bytes.size == 0) {
            return None
        }

        var pos = bytes.size - 1
        while (pos >= 0) {
            if (bytes[pos] < 255u8) {
                let upperBoundPos = pos
                let out = Array<UInt8>(Int64(upperBoundPos + 1), {
                    i => if (i == upperBoundPos) {
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

    private static func encodeRecord(value: String, ttlSeconds: Int64): String {
        return KvTtlRecords.encode(value, ttlSeconds)
    }

    private static func isExpired(record: KvTtlRecord): Bool {
        return KvTtlRecords.isExpired(record)
    }

    private static func closeTransaction(txn: LocalKVTransaction): Unit {
        txn.close()
    }

    private static func rollbackTransactionQuietly(txn: LocalKVTransaction): Unit {
        let _ = txn.rollbackResult()
    }

    private func getRecordNormalizedFromTxn(txn: LocalKVTransaction, groupId: String, key: String): Option<KvTtlRecord> {
        match (txn.getResult(TaskGroupKVKeys.storageKey(groupId, key))) {
            case LocalKVResult<String>.Ok(payload) => match (KvTtlRecordCodec.decode(payload)) {
                case Some(record) =>
                    if (isExpired(record)) {
                        return None
                    }
                    return Some(record)
                case None =>
                    logger.warn("task kv transaction decode failed", [("group_id", groupId), ("key", key)])
                    return None
            }
            case LocalKVResult<String>.NotFound => return None
            case LocalKVResult<String>.Err(err) =>
                logger.warn("task kv transaction get failed", [("group_id", groupId), ("key", key), ("error", err)])
                return None
        }
    }

    private func putRecordNormalizedToTxn(
        txn: LocalKVTransaction,
        groupId: String,
        key: String,
        value: String,
        ttlSeconds: Int64
    ): LocalKVResult<Unit> {
        return txn.putResult(TaskGroupKVKeys.storageKey(groupId, key), encodeRecord(value, ttlSeconds))
    }
}

public class TaskKVService {
    public static func getStore(): TaskKVStore {
        return TaskGroupKVStore.getInstance()
    }
}
