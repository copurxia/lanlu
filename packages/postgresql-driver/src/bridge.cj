package postgresql_driver

// ===== lanlu PG bridge FFI（native/lanlu_pg_bridge.c，经 [ffi.c] 链接）=====
// bridge 把整个 PGresult 一次物化成扁平缓冲：仓颉侧用 <=4 次 FFI（materialize +
// header/cell 访问器按需）取回，代替旧路径每 cell 2-3 次的 PQgetvalue/PQgetisnull。
// 声明均为纯内存操作（指针算术/memcpy/free），不阻塞、不回调仓颉，符合 @FastNative
// 约束；llpg_materialize 内部遍历大结果集有循环，保守起见不标注（见 fastnative-analysis）。

@FastNative
foreign func llpg_row_count(buf: CPointer<UInt8>): Int32

@FastNative
foreign func llpg_col_count(buf: CPointer<UInt8>): Int32

@FastNative
foreign func llpg_col_oid(buf: CPointer<UInt8>, col: Int32): Int32

@FastNative
foreign func llpg_cell_len(buf: CPointer<UInt8>, row: Int32, col: Int32): Int32

@FastNative
foreign func llpg_cell_off(buf: CPointer<UInt8>, row: Int32, col: Int32): Int64

@FastNative
foreign func llpg_bridge_free(buf: CPointer<UInt8>): Unit

// 内部含 malloc/遍历/memcpy（单次调用完成整个结果集搬运），不做 @FastNative 标注。
foreign func llpg_materialize(res: CPointer<Unit>): CPointer<UInt8>

// 二进制结果协议可用性判定（纯内存 OID 白名单检查）。内部无循环返回路径上有遍历，
// 保守不标注。
foreign func llpg_binary_result_format(res: CPointer<Unit>): Int32
