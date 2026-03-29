package lanlu.infrastructure.kv

import std.collection.*
import std.sync.*
import std.fs.*
import lanlu.contexts.system.application.SystemSettingsService
import lanlu.shared.utils.*
import rocksdb_ffi.RocksDb

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

        let fullKeys = Array<String>(keys.size, { i => composeKey(namespace, keys[i]) })
        let (ok, values, _) = db.multiGet(fullKeys)
        if (!ok) {
            return Array<Option<String>>(keys.size, { _ => None })
        }
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

        let enabled = SystemSettingsService.getBoolean("ROCKSDB_ENABLED")
        if (!enabled) {
            logger.info("RocksDB local KV disabled by settings")
            store = Option<LocalKVStore>.None
            mutex.unlock()
            return false
        }

        var dbPath = SystemSettingsService.getPath("ROCKSDB_PATH").trimAscii()
        if (dbPath.size == 0) {
            dbPath = FileUtils.joinPath(SystemSettingsService.getPath("CACHE_PATH"), "rocksdb")
        }
        FileUtils.ensureDirectoryExists(Path(dbPath))

        let (ok, dbOpt, err) = RocksDb.openBalanced(dbPath)
        if (!ok) {
            logger.warn("Failed to initialize RocksDB local KV; falling back to no-cache mode", ("path", dbPath), ("error", err))
            store = Option<LocalKVStore>.None
            mutex.unlock()
            return false
        }

        store = Option<LocalKVStore>.Some(RocksDbLocalKVStore(dbOpt.getOrThrow()))
        logger.info("Initialized RocksDB local KV", ("path", dbPath))
        mutex.unlock()
        return true
    }

    public static func getStore(): Option<LocalKVStore> {
        mutex.lock()
        let res = store
        mutex.unlock()
        return res
    }
}
