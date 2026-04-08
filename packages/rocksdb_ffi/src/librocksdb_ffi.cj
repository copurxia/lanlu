package rocksdb_ffi

@C
public struct rocksdb_t {
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

public const ROCKSDB_NO_COMPRESSION: Int32 = 0

foreign func rocksdb_options_create(): CPointer<rocksdb_options_t>
foreign func rocksdb_options_destroy(options: CPointer<rocksdb_options_t>): Unit
foreign func rocksdb_options_set_create_if_missing(options: CPointer<rocksdb_options_t>, value: UInt8): Unit
foreign func rocksdb_options_set_paranoid_checks(options: CPointer<rocksdb_options_t>, value: UInt8): Unit
foreign func rocksdb_options_set_write_buffer_size(options: CPointer<rocksdb_options_t>, size: UIntNative): Unit
foreign func rocksdb_options_set_db_write_buffer_size(options: CPointer<rocksdb_options_t>, size: UIntNative): Unit
foreign func rocksdb_options_set_max_open_files(options: CPointer<rocksdb_options_t>, value: Int32): Unit
foreign func rocksdb_options_set_max_write_buffer_number(options: CPointer<rocksdb_options_t>, value: Int32): Unit
foreign func rocksdb_options_set_min_write_buffer_number_to_merge(options: CPointer<rocksdb_options_t>, value: Int32): Unit
foreign func rocksdb_options_set_max_write_buffer_number_to_maintain(options: CPointer<rocksdb_options_t>, value: Int32): Unit
foreign func rocksdb_options_set_max_background_jobs(options: CPointer<rocksdb_options_t>, value: Int32): Unit
foreign func rocksdb_options_set_keep_log_file_num(options: CPointer<rocksdb_options_t>, value: UIntNative): Unit
foreign func rocksdb_options_set_use_fsync(options: CPointer<rocksdb_options_t>, value: UInt8): Unit
foreign func rocksdb_options_set_allow_mmap_reads(options: CPointer<rocksdb_options_t>, value: UInt8): Unit
foreign func rocksdb_options_set_bytes_per_sync(options: CPointer<rocksdb_options_t>, value: UInt64): Unit
foreign func rocksdb_options_set_compression(options: CPointer<rocksdb_options_t>, value: Int32): Unit

foreign func rocksdb_block_based_options_create(): CPointer<rocksdb_block_based_table_options_t>
foreign func rocksdb_block_based_options_destroy(options: CPointer<rocksdb_block_based_table_options_t>): Unit
foreign func rocksdb_block_based_options_set_no_block_cache(options: CPointer<rocksdb_block_based_table_options_t>, value: UInt8): Unit
foreign func rocksdb_block_based_options_set_block_cache(
    options: CPointer<rocksdb_block_based_table_options_t>,
    cache: CPointer<rocksdb_cache_t>
): Unit
foreign func rocksdb_block_based_options_set_cache_index_and_filter_blocks(options: CPointer<rocksdb_block_based_table_options_t>, value: UInt8): Unit
foreign func rocksdb_block_based_options_set_cache_index_and_filter_blocks_with_high_priority(options: CPointer<rocksdb_block_based_table_options_t>, value: UInt8): Unit
foreign func rocksdb_block_based_options_set_pin_l0_filter_and_index_blocks_in_cache(options: CPointer<rocksdb_block_based_table_options_t>, value: UInt8): Unit
foreign func rocksdb_block_based_options_set_pin_top_level_index_and_filter(options: CPointer<rocksdb_block_based_table_options_t>, value: UInt8): Unit
foreign func rocksdb_options_set_block_based_table_factory(options: CPointer<rocksdb_options_t>, tableOptions: CPointer<rocksdb_block_based_table_options_t>): Unit
foreign func rocksdb_cache_create_lru(capacity: UIntNative): CPointer<rocksdb_cache_t>
foreign func rocksdb_cache_destroy(cache: CPointer<rocksdb_cache_t>): Unit

foreign func rocksdb_open(options: CPointer<rocksdb_options_t>, name: CString, errptr: CPointer<CPointer<UInt8>>): CPointer<rocksdb_t>
foreign func rocksdb_close(db: CPointer<rocksdb_t>): Unit

foreign func rocksdb_readoptions_create(): CPointer<rocksdb_readoptions_t>
foreign func rocksdb_readoptions_destroy(options: CPointer<rocksdb_readoptions_t>): Unit
foreign func rocksdb_readoptions_set_iterate_upper_bound(options: CPointer<rocksdb_readoptions_t>, key: CString, keylen: UIntNative): Unit
foreign func rocksdb_readoptions_set_prefix_same_as_start(options: CPointer<rocksdb_readoptions_t>, value: UInt8): Unit
foreign func rocksdb_readoptions_set_total_order_seek(options: CPointer<rocksdb_readoptions_t>, value: UInt8): Unit
foreign func rocksdb_writeoptions_create(): CPointer<rocksdb_writeoptions_t>
foreign func rocksdb_writeoptions_destroy(options: CPointer<rocksdb_writeoptions_t>): Unit
foreign func rocksdb_writeoptions_set_sync(options: CPointer<rocksdb_writeoptions_t>, value: UInt8): Unit

foreign func rocksdb_create_iterator(
    db: CPointer<rocksdb_t>,
    options: CPointer<rocksdb_readoptions_t>
): CPointer<rocksdb_iterator_t>

foreign func rocksdb_iter_destroy(iter: CPointer<rocksdb_iterator_t>): Unit
foreign func rocksdb_iter_valid(iter: CPointer<rocksdb_iterator_t>): UInt8
foreign func rocksdb_iter_seek(iter: CPointer<rocksdb_iterator_t>, key: CString, klen: UIntNative): Unit
foreign func rocksdb_iter_next(iter: CPointer<rocksdb_iterator_t>): Unit
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

foreign func rocksdb_delete(
    db: CPointer<rocksdb_t>,
    options: CPointer<rocksdb_writeoptions_t>,
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
foreign func rocksdb_writebatch_put(batch: CPointer<rocksdb_writebatch_t>, key: CString, klen: UIntNative, value: CString, vlen: UIntNative): Unit
foreign func rocksdb_writebatch_merge(batch: CPointer<rocksdb_writebatch_t>, key: CString, klen: UIntNative, value: CString, vlen: UIntNative): Unit
foreign func rocksdb_writebatch_delete(batch: CPointer<rocksdb_writebatch_t>, key: CString, klen: UIntNative): Unit
foreign func rocksdb_writebatch_delete_range(
    batch: CPointer<rocksdb_writebatch_t>,
    startKey: CString,
    startKeyLen: UIntNative,
    endKey: CString,
    endKeyLen: UIntNative
): Unit

foreign func rocksdb_free(ptr: CPointer<Unit>): Unit
