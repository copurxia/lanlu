// cjbind 0.2.3 生成，请勿编辑, DO NOT EDIT

package archive_ffi

public const ARCHIVE_VERSION_NUMBER: Int64 = 3008001
public const ARCHIVE_EOF: Int64 = 1
public const ARCHIVE_OK: Int64 = 0
public const ARCHIVE_RETRY: Int64 = -10
public const ARCHIVE_WARN: Int64 = -20
public const ARCHIVE_FAILED: Int64 = -25
public const ARCHIVE_FATAL: Int64 = -30
public const ARCHIVE_FILTER_NONE: Int64 = 0
public const ARCHIVE_FILTER_GZIP: Int64 = 1
public const ARCHIVE_FILTER_BZIP2: Int64 = 2
public const ARCHIVE_FILTER_COMPRESS: Int64 = 3
public const ARCHIVE_FILTER_PROGRAM: Int64 = 4
public const ARCHIVE_FILTER_LZMA: Int64 = 5
public const ARCHIVE_FILTER_XZ: Int64 = 6
public const ARCHIVE_FILTER_UU: Int64 = 7
public const ARCHIVE_FILTER_RPM: Int64 = 8
public const ARCHIVE_FILTER_LZIP: Int64 = 9
public const ARCHIVE_FILTER_LRZIP: Int64 = 10
public const ARCHIVE_FILTER_LZOP: Int64 = 11
public const ARCHIVE_FILTER_GRZIP: Int64 = 12
public const ARCHIVE_FILTER_LZ4: Int64 = 13
public const ARCHIVE_FILTER_ZSTD: Int64 = 14
public const ARCHIVE_COMPRESSION_NONE: Int64 = 0
public const ARCHIVE_COMPRESSION_GZIP: Int64 = 1
public const ARCHIVE_COMPRESSION_BZIP2: Int64 = 2
public const ARCHIVE_COMPRESSION_COMPRESS: Int64 = 3
public const ARCHIVE_COMPRESSION_PROGRAM: Int64 = 4
public const ARCHIVE_COMPRESSION_LZMA: Int64 = 5
public const ARCHIVE_COMPRESSION_XZ: Int64 = 6
public const ARCHIVE_COMPRESSION_UU: Int64 = 7
public const ARCHIVE_COMPRESSION_RPM: Int64 = 8
public const ARCHIVE_COMPRESSION_LZIP: Int64 = 9
public const ARCHIVE_COMPRESSION_LRZIP: Int64 = 10
public const ARCHIVE_FORMAT_BASE_MASK: Int64 = 16711680
public const ARCHIVE_FORMAT_CPIO: Int64 = 65536
public const ARCHIVE_FORMAT_CPIO_POSIX: Int64 = 65537
public const ARCHIVE_FORMAT_CPIO_BIN_LE: Int64 = 65538
public const ARCHIVE_FORMAT_CPIO_BIN_BE: Int64 = 65539
public const ARCHIVE_FORMAT_CPIO_SVR4_NOCRC: Int64 = 65540
public const ARCHIVE_FORMAT_CPIO_SVR4_CRC: Int64 = 65541
public const ARCHIVE_FORMAT_CPIO_AFIO_LARGE: Int64 = 65542
public const ARCHIVE_FORMAT_CPIO_PWB: Int64 = 65543
public const ARCHIVE_FORMAT_SHAR: Int64 = 131072
public const ARCHIVE_FORMAT_SHAR_BASE: Int64 = 131073
public const ARCHIVE_FORMAT_SHAR_DUMP: Int64 = 131074
public const ARCHIVE_FORMAT_TAR: Int64 = 196608
public const ARCHIVE_FORMAT_TAR_USTAR: Int64 = 196609
public const ARCHIVE_FORMAT_TAR_PAX_INTERCHANGE: Int64 = 196610
public const ARCHIVE_FORMAT_TAR_PAX_RESTRICTED: Int64 = 196611
public const ARCHIVE_FORMAT_TAR_GNUTAR: Int64 = 196612
public const ARCHIVE_FORMAT_ISO9660: Int64 = 262144
public const ARCHIVE_FORMAT_ISO9660_ROCKRIDGE: Int64 = 262145
public const ARCHIVE_FORMAT_ZIP: Int64 = 327680
public const ARCHIVE_FORMAT_EMPTY: Int64 = 393216
public const ARCHIVE_FORMAT_AR: Int64 = 458752
public const ARCHIVE_FORMAT_AR_GNU: Int64 = 458753
public const ARCHIVE_FORMAT_AR_BSD: Int64 = 458754
public const ARCHIVE_FORMAT_MTREE: Int64 = 524288
public const ARCHIVE_FORMAT_RAW: Int64 = 589824
public const ARCHIVE_FORMAT_XAR: Int64 = 655360
public const ARCHIVE_FORMAT_LHA: Int64 = 720896
public const ARCHIVE_FORMAT_CAB: Int64 = 786432
public const ARCHIVE_FORMAT_RAR: Int64 = 851968
public const ARCHIVE_FORMAT_7ZIP: Int64 = 917504
public const ARCHIVE_FORMAT_WARC: Int64 = 983040
public const ARCHIVE_FORMAT_RAR_V5: Int64 = 1048576
public const ARCHIVE_READ_FORMAT_CAPS_NONE: Int64 = 0
public const ARCHIVE_READ_FORMAT_CAPS_ENCRYPT_DATA: Int64 = 1
public const ARCHIVE_READ_FORMAT_CAPS_ENCRYPT_METADATA: Int64 = 2
public const ARCHIVE_READ_FORMAT_ENCRYPTION_UNSUPPORTED: Int64 = -2
public const ARCHIVE_READ_FORMAT_ENCRYPTION_DONT_KNOW: Int64 = -1
public const ARCHIVE_EXTRACT_OWNER: Int64 = 1
public const ARCHIVE_EXTRACT_PERM: Int64 = 2
public const ARCHIVE_EXTRACT_TIME: Int64 = 4
public const ARCHIVE_EXTRACT_NO_OVERWRITE: Int64 = 8
public const ARCHIVE_EXTRACT_UNLINK: Int64 = 16
public const ARCHIVE_EXTRACT_ACL: Int64 = 32
public const ARCHIVE_EXTRACT_FFLAGS: Int64 = 64
public const ARCHIVE_EXTRACT_XATTR: Int64 = 128
public const ARCHIVE_EXTRACT_SECURE_SYMLINKS: Int64 = 256
public const ARCHIVE_EXTRACT_SECURE_NODOTDOT: Int64 = 512
public const ARCHIVE_EXTRACT_NO_AUTODIR: Int64 = 1024
public const ARCHIVE_EXTRACT_NO_OVERWRITE_NEWER: Int64 = 2048
public const ARCHIVE_EXTRACT_SPARSE: Int64 = 4096
public const ARCHIVE_EXTRACT_MAC_METADATA: Int64 = 8192
public const ARCHIVE_EXTRACT_NO_HFS_COMPRESSION: Int64 = 16384
public const ARCHIVE_EXTRACT_HFS_COMPRESSION_FORCED: Int64 = 32768
public const ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS: Int64 = 65536
public const ARCHIVE_EXTRACT_CLEAR_NOCHANGE_FFLAGS: Int64 = 131072
public const ARCHIVE_EXTRACT_SAFE_WRITES: Int64 = 262144
public const ARCHIVE_READDISK_RESTORE_ATIME: Int64 = 1
public const ARCHIVE_READDISK_HONOR_NODUMP: Int64 = 2
public const ARCHIVE_READDISK_MAC_COPYFILE: Int64 = 4
public const ARCHIVE_READDISK_NO_TRAVERSE_MOUNTS: Int64 = 8
public const ARCHIVE_READDISK_NO_XATTR: Int64 = 16
public const ARCHIVE_READDISK_NO_ACL: Int64 = 32
public const ARCHIVE_READDISK_NO_FFLAGS: Int64 = 64
public const ARCHIVE_READDISK_NO_SPARSE: Int64 = 128
public const ARCHIVE_MATCH_MTIME: Int64 = 256
public const ARCHIVE_MATCH_CTIME: Int64 = 512
public const ARCHIVE_MATCH_NEWER: Int64 = 1
public const ARCHIVE_MATCH_OLDER: Int64 = 2
public const ARCHIVE_MATCH_EQUAL: Int64 = 16
public const AE_IFMT: UInt32 = 61440
public const AE_IFREG: UInt32 = 32768
public const AE_IFLNK: UInt32 = 40960
public const AE_IFSOCK: UInt32 = 49152
public const AE_IFCHR: UInt32 = 8192
public const AE_IFBLK: UInt32 = 24576
public const AE_IFDIR: UInt32 = 16384
public const AE_IFIFO: UInt32 = 4096
public const AE_SYMLINK_TYPE_UNDEFINED: UInt32 = 0
public const AE_SYMLINK_TYPE_FILE: UInt32 = 1
public const AE_SYMLINK_TYPE_DIRECTORY: UInt32 = 2
public const ARCHIVE_ENTRY_DIGEST_MD5: Int64 = 1
public const ARCHIVE_ENTRY_DIGEST_RMD160: Int64 = 2
public const ARCHIVE_ENTRY_DIGEST_SHA1: Int64 = 3
public const ARCHIVE_ENTRY_DIGEST_SHA256: Int64 = 4
public const ARCHIVE_ENTRY_DIGEST_SHA384: Int64 = 5
public const ARCHIVE_ENTRY_DIGEST_SHA512: Int64 = 6
public const ARCHIVE_ENTRY_ACL_EXECUTE: Int64 = 1
public const ARCHIVE_ENTRY_ACL_WRITE: Int64 = 2
public const ARCHIVE_ENTRY_ACL_READ: Int64 = 4
public const ARCHIVE_ENTRY_ACL_READ_DATA: Int64 = 8
public const ARCHIVE_ENTRY_ACL_LIST_DIRECTORY: Int64 = 8
public const ARCHIVE_ENTRY_ACL_WRITE_DATA: Int64 = 16
public const ARCHIVE_ENTRY_ACL_ADD_FILE: Int64 = 16
public const ARCHIVE_ENTRY_ACL_APPEND_DATA: Int64 = 32
public const ARCHIVE_ENTRY_ACL_ADD_SUBDIRECTORY: Int64 = 32
public const ARCHIVE_ENTRY_ACL_READ_NAMED_ATTRS: Int64 = 64
public const ARCHIVE_ENTRY_ACL_WRITE_NAMED_ATTRS: Int64 = 128
public const ARCHIVE_ENTRY_ACL_DELETE_CHILD: Int64 = 256
public const ARCHIVE_ENTRY_ACL_READ_ATTRIBUTES: Int64 = 512
public const ARCHIVE_ENTRY_ACL_WRITE_ATTRIBUTES: Int64 = 1024
public const ARCHIVE_ENTRY_ACL_DELETE: Int64 = 2048
public const ARCHIVE_ENTRY_ACL_READ_ACL: Int64 = 4096
public const ARCHIVE_ENTRY_ACL_WRITE_ACL: Int64 = 8192
public const ARCHIVE_ENTRY_ACL_WRITE_OWNER: Int64 = 16384
public const ARCHIVE_ENTRY_ACL_SYNCHRONIZE: Int64 = 32768
public const ARCHIVE_ENTRY_ACL_PERMS_POSIX1E: Int64 = 7
public const ARCHIVE_ENTRY_ACL_PERMS_NFS4: Int64 = 65529
public const ARCHIVE_ENTRY_ACL_ENTRY_INHERITED: Int64 = 16777216
public const ARCHIVE_ENTRY_ACL_ENTRY_FILE_INHERIT: Int64 = 33554432
public const ARCHIVE_ENTRY_ACL_ENTRY_DIRECTORY_INHERIT: Int64 = 67108864
public const ARCHIVE_ENTRY_ACL_ENTRY_NO_PROPAGATE_INHERIT: Int64 = 134217728
public const ARCHIVE_ENTRY_ACL_ENTRY_INHERIT_ONLY: Int64 = 268435456
public const ARCHIVE_ENTRY_ACL_ENTRY_SUCCESSFUL_ACCESS: Int64 = 536870912
public const ARCHIVE_ENTRY_ACL_ENTRY_FAILED_ACCESS: Int64 = 1073741824
public const ARCHIVE_ENTRY_ACL_INHERITANCE_NFS4: Int64 = 2130706432
public const ARCHIVE_ENTRY_ACL_TYPE_ACCESS: Int64 = 256
public const ARCHIVE_ENTRY_ACL_TYPE_DEFAULT: Int64 = 512
public const ARCHIVE_ENTRY_ACL_TYPE_ALLOW: Int64 = 1024
public const ARCHIVE_ENTRY_ACL_TYPE_DENY: Int64 = 2048
public const ARCHIVE_ENTRY_ACL_TYPE_AUDIT: Int64 = 4096
public const ARCHIVE_ENTRY_ACL_TYPE_ALARM: Int64 = 8192
public const ARCHIVE_ENTRY_ACL_TYPE_POSIX1E: Int64 = 768
public const ARCHIVE_ENTRY_ACL_TYPE_NFS4: Int64 = 15360
public const ARCHIVE_ENTRY_ACL_USER: Int64 = 10001
public const ARCHIVE_ENTRY_ACL_USER_OBJ: Int64 = 10002
public const ARCHIVE_ENTRY_ACL_GROUP: Int64 = 10003
public const ARCHIVE_ENTRY_ACL_GROUP_OBJ: Int64 = 10004
public const ARCHIVE_ENTRY_ACL_MASK: Int64 = 10005
public const ARCHIVE_ENTRY_ACL_OTHER: Int64 = 10006
public const ARCHIVE_ENTRY_ACL_EVERYONE: Int64 = 10107
public const ARCHIVE_ENTRY_ACL_STYLE_EXTRA_ID: Int64 = 1
public const ARCHIVE_ENTRY_ACL_STYLE_MARK_DEFAULT: Int64 = 2
public const ARCHIVE_ENTRY_ACL_STYLE_SOLARIS: Int64 = 4
public const ARCHIVE_ENTRY_ACL_STYLE_SEPARATOR_COMMA: Int64 = 8
public const ARCHIVE_ENTRY_ACL_STYLE_COMPACT: Int64 = 16
public const OLD_ARCHIVE_ENTRY_ACL_STYLE_EXTRA_ID: Int64 = 1024
public const OLD_ARCHIVE_ENTRY_ACL_STYLE_MARK_DEFAULT: Int64 = 2048

public type la_int64_t = Int64

public type la_uint64_t = UInt64

public type la_ssize_t = IntNative

foreign func archive_version_number(): Int32

foreign func archive_version_string(): CString

foreign func archive_version_details(): CString

foreign func archive_zlib_version(): CString

foreign func archive_liblzma_version(): CString

foreign func archive_bzlib_version(): CString

foreign func archive_liblz4_version(): CString

foreign func archive_libzstd_version(): CString

foreign func archive_liblzo2_version(): CString

foreign func archive_libexpat_version(): CString

foreign func archive_libbsdxml_version(): CString

foreign func archive_libxml2_version(): CString

foreign func archive_mbedtls_version(): CString

foreign func archive_nettle_version(): CString

foreign func archive_openssl_version(): CString

foreign func archive_libmd_version(): CString

foreign func archive_commoncrypto_version(): CString

foreign func archive_cng_version(): CString

foreign func archive_wincrypt_version(): CString

foreign func archive_librichacl_version(): CString

foreign func archive_libacl_version(): CString

foreign func archive_libattr_version(): CString

foreign func archive_libiconv_version(): CString

foreign func archive_libpcre_version(): CString

foreign func archive_libpcre2_version(): CString

@C
public struct archive {
    init() {
        throw Exception("type should not be inited")
    }
}

@C
public struct archive_entry {
    init() {
        throw Exception("type should not be inited")
    }
}

public type archive_read_callback = CFunc<(arg1: CPointer<archive>, _client_data: CPointer<Unit>, _buffer: CPointer<CPointer<Unit>>) -> la_ssize_t>

public type archive_skip_callback = CFunc<(arg1: CPointer<archive>, _client_data: CPointer<Unit>, request: la_int64_t) -> la_int64_t>

public type archive_seek_callback = CFunc<(arg1: CPointer<archive>, _client_data: CPointer<Unit>, offset: la_int64_t,
    whence: Int32) -> la_int64_t>

public type archive_write_callback = CFunc<(arg1: CPointer<archive>, _client_data: CPointer<Unit>, _buffer: CPointer<Unit>,
    _length: UIntNative) -> la_ssize_t>

public type archive_open_callback = CFunc<(arg1: CPointer<archive>, _client_data: CPointer<Unit>) -> Int32>

public type archive_close_callback = CFunc<(arg1: CPointer<archive>, _client_data: CPointer<Unit>) -> Int32>

public type archive_free_callback = CFunc<(arg1: CPointer<archive>, _client_data: CPointer<Unit>) -> Int32>

public type archive_switch_callback = CFunc<(arg1: CPointer<archive>, _client_data1: CPointer<Unit>, _client_data2: CPointer<Unit>) -> Int32>

public type archive_passphrase_callback = CFunc<(arg1: CPointer<archive>, _client_data: CPointer<Unit>) -> CString>

foreign func archive_read_new(): CPointer<archive>

foreign func archive_read_support_compression_all(arg1: CPointer<archive>): Int32

foreign func archive_read_support_compression_bzip2(arg1: CPointer<archive>): Int32

foreign func archive_read_support_compression_compress(arg1: CPointer<archive>): Int32

foreign func archive_read_support_compression_gzip(arg1: CPointer<archive>): Int32

foreign func archive_read_support_compression_lzip(arg1: CPointer<archive>): Int32

foreign func archive_read_support_compression_lzma(arg1: CPointer<archive>): Int32

foreign func archive_read_support_compression_none(arg1: CPointer<archive>): Int32

foreign func archive_read_support_compression_program(arg1: CPointer<archive>, command: CString): Int32

foreign func archive_read_support_compression_program_signature(arg1: CPointer<archive>, arg2: CString,
    arg3: CPointer<Unit>, arg4: UIntNative): Int32

foreign func archive_read_support_compression_rpm(arg1: CPointer<archive>): Int32

foreign func archive_read_support_compression_uu(arg1: CPointer<archive>): Int32

foreign func archive_read_support_compression_xz(arg1: CPointer<archive>): Int32

foreign func archive_read_support_filter_all(arg1: CPointer<archive>): Int32

foreign func archive_read_support_filter_by_code(arg1: CPointer<archive>, arg2: Int32): Int32

foreign func archive_read_support_filter_bzip2(arg1: CPointer<archive>): Int32

foreign func archive_read_support_filter_compress(arg1: CPointer<archive>): Int32

foreign func archive_read_support_filter_gzip(arg1: CPointer<archive>): Int32

foreign func archive_read_support_filter_grzip(arg1: CPointer<archive>): Int32

foreign func archive_read_support_filter_lrzip(arg1: CPointer<archive>): Int32

foreign func archive_read_support_filter_lz4(arg1: CPointer<archive>): Int32

foreign func archive_read_support_filter_lzip(arg1: CPointer<archive>): Int32

foreign func archive_read_support_filter_lzma(arg1: CPointer<archive>): Int32

foreign func archive_read_support_filter_lzop(arg1: CPointer<archive>): Int32

foreign func archive_read_support_filter_none(arg1: CPointer<archive>): Int32

foreign func archive_read_support_filter_program(arg1: CPointer<archive>, command: CString): Int32

foreign func archive_read_support_filter_program_signature(arg1: CPointer<archive>, arg2: CString,
    arg3: CPointer<Unit>, arg4: UIntNative): Int32

foreign func archive_read_support_filter_rpm(arg1: CPointer<archive>): Int32

foreign func archive_read_support_filter_uu(arg1: CPointer<archive>): Int32

foreign func archive_read_support_filter_xz(arg1: CPointer<archive>): Int32

foreign func archive_read_support_filter_zstd(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_7zip(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_all(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_ar(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_by_code(arg1: CPointer<archive>, arg2: Int32): Int32

foreign func archive_read_support_format_cab(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_cpio(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_empty(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_gnutar(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_iso9660(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_lha(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_mtree(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_rar(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_rar5(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_raw(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_tar(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_warc(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_xar(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_zip(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_zip_streamable(arg1: CPointer<archive>): Int32

foreign func archive_read_support_format_zip_seekable(arg1: CPointer<archive>): Int32

foreign func archive_read_set_format(arg1: CPointer<archive>, arg2: Int32): Int32

foreign func archive_read_append_filter(arg1: CPointer<archive>, arg2: Int32): Int32

foreign func archive_read_append_filter_program(arg1: CPointer<archive>, arg2: CString): Int32

foreign func archive_read_append_filter_program_signature(arg1: CPointer<archive>, arg2: CString,
    arg3: CPointer<Unit>, arg4: UIntNative): Int32

foreign func archive_read_set_open_callback(arg1: CPointer<archive>, arg2: archive_open_callback): Int32

foreign func archive_read_set_read_callback(arg1: CPointer<archive>, arg2: archive_read_callback): Int32

foreign func archive_read_set_seek_callback(arg1: CPointer<archive>, arg2: archive_seek_callback): Int32

foreign func archive_read_set_skip_callback(arg1: CPointer<archive>, arg2: archive_skip_callback): Int32

foreign func archive_read_set_close_callback(arg1: CPointer<archive>, arg2: archive_close_callback): Int32

foreign func archive_read_set_switch_callback(arg1: CPointer<archive>, arg2: archive_switch_callback): Int32

foreign func archive_read_set_callback_data(arg1: CPointer<archive>, arg2: CPointer<Unit>): Int32

foreign func archive_read_set_callback_data2(arg1: CPointer<archive>, arg2: CPointer<Unit>, arg3: UInt32): Int32

foreign func archive_read_add_callback_data(arg1: CPointer<archive>, arg2: CPointer<Unit>, arg3: UInt32): Int32

foreign func archive_read_append_callback_data(arg1: CPointer<archive>, arg2: CPointer<Unit>): Int32

foreign func archive_read_prepend_callback_data(arg1: CPointer<archive>, arg2: CPointer<Unit>): Int32

foreign func archive_read_open1(arg1: CPointer<archive>): Int32

foreign func archive_read_open(arg1: CPointer<archive>, _client_data: CPointer<Unit>, arg2: archive_open_callback,
    arg3: archive_read_callback, arg4: archive_close_callback): Int32

foreign func archive_read_open2(arg1: CPointer<archive>, _client_data: CPointer<Unit>, arg2: archive_open_callback,
    arg3: archive_read_callback, arg4: archive_skip_callback, arg5: archive_close_callback): Int32

foreign func archive_read_open_filename(arg1: CPointer<archive>, _filename: CString, _block_size: UIntNative): Int32

foreign func archive_read_open_filenames(arg1: CPointer<archive>, _filenames: CPointer<CString>,
    _block_size: UIntNative): Int32

foreign func archive_read_open_filename_w(arg1: CPointer<archive>, _filename: CPointer<wchar_t>, _block_size: UIntNative): Int32

foreign func archive_read_open_file(arg1: CPointer<archive>, _filename: CString, _block_size: UIntNative): Int32

foreign func archive_read_open_memory(arg1: CPointer<archive>, buff: CPointer<Unit>, size: UIntNative): Int32

foreign func archive_read_open_memory2(a: CPointer<archive>, buff: CPointer<Unit>, size: UIntNative,
    read_size: UIntNative): Int32

foreign func archive_read_open_fd(arg1: CPointer<archive>, _fd: Int32, _block_size: UIntNative): Int32

foreign func archive_read_open_FILE(arg1: CPointer<archive>, _file: CPointer<VArray<UInt64, $27>>): Int32

foreign func archive_read_next_header(arg1: CPointer<archive>, arg2: CPointer<CPointer<archive_entry>>): Int32

foreign func archive_read_next_header2(arg1: CPointer<archive>, arg2: CPointer<archive_entry>): Int32

foreign func archive_read_header_position(arg1: CPointer<archive>): la_int64_t

foreign func archive_read_has_encrypted_entries(arg1: CPointer<archive>): Int32

foreign func archive_read_format_capabilities(arg1: CPointer<archive>): Int32

foreign func archive_read_data(arg1: CPointer<archive>, arg2: CPointer<Unit>, arg3: UIntNative): la_ssize_t

foreign func archive_seek_data(arg1: CPointer<archive>, arg2: la_int64_t, arg3: Int32): la_int64_t

foreign func archive_read_data_block(a: CPointer<archive>, buff: CPointer<CPointer<Unit>>, size: CPointer<UIntNative>,
    offset: CPointer<la_int64_t>): Int32

foreign func archive_read_data_skip(arg1: CPointer<archive>): Int32

foreign func archive_read_data_into_fd(arg1: CPointer<archive>, fd: Int32): Int32

foreign func archive_read_set_format_option(_a: CPointer<archive>, m: CString, o: CString,
    v: CString): Int32

foreign func archive_read_set_filter_option(_a: CPointer<archive>, m: CString, o: CString,
    v: CString): Int32

foreign func archive_read_set_option(_a: CPointer<archive>, m: CString, o: CString, v: CString): Int32

foreign func archive_read_set_options(_a: CPointer<archive>, opts: CString): Int32

foreign func archive_read_add_passphrase(arg1: CPointer<archive>, arg2: CString): Int32

foreign func archive_read_set_passphrase_callback(arg1: CPointer<archive>, client_data: CPointer<Unit>,
    arg2: archive_passphrase_callback): Int32

foreign func archive_read_extract(arg1: CPointer<archive>, arg2: CPointer<archive_entry>, flags: Int32): Int32

foreign func archive_read_extract2(arg1: CPointer<archive>, arg2: CPointer<archive_entry>, arg3: CPointer<archive>): Int32

foreign func archive_read_extract_set_progress_callback(arg1: CPointer<archive>,
    _progress_func: CFunc<(arg1: CPointer<Unit>) -> Unit>, _user_data: CPointer<Unit>): Unit

foreign func archive_read_extract_set_skip_file(arg1: CPointer<archive>, arg2: la_int64_t, arg3: la_int64_t): Unit

foreign func archive_read_close(arg1: CPointer<archive>): Int32

foreign func archive_read_free(arg1: CPointer<archive>): Int32

foreign func archive_read_finish(arg1: CPointer<archive>): Int32

foreign func archive_write_new(): CPointer<archive>

foreign func archive_write_set_bytes_per_block(arg1: CPointer<archive>, bytes_per_block: Int32): Int32

foreign func archive_write_get_bytes_per_block(arg1: CPointer<archive>): Int32

foreign func archive_write_set_bytes_in_last_block(arg1: CPointer<archive>, bytes_in_last_block: Int32): Int32

foreign func archive_write_get_bytes_in_last_block(arg1: CPointer<archive>): Int32

foreign func archive_write_set_skip_file(arg1: CPointer<archive>, arg2: la_int64_t, arg3: la_int64_t): Int32

foreign func archive_write_set_compression_bzip2(arg1: CPointer<archive>): Int32

foreign func archive_write_set_compression_compress(arg1: CPointer<archive>): Int32

foreign func archive_write_set_compression_gzip(arg1: CPointer<archive>): Int32

foreign func archive_write_set_compression_lzip(arg1: CPointer<archive>): Int32

foreign func archive_write_set_compression_lzma(arg1: CPointer<archive>): Int32

foreign func archive_write_set_compression_none(arg1: CPointer<archive>): Int32

foreign func archive_write_set_compression_program(arg1: CPointer<archive>, cmd: CString): Int32

foreign func archive_write_set_compression_xz(arg1: CPointer<archive>): Int32

foreign func archive_write_add_filter(arg1: CPointer<archive>, filter_code: Int32): Int32

foreign func archive_write_add_filter_by_name(arg1: CPointer<archive>, name: CString): Int32

foreign func archive_write_add_filter_b64encode(arg1: CPointer<archive>): Int32

foreign func archive_write_add_filter_bzip2(arg1: CPointer<archive>): Int32

foreign func archive_write_add_filter_compress(arg1: CPointer<archive>): Int32

foreign func archive_write_add_filter_grzip(arg1: CPointer<archive>): Int32

foreign func archive_write_add_filter_gzip(arg1: CPointer<archive>): Int32

foreign func archive_write_add_filter_lrzip(arg1: CPointer<archive>): Int32

foreign func archive_write_add_filter_lz4(arg1: CPointer<archive>): Int32

foreign func archive_write_add_filter_lzip(arg1: CPointer<archive>): Int32

foreign func archive_write_add_filter_lzma(arg1: CPointer<archive>): Int32

foreign func archive_write_add_filter_lzop(arg1: CPointer<archive>): Int32

foreign func archive_write_add_filter_none(arg1: CPointer<archive>): Int32

foreign func archive_write_add_filter_program(arg1: CPointer<archive>, cmd: CString): Int32

foreign func archive_write_add_filter_uuencode(arg1: CPointer<archive>): Int32

foreign func archive_write_add_filter_xz(arg1: CPointer<archive>): Int32

foreign func archive_write_add_filter_zstd(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format(arg1: CPointer<archive>, format_code: Int32): Int32

foreign func archive_write_set_format_by_name(arg1: CPointer<archive>, name: CString): Int32

foreign func archive_write_set_format_7zip(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_ar_bsd(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_ar_svr4(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_cpio(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_cpio_bin(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_cpio_newc(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_cpio_odc(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_cpio_pwb(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_gnutar(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_iso9660(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_mtree(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_mtree_classic(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_pax(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_pax_restricted(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_raw(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_shar(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_shar_dump(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_ustar(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_v7tar(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_warc(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_xar(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_zip(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_filter_by_ext(a: CPointer<archive>, filename: CString): Int32

foreign func archive_write_set_format_filter_by_ext_def(a: CPointer<archive>, filename: CString,
    def_ext: CString): Int32

foreign func archive_write_zip_set_compression_deflate(arg1: CPointer<archive>): Int32

foreign func archive_write_zip_set_compression_store(arg1: CPointer<archive>): Int32

foreign func archive_write_zip_set_compression_lzma(arg1: CPointer<archive>): Int32

foreign func archive_write_zip_set_compression_xz(arg1: CPointer<archive>): Int32

foreign func archive_write_zip_set_compression_bzip2(arg1: CPointer<archive>): Int32

foreign func archive_write_zip_set_compression_zstd(arg1: CPointer<archive>): Int32

foreign func archive_write_open(arg1: CPointer<archive>, arg2: CPointer<Unit>, arg3: archive_open_callback,
    arg4: archive_write_callback, arg5: archive_close_callback): Int32

foreign func archive_write_open2(arg1: CPointer<archive>, arg2: CPointer<Unit>, arg3: archive_open_callback,
    arg4: archive_write_callback, arg5: archive_close_callback, arg6: archive_free_callback): Int32

foreign func archive_write_open_fd(arg1: CPointer<archive>, _fd: Int32): Int32

foreign func archive_write_open_filename(arg1: CPointer<archive>, _file: CString): Int32

foreign func archive_write_open_filename_w(arg1: CPointer<archive>, _file: CPointer<wchar_t>): Int32

foreign func archive_write_open_file(arg1: CPointer<archive>, _file: CString): Int32

foreign func archive_write_open_FILE(arg1: CPointer<archive>, arg2: CPointer<VArray<UInt64, $27>>): Int32

foreign func archive_write_open_memory(arg1: CPointer<archive>, _buffer: CPointer<Unit>, _buffSize: UIntNative,
    _used: CPointer<UIntNative>): Int32

foreign func archive_write_header(arg1: CPointer<archive>, arg2: CPointer<archive_entry>): Int32

foreign func archive_write_data(arg1: CPointer<archive>, arg2: CPointer<Unit>, arg3: UIntNative): la_ssize_t

foreign func archive_write_data_block(arg1: CPointer<archive>, arg2: CPointer<Unit>, arg3: UIntNative, arg4: la_int64_t): la_ssize_t

foreign func archive_write_finish_entry(arg1: CPointer<archive>): Int32

foreign func archive_write_close(arg1: CPointer<archive>): Int32

foreign func archive_write_fail(arg1: CPointer<archive>): Int32

foreign func archive_write_free(arg1: CPointer<archive>): Int32

foreign func archive_write_finish(arg1: CPointer<archive>): Int32

foreign func archive_write_set_format_option(_a: CPointer<archive>, m: CString, o: CString,
    v: CString): Int32

foreign func archive_write_set_filter_option(_a: CPointer<archive>, m: CString, o: CString,
    v: CString): Int32

foreign func archive_write_set_option(_a: CPointer<archive>, m: CString, o: CString, v: CString): Int32

foreign func archive_write_set_options(_a: CPointer<archive>, opts: CString): Int32

foreign func archive_write_set_passphrase(_a: CPointer<archive>, p: CString): Int32

foreign func archive_write_set_passphrase_callback(arg1: CPointer<archive>, client_data: CPointer<Unit>,
    arg2: archive_passphrase_callback): Int32

foreign func archive_write_disk_new(): CPointer<archive>

foreign func archive_write_disk_set_skip_file(arg1: CPointer<archive>, arg2: la_int64_t, arg3: la_int64_t): Int32

foreign func archive_write_disk_set_options(arg1: CPointer<archive>, flags: Int32): Int32

foreign func archive_write_disk_set_standard_lookup(arg1: CPointer<archive>): Int32

foreign func archive_write_disk_set_group_lookup(arg1: CPointer<archive>, arg2: CPointer<Unit>,
    arg3: CFunc<(arg1: CPointer<Unit>, arg2: CString, arg3: la_int64_t) -> la_int64_t>,
    arg4: CFunc<(arg1: CPointer<Unit>) -> Unit>): Int32

foreign func archive_write_disk_set_user_lookup(arg1: CPointer<archive>, arg2: CPointer<Unit>,
    arg3: CFunc<(arg1: CPointer<Unit>, arg2: CString, arg3: la_int64_t) -> la_int64_t>,
    arg4: CFunc<(arg1: CPointer<Unit>) -> Unit>): Int32

foreign func archive_write_disk_gid(arg1: CPointer<archive>, arg2: CString, arg3: la_int64_t): la_int64_t

foreign func archive_write_disk_uid(arg1: CPointer<archive>, arg2: CString, arg3: la_int64_t): la_int64_t

foreign func archive_read_disk_new(): CPointer<archive>

foreign func archive_read_disk_set_symlink_logical(arg1: CPointer<archive>): Int32

foreign func archive_read_disk_set_symlink_physical(arg1: CPointer<archive>): Int32

foreign func archive_read_disk_set_symlink_hybrid(arg1: CPointer<archive>): Int32

foreign func archive_read_disk_entry_from_file(arg1: CPointer<archive>, arg2: CPointer<archive_entry>, arg3: Int32,
    arg4: CPointer<stat>): Int32

foreign func archive_read_disk_gname(arg1: CPointer<archive>, arg2: la_int64_t): CString

foreign func archive_read_disk_uname(arg1: CPointer<archive>, arg2: la_int64_t): CString

foreign func archive_read_disk_set_standard_lookup(arg1: CPointer<archive>): Int32

foreign func archive_read_disk_set_gname_lookup(arg1: CPointer<archive>, arg2: CPointer<Unit>,
    arg3: CFunc<(arg1: CPointer<Unit>, arg2: la_int64_t) -> CString>,
    arg4: CFunc<(arg1: CPointer<Unit>) -> Unit>): Int32

foreign func archive_read_disk_set_uname_lookup(arg1: CPointer<archive>, arg2: CPointer<Unit>,
    arg3: CFunc<(arg1: CPointer<Unit>, arg2: la_int64_t) -> CString>,
    arg4: CFunc<(arg1: CPointer<Unit>) -> Unit>): Int32

foreign func archive_read_disk_open(arg1: CPointer<archive>, arg2: CString): Int32

foreign func archive_read_disk_open_w(arg1: CPointer<archive>, arg2: CPointer<wchar_t>): Int32

foreign func archive_read_disk_descend(arg1: CPointer<archive>): Int32

foreign func archive_read_disk_can_descend(arg1: CPointer<archive>): Int32

foreign func archive_read_disk_current_filesystem(arg1: CPointer<archive>): Int32

foreign func archive_read_disk_current_filesystem_is_synthetic(arg1: CPointer<archive>): Int32

foreign func archive_read_disk_current_filesystem_is_remote(arg1: CPointer<archive>): Int32

foreign func archive_read_disk_set_atime_restored(arg1: CPointer<archive>): Int32

foreign func archive_read_disk_set_behavior(arg1: CPointer<archive>, flags: Int32): Int32

foreign func archive_read_disk_set_matching(arg1: CPointer<archive>, _matching: CPointer<archive>,
    _excluded_func: CFunc<(arg1: CPointer<archive>, arg2: CPointer<Unit>, arg3: CPointer<archive_entry>) -> Unit>,
    _client_data: CPointer<Unit>): Int32

foreign func archive_read_disk_set_metadata_filter_callback(arg1: CPointer<archive>,
    _metadata_filter_func: CFunc<(arg1: CPointer<archive>, arg2: CPointer<Unit>, arg3: CPointer<archive_entry>) -> Int32>,
    _client_data: CPointer<Unit>): Int32

foreign func archive_free(arg1: CPointer<archive>): Int32

foreign func archive_filter_count(arg1: CPointer<archive>): Int32

foreign func archive_filter_bytes(arg1: CPointer<archive>, arg2: Int32): la_int64_t

foreign func archive_filter_code(arg1: CPointer<archive>, arg2: Int32): Int32

foreign func archive_filter_name(arg1: CPointer<archive>, arg2: Int32): CString

foreign func archive_position_compressed(arg1: CPointer<archive>): la_int64_t

foreign func archive_position_uncompressed(arg1: CPointer<archive>): la_int64_t

foreign func archive_compression_name(arg1: CPointer<archive>): CString

foreign func archive_compression(arg1: CPointer<archive>): Int32

foreign func archive_parse_date(now: time_t, datestr: CString): time_t

foreign func archive_errno(arg1: CPointer<archive>): Int32

foreign func archive_error_string(arg1: CPointer<archive>): CString

foreign func archive_format_name(arg1: CPointer<archive>): CString

foreign func archive_format(arg1: CPointer<archive>): Int32

foreign func archive_clear_error(arg1: CPointer<archive>): Unit

foreign func archive_set_error(arg1: CPointer<archive>, _err: Int32, fmt: CString, ...): Unit

foreign func archive_copy_error(dest: CPointer<archive>, src: CPointer<archive>): Unit

foreign func archive_file_count(arg1: CPointer<archive>): Int32

foreign func archive_match_new(): CPointer<archive>

foreign func archive_match_free(arg1: CPointer<archive>): Int32

foreign func archive_match_excluded(arg1: CPointer<archive>, arg2: CPointer<archive_entry>): Int32

foreign func archive_match_path_excluded(arg1: CPointer<archive>, arg2: CPointer<archive_entry>): Int32

foreign func archive_match_set_inclusion_recursion(arg1: CPointer<archive>, arg2: Int32): Int32

foreign func archive_match_exclude_pattern(arg1: CPointer<archive>, arg2: CString): Int32

foreign func archive_match_exclude_pattern_w(arg1: CPointer<archive>, arg2: CPointer<wchar_t>): Int32

foreign func archive_match_exclude_pattern_from_file(arg1: CPointer<archive>, arg2: CString,
    _nullSeparator: Int32): Int32

foreign func archive_match_exclude_pattern_from_file_w(arg1: CPointer<archive>, arg2: CPointer<wchar_t>,
    _nullSeparator: Int32): Int32

foreign func archive_match_include_pattern(arg1: CPointer<archive>, arg2: CString): Int32

foreign func archive_match_include_pattern_w(arg1: CPointer<archive>, arg2: CPointer<wchar_t>): Int32

foreign func archive_match_include_pattern_from_file(arg1: CPointer<archive>, arg2: CString,
    _nullSeparator: Int32): Int32

foreign func archive_match_include_pattern_from_file_w(arg1: CPointer<archive>, arg2: CPointer<wchar_t>,
    _nullSeparator: Int32): Int32

foreign func archive_match_path_unmatched_inclusions(arg1: CPointer<archive>): Int32

foreign func archive_match_path_unmatched_inclusions_next(arg1: CPointer<archive>, arg2: CPointer<CString>): Int32

foreign func archive_match_path_unmatched_inclusions_next_w(arg1: CPointer<archive>, arg2: CPointer<CPointer<wchar_t>>): Int32

foreign func archive_match_time_excluded(arg1: CPointer<archive>, arg2: CPointer<archive_entry>): Int32

foreign func archive_match_include_time(arg1: CPointer<archive>, _flag: Int32, _sec: time_t, _nsec: Int64): Int32

foreign func archive_match_include_date(arg1: CPointer<archive>, _flag: Int32, _datestr: CString): Int32

foreign func archive_match_include_date_w(arg1: CPointer<archive>, _flag: Int32, _datestr: CPointer<wchar_t>): Int32

foreign func archive_match_include_file_time(arg1: CPointer<archive>, _flag: Int32, _pathname: CString): Int32

foreign func archive_match_include_file_time_w(arg1: CPointer<archive>, _flag: Int32, _pathname: CPointer<wchar_t>): Int32

foreign func archive_match_exclude_entry(arg1: CPointer<archive>, _flag: Int32, arg2: CPointer<archive_entry>): Int32

foreign func archive_match_owner_excluded(arg1: CPointer<archive>, arg2: CPointer<archive_entry>): Int32

foreign func archive_match_include_uid(arg1: CPointer<archive>, arg2: la_int64_t): Int32

foreign func archive_match_include_gid(arg1: CPointer<archive>, arg2: la_int64_t): Int32

foreign func archive_match_include_uname(arg1: CPointer<archive>, arg2: CString): Int32

foreign func archive_match_include_uname_w(arg1: CPointer<archive>, arg2: CPointer<wchar_t>): Int32

foreign func archive_match_include_gname(arg1: CPointer<archive>, arg2: CString): Int32

foreign func archive_match_include_gname_w(arg1: CPointer<archive>, arg2: CPointer<wchar_t>): Int32

foreign func archive_utility_string_sort(arg1: CPointer<CString>): Int32

foreign func archive_entry_clear(arg1: CPointer<archive_entry>): CPointer<archive_entry>

foreign func archive_entry_clone(arg1: CPointer<archive_entry>): CPointer<archive_entry>

foreign func archive_entry_free(arg1: CPointer<archive_entry>): Unit

foreign func archive_entry_new(): CPointer<archive_entry>

foreign func archive_entry_new2(arg1: CPointer<archive>): CPointer<archive_entry>

foreign func archive_entry_atime(arg1: CPointer<archive_entry>): time_t

foreign func archive_entry_atime_nsec(arg1: CPointer<archive_entry>): Int64

foreign func archive_entry_atime_is_set(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_birthtime(arg1: CPointer<archive_entry>): time_t

foreign func archive_entry_birthtime_nsec(arg1: CPointer<archive_entry>): Int64

foreign func archive_entry_birthtime_is_set(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_ctime(arg1: CPointer<archive_entry>): time_t

foreign func archive_entry_ctime_nsec(arg1: CPointer<archive_entry>): Int64

foreign func archive_entry_ctime_is_set(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_dev(arg1: CPointer<archive_entry>): dev_t

foreign func archive_entry_dev_is_set(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_devmajor(arg1: CPointer<archive_entry>): dev_t

foreign func archive_entry_devminor(arg1: CPointer<archive_entry>): dev_t

foreign func archive_entry_filetype(arg1: CPointer<archive_entry>): mode_t

foreign func archive_entry_filetype_is_set(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_fflags(arg1: CPointer<archive_entry>, arg2: CPointer<UInt64>, arg3: CPointer<UInt64>): Unit

foreign func archive_entry_fflags_text(arg1: CPointer<archive_entry>): CString

foreign func archive_entry_gid(arg1: CPointer<archive_entry>): la_int64_t

foreign func archive_entry_gid_is_set(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_gname(arg1: CPointer<archive_entry>): CString

foreign func archive_entry_gname_utf8(arg1: CPointer<archive_entry>): CString

foreign func archive_entry_gname_w(arg1: CPointer<archive_entry>): CPointer<wchar_t>

foreign func archive_entry_set_link_to_hardlink(arg1: CPointer<archive_entry>): Unit

foreign func archive_entry_hardlink(arg1: CPointer<archive_entry>): CString

foreign func archive_entry_hardlink_utf8(arg1: CPointer<archive_entry>): CString

foreign func archive_entry_hardlink_w(arg1: CPointer<archive_entry>): CPointer<wchar_t>

foreign func archive_entry_hardlink_is_set(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_ino(arg1: CPointer<archive_entry>): la_int64_t

foreign func archive_entry_ino64(arg1: CPointer<archive_entry>): la_int64_t

foreign func archive_entry_ino_is_set(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_mode(arg1: CPointer<archive_entry>): mode_t

foreign func archive_entry_mtime(arg1: CPointer<archive_entry>): time_t

foreign func archive_entry_mtime_nsec(arg1: CPointer<archive_entry>): Int64

foreign func archive_entry_mtime_is_set(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_nlink(arg1: CPointer<archive_entry>): UInt32

foreign func archive_entry_pathname(arg1: CPointer<archive_entry>): CString

foreign func archive_entry_pathname_utf8(arg1: CPointer<archive_entry>): CString

foreign func archive_entry_pathname_w(arg1: CPointer<archive_entry>): CPointer<wchar_t>

foreign func archive_entry_perm(arg1: CPointer<archive_entry>): mode_t

foreign func archive_entry_perm_is_set(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_rdev_is_set(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_rdev(arg1: CPointer<archive_entry>): dev_t

foreign func archive_entry_rdevmajor(arg1: CPointer<archive_entry>): dev_t

foreign func archive_entry_rdevminor(arg1: CPointer<archive_entry>): dev_t

foreign func archive_entry_sourcepath(arg1: CPointer<archive_entry>): CString

foreign func archive_entry_sourcepath_w(arg1: CPointer<archive_entry>): CPointer<wchar_t>

foreign func archive_entry_size(arg1: CPointer<archive_entry>): la_int64_t

foreign func archive_entry_size_is_set(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_strmode(arg1: CPointer<archive_entry>): CString

foreign func archive_entry_set_link_to_symlink(arg1: CPointer<archive_entry>): Unit

foreign func archive_entry_symlink(arg1: CPointer<archive_entry>): CString

foreign func archive_entry_symlink_utf8(arg1: CPointer<archive_entry>): CString

foreign func archive_entry_symlink_type(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_symlink_w(arg1: CPointer<archive_entry>): CPointer<wchar_t>

foreign func archive_entry_uid(arg1: CPointer<archive_entry>): la_int64_t

foreign func archive_entry_uid_is_set(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_uname(arg1: CPointer<archive_entry>): CString

foreign func archive_entry_uname_utf8(arg1: CPointer<archive_entry>): CString

foreign func archive_entry_uname_w(arg1: CPointer<archive_entry>): CPointer<wchar_t>

foreign func archive_entry_is_data_encrypted(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_is_metadata_encrypted(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_is_encrypted(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_set_atime(arg1: CPointer<archive_entry>, arg2: time_t, arg3: Int64): Unit

foreign func archive_entry_unset_atime(arg1: CPointer<archive_entry>): Unit

foreign func archive_entry_set_birthtime(arg1: CPointer<archive_entry>, arg2: time_t, arg3: Int64): Unit

foreign func archive_entry_unset_birthtime(arg1: CPointer<archive_entry>): Unit

foreign func archive_entry_set_ctime(arg1: CPointer<archive_entry>, arg2: time_t, arg3: Int64): Unit

foreign func archive_entry_unset_ctime(arg1: CPointer<archive_entry>): Unit

foreign func archive_entry_set_dev(arg1: CPointer<archive_entry>, arg2: dev_t): Unit

foreign func archive_entry_set_devmajor(arg1: CPointer<archive_entry>, arg2: dev_t): Unit

foreign func archive_entry_set_devminor(arg1: CPointer<archive_entry>, arg2: dev_t): Unit

foreign func archive_entry_set_filetype(arg1: CPointer<archive_entry>, arg2: UInt32): Unit

foreign func archive_entry_set_fflags(arg1: CPointer<archive_entry>, arg2: UInt64, arg3: UInt64): Unit

foreign func archive_entry_copy_fflags_text(arg1: CPointer<archive_entry>, arg2: CString): CString

foreign func archive_entry_copy_fflags_text_len(arg1: CPointer<archive_entry>, arg2: CString, arg3: UIntNative): CString

foreign func archive_entry_copy_fflags_text_w(arg1: CPointer<archive_entry>, arg2: CPointer<wchar_t>): CPointer<wchar_t>

foreign func archive_entry_set_gid(arg1: CPointer<archive_entry>, arg2: la_int64_t): Unit

foreign func archive_entry_set_gname(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_set_gname_utf8(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_copy_gname(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_copy_gname_w(arg1: CPointer<archive_entry>, arg2: CPointer<wchar_t>): Unit

foreign func archive_entry_update_gname_utf8(arg1: CPointer<archive_entry>, arg2: CString): Int32

foreign func archive_entry_set_hardlink(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_set_hardlink_utf8(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_copy_hardlink(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_copy_hardlink_w(arg1: CPointer<archive_entry>, arg2: CPointer<wchar_t>): Unit

foreign func archive_entry_update_hardlink_utf8(arg1: CPointer<archive_entry>, arg2: CString): Int32

foreign func archive_entry_set_ino(arg1: CPointer<archive_entry>, arg2: la_int64_t): Unit

foreign func archive_entry_set_ino64(arg1: CPointer<archive_entry>, arg2: la_int64_t): Unit

foreign func archive_entry_set_link(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_set_link_utf8(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_copy_link(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_copy_link_w(arg1: CPointer<archive_entry>, arg2: CPointer<wchar_t>): Unit

foreign func archive_entry_update_link_utf8(arg1: CPointer<archive_entry>, arg2: CString): Int32

foreign func archive_entry_set_mode(arg1: CPointer<archive_entry>, arg2: mode_t): Unit

foreign func archive_entry_set_mtime(arg1: CPointer<archive_entry>, arg2: time_t, arg3: Int64): Unit

foreign func archive_entry_unset_mtime(arg1: CPointer<archive_entry>): Unit

foreign func archive_entry_set_nlink(arg1: CPointer<archive_entry>, arg2: UInt32): Unit

foreign func archive_entry_set_pathname(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_set_pathname_utf8(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_copy_pathname(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_copy_pathname_w(arg1: CPointer<archive_entry>, arg2: CPointer<wchar_t>): Unit

foreign func archive_entry_update_pathname_utf8(arg1: CPointer<archive_entry>, arg2: CString): Int32

foreign func archive_entry_set_perm(arg1: CPointer<archive_entry>, arg2: mode_t): Unit

foreign func archive_entry_set_rdev(arg1: CPointer<archive_entry>, arg2: dev_t): Unit

foreign func archive_entry_set_rdevmajor(arg1: CPointer<archive_entry>, arg2: dev_t): Unit

foreign func archive_entry_set_rdevminor(arg1: CPointer<archive_entry>, arg2: dev_t): Unit

foreign func archive_entry_set_size(arg1: CPointer<archive_entry>, arg2: la_int64_t): Unit

foreign func archive_entry_unset_size(arg1: CPointer<archive_entry>): Unit

foreign func archive_entry_copy_sourcepath(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_copy_sourcepath_w(arg1: CPointer<archive_entry>, arg2: CPointer<wchar_t>): Unit

foreign func archive_entry_set_symlink(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_set_symlink_type(arg1: CPointer<archive_entry>, arg2: Int32): Unit

foreign func archive_entry_set_symlink_utf8(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_copy_symlink(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_copy_symlink_w(arg1: CPointer<archive_entry>, arg2: CPointer<wchar_t>): Unit

foreign func archive_entry_update_symlink_utf8(arg1: CPointer<archive_entry>, arg2: CString): Int32

foreign func archive_entry_set_uid(arg1: CPointer<archive_entry>, arg2: la_int64_t): Unit

foreign func archive_entry_set_uname(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_set_uname_utf8(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_copy_uname(arg1: CPointer<archive_entry>, arg2: CString): Unit

foreign func archive_entry_copy_uname_w(arg1: CPointer<archive_entry>, arg2: CPointer<wchar_t>): Unit

foreign func archive_entry_update_uname_utf8(arg1: CPointer<archive_entry>, arg2: CString): Int32

foreign func archive_entry_set_is_data_encrypted(arg1: CPointer<archive_entry>, is_encrypted: UInt8): Unit

foreign func archive_entry_set_is_metadata_encrypted(arg1: CPointer<archive_entry>, is_encrypted: UInt8): Unit

foreign func archive_entry_stat(arg1: CPointer<archive_entry>): CPointer<stat>

foreign func archive_entry_copy_stat(arg1: CPointer<archive_entry>, arg2: CPointer<stat>): Unit

foreign func archive_entry_mac_metadata(arg1: CPointer<archive_entry>, arg2: CPointer<UIntNative>): CPointer<Unit>

foreign func archive_entry_copy_mac_metadata(arg1: CPointer<archive_entry>, arg2: CPointer<Unit>, arg3: UIntNative): Unit

foreign func archive_entry_digest(arg1: CPointer<archive_entry>, arg2: Int32): CString

foreign func archive_entry_set_digest(arg1: CPointer<archive_entry>, arg2: Int32, arg3: CString): Int32

foreign func archive_entry_acl_clear(arg1: CPointer<archive_entry>): Unit

foreign func archive_entry_acl_add_entry(arg1: CPointer<archive_entry>, arg2: Int32, arg3: Int32, arg4: Int32,
    arg5: Int32, arg6: CString): Int32

foreign func archive_entry_acl_add_entry_w(arg1: CPointer<archive_entry>, arg2: Int32, arg3: Int32, arg4: Int32,
    arg5: Int32, arg6: CPointer<wchar_t>): Int32

foreign func archive_entry_acl_reset(arg1: CPointer<archive_entry>, arg2: Int32): Int32

foreign func archive_entry_acl_next(arg1: CPointer<archive_entry>, arg2: Int32, arg3: CPointer<Int32>,
    arg4: CPointer<Int32>, arg5: CPointer<Int32>, arg6: CPointer<Int32>, arg7: CPointer<CString>): Int32

foreign func archive_entry_acl_to_text_w(arg1: CPointer<archive_entry>, arg2: CPointer<la_ssize_t>, arg3: Int32): CPointer<wchar_t>

foreign func archive_entry_acl_to_text(arg1: CPointer<archive_entry>, arg2: CPointer<la_ssize_t>, arg3: Int32): CString

foreign func archive_entry_acl_from_text_w(arg1: CPointer<archive_entry>, arg2: CPointer<wchar_t>, arg3: Int32): Int32

foreign func archive_entry_acl_from_text(arg1: CPointer<archive_entry>, arg2: CString, arg3: Int32): Int32

foreign func archive_entry_acl_text_w(arg1: CPointer<archive_entry>, arg2: Int32): CPointer<wchar_t>

foreign func archive_entry_acl_text(arg1: CPointer<archive_entry>, arg2: Int32): CString

foreign func archive_entry_acl_types(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_acl_count(arg1: CPointer<archive_entry>, arg2: Int32): Int32

@C
public struct archive_acl {
    init() {
        throw Exception("type should not be inited")
    }
}

foreign func archive_entry_acl(arg1: CPointer<archive_entry>): CPointer<archive_acl>

foreign func archive_entry_xattr_clear(arg1: CPointer<archive_entry>): Unit

foreign func archive_entry_xattr_add_entry(arg1: CPointer<archive_entry>, arg2: CString, arg3: CPointer<Unit>,
    arg4: UIntNative): Unit

foreign func archive_entry_xattr_count(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_xattr_reset(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_xattr_next(arg1: CPointer<archive_entry>, arg2: CPointer<CString>,
    arg3: CPointer<CPointer<Unit>>, arg4: CPointer<UIntNative>): Int32

foreign func archive_entry_sparse_clear(arg1: CPointer<archive_entry>): Unit

foreign func archive_entry_sparse_add_entry(arg1: CPointer<archive_entry>, arg2: la_int64_t, arg3: la_int64_t): Unit

foreign func archive_entry_sparse_count(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_sparse_reset(arg1: CPointer<archive_entry>): Int32

foreign func archive_entry_sparse_next(arg1: CPointer<archive_entry>, arg2: CPointer<la_int64_t>,
    arg3: CPointer<la_int64_t>): Int32

@C
public struct archive_entry_linkresolver {
    init() {
        throw Exception("type should not be inited")
    }
}

foreign func archive_entry_linkresolver_new(): CPointer<archive_entry_linkresolver>

foreign func archive_entry_linkresolver_set_strategy(arg1: CPointer<archive_entry_linkresolver>, arg2: Int32): Unit

foreign func archive_entry_linkresolver_free(arg1: CPointer<archive_entry_linkresolver>): Unit

foreign func archive_entry_linkify(arg1: CPointer<archive_entry_linkresolver>, arg2: CPointer<CPointer<archive_entry>>,
    arg3: CPointer<CPointer<archive_entry>>): Unit

foreign func archive_entry_partial_links(res: CPointer<archive_entry_linkresolver>, links: CPointer<UInt32>): CPointer<archive_entry>

public type __int64_t = Int64

public type __uint64_t = UInt64

public type __ssize_t = Int64

public type wchar_t = Int32

public type __dev_t = UInt64

public type __ino_t = UInt64

public type __nlink_t = UInt64

public type __mode_t = UInt32

public type __uid_t = UInt32

public type __gid_t = UInt32

public type __off_t = Int64

public type __blksize_t = Int64

public type __blkcnt_t = Int64

public type __time_t = Int64

public type __syscall_slong_t = Int64

@C
public struct timespec {
    public let tv_sec: __time_t
    public let tv_nsec: __syscall_slong_t

    public init(tv_sec: __time_t, tv_nsec: __syscall_slong_t) {
        this.tv_sec = tv_sec
        this.tv_nsec = tv_nsec
    }
}

@When[debug]
let _ = {
    =>
    let size = sizeOf<timespec>()
    if (size != 16) {
        throw Exception("Size of timespec is not 16 but ${size} bytes")
    }
    let align = alignOf<timespec>()
    if (align != 8) {
        throw Exception("Alignment of timespec is not 8 but ${align} bytes")
    }
}

@C
public struct stat {
    public let st_dev: __dev_t
    public let st_ino: __ino_t
    public let st_nlink: __nlink_t
    public let st_mode: __mode_t
    public let st_uid: __uid_t
    public let st_gid: __gid_t
    public let __pad0: Int32
    public let st_rdev: __dev_t
    public let st_size: __off_t
    public let st_blksize: __blksize_t
    public let st_blocks: __blkcnt_t
    public let st_atim: timespec
    public let st_mtim: timespec
    public let st_ctim: timespec
    public let __glibc_reserved: VArray<__syscall_slong_t, $3>

    init(st_dev: __dev_t, st_ino: __ino_t, st_nlink: __nlink_t, st_mode: __mode_t, st_uid: __uid_t, st_gid: __gid_t,
        __pad0: Int32, st_rdev: __dev_t, st_size: __off_t, st_blksize: __blksize_t, st_blocks: __blkcnt_t,
        st_atim: timespec, st_mtim: timespec, st_ctim: timespec, __glibc_reserved: VArray<__syscall_slong_t, $3>) {
        this.st_dev = st_dev
        this.st_ino = st_ino
        this.st_nlink = st_nlink
        this.st_mode = st_mode
        this.st_uid = st_uid
        this.st_gid = st_gid
        this.__pad0 = __pad0
        this.st_rdev = st_rdev
        this.st_size = st_size
        this.st_blksize = st_blksize
        this.st_blocks = st_blocks
        this.st_atim = st_atim
        this.st_mtim = st_mtim
        this.st_ctim = st_ctim
        this.__glibc_reserved = __glibc_reserved
        throw Exception("type should not be inited")
    }
}

public type time_t = __time_t

public type dev_t = __dev_t

public type mode_t = __mode_t
