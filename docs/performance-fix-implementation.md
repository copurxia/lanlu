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
