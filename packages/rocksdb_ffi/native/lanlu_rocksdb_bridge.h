#ifndef LANLU_ROCKSDB_BRIDGE_H
#define LANLU_ROCKSDB_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t llrocksdb_compiled_major(void);
int32_t llrocksdb_compiled_minor(void);

#ifdef __cplusplus
}
#endif

#endif /* LANLU_ROCKSDB_BRIDGE_H */
