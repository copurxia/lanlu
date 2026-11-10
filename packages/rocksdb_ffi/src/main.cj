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
    | Unsupported
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
    if (normalized.contains("unsupported")) {        return RocksDbErrorKind.Unsupported
    }
    if (OptimisticRocksDb.isConflictError(error)) {
        return RocksDbErrorKind.Conflict
    }
    return RocksDbErrorKind.FfiFailure
}

// 编译期 RocksDB C API 版本（native/lanlu_rocksdb_bridge.c 读 rocksdb/version.h 宏）。
// 用于最小 FFI 测试断言编译期门槛：不同平台/库版本下仍能探测编译时 major/minor。
public struct RocksDbCompiledVersion {
    public let major: Int32
    public let minor: Int32

    public init(major: Int32, minor: Int32) {
        this.major = major
        this.minor = minor
    }
}

public func rocksDbCompiledVersion(): RocksDbCompiledVersion {
    let major = unsafe { llrocksdb_compiled_major() }
    let minor = unsafe { llrocksdb_compiled_minor() }
    return RocksDbCompiledVersion(major, minor)
}

private func copyNativeBytes(ptr: CPointer<UInt8>, length: UIntNative): Option<Array<UInt8>> {
    if (length > UIntNative(Int64.Max)) {
        return None
    }
    if (length == 0) {
        return Some(Array<UInt8>())
    }
    if (ptr.isNull()) {
        return None
    }
    return Some(Array<UInt8>(Int64(length), {i => unsafe { (ptr + i).read() }}))
}

private func copyBytesToNative(bytes: Array<UInt8>): CPointer<UInt8> {
    if (bytes.size == 0) {
        return CPointer<UInt8>()
    }
    let ptr = unsafe { LibC.malloc<UInt8>(count: bytes.size) }
    if (ptr.isNull()) {
        return ptr
    }
    for (i in 0..bytes.size) {
        unsafe { ptr.write(i, bytes[i]) }
    }
    return ptr
}

private func bytesEqual(left: Array<UInt8>, right: Array<UInt8>): Bool {
    if (left.size != right.size) {
        return false
    }
    for (i in 0..left.size) {
        if (left[i] != right[i]) {
            return false
        }
    }
    return true
}

private func bytesStartWith(value: Array<UInt8>, prefix: Array<UInt8>): Bool {
    if (value.size < prefix.size) {
        return false
    }
    for (i in 0..prefix.size) {
        if (value[i] != prefix[i]) {
            return false
        }
    }
    return true
}

private func nextPrefixUpperBoundBytes(prefix: Array<UInt8>): Option<Array<UInt8>> {
    if (prefix.size == 0) {
        return None
    }
    var pos = prefix.size - 1
    while (pos >= 0) {
        if (prefix[pos] < 255u8) {
            let upperBoundPos = pos
            return Some(Array<UInt8>(Int64(upperBoundPos + 1), {
                i => if (i == upperBoundPos) {
                    prefix[i] + 1u8
                } else {
                    prefix[i]
                }
            }))
        }
        pos -= 1
    }
    return None
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

// Column-family handles are owned by one RocksDb instance. Closing the DB closes
// every still-open handle first; callers may also close handles early.
public class RocksDbColumnFamily <: Resource {
    public let name: String
    private let handle: CPointer<rocksdb_column_family_handle_t>
    private let ownerKey: UIntNative
    private var closed: Bool = false

    internal init(name: String, handle: CPointer<rocksdb_column_family_handle_t>, ownerKey: UIntNative) {
        this.name = name
        this.handle = handle
        this.ownerKey = ownerKey
    }

    internal func nativeHandle(expectedOwnerKey: UIntNative): Option<CPointer<rocksdb_column_family_handle_t>> {
        if (closed || ownerKey != expectedOwnerKey) {
            return None
        }
        return Some(handle)
    }

    internal func ownerToken(): UIntNative {
        return ownerKey
    }

    public func isClosed(): Bool {
        return closed
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        unsafe { rocksdb_column_family_handle_destroy(handle) }
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
    private let columnFamilies = ArrayList<RocksDbColumnFamily>()
    private let snapshots = ArrayList<RocksDbSnapshot>()
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
        let columnFamilyNames = ArrayList<String>()
        var listedCount: UIntNative = 0
        var listErrPtr = CPointer<UInt8>()
        let listed = unsafe { rocksdb_list_column_families(options, pathC, inout listedCount, inout listErrPtr) }
        if (listErrPtr.isNull() && !listed.isNull() && listedCount <= UIntNative(Int64.Max)) {
            for (i in 0..Int64(listedCount)) {
                let item = unsafe { listed.read(i) }
                if (!item.isNull()) {
                    columnFamilyNames.add(unsafe { item.toString() })
                }
            }
            unsafe { rocksdb_list_column_families_destroy(listed, listedCount) }
        } else {
            // A missing/empty DB cannot be listed yet. Opening just the default
            // family with create_if_missing creates it; all other list errors are
            // surfaced by the subsequent open call.
            if (!listErrPtr.isNull()) {
                unsafe { rocksdb_free(CPointer<Unit>(listErrPtr)) }
            }
        }
        if (columnFamilyNames.size == 0) {
            columnFamilyNames.add("default")
        }
        if (columnFamilyNames.size > Int64(Int32.Max)) {
            unsafe {
                LibC.free(pathC)
                rocksdb_block_based_options_destroy(tableOptions)
                rocksdb_cache_destroy(blockCache)
                rocksdb_options_destroy(options)
            }
            return (false, None, "too many RocksDB column families")
        }

        let nativeNames = Array<CString>(columnFamilyNames.size, {_ => CString(CPointer<UInt8>())})
        let nativeOptions = Array<CPointer<rocksdb_options_t>>(columnFamilyNames.size, {_ => options})
        let nativeHandles = Array<CPointer<rocksdb_column_family_handle_t>>(columnFamilyNames.size,
            {_ => CPointer<rocksdb_column_family_handle_t>()})
        for (i in 0..columnFamilyNames.size) {
            nativeNames[i] = unsafe { LibC.mallocCString(columnFamilyNames[i]) }
        }
        let namesHandle = unsafe { acquireArrayRawData(nativeNames) }
        let optionsHandle = unsafe { acquireArrayRawData(nativeOptions) }
        let handlesHandle = unsafe { acquireArrayRawData(nativeHandles) }
        var errPtr = CPointer<UInt8>()
        let db = unsafe {
            rocksdb_open_column_families(options, pathC, Int32(columnFamilyNames.size), namesHandle.pointer,
                optionsHandle.pointer, handlesHandle.pointer, inout errPtr)
        }
        unsafe {
            releaseArrayRawData(handlesHandle)
            releaseArrayRawData(optionsHandle)
            releaseArrayRawData(namesHandle)
        }
        for (name in nativeNames) {
            if (!name.isNull()) {
                unsafe { LibC.free(name) }
            }
        }
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

        // 低内存默认值：读校验开启（数据一致性优先）、读填充 block cache 开启（热点复用）、
        // 写不强制 fsync（掉电可接受最后一批，进度/响应可重放）、WAL 开启（崩溃可恢复）。
        unsafe { rocksdb_readoptions_set_verify_checksums(readOptions, 1u8) }
        unsafe { rocksdb_readoptions_set_fill_cache(readOptions, 1u8) }
        unsafe { rocksdb_writeoptions_set_sync(writeOptions, 0u8) }
        let opened = RocksDb(db, readOptions, writeOptions)
        for (i in 0..columnFamilyNames.size) {
            if (nativeHandles[i].isNull()) {
                opened.close()
                return (false, None, "rocksdb returned a null column-family handle")
            }
            opened.columnFamilies.add(RocksDbColumnFamily(columnFamilyNames[i], nativeHandles[i], db.toUIntNative()))
        }
        return (true, Some(opened), "")
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

    public func getBytesResult(key: Array<UInt8>): RocksDbOperationResult<Array<UInt8>> {
        return getBytesWithOptionsResult(key, readOptions, None)
    }

    public func getBytesResult(
        columnFamily: RocksDbColumnFamily,
        key: Array<UInt8>
    ): RocksDbOperationResult<Array<UInt8>> {
        let handle = match (columnFamily.nativeHandle(db.toUIntNative())) {
            case Some(value) => value
            case None => return invalidColumnFamilyError<Array<UInt8>>()
        }
        return getBytesWithOptionsResult(key, readOptions, Some(handle))
    }

    internal func getBytesWithOptionsResult(
        key: Array<UInt8>,
        options: CPointer<rocksdb_readoptions_t>,
        columnFamily: Option<CPointer<rocksdb_column_family_handle_t>>
    ): RocksDbOperationResult<Array<UInt8>> {
        if (closed) {
            return RocksDbOperationResult<Array<UInt8>>.Err(RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }

        var valueLen: UIntNative = 0
        var errPtr = CPointer<UInt8>()
        let valuePtr = unsafe {
            let keyHandle = acquireArrayRawData(key)
            try {
                match (columnFamily) {
                    case Some(cf) => rocksdb_get_cf(db, options, cf, CString(keyHandle.pointer), UIntNative(key.size),
                        inout valueLen, inout errPtr)
                    case None => rocksdb_get(db, options, CString(keyHandle.pointer), UIntNative(key.size),
                        inout valueLen, inout errPtr)
                }
            } finally {
                releaseArrayRawData(keyHandle)
            }
        }

        if (!errPtr.isNull()) {
            let error = takeOwnedCString(errPtr)
            return RocksDbOperationResult<Array<UInt8>>.Err(RocksDbError(classifyRocksDbError(error), error))
        }
        if (valuePtr.isNull()) {
            return RocksDbOperationResult<Array<UInt8>>.NotFound
        }

        try {
            match (copyNativeBytes(valuePtr, valueLen)) {
                case Some(out) => return RocksDbOperationResult<Array<UInt8>>.Ok(out)
                case None => return RocksDbOperationResult<Array<UInt8>>.Err(
                    RocksDbError(RocksDbErrorKind.DecodeFailure,
                        "rocksdb value is too large or has an invalid native buffer"))
            }
        } finally {
            unsafe { rocksdb_free(CPointer<Unit>(valuePtr)) }
        }
    }

    public func isClosed(): Bool {
        return closed
    }

    public func getResult(key: String): RocksDbOperationResult<String> {
        match (getBytesResult(key.toArray())) {
            case RocksDbOperationResult<Array<UInt8>>.Ok(bytes) => try {
                return RocksDbOperationResult<String>.Ok(String.fromUtf8(bytes))
            } catch (_: Exception) {
                return RocksDbOperationResult<String>.Err(
                    RocksDbError(RocksDbErrorKind.DecodeFailure, "rocksdb value is not valid UTF-8"))
            }
            case RocksDbOperationResult<Array<UInt8>>.NotFound => return RocksDbOperationResult<String>.NotFound
            case RocksDbOperationResult<Array<UInt8>>.Err(error) => return RocksDbOperationResult<String>.Err(error)
        }
    }

    public func getResult(columnFamily: RocksDbColumnFamily, key: String): RocksDbOperationResult<String> {
        match (getBytesResult(columnFamily, key.toArray())) {
            case RocksDbOperationResult<Array<UInt8>>.Ok(bytes) => try {
                return RocksDbOperationResult<String>.Ok(String.fromUtf8(bytes))
            } catch (_: Exception) {
                return RocksDbOperationResult<String>.Err(
                    RocksDbError(RocksDbErrorKind.DecodeFailure, "rocksdb value is not valid UTF-8"))
            }
            case RocksDbOperationResult<Array<UInt8>>.NotFound => return RocksDbOperationResult<String>.NotFound
            case RocksDbOperationResult<Array<UInt8>>.Err(error) => return RocksDbOperationResult<String>.Err(error)
        }
    }

    public func multiGetBytesResult(keys: Array<Array<UInt8>>): RocksDbOperationResult<Array<Option<Array<UInt8>>>> {
        if (closed) {
            return RocksDbOperationResult<Array<Option<Array<UInt8>>>>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }
        if (keys.size == 0) {
            return RocksDbOperationResult<Array<Option<Array<UInt8>>>>.Ok([])
        }

        let nativeKeys = Array<CPointer<UInt8>>(keys.size, {_ => CPointer<UInt8>()})
        let keyPtrs = Array<CString>(keys.size, {_ => CString(CPointer<UInt8>())})
        let keyLens = Array<UIntNative>(keys.size, {_ => UIntNative(0)})
        let valuePtrs = Array<CPointer<UInt8>>(keys.size, {_ => CPointer<UInt8>()})
        let valueLens = Array<UIntNative>(keys.size, {_ => UIntNative(0)})
        let errs = Array<CPointer<UInt8>>(keys.size, {_ => CPointer<UInt8>()})

        for (i in 0..keys.size) {
            nativeKeys[i] = copyBytesToNative(keys[i])
            if (keys[i].size > 0 && nativeKeys[i].isNull()) {
                for (j in 0..i) {
                    if (!nativeKeys[j].isNull()) {
                        unsafe { LibC.free(nativeKeys[j]) }
                    }
                }
                return RocksDbOperationResult<Array<Option<Array<UInt8>>>>.Err(
                    RocksDbError(RocksDbErrorKind.FfiFailure, "failed to allocate native key buffer"))
            }
            keyPtrs[i] = CString(nativeKeys[i])
            keyLens[i] = UIntNative(keys[i].size)
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

            let results = ArrayList<Option<Array<UInt8>>>()
            for (i in 0..keys.size) {
                if (!errs[i].isNull()) {
                    let error = unsafe { CString(errs[i]).toString() }
                    return RocksDbOperationResult<Array<Option<Array<UInt8>>>>.Err(
                        RocksDbError(classifyRocksDbError(error), error))
                }
                if (valuePtrs[i].isNull()) {
                    results.add(None)
                    continue
                }
                match (copyNativeBytes(valuePtrs[i], valueLens[i])) {
                    case Some(value) => results.add(Some(value))
                    case None => return RocksDbOperationResult<Array<Option<Array<UInt8>>>>.Err(
                        RocksDbError(RocksDbErrorKind.DecodeFailure,
                            "rocksdb value is too large or has an invalid native buffer"))
                }
            }
            return RocksDbOperationResult<Array<Option<Array<UInt8>>>>.Ok(results.toArray())
        } finally {
            unsafe { releaseArrayRawData(errHandle) }
            unsafe { releaseArrayRawData(valueLenHandle) }
            unsafe { releaseArrayRawData(valuePtrHandle) }
            unsafe { releaseArrayRawData(keyLenHandle) }
            unsafe { releaseArrayRawData(keyPtrHandle) }
            for (i in 0..keys.size) {
                if (!nativeKeys[i].isNull()) {
                    unsafe { LibC.free(nativeKeys[i]) }
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
        let byteKeys = Array<Array<UInt8>>(keys.size, {i => keys[i].toArray()})
        match (multiGetBytesResult(byteKeys)) {
            case RocksDbOperationResult<Array<Option<Array<UInt8>>>>.Ok(values) =>
                let decoded = ArrayList<Option<String>>()
                for (value in values) {
                    match (value) {
                        case Some(bytes) => try {
                            decoded.add(Some(String.fromUtf8(bytes)))
                        } catch (_: Exception) {
                            return RocksDbOperationResult<Array<Option<String>>>.Err(
                                RocksDbError(RocksDbErrorKind.DecodeFailure, "rocksdb value is not valid UTF-8"))
                        }
                        case None => decoded.add(None)
                    }
                }
                return RocksDbOperationResult<Array<Option<String>>>.Ok(decoded.toArray())
            case RocksDbOperationResult<Array<Option<Array<UInt8>>>>.NotFound => return RocksDbOperationResult<Array<Option<String>>>
                .NotFound
            case RocksDbOperationResult<Array<Option<Array<UInt8>>>>.Err(error) => return RocksDbOperationResult<Array<Option<String>>>
                .Err(error)
        }
    }

    private func putBytesTuple(
        key: Array<UInt8>,
        value: Array<UInt8>,
        columnFamily: Option<CPointer<rocksdb_column_family_handle_t>>
    ): (Bool, String) {
        if (closed) {
            return (false, "rocksdb is closed")
        }

        unsafe {
            let keyHandle = acquireArrayRawData(key)
            let valueHandle = acquireArrayRawData(value)
            var errPtr = CPointer<UInt8>()
            try {
                match (columnFamily) {
                    case Some(cf) => rocksdb_put_cf(db, writeOptions, cf, CString(keyHandle.pointer),
                        UIntNative(key.size), CString(valueHandle.pointer), UIntNative(value.size), inout errPtr)
                    case None => rocksdb_put(db, writeOptions, CString(keyHandle.pointer), UIntNative(key.size),
                        CString(valueHandle.pointer), UIntNative(value.size), inout errPtr)
                }
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

    public func putBytesResult(key: Array<UInt8>, value: Array<UInt8>): RocksDbOperationResult<Unit> {
        let (ok, err) = putBytesTuple(key, value, None)
        if (ok) {
            return RocksDbOperationResult<Unit>.Ok(())
        }
        return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    public func putBytesResult(
        columnFamily: RocksDbColumnFamily,
        key: Array<UInt8>,
        value: Array<UInt8>
    ): RocksDbOperationResult<Unit> {
        let handle = match (columnFamily.nativeHandle(db.toUIntNative())) {
            case Some(raw) => raw
            case None => return invalidColumnFamilyError<Unit>()
        }
        let (ok, err) = putBytesTuple(key, value, Some(handle))
        if (ok) {
            return RocksDbOperationResult<Unit>.Ok(())
        }
        return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    public func putResult(key: String, value: String): RocksDbOperationResult<Unit> {
        return putBytesResult(key.toArray(), value.toArray())
    }

    public func putResult(
        columnFamily: RocksDbColumnFamily,
        key: String,
        value: String
    ): RocksDbOperationResult<Unit> {
        return putBytesResult(columnFamily, key.toArray(), value.toArray())
    }

    public func merge(key: String, value: String): (Bool, String) {
        let _ = key
        let _ = value
        return (false, "unsupported: no RocksDB merge operator is configured")
    }

    private func deleteBytesTuple(
        key: Array<UInt8>,
        columnFamily: Option<CPointer<rocksdb_column_family_handle_t>>
    ): (Bool, String) {
        if (closed) {
            return (false, "rocksdb is closed")
        }
        unsafe {
            let keyHandle = acquireArrayRawData(key)
            var errPtr = CPointer<UInt8>()
            try {
                match (columnFamily) {
                    case Some(cf) => rocksdb_delete_cf(db, writeOptions, cf, CString(keyHandle.pointer),
                        UIntNative(key.size), inout errPtr)
                    case None => rocksdb_delete(db, writeOptions, CString(keyHandle.pointer), UIntNative(key.size),
                        inout errPtr)
                }
            } finally {
                releaseArrayRawData(keyHandle)
            }

            if (!errPtr.isNull()) {
                return (false, takeOwnedCString(errPtr))
            }
        }
        return (true, "")
    }

    public func deleteBytesResult(key: Array<UInt8>): RocksDbOperationResult<Unit> {
        let (ok, err) = deleteBytesTuple(key, None)
        if (ok) {
            return RocksDbOperationResult<Unit>.Ok(())
        }
        return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    public func deleteBytesResult(
        columnFamily: RocksDbColumnFamily,
        key: Array<UInt8>
    ): RocksDbOperationResult<Unit> {
        let handle = match (columnFamily.nativeHandle(db.toUIntNative())) {
            case Some(raw) => raw
            case None => return invalidColumnFamilyError<Unit>()
        }
        let (ok, err) = deleteBytesTuple(key, Some(handle))
        if (ok) {
            return RocksDbOperationResult<Unit>.Ok(())
        }
        return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    public func deleteResult(key: String): RocksDbOperationResult<Unit> {
        return deleteBytesResult(key.toArray())
    }

    public func deleteResult(columnFamily: RocksDbColumnFamily, key: String): RocksDbOperationResult<Unit> {
        return deleteBytesResult(columnFamily, key.toArray())
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
        if (merges.size > 0) {
            return (false, "unsupported: no RocksDB merge operator is configured")
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
        let opened = openPrefixCursorResult(prefix.toArray())
        let cursor = match (opened) {
            case RocksDbOperationResult<RocksDbPrefixCursor>.Ok(value) => value
            case RocksDbOperationResult<RocksDbPrefixCursor>.NotFound => return (true, [], "")
            case RocksDbOperationResult<RocksDbPrefixCursor>.Err(error) => return (false, [], error.message)
        }
        let results = ArrayList<(String, String)>()
        try {
            while (cursor.isValid()) {
                try {
                    let key = match (cursor.keyBytes()) {
                        case RocksDbOperationResult<Array<UInt8>>.Ok(value) => String.fromUtf8(value)
                        case RocksDbOperationResult<Array<UInt8>>.NotFound => break
                        case RocksDbOperationResult<Array<UInt8>>.Err(error) => return (false, [], error.message)
                    }
                    let value = match (cursor.valueBytes()) {
                        case RocksDbOperationResult<Array<UInt8>>.Ok(bytes) => String.fromUtf8(bytes)
                        case RocksDbOperationResult<Array<UInt8>>.NotFound => break
                        case RocksDbOperationResult<Array<UInt8>>.Err(error) => return (false, [], error.message)
                    }
                    results.add((key, value))
                } catch (_: Exception) {
                    return (false, [], "rocksdb key or value is not valid UTF-8")
                }
                cursor.next()
            }
            match (cursor.status()) {
                case RocksDbOperationResult<Unit>.Ok(_) => return (true, results.toArray(), "")
                case RocksDbOperationResult<Unit>.NotFound => return (true, results.toArray(), "")
                case RocksDbOperationResult<Unit>.Err(error) => return (false, [], error.message)
            }
        } finally {
            cursor.close()
        }
    }

    public func scanByPrefixResult(prefix: String): RocksDbOperationResult<Array<(String, String)>> {
        let (ok, pairs, err) = scanByPrefixTuple(prefix)
        if (ok) {
            return RocksDbOperationResult<Array<(String, String)>>.Ok(pairs)
        }
        return RocksDbOperationResult<Array<(String, String)>>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    public func openIteratorResult(): RocksDbOperationResult<RocksDbIterator> {
        if (closed) {
            return RocksDbOperationResult<RocksDbIterator>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }
        return RocksDbIterator.create(db)
    }

    public func openIteratorResult(columnFamily: RocksDbColumnFamily): RocksDbOperationResult<RocksDbIterator> {
        if (closed) {
            return RocksDbOperationResult<RocksDbIterator>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }
        let handle = match (columnFamily.nativeHandle(db.toUIntNative())) {
            case Some(raw) => raw
            case None => return invalidColumnFamilyError<RocksDbIterator>()
        }
        return RocksDbIterator.create(db, columnFamily: Some(handle))
    }

    public func openPrefixCursorResult(
        prefix: Array<UInt8>,
        startAfter!: Option<Array<UInt8>> = None,
        limit!: Int64 = Int64.Max,
        reverse!: Bool = false
    ): RocksDbOperationResult<RocksDbPrefixCursor> {
        if (closed) {
            return RocksDbOperationResult<RocksDbPrefixCursor>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }
        return RocksDbPrefixCursor.create(db, prefix, startAfter: startAfter, limit: limit, reverse: reverse)
    }

    public func openPrefixCursorResult(
        columnFamily: RocksDbColumnFamily,
        prefix: Array<UInt8>,
        startAfter!: Option<Array<UInt8>> = None,
        limit!: Int64 = Int64.Max,
        reverse!: Bool = false
    ): RocksDbOperationResult<RocksDbPrefixCursor> {
        if (closed) {
            return RocksDbOperationResult<RocksDbPrefixCursor>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }
        let handle = match (columnFamily.nativeHandle(db.toUIntNative())) {
            case Some(raw) => raw
            case None => return invalidColumnFamilyError<RocksDbPrefixCursor>()
        }
        return RocksDbPrefixCursor.create(db, prefix, startAfter: startAfter, limit: limit, reverse: reverse,
            columnFamily: Some(handle))
    }

    public func commitWriteBatchResult(batch: RocksDbWriteBatch): RocksDbOperationResult<Unit> {
        if (closed) {
            return RocksDbOperationResult<Unit>.Err(RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }
        if (batch.boundOwner() != 0 && batch.boundOwner() != db.toUIntNative()) {
            return RocksDbOperationResult<Unit>.Err(
                RocksDbError(RocksDbErrorKind.FfiFailure, "write batch contains a column family from another database"))
        }
        let nativeBatch = match (batch.nativeHandle()) {
            case Some(value) => value
            case None => return RocksDbOperationResult<Unit>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "rocksdb write batch is closed"))
        }
        var errPtr = CPointer<UInt8>()
        unsafe { rocksdb_write(db, writeOptions, nativeBatch, inout errPtr) }
        if (!errPtr.isNull()) {
            let error = takeOwnedCString(errPtr)
            return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(error), error))
        }
        return RocksDbOperationResult<Unit>.Ok(())
    }

    public func deletePrefixResult(prefix: Array<UInt8>): RocksDbOperationResult<Unit> {
        return deletePrefixWithColumnFamily(prefix, None)
    }

    public func deletePrefixResult(
        columnFamily: RocksDbColumnFamily,
        prefix: Array<UInt8>
    ): RocksDbOperationResult<Unit> {
        let handle = match (columnFamily.nativeHandle(db.toUIntNative())) {
            case Some(raw) => raw
            case None => return invalidColumnFamilyError<Unit>()
        }
        return deletePrefixWithColumnFamily(prefix, Some((columnFamily, handle)))
    }

    private func deletePrefixWithColumnFamily(
        prefix: Array<UInt8>,
        columnFamily: Option<(RocksDbColumnFamily, CPointer<rocksdb_column_family_handle_t>)>
    ): RocksDbOperationResult<Unit> {
        match (nextPrefixUpperBoundBytes(prefix)) {
            case Some(upperBound) =>
                let created = RocksDbWriteBatch.create()
                let batch = match (created) {
                    case RocksDbOperationResult<RocksDbWriteBatch>.Ok(value) => value
                    case RocksDbOperationResult<RocksDbWriteBatch>.NotFound => return RocksDbOperationResult<Unit>.Err(
                        RocksDbError(RocksDbErrorKind.FfiFailure, "rocksdb write batch create returned no batch"))
                    case RocksDbOperationResult<RocksDbWriteBatch>.Err(error) => return RocksDbOperationResult<Unit>
                        .Err(error)
                }
                try {
                    let deleted = match (columnFamily) {
                        case Some((cf, _)) => batch.deleteRangeBytes(cf, prefix, upperBound)
                        case None => batch.deleteRangeBytes(prefix, upperBound)
                    }
                    match (deleted) {
                        case RocksDbOperationResult<Unit>.Ok(_) => return commitWriteBatchResult(batch)
                        case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<Unit>.NotFound
                        case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
                    }
                } finally {
                    batch.close()
                }
            case None => ()
        }

        while (true) {
            let opened = match (columnFamily) {
                case Some((cf, _)) => openPrefixCursorResult(cf, prefix, limit: 512)
                case None => openPrefixCursorResult(prefix, limit: 512)
            }
            let cursor = match (opened) {
                case RocksDbOperationResult<RocksDbPrefixCursor>.Ok(value) => value
                case RocksDbOperationResult<RocksDbPrefixCursor>.NotFound => return RocksDbOperationResult<Unit>.Ok(())
                case RocksDbOperationResult<RocksDbPrefixCursor>.Err(error) => return RocksDbOperationResult<Unit>.Err(
                    error)
            }
            let keys = ArrayList<Array<UInt8>>()
            try {
                while (cursor.isValid()) {
                    match (cursor.keyBytes()) {
                        case RocksDbOperationResult<Array<UInt8>>.Ok(key) => keys.add(key)
                        case RocksDbOperationResult<Array<UInt8>>.NotFound => break
                        case RocksDbOperationResult<Array<UInt8>>.Err(error) => return RocksDbOperationResult<Unit>
                            .Err(error)
                    }
                    cursor.next()
                }
                match (cursor.status()) {
                    case RocksDbOperationResult<Unit>.Ok(_) => ()
                    case RocksDbOperationResult<Unit>.NotFound => ()
                    case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
                }
            } finally {
                cursor.close()
            }

            if (keys.size == 0) {
                return RocksDbOperationResult<Unit>.Ok(())
            }
            let created = RocksDbWriteBatch.create()
            let batch = match (created) {
                case RocksDbOperationResult<RocksDbWriteBatch>.Ok(value) => value
                case RocksDbOperationResult<RocksDbWriteBatch>.NotFound => return RocksDbOperationResult<Unit>.Err(
                    RocksDbError(RocksDbErrorKind.FfiFailure, "rocksdb write batch create returned no batch"))
                case RocksDbOperationResult<RocksDbWriteBatch>.Err(error) => return RocksDbOperationResult<Unit>.Err(
                    error)
            }
            try {
                for (key in keys) {
                    let deleted = match (columnFamily) {
                        case Some((cf, _)) => batch.deleteBytes(cf, key)
                        case None => batch.deleteBytes(key)
                    }
                    match (deleted) {
                        case RocksDbOperationResult<Unit>.Ok(_) => ()
                        case RocksDbOperationResult<Unit>.NotFound => ()
                        case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
                    }
                }
                match (commitWriteBatchResult(batch)) {
                    case RocksDbOperationResult<Unit>.Ok(_) => ()
                    case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<Unit>.NotFound
                    case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
                }
            } finally {
                batch.close()
            }
        }
        return RocksDbOperationResult<Unit>.Ok(())
    }

    public func columnFamily(name: String): Option<RocksDbColumnFamily> {
        if (closed) {
            return None
        }
        for (columnFamily in columnFamilies) {
            if (!columnFamily.isClosed() && columnFamily.name == name) {
                return Some(columnFamily)
            }
        }
        return None
    }

    public func columnFamilyNames(): Array<String> {
        let names = ArrayList<String>()
        if (!closed) {
            for (columnFamily in columnFamilies where !columnFamily.isClosed()) {
                names.add(columnFamily.name)
            }
        }
        return names.toArray()
    }

    public func ensureColumnFamilyResult(name: String): RocksDbOperationResult<RocksDbColumnFamily> {
        if (closed) {
            return RocksDbOperationResult<RocksDbColumnFamily>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }
        if (name.size == 0 || name == "default") {
            match (columnFamily("default")) {
                case Some(value) => return RocksDbOperationResult<RocksDbColumnFamily>.Ok(value)
                case None => return RocksDbOperationResult<RocksDbColumnFamily>.Err(
                    RocksDbError(RocksDbErrorKind.FfiFailure, "default column family is unavailable"))
            }
        }
        match (columnFamily(name)) {
            case Some(value) => return RocksDbOperationResult<RocksDbColumnFamily>.Ok(value)
            case None => ()
        }
        let options = unsafe { rocksdb_options_create() }
        if (options.isNull()) {
            return RocksDbOperationResult<RocksDbColumnFamily>.Err(
                RocksDbError(RocksDbErrorKind.FfiFailure, "rocksdb_options_create failed"))
        }
        unsafe { rocksdb_options_set_compression(options, ROCKSDB_NO_COMPRESSION) }
        let nameC = unsafe { LibC.mallocCString(name) }
        var errPtr = CPointer<UInt8>()
        let handle = unsafe { rocksdb_create_column_family(db, options, nameC, inout errPtr) }
        unsafe {
            LibC.free(nameC)
            rocksdb_options_destroy(options)
        }
        if (!errPtr.isNull()) {
            let error = takeOwnedCString(errPtr)
            if (!handle.isNull()) {
                unsafe { rocksdb_column_family_handle_destroy(handle) }
            }
            return RocksDbOperationResult<RocksDbColumnFamily>.Err(RocksDbError(classifyRocksDbError(error), error))
        }
        if (handle.isNull()) {
            return RocksDbOperationResult<RocksDbColumnFamily>.Err(
                RocksDbError(RocksDbErrorKind.FfiFailure, "rocksdb_create_column_family returned null"))
        }
        let created = RocksDbColumnFamily(name, handle, db.toUIntNative())
        columnFamilies.add(created)
        return RocksDbOperationResult<RocksDbColumnFamily>.Ok(created)
    }

    public func dropColumnFamilyResult(columnFamily: RocksDbColumnFamily): RocksDbOperationResult<Unit> {
        if (closed) {
            return RocksDbOperationResult<Unit>.Err(RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }
        if (columnFamily.name == "default") {
            return RocksDbOperationResult<Unit>.Err(
                RocksDbError(RocksDbErrorKind.Unsupported, "the default column family cannot be dropped"))
        }
        let handle = match (columnFamily.nativeHandle(db.toUIntNative())) {
            case Some(raw) => raw
            case None => return invalidColumnFamilyError<Unit>()
        }
        var errPtr = CPointer<UInt8>()
        unsafe { rocksdb_drop_column_family(db, handle, inout errPtr) }
        if (!errPtr.isNull()) {
            let error = takeOwnedCString(errPtr)
            return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(error), error))
        }
        columnFamily.close()
        return RocksDbOperationResult<Unit>.Ok(())
    }

    public func createSnapshotResult(): RocksDbOperationResult<RocksDbSnapshot> {
        if (closed) {
            return RocksDbOperationResult<RocksDbSnapshot>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }
        let handle = unsafe { rocksdb_create_snapshot(db) }
        if (handle.isNull()) {
            return RocksDbOperationResult<RocksDbSnapshot>.Err(
                RocksDbError(RocksDbErrorKind.FfiFailure, "rocksdb_create_snapshot returned null"))
        }
        let snapshot = RocksDbSnapshot(this, db, handle)
        snapshots.add(snapshot)
        return RocksDbOperationResult<RocksDbSnapshot>.Ok(snapshot)
    }

    public func flushResult(wait!: Bool = true): RocksDbOperationResult<Unit> {
        return flushWithColumnFamily(None, wait)
    }

    public func flushResult(
        columnFamily: RocksDbColumnFamily,
        wait!: Bool = true
    ): RocksDbOperationResult<Unit> {
        let handle = match (columnFamily.nativeHandle(db.toUIntNative())) {
            case Some(raw) => raw
            case None => return invalidColumnFamilyError<Unit>()
        }
        return flushWithColumnFamily(Some(handle), wait)
    }

    private func flushWithColumnFamily(
        columnFamily: Option<CPointer<rocksdb_column_family_handle_t>>,
        wait: Bool
    ): RocksDbOperationResult<Unit> {
        if (closed) {
            return RocksDbOperationResult<Unit>.Err(RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }
        let options = unsafe { rocksdb_flushoptions_create() }
        if (options.isNull()) {
            return RocksDbOperationResult<Unit>.Err(
                RocksDbError(RocksDbErrorKind.FfiFailure, "rocksdb_flushoptions_create failed"))
        }
        unsafe { rocksdb_flushoptions_set_wait(options, if (wait) {
            1u8
        } else {
            0u8
        }) }
        var errPtr = CPointer<UInt8>()
        try {
            match (columnFamily) {
                case Some(cf) => unsafe { rocksdb_flush_cf(db, options, cf, inout errPtr) }
                case None => unsafe { rocksdb_flush(db, options, inout errPtr) }
            }
        } finally {
            unsafe { rocksdb_flushoptions_destroy(options) }
        }
        if (!errPtr.isNull()) {
            let error = takeOwnedCString(errPtr)
            return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(error), error))
        }
        return RocksDbOperationResult<Unit>.Ok(())
    }

    public func compactRangeResult(
        startKey!: Option<Array<UInt8>> = None,
        endKey!: Option<Array<UInt8>> = None
    ): RocksDbOperationResult<Unit> {
        return compactRangeWithColumnFamily(None, startKey, endKey)
    }

    public func compactRangeResult(
        columnFamily: RocksDbColumnFamily,
        startKey!: Option<Array<UInt8>> = None,
        endKey!: Option<Array<UInt8>> = None
    ): RocksDbOperationResult<Unit> {
        let handle = match (columnFamily.nativeHandle(db.toUIntNative())) {
            case Some(raw) => raw
            case None => return invalidColumnFamilyError<Unit>()
        }
        return compactRangeWithColumnFamily(Some(handle), startKey, endKey)
    }

    private func compactRangeWithColumnFamily(
        columnFamily: Option<CPointer<rocksdb_column_family_handle_t>>,
        startKey: Option<Array<UInt8>>,
        endKey: Option<Array<UInt8>>
    ): RocksDbOperationResult<Unit> {
        if (closed) {
            return RocksDbOperationResult<Unit>.Err(RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }
        let start = startKey ?? Array<UInt8>()
        let end = endKey ?? Array<UInt8>()
        let startHandle = unsafe { acquireArrayRawData(start) }
        let endHandle = unsafe { acquireArrayRawData(end) }
        try {
            match (columnFamily) {
                case Some(cf) => unsafe {
                    rocksdb_compact_range_cf(db, cf, CString(startHandle.pointer), UIntNative(start.size),
                        CString(endHandle.pointer), UIntNative(end.size))
                }
                case None => unsafe {
                    rocksdb_compact_range(db, CString(startHandle.pointer), UIntNative(start.size),
                        CString(endHandle.pointer), UIntNative(end.size))
                }
            }
        } finally {
            unsafe { releaseArrayRawData(endHandle) }
            unsafe { releaseArrayRawData(startHandle) }
        }
        return RocksDbOperationResult<Unit>.Ok(())
    }

    public func propertyUInt64Result(name: String): RocksDbOperationResult<UInt64> {
        return propertyUInt64WithColumnFamily(None, name)
    }

    public func propertyUInt64Result(
        columnFamily: RocksDbColumnFamily,
        name: String
    ): RocksDbOperationResult<UInt64> {
        let handle = match (columnFamily.nativeHandle(db.toUIntNative())) {
            case Some(raw) => raw
            case None => return invalidColumnFamilyError<UInt64>()
        }
        return propertyUInt64WithColumnFamily(Some(handle), name)
    }

    private func propertyUInt64WithColumnFamily(
        columnFamily: Option<CPointer<rocksdb_column_family_handle_t>>,
        name: String
    ): RocksDbOperationResult<UInt64> {
        if (closed) {
            return RocksDbOperationResult<UInt64>.Err(RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }
        let nameC = unsafe { LibC.mallocCString(name) }
        var value: UInt64 = 0
        let status = match (columnFamily) {
            case Some(cf) => unsafe { rocksdb_property_int_cf(db, cf, nameC, inout value) }
            case None => unsafe { rocksdb_property_int(db, nameC, inout value) }
        }
        unsafe { LibC.free(nameC) }
        if (status != 0) {
            return RocksDbOperationResult<UInt64>.NotFound
        }
        return RocksDbOperationResult<UInt64>.Ok(value)
    }

    public func propertyStringResult(name: String): RocksDbOperationResult<String> {
        return propertyStringWithColumnFamily(None, name)
    }

    public func propertyStringResult(
        columnFamily: RocksDbColumnFamily,
        name: String
    ): RocksDbOperationResult<String> {
        let handle = match (columnFamily.nativeHandle(db.toUIntNative())) {
            case Some(raw) => raw
            case None => return invalidColumnFamilyError<String>()
        }
        return propertyStringWithColumnFamily(Some(handle), name)
    }

    private func propertyStringWithColumnFamily(
        columnFamily: Option<CPointer<rocksdb_column_family_handle_t>>,
        name: String
    ): RocksDbOperationResult<String> {
        if (closed) {
            return RocksDbOperationResult<String>.Err(RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }
        let nameC = unsafe { LibC.mallocCString(name) }
        let value = match (columnFamily) {
            case Some(cf) => unsafe { rocksdb_property_value_cf(db, cf, nameC) }
            case None => unsafe { rocksdb_property_value(db, nameC) }
        }
        unsafe { LibC.free(nameC) }
        if (value.isNull()) {
            return RocksDbOperationResult<String>.NotFound
        }
        return RocksDbOperationResult<String>.Ok(takeOwnedCString(value))
    }

    public func approximateSizeResult(
        startKey: Array<UInt8>,
        endKey: Array<UInt8>
    ): RocksDbOperationResult<UInt64> {
        return approximateSizeWithColumnFamily(None, startKey, endKey)
    }

    public func approximateSizeResult(
        columnFamily: RocksDbColumnFamily,
        startKey: Array<UInt8>,
        endKey: Array<UInt8>
    ): RocksDbOperationResult<UInt64> {
        let handle = match (columnFamily.nativeHandle(db.toUIntNative())) {
            case Some(raw) => raw
            case None => return invalidColumnFamilyError<UInt64>()
        }
        return approximateSizeWithColumnFamily(Some(handle), startKey, endKey)
    }

    private func approximateSizeWithColumnFamily(
        columnFamily: Option<CPointer<rocksdb_column_family_handle_t>>,
        startKey: Array<UInt8>,
        endKey: Array<UInt8>
    ): RocksDbOperationResult<UInt64> {
        if (closed) {
            return RocksDbOperationResult<UInt64>.Err(RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }
        let startHandle = unsafe { acquireArrayRawData(startKey) }
        let endHandle = unsafe { acquireArrayRawData(endKey) }
        let starts = [CString(startHandle.pointer)]
        let ends = [CString(endHandle.pointer)]
        let startLengths = [UIntNative(startKey.size)]
        let endLengths = [UIntNative(endKey.size)]
        let sizes = [0u64]
        let startsHandle = unsafe { acquireArrayRawData(starts) }
        let endsHandle = unsafe { acquireArrayRawData(ends) }
        let startLengthsHandle = unsafe { acquireArrayRawData(startLengths) }
        let endLengthsHandle = unsafe { acquireArrayRawData(endLengths) }
        let sizesHandle = unsafe { acquireArrayRawData(sizes) }
        var errPtr = CPointer<UInt8>()
        try {
            match (columnFamily) {
                case Some(cf) => unsafe {
                    rocksdb_approximate_sizes_cf(db, cf, 1, startsHandle.pointer, startLengthsHandle.pointer,
                        endsHandle.pointer, endLengthsHandle.pointer, sizesHandle.pointer, inout errPtr)
                }
                case None => unsafe {
                    rocksdb_approximate_sizes(db, 1, startsHandle.pointer, startLengthsHandle.pointer,
                        endsHandle.pointer, endLengthsHandle.pointer, sizesHandle.pointer, inout errPtr)
                }
            }
        } finally {
            unsafe { releaseArrayRawData(sizesHandle) }
            unsafe { releaseArrayRawData(endLengthsHandle) }
            unsafe { releaseArrayRawData(startLengthsHandle) }
            unsafe { releaseArrayRawData(endsHandle) }
            unsafe { releaseArrayRawData(startsHandle) }
            unsafe { releaseArrayRawData(endHandle) }
            unsafe { releaseArrayRawData(startHandle) }
        }
        if (!errPtr.isNull()) {
            let error = takeOwnedCString(errPtr)
            return RocksDbOperationResult<UInt64>.Err(RocksDbError(classifyRocksDbError(error), error))
        }
        return RocksDbOperationResult<UInt64>.Ok(sizes[0])
    }

    public func latestSequenceNumberResult(): RocksDbOperationResult<UInt64> {
        if (closed) {
            return RocksDbOperationResult<UInt64>.Err(RocksDbError(RocksDbErrorKind.Closed, "rocksdb is closed"))
        }
        return RocksDbOperationResult<UInt64>.Ok(unsafe { rocksdb_get_latest_sequence_number(db) })
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        for (snapshot in snapshots) {
            snapshot.close()
        }
        for (columnFamily in columnFamilies) {
            columnFamily.close()
        }
        unsafe {
            rocksdb_readoptions_destroy(readOptions)
            rocksdb_writeoptions_destroy(writeOptions)
            rocksdb_close(db)
        }
    }

    private func invalidColumnFamilyError<T>(): RocksDbOperationResult<T> {
        return RocksDbOperationResult<T>.Err(
            RocksDbError(RocksDbErrorKind.Closed, "column family is closed or belongs to another database"))
    }

    private static func takeOwnedCString(raw: CPointer<UInt8>): String {
        let text = unsafe { CString(raw).toString() }
        unsafe { rocksdb_free(CPointer<Unit>(raw)) }
        return text
    }
}

public class RocksDbSnapshot <: Resource {
    private let owner: RocksDb
    private let db: CPointer<rocksdb_t>
    private let snapshot: CPointer<rocksdb_snapshot_t>
    private let readOptions: CPointer<rocksdb_readoptions_t>
    private var closed: Bool = false

    internal init(owner: RocksDb, db: CPointer<rocksdb_t>, snapshot: CPointer<rocksdb_snapshot_t>) {
        this.owner = owner
        this.db = db
        this.snapshot = snapshot
        let options = unsafe { rocksdb_readoptions_create() }
        if (options.isNull()) {
            unsafe { rocksdb_release_snapshot(db, snapshot) }
            throw Exception("rocksdb_readoptions_create failed")
        }
        unsafe {
            rocksdb_readoptions_set_snapshot(options, snapshot)
            rocksdb_readoptions_set_verify_checksums(options, 1u8)
            rocksdb_readoptions_set_fill_cache(options, 0u8)
        }
        this.readOptions = options
    }

    public func sequenceNumber(): UInt64 {
        if (closed) {
            return 0u64
        }
        return unsafe { llrocksdb_snapshot_get_sequence_number(snapshot) }
    }

    public func getBytesResult(key: Array<UInt8>): RocksDbOperationResult<Array<UInt8>> {
        if (closed) {
            return closedError<Array<UInt8>>()
        }
        return owner.getBytesWithOptionsResult(key, readOptions, None)
    }

    public func getBytesResult(
        columnFamily: RocksDbColumnFamily,
        key: Array<UInt8>
    ): RocksDbOperationResult<Array<UInt8>> {
        if (closed) {
            return closedError<Array<UInt8>>()
        }
        let handle = match (columnFamily.nativeHandle(db.toUIntNative())) {
            case Some(raw) => raw
            case None => return RocksDbOperationResult<Array<UInt8>>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "column family is closed or belongs to another database"))
        }
        return owner.getBytesWithOptionsResult(key, readOptions, Some(handle))
    }

    public func openPrefixCursorResult(
        prefix: Array<UInt8>,
        startAfter!: Option<Array<UInt8>> = None,
        limit!: Int64 = Int64.Max,
        reverse!: Bool = false
    ): RocksDbOperationResult<RocksDbPrefixCursor> {
        if (closed) {
            return closedError<RocksDbPrefixCursor>()
        }
        return RocksDbPrefixCursor.create(db, prefix, startAfter: startAfter, limit: limit, reverse: reverse,
            snapshot: Some(snapshot))
    }

    public func openPrefixCursorResult(
        columnFamily: RocksDbColumnFamily,
        prefix: Array<UInt8>,
        startAfter!: Option<Array<UInt8>> = None,
        limit!: Int64 = Int64.Max,
        reverse!: Bool = false
    ): RocksDbOperationResult<RocksDbPrefixCursor> {
        if (closed) {
            return closedError<RocksDbPrefixCursor>()
        }
        let handle = match (columnFamily.nativeHandle(db.toUIntNative())) {
            case Some(raw) => raw
            case None => return RocksDbOperationResult<RocksDbPrefixCursor>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "column family is closed or belongs to another database"))
        }
        return RocksDbPrefixCursor.create(db, prefix, startAfter: startAfter, limit: limit, reverse: reverse,
            columnFamily: Some(handle), snapshot: Some(snapshot))
    }

    public func isClosed(): Bool {
        return closed
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        unsafe {
            rocksdb_readoptions_destroy(readOptions)
            rocksdb_release_snapshot(db, snapshot)
        }
    }

    private func closedError<T>(): RocksDbOperationResult<T> {
        return RocksDbOperationResult<T>.Err(RocksDbError(RocksDbErrorKind.Closed, "rocksdb snapshot is closed"))
    }
}

public class RocksDbIterator <: Resource {
    private let iter: CPointer<rocksdb_iterator_t>
    private let readOptions: CPointer<rocksdb_readoptions_t>
    private var closed: Bool = false

    private init(iter: CPointer<rocksdb_iterator_t>, readOptions: CPointer<rocksdb_readoptions_t>) {
        this.iter = iter
        this.readOptions = readOptions
    }

    public static func create(
        db: CPointer<rocksdb_t>,
        columnFamily!: Option<CPointer<rocksdb_column_family_handle_t>> = None,
        snapshot!: Option<CPointer<rocksdb_snapshot_t>> = None
    ): RocksDbOperationResult<RocksDbIterator> {
        let options = unsafe { rocksdb_readoptions_create() }
        if (options.isNull()) {
            return RocksDbOperationResult<RocksDbIterator>.Err(
                RocksDbError(RocksDbErrorKind.FfiFailure, "rocksdb_readoptions_create failed"))
        }
        unsafe {
            rocksdb_readoptions_set_total_order_seek(options, 1u8)
            rocksdb_readoptions_set_verify_checksums(options, 1u8)
            rocksdb_readoptions_set_fill_cache(options, 0u8)
        }
        match (snapshot) {
            case Some(value) => unsafe { rocksdb_readoptions_set_snapshot(options, value) }
            case None => ()
        }
        let iter = match (columnFamily) {
            case Some(cf) => unsafe { rocksdb_create_iterator_cf(db, options, cf) }
            case None => unsafe { rocksdb_create_iterator(db, options) }
        }
        if (iter.isNull()) {
            unsafe { rocksdb_readoptions_destroy(options) }
            return RocksDbOperationResult<RocksDbIterator>.Err(
                RocksDbError(RocksDbErrorKind.FfiFailure, "rocksdb_create_iterator failed"))
        }
        return RocksDbOperationResult<RocksDbIterator>.Ok(RocksDbIterator(iter, options))
    }

    public func first(): Unit {
        if (!closed) {
            unsafe { rocksdb_iter_seek_to_first(iter) }
        }
    }

    public func last(): Unit {
        if (!closed) {
            unsafe { rocksdb_iter_seek_to_last(iter) }
        }
    }

    public func seek(key: Array<UInt8>): Unit {
        if (closed) {
            return
        }
        let keyHandle = unsafe { acquireArrayRawData(key) }
        try {
            unsafe { rocksdb_iter_seek(iter, CString(keyHandle.pointer), UIntNative(key.size)) }
        } finally {
            unsafe { releaseArrayRawData(keyHandle) }
        }
    }

    public func seekForPrev(key: Array<UInt8>): Unit {
        if (closed) {
            return
        }
        let keyHandle = unsafe { acquireArrayRawData(key) }
        try {
            unsafe { rocksdb_iter_seek_for_prev(iter, CString(keyHandle.pointer), UIntNative(key.size)) }
        } finally {
            unsafe { releaseArrayRawData(keyHandle) }
        }
    }

    public func next(): Unit {
        if (!closed && unsafe { rocksdb_iter_valid(iter) } != 0u8) {
            unsafe { rocksdb_iter_next(iter) }
        }
    }

    public func prev(): Unit {
        if (!closed && unsafe { rocksdb_iter_valid(iter) } != 0u8) {
            unsafe { rocksdb_iter_prev(iter) }
        }
    }

    public func isValid(): Bool {
        return !closed && unsafe { rocksdb_iter_valid(iter) } != 0u8
    }

    public func keyBytes(): RocksDbOperationResult<Array<UInt8>> {
        return currentBytes(true)
    }

    public func valueBytes(): RocksDbOperationResult<Array<UInt8>> {
        return currentBytes(false)
    }

    public func status(): RocksDbOperationResult<Unit> {
        if (closed) {
            return RocksDbOperationResult<Unit>.Err(RocksDbError(RocksDbErrorKind.Closed, "rocksdb iterator is closed"))
        }
        var errPtr = CPointer<UInt8>()
        unsafe { rocksdb_iter_get_error(iter, inout errPtr) }
        if (!errPtr.isNull()) {
            let error = takeOwnedCString(errPtr)
            return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(error), error))
        }
        return RocksDbOperationResult<Unit>.Ok(())
    }

    public func isClosed(): Bool {
        return closed
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        unsafe {
            rocksdb_iter_destroy(iter)
            rocksdb_readoptions_destroy(readOptions)
        }
    }

    private func currentBytes(readKey: Bool): RocksDbOperationResult<Array<UInt8>> {
        if (closed) {
            return RocksDbOperationResult<Array<UInt8>>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "rocksdb iterator is closed"))
        }
        if (unsafe { rocksdb_iter_valid(iter) } == 0u8) {
            return RocksDbOperationResult<Array<UInt8>>.NotFound
        }
        var length: UIntNative = 0
        let ptr = if (readKey) {
            unsafe { rocksdb_iter_key(iter, inout length) }
        } else {
            unsafe { rocksdb_iter_value(iter, inout length) }
        }
        match (copyNativeBytes(ptr, length)) {
            case Some(value) => return RocksDbOperationResult<Array<UInt8>>.Ok(value)
            case None => return RocksDbOperationResult<Array<UInt8>>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "rocksdb iterator returned an invalid native buffer"))
        }
    }

    private static func takeOwnedCString(raw: CPointer<UInt8>): String {
        let text = unsafe { CString(raw).toString() }
        unsafe { rocksdb_free(CPointer<Unit>(raw)) }
        return text
    }
}

public class RocksDbPrefixCursor <: Resource {
    private let iterator: RocksDbIterator
    private let prefix: Array<UInt8>
    private let reverse: Bool
    private let limit: Int64
    private var consumed: Int64 = 0
    private var closed: Bool = false

    private init(iterator: RocksDbIterator, prefix: Array<UInt8>, reverse: Bool, limit: Int64) {
        this.iterator = iterator
        this.prefix = prefix
        this.reverse = reverse
        this.limit = if (limit < 0) {
            0
        } else {
            limit
        }
    }

    public static func create(
        db: CPointer<rocksdb_t>,
        prefix: Array<UInt8>,
        startAfter!: Option<Array<UInt8>> = None,
        limit!: Int64 = Int64.Max,
        reverse!: Bool = false,
        columnFamily!: Option<CPointer<rocksdb_column_family_handle_t>> = None,
        snapshot!: Option<CPointer<rocksdb_snapshot_t>> = None
    ): RocksDbOperationResult<RocksDbPrefixCursor> {
        let opened = RocksDbIterator.create(db, columnFamily: columnFamily, snapshot: snapshot)
        let iterator = match (opened) {
            case RocksDbOperationResult<RocksDbIterator>.Ok(value) => value
            case RocksDbOperationResult<RocksDbIterator>.NotFound => return RocksDbOperationResult<RocksDbPrefixCursor>
                .NotFound
            case RocksDbOperationResult<RocksDbIterator>.Err(error) => return RocksDbOperationResult<RocksDbPrefixCursor>
                .Err(error)
        }

        if (reverse) {
            match (startAfter) {
                case Some(start) =>
                    iterator.seekForPrev(start)
                    if (iterator.isValid()) {
                        match (iterator.keyBytes()) {
                            case RocksDbOperationResult<Array<UInt8>>.Ok(key) =>
                                if (bytesEqual(key, start)) {
                                    iterator.prev()
                                }
                            case _ => ()
                        }
                    }
                case None => match (nextPrefixUpperBoundBytes(prefix)) {
                    case Some(upper) =>
                        iterator.seekForPrev(upper)
                        if (iterator.isValid()) {
                            match (iterator.keyBytes()) {
                                case RocksDbOperationResult<Array<UInt8>>.Ok(key) =>
                                    if (!bytesStartWith(key, prefix)) {
                                        iterator.prev()
                                    }
                                case _ => ()
                            }
                        }
                    case None => iterator.last()
                }
            }
        } else {
            match (startAfter) {
                case Some(start) =>
                    iterator.seek(start)
                    if (iterator.isValid()) {
                        match (iterator.keyBytes()) {
                            case RocksDbOperationResult<Array<UInt8>>.Ok(key) =>
                                if (bytesEqual(key, start)) {
                                    iterator.next()
                                }
                            case _ => ()
                        }
                    }
                case None => iterator.seek(prefix)
            }
        }
        return RocksDbOperationResult<RocksDbPrefixCursor>.Ok(RocksDbPrefixCursor(iterator, prefix, reverse, limit))
    }

    public func isValid(): Bool {
        if (closed || consumed >= limit || !iterator.isValid()) {
            return false
        }
        match (iterator.keyBytes()) {
            case RocksDbOperationResult<Array<UInt8>>.Ok(key) => return bytesStartWith(key, prefix)
            case _ => return false
        }
    }

    public func keyBytes(): RocksDbOperationResult<Array<UInt8>> {
        if (!isValid()) {
            return RocksDbOperationResult<Array<UInt8>>.NotFound
        }
        return iterator.keyBytes()
    }

    public func valueBytes(): RocksDbOperationResult<Array<UInt8>> {
        if (!isValid()) {
            return RocksDbOperationResult<Array<UInt8>>.NotFound
        }
        return iterator.valueBytes()
    }

    public func next(): Unit {
        if (!isValid()) {
            return
        }
        consumed += 1
        if (reverse) {
            iterator.prev()
        } else {
            iterator.next()
        }
    }

    public func status(): RocksDbOperationResult<Unit> {
        return iterator.status()
    }

    public func isClosed(): Bool {
        return closed
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        iterator.close()
    }
}

public class RocksDbWriteBatch <: Resource {
    private let batch: CPointer<rocksdb_writebatch_t>
    private var closed: Bool = false

    private init(batch: CPointer<rocksdb_writebatch_t>) {
        this.batch = batch
    }

    public static func create(): RocksDbOperationResult<RocksDbWriteBatch> {
        let batch = unsafe { rocksdb_writebatch_create() }
        if (batch.isNull()) {
            return RocksDbOperationResult<RocksDbWriteBatch>.Err(
                RocksDbError(RocksDbErrorKind.FfiFailure, "rocksdb_writebatch_create failed"))
        }
        return RocksDbOperationResult<RocksDbWriteBatch>.Ok(RocksDbWriteBatch(batch))
    }

    public func putBytes(key: Array<UInt8>, value: Array<UInt8>): RocksDbOperationResult<Unit> {
        if (closed) {
            return closedError()
        }
        let keyHandle = unsafe { acquireArrayRawData(key) }
        let valueHandle = unsafe { acquireArrayRawData(value) }
        try {
            unsafe {
                rocksdb_writebatch_put(batch, CString(keyHandle.pointer), UIntNative(key.size),
                    CString(valueHandle.pointer), UIntNative(value.size))
            }
        } finally {
            unsafe { releaseArrayRawData(valueHandle) }
            unsafe { releaseArrayRawData(keyHandle) }
        }
        return RocksDbOperationResult<Unit>.Ok(())
    }

    public func put(key: String, value: String): RocksDbOperationResult<Unit> {
        return putBytes(key.toArray(), value.toArray())
    }

    public func putBytes(
        columnFamily: RocksDbColumnFamily,
        key: Array<UInt8>,
        value: Array<UInt8>
    ): RocksDbOperationResult<Unit> {
        if (closed) {
            return closedError()
        }
        let cf = match (bindColumnFamily(columnFamily)) {
            case Some(raw) => raw
            case None => return RocksDbOperationResult<Unit>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "column family is closed or belongs to another database"))
        }
        let keyHandle = unsafe { acquireArrayRawData(key) }
        let valueHandle = unsafe { acquireArrayRawData(value) }
        try {
            unsafe {
                rocksdb_writebatch_put_cf(batch, cf, CString(keyHandle.pointer), UIntNative(key.size),
                    CString(valueHandle.pointer), UIntNative(value.size))
            }
        } finally {
            unsafe { releaseArrayRawData(valueHandle) }
            unsafe { releaseArrayRawData(keyHandle) }
        }
        return RocksDbOperationResult<Unit>.Ok(())
    }

    public func put(
        columnFamily: RocksDbColumnFamily,
        key: String,
        value: String
    ): RocksDbOperationResult<Unit> {
        return putBytes(columnFamily, key.toArray(), value.toArray())
    }

    public func deleteBytes(key: Array<UInt8>): RocksDbOperationResult<Unit> {
        if (closed) {
            return closedError()
        }
        let keyHandle = unsafe { acquireArrayRawData(key) }
        try {
            unsafe { rocksdb_writebatch_delete(batch, CString(keyHandle.pointer), UIntNative(key.size)) }
        } finally {
            unsafe { releaseArrayRawData(keyHandle) }
        }
        return RocksDbOperationResult<Unit>.Ok(())
    }

    public func delete(key: String): RocksDbOperationResult<Unit> {
        return deleteBytes(key.toArray())
    }

    public func deleteBytes(
        columnFamily: RocksDbColumnFamily,
        key: Array<UInt8>
    ): RocksDbOperationResult<Unit> {
        if (closed) {
            return closedError()
        }
        let cf = match (bindColumnFamily(columnFamily)) {
            case Some(raw) => raw
            case None => return RocksDbOperationResult<Unit>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "column family is closed or belongs to another database"))
        }
        let keyHandle = unsafe { acquireArrayRawData(key) }
        try {
            unsafe { rocksdb_writebatch_delete_cf(batch, cf, CString(keyHandle.pointer), UIntNative(key.size)) }
        } finally {
            unsafe { releaseArrayRawData(keyHandle) }
        }
        return RocksDbOperationResult<Unit>.Ok(())
    }

    public func delete(columnFamily: RocksDbColumnFamily, key: String): RocksDbOperationResult<Unit> {
        return deleteBytes(columnFamily, key.toArray())
    }

    public func deleteRangeBytes(
        startKey: Array<UInt8>,
        endKey: Array<UInt8>
    ): RocksDbOperationResult<Unit> {
        if (closed) {
            return closedError()
        }
        let startHandle = unsafe { acquireArrayRawData(startKey) }
        let endHandle = unsafe { acquireArrayRawData(endKey) }
        try {
            unsafe {
                rocksdb_writebatch_delete_range(batch, CString(startHandle.pointer), UIntNative(startKey.size),
                    CString(endHandle.pointer), UIntNative(endKey.size))
            }
        } finally {
            unsafe { releaseArrayRawData(endHandle) }
            unsafe { releaseArrayRawData(startHandle) }
        }
        return RocksDbOperationResult<Unit>.Ok(())
    }

    public func deleteRange(startKey: String, endKey: String): RocksDbOperationResult<Unit> {
        return deleteRangeBytes(startKey.toArray(), endKey.toArray())
    }

    public func deleteRangeBytes(
        columnFamily: RocksDbColumnFamily,
        startKey: Array<UInt8>,
        endKey: Array<UInt8>
    ): RocksDbOperationResult<Unit> {
        if (closed) {
            return closedError()
        }
        let cf = match (bindColumnFamily(columnFamily)) {
            case Some(raw) => raw
            case None => return RocksDbOperationResult<Unit>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "column family is closed or belongs to another database"))
        }
        let startHandle = unsafe { acquireArrayRawData(startKey) }
        let endHandle = unsafe { acquireArrayRawData(endKey) }
        try {
            unsafe {
                rocksdb_writebatch_delete_range_cf(batch, cf, CString(startHandle.pointer), UIntNative(startKey.size),
                    CString(endHandle.pointer), UIntNative(endKey.size))
            }
        } finally {
            unsafe { releaseArrayRawData(endHandle) }
            unsafe { releaseArrayRawData(startHandle) }
        }
        return RocksDbOperationResult<Unit>.Ok(())
    }

    public func deleteRange(
        columnFamily: RocksDbColumnFamily,
        startKey: String,
        endKey: String
    ): RocksDbOperationResult<Unit> {
        return deleteRangeBytes(columnFamily, startKey.toArray(), endKey.toArray())
    }

    internal func nativeHandle(): Option<CPointer<rocksdb_writebatch_t>> {
        if (closed) {
            return None
        }
        return Some(batch)
    }

    internal func boundOwner(): UIntNative {
        return boundOwnerKey
    }

    private var boundOwnerKey: UIntNative = 0

    private func bindColumnFamily(columnFamily: RocksDbColumnFamily): Option<CPointer<rocksdb_column_family_handle_t>> {
        let candidate = columnFamily.ownerToken()
        if (boundOwnerKey == 0) {
            boundOwnerKey = candidate
        } else if (boundOwnerKey != candidate) {
            return None
        }
        return columnFamily.nativeHandle(boundOwnerKey)
    }

    public func isClosed(): Bool {
        return closed
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        unsafe { rocksdb_writebatch_destroy(batch) }
    }

    private func closedError(): RocksDbOperationResult<Unit> {
        return RocksDbOperationResult<Unit>.Err(RocksDbError(RocksDbErrorKind.Closed, "rocksdb write batch is closed"))
    }
}

public class RocksDbTxn <: Resource {
    private let txn: CPointer<rocksdb_transaction_t>
    private let readOptions: CPointer<rocksdb_readoptions_t>
    private let ownerKey: UIntNative
    private var closed: Bool = false

    private init(txn: CPointer<rocksdb_transaction_t>, readOptions: CPointer<rocksdb_readoptions_t>,
        ownerKey: UIntNative) {
        this.txn = txn
        this.readOptions = readOptions
        this.ownerKey = ownerKey
    }

    public static func wrap(txn: CPointer<rocksdb_transaction_t>, readOptions: CPointer<rocksdb_readoptions_t>,
        ownerKey: UIntNative): RocksDbTxn {
        return RocksDbTxn(txn, readOptions, ownerKey)
    }

    public func getResult(key: String): RocksDbOperationResult<String> {
        if (closed) {
            return RocksDbOperationResult<String>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "rocksdb transaction is closed"))
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

    // ---- column family 变体 ----

    private func resolveCfHandle(cf: RocksDbColumnFamily): Option<CPointer<rocksdb_column_family_handle_t>> {
        if (cf.isClosed() || cf.ownerToken() != ownerKey) {
            return None
        }
        return cf.nativeHandle(ownerKey)
    }

    public func getResultCf(cf: RocksDbColumnFamily, key: String): RocksDbOperationResult<String> {
        if (closed) {
            return RocksDbOperationResult<String>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "rocksdb transaction is closed"))
        }
        let handle = resolveCfHandle(cf) ?? return RocksDbOperationResult<String>.Err(
            RocksDbError(RocksDbErrorKind.FfiFailure, "column family does not belong to this database"))
        var valueLen: UIntNative = 0
        var errPtr = CPointer<UInt8>()
        let valuePtr = unsafe {
            let keyBytes = key.toArray()
            let keyHandle = acquireArrayRawData(keyBytes)
            try {
                rocksdb_transaction_get_cf(
                    txn,
                    readOptions,
                    handle,
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

    public func putResultCf(cf: RocksDbColumnFamily, key: String, value: String): RocksDbOperationResult<Unit> {
        if (closed) {
            return RocksDbOperationResult<Unit>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "rocksdb transaction is closed"))
        }
        let handle = resolveCfHandle(cf) ?? return RocksDbOperationResult<Unit>.Err(
            RocksDbError(RocksDbErrorKind.FfiFailure, "column family does not belong to this database"))
        var errPtr = CPointer<UInt8>()
        unsafe {
            let keyBytes = key.toArray()
            let keyHandle = acquireArrayRawData(keyBytes)
            let valueBytes = value.toArray()
            let valueHandle = acquireArrayRawData(valueBytes)
            try {
                rocksdb_transaction_put_cf(
                    txn,
                    handle,
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
        }
        if (!errPtr.isNull()) {
            let error = takeOwnedCString(errPtr)
            return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(error), error))
        }
        return RocksDbOperationResult<Unit>.Ok(())
    }

    public func deleteResultCf(cf: RocksDbColumnFamily, key: String): RocksDbOperationResult<Unit> {
        if (closed) {
            return RocksDbOperationResult<Unit>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "rocksdb transaction is closed"))
        }
        let handle = resolveCfHandle(cf) ?? return RocksDbOperationResult<Unit>.Err(
            RocksDbError(RocksDbErrorKind.FfiFailure, "column family does not belong to this database"))
        var errPtr = CPointer<UInt8>()
        unsafe {
            let keyBytes = key.toArray()
            let keyHandle = acquireArrayRawData(keyBytes)
            try {
                rocksdb_transaction_delete_cf(
                    txn,
                    handle,
                    CString(keyHandle.pointer),
                    UIntNative(keyBytes.size),
                    inout errPtr
                )
            } finally {
                releaseArrayRawData(keyHandle)
            }
        }
        if (!errPtr.isNull()) {
            let error = takeOwnedCString(errPtr)
            return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(error), error))
        }
        return RocksDbOperationResult<Unit>.Ok(())
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
            markFinished()
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
            markFinished()
            return RocksDbOperationResult<Unit>.Ok(())
        }
        return RocksDbOperationResult<Unit>.Err(RocksDbError(classifyRocksDbError(err), err))
    }

    private var finished: Bool = false

    // 事务结束标记：commit 或 rollback 成功后置位；未结束时 close 会先回滚（rollback-on-close），
    // 防止未提交状态泄漏到 DB。
    private func markFinished(): Unit {
        finished = true
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        if (!finished) {
            var errPtr = CPointer<UInt8>()
            unsafe { rocksdb_transaction_rollback(txn, inout errPtr) }
            if (!errPtr.isNull()) {
                unsafe { rocksdb_free(CPointer<Unit>(errPtr)) }
            }
        }
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
        // UIntNative → Int64 上限检查：超界视为空值（数据异常，不分配超界数组）。
        if (length > UIntNative(Int64.Max)) {
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
            return RocksDbOperationResult<String>.Err(
                RocksDbError(RocksDbErrorKind.Closed, "rocksdb optimistic db is closed"))
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
        if (merges.size > 0) {
            return (false, "unsupported: no RocksDB merge operator is configured")
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
            return (true, Some(RocksDbTxn.wrap(txn, readOptions, db.toUIntNative())), "")
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
        // UIntNative → Int64 上限检查：超界视为空值（数据异常，不分配超界数组）。
        if (length > UIntNative(Int64.Max)) {
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
