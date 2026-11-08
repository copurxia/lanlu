#ifndef LANLU_PG_BRIDGE_H
#define LANLU_PG_BRIDGE_H

/* lanlu PG bridge：把整个 PGresult 在 C 侧一次物化成扁平文本缓冲，
 * 仓颉侧用 <=4 次 FFI 调用取回（代替每 cell 2-3 次的 PQgetvalue/PQgetisnull）。
 * 仅做纯内存操作（遍历已就绪的 PGresult、memcpy、snprintf），不阻塞、不回调仓颉，
 * 符合 @FastNative 约束。PQexecParams/PQprepare 等阻塞调用仍在 ffi.cj 声明且不标注。 */

#include <libpq-fe.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 扁平物化布局（一个 malloc 缓冲，四段连续）：
 *   [header: 2 x int32]               nrows, ncols
 *   [col meta: ncols x int32]         每列 OID
 *   [cell table: nrows*ncols x int32] 每 cell 相对 data 段的字节长度；-1 表示 NULL
 *   [data: 变长]                      所有非 NULL cell 的文本字节（PQgetvalue 原样 memcpy）
 * 列名段不在此处：列名在结果内恒定，仓颉侧仍用 PQfname 逐列取一次（每结果 ncols 次，非每 cell）。
 * 返回 malloc 的缓冲指针；调用方用 llpg_bridge_free 释放。失败（res 为 NULL / OOM）返回 NULL。 */
int32_t llpg_binary_result_format(PGresult *res);
uint8_t *llpg_materialize(PGresult *res);

/* 头部与段定位（均为 O(1) 指针算术，输入 llpg_materialize 的返回值） */
int32_t llpg_row_count(const uint8_t *buf);
int32_t llpg_col_count(const uint8_t *buf);
/* 第 col 列的 OID（0-based） */
int32_t llpg_col_oid(const uint8_t *buf, int32_t col);
/* 第 (row,col) cell 的字节长度；NULL 返回 -1 */
int32_t llpg_cell_len(const uint8_t *buf, int32_t row, int32_t col);
/* 第 (row,col) cell 在缓冲内的起始下标（相对 buf 开头）；NULL cell 返回 -1 */
int64_t llpg_cell_off(const uint8_t *buf, int32_t row, int32_t col);

/* 浮点位模式 -> PG 文本协议等价字符串（静态缓冲，立即复制；线程安全因调用方
 * 串行使用同一连接；%.17g/%.9g 保证最短往返）。返回 malloc 字符串，调用方 free。 */
const char *llpg_f64_text(uint64_t bits);
const char *llpg_f32_text(uint32_t bits);

/* 指针身份键：任意指针 -> 64 位整数（供仓颉侧 HashMap 键，CPointer 无 ==/hash）。 */
uint64_t llpg_ptr_key(const void *p);

/* 释放 llpg_materialize 的缓冲 */
void llpg_bridge_free(uint8_t *buf);

#ifdef __cplusplus
}
#endif

#endif /* LANLU_PG_BRIDGE_H */
