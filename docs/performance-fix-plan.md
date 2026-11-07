# 性能问题根治计划（含单元测试设计）

- 日期：2026-11-06
- 输入：[api-performance-report.md](./api-performance-report.md)、[upstream-concurrency-report.md](./upstream-concurrency-report.md)、[fastnative-analysis.md](./fastnative-analysis.md)
- 范围：服务端 `src/` 与仓库内置上游 `packages/postgresql-driver`、`packages/rocksdb_ffi`；外部上游（ignite/brotli_middleware）不改源码，只调整应用侧装配。

## 验收指标（对照实测基线）

| 指标 | 现状 | 目标 |
| :-- | --: | --: |
| `GET /api/tankoubons` | 6.13s | 冷 < 1s，缓存热 < 200ms |
| `GET /api/search`（无词） | 1.43s | < 250ms |
| `GET /api/search?filter=…` | 4~8s | 首查 < 2s，同参 30s 内 < 100ms（结果缓存） |
| `GET /api/info` | 0.58s | < 100ms |
| `GET /api/tags/translations` | 0.56s / 1.4MB | 热 < 50ms；gzip 客户端 < 600KB 传输 |
| `GET /api/tags/cloud` | 0.67s | 热 < 50ms |
| 池满时行为 | 无限排队 | 借出超时（默认 5s）快速失败，可观测 |
| 回归保护 | 无 | 全部修复项有单元测试锁定（慢接口必须带"SQL 次数上限"断言） |

## 第 0 步：测试基础设施（先行，所有修复项共用）

### T1 SQL 计数测试工具（新文件 `src/shared/config/sql_count_test_support.cj`）

利用现成的 `csorm.DatabaseMetric.setMetricCallback`（`database.cj:75` 已示范挂法）：

```text
public class SqlCounter {
    // 安装回调并清零；记录 (sql, count)；提供：
    //   total()                      —— 总执行次数
    //   countOf(contains: String)    —— 含某片段的 SQL 次数（如 "COUNT(*)"、"FROM tankoubons"）
    //   reset() / uninstall()
}
```

测试内用法：`let c = SqlCounter.install()` → 执行被测函数 → `@Expect(c.total() <= 6)`。

这是锁死 N+1 的核心工具：**按"每请求 SQL 条数上限"断言**，而不是只断言结果正确。

### T2 测试数据库种子工具（`src/contexts/tankoubon/infrastructure/persistence/tankoubon_test_support.cj`）

- `seedTankoubonFixture(db, n)`: 建 n 个合集，每个带 2 个 archive + metadata（title/tags/cover asset 占位），1 个 archive 标记收藏、1 个标记已读；返回清理句柄（finally 物理删除，或用独立 schema/事务回滚）。
- 约定沿用 `packages/postgresql-driver/src/driver_test.cj` 的 `openOrSkip()`：连不上测试库时 `println("[skip]")` 并返回，避免 CI 无 DB 时假红。

### T3 ignite 进程内 HTTP 断言（沿用上游 `handleForTest` 模式）

控制器层测试用 `App` + `handleForTest("GET", path)`（ignite `inproc_bind_logger_test.cj` 模式），配合 `DatabaseConfig.initializePool()` 指向测试库。鉴权用测试内造好的 token 行。

### T4 CI 接入

`.cnb.yml` 与 `.github/workflows/build.yml` 增加 server-test 阶段：service 起 `postgres:18-alpine`（healthcheck pg_isready），`DB_STRING` 注入，跑 `cjpm test`（`--parallel nCores --timeout-each 120s`，与 client-next.yml:224 同款参数）。无 DB 的纯单元测试（连接池、编解码）独立标记，允许本地裸跑。

---

## P0 — 根治核心慢接口

### P0-1 `/api/tankoubons` N+1 → 批量 + 缓存

**改动**：`src/contexts/tankoubon/domain/tankoubon.cj:136` `getAllTankoubonsWithUser`：
1. `TankoubonDao.getAllTankoubons()` 只保留基础行（去掉 `:358` 循环内的 `getArchivesInTankoubonWithConnection`）；
2. 聚合元数据改调 `TankoubonDao.getBatchAggregatedMetadata(ids, userId)`（`tankoubon_dao.cj:1260`，带 RocksDB 缓存）；
3. children 改调 `getBatchArchivesInTankoubon(ids)`（`:1403`，带缓存）；
4. 收藏状态改调 `UserTankoubonFavoriteDao.getBatchFavoriteStatus(userId, ids)`（`user_tankoubon_favorite_dao.cj:205`）。
每请求 SQL 从 ~1.15 万条降到 ≤ 5 条。

**单元测试**（`tankoubon_dao_test.cj`，DB 测试）：

| 用例 | 断言 |
| :-- | :-- |
| `getAllTankoubonsWithUserQueryCountTest` | seed 20 个合集；SqlCounter 断言 `total() <= 6`（基线行 1 + 聚合 1 + children 1 + favorite 1 + 版本号 ≤2） |
| `getAllTankoubonsWithUserMatchesPerItemPathTest` | 同数据下，批量结果逐字段等于旧路径 `getTankoubonByIdWithUser`（黄金对照，防语义漂移：tags/pagecount/progress/isnew/isfavorite/cover） |
| `getAllTankoubonsWithUserCacheWarmTest` | 连续两次调用，第二次聚合相关 SQL 为 0（`countOf("tankoubon") 仅剩基础行查询`） |
| `getAllTankoubonsWithUserFavoriteRollupTest` | 收藏合集内任一子 archive → `isfavorite==true`；无 → `false` |
| `tankoubonsEndpointShapeTest`（T3） | `handleForTest("GET","/api/tankoubons")` → 200，`filtered==total==seed 数`，每项含 `children/archive_count/pagecount` |

### P0-2 `/api/search` 无词 COUNT 直查基表

**依据**：`archive_metadata_search` 是 `FROM archives LEFT JOIN metadata... GROUP BY a.id`，无 WHERE 时每行 archive 恰好聚成一行，故 `COUNT(*) FROM archives` 与视图计数恒等，可用索引 only-scan。

**改动**：`archive_dao.cj:765` `searchArchives` 与 `searchArchivesGrouped` 的 countSql：当 `whereConditions` 为空且无 relevance 时，改发 `SELECT COUNT(*) FROM archives`。

**单元测试**（`archive_dao_search_test.cj`）：

| 用例 | 断言 |
| :-- | :-- |
| `noFilterCountUsesBaseTableTest` | 无过滤调用；SqlCounter 断言发出的 SQL 含 `FROM archives` 且不含 `archive_metadata_search` 的 COUNT |
| `noFilterCountEqualsViewCountTest` | seed 后 `searchArchives("","",0,1,...).total` == 直接 `SELECT COUNT(*) FROM archive_metadata_search`（语义等价性黄金断言） |
| `filteredCountStillUsesViewTest` | 带 `filter=xx` / `newonly` 时仍走视图计数（不误改） |

### P0-3 `/api/search` 带词结果缓存（短 TTL + 版本失效）

**改动**：SearchController 对 `(normalized filter, category, sortby, order, flags, page, pageSize, userId)` 计键，结果 JSON 存 `PersistentCacheService`，namespace `search_result`，TTL 30s；归档/标签/合集写路径挂 `DerivedCacheUtils.bumpSearchResultVersion`（复用现有版本机制）。不做 singleflight 的话同名空间版本键即可挡住大部分重复。

**单元测试**：

| 用例 | 断言 |
| :-- | :-- |
| `searchResultCacheHitTest` | 同参两次调用，第二次 `countOf("archive_metadata_search")==0`，返回 JSON 逐字节相等 |
| `searchResultCacheVersionInvalidationTest` | bump 版本后同参调用重新查库 |
| `searchResultCacheKeyNormalizationTest` | `filter=a b` 与 `filter= b a `（同语义不同空格）命中同键；不同 page 不互串 |

### P0-4 `/api/tags/translations`、`/api/tags/cloud` 进缓存

**改动**：`tag_dao.cj:863` `getTranslationsMap(lang)` 与 `:1686` `getTagCloud(lang, limit)` 结果缓存（namespace `tag_translations_map` / `tag_cloud`，TTL 10min）；标签翻译写入、标签字典导入、archive 标签变更处 bump 版本（挂到现有 `DerivedCacheUtils` 模式，新增两个 namespace 常量即可）。

**单元测试**（`tag_dao_cache_test.cj`）：

| 用例 | 断言 |
| :-- | :-- |
| `translationsMapCacheTest` | 二次调用 SQL 为 0；更新某标签翻译并 bump → 新值可见 |
| `tagCloudCacheTest` | 同上模式；`limit` 不同产生不同键 |
| `translationsMapLangIsolationTest` | zh 缓存不污染 en 结果 |

### P0-5 `/api/info` 改简单 COUNT

**改动**：`info_controller.cj:24` `ArchiveDao.searchArchives("", "", 0, 0, ...)` → `SELECT COUNT(*) FROM archives`（DAO 加 `countArchivesFast()`）。

**单元测试**：`infoControllerCountTest`：SqlCounter 断言仅 1 条 SQL 且 `FROM archives`；数值与 `total_archives` 响应一致（T3 handleForTest）。

### P0-6 gzip 压缩补齐

**改动**：`observability.cj:34` 在 brotli 之外叠加 ignite 自带 `compressMiddleware`（gzip/deflate，`minBytes 2048`），并调整 `shouldSkip` 使两者不重复编码：brotli 中间件仅当客户端接受 br 时编码；gzip/deflate 由 compress 中间件兜底。外部上游不改。

**单元测试**（ignite inproc，`compression_middleware_test.cj`）：

| 用例 | 断言 |
| :-- | :-- |
| `gzipNegotiationTest` | `Accept-Encoding: gzip` → `content-encoding: gzip`，gunzip 后等于原文 |
| `brStillPreferredTest` | `Accept-Encoding: gzip, br` → `br`（优先级不回退） |
| `identityPassthroughTest` | 无 AE 头 → 无 content-encoding，body 原样 |
| `smallBodySkippedTest` | < 2048B 不压缩 |
| `sseNeverCompressedTest` | SSE 路径跳过（compress 中间件已内置该判断，断言之） |

---

## P1 — 并发健壮性（上游 `packages/postgresql-driver` + 部署配置）

### P1-1 连接借出超时

**改动**：`pool.cj`：`PoolConfig` 加 `borrowTimeoutMs`（默认 5000，连接串键 `pool.borrowTimeout`）；`borrow()` → `borrow(timeoutMs)`，`cond.wait(timeout)` 超时抛 `PGError(kind=PoolTimeout)`；`connection_pool.cj` 传参并在 503 响应层接住（observability 中间件兜底转 `503` + 告警日志）。

**单元测试**（`pool_test.cj`，**无需数据库**，用假 connect/disconnect 闭包）：

| 用例 | 断言 |
| :-- | :-- |
| `borrowTimesOutWhenSaturatedTest` | maxSize=1，先借走；`borrow(100ms)` 在 100~400ms 内抛超时异常 |
| `borrowWakesOnGiveBackTest` | 饱和后另一线程 `giveBack`，等待者拿到连接 |
| `borrowThrowsOnClosedPoolTest` | `closeAll()` 后 borrow 抛错 |
| `conninfoParsesBorrowTimeoutTest` | `pool.borrowTimeout=2500` 解析进 PoolConfig（扩展 `observability_test.cj:89` 现有断言组） |

### P1-2 借出校验 + 一次重试

**改动**：`ConnectionPool.init` 增 `validate: (CPointer<Unit>) -> Bool`（PGDatabase 传 `PQstatus==CONNECTION_OK`）；`borrow` 弹出空闲连接先 validate，失败则 disconnect、total-1、继续循环。

**单元测试**（假连接）：

| 用例 | 断言 |
| :-- | :-- |
| `borrowSkipsBrokenIdleConnTest` | 空闲栈放 1 坏 1 好；borrow 返回好的，total 减 1，坏连接被 disconnect |
| `borrowReopensWhenAllIdleBrokenTest` | 全坏且未达上限 → 新建 |
| `realDbRestartSurvivalTest`（DB 测试，可跳过） | `SELECT pg_terminate_backend(pid)` 杀掉池内连接后，下一次 query 自动恢复（当前实现会抛错） |

### P1-3 `lastAffected` 改 ThreadLocal

**改动**：`connection.cj:23` `var lastAffected` → `ThreadLocal<Int64>`；`exec` 写、`affectedRows` 读各自线程副本。

**单元测试**：`lastAffectedThreadIsolationTest`：两个 `spawn` 线程各自 `exec("SELECT 1")` 后写不同值再读，互不可见；主线程读不到子线程值。

### P1-4 cancel 目标按线程注册（纠正全局单槽）

**改动**：`connection.cj` 的 `activeConn` 单槽改为 `ConcurrentHashMap<Int64 /*threadId*/, CPointer>` 注册表；`cancel()` 增加目标参数（保持旧签名兼容：默认取消"当前线程的活动查询"）。

**单元测试**（DB，可跳过）：`cancelTargetsOnlyOwnQueryTest`：两线程各跑 `pg_sleep(3)`，cancel 其中一个 → 一个报 57014 取消、另一个正常完成。

### P1-5 池指标真实化

**改动**：`pool.cj` 加 `waiting`、`borrowTimeoutCount` 计数；`connection_pool.cj:161` `stats()` 填真值（去掉 idle 硬编码 0）；接入 `database_metric` 日志（每分钟汇总一行）。

**单元测试**：`poolStatsReflectStateTest`：借 2 还 1 → `open==2, inUse==1`；饱和等待 → `waiting>=1`；超时后 `borrowTimeoutCount==1`。

### P1-6 部署层：`POOL_MAX` 与 `statement_timeout`

**改动**：`connection_pool.cj` 默认 `maxConnections` 10→20；连接串追加 libpq `options=-c statement_timeout=8000`；`.env.example`、`docker-compose.yml` 注释说明。**这是配置变更，需在部署时确认 PG 侧 max_connections 余量。**

**单元测试**：`conninfoIncludesStatementTimeoutTest`（解析断言）；DB 集成 `statementTimeoutKillsLongQueryTest`：`SELECT pg_sleep(10)` 在 ~8s 报 `57014/查询取消`（可跳过）。

---

## P2 — FFI 边界与鉴权路径优化

### P2-1 `materialize` 去重判空 + 惰性列索引

**改动**：`connection.cj:116-124` 先算 `nulls` 数组再填 `vals`（`PQgetisnull` 每格 1 次，省 1/3 FFI）；`row.cj:46-56` 列名 HashMap 改首次 `idx()` 调用时惰性构建（结果集级别共享可选，先做惰性即可）。

**单元测试**：

| 用例 | 断言 |
| :-- | :-- |
| `materializeNullsAndValuesTest`（DB） | `SELECT NULL::text, ''::text, '中文'::text` 三列：isNull/空串/unicode 全对 |
| `rowLazyNameIndexTest` | `PgRowData(names, values)` 构造后 `getText("col")` 正常；同一行多次按名取值一致 |
| `materializePerfSmokeTest`（DB） | 5000 行 × 4 列物化 < 500ms（防回归的烟测，超时即红） |

### P2-2 RocksDB 取值批量拷贝

**改动**：`rocksdb_ffi/src/main.cj:2766` 等 3 处逐字节循环 → `LibC.memcpy` 进 `Array<UInt8>` 原始数据。

**单元测试**（`rocksdb_ffi` 本地，无网络）：`largeValueRoundTripTest`（1MB 随机字节 put/get 全等）；`copyPerfSmokeTest`（1MB 拷贝 < 20ms）。

### P2-3 鉴权 token 查询缓存

**改动**：`auth.cj:232` `getTokenRowByToken`：tokenHash → (userId, tokenId) 存 RocksDB TTL 30s；token 撤销/登出/改密处 bump namespace 版本（写路径已有 `UserTokenDao` 集中点，挂钩即可）。last_used 触达逻辑已有节流，不受影响。

**单元测试**：

| 用例 | 断言 |
| :-- | :-- |
| `tokenLookupCacheHitTest` | 二次校验同 token，`countOf("FROM user_tokens")==0` |
| `tokenCacheRevocationTest` | 撤销 token 并 bump 后，同 token 立即 401（缓存不可见过期窗口） |
| `tokenCacheNoLeakAcrossUsersTest` | 不同 token 不互串 |

### P2-4 搜索视图长期方案（调研项，不阻塞上线）

聚合视图无法被 planner 内联，ILIKE/trgm 索引无法穿透 GROUP BY。备选：(a) 物化列（tags 冗余进 archives 表，写时维护）；(b) MATERIALIZED VIEW + 写路径触发刷新。本计划只做 spike 输出结论，实现另立项。

---

## P3 — 可选微优化（低风险顺手做）

- `@FastNative` 标注 `ffi.cj` 的 8 个 libpq 访问器（`PQgetvalue/PQgetisnull/PQntuples/PQnfields/PQfname/PQftype/PQresultStatus/PQcmdTuples`）；**禁止**标注会阻塞的 `PQexecParams/PQconnectdb` 等（清单见 fastnative-analysis.md 第三节）。验证：CI 加 `cjc -v` 版本检查 + 10 万次调用微基准对比，p50 改善 <2% 则仅保留不扩展。
- `reapIdleLocked` O(n) 头删改栈式弹出（pool_test 加 1000 空闲连接回收计时烟测）。
- `/api/tankoubons` 分页参数（前端 `AddToTankoubonDialog` 渐进迁移，非阻塞）。
- SSE 并发上限与写超时（ignite 未暴露，需上游配合，先在 observability 记录活跃流数）。

## 里程碑与依赖顺序

```
M0 测试基建 (T1-T4)                    —— 独立 PR，先行合入
M1 P0-1 tankoubons  ┐
M1 P0-5 info        ├ 同一 PR：都是"换查询"类改动，风险低，先拿最大收益
M1 P0-2 search计数  ┘
M2 P0-3/P0-4 缓存类（依赖 M0 的 SqlCounter）+ P0-6 gzip
M3 P1-1~P1-3 池健壮性（纯单元可并行开发）→ P1-4/P1-5 → P1-6 部署配置（随下个版本发布）
M4 P2-1~P2-3；P3 择机
```

每个 PR：改动 + 对应测试 + 用 `docs/api-performance-report.md` 的压测脚本对线上 staging 复测一次，把新数据追加进报告的"修复后"章节。

## 回归防线（测试目录总览）

```
packages/postgresql-driver/src/pool_test.cj          # P1-1/2/5，无需 DB
packages/postgresql-driver/src/materialize_test.cj   # P2-1，DB 可跳过
src/shared/config/sql_count_test_support.cj          # T1 工具
src/contexts/tankoubon/infrastructure/persistence/tankoubon_dao_test.cj      # P0-1
src/contexts/archive/infrastructure/persistence/archive_dao_search_test.cj  # P0-2/P0-3
src/contexts/tag/infrastructure/persistence/tag_dao_cache_test.cj           # P0-4
src/infrastructure/middleware/compression_middleware_test.cj                # P0-6（inproc）
src/infrastructure/middleware/auth_cache_test.cj                            # P2-3
packages/rocksdb_ffi/src/main_test.cj（扩充）        # P2-2
```

核心原则：**每个"次数型"修复必须带 SQL 次数上限断言**（SqlCounter），每个"缓存型"修复必须有命中断言 + 失效断言 + 语义黄金对照，防止修完又悄悄退化。

## 风险与回滚

| 风险 | 缓解 |
| :-- | :-- |
| 批量聚合 SQL 与旧逐条路径语义不一致（tags 合并顺序、isfavorite 口径） | P0-1 黄金对照测试逐字段比对；上线灰度开关（`TANKOUBON_BATCH=1` 环境变量，默认新路径，异常可切回） |
| COUNT 换基表后与视图计数出现偏差（脏数据：archive 无 metadata 行仍应计数，LEFT JOIN 语义已覆盖） | P0-2 等价性测试在真实 staging 库跑一次全量比对再上线 |
| 双压缩中间件叠加导致重复编码 | P0-6 中间件顺序测试（br 优先、互斥） |
| statement_timeout 误杀合法慢任务（缩略图批处理等） | 任务跑在独立会话/TaskPool 连接，暂不设 timeout；仅 API 池设置，灰度 8s |
| borrow 超时误伤正常高峰排队 | 默认 5s 较宽松；`PoolTimeout` 计数进指标，观察一周再收紧 |
