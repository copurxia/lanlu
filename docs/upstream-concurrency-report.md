# 上游代码并发相关缺陷报告

- 报告日期：2026-11-06
- 被测实例：`https://nas.copur.xyz:3005/`（兰鹿 `1.0.0-feat/plugin-source-setting.006e31b`）
- 审查范围：
  - `packages/postgresql-driver`（仓库内置上游，连接池与 FFI 驱动）
  - `packages/csorm`（仓库内置上游，ORM 执行层）
  - `ignite`（外部 git 依赖，`gitcode.com/copur/ignite-cangjie.git` branch `stdx`，已 clone 到本地审查）
  - `brotli_middleware`（外部 git 依赖，行为经线上响应头实测确认）
  - `stdx.net.http`（仓颉标准扩展库，未获取源码，行为基于实测推断）
- 结论摘要：**并发瓶颈主要不在框架层，而在"慢查询 x 连接池 10 x 无超时保护"的组合**。框架层轻请求可跑到约 1400 rps / 100 连接，40 路 SSE 常驻也未造成挤占；但共享连接池没有借出超时、失效连接校验和池指标，一旦慢查询出现，全站请求排队且无快速失败。

## 一、postgresql-driver（优先级最高）

### P1-1 连接借出无超时，饱和时无限阻塞

`packages/postgresql-driver/src/pool.cj:53-88`：`borrow()` 在达到 `maxSize` 后执行 `cond.wait()`，**没有超时参数，也不返回排队状态**。同一文件里 `PoolConfig` 只有 max/min/idleTimeout，没有 `borrowTimeout`。

后果（与实测吻合）：`/api/search` 单次查询 1~2s，池上限 10，30 并发搜索时全站任何需要 DB 的请求都进入无界等待。实测搜索压测期间 `/api/auth/me` p95 达 1.63s、`/api/categories` p50 从 6ms 恶化到 367ms，但**没有任何 5xx 或超时错误**——请求只是排队。这意味着故障表现为"整站变慢"而非可观测的过载错误，运维无从定位。

建议：
- `borrow(timeoutMs)`，超时抛 `PGError`，由上层转 503/429；
- 暴露 `waiting`、`inUse`、`idle`、`waitDuration` 指标，并让 `ConnectionPoolStats` 真实返回（见 P1-5）。

### P1-2 借出连接不校验，失效连接直接抛给业务

`pool.cj:53-88` 的 `borrow()` 直接从 idle 栈弹出连接返回，没有 `PQstatus` 检查；`connection.cj:133-156` 的 `query/exec` 也没有重试。

后果：PostgreSQL 重启、容器网络抖动、NAS 侧连接跟踪超时后，池中残留连接在下一次被借出时执行失败，业务端表现为零星 500，直到 `idleTimeoutMs`（默认 5 分钟）惰性回收。多实例部署（或 PG 被运维重启）时这是必然事件。

建议：借出时校验 `PQstatus == CONNECTION_OK`（或在 SQLSTATE `08006/08003` 时丢弃并重借一次）。

### P1-3 `lastAffected` 是跨线程共享可变字段（数据竞争）

`connection.cj:23` `var lastAffected: Int64 = -1`，`exec()` 在 `connection.cj:191` 写入，`affectedRows()` 在 `:214` 读取。`PGDatabase` 是全局单例（所有线程共享同一个 `Database`），该字段无锁、无 `ThreadLocal`，并发下 `affectedRows()` 可能返回其他线程刚写入的值。

影响：依赖受影响行数做幂等/冲突判断的写接口（收藏、进度、token 撤销等）在高并发下可能误判。

建议：改为 `ThreadLocal<Int64>`，或把受影响行数作为 `exec` 返回值传递（现有调用方已可直接使用返回值）。

### P1-4 跨线程 cancel 的目标连接是全局单槽

`connection.cj:21-22` 只有一个 `activeConn`（受 `activeConnMu` 保护），`:54-60` 每次查询前覆盖写入。并发查询时，`cancel()` 从另一线程取消时可能取消到**别的请求正在执行的查询**。

建议：维护 `线程ID -> 连接` 注册表，cancel 按请求上下文目标定位；或限制 cancel API 只在持有查询句柄时可用。

### P2-5 池指标不可用

`ConnectionPool` 只提供 `idleCount()` 与 `size()`（`pool.cj:44-50`）；应用层 `connection_pool.cj:161-170` 的 `stats()` 把 `idle` 硬编码为 0，也不返回 `inUse/broken/waiting`。线上无法判断"是池满还是 DB 慢"。

建议：补 `inUse`、`waiting`、`totalWaitMs`、`borrowCount`，并接入现有系统设置/信息接口。

### P2-6 `reapIdleLocked` 在持锁状态下做 O(n) 头部删除

`pool.cj:120-135`：每次 `borrow()` 都会调用，`idle.remove(at: 0)` + `idleSince.remove(at: 0)` 在 `ArrayList` 头部删除是 O(n)。空闲连接多时（池上限 10 时影响小；若调大 `POOL_MAX` 到 100+ 则明显），每次借还都放大锁持有时间。

建议：改用栈式弹出（`remove(at: size-1)`，空闲超时按创建时间检查）或 `ArrayDeque`。

### P2-7 池默认值与大查询负载不匹配

`conninfo.cj:110`、`:150` 与 `packages/.../connection_pool.cj:19` 默认 `maxSize=10`；`.env.example:18` 也是 `POOL_MAX=10`，docker-compose 未覆盖。单条搜索查询在 PG 侧要 0.5~1s，10 个连接意味着**理论上限只有约 10 rps 的搜索吞吐**，实测 30 并发搜索仅 5.4 rps，与推算一致。

这不是驱动 bug，但驱动没有提供"按查询耗时自适应/排队告警"的手段。建议在驱动文档或应用层补 `statement_timeout`（当前应用与驱动均未设置，全仓库仅在测试字符串里出现过）与并发建议。

## 二、ignite 框架（外部上游）

### P2-8 自带 gzip/deflate 压缩中间件，但兰鹿没有启用

`ignite/middleware/compress.cj:34-100` 实现了完整的 `Accept-Encoding` 协商，支持 **gzip 与 deflate**（`stdx.compress.zlib`），并有 `minBytes`、`skipIfNoGain`、`Vary` 等配置。兰鹿当前依赖的是外部 `brotli_middleware`，线上实测：

```
Accept-Encoding: gzip        -> 1,435KB 原文（无压缩）
Accept-Encoding: br          -> 522KB  (content-encoding: br)
Accept-Encoding: gzip, br    -> 522KB  (content-encoding: br)
```

即 **gzip-only 客户端拿不到任何压缩**。`/api/tags/translations` 每次 1.4MB，部分原生 HTTP 客户端（含默认只带 gzip 的库）会持续拉原文。

建议（二选一）：
- 兰鹿侧同时挂载 `compressMiddleware`（gzip/deflate）与 brotli，优先 br（改动在应用，不在上游）；
- 或上游 `brotli_middleware` 补 gzip 回退分支，并正确设置 `Vary: Accept-Encoding`。

### P2-9 未暴露服务端并发/线程模型配置

`ignite/server_engine.cj:177-225` 直接把请求交给 `stdx.net.http.Server`，`app.cj:1370-1391` 的 `IgniteDistributor` 把所有路径都分发给同一个 handler。`Config` 中没有 worker 数、并发连接上限、SSE 流上限等配置项。

实测：40 路 SSE 常驻时 `/api/categories` 仍 481 rps / p50 5.9ms，说明当前规模下 stdx Server 的线程模型能撑住；但 Ignite 没有提供任何上限保护。SSE（`taskpool_controller.cj:52-90`）在 handler 里 `while(true)` 长期占用，若部署规模上升到数百路流，将没有防护手段。

建议：上游暴露 `maxConcurrentStreams` / 每连接写超时；框架侧给出"长连接不占 worker"的协程模型或明确文档说明线程模型。

### 说明：路由匹配不是瓶颈

`ignite/router.cj:210-260` 使用 trie 匹配，单请求匹配成本与路由数量无关，实测轻接口 p50 1~6ms 也印证无路由层瓶颈。

## 三、brotli_middleware（外部上游）

仅有 br 分支，无 gzip/deflate 回退（见 P2-8 实测）。建议上游支持协商回退，或由使用方组合 ignite 自带压缩中间件。

## 四、csorm（仓库内置上游）

`executor.cj:142-161` 的 `raw/rawOne` 直接走 `Database`，除 observability 回调注册（`observability.cj:47-61`）与 schema 注册（`schema.cj:337-360`）外**没有每查询全局锁**，并发路径干净，不构成瓶颈。

## 五、上游修改优先级建议

| 优先级 | 位置 | 改动 | 预期收益 |
| :-- | :-- | :-- | :-- |
| P1 | postgresql-driver `pool.cj` | 借出超时 + 池指标 | 过载时快速失败，可观测 |
| P1 | postgresql-driver `pool.cj` / `connection.cj` | 借出校验 + 一次重试 | 消除 PG 重启后的零星 500 |
| P1 | postgresql-driver `connection.cj` | `lastAffected` 改 `ThreadLocal` | 修复写接口并发误判 |
| P1 | postgresql-driver `connection.cj` | cancel 目标改为按线程注册 | 修复跨请求误取消 |
| P2 | ignite / brotli_middleware | gzip 回退（或组合压缩） | 1.4MB 响应体积降 60%+ |
| P2 | ignite | SSE 并发上限/写超时 | 长连接规模可控 |
| P2 | postgresql-driver `pool.cj` | 空闲回收 O(n) 改栈弹出 | 大池时降低锁持有时间 |
| P3 | 应用层 | `statement_timeout`、`POOL_MAX`、搜索限流 | 兜底保护，见主报告 |

## 六、无需改动上游即可先做的（收益远大于改上游）

1. `/api/tankoubons` 复用仓库内已有的批量缓存实现（见主报告第 2 节第 1 条），单点收益 6.1s → 亚秒级。
2. 搜索 COUNT 缓存/近似计数、带词搜索加 trigram 索引或缓存，搜索吞吐可提升一个数量级。
3. 每请求的 token 查询（`auth.cj:232-250` → `user_token_dao.cj:88-123`）可加 RocksDB 短 TTL 缓存，轻接口并发还能再抬高。
4. 慢查询与池满的监控指标（在应用层用现有 observability 中间件先兜住）。
