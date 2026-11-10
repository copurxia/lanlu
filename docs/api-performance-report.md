# 兰鹿 API 性能实测报告

- 测试日期：2026-11-06
- 测试实例：`https://nas.copur.xyz:3005/`（版本 `1.0.0-feat/plugin-source-setting.006e31b(1.1.0)`）
- 数据规模：13,435 个归档，2,319 个合集（tankoubon）
- 测试方法：curl 对每个读接口连续请求 3~5 轮取均值；SSE 接口用 3s 强制断开测首字节
- 源码比对：已确认部署提交 `006e31b` 与本地分析所涉文件（tankoubon/archive_dao/search/tag/migrations v013）之间无差异，根因分析对线上实例有效

## 基线

同实例上 `GET /api/auth/me`、`/api/categories`、`/api/user/stats` 等约 40 个轻接口，用 curl 单发（每次新建 TLS 连接）稳定在 **55~65ms**；改用 keep-alive 复用连接后同一批接口 **p50 仅 1~6ms**。即约 50ms 是 TLS 握手开销（测试端与实例同局域网，RTT≈1ms），服务端处理本身是毫秒级。下文慢接口的耗时几乎全部是服务端处理时间，不是网络传输。

## 一、实测结果总览

| 接口 | 平均耗时 | 响应体积 | 结论 |
| :-- | --: | --: | :-- |
| `/api/admin/taskpool/tasks` | 30.1s（恒定） | 44KB (SSE) | 首字节 0.15s，实为 SSE 流，非慢接口 |
| `/api/tankoubons` | **6.13s** | 963KB | 严重偏慢（基线 100 倍） |
| `/api/search?filter=test` | **5.9~8.2s** | 17KB | 严重偏慢，带词搜索最慢 |
| `/api/search`（无词） | 1.43s | 10KB | 偏慢（纯 COUNT 成本） |
| `/api/search?groupby_tanks=true` | 1.27s | 20KB | 前端首页默认走此路径 |
| `/api/tags/cloud` | 0.67s | 11KB | 偏慢 |
| `/api/info` | 0.58s | 0.3KB | 偏慢 |
| `/api/tags/translations` | 0.56s | 1,435KB | 体积异常；gzip 客户端拿不到压缩 |
| 其余约 40 个接口 | 0.05~0.11s | — | 正常 |

归档详情、封面、页面图片、files、用户统计、分类、任务列表（非流式）等阅读主链路接口均正常。

## 二、慢接口根因分析

### 1. `/api/tankoubons`（6.1s）—— N+1 查询 + 绕过已有缓存

调用链：`TankoubonController.getTankoubons` → `TankoubonModel.getAllTankoubonsWithUser`（`src/contexts/tankoubon/domain/tankoubon.cj:136`）→ `TankoubonDao.getAllTankoubons`（`tankoubon_dao.cj:304`）。

对返回的 **2319 个合集，每个至少执行 4 次独立 SQL**（单次请求合计约 1.1 万条查询）：

| 每合集的查询 | 位置 |
| :-- | :-- |
| `getArchivesInTankoubonWithConnection`（children 列表） | `tankoubon_dao.cj:282`，由 `getAllTankoubons` 循环内 358 行调用 |
| `getAggregatedMetadata`（聚合元数据，含 3 个 JOIN + 2 次标签子查询） | `tankoubon_dao.cj:997`，由 `applyAggregatedMetadata` 调用 |
| `UserTankoubonFavoriteDao.isFavorite`（收藏状态） | `user_tankoubon_favorite_dao.cj:87`，由 `applyAggregatedMetadata` 调用 |

关键反差：**DAO 中已有 RocksDB 缓存版批量实现 `getBatchAggregatedMetadata`（`tankoubon_dao.cj:1260`）、`getBatchArchivesInTankoubon`（:1403）和 `getBatchFavoriteStatus`（`user_tankoubon_favorite_dao.cj:205`），但只被搜索接口（`SearchController.writeSearchDataArray`）使用；列表接口 `getAllTankoubonsWithUser` 完全没有接入。** 实测连续请求 4 次 `/api/tankoubons` 耗时恒定 6.1~6.2s、无任何缓存预热效应，印证了这一点。

次要问题：接口无分页，一次返回全部 2319 条、963KB。

### 2. `/api/search`（无词 1.4s，带词 4~8s）—— COUNT 对聚合视图全量物化

- 基础原因：`ArchiveDao.searchArchives`（`archive_dao.cj:747`）先执行 `SELECT COUNT(*) FROM archive_metadata_search`。`archive_metadata_search` 是带 `string_agg`、`to_tsvector` 和 GROUP BY 的**非物化视图**（`src/infrastructure/migrations/versions/v013_metadata_time_semantics_unification.cj:216`），每次 COUNT 都对 13,435 个归档做全量聚合。实测 `pageSize=1` 与 `pageSize=20`、第 1 页与第 672 页耗时完全相同，证明成本固定在 COUNT 阶段而非取数阶段。
- 带词搜索的额外放大：
  - WHERE 用 `ILIKE '%term%'` + `unaccent()` 对视图的 title/filename/summary/tags 逐行匹配（`buildArchiveTextMatchCondition`，`archive_dao.cj:189`），无法使用任何索引；
  - 相关度评分 `buildRelevanceExpr`（:675）对每行计算 `ts_rank` + 6 个 ILIKE CASE，且计数、取数各算一遍；
  - 默认 `sortby=title`（`search_controller.cj:386`）对表达式输出做全量排序，无法走索引；
  - 分组模式（前端首页默认 `groupby_tanks=true`）额外 LEFT JOIN tankoubon 三表并按 DISTINCT 组计数（`search_dao` countSql，`archive_dao.cj:1317`）。

### 3. `/api/tags/cloud`（0.67s）—— 标签全量笛卡尔聚合

`TagDao.getTagCloud`（`tag_dao.cj:1686`）对 tags × metadata_tags × metadata_objects 全表 JOIN 后 `COUNT(DISTINCT)` 排序取前 N，无缓存。前端仅在统计页调用（`settings/stats/page.tsx:47`），影响面小，但同样的聚合结果完全可以进 RocksDB 短 TTL 缓存。

### 4. `/api/info`（0.58s）—— 用重量级搜索数总数

`InfoController.getServerInfo`（`info_controller.cj:24`）为拿"归档总数"调用了完整的 `ArchiveDao.searchArchives("", "", 0, 0, "title", "asc")`——即第 2 条里那套 COUNT + 全列 SELECT + 标题排序，而实际只需要一个 `SELECT COUNT(*) FROM archives`。前端有 5 分钟内存缓存（`archive-service.ts:664`），所以只在冷启动/过期时暴露。

### 5. `/api/tags/translations`（0.56s，1.4MB）—— 无缓存全量 + 无 gzip

- 无参数时 `TagDao.getTranslationsMap`（`tag_dao.cj:863`）`SELECT namespace, name, translations FROM tags` 全表加载并在服务端解析 JSON，无缓存。
- 压缩协商缺陷：服务器**只支持 brotli，不支持 gzip**（实测 `Accept-Encoding: gzip` 返回原文 1,435KB，仅 `br` 协商成功时为 523KB）。curl/部分原生 HTTP 客户端与安卓 OkHttp 默认不带 br，会每次拉 1.4MB 原文。

### 6. `/api/admin/taskpool/tasks`（30s）—— 误判澄清

该接口是 SSE 长连接流（`taskpool_controller.cj:26`），30.1s 恒定耗时是客户端 `--max-time`/反代空闲超时掐断连接的表现。实测首字节 0.15s、3 秒内推完 22.9KB 快照，**不是慢接口**。做 HTTP 轮询式压测时不应包含此路径。

## 三、并发能力评估

### 测试方法

- keep-alive 复用连接（排除 TLS 握手噪声），多进程 × 多线程叠加，避免单进程 Python GIL 限制；
- 全部测试 0 个 4xx/5xx、0 个连接错误（过载表现为排队变慢，而不是报错）；
- 详细上游代码问题见 [upstream-concurrency-report.md](./upstream-concurrency-report.md)。

### 实测数据

| 场景 | 并发 | 吞吐 | p50 | p95 |
| :-- | --: | --: | --: | --: |
| `/api/auth/me`（1 连接复用） | 1 | — | 1.0ms | — |
| `/api/auth/me`（4 进程 × 25 线程） | 100 | **1,406 rps** | 10~18ms | 407~768ms |
| `/api/categories`（单进程） | 20 | 537 rps | 20.7ms | 154ms |
| `/api/categories`（4 进程 × 25 线程） | 100 | **388 rps** | 91~95ms | 1.44~1.53s |
| `/api/tags?limit=50` | 10 | 546 rps | 7.2ms | 91ms |
| `/api/search`（3 进程 × 10 线程） | 30 | **5.4 rps** | 4.7~8.2s | 5.3~13.2s |
| 40 路 SSE 常驻时的 `/api/categories` | 5 | 481 rps | 5.9ms | 69ms |
| 搜索压测期间的 `/api/categories` | 5 | 8.6~385 rps | 6.6~367ms | 67~1,731ms |
| 搜索压测期间的 `/api/auth/me` | 5 | 28.8 rps | 7.2ms | 1,631ms |

### 结论

**框架层并发能力不是瓶颈，但业务层有效并发不充足。**

1. **框架本身够用**：轻接口在 100 连接下可跑到约 1,400 rps，40 路 SSE 长连接常驻对轻接口无可见影响（Ignite 路由为 trie、请求处理无全局锁）。这说明 Ignite + stdx Server 不是主要限制。
2. **有效并发被慢查询支配**：`/api/search` 在 30 并发下只有约 5 rps、p50 4.7~8s。10 个用户同时刷新首页，请求就会排到秒级。按单查询 1~2s、池上限 10 推算，搜索吞吐上限约 5~10 rps，与实测一致。
3. **共享池放大影响面**：全站 10 个 DB 连接是共享的（`connection_pool.cj:19`，部署未设置 `POOL_MAX`）。搜索压测进行时，纯读的分类列表 p50 从 6ms 恶化到 367ms、`/api/auth/me` 出现 1.6s 尾延迟——**一个人搜索会拖慢全站**。
4. **没有过载保护**：连接池 `borrow()` 无超时（`postgresql-driver/src/pool.cj:82`），应用与驱动均未设置 `statement_timeout`。过载时请求无限排队，不会快速失败，也不会触发告警。
5. **每请求一次鉴权查询**：每个已鉴权请求都要 `SELECT ... FROM user_tokens WHERE token_hash=$1`（`user_token_dao.cj:88`），占用一次连接借还；慢请求占满池后鉴权请求同样排队。
6. **规模判断**：3~5 人家庭环境、以阅读为主（阅读链路 50ms 内）基本够用；10 人以上并发、或有人使用搜索/打开"加入合集"弹窗（`/api/tankoubons` 6s）时，体验会明显下降。不属于"并发充足"。

### 提升路径（按收益排序）

1. 先修慢查询本身（复用批量缓存、搜索 COUNT 缓存）：搜索吞吐可提升一个数量级，并发问题的根源随之消失；
2. `POOL_MAX` 从 10 上调，并在 PG 侧为 API 会话设置 `statement_timeout`（如 5s），避免慢查询无限占用连接；
3. 搜索加单飞（singleflight）/短 TTL 缓存与限流；`/api/tankoubons` 加分页；
4. 鉴权 token 查询加 RocksDB 短 TTL 缓存；
5. 上游驱动补借出超时、连接校验重试和池指标（详见上游报告）；
6. 压缩补 gzip，减少 1.4MB 级响应在弱网下的传输时间。

## 四、RocksDB 是否被充分利用

**架构上是核心组件，但覆盖面不足，热点路径反而没用上。**

### 现状

- 初始化：启动时 `LocalKVService.initializeFromSettings`（`src/infrastructure/kv/local_kv_store.cj:477`）以 OptimisticTransactionDB 打开 `./data/cache/rocksdb`，参数可由系统设置调整（block cache 64MB、mmap reads 等，`system_settings_service.cj:138`）。打开失败则整体降级为"无缓存模式"，无内存兜底。
- 统一入口：`PersistentCacheService`（带 TTL 记录 + 命名空间版本失效）包装 `LocalKVService`。
- 已接入的场景（10 处消费点）：
  - 归档 assets_raw 批量缓存（`archive_dao.cj:111`，TTL 7 天）——被 `/api/search` 使用；
  - 合集聚合元数据 / children 批量缓存（`tankoubon_dao.cj:187,212`）——仅被 `/api/search` 分组结果使用；
  - 标签翻译搜索缓存（`tag_dao.cj:1136`）——仅缓存"按词搜索翻译"，不覆盖全量 translations；
  - 会话鉴权（`middleware/auth.cj`）、登录限流/TOTP/WebAuthn 挑战（`auth_security_service` 等 16 处）；
  - 任务组 KV（`task_group_kv_store.cj`，v016 迁移后从 PG 迁来）；
  - 归档包索引（`archive_package_index.cj`）。

### 未充分利用的证据与缺口

1. **最慢的 `/api/tankoubons` 完全绕过 RocksDB**：批量缓存实现就在同一个文件里（`tankoubon_dao.cj:1260`），列表接口却走逐条 SQL。这是"建了高速路没通车"的典型——实测重复请求无任何预热效应。
2. **搜索主链路零缓存**：`searchArchives` / `searchArchivesGrouped` 全文无任何 PersistentCacheService 调用，COUNT 对聚合视图的全量物化每次重算。
3. **全量 translations、tags/cloud 无缓存**：已有命名空间版本失效机制（`derived_cache_utils.cj`）可直接复用，写回成本低。
4. **`/api/info` 绕过**：总数完全可以放 KV 缓存或改用简单 COUNT。
5. 客户端（client-next）倒是把 RocksDB 用得较充分（离线缓存、页面存储、标签翻译缓存等 7 个 store），服务端与客户端的利用度形成反差。

### 建议（按收益排序）

1. `getAllTankoubonsWithUser` 改用已有的 `getBatchAggregatedMetadata` + `getBatchArchivesInTankoubon` + `getBatchFavoriteStatus`，预计 6.1s → 亚秒级（纯代码复用，改动集中在一个函数）。
2. `/api/search` 无词路径用近似计数或缓存 COUNT 结果（按命名空间版本失效）；`/api/info` 改简单 COUNT。
3. 给 `getTranslationsMap`、`getTagCloud` 加 RocksDB 缓存，写失效挂到标签变更处（版本机制已就绪）。
4. 服务端补 gzip 压缩（目前仅 br），或前端/客户端确认始终带 `Accept-Encoding: br`。
5. `/api/tankoubons` 增加分页参数（接口已返回 filtered/total 字段，前端 `AddToTankoubonDialog` 等调用方可渐进迁移）。

## 五、测试记录

<details>
<summary>原始计时数据（节选）</summary>

```
基线:  /api/auth/me 0.057s | /api/categories 0.060s | /api/user/stats 0.056s | /api/tags 0.062s

/api/tankoubons            6.13s (min 5.98 max 6.28, 963KB)  ×4 次重复 6.12/6.12/6.24/6.22 无预热效应
/api/search                1.43s (min 1.26 max 1.74, 10KB)
/api/search?pageSize=1     1.30~1.47s
/api/search?filter=test    7.41/7.18/5.87s；groupby_tanks=true 4.0~4.4s；false 7.8~8.2s
/api/search?page=500/672   1.20~1.32s（与首页相同 → 成本在 COUNT）
/api/tags/cloud            0.67s | /api/tags/translations 0.56s 1435KB
/api/info                  0.58s | /api/user/trend 0.058s
压缩协商: AE=gzip → 1435KB 原文; AE=br → 523KB (content-encoding: br)

/api/admin/taskpool/tasks (SSE): ttfb 0.116~0.159s, 3s 内推 22931B 快照
阅读链路: /api/archives/:id/metadata 0.057s | files 0.113s | cover 0.052s | page?path=… 0.055s (66KB) | /api/assets/:id 0.063s

并发（keep-alive，多进程叠加，0 错误）:
/api/auth/me        c=1    p50 1.0ms
/api/auth/me        c=100  1406 rps  p50 10~18ms  p95 407~768ms
/api/categories     c=20   537 rps   p50 20.7ms   p95 154ms
/api/categories     c=100  388 rps   p50 91~95ms  p95 1.44~1.53s
/api/tags?limit=50  c=10   546 rps   p50 7.2ms    p95 91ms
/api/search         c=30   5.4 rps   p50 4.7~8.2s p95 5.3~13.2s
40 路 SSE 常驻同时 /api/categories c=5: 481 rps p50 5.9ms p95 69ms（无挤占）
30 并发搜索同时 /api/categories c=5: p50 6.6~367ms / p95 67~1731ms（随压测节奏波动）
30 并发搜索同时 /api/auth/me   c=5: p50 7.2ms / p95 1631ms
```

</details>
