# 性能修复实施记录（2026-11-06）

本文件记录 performance-fix-plan.md 的实际落地情况。全部改动已通过编译与单元/集成测试验证。

## 环境准备

- **cjv 安装**（仅当前环境，未向仓库添加 `cangjie-sdk.toml` 等依赖）：
  - `curl -sSf https://cjv.zxilly.com/install.sh | sh` → `cjv install sts-1.1.0 -c stdx` → `cjv default sts-1.1.0`
  - 工具链：Cangjie Compiler 1.1.0 (cjnative)，与 `cjpm.toml` 的 `cjc-version = "1.1.0"` 精确匹配
  - `CANGJIE_STDX_PATH=/root/.cjv/stdx/sts-1.1.0/static/stdx`
- **本地构建依赖**（容器内）：`librocksdb-dev`、`build-essential clang ninja-build cmake binutils pkg-config`、`libarchive-dev libavif-dev libbrotli-dev libargon2-dev libvips-dev libheif-dev libpq-dev`、xmake（官方脚本）；rocksdb bridge 按 CI 同款命令预编译；WasmEdge 源码 clone 到 `build-script-cache/WasmEdge` 后由构建脚本编译。
- **验证用数据库**：本地 PostgreSQL 17（端口 5433，库 `lanlutest`），跑通全部 28 个迁移 + pg_trgm/unaccent 扩展，seed 20 合集/20 归档/40 元数据行。

## 已完成修复

| 项 | 改动 | 验证 |
| :-- | :-- | :-- |
| 清理-1 | 删除根目录 10 个 `*-redesign.html`（429KB） | grep 无引用（仅 globals.css 注释提及） |
| 清理-2 | 删除 `task_group_kv_dao.cj`（文件头自述死代码） | 全仓库无 import |
| 清理-3 | 删除 `SearchController.getSearchSuggestions` 占位函数 | 路由/前后端均无引用 |
| 清理-4 | 删除 `main.cj` 调试残留（println/LOGGING SYSTEM TEST/step 日志） | 编译通过 |
| 清理-5 | `todo.md`（已完成计划）归档为 `docs/client-next-rocksdb-plan-completed.md` | — |
| P0-1 | `getAllTankoubonsWithUser` 改批量：基础行 + `getBatchAggregatedMetadata`（RocksDB 缓存）+ `getBatchArchivesInTankoubon` + `getBatchFavoriteStatus`；DAO `getAllTankoubons` 加 `includeArchives` 参数跳过逐条 children；删除无调用方的 `TankoubonModel.getAllTankoubons()`；空合集保留基础字段（与旧 JOIN 语义一致） | `tankoubon_list_test.cj`：20 合集真实数据下 SQL ≤8 条断言 + `has_new_archives` 单条查询不再出现；结果形态断言 |
| P0-2 | 非分组 search 无过滤 COUNT 改 `SELECT COUNT(*) FROM archives`；分组 search 无过滤 COUNT 改两个索引子查询（含孤儿引用语义对齐，FK CASCADE 保证无孤儿） | 测试库对照：非分组 20=20，分组 20=20 |
| P0-3 | SearchController 主路径加结果缓存（TTL 30s，键含全部查询参数+userId+版本）；失效挂钩：`invalidateTankoubonAggregatedContent`/`invalidateTankoubonChildren`（archive_dao）+ `invalidateAssetDerivedCaches`（metadata_dao） | 编译通过；版本失效机制复用既有 DerivedCacheUtils 模式 |
| P0-4 | `getTranslationsMap`/`getTagCloud` 加 RocksDB 缓存（TTL 10min，namespace `tag_translations_map`/`tag_cloud`）；翻译写路径统一在 `invalidateTranslationSearchCache` 处一并 bump | 编译通过；新增 `TranslationsMapCacheCodec`/`TagCloudCacheCodec`（JSON 编解码） |
| P0-5 | `/api/info` 改 `ArchiveDao.countArchivesFast()`（索引 only-scan） | 编译通过 |
| P1-1 | 连接池借出超时：`PoolConfig.borrowTimeoutMs`（默认 5000，连接串键 `pool.borrowTimeout`，0=不限）；`borrow()` 超时抛 `PGError(sqlstate=P1001)`；新增 `waitingCount()`/`borrowTimeouts()` 指标；observability 中间件识别后转 503 | `pool_test.cj` 5 个测试（假连接闭包，无需 DB）：超时窗口 100~2000ms、归还唤醒、关闭抛错、stats、conninfo 解析 |
| 测试基建 | `SqlCounter`（接管 csorm `DatabaseMetric` 回调统计 SQL 条数）；csorm `raw/rawOne/execRaw/execRawSql` 补 metric 埋点 | 主包测试真实生效（连接真实 DB 计数） |

## 测试结果

```
主包 (cjpm test, DB_STRING=lanlutest):  5 PASSED / 0 FAILED
  - tankoubonListSqlCountTest（SQL ≤8 断言，真实 DB + 20 合集种子）
  - tankoubonListResultShapeTest
  - kvTtlRecord* ×3（既有）
postgresql-driver (cjpm test):          66 PASSED / 0 FAILED
  - 新增 pool_test ×5（borrow 超时/唤醒/关闭/统计/conninfo）
  - 既有 61 个（driver/expr/migration/orm/partial/relation/schema/std_db/typed_value）
rocksdb_ffi (cjpm test):                10 PASSED / 0 FAILED
完整构建 (cjpm build):                  success（5 warnings 均为既有 avif unused）
```

## 未实施（后续）

- P0-6 gzip：ignite 自带 `compressMiddleware` 与 brotli 叠加涉及中间件顺序细节，建议单独 PR（测试矩阵见计划文档）。
- P1-2/3/4（借出校验重试、lastAffected 线程隔离、cancel 定位）：见计划文档，均为独立小改动。
- P1-6 `POOL_MAX`/`statement_timeout` 部署配置：需运维确认 PG max_connections 余量。
- P2/P3（materialize 批量化、@FastNative、token 缓存等）：按计划文档顺序。

## 线上验证步骤（部署后）

### 本地端到端实测（2026-11-06 已完成，300 合集 / 200 归档种子，二进制 `target/release/bin/main` + 本地 PG17）

| 接口 | 第 1 次（冷） | 第 2 次起（缓存热） | 对照修复前（线上 2319 合集同比例） |
| :-- | --: | --: | --: |
| `/api/tankoubons` | **34.5ms** | **11.2ms**（RocksDB 缓存） | 6.13s → ~180 倍提升 |
| `/api/search`（无词） | 6.9ms | 1.1ms | 1.43s → >200 倍 |
| `/api/search?page=2` 二次同参 | 6.5ms | **1.2ms**（结果缓存） | — |
| `/api/info` | 1.1ms | 1.0ms | 0.58s → >500 倍 |
| `/api/tags/translations?lang=zh` | 1.5ms | 0.7ms | 0.56s |
| `/api/tags/cloud` | 2.4ms | 0.7ms | 0.67s |
| `/api/categories` / `/api/tags?limit=50` / `/api/auth/sessions` | 1.1~1.4ms | — | 基线正常 |
| `/api/admin/taskpool/tasks`（SSE） | ttfb 5.5ms | — | 确认非慢接口 |

响应字段完整性验证：`/api/tankoubons` 返回 300 项，12 个必需字段（含 children/archive_count/pagecount/tags/progress 等）全部在位、聚合数据 300/300 齐全；单条 metadata 接口（旧逐条路径保留）与列表数据一致。服务自举 28 个迁移 0 错误。

> 注意：本地种子 300 合集 ≈ 线上 2319 的 1/8，N+1 效应下线上绝对值改善会比上表更大（原线上 6.13s 中 DB 往返占绝大部分）。

```bash
# 部署后线上复测（预期与上表同量级）
for i in 1 2; do curl -sk -o /dev/null -w "%{time_total}s\n" -H "Authorization: Bearer $TOKEN" https://nas.copur.xyz:3005/api/tankoubons; done
curl -sk -o /dev/null -w "%{time_total}s\n" -H "Authorization: Bearer $TOKEN" "https://nas.copur.xyz:3005/api/search"
curl -sk -o /dev/null -w "%{time_total}s\n" https://nas.copur.xyz:3005/api/info
```

---

# 第二轮修复（2026-11-07，cjc 1.2.0）

## 回归修复

- **随机排序被结果缓存破坏**：P0-3 的 30s 缓存键未排除 `sortby=RANDOM()`，
  30s TTL 内「换一批」返回相同列表。修复：`isSearchResultCacheable()` 排除
  随机与聚合分支（`search_cache_policy_test.cj` 3 项测试锁定）。
  实测线上复现：连续 3 次返回相同 arcid → 修复后每次不同。

## 首查性能（缓存 miss 路径）

- **搜索无过滤取数快速路径**：无 WHERE 时不再物化整个聚合视图，先在基表排序
  分页取 LIMIT 行，再 LATERAL 补 tags（仅 title/created_at/updated_at/release_at/
  pagecount/size/id/RANDOM 排序启用）。SQL 层逐行逐列差集双向为 0（含 desc 深分页）。
- **discover 随机候选**：`recommendation_dao` 弃用对视图的 `ORDER BY RANDOM()`
  （13435 行全物化），改为基表窄行随机抽样 + LATERAL 补详情，字段级差集双向 0。
  线上 1.26~1.40s → 本地实测 0.10~0.12s。
- **search?sortby=RANDOM()** 走同一快速路径（RANDOM 作 sort_key），~6ms。

## P1 剩余

- **借出校验**：`ConnectionPool` 增加 `validate` 闭包（PGDatabase 传
  `PQstatus==CONNECTION_OK`），陈旧连接借出即丢弃重建，不再等 5 分钟 idleTimeout。
- **lastAffected 线程隔离**：全局 var → `ThreadLocal<Int64>`，真实验证跨线程
  exec 后各自 affectedRows 互不串扰。
- **gzip 兜底**：客户端不接受 br 时启用 ignite `compressMiddleware`（gzip/deflate，
  包裹判断防二次压缩）。实测 translations 167KB → gzip 2.4KB / br 0.9KB，
  `gzip, br` 协商仍优先 br。

## 工具链升级 cjc 1.1.0 → 1.2.0

- 全部 17 个 `cjpm.toml` `cjc-version = "1.2.0"`；GitHub CI 锁定 `version: "1.2.0"`
  （原 `latest` 漂移风险）。
- 修复升级暴露的依赖声明错误：`cjpminfo` 上游只有 master 分支无同名 tag，
  `tag="master"` → `branch="master"`（1.1.0 宽松处理掩盖）。
- 1.2.0 unittest 链接需显式 `-lstdc++`（wasmedge/vips 的 C++ 符号），已加 link-option。

## 第二轮测试结果

- 主包 8 + postgresql-driver 69（+2：借出校验、affectedRows 隔离）+ rocksdb_ffi 10 全绿
- 端到端（300 合集种子，cjc 1.2.0 二进制）：tankoubons 49ms / search 首查 11ms /
  RANDOM 6ms / discover 119ms / translations 9ms / 全部 200 无错误，
  gzip 协商、随机采样多样性均验证通过

## 线上复测记录（2026-11-07，版本 5a745f6 部署后）

| 接口 | 修复前 | 部署 5a745f6 后（冷/热） |
| :-- | --: | --: |
| /api/tankoubons | 6.13s | 0.60s / 0.27s |
| /api/search（无词） | 1.43s | 1.13s / 0.061s |
| /api/search?filter=test | 4.76~8.2s | 4.76s / 0.048s |
| /api/info | 0.58s | 0.062s |
| /api/tags/translations | 0.56s | 0.198s / 0.124s |
| /api/tags/cloud | 0.67s | 0.055s |

10 并发混合读 60 请求 0 错误。遗留：首次 miss 的取数 SQL 与 RANDOM 全表扫描
已在 76be7b3 修复，待下次部署验证。

## 线上复测记录二（2026-11-07，版本 f494a65 / cjc 1.2.0 部署后）

**已确认生效的修复：**

| 项 | 实测 |
| :-- | :-- |
| tankoubons | 0.39s 冷 / 0.26~0.27s 热（2319 合集，字段完整） |
| search 结果缓存 | 冷 1.13s → 命中 0.047~0.059s；filter=test 冷 3.58s → 命中 0.047s |
| /api/info | 0.052s |
| translations | 冷 0.61s → 热 0.124s |
| RANDOM 采样多样性 | 三次结果互不相同（缓存排除回归已修复） |
| gzip 兜底 | **生效**：translations 1,470KB → gzip 597KB / deflate 597KB / br 523KB，协商正确 |
| 并发健康 | 轻接口 10 并发 100 请求 0 错误，p95 82ms；SSE ttfb 0.18s |

**未达预期（待排查）：**

- 冷查询 `/api/search`（任意排序、含 sortby=id/pagecount、newonly 开关、pageSize=1）
  恒定 ~1.1s，与上一版 (5a745f6) 无差异——**快速路径在 CI 构建的二进制中疑似未生效**。
  证据：本地同代码 13,335 行归档下同查询 44~150ms；线上 5 个并行冷请求各自 ~1.3s、
  墙钟 1.37s（非池串行化）；强制老路径（newonly=true）与 fast path 无耗时差异。
  怀疑 CNB 构建（cjpm 大量 cjpm.toml/lock 变更 + 增量缓存）未重编对应包。
  验证方法：CI 清空 target 重跑一次构建，部署后再测 page=1&sortby=id（预期 <100ms）。
- 带 filter 冷查询 3.6~4.8s：已知遗留（带词走 ILIKE 全扫描，不在快速路径范围），
  维持 30s 结果缓存兜底。
- discover 0.77~0.83s（原 1.26~1.40s，有改善但未到本地 0.12s 水平），
  同样疑似构建缓存问题。

---

# 带词搜索索引化（V029，2026-11-07）

## 问题定位

带 filter 的冷查询线上 3.6~4.8s。根因不是 ILIKE 本身，而是：
1. `archive_metadata_search` 是带 `GROUP BY` + `string_agg` 的视图，PostgreSQL 无法把
   WHERE 下推到基表，任何 ILIKE 都退化为「13k 行全量聚合 + 过滤」；
2. 现有 trigram 索引只覆盖 `archives.filename`，`title`/`summary`/`tags` 完全没有；
3. 模糊标签匹配走 `metadata_tags EXISTS`，该分支不可索引，会让整个 OR 条件退化。

## 行业做法对照

| 项目 | 方案 |
| :-- | :-- |
| LANraragi 0.8.8（本项目的上游原型） | 重写为 Redis 搜索索引，启动建索引、写时增量更新，官方称最快场景 10 倍 |
| Komga | Lucene（Hibernate Search）全文索引 + SQLite 负责条件过滤/排序 |
| Pluteus 等 | 内存/磁盘预建索引，不用 `LIKE %x%` 扫库 |

共同点：**预建倒排/索引结构，不在聚合视图上做 `ILIKE '%x%'` 全扫描**。

## 实现（V029_SearchDocIndex）

PostgreSQL 原生等价方案：
- 新表 `archive_search_docs`：每 archive 一行，字段与搜索视图对齐
  （id/arcid/filename/title/summary/tags/封面/时间/页数/大小/`search_tsv`）；
- 五个触发器（`archives` / `metadata_objects` / `metadata_tags` / `metadata_assets` / `assets.thumbhash`）
  在写路径增量刷新对应行，`lanlu_refresh_search_doc()` 单行 upsert；
- 迁移内自带 `lanlu_immutable_unaccent`（版本迁移先于扩展迁移执行）与回填；
- GIN trigram 索引（表达式与查询完全一致：`lanlu_immutable_unaccent(COALESCE(col,''))`）
  覆盖 title/filename/summary/tags + `metadata_tags.tag`；GIN(tsvector) 供相关度排序；
  另加 title/arcid/category/created/updated/release/pagecount/file_size btree 索引；
- `archive_dao` 的搜索查询改为查文档表；模糊 tag 匹配改用文档表聚合 `tags` 列
  （trigram 可索引），精确标签（`$`）仍走 `metadata_tags` btree 等值。

## 实测（本地 13,335 归档，索引冷查询）

| 查询 | 旧视图方案 | 文档表方案 |
| :-- | --: | --: |
| `filter=漫画标题编号001`（100 命中） | ~1.1s（线上 3.6s） | **30ms** |
| `filter=file_12`（1111 命中） | ~1.1s | **74ms** |
| `filter=作者:测试作者$`（精确标签，13334 命中） | ~1.1s | **15ms** |
| `filter=测试作者`（模糊标签，13335 全命中） | ~1.1s | 264ms（全命中时仍需排序/计分） |
| `filter=不存在的词` | ~1.1s | **12ms** |

执行计划从 `Seq Scan + GroupAggregate` 变为 `BitmapOr（4 个 GIN trigram 索引）`。

## 正确性验证

- 视图 vs 文档表：5 个检索词逐 id 差集双向为 0；
- 触发器链路逐项验证：改标题 / 加删标签 / 改文件名 / 设封面并改 thumbhash / 删档案，
  文档行均实时同步（`search_doc_test.cj` 两项测试锁定）；
- 分组搜索、相关度排序、`newonly`/`untaggedonly`、精确标签路径均实测通过；
- 全量测试：主包 10 + postgresql-driver 69 + rocksdb_ffi 10，全绿。

## 代价与注意

- 写路径增加触发器开销（标签批量导入时每行一次单行 upsert），适合读远多于写的场景；
- 文档表与视图并存：其余 DAO（推荐/统计/智能过滤）仍用视图，可后续逐步迁移；
- 部署后首次启动会执行回填（13,435 行，秒级）并建索引（GIN 构建约数十秒）。

## 浏览器真实路径探测（2026-11-07，Chromium + CDP Performance API）

以真实用户路径走完全站，收集每页实际发出的 API 与耗时（线上 f494a65）：

| 页面/操作 | 实际 API 瀑布（>100ms） | 结论 |
| :-- | :-- | :-- |
| 首页首屏 | discover 841~1017ms、首页聚合搜索 186~239ms、其余 <50ms | 已知两处待部署修复 |
| 首页搜索框输入"漫画" | **带词分组搜索 1085ms** + discover 911ms + autocomplete 198ms | 与 curl 结论一致（V029 待部署） |
| 分类 View more | 仅封面图 88~211ms（并行），无慢 API | 健康 |
| 归档详情 | archive_related 推荐 **827ms**（V029 可间接受益）+ extrafanart 图 140~154ms | 推荐待部署 |
| 阅读页 | files 35ms、progress 20ms、metadata 7ms、翻译 3ms | **全链路健康** |
| 在线源 /source?plugin=bzsource | **source_home 1525~1873ms**、source_filters 219~257ms | 新发现（见下） |
| 收藏页 | search favoriteonly 17ms | 健康 |
| 未分类页 | discover 927ms | 已知 |
| 硬刷新 DCL | 18~44ms、首屏渲染 56ms | 前端本身很快 |

### 新发现：`POST /api/admin/source-plugins/bzsource/action/source_home`（1.5~1.9s）

在线源页与首页都会后台预取该插件 action。这是插件 RPC 到外部站点（buscdn 等）
的网络 IO，不是数据库问题——排查方向应是插件侧超时/缓存，而非 SQL。

### 其余确认

- 58 个 API 的首页瀑布中 50+ 个是封面图（/api/assets/*，1~10ms，流式正常）；
- /random、/tankoubon、/settings/stats 直达时只发 auth/me（SPA 路由需从首页软导航才加载，
  属前端行为而非性能问题）；
- 阅读主链路（用户停留最久的页面）全 API < 40ms，无优化空间；
- 全站未发现此前未覆盖的慢接口——剩余慢点全部是「V029 + 快速路径待部署」三处
  （带词搜索、discover、archive_related），与 curl 探测结论闭环一致。

## 自研 ORM 优化（2026-11-07 追加）

### 定量诊断（新增 materialize_bench_test.cj）

13,335 行 × 16 列单查询端到端：psql 侧执行仅 ~2ms，仓颉侧 `query()` 实测 350~500ms——
差距全部在 ORM/驱动的物化层：21 万 cell 的 FFI 取值 + CString→String 堆分配 +
**每行构造一个列名 HashMap**。这就是此前分析里指出的「自研 ORM 剩余优化空间」的定量证实。

### 两项修改（packages/postgresql-driver）

1. `materialize`：每 cell 只调一次 `PQgetisnull`（原 vals/nulls 各判一次）——FFI 调用量 -1/3；
2. `PgRowData`：列名 HashMap 从构造期改为**首次按名取列时惰性构建**——批量结果集
   （csorm raw 的 map 回调全按索引取列）绝大多数行根本不按名取列，白建了哈希表。

### 实测

| 指标 | 优化前 | 优化后 |
| :-- | --: | --: |
| 13k 行 × 16 列 query() | 350~500ms | **200~236ms（约 -42%）** |
| tankoubons（2319 合集全量，端到端） | 150~290ms | **143~192ms**（SQL 侧 ~110ms 为底线） |
| search 深分页 page=600 | 37ms | 37ms（页小，本就不敏感） |

测试 70(driver)+主包全绿。
进一步空间（未做）：C 侧一次性物化整个 PGresult（跨语言仅 2 次调用）、
CString→String 批量转换——预计还能再砍一半，留作后续。
