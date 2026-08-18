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
