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
import rocksdb_ffi.RocksDbCompression
import rocksdb_ffi.RocksDbOperationResult
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
    func getResult(namespace: String, key: String): LocalKVResult<String>
    func multiGet(namespace: String, keys: Array<String>): Array<Option<String>>
    func multiGetResult(namespace: String, keys: Array<String>): LocalKVResult<Array<Option<String>>>
    func put(namespace: String, key: String, value: String): Bool
    func putResult(namespace: String, key: String, value: String): LocalKVResult<Unit>
    func putMany(namespace: String, entries: Array<(String, String)>): Bool
    func putManyResult(namespace: String, entries: Array<(String, String)>): LocalKVResult<Unit>
    func delete(namespace: String, key: String): Bool
    func deleteResult(namespace: String, key: String): LocalKVResult<Unit>
    func deleteMany(namespace: String, keys: Array<String>): Bool
    func deleteManyResult(namespace: String, keys: Array<String>): LocalKVResult<Unit>
    func deleteRange(namespace: String, startKey: String, endKey: String): Bool
    func deleteRangeResult(namespace: String, startKey: String, endKey: String): LocalKVResult<Unit>
    func scan(namespace: String, keyPrefix: String): Array<(String, String)>
    func scanResult(namespace: String, keyPrefix: String): LocalKVResult<Array<(String, String)>>
}

public enum LocalKVResult<T> {
    | Ok(T)
    | NotFound
    | Err(String)

    public func isOk(): Bool {
        match (this) {
            case Ok(_) => return true
            case _ => return false
        }
    }
}

public interface LocalKVTransactionalStore {
    func beginTransactionResult(namespace: String): LocalKVResult<LocalKVTransaction>
    func isConflictError(error: String): Bool
}

public interface LocalKVTransaction <: Resource {
    func getResult(key: String): LocalKVResult<String>
    func multiGetResult(keys: Array<String>): LocalKVResult<Array<Option<String>>>
    func putResult(key: String, value: String): LocalKVResult<Unit>
    func deleteResult(key: String): LocalKVResult<Unit>
    func commitResult(): LocalKVResult<Unit>
    func rollbackResult(): LocalKVResult<Unit>
    func close(): Unit
}

private class LocalKVKeys {
    public static func compose(namespace: String, key: String): String {
        return "${namespace}:${key}"
    }

    public static func stripNamespace(storageKey: String, namespace: String): Option<String> {
        let namespacePrefix = "${namespace}:"
        if (storageKey.startsWith(namespacePrefix) && storageKey.size >= namespacePrefix.size) {
            return Some(storageKey[namespacePrefix.size..storageKey.size])
        }
        return None
    }
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
        match (getResult(namespace, key)) {
            case Ok(value) => return Some(value)
            case NotFound => return None
            case Err(_) => return None
        }
    }

    public func getResult(namespace: String, key: String): LocalKVResult<String> {
        match (db.getResult(LocalKVKeys.compose(namespace, key))) {
            case RocksDbOperationResult<String>.Ok(value) => return LocalKVResult<String>.Ok(value)
            case RocksDbOperationResult<String>.NotFound => return LocalKVResult<String>.NotFound
            case RocksDbOperationResult<String>.Err(error) =>
                logger.warn(
                    "RocksDB get failed",
                    ("namespace", namespace),
                    ("key", key),
                    ("error", error.message)
                )
                return LocalKVResult<String>.Err(error.message)
        }
    }

    public func multiGet(namespace: String, keys: Array<String>): Array<Option<String>> {
        if (keys.size == 0) {
            return []
        }

        let t0 = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let fullKeys = Array<String>(keys.size, {i => LocalKVKeys.compose(namespace, keys[i])})
        let t1 = DateTime.now().toUnixTimeStamp().toMilliseconds()

        logger.debug(
            "[KV] RocksDb multiGet calling",
            ("namespace", namespace),
            ("key_count", keys.size.toString()),
            ("compose_ms", (t1 - t0).toString())
        )

        let result = db.multiGetResult(fullKeys)
        let t2 = DateTime.now().toUnixTimeStamp().toMilliseconds()

        match (result) {
            case RocksDbOperationResult<Array<Option<String>>>.Ok(values) =>
                let foundCount = values.filter({v => v.isSome()}).size
                logger.debug(
                    "[KV] RocksDb multiGet completed",
                    ("namespace", namespace),
                    ("key_count", keys.size.toString()),
                    ("found_count", foundCount.toString()),
                    ("rocksdb_ms", (t2 - t1).toString()),
                    ("total_ms", (t2 - t0).toString())
                )
                return values
            case RocksDbOperationResult<Array<Option<String>>>.Err(error) =>
                logger.warn(
                    "[KV] RocksDb multiGet failed",
                    ("namespace", namespace),
                    ("key_count", keys.size.toString()),
                    ("rocksdb_ms", (t2 - t1).toString()),
                    ("error", error.message)
                )
                return Array<Option<String>>(keys.size, {_ => None})
            case RocksDbOperationResult<Array<Option<String>>>.NotFound =>
                return Array<Option<String>>(keys.size, {_ => None})
        }
    }

    public func multiGetResult(namespace: String, keys: Array<String>): LocalKVResult<Array<Option<String>>> {
        if (keys.size == 0) {
            return LocalKVResult<Array<Option<String>>>.Ok([])
        }
        let fullKeys = Array<String>(keys.size, {i => LocalKVKeys.compose(namespace, keys[i])})
        match (db.multiGetResult(fullKeys)) {
            case RocksDbOperationResult<Array<Option<String>>>.Ok(values) => return LocalKVResult<Array<Option<String>>>.Ok(values)
            case RocksDbOperationResult<Array<Option<String>>>.NotFound => return LocalKVResult<Array<Option<String>>>.NotFound
            case RocksDbOperationResult<Array<Option<String>>>.Err(error) => return LocalKVResult<Array<Option<String>>>.Err(error.message)
        }
    }

    public func put(namespace: String, key: String, value: String): Bool {
        match (putResult(namespace, key, value)) {
            case LocalKVResult<Unit>.Ok(_) => return true
            case LocalKVResult<Unit>.Err(err) =>
                logger.warn(
                    "RocksDB put failed",
                    ("namespace", namespace),
                    ("key", key),
                    ("error", err)
                )
                return false
            case LocalKVResult<Unit>.NotFound => return false
        }
    }

    public func putResult(namespace: String, key: String, value: String): LocalKVResult<Unit> {
        match (db.putResult(LocalKVKeys.compose(namespace, key), value)) {
            case RocksDbOperationResult<Unit>.Ok(_) => return LocalKVResult<Unit>.Ok(())
            case RocksDbOperationResult<Unit>.NotFound => return LocalKVResult<Unit>.NotFound
            case RocksDbOperationResult<Unit>.Err(error) => return LocalKVResult<Unit>.Err(error.message)
        }
    }

    public func putMany(namespace: String, entries: Array<(String, String)>): Bool {
        match (putManyResult(namespace, entries)) {
            case LocalKVResult<Unit>.Ok(_) => return true
            case LocalKVResult<Unit>.Err(err) =>
                logger.warn(
                    "RocksDB putMany failed",
                    ("namespace", namespace),
                    ("entry_count", entries.size.toString()),
                    ("error", err)
                )
                return false
            case LocalKVResult<Unit>.NotFound => return false
        }
    }

    public func putManyResult(namespace: String, entries: Array<(String, String)>): LocalKVResult<Unit> {
        if (entries.size == 0) {
            return LocalKVResult<Unit>.Ok(())
        }

        let fullEntries = Array<(String, String)>(entries.size, {
            i => (LocalKVKeys.compose(namespace, entries[i][0]), entries[i][1])
        })
        match (db.writeBatchResult(fullEntries, [], [], [])) {
            case RocksDbOperationResult<Unit>.Ok(_) => return LocalKVResult<Unit>.Ok(())
            case RocksDbOperationResult<Unit>.NotFound => return LocalKVResult<Unit>.NotFound
            case RocksDbOperationResult<Unit>.Err(error) => return LocalKVResult<Unit>.Err(error.message)
        }
    }

    public func delete(namespace: String, key: String): Bool {
        match (deleteResult(namespace, key)) {
            case LocalKVResult<Unit>.Ok(_) => return true
            case LocalKVResult<Unit>.Err(err) =>
                logger.warn(
                    "RocksDB delete failed",
                    ("namespace", namespace),
                    ("key", key),
                    ("error", err)
                )
                return false
            case LocalKVResult<Unit>.NotFound => return false
        }
    }

    public func deleteResult(namespace: String, key: String): LocalKVResult<Unit> {
        match (db.deleteResult(LocalKVKeys.compose(namespace, key))) {
            case RocksDbOperationResult<Unit>.Ok(_) => return LocalKVResult<Unit>.Ok(())
            case RocksDbOperationResult<Unit>.NotFound => return LocalKVResult<Unit>.NotFound
            case RocksDbOperationResult<Unit>.Err(error) => return LocalKVResult<Unit>.Err(error.message)
        }
    }

    public func deleteMany(namespace: String, keys: Array<String>): Bool {
        match (deleteManyResult(namespace, keys)) {
            case LocalKVResult<Unit>.Ok(_) => return true
            case LocalKVResult<Unit>.Err(err) =>
                logger.warn(
                    "RocksDB deleteMany failed",
                    ("namespace", namespace),
                    ("key_count", keys.size.toString()),
                    ("error", err)
                )
                return false
            case LocalKVResult<Unit>.NotFound => return false
        }
    }

    public func deleteManyResult(namespace: String, keys: Array<String>): LocalKVResult<Unit> {
        if (keys.size == 0) {
            return LocalKVResult<Unit>.Ok(())
        }

        let fullKeys = Array<String>(keys.size, {i => LocalKVKeys.compose(namespace, keys[i])})
        match (db.deleteManyResult(fullKeys)) {
            case RocksDbOperationResult<Unit>.Ok(_) => return LocalKVResult<Unit>.Ok(())
            case RocksDbOperationResult<Unit>.NotFound => return LocalKVResult<Unit>.NotFound
            case RocksDbOperationResult<Unit>.Err(error) => return LocalKVResult<Unit>.Err(error.message)
        }
    }

    public func deleteRange(namespace: String, startKey: String, endKey: String): Bool {
        match (deleteRangeResult(namespace, startKey, endKey)) {
            case LocalKVResult<Unit>.Ok(_) => return true
            case LocalKVResult<Unit>.Err(err) =>
                logger.warn(
                    "RocksDB deleteRange failed",
                    ("namespace", namespace),
                    ("start_key", startKey),
                    ("end_key", endKey),
                    ("error", err)
                )
                return false
            case LocalKVResult<Unit>.NotFound => return false
        }
    }

    public func deleteRangeResult(namespace: String, startKey: String, endKey: String): LocalKVResult<Unit> {
        match (db.deleteRangeResult(LocalKVKeys.compose(namespace, startKey), LocalKVKeys.compose(namespace, endKey))) {
            case RocksDbOperationResult<Unit>.Ok(_) => return LocalKVResult<Unit>.Ok(())
            case RocksDbOperationResult<Unit>.NotFound => return LocalKVResult<Unit>.NotFound
            case RocksDbOperationResult<Unit>.Err(error) => return LocalKVResult<Unit>.Err(error.message)
        }
    }

    public func scan(namespace: String, keyPrefix: String): Array<(String, String)> {
        let fullPrefix = LocalKVKeys.compose(namespace, keyPrefix)
        let pairs = match (db.scanByPrefixResult(fullPrefix)) {
            case RocksDbOperationResult<Array<(String, String)>>.Ok(items) => items
            case RocksDbOperationResult<Array<(String, String)>>.Err(error) =>
                logger.warn(
                    "RocksDB scan failed",
                    ("namespace", namespace),
                    ("key_prefix", keyPrefix),
                    ("error", error.message)
                )
                return []
            case RocksDbOperationResult<Array<(String, String)>>.NotFound => return []
        }

        let entries = ArrayList<(String, String)>()
        for ((key, value) in pairs) {
            match (LocalKVKeys.stripNamespace(key, namespace)) {
                case Some(localKey) => entries.add((localKey, value))
                case None => ()
            }
        }
        return entries.toArray()
    }

    public func scanResult(namespace: String, keyPrefix: String): LocalKVResult<Array<(String, String)>> {
        let fullPrefix = LocalKVKeys.compose(namespace, keyPrefix)
        match (db.scanByPrefixResult(fullPrefix)) {
            case RocksDbOperationResult<Array<(String, String)>>.Ok(pairs) =>
                let entries = ArrayList<(String, String)>()
                for ((key, value) in pairs) {
                    match (LocalKVKeys.stripNamespace(key, namespace)) {
                        case Some(localKey) => entries.add((localKey, value))
                        case None => ()
                    }
                }
                return LocalKVResult<Array<(String, String)>>.Ok(entries.toArray())
            case RocksDbOperationResult<Array<(String, String)>>.NotFound => return LocalKVResult<Array<(String, String)>>.NotFound
            case RocksDbOperationResult<Array<(String, String)>>.Err(error) => return LocalKVResult<Array<(String, String)>>.Err(error.message)
        }
    }
}

public class RocksDbTransactionalStore <: LocalKVTransactionalStore {
    private let db: OptimisticRocksDb

    public init(db: OptimisticRocksDb) {
        this.db = db
    }

    public func beginTransactionResult(namespace: String): LocalKVResult<LocalKVTransaction> {
        match (db.beginTransactionResult()) {
            case RocksDbOperationResult<RocksDbTxn>.Ok(txn) => return LocalKVResult<LocalKVTransaction>.Ok(RocksDbNamespaceTransaction(namespace, txn))
            case RocksDbOperationResult<RocksDbTxn>.NotFound => return LocalKVResult<LocalKVTransaction>.NotFound
            case RocksDbOperationResult<RocksDbTxn>.Err(error) => return LocalKVResult<LocalKVTransaction>.Err(error.message)
        }
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

    public func getResult(key: String): LocalKVResult<String> {
        match (txn.getResult(LocalKVKeys.compose(namespace, key))) {
            case RocksDbOperationResult<String>.Ok(value) => return LocalKVResult<String>.Ok(value)
            case RocksDbOperationResult<String>.NotFound => return LocalKVResult<String>.NotFound
            case RocksDbOperationResult<String>.Err(error) => return LocalKVResult<String>.Err(error.message)
        }
    }

    public func multiGetResult(keys: Array<String>): LocalKVResult<Array<Option<String>>> {
        match (txn.multiGetResult(Array<String>(keys.size, {i => LocalKVKeys.compose(namespace, keys[i])}))) {
            case RocksDbOperationResult<Array<Option<String>>>.Ok(values) => return LocalKVResult<Array<Option<String>>>.Ok(values)
            case RocksDbOperationResult<Array<Option<String>>>.NotFound => return LocalKVResult<Array<Option<String>>>.NotFound
            case RocksDbOperationResult<Array<Option<String>>>.Err(error) => return LocalKVResult<Array<Option<String>>>.Err(error.message)
        }
    }

    public func putResult(key: String, value: String): LocalKVResult<Unit> {
        match (txn.putResult(LocalKVKeys.compose(namespace, key), value)) {
            case RocksDbOperationResult<Unit>.Ok(_) => return LocalKVResult<Unit>.Ok(())
            case RocksDbOperationResult<Unit>.NotFound => return LocalKVResult<Unit>.NotFound
            case RocksDbOperationResult<Unit>.Err(error) => return LocalKVResult<Unit>.Err(error.message)
        }
    }

    public func deleteResult(key: String): LocalKVResult<Unit> {
        match (txn.deleteResult(LocalKVKeys.compose(namespace, key))) {
            case RocksDbOperationResult<Unit>.Ok(_) => return LocalKVResult<Unit>.Ok(())
            case RocksDbOperationResult<Unit>.NotFound => return LocalKVResult<Unit>.NotFound
            case RocksDbOperationResult<Unit>.Err(error) => return LocalKVResult<Unit>.Err(error.message)
        }
    }

    public func commitResult(): LocalKVResult<Unit> {
        match (txn.commitResult()) {
            case RocksDbOperationResult<Unit>.Ok(_) => return LocalKVResult<Unit>.Ok(())
            case RocksDbOperationResult<Unit>.NotFound => return LocalKVResult<Unit>.NotFound
            case RocksDbOperationResult<Unit>.Err(error) => return LocalKVResult<Unit>.Err(error.message)
        }
    }

    public func rollbackResult(): LocalKVResult<Unit> {
        match (txn.rollbackResult()) {
            case RocksDbOperationResult<Unit>.Ok(_) => return LocalKVResult<Unit>.Ok(())
            case RocksDbOperationResult<Unit>.NotFound => return LocalKVResult<Unit>.NotFound
            case RocksDbOperationResult<Unit>.Err(error) => return LocalKVResult<Unit>.Err(error.message)
        }
    }

    public func close(): Unit {
        txn.close()
    }

    public func isClosed(): Bool {
        return txn.isClosed()
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
        return synchronized(mutex) {
            if (initialized) {
                return !store.isNone()
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
                return false
            }

            if (let Some(db) <- dbOpt) {
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
                return true
            }

            logger.warn("RocksDB local KV opened successfully but returned no handle", ("path", dbPath))
            store = Option<LocalKVStore>.None
            transactionalStore = Option<LocalKVTransactionalStore>.None
            return false
        }
    }

    public static func getStore(): Option<LocalKVStore> {
        return synchronized(mutex) {
            return store
        }
    }

    public static func getTransactionalStore(): Option<LocalKVTransactionalStore> {
        return synchronized(mutex) {
            return transactionalStore
        }
    }

    private static func resolveBootstrapConfig(): LocalKvBootstrapConfig {
        let fallbackCachePath = normalizeCachePath(getVariable("CACHE_PATH") ?? defaultCachePath)
        let cachePath = resolveBootstrapCachePath(fallbackCachePath)
        let kvMemoryMb = clampKvMemoryMb(resolveBootstrapInt32("ROCKSDB_KV_MEMORY_MB", defaultKvMemoryMb))
        let blockCacheMb = clampBlockCacheMb(resolveBootstrapInt32("ROCKSDB_BLOCK_CACHE_MB", defaultBlockCacheMb))
        let maxWriteBufferNumber = clampMaxWriteBufferNumber(
            resolveBootstrapInt32("ROCKSDB_MAX_WRITE_BUFFER_NUMBER", defaultMaxWriteBufferNumber))
        let maxOpenFiles = clampMaxOpenFiles(resolveBootstrapInt32("ROCKSDB_MAX_OPEN_FILES", defaultMaxOpenFiles))
        let maxBackgroundJobs = clampMaxBackgroundJobs(
            resolveBootstrapInt32("ROCKSDB_MAX_BACKGROUND_JOBS", defaultMaxBackgroundJobs))
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
        return if (trimmed.size > 0) {
            trimmed
        } else {
            defaultCachePath
        }
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

    private static func mapCompressionType(compression: String): RocksDbCompression {
        match (compression) {
            case "snappy" => return RocksDbCompression.Snappy
            case "zlib" => return RocksDbCompression.Zlib
            case "bz2" => return RocksDbCompression.Bz2
            case "lz4" => return RocksDbCompression.Lz4
            case "lz4hc" => return RocksDbCompression.Lz4hc
            case "xpress" => return RocksDbCompression.Xpress
            case "zstd" => return RocksDbCompression.Zstd
            case _ => return RocksDbCompression.NoCompression
        }
    }
}
