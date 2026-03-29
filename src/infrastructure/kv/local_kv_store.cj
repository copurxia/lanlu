package lanlu.infrastructure.kv

import std.sync.*
import std.fs.*
import lanlu.contexts.system.application.SystemSettingsService
import lanlu.shared.utils.*
import rocksdb_ffi.RocksDb

public interface LocalKVStore {
    func isAvailable(): Bool
    func get(namespace: String, key: String): Option<String>
    func put(namespace: String, key: String, value: String): Bool
    func delete(namespace: String, key: String): Bool
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

    public func put(namespace: String, key: String, value: String): Bool {
        let (ok, _) = db.put(composeKey(namespace, key), value)
        return ok
    }

    public func delete(namespace: String, key: String): Bool {
        let (ok, _) = db.delete(composeKey(namespace, key))
        return ok
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

        let (ok, dbOpt, err) = RocksDb.openLowMemory(dbPath)
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
