# `@FastNative` 可用性分析

- 分析日期：2026-11-06
- 结论先行：**能用，但对本项目当前测到的性能问题基本没有帮助（最乐观 <2%）。值得给少数"纯访问器"型 FFI 函数顺手加上，属于低成本微优化；不要指望它改善搜索/合集列表/并发表现。真正有效的方向是减少 FFI 调用次数（批量物化）和修 N+1，而不是降低单次调用开销。**
- 限制前提：本机未安装仓颉 SDK，无法做微基准；收益为基于官方语义与代码静态计数的估算，落地前应按第 6 节做一次 A/B 验证。

## 一、`@FastNative` 是什么（官方语义）

官方文档（`docs.cangjie-lang.cn` 内置编译标记）原文要点：

- "为了提升与 C 语言互操作的性能，仓颉提供 `@FastNative` 标记用于优化对 C 函数的调用。"
- "只能用于 `foreign` 声明的函数。"
- 被标注的 C 函数必须满足两条硬性要求：
  1. "函数的整体执行时间不宜太长。不允许函数内部存在很大的循环；不允许函数内部产生阻塞行为，例如：调用 sleep、wait 等函数。"
  2. "函数内部不能调用仓颉方法。"

第二条是**正确性约束**：标注后运行时不再为这次外调做完整的跨语言状态管理（GC 安全点/状态切换等），所以 C 函数一旦阻塞或回调仓颉，运行时无法正确接管。这决定了本项目里大量 FFI 函数**不能**标注（见下表）。

## 二、项目 FFI 现状盘点

仓颉侧 `foreign func` 声明数量（`grep` 统计）：

| 包 | 声明数 | 主要用途 | 是否在请求热路径 |
| :-- | --: | :-- | :-- |
| `packages/archive_ffi` | 456 | libarchive 遍历/解压 | 阅读页、封面、扫描 |
| `packages/rocksdb_ffi` | 117 | 本地 KV/缓存 | 每个鉴权请求、搜索缓存 |
| `packages/postgresql-driver` | 20 | libpq | 每个 DB 查询 |
| `packages/avif_ffi` | 83 | AVIF 编解码 | 图片转换（低频） |
| `packages/libvlc_ffi` / `libavformat_ffi` / `libass_ffi` | 47 | 媒体探测/播放 | 视频相关（低频） |
| `packages/rawdir_ffi` | 3 | 目录遍历 | 扫描任务 |
| 外部依赖 `vips_ffi` / `wasmedge_ffi` / `argon2_ffi` | — | 缩略图/WASM/口令哈希 | 后台任务、登录 |

### 每请求的 FFI 调用量（最坏的两个接口）

- `/api/tankoubons`：2319 行 × 12 列，`materialize` 每 cell 调 `PQgetisnull` 两次 + `PQgetvalue` 一次（`packages/postgresql-driver/src/connection.cj:116-124`），合计约 **8.3 万次** FFI 调用。
- `/api/search`：每页 20 行 × 16 列 ≈ **960 次** FFI 调用。
- 页面读取（`Archive.openEntryReader`）：每页几十到几百次（`archive_read_next_header2` 逐 entry），可忽略。

## 三、逐类判定

| 函数/场景 | 能否 `@FastNative` | 原因 |
| :-- | :--: | :-- |
| `PQntuples` / `PQnfields` / `PQfname` / `PQftype` / `PQgetvalue` / `PQgetisnull` / `PQresultStatus` / `PQcmdTuples` | ✅ 可以 | 纯内存访问器，微秒级、不阻塞、不回调 |
| `PQexecParams` / `PQexec` / `PQconnectdb` / `PQfinish` / `PQclear` / `PQcancel` | ❌ 禁止 | 网络阻塞（本项目单次查询 1~2s），违反"不得阻塞" |
| `rocksdb_get` / `rocksdb_put` / `rocksdb_write` / `rocksdb_multi_get` | ❌ 不建议 | 可能阻塞在磁盘 IO、WAL 同步、memtable 写满/compaction；且本身是 µs 级，收益近零 |
| `rocksdb_free`、各类 options getter/setter、`rocksdb_writebatch_put` | ⚠️ 可加但无意义 | 短且安全，但调用频率极低 |
| `archive_read_*` / `archive_entry_*` | ❌ 不建议 | `archive_read_open_filename`/`next_header` 内部做文件 IO 和解析循环；callback 型接口还可能回调仓颉 |
| `vips_*` / `avif_*` / `libavformat_*` / `libvlc_*` / `fontkit_*` | ❌ 不建议 | 单次解码/编码耗时毫秒到秒级，违反"执行时间不宜太长" |
| `argon2_*` | ❌ 禁止 | 设计上就是百毫秒级慢函数 |
| `rawdir_*`（readdir/stat） | ❌ 不建议 | 文件系统调用可能阻塞 |

## 四、收益量化（按实测数据估算）

单次 FFI 调用的运行时开销通常远小于 1µs（纯访问器在几十 ns 量级，保守按 100ns~1µs 估算）：

| 接口 | FFI 调用量 | 可省时间（100ns/call） | 可省时间（1µs/call） | 实测总耗时 | 占比 |
| :-- | --: | --: | --: | --: | --: |
| `/api/tankoubons` | ~83,000 | ~8ms | ~83ms | 6,130ms | 0.1%~1.4% |
| `/api/search`（每页） | ~960 | ~0.1ms | ~1ms | 1,400ms | <0.1% |
| `/api/search?filter=` | ~960 | ~0.1ms | ~1ms | 4,000~8,000ms | <0.03% |
| 页面读取 | <300 | 忽略 | 忽略 | 55ms | 忽略 |

结论：**即使把 `materialize` 里所有可标注的访问器都加上 `@FastNative`，最慢的 `/api/tankoubons` 也最多改善 1% 左右。** 该接口 6.1s 的构成是约 1.15 万次 DB 往返（每次 ~0.5ms），瓶颈在查询次数，不在跨语言调用开销。

## 五、比 `@FastNative` 收益大得多的 FFI 边界优化

这些都在仓库内置包（`packages/`）里，改动可控：

1. **`materialize` 每 cell 重复判空**：`connection.cj:116-124` 的 `vals` 和 `nulls` 两个 lambda 各调一次 `PQgetisnull`，可合并为一次，FFI 调用量直接降 1/3。
2. **按结果集批量物化**：在 `postgresql-driver` 里加一个 C 侧辅助函数（或一次性分配缓冲区），把整个 `PGresult` 在 C 侧转成连续的 `(ptr,len)` 数组，跨语言只调 2 次（而不是 2×行×列 次）。这是数量级上的改进，1000 行以上结果集收益明显。
3. **`PgRowData` 每行新建 `HashMap`**（`packages/postgresql-driver/src/row.cj:46-56`）：2319 行的合集查询会创建 2319 个列名 HashMap，这部分 Cangjie 堆分配开销很可能**大于**同请求的全部 FFI 开销。可改为共享列索引或在首次访问时惰性构建。
4. **RocksDB 取值逐字节拷贝**（`packages/rocksdb_ffi/src/main.cj:2765`：`Array<UInt8>(len, {i => (valuePtr + i).read()})`）：改为 `LibC.memcpy`/批量 `read`，对几十 KB 的缓存值收益明显。
5. **libpq 参数构造**：每次查询每个参数 `mallocCString` + `free`（`connection.cj:64-99`），可改为一次性 arena 或复用缓冲区。

## 六、若仍要落地 `@FastNative` 的建议方案

1. 先确认工具链：在 CI 里执行 `cjc -v`，确认 SDK 版本支持该标记（项目 `cjpm.toml` 声明 `cjc-version = 1.1.0`；1.0.0 文档已收录该标记，1.1.0 应可用，但以 CI 实际版本为准）。
2. 改动范围限定为 `packages/postgresql-driver/src/ffi.cj` 中的 8 个访问器（`PQntuples`、`PQnfields`、`PQfname`、`PQftype`、`PQgetvalue`、`PQgetisnull`、`PQresultStatus`、`PQcmdTuples`），逐个加 `@FastNative`。
3. **禁止**给任何可能阻塞或回调的声明加标注（清单见第三节）。
4. 验证：写一个单元基准（10 万次 `PQgetvalue` 调用）在 CI 跑一次，对比加标注前后的纳秒数；再对 `/api/tankoubons`、`/api/search` 做一次 A/B 压测。若 p50 改善 <2%，按微优化处理即可，不必继续扩大标注范围。
5. 回归重点关注：异常路径（`PQresultErrorMessage` 保持不标注）、取消查询（`PQcancel` 保持不标注）、以及 `--static` 构建下的行为一致性。

## 七、结论

- `@FastNative` 适合"高频、极短、纯内存"的 C 访问器，本项目符合的主要是 libpq 的取列函数。
- 它优化的是**单次跨语言调用开销**，而本项目实测瓶颈是**调用次数**（N+1、重复 COUNT、无缓存）和**并发排队**，两者不在一个数量级。
- 推荐顺序：先做第五节的批量物化/去重判空/复用列索引，再考虑顺手加 `@FastNative`；不要把它当成性能问题的解决方案。
