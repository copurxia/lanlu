package lanlu.infrastructure.kv

import std.collection.*
import std.sync.*
import std.fs.*
import std.convert.*
import std.time.*
import std.env.getVariable
import lanlu.contexts.system.infrastructure.persistence.*
import lanlu.shared.utils.*
import rocksdb_ffi.RocksDb

private class LocalKvBootstrapConfig {
    public var cachePath: String
    public var kvMemoryMb: Int32

    public init(cachePath: String, kvMemoryMb: Int32) {
        this.cachePath = cachePath
        this.kvMemoryMb = kvMemoryMb
    }
}

public interface LocalKVStore {
    func isAvailable(): Bool
    func get(namespace: String, key: String): Option<String>
    func multiGet(namespace: String, keys: Array<String>): Array<Option<String>>
    func put(namespace: String, key: String, value: String): Bool
    func delete(namespace: String, key: String): Bool
    func deleteMany(namespace: String, keys: Array<String>): Bool
    func deleteRange(namespace: String, startKey: String, endKey: String): Bool
    func scan(namespace: String, keyPrefix: String): Array<(String, String)>
}

public class RocksDbLocalKVStore <: LocalKVStore {
    private let db: RocksDb
    private static let logger = getLogger("rocksdb_local_kv")

    public init(db: RocksDb) {
        this.db = db
    }

    public func isAvailable(): Bool {
        return true
    }

    public func get(namespace: String, key: String): Option<String> {
        let (ok, valueOpt, _) = db.get(composeKey(namespace, key))
        if (!ok) {
            return None
        }
        return valueOpt
    }

    public func multiGet(namespace: String, keys: Array<String>): Array<Option<String>> {
        if (keys.size == 0) {
            return []
        }

        let t0 = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let fullKeys = Array<String>(keys.size, { i => composeKey(namespace, keys[i]) })
        let t1 = DateTime.now().toUnixTimeStamp().toMilliseconds()
        
        logger.debug(
            "[KV] RocksDb multiGet calling",
            ("namespace", namespace),
            ("key_count", keys.size.toString()),
            ("compose_ms", (t1 - t0).toString())
        )
        
        let (ok, values, err) = db.multiGet(fullKeys)
        let t2 = DateTime.now().toUnixTimeStamp().toMilliseconds()
        
        if (!ok) {
            logger.warn(
                "[KV] RocksDb multiGet failed",
                ("namespace", namespace),
                ("key_count", keys.size.toString()),
                ("rocksdb_ms", (t2 - t1).toString()),
                ("error", err)
            )
            return Array<Option<String>>(keys.size, { _ => None })
        }
        
        let foundCount = values.filter({ v => v.isSome() }).size
        logger.debug(
            "[KV] RocksDb multiGet completed",
            ("namespace", namespace),
            ("key_count", keys.size.toString()),
            ("found_count", foundCount.toString()),
            ("rocksdb_ms", (t2 - t1).toString()),
            ("total_ms", (t2 - t0).toString())
        )
        
        return values
    }

    public func put(namespace: String, key: String, value: String): Bool {
        let (ok, _) = db.put(composeKey(namespace, key), value)
        return ok
    }

    public func delete(namespace: String, key: String): Bool {
        let (ok, _) = db.delete(composeKey(namespace, key))
        return ok
    }

    public func deleteMany(namespace: String, keys: Array<String>): Bool {
        if (keys.size == 0) {
            return true
        }

        let fullKeys = Array<String>(keys.size, { i => composeKey(namespace, keys[i]) })
        let (ok, _) = db.deleteMany(fullKeys)
        return ok
    }

    public func deleteRange(namespace: String, startKey: String, endKey: String): Bool {
        let (ok, _) = db.deleteRange(composeKey(namespace, startKey), composeKey(namespace, endKey))
        return ok
    }

    public func scan(namespace: String, keyPrefix: String): Array<(String, String)> {
        let namespacePrefix = "${namespace}:"
        let fullPrefix = composeKey(namespace, keyPrefix)
        let (ok, pairs, _) = db.scanByPrefix(fullPrefix)
        if (!ok) {
            return []
        }

        let entries = ArrayList<(String, String)>()
        for ((key, value) in pairs) {
            if (key.startsWith(namespacePrefix) && key.size >= namespacePrefix.size) {
                entries.add((key[namespacePrefix.size..key.size], value))
            }
        }
        return entries.toArray()
    }

    private func composeKey(namespace: String, key: String): String {
        return "${namespace}:${key}"
    }
}

public class LocalKVService {
    private static let logger = getLogger("local_kv_service")
    private static let mutex = Mutex()
    private static let defaultCachePath = "./data/cache"
    private static let defaultKvMemoryMb: Int32 = 64
    private static let minKvMemoryMb: Int32 = 4
    private static var initialized = false
    private static var store: Option<LocalKVStore> = Option<LocalKVStore>.None

    public static func initializeFromSettings(): Bool {
        mutex.lock()
        if (initialized) {
            let ready = !store.isNone()
            mutex.unlock()
            return ready
        }

        initialized = true
        let bootstrapConfig = resolveBootstrapConfig()
        let dbPath = FileUtils.joinPath(bootstrapConfig.cachePath, "rocksdb")
        FileUtils.ensureDirectoryExists(Path(dbPath))

        let (ok, dbOpt, err) = RocksDb.openBalanced(dbPath, bootstrapConfig.kvMemoryMb)
        if (!ok) {
            logger.warn(
                "Failed to initialize RocksDB local KV; falling back to no-cache mode",
                ("path", dbPath),
                ("kv_memory_mb", bootstrapConfig.kvMemoryMb.toString()),
                ("error", err)
            )
            store = Option<LocalKVStore>.None
            mutex.unlock()
            return false
        }

        store = Option<LocalKVStore>.Some(RocksDbLocalKVStore(dbOpt.getOrThrow()))
        logger.info("Initialized RocksDB local KV", ("path", dbPath), ("kv_memory_mb", bootstrapConfig.kvMemoryMb.toString()))
        mutex.unlock()
        return true
    }

    public static func getStore(): Option<LocalKVStore> {
        mutex.lock()
        let res = store
        mutex.unlock()
        return res
    }

    private static func resolveBootstrapConfig(): LocalKvBootstrapConfig {
        let fallbackCachePath = normalizeCachePath(getVariable("CACHE_PATH") ?? defaultCachePath)
        let cachePath = resolveBootstrapCachePath(fallbackCachePath)
        let envMemoryMb = parseInt32OrDefault(getVariable("ROCKSDB_KV_MEMORY_MB") ?? "", defaultKvMemoryMb)
        let kvMemoryMb = clampKvMemoryMb(resolveBootstrapKvMemoryMb(envMemoryMb))
        return LocalKvBootstrapConfig(cachePath, kvMemoryMb)
    }

    private static func resolveBootstrapCachePath(fallback: String): String {
        match (SystemSettingsDao.getBootstrapValue("CACHE_PATH")) {
            case Some(value) =>
                let normalized = normalizeCachePath(value)
                if (normalized.size > 0) {
                    return normalized
                }
            case None => ()
        }
        return normalizeCachePath(fallback)
    }

    private static func resolveBootstrapKvMemoryMb(fallback: Int32): Int32 {
        match (SystemSettingsDao.getBootstrapValue("ROCKSDB_KV_MEMORY_MB")) {
            case Some(value) => return parseInt32OrDefault(value, fallback)
            case None => return fallback
        }
    }

    private static func normalizeCachePath(path: String): String {
        let trimmed = path.trimAscii()
        return if (trimmed.size > 0) { trimmed } else { defaultCachePath }
    }

    private static func clampKvMemoryMb(value: Int32): Int32 {
        var out = value
        if (out <= 0) {
            out = defaultKvMemoryMb
        }
        if (out < minKvMemoryMb) {
            out = minKvMemoryMb
        }
        return out
    }

    private static func parseInt32OrDefault(value: String, fallback: Int32): Int32 {
        let trimmed = value.trimAscii()
        if (trimmed.size == 0) {
            return fallback
        }

        try {
            return Int32.parse(trimmed)
        } catch (_: Exception) {
            return fallback
        }
    }
}
