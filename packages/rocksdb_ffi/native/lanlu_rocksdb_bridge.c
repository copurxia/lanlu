// Minimal RocksDB C API version probe: reads compile-time version macros so the
// Cangjie side can enforce a build-time major gate (same pattern as libavformat).
#include "lanlu_rocksdb_bridge.h"
#include <rocksdb/version.h>

int32_t llrocksdb_compiled_major(void) {
    return ROCKSDB_MAJOR;
}

int32_t llrocksdb_compiled_minor(void) {
    return ROCKSDB_MINOR;
}

uint64_t llrocksdb_snapshot_get_sequence_number(const rocksdb_snapshot_t *snapshot) {
#if ROCKSDB_MAJOR >= 9
    return rocksdb_snapshot_get_sequence_number(snapshot);
#else
    // RocksDB < 9.0 无此 C API；调用方语义允许退化为 0（快照读路径不依赖该值）。
    (void)snapshot;
    return 0;
#endif
}
