package rocksdb_ffi

@C
public struct rocksdb_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_transactiondb_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_optimistictransactiondb_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_options_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_transactiondb_options_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_block_based_table_options_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_cache_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_transaction_options_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_optimistictransaction_options_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_readoptions_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_writeoptions_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_transaction_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_writebatch_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_iterator_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_column_family_handle_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_snapshot_t {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct rocksdb_flushoptions_t {
    init() {
        throw Exception("type should not be inited")
    }
}

public const ROCKSDB_NO_COMPRESSION: Int32 = 0
public const ROCKSDB_SNAPPY_COMPRESSION: Int32 = 1
public const ROCKSDB_ZLIB_COMPRESSION: Int32 = 2
public const ROCKSDB_BZ2_COMPRESSION: Int32 = 3
public const ROCKSDB_LZ4_COMPRESSION: Int32 = 4
public const ROCKSDB_LZ4HC_COMPRESSION: Int32 = 5
public const ROCKSDB_XPRESS_COMPRESSION: Int32 = 6
public const ROCKSDB_ZSTD_COMPRESSION: Int32 = 7

foreign func rocksdb_options_create(): CPointer<rocksdb_options_t>

foreign func rocksdb_options_destroy(options: CPointer<rocksdb_options_t>): Unit

foreign func rocksdb_options_set_create_if_missing(options: CPointer<rocksdb_options_t>, value: UInt8): Unit

foreign func rocksdb_options_set_paranoid_checks(options: CPointer<rocksdb_options_t>, value: UInt8): Unit

foreign func rocksdb_options_set_write_buffer_size(options: CPointer<rocksdb_options_t>, size: UIntNative): Unit

foreign func rocksdb_options_set_db_write_buffer_size(options: CPointer<rocksdb_options_t>, size: UIntNative): Unit

foreign func rocksdb_options_set_max_open_files(options: CPointer<rocksdb_options_t>, value: Int32): Unit

foreign func rocksdb_options_set_max_write_buffer_number(options: CPointer<rocksdb_options_t>, value: Int32): Unit

foreign func rocksdb_options_set_min_write_buffer_number_to_merge(options: CPointer<rocksdb_options_t>, value: Int32): Unit

foreign func rocksdb_options_set_max_background_jobs(options: CPointer<rocksdb_options_t>, value: Int32): Unit

foreign func rocksdb_options_set_keep_log_file_num(options: CPointer<rocksdb_options_t>, value: UIntNative): Unit

foreign func rocksdb_options_set_use_fsync(options: CPointer<rocksdb_options_t>, value: UInt8): Unit

foreign func rocksdb_options_set_allow_mmap_reads(options: CPointer<rocksdb_options_t>, value: UInt8): Unit

foreign func rocksdb_options_set_bytes_per_sync(options: CPointer<rocksdb_options_t>, value: UInt64): Unit

foreign func rocksdb_options_set_compression(options: CPointer<rocksdb_options_t>, value: Int32): Unit

foreign func rocksdb_block_based_options_create(): CPointer<rocksdb_block_based_table_options_t>

foreign func rocksdb_block_based_options_destroy(options: CPointer<rocksdb_block_based_table_options_t>): Unit

foreign func rocksdb_block_based_options_set_no_block_cache(options: CPointer<rocksdb_block_based_table_options_t>,
    value: UInt8): Unit

foreign func rocksdb_block_based_options_set_block_cache(
    options: CPointer<rocksdb_block_based_table_options_t>,
    cache: CPointer<rocksdb_cache_t>
): Unit

foreign func rocksdb_block_based_options_set_cache_index_and_filter_blocks(
    options: CPointer<rocksdb_block_based_table_options_t>, value: UInt8): Unit

foreign func rocksdb_block_based_options_set_cache_index_and_filter_blocks_with_high_priority(
    options: CPointer<rocksdb_block_based_table_options_t>, value: UInt8): Unit

foreign func rocksdb_block_based_options_set_pin_l0_filter_and_index_blocks_in_cache(
    options: CPointer<rocksdb_block_based_table_options_t>, value: UInt8): Unit

foreign func rocksdb_block_based_options_set_pin_top_level_index_and_filter(
    options: CPointer<rocksdb_block_based_table_options_t>, value: UInt8): Unit

foreign func rocksdb_options_set_block_based_table_factory(options: CPointer<rocksdb_options_t>,
    tableOptions: CPointer<rocksdb_block_based_table_options_t>): Unit

foreign func rocksdb_cache_create_lru(capacity: UIntNative): CPointer<rocksdb_cache_t>

foreign func rocksdb_cache_destroy(cache: CPointer<rocksdb_cache_t>): Unit

foreign func rocksdb_open(options: CPointer<rocksdb_options_t>, name: CString, errptr: CPointer<CPointer<UInt8>>): CPointer<rocksdb_t>

foreign func rocksdb_open_column_families(
    options: CPointer<rocksdb_options_t>,
    name: CString,
    numColumnFamilies: Int32,
    columnFamilyNames: CPointer<CString>,
    columnFamilyOptions: CPointer<CPointer<rocksdb_options_t>>,
    columnFamilyHandles: CPointer<CPointer<rocksdb_column_family_handle_t>>,
    errptr: CPointer<CPointer<UInt8>>
): CPointer<rocksdb_t>

foreign func rocksdb_list_column_families(
    options: CPointer<rocksdb_options_t>,
    name: CString,
    length: CPointer<UIntNative>,
    errptr: CPointer<CPointer<UInt8>>
): CPointer<CString>

foreign func rocksdb_list_column_families_destroy(list: CPointer<CString>, length: UIntNative): Unit

foreign func rocksdb_create_column_family(
    db: CPointer<rocksdb_t>,
    options: CPointer<rocksdb_options_t>,
    name: CString,
    errptr: CPointer<CPointer<UInt8>>
): CPointer<rocksdb_column_family_handle_t>

foreign func rocksdb_drop_column_family(
    db: CPointer<rocksdb_t>,
    handle: CPointer<rocksdb_column_family_handle_t>,
    errptr: CPointer<CPointer<UInt8>>
): Unit

foreign func rocksdb_column_family_handle_destroy(handle: CPointer<rocksdb_column_family_handle_t>): Unit

foreign func rocksdb_close(db: CPointer<rocksdb_t>): Unit

foreign func rocksdb_optimistictransactiondb_open(
    options: CPointer<rocksdb_options_t>,
    name: CString,
    errptr: CPointer<CPointer<UInt8>>
): CPointer<rocksdb_optimistictransactiondb_t>

foreign func rocksdb_optimistictransactiondb_get_base_db(db: CPointer<rocksdb_optimistictransactiondb_t>): CPointer<rocksdb_t>

foreign func rocksdb_optimistictransactiondb_close_base_db(db: CPointer<rocksdb_t>): Unit

foreign func rocksdb_optimistictransactiondb_close(db: CPointer<rocksdb_optimistictransactiondb_t>): Unit

foreign func rocksdb_readoptions_create(): CPointer<rocksdb_readoptions_t>

foreign func rocksdb_readoptions_destroy(options: CPointer<rocksdb_readoptions_t>): Unit

foreign func rocksdb_readoptions_set_iterate_upper_bound(options: CPointer<rocksdb_readoptions_t>, key: CString,
    keylen: UIntNative): Unit

foreign func rocksdb_readoptions_set_prefix_same_as_start(options: CPointer<rocksdb_readoptions_t>, value: UInt8): Unit

foreign func rocksdb_readoptions_set_total_order_seek(options: CPointer<rocksdb_readoptions_t>, value: UInt8): Unit

foreign func rocksdb_readoptions_set_snapshot(
    options: CPointer<rocksdb_readoptions_t>,
    snapshot: CPointer<rocksdb_snapshot_t>
): Unit

foreign func rocksdb_readoptions_set_verify_checksums(options: CPointer<rocksdb_readoptions_t>, value: UInt8): Unit

foreign func rocksdb_readoptions_set_fill_cache(options: CPointer<rocksdb_readoptions_t>, value: UInt8): Unit

foreign func rocksdb_writeoptions_create(): CPointer<rocksdb_writeoptions_t>

foreign func rocksdb_writeoptions_destroy(options: CPointer<rocksdb_writeoptions_t>): Unit

foreign func rocksdb_writeoptions_set_sync(options: CPointer<rocksdb_writeoptions_t>, value: UInt8): Unit

foreign func rocksdb_transaction_options_create(): CPointer<rocksdb_transaction_options_t>

foreign func rocksdb_transaction_options_destroy(options: CPointer<rocksdb_transaction_options_t>): Unit

foreign func rocksdb_transaction_options_set_set_snapshot(options: CPointer<rocksdb_transaction_options_t>, value: UInt8): Unit

foreign func rocksdb_optimistictransaction_options_create(): CPointer<rocksdb_optimistictransaction_options_t>

foreign func rocksdb_optimistictransaction_options_destroy(options: CPointer<rocksdb_optimistictransaction_options_t>): Unit

foreign func rocksdb_optimistictransaction_options_set_set_snapshot(
    options: CPointer<rocksdb_optimistictransaction_options_t>,
    value: UInt8
): Unit

foreign func rocksdb_optimistictransaction_begin(
    db: CPointer<rocksdb_optimistictransactiondb_t>,
    write_options: CPointer<rocksdb_writeoptions_t>,
    txn_options: CPointer<rocksdb_optimistictransaction_options_t>,
    old_txn: CPointer<rocksdb_transaction_t>
): CPointer<rocksdb_transaction_t>

foreign func rocksdb_transaction_destroy(txn: CPointer<rocksdb_transaction_t>): Unit

// 编译期版本探测（native/lanlu_rocksdb_bridge.c 读取 rocksdb/version.h 的宏）：
// 供运行时校验 C API 编译期 major，探测头文件/库版本差异（对齐 libavformat 模式）。
foreign func llrocksdb_compiled_major(): Int32
foreign func llrocksdb_compiled_minor(): Int32

foreign func rocksdb_transaction_commit(txn: CPointer<rocksdb_transaction_t>, errptr: CPointer<CPointer<UInt8>>): Unit

foreign func rocksdb_transaction_rollback(txn: CPointer<rocksdb_transaction_t>, errptr: CPointer<CPointer<UInt8>>): Unit

foreign func rocksdb_transaction_get(
    txn: CPointer<rocksdb_transaction_t>,
    options: CPointer<rocksdb_readoptions_t>,
    key: CString,
    keylen: UIntNative,
    vallen: CPointer<UIntNative>,
    errptr: CPointer<CPointer<UInt8>>
): CPointer<UInt8>

foreign func rocksdb_transaction_get_cf(
    txn: CPointer<rocksdb_transaction_t>,
    options: CPointer<rocksdb_readoptions_t>,
    column_family: CPointer<rocksdb_column_family_handle_t>,
    key: CString,
    keylen: UIntNative,
    vallen: CPointer<UIntNative>,
    errptr: CPointer<CPointer<UInt8>>
): CPointer<UInt8>

foreign func rocksdb_transaction_multi_get(
    txn: CPointer<rocksdb_transaction_t>,
    options: CPointer<rocksdb_readoptions_t>,
    numKeys: UIntNative,
    keysList: CPointer<CString>,
    keyListSizes: CPointer<UIntNative>,
    valuesList: CPointer<CPointer<UInt8>>,
    valueListSizes: CPointer<UIntNative>,
    errs: CPointer<CPointer<UInt8>>
): Unit

foreign func rocksdb_transaction_put(
    txn: CPointer<rocksdb_transaction_t>,
    key: CString,
    keylen: UIntNative,
    value: CString,
    vallen: UIntNative,
    errptr: CPointer<CPointer<UInt8>>
): Unit

foreign func rocksdb_transaction_put_cf(
    txn: CPointer<rocksdb_transaction_t>,
    column_family: CPointer<rocksdb_column_family_handle_t>,
    key: CString,
    keylen: UIntNative,
    value: CString,
    vallen: UIntNative,
    errptr: CPointer<CPointer<UInt8>>
): Unit

foreign func rocksdb_transaction_delete_cf(
    txn: CPointer<rocksdb_transaction_t>,
    column_family: CPointer<rocksdb_column_family_handle_t>,
    key: CString,
    keylen: UIntNative,
    errptr: CPointer<CPointer<UInt8>>
): Unit

foreign func rocksdb_transaction_delete(
    txn: CPointer<rocksdb_transaction_t>,
    key: CString,
    keylen: UIntNative,
    errptr: CPointer<CPointer<UInt8>>
): Unit

foreign func rocksdb_create_iterator(
    db: CPointer<rocksdb_t>,
    options: CPointer<rocksdb_readoptions_t>
): CPointer<rocksdb_iterator_t>

foreign func rocksdb_create_iterator_cf(
    db: CPointer<rocksdb_t>,
    options: CPointer<rocksdb_readoptions_t>,
    columnFamily: CPointer<rocksdb_column_family_handle_t>
): CPointer<rocksdb_iterator_t>

foreign func rocksdb_create_snapshot(db: CPointer<rocksdb_t>): CPointer<rocksdb_snapshot_t>

foreign func rocksdb_release_snapshot(db: CPointer<rocksdb_t>, snapshot: CPointer<rocksdb_snapshot_t>): Unit

// RocksDB 9.0 起才有 rocksdb_snapshot_get_sequence_number；经 bridge 转发，
// 老库（如 Ubuntu 24.04 的 8.9.x）由 bridge 返回 0，避免直接引用符号链接失败。
foreign func llrocksdb_snapshot_get_sequence_number(snapshot: CPointer<rocksdb_snapshot_t>): UInt64

foreign func rocksdb_iter_destroy(iter: CPointer<rocksdb_iterator_t>): Unit

foreign func rocksdb_iter_valid(iter: CPointer<rocksdb_iterator_t>): UInt8

foreign func rocksdb_iter_seek_to_first(iter: CPointer<rocksdb_iterator_t>): Unit

foreign func rocksdb_iter_seek_to_last(iter: CPointer<rocksdb_iterator_t>): Unit

foreign func rocksdb_iter_seek(iter: CPointer<rocksdb_iterator_t>, key: CString, klen: UIntNative): Unit

foreign func rocksdb_iter_seek_for_prev(iter: CPointer<rocksdb_iterator_t>, key: CString, klen: UIntNative): Unit

foreign func rocksdb_iter_next(iter: CPointer<rocksdb_iterator_t>): Unit

foreign func rocksdb_iter_prev(iter: CPointer<rocksdb_iterator_t>): Unit

foreign func rocksdb_iter_key(
    iter: CPointer<rocksdb_iterator_t>,
    klen: CPointer<UIntNative>
): CPointer<UInt8>

foreign func rocksdb_iter_value(
    iter: CPointer<rocksdb_iterator_t>,
    vlen: CPointer<UIntNative>
): CPointer<UInt8>

foreign func rocksdb_iter_get_error(iter: CPointer<rocksdb_iterator_t>, errptr: CPointer<CPointer<UInt8>>): Unit

foreign func rocksdb_get(
    db: CPointer<rocksdb_t>,
    options: CPointer<rocksdb_readoptions_t>,
    key: CString,
    keylen: UIntNative,
    vallen: CPointer<UIntNative>,
    errptr: CPointer<CPointer<UInt8>>
): CPointer<UInt8>

foreign func rocksdb_get_cf(
    db: CPointer<rocksdb_t>,
    options: CPointer<rocksdb_readoptions_t>,
    columnFamily: CPointer<rocksdb_column_family_handle_t>,
    key: CString,
    keylen: UIntNative,
    vallen: CPointer<UIntNative>,
    errptr: CPointer<CPointer<UInt8>>
): CPointer<UInt8>

foreign func rocksdb_multi_get(
    db: CPointer<rocksdb_t>,
    options: CPointer<rocksdb_readoptions_t>,
    numKeys: UIntNative,
    keysList: CPointer<CString>,
    keyListSizes: CPointer<UIntNative>,
    valuesList: CPointer<CPointer<UInt8>>,
    valueListSizes: CPointer<UIntNative>,
    errs: CPointer<CPointer<UInt8>>
): Unit

foreign func rocksdb_put(
    db: CPointer<rocksdb_t>,
    options: CPointer<rocksdb_writeoptions_t>,
    key: CString,
    keylen: UIntNative,
    value: CString,
    vallen: UIntNative,
    errptr: CPointer<CPointer<UInt8>>
): Unit

foreign func rocksdb_put_cf(
    db: CPointer<rocksdb_t>,
    options: CPointer<rocksdb_writeoptions_t>,
    columnFamily: CPointer<rocksdb_column_family_handle_t>,
    key: CString,
    keylen: UIntNative,
    value: CString,
    vallen: UIntNative,
    errptr: CPointer<CPointer<UInt8>>
): Unit

foreign func rocksdb_delete(
    db: CPointer<rocksdb_t>,
    options: CPointer<rocksdb_writeoptions_t>,
    key: CString,
    keylen: UIntNative,
    errptr: CPointer<CPointer<UInt8>>
): Unit

foreign func rocksdb_delete_cf(
    db: CPointer<rocksdb_t>,
    options: CPointer<rocksdb_writeoptions_t>,
    columnFamily: CPointer<rocksdb_column_family_handle_t>,
    key: CString,
    keylen: UIntNative,
    errptr: CPointer<CPointer<UInt8>>
): Unit

foreign func rocksdb_merge(
    db: CPointer<rocksdb_t>,
    options: CPointer<rocksdb_writeoptions_t>,
    key: CString,
    keylen: UIntNative,
    value: CString,
    vallen: UIntNative,
    errptr: CPointer<CPointer<UInt8>>
): Unit

foreign func rocksdb_write(
    db: CPointer<rocksdb_t>,
    options: CPointer<rocksdb_writeoptions_t>,
    batch: CPointer<rocksdb_writebatch_t>,
    errptr: CPointer<CPointer<UInt8>>
): Unit

foreign func rocksdb_writebatch_create(): CPointer<rocksdb_writebatch_t>

foreign func rocksdb_writebatch_destroy(batch: CPointer<rocksdb_writebatch_t>): Unit

foreign func rocksdb_writebatch_put(batch: CPointer<rocksdb_writebatch_t>, key: CString, klen: UIntNative,
    value: CString, vlen: UIntNative): Unit

foreign func rocksdb_writebatch_put_cf(
    batch: CPointer<rocksdb_writebatch_t>,
    columnFamily: CPointer<rocksdb_column_family_handle_t>,
    key: CString,
    klen: UIntNative,
    value: CString,
    vlen: UIntNative
): Unit

foreign func rocksdb_writebatch_merge(batch: CPointer<rocksdb_writebatch_t>, key: CString, klen: UIntNative,
    value: CString, vlen: UIntNative): Unit

foreign func rocksdb_writebatch_delete(batch: CPointer<rocksdb_writebatch_t>, key: CString, klen: UIntNative): Unit

foreign func rocksdb_writebatch_delete_cf(
    batch: CPointer<rocksdb_writebatch_t>,
    columnFamily: CPointer<rocksdb_column_family_handle_t>,
    key: CString,
    klen: UIntNative
): Unit

foreign func rocksdb_writebatch_delete_range(
    batch: CPointer<rocksdb_writebatch_t>,
    startKey: CString,
    startKeyLen: UIntNative,
    endKey: CString,
    endKeyLen: UIntNative
): Unit

foreign func rocksdb_writebatch_delete_range_cf(
    batch: CPointer<rocksdb_writebatch_t>,
    columnFamily: CPointer<rocksdb_column_family_handle_t>,
    startKey: CString,
    startKeyLen: UIntNative,
    endKey: CString,
    endKeyLen: UIntNative
): Unit

foreign func rocksdb_flushoptions_create(): CPointer<rocksdb_flushoptions_t>

foreign func rocksdb_flushoptions_destroy(options: CPointer<rocksdb_flushoptions_t>): Unit

foreign func rocksdb_flushoptions_set_wait(options: CPointer<rocksdb_flushoptions_t>, value: UInt8): Unit

foreign func rocksdb_flush(db: CPointer<rocksdb_t>, options: CPointer<rocksdb_flushoptions_t>,
    errptr: CPointer<CPointer<UInt8>>): Unit

foreign func rocksdb_flush_cf(db: CPointer<rocksdb_t>, options: CPointer<rocksdb_flushoptions_t>,
    columnFamily: CPointer<rocksdb_column_family_handle_t>, errptr: CPointer<CPointer<UInt8>>): Unit

foreign func rocksdb_compact_range(db: CPointer<rocksdb_t>, startKey: CString, startKeyLen: UIntNative, endKey: CString,
    endKeyLen: UIntNative): Unit

foreign func rocksdb_compact_range_cf(db: CPointer<rocksdb_t>, columnFamily: CPointer<rocksdb_column_family_handle_t>,
    startKey: CString, startKeyLen: UIntNative, endKey: CString, endKeyLen: UIntNative): Unit

foreign func rocksdb_property_int(db: CPointer<rocksdb_t>, name: CString, value: CPointer<UInt64>): Int32

foreign func rocksdb_property_value(db: CPointer<rocksdb_t>, name: CString): CPointer<UInt8>

foreign func rocksdb_property_int_cf(db: CPointer<rocksdb_t>, columnFamily: CPointer<rocksdb_column_family_handle_t>,
    name: CString, value: CPointer<UInt64>): Int32

foreign func rocksdb_property_value_cf(db: CPointer<rocksdb_t>, columnFamily: CPointer<rocksdb_column_family_handle_t>,
    name: CString): CPointer<UInt8>

foreign func rocksdb_approximate_sizes(db: CPointer<rocksdb_t>, rangeCount: Int32, startKeys: CPointer<CString>,
    startKeyLengths: CPointer<UIntNative>, endKeys: CPointer<CString>, endKeyLengths: CPointer<UIntNative>,
    sizes: CPointer<UInt64>, errptr: CPointer<CPointer<UInt8>>): Unit

foreign func rocksdb_approximate_sizes_cf(db: CPointer<rocksdb_t>,
    columnFamily: CPointer<rocksdb_column_family_handle_t>, rangeCount: Int32, startKeys: CPointer<CString>,
    startKeyLengths: CPointer<UIntNative>, endKeys: CPointer<CString>, endKeyLengths: CPointer<UIntNative>,
    sizes: CPointer<UInt64>, errptr: CPointer<CPointer<UInt8>>): Unit

foreign func rocksdb_get_latest_sequence_number(db: CPointer<rocksdb_t>): UInt64

foreign func rocksdb_free(ptr: CPointer<Unit>): Unit
