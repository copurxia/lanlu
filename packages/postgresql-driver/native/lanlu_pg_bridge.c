/* lanlu PG bridge：见 lanlu_pg_bridge.h 的布局说明。
 * 编译进 liblanlu_pg_bridge.a，经 cjpm [ffi.c] 与 -llanlu_pg_bridge 链接。 */
#include "lanlu_pg_bridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int32_t llpg_binary_result_format(PGresult *res)
{
    /* 保守：仅当结果为 TUPLES_OK 且所有列 OID 都在二进制白名单内时返回 1。
     * 非元组结果（COMMAND_OK 等）没有列信息，调用方不会进入物化路径。 */
    if (res == NULL || PQresultStatus(res) != PGRES_TUPLES_OK) {
        return 0;
    }
    int n = PQnfields(res);
    if (n <= 0) {
        return 0;
    }
    for (int i = 0; i < n; i++) {
        Oid t = PQftype(res, i);
        switch (t) {
        case 16:   /* bool */
        case 17:   /* bytea */
        case 20:   /* int8 */
        case 21:   /* int2 */
        case 23:   /* int4 */
        case 25:   /* text */
        /* float4(700)/float8(701) 移出白名单：%.17g 与 PG 最短往返表示在仓颉
         * parseFloat64 下存在 ULP 级差异（e 常数案例），float 列走文本协议更稳 */
        case 1043: /* varchar */
        case 2950: /* uuid */
            continue;
        default:
            return 0;
        }
    }
    return 1;
}

uint8_t *llpg_materialize(PGresult *res)
{
    if (res == NULL) {
        return NULL;
    }
    int nrows = PQntuples(res);
    int ncols = PQnfields(res);
    if (nrows < 0 || ncols < 0) {
        return NULL;
    }

    /* 第一遍：累计非 NULL cell 的总字节数 */
    size_t data_bytes = 0;
    for (int r = 0; r < nrows; r++) {
        for (int c = 0; c < ncols; c++) {
            if (PQgetisnull(res, r, c) == 0) {
                data_bytes += (size_t)PQgetlength(res, r, c) + 1; /* +1 NUL terminator */
            }
        }
    }

    size_t header = 2 * sizeof(int32_t);
    size_t colmeta = (size_t)ncols * sizeof(int32_t);
    size_t cells = (size_t)nrows * (size_t)ncols * sizeof(int32_t);
    size_t total = header + colmeta + cells + data_bytes;
    uint8_t *buf = (uint8_t *)malloc(total ? total : 1);
    if (buf == NULL) {
        return NULL;
    }

    /* 头部 */
    int32_t *hdr = (int32_t *)buf;
    hdr[0] = (int32_t)nrows;
    hdr[1] = (int32_t)ncols;

    /* 列 OID */
    int32_t *coloids = (int32_t *)(buf + header);
    for (int c = 0; c < ncols; c++) {
        coloids[c] = (int32_t)PQftype(res, c);
    }

    /* cell 表 + data 段（一遍写出） */
    int32_t *celltab = (int32_t *)(buf + header + colmeta);
    uint8_t *data = buf + header + colmeta + cells;
    size_t off = 0;
    for (int r = 0; r < nrows; r++) {
        for (int c = 0; c < ncols; c++) {
            int32_t idx = (int32_t)((size_t)r * (size_t)ncols + (size_t)c);
            if (PQgetisnull(res, r, c) != 0) {
                celltab[idx] = -1;
                continue;
            }
            int len = PQgetlength(res, r, c);
            if (len > 0) {
                memcpy(data + off, PQgetvalue(res, r, c), (size_t)len);
            }
            data[off + len] = 0; /* NUL 终止：文本 cell 可用 CString(ptr).toString() 一次转换 */
            celltab[idx] = (int32_t)len;
            off += (size_t)len + 1;
        }
    }
    return buf;
}

int32_t llpg_row_count(const uint8_t *buf)
{
    return buf ? ((const int32_t *)buf)[0] : 0;
}

int32_t llpg_col_count(const uint8_t *buf)
{
    return buf ? ((const int32_t *)buf)[1] : 0;
}

int32_t llpg_col_oid(const uint8_t *buf, int32_t col)
{
    if (buf == NULL || col < 0) {
        return 0;
    }
    int32_t ncols = ((const int32_t *)buf)[1];
    if (col >= ncols) {
        return 0;
    }
    const int32_t *coloids = (const int32_t *)(buf + 2 * sizeof(int32_t));
    return coloids[col];
}

static const int32_t *llpg_cell_table(const uint8_t *buf, int32_t ncols)
{
    size_t header = 2 * sizeof(int32_t);
    size_t colmeta = (size_t)ncols * sizeof(int32_t);
    return (const int32_t *)(buf + header + colmeta);
}

int32_t llpg_cell_len(const uint8_t *buf, int32_t row, int32_t col)
{
    if (buf == NULL || row < 0 || col < 0) {
        return -1;
    }
    int32_t nrows = ((const int32_t *)buf)[0];
    int32_t ncols = ((const int32_t *)buf)[1];
    if (row >= nrows || col >= ncols) {
        return -1;
    }
    const int32_t *celltab = llpg_cell_table(buf, ncols);
    return celltab[(size_t)row * (size_t)ncols + (size_t)col];
}

int64_t llpg_cell_off(const uint8_t *buf, int32_t row, int32_t col)
{
    if (buf == NULL || row < 0 || col < 0) {
        return -1;
    }
    int32_t nrows = ((const int32_t *)buf)[0];
    int32_t ncols = ((const int32_t *)buf)[1];
    if (row >= nrows || col >= ncols) {
        return -1;
    }
    const int32_t *celltab = llpg_cell_table(buf, ncols);
    size_t idx = (size_t)row * (size_t)ncols + (size_t)col;
    if (celltab[idx] < 0) {
        return -1; /* NULL cell 无数据段偏移 */
    }
    size_t header = 2 * sizeof(int32_t);
    size_t colmeta = (size_t)ncols * sizeof(int32_t);
    size_t cells = (size_t)nrows * (size_t)ncols * sizeof(int32_t);
    size_t data_start = header + colmeta + cells;
    /* 该 cell 之前所有非 NULL cell 的占用（len + 1 NUL，与写入步进一致） */
    size_t off = 0;
    for (size_t i = 0; i < idx; i++) {
        if (celltab[i] >= 0) {
            off += (size_t)celltab[i] + 1;
        }
    }
    return (int64_t)(data_start + off);
}

const char *llpg_f64_text(uint64_t bits)
{
    double d;
    memcpy(&d, &bits, sizeof(d));
    /* PG 文本协议输出最短往返表示；%.17g 恒可往返。仓颉 parseFloat64 接受该格式。
     * 写入调用方传入的缓冲，避免分配与所有权问题。 */
    static _Thread_local char buf64[64];
    snprintf(buf64, sizeof(buf64), "%.17g", d);
    return buf64;
}

const char *llpg_f32_text(uint32_t bits)
{
    float f;
    memcpy(&f, &bits, sizeof(f));
    static _Thread_local char buf32[32];
    snprintf(buf32, sizeof(buf32), "%.9g", f);
    return buf32;
}

uint64_t llpg_ptr_key(const void *p)
{
    /* 指针值直接转整数；同一地址恒等。连接池保证连接指针生命周期内唯一。 */
    return (uint64_t)(uintptr_t)p;
}

void llpg_bridge_free(uint8_t *buf)
{
    free(buf);
}
