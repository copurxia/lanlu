package rocksdb_ffi

import std.collection.*

public enum RocksDbCompression {
    | NoCompression
    | Snappy
    | Zlib
    | Bz2
    | Lz4
    | Lz4hc
    | Xpress
    | Zstd

    public func toNative(): Int32 {
        match (this) {
            case NoCompression => return ROCKSDB_NO_COMPRESSION
            case Snappy => return ROCKSDB_SNAPPY_COMPRESSION
            case Zlib => return ROCKSDB_ZLIB_COMPRESSION
            case Bz2 => return ROCKSDB_BZ2_COMPRESSION
            case Lz4 => return ROCKSDB_LZ4_COMPRESSION
            case Lz4hc => return ROCKSDB_LZ4HC_COMPRESSION
            case Xpress => return ROCKSDB_XPRESS_COMPRESSION
            case Zstd => return ROCKSDB_ZSTD_COMPRESSION
        }
    }

    public static func fromNative(value: Int32): RocksDbCompression {
        if (value == ROCKSDB_SNAPPY_COMPRESSION) {
            return Snappy
        }
        if (value == ROCKSDB_ZLIB_COMPRESSION) {
            return Zlib
        }
        if (value == ROCKSDB_BZ2_COMPRESSION) {
            return Bz2
        }
        if (value == ROCKSDB_LZ4_COMPRESSION) {
            return Lz4
        }
        if (value == ROCKSDB_LZ4HC_COMPRESSION) {
            return Lz4hc
        }
        if (value == ROCKSDB_XPRESS_COMPRESSION) {
            return Xpress
        }
        if (value == ROCKSDB_ZSTD_COMPRESSION) {
            return Zstd
        }
        return NoCompression
    }
}

public enum RocksDbErrorKind {
    | NotFound
    | Conflict
    | Closed
    | FfiFailure
    | DecodeFailure
}

public class RocksDbError {
    public let kind: RocksDbErrorKind
    public let message: String

    public init(kind: RocksDbErrorKind, message: String) {
        this.kind = kind
        this.message = message
    }
}

public class RocksDbResult<T> {
    public let ok: Bool
    public let value: Option<T>
    public let error: Option<RocksDbError>

    public init(ok: Bool, value: Option<T>, error: Option<RocksDbError>) {
        this.ok = ok
        this.value = value
        this.error = error
    }
}

public enum RocksDbOperationResult<T> {
    | Ok(T)
    | NotFound
    | Err(RocksDbError)
}

public func classifyRocksDbError(error: String): RocksDbErrorKind {
    let normalized = error.toAsciiLower()
    if (normalized.size == 0) {
        return RocksDbErrorKind.FfiFailure
    }
    if (normalized.contains("notfound") || normalized.contains("not found")) {
        return RocksDbErrorKind.NotFound
    }
    if (normalized.contains("closed")) {
        return RocksDbErrorKind.Closed
    }
    if (OptimisticRocksDb.isConflictError(error)) {
        return RocksDbErrorKind.Conflict
    }
    return RocksDbErrorKind.FfiFailure
}

public class OptimisticRocksDbOptions {
    public let kvMemoryMb: Int32
    public let blockCacheMb: Int32
    public let maxWriteBufferNumber: Int32
    public let maxOpenFiles: Int32
    public let maxBackgroundJobs: Int32
    public let allowMmapReads: Bool
    public let compression: RocksDbCompression

    public init(
        kvMemoryMb: Int32,
        blockCacheMb: Int32,
        maxWriteBufferNumber: Int32,
        maxOpenFiles: Int32,
        maxBackgroundJobs: Int32,
        allowMmapReads: Bool,
        compression: RocksDbCompression
    ) {
        this.kvMemoryMb = kvMemoryMb
        this.blockCacheMb = blockCacheMb
        this.maxWriteBufferNumber = maxWriteBufferNumber
        this.maxOpenFiles = maxOpenFiles
        this.maxBackgroundJobs = maxBackgroundJobs
        this.allowMmapReads = allowMmapReads
        this.compression = compression
    }

    public init(
        kvMemoryMb: Int32,
        blockCacheMb: Int32,
        maxWriteBufferNumber: Int32,
        maxOpenFiles: Int32,
        maxBackgroundJobs: Int32,
        allowMmapReads: Bool,
        compressionType: Int32
    ) {
        this(
            kvMemoryMb,
            blockCacheMb,
            maxWriteBufferNumber,
            maxOpenFiles,
            maxBackgroundJobs,
            allowMmapReads,
            RocksDbCompression.fromNative(compressionType)
        )
    }
}

public class RocksDb {
    private static let defaultKvMemoryMb: Int32 = 16
    private static let minKvMemoryMb: Int32 = 4
    private static let dbWriteBufferMultiplier: UIntNative = 4
    private static let blockCacheSizeBytes: UIntNative = 64 * 1024 * 1024
    private let db: CPointer<rocksdb_t>
    private let readOptions: CPointer<rocksdb_readoptions_t>
    private let writeOptions: CPointer<rocksdb_writeoptions_t>
    private var closed: Bool = false

    private init(
        db: CPointer<rocksdb_t>,
        readOptions: CPointer<rocksdb_readoptions_t>,
        writeOptions: CPointer<rocksdb_writeoptions_t>
    ) {
        this.db = db
        this.readOptions = readOptions
        this.writeOptions = writeOptions
    }

    public static func openBalanced(path: String, kvMemoryMb: Int32): (Bool, Option<RocksDb>, String) {
        let normalizedKvMemoryMb = normalizeKvMemoryMb(kvMemoryMb)
        let writeBufferSizeBytes = mbToBytes(normalizedKvMemoryMb)
        let dbWriteBufferSizeBytes = writeBufferSizeBytes * dbWriteBufferMultiplier
        let options = unsafe { rocksdb_options_create() }
        if (options.isNull()) {
            return (false, None, "rocksdb_options_create failed")
        }

        let tableOptions = unsafe { rocksdb_block_based_options_create() }
        if (tableOptions.isNull()) {
            unsafe { rocksdb_options_destroy(options) }
            return (false, None, "rocksdb_block_based_options_create failed")
        }

        let blockCache = unsafe { rocksdb_cache_create_lru(blockCacheSizeBytes) }
        if (blockCache.isNull()) {
            unsafe {
                rocksdb_block_based_options_destroy(tableOptions)
                rocksdb_options_destroy(options)
            }
            return (false, None, "rocksdb_cache_create_lru failed")
        }

        unsafe {
            rocksdb_options_set_create_if_missing(options, 1u8)
            rocksdb_options_set_paranoid_checks(options, 0u8)
            rocksdb_options_set_compression(options, ROCKSDB_NO_COMPRESSION)
            rocksdb_options_set_write_buffer_size(options, writeBufferSizeBytes)
            rocksdb_options_set_db_write_buffer_size(options, dbWriteBufferSizeBytes)
            rocksdb_options_set_max_write_buffer_number(options, 4)
            rocksdb_options_set_min_write_buffer_number_to_merge(options, 1)
            rocksdb_options_set_max_write_buffer_number_to_maintain(options, 1)
            rocksdb_options_set_max_open_files(options, 256)
            rocksdb_options_set_max_background_jobs(options, 2)
            rocksdb_options_set_keep_log_file_num(options, 2)
            rocksdb_options_set_use_fsync(options, 0u8)
            rocksdb_options_set_allow_mmap_reads(options, 1u8)
            rocksdb_options_set_bytes_per_sync(options, 0u64)

            // Keep block cache fixed and let the memtable size be configured
            // from system settings.
            rocksdb_block_based_options_set_no_block_cache(tableOptions, 0u8)
            rocksdb_block_based_options_set_block_cache(tableOptions, blockCache)
            rocksdb_block_based_options_set_cache_index_and_filter_blocks(tableOptions, 1u8)
            rocksdb_block_based_options_set_cache_index_and_filter_blocks_with_high_priority(tableOptions, 1u8)
            rocksdb_block_based_options_set_pin_l0_filter_and_index_blocks_in_cache(tableOptions, 1u8)
            rocksdb_block_based_options_set_pin_top_level_index_and_filter(tableOptions, 1u8)
            rocksdb_options_set_block_based_table_factory(options, tableOptions)
        }

        let pathC = unsafe { LibC.mallocCString(path) }
        var errPtr = CPointer<UInt8>()
        let db = unsafe { rocksdb_open(options, pathC, inout errPtr) }
        unsafe {
            LibC.free(pathC)
            rocksdb_block_based_options_destroy(tableOptions)
            rocksdb_cache_destroy(blockCache)
            rocksdb_options_destroy(options)
        }

        if (!errPtr.isNull()) {
            let error = takeOwnedCString(errPtr)
            if (!db.isNull()) {
                unsafe { rocksdb_close(db) }
            }
            return (false, None, error)
        }
        if (db.isNull()) {
            return (false, None, "rocksdb_open returned null")
        }

        let readOptions = unsafe { rocksdb_readoptions_create() }
        let writeOptions = unsafe { rocksdb_writeoptions_create() }
        if (readOptions.isNull() || writeOptions.isNull()) {
            if (!readOptions.isNull()) {
                unsafe { rocksdb_readoptions_destroy(readOptions) }
            }
            if (!writeOptions.isNull()) {
                unsafe { rocksdb_writeoptions_destroy(writeOptions) }
            }
            unsafe { rocksdb_close(db) }
            return (false, None, "rocksdb read/write options init failed")
        }

        unsafe { rocksdb_writeoptions_set_sync(writeOptions, 0u8) }
        return (true, Some(RocksDb(db, readOptions, writeOptions)), "")
    }

    public static func openLowMemory(path: String): (Bool, Option<RocksDb>, String) {
        return openBalanced(path, defaultKvMemoryMb)
    }

    private static func normalizeKvMemoryMb(kvMemoryMb: Int32): Int32 {
        if (kvMemoryMb <= 0) {
            return defaultKvMemoryMb
        }
        if (kvMemoryMb < minKvMemoryMb) {
            return minKvMemoryMb
        }
        return kvMemoryMb
    }

    private static func mbToBytes(memoryMb: Int32): UIntNative {
        return UIntNative(memoryMb) * UIntNative(1024) * UIntNative(1024)
    }

    public func getResult(key: String): RocksDbOperationResult<String> {
        if (closed) {
            return RocksDbOperationResult<String>.Err(RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }

        var valueLen: UIntNative = 0
        var errPtr = CPointer<UInt8>()
        let valuePtr = unsafe {
            let keyBytes = key.toArray()
            let keyHandle = acquireArrayRawData(keyBytes)
            try {
                rocksdb_get(
                    db,
                    readOptions,
                    CString(keyHandle.pointer),
                    UIntNative(keyBytes.size),
                    inout valueLen,
                    inout errPtr
                )
            } finally {
                releaseArrayRawData(keyHandle)
            }
        }

        if (!errPtr.isNull()) {
            let error = takeOwnedCString(errPtr)
            return RocksDbOperationResult<String>.Err(RocksDbError(classifyRocksDbError(error), error))
        }
        if (valuePtr.isNull()) {
            return RocksDbOperationResult<String>.NotFound
        }

        let out = Array<UInt8>(Int64(valueLen), {i => unsafe { (valuePtr + i).read() }})
        unsafe { rocksdb_free(CPointer<Unit>(valuePtr)) }
        return RocksDbOperationResult<String>.Ok(String.fromUtf8(out))
    }

    private func multiGetTuple(keys: Array<String>): (Bool, Array<Option<String>>, String) {
        if (closed) {
            return (false, [], "rocksdb is closed")
        }
        if (keys.size == 0) {
            return (true, [], "")
        }

        let keyPtrs = Array<CString>(keys.size, {_ => CString(CPointer<UInt8>())})
        let keyLens = Array<UIntNative>(keys.size, {_ => UIntNative(0)})
        let valuePtrs = Array<CPointer<UInt8>>(keys.size, {_ => CPointer<UInt8>()})
        let valueLens = Array<UIntNative>(keys.size, {_ => UIntNative(0)})
        let errs = Array<CPointer<UInt8>>(keys.size, {_ => CPointer<UInt8>()})

        for (i in 0..keys.size) {
            let rawKey = unsafe { LibC.mallocCString(keys[i]) }
            keyPtrs[i] = rawKey
            keyLens[i] = UIntNative(keys[i].toArray().size)
        }

        let keyPtrHandle = unsafe { acquireArrayRawData(keyPtrs) }
        let keyLenHandle = unsafe { acquireArrayRawData(keyLens) }
        let valuePtrHandle = unsafe { acquireArrayRawData(valuePtrs) }
        let valueLenHandle = unsafe { acquireArrayRawData(valueLens) }
        let errHandle = unsafe { acquireArrayRawData(errs) }
        try {
            unsafe {
                rocksdb_multi_get(
                    db,
                    readOptions,
                    UIntNative(keys.size),
                    keyPtrHandle.pointer,
                    keyLenHandle.pointer,
                    valuePtrHandle.pointer,
                    valueLenHandle.pointer,
                    errHandle.pointer
                )
            }

            let results = ArrayList<Option<String>>()
            for (i in 0..keys.size) {
                if (!errs[i].isNull()) {
                    let error = unsafe { CString(errs[i]).toString() }
                    return (false, [], error)
                }

                if (valuePtrs[i].isNull()) {
                    results.add(None)
                } else {
                    let value = readCStringBytes(valuePtrs[i], valueLens[i])
                    results.add(Some(value))
                }
            }
            return (true, results.toArray(), "")
        } finally {
            unsafe { releaseArrayRawData(errHandle) }
            unsafe { releaseArrayRawData(valueLenHandle) }
            unsafe { releaseArrayRawData(valuePtrHandle) }
            unsafe { releaseArrayRawData(keyLenHandle) }
            unsafe { releaseArrayRawData(keyPtrHandle) }
            for (i in 0..keyPtrs.size) {
                if (!keyPtrs[i].isNull()) {
                    unsafe { LibC.free(keyPtrs[i]) }
                }
                if (!valuePtrs[i].isNull()) {
                    unsafe { rocksdb_free(CPointer<Unit>(valuePtrs[i])) }
                }
                if (!errs[i].isNull()) {
                    unsafe { rocksdb_free(CPointer<Unit>(errs[i])) }
                }
            }
        }
    }

    public func multiGetResult(keys: Array<String>): RocksDbOperationResult<Array<Option<String>>> {
        let (ok, values, err) = multiGetTuple(keys)
        if (ok) {
            return RocksDbOperationResult<Array<Option<String>>>.Ok(values)
        }
        return RocksDbOperationResult<Array<Option<String>>>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    private func putTuple(key: String, value: String): (Bool, String) {
        if (closed) {
            return (false, "rocksdb is closed")
        }

        unsafe {
            let keyBytes = key.toArray()
            let keyHandle = acquireArrayRawData(keyBytes)
            let valueBytes = value.toArray()
            let valueHandle = acquireArrayRawData(valueBytes)
            var errPtr = CPointer<UInt8>()
            try {
                rocksdb_put(
                    db,
                    writeOptions,
                    CString(keyHandle.pointer),
                    UIntNative(keyBytes.size),
                    CString(valueHandle.pointer),
                    UIntNative(valueBytes.size),
                    inout errPtr
                )
            } finally {
                releaseArrayRawData(valueHandle)
                releaseArrayRawData(keyHandle)
            }

            if (!errPtr.isNull()) {
                return (false, takeOwnedCString(errPtr))
            }
        }
        return (true, "")
    }

    public func putResult(key: String, value: String): RocksDbOperationResult<Unit> {
        let (ok, err) = putTuple(key, value)
        if (ok) {
            return RocksDbOperationResult<Unit>.Ok(())
        }
        return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    public func merge(key: String, value: String): (Bool, String) {
        if (closed) {
            return (false, "rocksdb is closed")
        }

        unsafe {
            let keyBytes = key.toArray()
            let keyHandle = acquireArrayRawData(keyBytes)
            let valueBytes = value.toArray()
            let valueHandle = acquireArrayRawData(valueBytes)
            var errPtr = CPointer<UInt8>()
            try {
                rocksdb_merge(
                    db,
                    writeOptions,
                    CString(keyHandle.pointer),
                    UIntNative(keyBytes.size),
                    CString(valueHandle.pointer),
                    UIntNative(valueBytes.size),
                    inout errPtr
                )
            } finally {
                releaseArrayRawData(valueHandle)
                releaseArrayRawData(keyHandle)
            }

            if (!errPtr.isNull()) {
                return (false, takeOwnedCString(errPtr))
            }
        }
        return (true, "")
    }

    private func deleteTuple(key: String): (Bool, String) {
        if (closed) {
            return (false, "rocksdb is closed")
        }

        unsafe {
            let keyBytes = key.toArray()
            let keyHandle = acquireArrayRawData(keyBytes)
            var errPtr = CPointer<UInt8>()
            try {
                rocksdb_delete(
                    db,
                    writeOptions,
                    CString(keyHandle.pointer),
                    UIntNative(keyBytes.size),
                    inout errPtr
                )
            } finally {
                releaseArrayRawData(keyHandle)
            }

            if (!errPtr.isNull()) {
                return (false, takeOwnedCString(errPtr))
            }
        }
        return (true, "")
    }

    public func deleteResult(key: String): RocksDbOperationResult<Unit> {
        let (ok, err) = deleteTuple(key)
        if (ok) {
            return RocksDbOperationResult<Unit>.Ok(())
        }
        return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    public func deleteRangeResult(startKey: String, endKey: String): RocksDbOperationResult<Unit> {
        return writeBatchResult([], [], [(startKey, endKey)], [])
    }

    public func deleteManyResult(keys: Array<String>): RocksDbOperationResult<Unit> {
        return writeBatchResult([], keys, [], [])
    }

    private func writeBatchTuple(
        puts: Array<(String, String)>,
        deletes: Array<String>,
        deleteRanges: Array<(String, String)>,
        merges: Array<(String, String)>
    ): (Bool, String) {
        if (closed) {
            return (false, "rocksdb is closed")
        }
        if (puts.size == 0 && deletes.size == 0 && deleteRanges.size == 0 && merges.size == 0) {
            return (true, "")
        }

        let batch = unsafe { rocksdb_writebatch_create() }
        if (batch.isNull()) {
            return (false, "rocksdb_writebatch_create failed")
        }

        try {
            for ((key, value) in puts) {
                unsafe {
                    let keyBytes = key.toArray()
                    let keyHandle = acquireArrayRawData(keyBytes)
                    let valueBytes = value.toArray()
                    let valueHandle = acquireArrayRawData(valueBytes)
                    try {
                        rocksdb_writebatch_put(
                            batch,
                            CString(keyHandle.pointer),
                            UIntNative(keyBytes.size),
                            CString(valueHandle.pointer),
                            UIntNative(valueBytes.size)
                        )
                    } finally {
                        releaseArrayRawData(valueHandle)
                        releaseArrayRawData(keyHandle)
                    }
                }
            }

            for ((key, value) in merges) {
                unsafe {
                    let keyBytes = key.toArray()
                    let keyHandle = acquireArrayRawData(keyBytes)
                    let valueBytes = value.toArray()
                    let valueHandle = acquireArrayRawData(valueBytes)
                    try {
                        rocksdb_writebatch_merge(
                            batch,
                            CString(keyHandle.pointer),
                            UIntNative(keyBytes.size),
                            CString(valueHandle.pointer),
                            UIntNative(valueBytes.size)
                        )
                    } finally {
                        releaseArrayRawData(valueHandle)
                        releaseArrayRawData(keyHandle)
                    }
                }
            }

            for (key in deletes) {
                unsafe {
                    let keyBytes = key.toArray()
                    let keyHandle = acquireArrayRawData(keyBytes)
                    try {
                        rocksdb_writebatch_delete(
                            batch,
                            CString(keyHandle.pointer),
                            UIntNative(keyBytes.size)
                        )
                    } finally {
                        releaseArrayRawData(keyHandle)
                    }
                }
            }

            for ((startKey, endKey) in deleteRanges) {
                unsafe {
                    let startBytes = startKey.toArray()
                    let startHandle = acquireArrayRawData(startBytes)
                    let endBytes = endKey.toArray()
                    let endHandle = acquireArrayRawData(endBytes)
                    try {
                        rocksdb_writebatch_delete_range(
                            batch,
                            CString(startHandle.pointer),
                            UIntNative(startBytes.size),
                            CString(endHandle.pointer),
                            UIntNative(endBytes.size)
                        )
                    } finally {
                        releaseArrayRawData(endHandle)
                        releaseArrayRawData(startHandle)
                    }
                }
            }

            var errPtr = CPointer<UInt8>()
            unsafe { rocksdb_write(db, writeOptions, batch, inout errPtr) }
            if (!errPtr.isNull()) {
                return (false, takeOwnedCString(errPtr))
            }
            return (true, "")
        } finally {
            unsafe { rocksdb_writebatch_destroy(batch) }
        }
    }

    public func writeBatchResult(
        puts: Array<(String, String)>,
        deletes: Array<String>,
        deleteRanges: Array<(String, String)>,
        merges: Array<(String, String)>
    ): RocksDbOperationResult<Unit> {
        let (ok, err) = writeBatchTuple(puts, deletes, deleteRanges, merges)
        if (ok) {
            return RocksDbOperationResult<Unit>.Ok(())
        }
        return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    private func scanByPrefixTuple(prefix: String): (Bool, Array<(String, String)>, String) {
        if (closed) {
            return (false, [], "rocksdb is closed")
        }

        let prefixBytes = prefix.toArray()
        let prefixLen = prefixBytes.size
        let upperBoundOpt = nextPrefixUpperBound(prefix)
        let scanOptions = unsafe { rocksdb_readoptions_create() }
        if (scanOptions.isNull()) {
            return (false, [], "rocksdb_readoptions_create failed")
        }

        let results = ArrayList<(String, String)>()
        let prefixHandle = unsafe { acquireArrayRawData(prefixBytes) }
        try {
            unsafe {
                rocksdb_readoptions_set_prefix_same_as_start(scanOptions, 1u8)
                rocksdb_readoptions_set_total_order_seek(scanOptions, 0u8)
            }

            match (upperBoundOpt) {
                case Some(upperBound) =>
                    let upperBoundBytes = upperBound.toArray()
                    let upperBoundHandle = unsafe { acquireArrayRawData(upperBoundBytes) }
                    try {
                        unsafe {
                            rocksdb_readoptions_set_iterate_upper_bound(
                                scanOptions,
                                CString(upperBoundHandle.pointer),
                                UIntNative(upperBoundBytes.size)
                            )
                        }
                        let iter = unsafe { rocksdb_create_iterator(db, scanOptions) }
                        if (iter.isNull()) {
                            return (false, [], "rocksdb_create_iterator failed")
                        }
                        try {
                            unsafe {
                                rocksdb_iter_seek(
                                    iter,
                                    CString(prefixHandle.pointer),
                                    UIntNative(prefixLen)
                                )
                            }

                            while (unsafe { rocksdb_iter_valid(iter) } != 0u8) {
                                let key = readIteratorBytes(iter, true)
                                if (!key.startsWith(prefix)) {
                                    break
                                }
                                let value = readIteratorBytes(iter, false)
                                results.add((key, value))
                                unsafe { rocksdb_iter_next(iter) }
                            }

                            var errPtr = CPointer<UInt8>()
                            unsafe { rocksdb_iter_get_error(iter, inout errPtr) }
                            if (!errPtr.isNull()) {
                                return (false, [], takeOwnedCString(errPtr))
                            }
                        } finally {
                            unsafe { rocksdb_iter_destroy(iter) }
                        }
                    } finally {
                        unsafe { releaseArrayRawData(upperBoundHandle) }
                    }
                case None => ()
            }

            if (upperBoundOpt.isNone()) {
                let iter = unsafe { rocksdb_create_iterator(db, scanOptions) }
                if (iter.isNull()) {
                    return (false, [], "rocksdb_create_iterator failed")
                }
                try {
                    unsafe {
                        rocksdb_iter_seek(
                            iter,
                            CString(prefixHandle.pointer),
                            UIntNative(prefixLen)
                        )
                    }

                    while (unsafe { rocksdb_iter_valid(iter) } != 0u8) {
                        let key = readIteratorBytes(iter, true)
                        if (!key.startsWith(prefix)) {
                            break
                        }
                        let value = readIteratorBytes(iter, false)
                        results.add((key, value))
                        unsafe { rocksdb_iter_next(iter) }
                    }

                    var errPtr = CPointer<UInt8>()
                    unsafe { rocksdb_iter_get_error(iter, inout errPtr) }
                    if (!errPtr.isNull()) {
                        return (false, [], takeOwnedCString(errPtr))
                    }
                } finally {
                    unsafe { rocksdb_iter_destroy(iter) }
                }
            }

            return (true, results.toArray(), "")
        } finally {
            unsafe { releaseArrayRawData(prefixHandle) }
            unsafe { rocksdb_readoptions_destroy(scanOptions) }
        }
    }

    public func scanByPrefixResult(prefix: String): RocksDbOperationResult<Array<(String, String)>> {
        let (ok, pairs, err) = scanByPrefixTuple(prefix)
        if (ok) {
            return RocksDbOperationResult<Array<(String, String)>>.Ok(pairs)
        }
        return RocksDbOperationResult<Array<(String, String)>>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        unsafe {
            rocksdb_readoptions_destroy(readOptions)
            rocksdb_writeoptions_destroy(writeOptions)
            rocksdb_close(db)
        }
    }

    private static func takeOwnedCString(raw: CPointer<UInt8>): String {
        let text = unsafe { CString(raw).toString() }
        unsafe { rocksdb_free(CPointer<Unit>(raw)) }
        return text
    }

    private static func readCStringBytes(ptr: CPointer<UInt8>, length: UIntNative): String {
        if (ptr.isNull() || length == 0) {
            return ""
        }
        return unsafe { CString(ptr).toString() }
    }

    private static func readIteratorBytes(iter: CPointer<rocksdb_iterator_t>, readKey: Bool): String {
        var length: UIntNative = 0
        let ptr = if (readKey) {
            unsafe { rocksdb_iter_key(iter, inout length) }
        } else {
            unsafe { rocksdb_iter_value(iter, inout length) }
        }
        if (ptr.isNull() || length == 0) {
            return ""
        }
        let out = Array<UInt8>(Int64(length), {i => unsafe { (ptr + i).read() }})
        return String.fromUtf8(out)
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
}

public class RocksDbTxn <: Resource {
    private let txn: CPointer<rocksdb_transaction_t>
    private let readOptions: CPointer<rocksdb_readoptions_t>
    private var closed: Bool = false

    private init(txn: CPointer<rocksdb_transaction_t>, readOptions: CPointer<rocksdb_readoptions_t>) {
        this.txn = txn
        this.readOptions = readOptions
    }

    public static func wrap(txn: CPointer<rocksdb_transaction_t>, readOptions: CPointer<rocksdb_readoptions_t>): RocksDbTxn {
        return RocksDbTxn(txn, readOptions)
    }

    public func getResult(key: String): RocksDbOperationResult<String> {
        if (closed) {
            return RocksDbOperationResult<String>.Err(RocksDbError(RocksDbErrorKind.Closed, "rocksdb transaction is closed"))
        }

        var valueLen: UIntNative = 0
        var errPtr = CPointer<UInt8>()
        let valuePtr = unsafe {
            let keyBytes = key.toArray()
            let keyHandle = acquireArrayRawData(keyBytes)
            try {
                rocksdb_transaction_get(
                    txn,
                    readOptions,
                    CString(keyHandle.pointer),
                    UIntNative(keyBytes.size),
                    inout valueLen,
                    inout errPtr
                )
            } finally {
                releaseArrayRawData(keyHandle)
            }
        }

        if (!errPtr.isNull()) {
            let error = takeOwnedCString(errPtr)
            return RocksDbOperationResult<String>.Err(RocksDbError(classifyRocksDbError(error), error))
        }
        if (valuePtr.isNull()) {
            return RocksDbOperationResult<String>.NotFound
        }

        let out = Array<UInt8>(Int64(valueLen), {i => unsafe { (valuePtr + i).read() }})
        unsafe { rocksdb_free(CPointer<Unit>(valuePtr)) }
        return RocksDbOperationResult<String>.Ok(String.fromUtf8(out))
    }

    private func multiGetTuple(keys: Array<String>): (Bool, Array<Option<String>>, String) {
        if (closed) {
            return (false, [], "rocksdb transaction is closed")
        }
        if (keys.size == 0) {
            return (true, [], "")
        }

        let keyPtrs = Array<CString>(keys.size, {_ => CString(CPointer<UInt8>())})
        let keyLens = Array<UIntNative>(keys.size, {_ => UIntNative(0)})
        let valuePtrs = Array<CPointer<UInt8>>(keys.size, {_ => CPointer<UInt8>()})
        let valueLens = Array<UIntNative>(keys.size, {_ => UIntNative(0)})
        let errs = Array<CPointer<UInt8>>(keys.size, {_ => CPointer<UInt8>()})

        for (i in 0..keys.size) {
            let rawKey = unsafe { LibC.mallocCString(keys[i]) }
            keyPtrs[i] = rawKey
            keyLens[i] = UIntNative(keys[i].toArray().size)
        }

        let keyPtrHandle = unsafe { acquireArrayRawData(keyPtrs) }
        let keyLenHandle = unsafe { acquireArrayRawData(keyLens) }
        let valuePtrHandle = unsafe { acquireArrayRawData(valuePtrs) }
        let valueLenHandle = unsafe { acquireArrayRawData(valueLens) }
        let errHandle = unsafe { acquireArrayRawData(errs) }
        try {
            unsafe {
                rocksdb_transaction_multi_get(
                    txn,
                    readOptions,
                    UIntNative(keys.size),
                    keyPtrHandle.pointer,
                    keyLenHandle.pointer,
                    valuePtrHandle.pointer,
                    valueLenHandle.pointer,
                    errHandle.pointer
                )
            }

            let results = ArrayList<Option<String>>()
            for (i in 0..keys.size) {
                if (!errs[i].isNull()) {
                    let error = unsafe { CString(errs[i]).toString() }
                    return (false, [], error)
                }
                if (valuePtrs[i].isNull()) {
                    results.add(None)
                } else {
                    let value = readCStringBytes(valuePtrs[i], valueLens[i])
                    results.add(Some(value))
                }
            }
            return (true, results.toArray(), "")
        } finally {
            unsafe { releaseArrayRawData(errHandle) }
            unsafe { releaseArrayRawData(valueLenHandle) }
            unsafe { releaseArrayRawData(valuePtrHandle) }
            unsafe { releaseArrayRawData(keyLenHandle) }
            unsafe { releaseArrayRawData(keyPtrHandle) }
            for (i in 0..keyPtrs.size) {
                if (!keyPtrs[i].isNull()) {
                    unsafe { LibC.free(keyPtrs[i]) }
                }
                if (!valuePtrs[i].isNull()) {
                    unsafe { rocksdb_free(CPointer<Unit>(valuePtrs[i])) }
                }
                if (!errs[i].isNull()) {
                    unsafe { rocksdb_free(CPointer<Unit>(errs[i])) }
                }
            }
        }
    }

    public func multiGetResult(keys: Array<String>): RocksDbOperationResult<Array<Option<String>>> {
        let (ok, values, err) = multiGetTuple(keys)
        if (ok) {
            return RocksDbOperationResult<Array<Option<String>>>.Ok(values)
        }
        return RocksDbOperationResult<Array<Option<String>>>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    private func putTuple(key: String, value: String): (Bool, String) {
        if (closed) {
            return (false, "rocksdb transaction is closed")
        }

        unsafe {
            let keyBytes = key.toArray()
            let keyHandle = acquireArrayRawData(keyBytes)
            let valueBytes = value.toArray()
            let valueHandle = acquireArrayRawData(valueBytes)
            var errPtr = CPointer<UInt8>()
            try {
                rocksdb_transaction_put(
                    txn,
                    CString(keyHandle.pointer),
                    UIntNative(keyBytes.size),
                    CString(valueHandle.pointer),
                    UIntNative(valueBytes.size),
                    inout errPtr
                )
            } finally {
                releaseArrayRawData(valueHandle)
                releaseArrayRawData(keyHandle)
            }
            if (!errPtr.isNull()) {
                return (false, takeOwnedCString(errPtr))
            }
        }
        return (true, "")
    }

    public func putResult(key: String, value: String): RocksDbOperationResult<Unit> {
        let (ok, err) = putTuple(key, value)
        if (ok) {
            return RocksDbOperationResult<Unit>.Ok(())
        }
        return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    private func deleteTuple(key: String): (Bool, String) {
        if (closed) {
            return (false, "rocksdb transaction is closed")
        }

        unsafe {
            let keyBytes = key.toArray()
            let keyHandle = acquireArrayRawData(keyBytes)
            var errPtr = CPointer<UInt8>()
            try {
                rocksdb_transaction_delete(
                    txn,
                    CString(keyHandle.pointer),
                    UIntNative(keyBytes.size),
                    inout errPtr
                )
            } finally {
                releaseArrayRawData(keyHandle)
            }
            if (!errPtr.isNull()) {
                return (false, takeOwnedCString(errPtr))
            }
        }
        return (true, "")
    }

    public func deleteResult(key: String): RocksDbOperationResult<Unit> {
        let (ok, err) = deleteTuple(key)
        if (ok) {
            return RocksDbOperationResult<Unit>.Ok(())
        }
        return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    private func commitTuple(): (Bool, String) {
        if (closed) {
            return (false, "rocksdb transaction is closed")
        }
        var errPtr = CPointer<UInt8>()
        unsafe { rocksdb_transaction_commit(txn, inout errPtr) }
        if (!errPtr.isNull()) {
            return (false, takeOwnedCString(errPtr))
        }
        return (true, "")
    }

    public func commitResult(): RocksDbOperationResult<Unit> {
        let (ok, err) = commitTuple()
        if (ok) {
            return RocksDbOperationResult<Unit>.Ok(())
        }
        return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    private func rollbackTuple(): (Bool, String) {
        if (closed) {
            return (false, "rocksdb transaction is closed")
        }
        var errPtr = CPointer<UInt8>()
        unsafe { rocksdb_transaction_rollback(txn, inout errPtr) }
        if (!errPtr.isNull()) {
            return (false, takeOwnedCString(errPtr))
        }
        return (true, "")
    }

    public func rollbackResult(): RocksDbOperationResult<Unit> {
        let (ok, err) = rollbackTuple()
        if (ok) {
            return RocksDbOperationResult<Unit>.Ok(())
        }
        return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        unsafe { rocksdb_transaction_destroy(txn) }
    }

    public func isClosed(): Bool {
        return closed
    }

    private static func takeOwnedCString(raw: CPointer<UInt8>): String {
        let text = unsafe { CString(raw).toString() }
        unsafe { rocksdb_free(CPointer<Unit>(raw)) }
        return text
    }

    private static func readCStringBytes(ptr: CPointer<UInt8>, length: UIntNative): String {
        if (ptr.isNull() || length == 0) {
            return ""
        }
        let out = Array<UInt8>(Int64(length), {i => unsafe { (ptr + i).read() }})
        return String.fromUtf8(out)
    }
}

public class OptimisticRocksDb {
    private static let defaultKvMemoryMb: Int32 = 16
    private static let minKvMemoryMb: Int32 = 4
    private static let defaultBlockCacheMb: Int32 = 64
    private static let minBlockCacheMb: Int32 = 4
    private static let defaultMaxWriteBufferNumber: Int32 = 4
    private static let minMaxWriteBufferNumber: Int32 = 1
    private static let defaultMaxOpenFiles: Int32 = 256
    private static let minMaxOpenFiles: Int32 = -1
    private static let defaultMaxBackgroundJobs: Int32 = 2
    private static let minMaxBackgroundJobs: Int32 = 1
    private static let dbWriteBufferMultiplier: UIntNative = 4
    private let db: CPointer<rocksdb_optimistictransactiondb_t>
    private let baseDb: CPointer<rocksdb_t>
    private let readOptions: CPointer<rocksdb_readoptions_t>
    private let writeOptions: CPointer<rocksdb_writeoptions_t>
    private var closed: Bool = false

    private init(
        db: CPointer<rocksdb_optimistictransactiondb_t>,
        baseDb: CPointer<rocksdb_t>,
        readOptions: CPointer<rocksdb_readoptions_t>,
        writeOptions: CPointer<rocksdb_writeoptions_t>
    ) {
        this.db = db
        this.baseDb = baseDb
        this.readOptions = readOptions
        this.writeOptions = writeOptions
    }

    public static func openOptimistic(path: String, dbOptions: OptimisticRocksDbOptions): (Bool, Option<OptimisticRocksDb>,
        String) {
        let normalizedKvMemoryMb = normalizeKvMemoryMb(dbOptions.kvMemoryMb)
        let normalizedBlockCacheMb = normalizeBlockCacheMb(dbOptions.blockCacheMb)
        let normalizedMaxWriteBufferNumber = normalizeMaxWriteBufferNumber(dbOptions.maxWriteBufferNumber)
        let normalizedMaxOpenFiles = normalizeMaxOpenFiles(dbOptions.maxOpenFiles)
        let normalizedMaxBackgroundJobs = normalizeMaxBackgroundJobs(dbOptions.maxBackgroundJobs)
        let normalizedCompressionType = normalizeCompressionType(dbOptions.compression)
        let writeBufferSizeBytes = mbToBytes(normalizedKvMemoryMb)
        let dbWriteBufferSizeBytes = writeBufferSizeBytes * dbWriteBufferMultiplier
        let blockCacheSizeBytes = mbToBytes(normalizedBlockCacheMb)
        let options = unsafe { rocksdb_options_create() }
        if (options.isNull()) {
            return (false, None, "rocksdb_options_create failed")
        }

        let tableOptions = unsafe { rocksdb_block_based_options_create() }
        if (tableOptions.isNull()) {
            unsafe { rocksdb_options_destroy(options) }
            return (false, None, "rocksdb_block_based_options_create failed")
        }

        let blockCache = unsafe { rocksdb_cache_create_lru(blockCacheSizeBytes) }
        if (blockCache.isNull()) {
            unsafe {
                rocksdb_block_based_options_destroy(tableOptions)
                rocksdb_options_destroy(options)
            }
            return (false, None, "rocksdb_cache_create_lru failed")
        }

        unsafe {
            rocksdb_options_set_create_if_missing(options, 1u8)
            rocksdb_options_set_paranoid_checks(options, 0u8)
            rocksdb_options_set_compression(options, normalizedCompressionType)
            rocksdb_options_set_write_buffer_size(options, writeBufferSizeBytes)
            rocksdb_options_set_db_write_buffer_size(options, dbWriteBufferSizeBytes)
            rocksdb_options_set_max_write_buffer_number(options, normalizedMaxWriteBufferNumber)
            rocksdb_options_set_min_write_buffer_number_to_merge(options, 1)
            rocksdb_options_set_max_write_buffer_number_to_maintain(options, 1)
            rocksdb_options_set_max_open_files(options, normalizedMaxOpenFiles)
            rocksdb_options_set_max_background_jobs(options, normalizedMaxBackgroundJobs)
            rocksdb_options_set_keep_log_file_num(options, 2)
            rocksdb_options_set_use_fsync(options, 0u8)
            rocksdb_options_set_allow_mmap_reads(options, if (dbOptions.allowMmapReads) {
                1u8
            } else {
                0u8
            })
            rocksdb_options_set_bytes_per_sync(options, 0u64)
            rocksdb_block_based_options_set_no_block_cache(tableOptions, 0u8)
            rocksdb_block_based_options_set_block_cache(tableOptions, blockCache)
            rocksdb_block_based_options_set_cache_index_and_filter_blocks(tableOptions, 1u8)
            rocksdb_block_based_options_set_cache_index_and_filter_blocks_with_high_priority(tableOptions, 1u8)
            rocksdb_block_based_options_set_pin_l0_filter_and_index_blocks_in_cache(tableOptions, 1u8)
            rocksdb_block_based_options_set_pin_top_level_index_and_filter(tableOptions, 1u8)
            rocksdb_options_set_block_based_table_factory(options, tableOptions)
        }

        let pathC = unsafe { LibC.mallocCString(path) }
        var errPtr = CPointer<UInt8>()
        let db = unsafe { rocksdb_optimistictransactiondb_open(options, pathC, inout errPtr) }
        unsafe {
            LibC.free(pathC)
            rocksdb_block_based_options_destroy(tableOptions)
            rocksdb_cache_destroy(blockCache)
            rocksdb_options_destroy(options)
        }

        if (!errPtr.isNull()) {
            let error = takeOwnedCString(errPtr)
            if (!db.isNull()) {
                unsafe { rocksdb_optimistictransactiondb_close(db) }
            }
            return (false, None, error)
        }
        if (db.isNull()) {
            return (false, None, "rocksdb_optimistictransactiondb_open returned null")
        }

        let baseDb = unsafe { rocksdb_optimistictransactiondb_get_base_db(db) }
        if (baseDb.isNull()) {
            unsafe { rocksdb_optimistictransactiondb_close(db) }
            return (false, None, "rocksdb_optimistictransactiondb_get_base_db returned null")
        }

        let readOptions = unsafe { rocksdb_readoptions_create() }
        let writeOptions = unsafe { rocksdb_writeoptions_create() }
        if (readOptions.isNull() || writeOptions.isNull()) {
            if (!readOptions.isNull()) {
                unsafe { rocksdb_readoptions_destroy(readOptions) }
            }
            if (!writeOptions.isNull()) {
                unsafe { rocksdb_writeoptions_destroy(writeOptions) }
            }
            unsafe { rocksdb_optimistictransactiondb_close_base_db(baseDb) }
            unsafe { rocksdb_optimistictransactiondb_close(db) }
            return (false, None, "rocksdb read/write options init failed")
        }

        unsafe { rocksdb_writeoptions_set_sync(writeOptions, 0u8) }
        return (true, Some(OptimisticRocksDb(db, baseDb, readOptions, writeOptions)), "")
    }

    private static func normalizeBlockCacheMb(blockCacheMb: Int32): Int32 {
        if (blockCacheMb <= 0) {
            return defaultBlockCacheMb
        }
        if (blockCacheMb < minBlockCacheMb) {
            return minBlockCacheMb
        }
        return blockCacheMb
    }

    private static func normalizeMaxWriteBufferNumber(maxWriteBufferNumber: Int32): Int32 {
        if (maxWriteBufferNumber <= 0) {
            return defaultMaxWriteBufferNumber
        }
        if (maxWriteBufferNumber < minMaxWriteBufferNumber) {
            return minMaxWriteBufferNumber
        }
        return maxWriteBufferNumber
    }

    private static func normalizeMaxOpenFiles(maxOpenFiles: Int32): Int32 {
        if (maxOpenFiles == 0 || maxOpenFiles < minMaxOpenFiles) {
            return defaultMaxOpenFiles
        }
        return maxOpenFiles
    }

    private static func normalizeMaxBackgroundJobs(maxBackgroundJobs: Int32): Int32 {
        if (maxBackgroundJobs <= 0) {
            return defaultMaxBackgroundJobs
        }
        if (maxBackgroundJobs < minMaxBackgroundJobs) {
            return minMaxBackgroundJobs
        }
        return maxBackgroundJobs
    }

    private static func normalizeCompressionType(compression: RocksDbCompression): Int32 {
        return compression.toNative()
    }

    public func getResult(key: String): RocksDbOperationResult<String> {
        if (closed) {
            return RocksDbOperationResult<String>.Err(RocksDbError(RocksDbErrorKind.Closed, "rocksdb optimistic db is closed"))
        }

        var valueLen: UIntNative = 0
        var errPtr = CPointer<UInt8>()
        let valuePtr = unsafe {
            let keyBytes = key.toArray()
            let keyHandle = acquireArrayRawData(keyBytes)
            try {
                rocksdb_get(
                    baseDb,
                    readOptions,
                    CString(keyHandle.pointer),
                    UIntNative(keyBytes.size),
                    inout valueLen,
                    inout errPtr
                )
            } finally {
                releaseArrayRawData(keyHandle)
            }
        }

        if (!errPtr.isNull()) {
            let error = takeOwnedCString(errPtr)
            return RocksDbOperationResult<String>.Err(RocksDbError(classifyRocksDbError(error), error))
        }
        if (valuePtr.isNull()) {
            return RocksDbOperationResult<String>.NotFound
        }

        let out = Array<UInt8>(Int64(valueLen), {i => unsafe { (valuePtr + i).read() }})
        unsafe { rocksdb_free(CPointer<Unit>(valuePtr)) }
        return RocksDbOperationResult<String>.Ok(String.fromUtf8(out))
    }

    private func multiGetTuple(keys: Array<String>): (Bool, Array<Option<String>>, String) {
        if (closed) {
            return (false, [], "rocksdb optimistic db is closed")
        }
        if (keys.size == 0) {
            return (true, [], "")
        }

        let keyPtrs = Array<CString>(keys.size, {_ => CString(CPointer<UInt8>())})
        let keyLens = Array<UIntNative>(keys.size, {_ => UIntNative(0)})
        let valuePtrs = Array<CPointer<UInt8>>(keys.size, {_ => CPointer<UInt8>()})
        let valueLens = Array<UIntNative>(keys.size, {_ => UIntNative(0)})
        let errs = Array<CPointer<UInt8>>(keys.size, {_ => CPointer<UInt8>()})

        for (i in 0..keys.size) {
            let rawKey = unsafe { LibC.mallocCString(keys[i]) }
            keyPtrs[i] = rawKey
            keyLens[i] = UIntNative(keys[i].toArray().size)
        }

        let keyPtrHandle = unsafe { acquireArrayRawData(keyPtrs) }
        let keyLenHandle = unsafe { acquireArrayRawData(keyLens) }
        let valuePtrHandle = unsafe { acquireArrayRawData(valuePtrs) }
        let valueLenHandle = unsafe { acquireArrayRawData(valueLens) }
        let errHandle = unsafe { acquireArrayRawData(errs) }
        try {
            unsafe {
                rocksdb_multi_get(
                    baseDb,
                    readOptions,
                    UIntNative(keys.size),
                    keyPtrHandle.pointer,
                    keyLenHandle.pointer,
                    valuePtrHandle.pointer,
                    valueLenHandle.pointer,
                    errHandle.pointer
                )
            }

            let results = ArrayList<Option<String>>()
            for (i in 0..keys.size) {
                if (!errs[i].isNull()) {
                    let error = unsafe { CString(errs[i]).toString() }
                    return (false, [], error)
                }

                if (valuePtrs[i].isNull()) {
                    results.add(None)
                } else {
                    let value = readCStringBytes(valuePtrs[i], valueLens[i])
                    results.add(Some(value))
                }
            }
            return (true, results.toArray(), "")
        } finally {
            unsafe { releaseArrayRawData(errHandle) }
            unsafe { releaseArrayRawData(valueLenHandle) }
            unsafe { releaseArrayRawData(valuePtrHandle) }
            unsafe { releaseArrayRawData(keyLenHandle) }
            unsafe { releaseArrayRawData(keyPtrHandle) }
            for (i in 0..keyPtrs.size) {
                if (!keyPtrs[i].isNull()) {
                    unsafe { LibC.free(keyPtrs[i]) }
                }
                if (!valuePtrs[i].isNull()) {
                    unsafe { rocksdb_free(CPointer<Unit>(valuePtrs[i])) }
                }
                if (!errs[i].isNull()) {
                    unsafe { rocksdb_free(CPointer<Unit>(errs[i])) }
                }
            }
        }
    }

    public func multiGetResult(keys: Array<String>): RocksDbOperationResult<Array<Option<String>>> {
        let (ok, values, err) = multiGetTuple(keys)
        if (ok) {
            return RocksDbOperationResult<Array<Option<String>>>.Ok(values)
        }
        return RocksDbOperationResult<Array<Option<String>>>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    private func putTuple(key: String, value: String): (Bool, String) {
        if (closed) {
            return (false, "rocksdb optimistic db is closed")
        }

        unsafe {
            let keyBytes = key.toArray()
            let keyHandle = acquireArrayRawData(keyBytes)
            let valueBytes = value.toArray()
            let valueHandle = acquireArrayRawData(valueBytes)
            var errPtr = CPointer<UInt8>()
            try {
                rocksdb_put(
                    baseDb,
                    writeOptions,
                    CString(keyHandle.pointer),
                    UIntNative(keyBytes.size),
                    CString(valueHandle.pointer),
                    UIntNative(valueBytes.size),
                    inout errPtr
                )
            } finally {
                releaseArrayRawData(valueHandle)
                releaseArrayRawData(keyHandle)
            }
            if (!errPtr.isNull()) {
                return (false, takeOwnedCString(errPtr))
            }
        }
        return (true, "")
    }

    public func putResult(key: String, value: String): RocksDbOperationResult<Unit> {
        let (ok, err) = putTuple(key, value)
        if (ok) {
            return RocksDbOperationResult<Unit>.Ok(())
        }
        return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    private func deleteTuple(key: String): (Bool, String) {
        if (closed) {
            return (false, "rocksdb optimistic db is closed")
        }

        unsafe {
            let keyBytes = key.toArray()
            let keyHandle = acquireArrayRawData(keyBytes)
            var errPtr = CPointer<UInt8>()
            try {
                rocksdb_delete(
                    baseDb,
                    writeOptions,
                    CString(keyHandle.pointer),
                    UIntNative(keyBytes.size),
                    inout errPtr
                )
            } finally {
                releaseArrayRawData(keyHandle)
            }
            if (!errPtr.isNull()) {
                return (false, takeOwnedCString(errPtr))
            }
        }
        return (true, "")
    }

    public func deleteResult(key: String): RocksDbOperationResult<Unit> {
        let (ok, err) = deleteTuple(key)
        if (ok) {
            return RocksDbOperationResult<Unit>.Ok(())
        }
        return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    private func writeBatchTuple(
        puts: Array<(String, String)>,
        deletes: Array<String>,
        deleteRanges: Array<(String, String)>,
        merges: Array<(String, String)>
    ): (Bool, String) {
        if (closed) {
            return (false, "rocksdb optimistic db is closed")
        }
        if (puts.size == 0 && deletes.size == 0 && deleteRanges.size == 0 && merges.size == 0) {
            return (true, "")
        }

        let batch = unsafe { rocksdb_writebatch_create() }
        if (batch.isNull()) {
            return (false, "rocksdb_writebatch_create failed")
        }

        try {
            for ((key, value) in puts) {
                unsafe {
                    let keyBytes = key.toArray()
                    let keyHandle = acquireArrayRawData(keyBytes)
                    let valueBytes = value.toArray()
                    let valueHandle = acquireArrayRawData(valueBytes)
                    try {
                        rocksdb_writebatch_put(
                            batch,
                            CString(keyHandle.pointer),
                            UIntNative(keyBytes.size),
                            CString(valueHandle.pointer),
                            UIntNative(valueBytes.size)
                        )
                    } finally {
                        releaseArrayRawData(valueHandle)
                        releaseArrayRawData(keyHandle)
                    }
                }
            }

            for ((key, value) in merges) {
                unsafe {
                    let keyBytes = key.toArray()
                    let keyHandle = acquireArrayRawData(keyBytes)
                    let valueBytes = value.toArray()
                    let valueHandle = acquireArrayRawData(valueBytes)
                    try {
                        rocksdb_writebatch_merge(
                            batch,
                            CString(keyHandle.pointer),
                            UIntNative(keyBytes.size),
                            CString(valueHandle.pointer),
                            UIntNative(valueBytes.size)
                        )
                    } finally {
                        releaseArrayRawData(valueHandle)
                        releaseArrayRawData(keyHandle)
                    }
                }
            }

            for (key in deletes) {
                unsafe {
                    let keyBytes = key.toArray()
                    let keyHandle = acquireArrayRawData(keyBytes)
                    try {
                        rocksdb_writebatch_delete(
                            batch,
                            CString(keyHandle.pointer),
                            UIntNative(keyBytes.size)
                        )
                    } finally {
                        releaseArrayRawData(keyHandle)
                    }
                }
            }

            for ((startKey, endKey) in deleteRanges) {
                unsafe {
                    let startBytes = startKey.toArray()
                    let startHandle = acquireArrayRawData(startBytes)
                    let endBytes = endKey.toArray()
                    let endHandle = acquireArrayRawData(endBytes)
                    try {
                        rocksdb_writebatch_delete_range(
                            batch,
                            CString(startHandle.pointer),
                            UIntNative(startBytes.size),
                            CString(endHandle.pointer),
                            UIntNative(endBytes.size)
                        )
                    } finally {
                        releaseArrayRawData(endHandle)
                        releaseArrayRawData(startHandle)
                    }
                }
            }

            var errPtr = CPointer<UInt8>()
            unsafe { rocksdb_write(baseDb, writeOptions, batch, inout errPtr) }
            if (!errPtr.isNull()) {
                return (false, takeOwnedCString(errPtr))
            }
            return (true, "")
        } finally {
            unsafe { rocksdb_writebatch_destroy(batch) }
        }
    }

    public func writeBatchResult(
        puts: Array<(String, String)>,
        deletes: Array<String>,
        deleteRanges: Array<(String, String)>,
        merges: Array<(String, String)>
    ): RocksDbOperationResult<Unit> {
        let (ok, err) = writeBatchTuple(puts, deletes, deleteRanges, merges)
        if (ok) {
            return RocksDbOperationResult<Unit>.Ok(())
        }
        return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    public func deleteRangeResult(startKey: String, endKey: String): RocksDbOperationResult<Unit> {
        return writeBatchResult([], [], [(startKey, endKey)], [])
    }

    public func deleteManyResult(keys: Array<String>): RocksDbOperationResult<Unit> {
        return writeBatchResult([], keys, [], [])
    }

    private func scanByPrefixTuple(prefix: String): (Bool, Array<(String, String)>, String) {
        if (closed) {
            return (false, [], "rocksdb optimistic db is closed")
        }

        let prefixBytes = prefix.toArray()
        let prefixLen = prefixBytes.size
        let upperBoundOpt = nextPrefixUpperBound(prefix)
        let scanOptions = unsafe { rocksdb_readoptions_create() }
        if (scanOptions.isNull()) {
            return (false, [], "rocksdb_readoptions_create failed")
        }

        let results = ArrayList<(String, String)>()
        let prefixHandle = unsafe { acquireArrayRawData(prefixBytes) }
        try {
            unsafe {
                rocksdb_readoptions_set_prefix_same_as_start(scanOptions, 1u8)
                rocksdb_readoptions_set_total_order_seek(scanOptions, 0u8)
            }

            match (upperBoundOpt) {
                case Some(upperBound) =>
                    let upperBoundBytes = upperBound.toArray()
                    let upperBoundHandle = unsafe { acquireArrayRawData(upperBoundBytes) }
                    try {
                        unsafe {
                            rocksdb_readoptions_set_iterate_upper_bound(
                                scanOptions,
                                CString(upperBoundHandle.pointer),
                                UIntNative(upperBoundBytes.size)
                            )
                        }
                        let iter = unsafe { rocksdb_create_iterator(baseDb, scanOptions) }
                        if (iter.isNull()) {
                            return (false, [], "rocksdb_create_iterator failed")
                        }
                        try {
                            unsafe {
                                rocksdb_iter_seek(
                                    iter,
                                    CString(prefixHandle.pointer),
                                    UIntNative(prefixLen)
                                )
                            }

                            while (unsafe { rocksdb_iter_valid(iter) } != 0u8) {
                                let key = readIteratorBytes(iter, true)
                                if (!key.startsWith(prefix)) {
                                    break
                                }
                                let value = readIteratorBytes(iter, false)
                                results.add((key, value))
                                unsafe { rocksdb_iter_next(iter) }
                            }

                            var errPtr = CPointer<UInt8>()
                            unsafe { rocksdb_iter_get_error(iter, inout errPtr) }
                            if (!errPtr.isNull()) {
                                return (false, [], takeOwnedCString(errPtr))
                            }
                        } finally {
                            unsafe { rocksdb_iter_destroy(iter) }
                        }
                    } finally {
                        unsafe { releaseArrayRawData(upperBoundHandle) }
                    }
                case None => ()
            }

            if (upperBoundOpt.isNone()) {
                let iter = unsafe { rocksdb_create_iterator(baseDb, scanOptions) }
                if (iter.isNull()) {
                    return (false, [], "rocksdb_create_iterator failed")
                }
                try {
                    unsafe {
                        rocksdb_iter_seek(
                            iter,
                            CString(prefixHandle.pointer),
                            UIntNative(prefixLen)
                        )
                    }

                    while (unsafe { rocksdb_iter_valid(iter) } != 0u8) {
                        let key = readIteratorBytes(iter, true)
                        if (!key.startsWith(prefix)) {
                            break
                        }
                        let value = readIteratorBytes(iter, false)
                        results.add((key, value))
                        unsafe { rocksdb_iter_next(iter) }
                    }

                    var errPtr = CPointer<UInt8>()
                    unsafe { rocksdb_iter_get_error(iter, inout errPtr) }
                    if (!errPtr.isNull()) {
                        return (false, [], takeOwnedCString(errPtr))
                    }
                } finally {
                    unsafe { rocksdb_iter_destroy(iter) }
                }
            }

            return (true, results.toArray(), "")
        } finally {
            unsafe { releaseArrayRawData(prefixHandle) }
            unsafe { rocksdb_readoptions_destroy(scanOptions) }
        }
    }

    public func scanByPrefixResult(prefix: String): RocksDbOperationResult<Array<(String, String)>> {
        let (ok, pairs, err) = scanByPrefixTuple(prefix)
        if (ok) {
            return RocksDbOperationResult<Array<(String, String)>>.Ok(pairs)
        }
        return RocksDbOperationResult<Array<(String, String)>>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    private func beginTransactionTuple(): (Bool, Option<RocksDbTxn>, String) {
        if (closed) {
            return (false, None, "rocksdb optimistic db is closed")
        }

        let txnOptions = unsafe { rocksdb_optimistictransaction_options_create() }
        if (txnOptions.isNull()) {
            return (false, None, "rocksdb_optimistictransaction_options_create failed")
        }

        try {
            unsafe { rocksdb_optimistictransaction_options_set_set_snapshot(txnOptions, 1u8) }
            let txn = unsafe {
                rocksdb_optimistictransaction_begin(
                    db,
                    writeOptions,
                    txnOptions,
                    CPointer<rocksdb_transaction_t>()
                )
            }
            if (txn.isNull()) {
                return (false, None, "rocksdb_optimistictransaction_begin returned null")
            }
            return (true, Some(RocksDbTxn.wrap(txn, readOptions)), "")
        } finally {
            unsafe { rocksdb_optimistictransaction_options_destroy(txnOptions) }
        }
    }

    public func beginTransactionResult(): RocksDbOperationResult<RocksDbTxn> {
        let (ok, txnOpt, err) = beginTransactionTuple()
        if (!ok) {
            return RocksDbOperationResult<RocksDbTxn>.Err(RocksDbError(classifyRocksDbError(err), err))
        }
        match (txnOpt) {
            case Some(txn) => return RocksDbOperationResult<RocksDbTxn>.Ok(txn)
            case None => return RocksDbOperationResult<RocksDbTxn>.Err(
                RocksDbError(RocksDbErrorKind.FfiFailure, "rocksdb transaction begin returned no transaction"))
        }
    }

    public static func isConflictError(error: String): Bool {
        let normalized = error.toAsciiLower()
        if (normalized.contains("conflict")) {
            return true
        }
        if (normalized.contains("busy")) {
            return true
        }
        if (normalized.contains("try again")) {
            return true
        }
        if (normalized.contains("timed out")) {
            return true
        }
        return false
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        unsafe {
            rocksdb_readoptions_destroy(readOptions)
            rocksdb_writeoptions_destroy(writeOptions)
            rocksdb_optimistictransactiondb_close_base_db(baseDb)
            rocksdb_optimistictransactiondb_close(db)
        }
    }

    private static func normalizeKvMemoryMb(kvMemoryMb: Int32): Int32 {
        if (kvMemoryMb <= 0) {
            return defaultKvMemoryMb
        }
        if (kvMemoryMb < minKvMemoryMb) {
            return minKvMemoryMb
        }
        return kvMemoryMb
    }

    private static func mbToBytes(memoryMb: Int32): UIntNative {
        return UIntNative(memoryMb) * UIntNative(1024) * UIntNative(1024)
    }

    private static func takeOwnedCString(raw: CPointer<UInt8>): String {
        let text = unsafe { CString(raw).toString() }
        unsafe { rocksdb_free(CPointer<Unit>(raw)) }
        return text
    }

    private static func readCStringBytes(ptr: CPointer<UInt8>, length: UIntNative): String {
        if (ptr.isNull() || length == 0) {
            return ""
        }
        let out = Array<UInt8>(Int64(length), {i => unsafe { (ptr + i).read() }})
        return String.fromUtf8(out)
    }

    private static func readIteratorBytes(iter: CPointer<rocksdb_iterator_t>, readKey: Bool): String {
        var length: UIntNative = 0
        let ptr = if (readKey) {
            unsafe { rocksdb_iter_key(iter, inout length) }
        } else {
            unsafe { rocksdb_iter_value(iter, inout length) }
        }
        if (ptr.isNull() || length == 0) {
            return ""
        }
        let out = Array<UInt8>(Int64(length), {i => unsafe { (ptr + i).read() }})
        return String.fromUtf8(out)
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
}
