package lanlu.infrastructure.kv

import std.collection.*
import std.sync.*
import std.fs.*
import std.convert.*
import std.time.*
import std.env.getVariable
import lanlu.contexts.system.infrastructure.persistence.*
import lanlu.shared.utils.*
import rocksdb_ffi.OptimisticRocksDb
import rocksdb_ffi.OptimisticRocksDbOptions
import rocksdb_ffi.RocksDbTxn

private class LocalKvBootstrapConfig {
    public var cachePath: String
    public var kvMemoryMb: Int32
    public var blockCacheMb: Int32
    public var maxWriteBufferNumber: Int32
    public var maxOpenFiles: Int32
    public var maxBackgroundJobs: Int32
    public var allowMmapReads: Bool
    public var compression: String

    public init(
        cachePath: String,
        kvMemoryMb: Int32,
        blockCacheMb: Int32,
        maxWriteBufferNumber: Int32,
        maxOpenFiles: Int32,
        maxBackgroundJobs: Int32,
        allowMmapReads: Bool,
        compression: String
    ) {
        this.cachePath = cachePath
        this.kvMemoryMb = kvMemoryMb
        this.blockCacheMb = blockCacheMb
        this.maxWriteBufferNumber = maxWriteBufferNumber
        this.maxOpenFiles = maxOpenFiles
        this.maxBackgroundJobs = maxBackgroundJobs
        this.allowMmapReads = allowMmapReads
        this.compression = compression
    }
}

public interface LocalKVStore {
    func isAvailable(): Bool
    func get(namespace: String, key: String): Option<String>
    func multiGet(namespace: String, keys: Array<String>): Array<Option<String>>
    func put(namespace: String, key: String, value: String): Bool
    func putMany(namespace: String, entries: Array<(String, String)>): Bool
    func delete(namespace: String, key: String): Bool
    func deleteMany(namespace: String, keys: Array<String>): Bool
    func deleteRange(namespace: String, startKey: String, endKey: String): Bool
    func scan(namespace: String, keyPrefix: String): Array<(String, String)>
}

public interface LocalKVTransactionalStore {
    func beginTransaction(namespace: String): (Bool, Option<LocalKVTransaction>, String)
    func isConflictError(error: String): Bool
}

public interface LocalKVTransaction {
    func get(key: String): (Bool, Option<String>, String)
    func multiGet(keys: Array<String>): (Bool, Array<Option<String>>, String)
    func put(key: String, value: String): (Bool, String)
    func delete(key: String): (Bool, String)
    func commit(): (Bool, String)
    func rollback(): (Bool, String)
    func close(): Unit
}

public class RocksDbLocalKVStore <: LocalKVStore {
    private let db: OptimisticRocksDb
    private static let logger = getLogger("rocksdb_local_kv")

    public init(db: OptimisticRocksDb) {
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

    public func putMany(namespace: String, entries: Array<(String, String)>): Bool {
        if (entries.size == 0) {
            return true
        }

        let fullEntries = Array<(String, String)>(entries.size, { i =>
            (composeKey(namespace, entries[i][0]), entries[i][1])
        })
        let (ok, _) = db.writeBatch(fullEntries, [], [], [])
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

public class RocksDbTransactionalStore <: LocalKVTransactionalStore {
    private let db: OptimisticRocksDb

    public init(db: OptimisticRocksDb) {
        this.db = db
    }

    public func beginTransaction(namespace: String): (Bool, Option<LocalKVTransaction>, String) {
        let (ok, txnOpt, err) = db.beginTransaction()
        if (!ok || txnOpt.isNone()) {
            return (ok, None, err)
        }
        return (true, Some(RocksDbNamespaceTransaction(namespace, txnOpt.getOrThrow())), "")
    }

    public func isConflictError(error: String): Bool {
        return OptimisticRocksDb.isConflictError(error)
    }
}

private class RocksDbNamespaceTransaction <: LocalKVTransaction {
    private let namespace: String
    private let txn: RocksDbTxn

    public init(namespace: String, txn: RocksDbTxn) {
        this.namespace = namespace
        this.txn = txn
    }

    public func get(key: String): (Bool, Option<String>, String) {
        return txn.get(composeKey(key))
    }

    public func multiGet(keys: Array<String>): (Bool, Array<Option<String>>, String) {
        return txn.multiGet(Array<String>(keys.size, { i => composeKey(keys[i]) }))
    }

    public func put(key: String, value: String): (Bool, String) {
        return txn.put(composeKey(key), value)
    }

    public func delete(key: String): (Bool, String) {
        return txn.delete(composeKey(key))
    }

    public func commit(): (Bool, String) {
        return txn.commit()
    }

    public func rollback(): (Bool, String) {
        return txn.rollback()
    }

    public func close(): Unit {
        txn.close()
    }

    private func composeKey(key: String): String {
        return "${namespace}:${key}"
    }
}

public class LocalKVService {
    private static let logger = getLogger("local_kv_service")
    private static let mutex = Mutex()
    private static let defaultCachePath = "./data/cache"
    private static let defaultKvMemoryMb: Int32 = 64
    private static let minKvMemoryMb: Int32 = 4
    private static let defaultBlockCacheMb: Int32 = 64
    private static let minBlockCacheMb: Int32 = 4
    private static let defaultMaxWriteBufferNumber: Int32 = 4
    private static let minMaxWriteBufferNumber: Int32 = 1
    private static let defaultMaxOpenFiles: Int32 = 256
    private static let minMaxOpenFiles: Int32 = -1
    private static let defaultMaxBackgroundJobs: Int32 = 2
    private static let minMaxBackgroundJobs: Int32 = 1
    private static let defaultAllowMmapReads: Bool = true
    private static let defaultCompression = "none"
    private static var initialized = false
    private static var store: Option<LocalKVStore> = Option<LocalKVStore>.None
    private static var transactionalStore: Option<LocalKVTransactionalStore> = Option<LocalKVTransactionalStore>.None

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
        let dbOptions = OptimisticRocksDbOptions(
            bootstrapConfig.kvMemoryMb,
            bootstrapConfig.blockCacheMb,
            bootstrapConfig.maxWriteBufferNumber,
            bootstrapConfig.maxOpenFiles,
            bootstrapConfig.maxBackgroundJobs,
            bootstrapConfig.allowMmapReads,
            mapCompressionType(bootstrapConfig.compression)
        )

        let (ok, dbOpt, err) = OptimisticRocksDb.openOptimistic(dbPath, dbOptions)
        if (!ok) {
            logger.warn(
                "Failed to initialize RocksDB local KV; falling back to no-cache mode",
                ("path", dbPath),
                ("kv_memory_mb", bootstrapConfig.kvMemoryMb.toString()),
                ("block_cache_mb", bootstrapConfig.blockCacheMb.toString()),
                ("max_write_buffer_number", bootstrapConfig.maxWriteBufferNumber.toString()),
                ("max_open_files", bootstrapConfig.maxOpenFiles.toString()),
                ("max_background_jobs", bootstrapConfig.maxBackgroundJobs.toString()),
                ("allow_mmap_reads", bootstrapConfig.allowMmapReads.toString()),
                ("compression", bootstrapConfig.compression),
                ("error", err)
            )
            store = Option<LocalKVStore>.None
            mutex.unlock()
            return false
        }

        let db = dbOpt.getOrThrow()
        store = Option<LocalKVStore>.Some(RocksDbLocalKVStore(db))
        transactionalStore = Option<LocalKVTransactionalStore>.Some(RocksDbTransactionalStore(db))
        logger.info(
            "Initialized RocksDB local KV",
            ("path", dbPath),
            ("kv_memory_mb", bootstrapConfig.kvMemoryMb.toString()),
            ("block_cache_mb", bootstrapConfig.blockCacheMb.toString()),
            ("max_write_buffer_number", bootstrapConfig.maxWriteBufferNumber.toString()),
            ("max_open_files", bootstrapConfig.maxOpenFiles.toString()),
            ("max_background_jobs", bootstrapConfig.maxBackgroundJobs.toString()),
            ("allow_mmap_reads", bootstrapConfig.allowMmapReads.toString()),
            ("compression", bootstrapConfig.compression)
        )
        mutex.unlock()
        return true
    }

    public static func getStore(): Option<LocalKVStore> {
        mutex.lock()
        let res = store
        mutex.unlock()
        return res
    }

    public static func getTransactionalStore(): Option<LocalKVTransactionalStore> {
        mutex.lock()
        let res = transactionalStore
        mutex.unlock()
        return res
    }

    private static func resolveBootstrapConfig(): LocalKvBootstrapConfig {
        let fallbackCachePath = normalizeCachePath(getVariable("CACHE_PATH") ?? defaultCachePath)
        let cachePath = resolveBootstrapCachePath(fallbackCachePath)
        let kvMemoryMb = clampKvMemoryMb(resolveBootstrapInt32("ROCKSDB_KV_MEMORY_MB", defaultKvMemoryMb))
        let blockCacheMb = clampBlockCacheMb(resolveBootstrapInt32("ROCKSDB_BLOCK_CACHE_MB", defaultBlockCacheMb))
        let maxWriteBufferNumber = clampMaxWriteBufferNumber(resolveBootstrapInt32("ROCKSDB_MAX_WRITE_BUFFER_NUMBER", defaultMaxWriteBufferNumber))
        let maxOpenFiles = clampMaxOpenFiles(resolveBootstrapInt32("ROCKSDB_MAX_OPEN_FILES", defaultMaxOpenFiles))
        let maxBackgroundJobs = clampMaxBackgroundJobs(resolveBootstrapInt32("ROCKSDB_MAX_BACKGROUND_JOBS", defaultMaxBackgroundJobs))
        let allowMmapReads = resolveBootstrapBoolean("ROCKSDB_ALLOW_MMAP_READS", defaultAllowMmapReads)
        let compression = normalizeCompression(resolveBootstrapString("ROCKSDB_COMPRESSION", defaultCompression))
        return LocalKvBootstrapConfig(
            cachePath,
            kvMemoryMb,
            blockCacheMb,
            maxWriteBufferNumber,
            maxOpenFiles,
            maxBackgroundJobs,
            allowMmapReads,
            compression
        )
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

    private static func resolveBootstrapString(key: String, fallback: String): String {
        let envValue = getVariable(key) ?? fallback
        match (SystemSettingsDao.getBootstrapValue(key)) {
            case Some(value) =>
                let trimmed = value.trimAscii()
                if (trimmed.size > 0) {
                    return trimmed
                }
            case None => ()
        }
        return envValue.trimAscii()
    }

    private static func resolveBootstrapInt32(key: String, fallback: Int32): Int32 {
        let envValue = parseInt32OrDefault(getVariable(key) ?? "", fallback)
        match (SystemSettingsDao.getBootstrapValue(key)) {
            case Some(value) => return parseInt32OrDefault(value, envValue)
            case None => return envValue
        }
    }

    private static func resolveBootstrapBoolean(key: String, fallback: Bool): Bool {
        let envValue = parseBooleanOrDefault(getVariable(key) ?? "", fallback)
        match (SystemSettingsDao.getBootstrapValue(key)) {
            case Some(value) => return parseBooleanOrDefault(value, envValue)
            case None => return envValue
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

    private static func clampBlockCacheMb(value: Int32): Int32 {
        var out = value
        if (out <= 0) {
            out = defaultBlockCacheMb
        }
        if (out < minBlockCacheMb) {
            out = minBlockCacheMb
        }
        return out
    }

    private static func clampMaxWriteBufferNumber(value: Int32): Int32 {
        var out = value
        if (out <= 0) {
            out = defaultMaxWriteBufferNumber
        }
        if (out < minMaxWriteBufferNumber) {
            out = minMaxWriteBufferNumber
        }
        return out
    }

    private static func clampMaxOpenFiles(value: Int32): Int32 {
        if (value == 0 || value < minMaxOpenFiles) {
            return defaultMaxOpenFiles
        }
        return value
    }

    private static func clampMaxBackgroundJobs(value: Int32): Int32 {
        var out = value
        if (out <= 0) {
            out = defaultMaxBackgroundJobs
        }
        if (out < minMaxBackgroundJobs) {
            out = minMaxBackgroundJobs
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

    private static func parseBooleanOrDefault(value: String, fallback: Bool): Bool {
        let trimmed = value.trimAscii().toAsciiLower()
        if (trimmed.size == 0) {
            return fallback
        }

        if (trimmed == "true" || trimmed == "1" || trimmed == "yes" || trimmed == "on") {
            return true
        }
        if (trimmed == "false" || trimmed == "0" || trimmed == "no" || trimmed == "off") {
            return false
        }
        return fallback
    }

    private static func normalizeCompression(value: String): String {
        let trimmed = value.trimAscii().toAsciiLower()
        match (trimmed) {
            case "none" => return "none"
            case "snappy" => return "snappy"
            case "zlib" => return "zlib"
            case "bz2" => return "bz2"
            case "lz4" => return "lz4"
            case "lz4hc" => return "lz4hc"
            case "xpress" => return "xpress"
            case "zstd" => return "zstd"
            case _ => return defaultCompression
        }
    }

    private static func mapCompressionType(compression: String): Int32 {
        match (compression) {
            case "snappy" => return 1
            case "zlib" => return 2
            case "bz2" => return 3
            case "lz4" => return 4
            case "lz4hc" => return 5
            case "xpress" => return 6
            case "zstd" => return 7
            case _ => return 0
        }
    }
}
