package lanlu.infrastructure.kv

import std.sync.*
import std.convert.*
import lanlu.shared.utils.*

public class PersistentCacheService {
    private static let logger = getLogger("persistent_cache_service")
    private static let namespaceVersionKey = "__version__"
    private static let namespaceLockCount: Int64 = 64
    private static let namespaceLocks: Array<Mutex> = Array<Mutex>(namespaceLockCount, {
        i => if (i >= 0) {
            Mutex()
        } else {
            Mutex()
        }
    })

    public static func get(namespace: String, key: String): Option<String> {
        let normalizedNamespace = normalizeNamespace(namespace)
        let normalizedKey = normalizeKey(key)
        if (normalizedNamespace.size == 0 || normalizedKey.size == 0) {
            return None
        }

        let storeOpt = LocalKVService.getStore()
        match (storeOpt) {
            case Some(store) => match (store.get(normalizedNamespace, normalizedKey)) {
                case Some(payload) => match (KvTtlRecordCodec.decode(payload)) {
                    case Some(record) =>
                        if (isExpired(record)) {
                            let _ = store.delete(normalizedNamespace, normalizedKey)
                            return None
                        }
                        return Some(record.value)
                    case None =>
                        let _ = store.delete(normalizedNamespace, normalizedKey)
                        logger.warn("persistent cache record decode failed; evicted key",
                            ("namespace", normalizedNamespace), ("key", normalizedKey))
                        return None
                }
                case None => return None
            }
            case None => return None
        }
    }

    public static func set(namespace: String, key: String, value: String, ttlSeconds: Int64): Bool {
        let normalizedNamespace = normalizeNamespace(namespace)
        let normalizedKey = normalizeKey(key)
        if (normalizedNamespace.size == 0 || normalizedKey.size == 0) {
            return false
        }

        let storeOpt = LocalKVService.getStore()
        match (storeOpt) {
            case Some(store) => return store.put(normalizedNamespace, normalizedKey,
                KvTtlRecords.encode(value, ttlSeconds))
            case None => return false
        }
    }

    public static func delete(namespace: String, key: String): Bool {
        let normalizedNamespace = normalizeNamespace(namespace)
        let normalizedKey = normalizeKey(key)
        if (normalizedNamespace.size == 0 || normalizedKey.size == 0) {
            return false
        }

        let storeOpt = LocalKVService.getStore()
        match (storeOpt) {
            case Some(store) => return store.delete(normalizedNamespace, normalizedKey)
            case None => return false
        }
    }

    public static func deleteByPrefix(namespace: String, prefix: String): Bool {
        let normalizedNamespace = normalizeNamespace(namespace)
        let normalizedPrefix = normalizeKeyPrefix(prefix)
        if (normalizedNamespace.size == 0) {
            return false
        }

        let storeOpt = LocalKVService.getStore()
        match (storeOpt) {
            case Some(store) => match (nextPrefixUpperBound(normalizedPrefix)) {
                case Some(endKey) => return store.deleteRange(normalizedNamespace, normalizedPrefix, endKey)
                case None =>
                    let entries = store.scan(normalizedNamespace, normalizedPrefix)
                    if (entries.size == 0) {
                        return true
                    }

                    let keys = Array<String>(entries.size, {i => entries[i][0]})
                    return store.deleteMany(normalizedNamespace, keys)
            }
            case None => return false
        }
    }

    public static func getNamespaceVersion(namespace: String): Int64 {
        let normalizedNamespace = normalizeNamespace(namespace)
        if (normalizedNamespace.size == 0) {
            return 1
        }

        return readNamespaceVersion(normalizedNamespace)
    }

    public static func bumpNamespaceVersion(namespace: String): Int64 {
        let normalizedNamespace = normalizeNamespace(namespace)
        if (normalizedNamespace.size == 0) {
            return 1
        }

        let namespaceMutex = getNamespaceMutex(normalizedNamespace)
        namespaceMutex.lock()
        try {
            let current = readNamespaceVersion(normalizedNamespace)
            let next = current + 1
            if (!set(normalizedNamespace, namespaceVersionKey, next.toString(), 0)) {
                return current
            }
            return next
        } finally {
            namespaceMutex.unlock()
        }
    }

    private static func readNamespaceVersion(namespace: String): Int64 {
        match (get(namespace, namespaceVersionKey)) {
            case Some(value) => try {
                let parsed = Int64.parse(value)
                return if (parsed > 0) {
                    parsed
                } else {
                    1
                }
            } catch (_: Exception) {
                return 1
            }
            case None => return 1
        }
    }

    private static func normalizeNamespace(namespace: String): String {
        return namespace.trimAscii()
    }

    private static func normalizeKey(key: String): String {
        return key.trimAscii()
    }

    private static func normalizeKeyPrefix(prefix: String): String {
        return prefix.trimAscii()
    }

    private static func getNamespaceMutex(namespace: String): Mutex {
        let hash = namespace.hashCode()
        let positiveHash = if (hash < 0) {
            -hash
        } else {
            hash
        }
        return namespaceLocks[positiveHash % namespaceLocks.size]
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

    private static func isExpired(record: KvTtlRecord): Bool {
        return KvTtlRecords.isExpired(record)
    }
}
