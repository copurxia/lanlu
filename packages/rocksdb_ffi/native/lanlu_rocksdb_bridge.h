#ifndef LANLU_ROCKSDB_BRIDGE_H
#define LANLU_ROCKSDB_BRIDGE_H

#include <rocksdb/c.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t llrocksdb_compiled_major(void);
int32_t llrocksdb_compiled_minor(void);

/* rocksdb_snapshot_get_sequence_number 自 RocksDB 9.0 才存在于 C API，
 * 老版本（如 Ubuntu 24.04 的 8.9.x）由 bridge 兜底返回 0，
 * 避免仓颉侧直接 foreign 引用导致老库链接失败。 */
uint64_t llrocksdb_snapshot_get_sequence_number(const rocksdb_snapshot_t *snapshot);

#ifdef __cplusplus
}
#endif

#endif /* LANLU_ROCKSDB_BRIDGE_H */
