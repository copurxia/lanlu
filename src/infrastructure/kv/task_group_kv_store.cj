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
    private static let operationLockCount: Int64 = 64

    private let refCountMutex: Mutex = Mutex()
    private let operationLocks: Array<Mutex>
    private var groupRefCounts: HashMap<String, Int32>

    private init() {
        operationLocks = Array<Mutex>(operationLockCount, { i => if (i >= 0) { Mutex() } else { Mutex() } })
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
        let lockIndex = getOperationLockIndex(groupId)
        return operationLocks[lockIndex]
    }

    private func getOperationLockIndex(groupId: String): Int64 {
        let hash = groupId.hashCode()
        let positiveHash = if (hash < 0) {
            -hash
        } else {
            hash
        }
        return positiveHash % operationLocks.size
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
