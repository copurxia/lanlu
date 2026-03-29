package rocksdb_ffi

import std.collection.*

public class RocksDb {
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

    public static func openLowMemory(path: String): (Bool, Option<RocksDb>, String) {
        let options = unsafe { rocksdb_options_create() }
        if (options.isNull()) {
            return (false, None, "rocksdb_options_create failed")
        }

        let tableOptions = unsafe { rocksdb_block_based_options_create() }
        if (tableOptions.isNull()) {
            unsafe { rocksdb_options_destroy(options) }
            return (false, None, "rocksdb_block_based_options_create failed")
        }

        unsafe {
            rocksdb_options_set_create_if_missing(options, 1u8)
            rocksdb_options_set_paranoid_checks(options, 0u8)
            rocksdb_options_set_compression(options, ROCKSDB_NO_COMPRESSION)
            rocksdb_options_set_write_buffer_size(options, 64 * 1024)
            rocksdb_options_set_db_write_buffer_size(options, 128 * 1024)
            rocksdb_options_set_max_write_buffer_number(options, 2)
            rocksdb_options_set_min_write_buffer_number_to_merge(options, 1)
            rocksdb_options_set_max_write_buffer_number_to_maintain(options, 0)
            rocksdb_options_set_max_open_files(options, 32)
            rocksdb_options_set_max_background_jobs(options, 1)
            rocksdb_options_set_keep_log_file_num(options, 1)
            rocksdb_options_set_use_fsync(options, 0u8)
            rocksdb_options_set_allow_mmap_reads(options, 1u8)
            rocksdb_options_set_bytes_per_sync(options, 0u64)

            // This RocksDB instance is used as an on-disk index store.
            // Prefer OS page cache and small memtables over RocksDB-managed caches.
            rocksdb_block_based_options_set_no_block_cache(tableOptions, 1u8)
            rocksdb_block_based_options_set_cache_index_and_filter_blocks(tableOptions, 0u8)
            rocksdb_block_based_options_set_cache_index_and_filter_blocks_with_high_priority(tableOptions, 0u8)
            rocksdb_block_based_options_set_pin_l0_filter_and_index_blocks_in_cache(tableOptions, 0u8)
            rocksdb_block_based_options_set_pin_top_level_index_and_filter(tableOptions, 0u8)
            rocksdb_options_set_block_based_table_factory(options, tableOptions)
        }

        let pathC = unsafe { LibC.mallocCString(path) }
        var errPtr = CPointer<UInt8>()
        let db = unsafe { rocksdb_open(options, pathC, inout errPtr) }
        unsafe {
            LibC.free(pathC)
            rocksdb_block_based_options_destroy(tableOptions)
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

    public func get(key: String): (Bool, Option<String>, String) {
        if (closed) {
            return (false, None, "rocksdb is closed")
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
            return (false, None, takeOwnedCString(errPtr))
        }
        if (valuePtr.isNull()) {
            return (true, None, "")
        }

        let out = Array<UInt8>(Int64(valueLen), { i => unsafe { (valuePtr + i).read() } })
        unsafe { rocksdb_free(CPointer<Unit>(valuePtr)) }
        return (true, Some(String.fromUtf8(out)), "")
    }

    public func put(key: String, value: String): (Bool, String) {
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

    public func delete(key: String): (Bool, String) {
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

    public func scanByPrefix(prefix: String): (Bool, Array<(String, String)>, String) {
        if (closed) {
            return (false, [], "rocksdb is closed")
        }

        let iter = unsafe { rocksdb_create_iterator(db, readOptions) }
        if (iter.isNull()) {
            return (false, [], "rocksdb_create_iterator failed")
        }

        let prefixBytes = prefix.toArray()
        let prefixLen = prefixBytes.size
        let results = ArrayList<(String, String)>()

        unsafe {
            let prefixHandle = acquireArrayRawData(prefixBytes)
            try {
                rocksdb_iter_seek(
                    iter,
                    CString(prefixHandle.pointer),
                    UIntNative(prefixLen)
                )
            } finally {
                releaseArrayRawData(prefixHandle)
            }
        }

        try {
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

            return (true, results.toArray(), "")
        } finally {
            unsafe { rocksdb_iter_destroy(iter) }
        }
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
        let out = Array<UInt8>(Int64(length), { i => unsafe { (ptr + i).read() } })
        return String.fromUtf8(out)
    }
}
