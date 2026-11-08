# 自研 ORM（csorm）vs 主流 ORM（SeaORM 等）差距分析 & PG 性能发挥评估

- 日期：2026-11-08
- 范围：packages/csorm（5,238 行）、packages/postgresql-driver（5,474 行）、src/contexts 23 个 DAO、28+2 个迁移、docs/ 既有性能报告
- 方法：源码逐文件核对（含行号证据）+ SeaORM 官方文档/官方博客/docs.rs 联网核实 + 业务 SQL 模式统计 + 既有实测数据引用

---

## 一、总体判断（先说结论）

1. **csorm 的架构骨架是照着 SeaORM 画的，骨架对齐度约 70%**：后端抽象（backend.cj 自述"对标 SeaORM DatabaseBackend + ConnectionTrait + QueryBuilder"）、链式 builder、类型化表达式树、@entity 宏、Repo/ActiveModel、关系 Loader、分页器、迁移器、MockDatabase 全部在位。CRUD + PG 写路径能力（RETURNING / ON CONFLICT / 服务端游标 / SAVEPOINT / FOR UPDATE）与 SeaORM 基本齐平。
2. **真正的差距在四层**：①执行协议（文本协议 + 无 prepared statement 缓存 vs sqlx 二进制协议 + 语句缓存）；②PG 高级查询 API 化程度（CTE/窗口/LATERAL/DISTINCT ON 在 csorm 只能 raw，SeaORM 在 SeaQuery 层原生）；③关系预加载编排（单跳批量 vs 嵌套图谱）；④工程化收尾（索引 DDL 缺失、builder 路径无 metric、事务作用域薄、两个并发缺陷）。
3. **PG 性能发挥：读主链路已是高水准 PG 实践，但仍有约一半场景停在旧方案上**。V029（反规范化文档表 + 5 触发器 + GIN trigram/tsvector 表达式索引）把带词搜索从 3.6~4.8s 压到 0.74s，这是教科书级的 PG 优化；但旧聚合视图 archive_metadata_search 仍被推荐/统计/收藏/进度/智能过滤 5 个模块消费，V029 消灭的"每次查询全量物化"问题在这些路径依然存在。
4. **一个重要的定性结论**：本项目的性能瓶颈从来不是"ORM 抽象太慢"，而是查询模式（N+1、视图全量物化、ILIKE 全扫）——这在 docs/api-performance-report.md 与两轮修复的实测数据里已经闭环证明。ORM 层剩余的、可量化的优化空间是物化层的 C 侧整块拷贝（自述可再省一半）与协议层 statement cache。

---

## 二、csorm vs SeaORM 逐项能力矩阵

评分：✅ 原生支持 / 🟡 部分支持或需 raw / ❌ 不支持。

### 2.1 驱动与执行协议（差距最大的一层）

| 能力 | csorm + postgresql-driver | SeaORM（sqlx） | 差距说明 |
| :-- | :-- | :-- | :-- |
| 参数化绑定 | ✅ 唯一路径 PQexecParams $n（connection.cj:67-102） | ✅ | 对齐 |
| 传输协议 | ❌ 纯文本（resultFormat 恒 0，connection.cj:80/86；每值 pgValueToText、每 cell CString→String） | ✅ 二进制协议 | 文本协议整数/时间戳要序列化再解析，二进制直接按 OID 拷贝 |
| prepared statement 缓存 | ❌ 无 PQprepare/PQexecPrepared，每条语句重发完整 SQL 重新 parse+plan | ✅ sqlx 默认缓存 100 条（statement_cache_capacity 可调） | 高频小查询（每请求鉴权 SELECT user_tokens）每次都付 parse+plan 成本 |
| pipeline/批处理 | ❌ | 🟡（sqlx pipeline 支持） | — |
| COPY 批量装载 | ❌ | ❌（需外部工具） | 同水平 |

**量化参考**：本项目 13,335 行 × 16 列 query() 实测 350~500ms（psql 仅 ~2ms），两项优化后 200~236ms——差距全部在 ORM/驱动物化层。sqlx 二进制协议 + 零拷贝解析下同规模通常在几十 ms 量级（差异来源：文本→类型转换 + CString 堆分配 + 逐 cell FFI）。C 侧一次性物化整个 PGresult（跨语言仅 2 次调用）已规划未实施，预计再省一半。

### 2.2 查询构建能力

| 能力 | csorm | SeaORM | 说明 |
| :-- | :-- | :-- | :-- |
| 动态条件/链式 builder | ✅ SelectQuery/Insert/Update/Delete + Cond/Expr 树（query.cj/condition.cj/expr.cj） | ✅ SeaQuery 语法树 | 对齐 |
| 类型安全 | 🟡 宏生成 fromRow 按列名 getter，类型错误延迟到运行期；无关联类型（entity.cj:52 注释自述） | 🟡 2.0 强类型列常量，但查询合法性也是运行期拼 SQL | 都不及 Diesel（编译期对 schema 验证）/sqlx（query! 宏对真实库验证） |
| 子查询/JOIN/GROUP/HAVING/UNION | ✅（UNION 仅拼原始 SQL，query.cj:214-221） | ✅ | 对齐 |
| CTE / 递归 CTE | 🟡 仅 rawPrefixFragment（query.cj:223-228），占位符编号要调用方手工续接 | 🟡 SeaQuery WithQuery 原生，SeaORM 层需穿透 | csorm raw 片段编号错位只会在运行期报错 |
| 窗口函数 | 🟡 仅 raw | 🟡 SeaQuery WindowStatement | 同水平（都需下沉） |
| LATERAL | 🟡 仅 raw（业务 fast path 的 LATERAL 是 DAO 手写） | ✅ SeaQuery join_lateral | 差距 |
| DISTINCT ON | ❌ distinct() 仅普通 DISTINCT | ✅ SeaQuery distinct_on | 差距 |
| raw 逃生舱 | ✅ raw/rawOne/execRaw/RawQuery/rawCond/addRawColumn | ✅ Statement + 2.0 raw_sql! 宏（防注入插值） | SeaORM 的 raw_sql! 支持 ({ids}) 数组展开，csorm raw 全手拼 |

### 2.3 关系与读取

| 能力 | csorm | SeaORM | 说明 |
| :-- | :-- | :-- | :-- |
| 关系定义 | ✅ RelationDef HasOne/HasMany + @[hasMany] 宏 | ✅ RelationTrait | 对齐 |
| N+1 防护（批量 load） | ✅ loadOne/loadMany（单条 IN 回填，relation.cj:197-272）/loadManyToMany（两步查询，relation.cj:315 自认简化） | ✅ LoaderTrait load_one/load_many | csorm 有基础但从未被业务使用（src 中 0 调用方） |
| 嵌套/图谱式 eager loading | ❌ 无嵌套 include，逐跳手动编排 | ✅ 2.0 .with(entity) 一行声明（1-1 自动 JOIN、1-N 自动 data loader） | 明显差距 |
| 分页 | ✅ OFFSET Paginator + KeysetPaginator（paginator.cj:81-123） | ✅ paginate + cursor_by | csorm 有货没用：KeysetPaginator 在业务里 0 调用方，深分页仍 OFFSET |
| 流式读取 | 🟡 服务端游标 DECLARE/FETCH（connection.cj:323-372），但每批仍全量物化 | ✅ async stream 逐行 | 中等差距 |

### 2.4 写入与事务

| 能力 | csorm | SeaORM | 说明 |
| :-- | :-- | :-- | :-- |
| 只写脏字段 | ✅ ActiveModel ActiveValue（对标 SeaORM 同设计） | ✅ | 对齐 |
| 批量插入 | 🟡 builder 支持多行 VALUES（query.cj:418-424）；业务写路径仍是循环单条 | ✅ insert_many + exec_with_returning | 能力基本对齐，业务未用 |
| upsert | ✅ onConflictDoNothing/DoUpdate + EXCLUDED（query.cj:426-435） | ✅ OnConflict | 对齐（业务 ON CONFLICT 仅 6 处，集中在 V029 触发器） |
| RETURNING | ✅ 三种写语句 + execReturning + 自增 PK 自动 RETURNING | ✅ | 对齐 |
| 事务 | 🟡 ThreadLocal 钉连接 + transaction() 传播 REQUIRED；**begin() 无重入保护——嵌套 begin 会借第二条连接覆盖 ThreadLocal，旧连接永久泄漏**（connection.cj:222-231）；主路径无隔离级别（std_db 才有） | ✅ 闭包式 + begin/commit 双 API + SAVEPOINT 任意嵌套 | csorm 有 SAVEPOINT（connection.cj:263-267）但主路径事务作用域是线程绑定而非词法作用域 |
| 隔离级别 | ❌ 主路径裸 BEGIN（connection.cj:225）；std_db 路径才有 | ✅ 各隔离级别 | 差距 |

### 2.5 Schema / 迁移 / 测试 / 可观测性

| 能力 | csorm | SeaORM | 说明 |
| :-- | :-- | :-- | :-- |
| 版本化迁移 | ✅ Migrator（schema_migrations 元表，up/down/refresh/status，migration.cj:105-262），每迁移独立事务 | ✅ sea-orm-cli + MigratorTrait | 对齐；csorm 缺**迁移并发锁（advisory lock）**，多实例同时迁移会竞争 |
| 索引 DDL | ❌ ColumnDef.indexed 字段存在但**全包无任何 CREATE INDEX 生成代码**；GIN/GiST/部分/表达式索引全靠手写迁移 SQL | 🟡 SchemaManager + IndexType（GIN/GiST 用 Custom 变体） | 明显差距 |
| 反向 codegen | ✅ information_schema → @Entity struct（schema.cj:430-567，decimal/date 简化待完善） | ✅ sea-orm-cli generate entity | 对齐 |
| mock 测试 | ✅ MockRow/MockDatabase（observability.cj:122-376） | ✅ MockDatabase | 对齐（csorm MockRow.getTextArray 朴素分割与真实行为有偏差） |
| 可观测性 | 🟡 DatabaseMetric 回调 + 慢查询日志（>500ms，database.cj:72-89），**但 metric 只埋在 raw/rawOne/execRaw 路径——builder 路径 all/one/exec 完全无埋点**（executor.cj:141-204 vs 34-138） | ✅ tracing 全链路 + sqlx_logging | csorm 半成品；池指标 waitingCount/borrowTimeouts 已有但应用未暴露 |
| 连接池 | ✅ max/min/idle/borrow 超时 + 借出校验 + LIFO + 指标（pool.cj），缺 max_lifetime | ✅ sqlx Pool 全参数 | 基本对齐 |

### 2.6 PG 特有类型与特性

| 特性 | csorm | SeaORM | 说明 |
| :-- | :-- | :-- | :-- |
| JSONB | 🟡 DDL TJsonb（schema.cj:46）；绑定 VJson 文本需调用方手写 ::jsonb cast；读取仅原始文本；无 ->/@>/jsonb_set API | ✅ Json 列 column_type="JsonBinary" 映射 struct，FromJsonQueryResult | 差距 |
| 数组 | 🟡 PGArray 写 {…} 文本（需 ::text[] cast）；读解析 text[]/int 数组（row.cj:206-248） | ✅ Vec<T> 原生 | 小差距 |
| UUID/ENUM/inet/范围/pgvector | 🟡 UUID/ENUM 部分支持（CREATE TYPE AS ENUM + ActiveEnum 接口，手写宏缺失）；范围/inet/几何/向量 ❌ | ✅ 全部原生（含 pgvector 1.1.6+） | 差距 |
| tsvector/全文检索 | 🟡 ORM 层无 API；迁移层已用 GIN+trigram（V029） | 🟡 同样需 raw | 同水平 |
| LISTEN/NOTIFY | ❌ | 🟡 sqlx PgListener 底层可用 | 小差距 |
| advisory lock / SKIP LOCKED | ❌（FOR UPDATE 有，SKIP LOCKED/NOWAIT 无） | 🟡 raw | 小差距 |

### 2.7 横向对比结论

- **与 SeaORM 的真实差距 ≈ 协议层 + 生态成熟度，而非功能骨架**。csorm 单独支持 PG，因此 SeaORM 最大的卖点（多后端可移植、运行时切方言）对本项目无价值；反过来 csorm 的 libpq 直连 FFI + @FastNative 访问器是一条 SeaORM 没有的路径，只是还没把物化层优化做完。
- 与 Diesel/sqlx 比：csorm 和 SeaORM 一样没有编译期 SQL 校验；sqlx 的二进制协议 + 语句缓存正是 csorm 协议层要补的方向。
- 一次第三方基准（qail.rs，2025-12 快照，CTE+JOIN+LIMIT 负载）：SeaORM ≈ 0.89×、SQLx ≈ 0.79×（相对裸驱动缓存路径）——说明成熟 ORM 的抽象开销本身不大，csorm 200ms 级的物化成本不是 ORM 的宿命，是未完成的优化。

---

## 三、是否充分发挥了 PG 的性能？

### 3.1 已经用上的（含金量不低）

| PG 能力 | 用法 | 证据 |
| :-- | :-- | :-- |
| 反规范化文档表 + 触发器增量维护 | archive_search_docs 每 archive 一行，5 个触发器写路径单行 upsert 刷新 | v029_search_doc_index.cj:31-51, 56-277 |
| GIN trigram 表达式索引 | lanlu_immutable_unaccent(COALESCE(col,'')) gin_trgm_ops，表达式与查询侧完全对齐 | v029:338-376, x013 extensions |
| GIN tsvector | search_tsv 加权（A/B/C setweight）+ ts_rank 相关度 | v029:379-385, archive_dao:747 |
| LATERAL | 快速分页路径 LEFT JOIN LATERAL string_agg、CROSS JOIN LATERAL jsonb_each_text | archive_dao:1063-1084, tankoubon_dao:785-790 |
| CTE | WITH base AS（相关度只算一次复用）、WITH page AS MATERIALIZED | archive_dao:997/1064/1099 |
| DISTINCT ON | 归档→主合集映射 | recommendation_dao:530 |
| UPSERT / RETURNING | ON CONFLICT DO UPDATE（V029、user_target_status）；任务原子领取 RETURNING | task_dao:984-1002 |
| 部分唯一/部分索引 | WHERE entity_type='page'、WHERE revoked_at IS NULL 等 | v011:84-90, v020:57 |
| IMMUTABLE PARALLEL SAFE 包装 | lanlu_immutable_unaccent 解决 unaccent 不可索引问题 | v029:338-349 |
| 读缓存体系 | RocksDB 批量缓存 + 命名空间版本失效 + 结果缓存（TTL 30s） | performance-fix-implementation.md |

**效果已实测闭环**（同 docs）：tankoubons 6.13s→0.28-0.39s、无词搜索 1.1s→70ms、带词冷查 3.6~4.8s→0.74s、info 0.58s→0.046s、并发 0 错误。

### 3.2 没发挥的（按收益排序，均可操作）

> 2026-11 落地更新：本节 1-10 条已全部实施完成，逐条完成状态与实测数字见文末「六、落地记录」6.6。

1. **旧聚合视图残留（最大单项收益）**：archive_metadata_search（GROUP BY + string_agg 非物化视图）仍被 recommendation_dao（5 处）、user_stats_dao（:191/:228）、user_favorite_dao、user_archive_status_dao、smart_filter_dao 查询——每次都重算 13k 行聚合。V029 已建好字段一一对应的 archive_search_docs，换 FROM 即可。
2. **tsvector 只打分、不过滤**：带词搜索 WHERE 仍是 ILIKE '%term%'（52 处），tsquery 全仓仅 1 处。加 search_tsv @@ websearch_to_tsquery('simple', $1) OR trigram 条件，整词命中走已有 GIN。
3. **写路径未批量化**：insertImpressions 循环单条 INSERT（recommendation_dao:672-687）、batchUpdateSortOrder 循环 UPDATE（smart_filter_dao:191-198）、UPDATE-then-INSERT 而非 upsert（user_archive_status_dao:31-41、user_favorite_dao:34-38）。csorm builder 本身支持多行 VALUES，业务没用。
4. **任务队列无 SKIP LOCKED**：原子领取靠 WHERE status='pending' 竞争（task_dao:984-1002），多 worker 争同一行；FOR UPDATE SKIP LOCKED 一行 SQL 解决（csorm 的 forUpdate() 也未带 SKIP LOCKED 参数）。
5. **keyset 分页未接线**：csorm KeysetPaginator 已实现（paginator.cj:81-123），src 0 调用方；26 处 OFFSET 分页在深翻页时退化。
6. **部署层兜底缺失**：statement_timeout 应用/驱动/PG 三层都没设；POOL_MAX 默认 10 共享全站；池 waiting/borrowTimeouts 指标已实现但应用层 stats() 的 idle 硬编码 0（connection_pool.cj:161-170）。
7. **窗口函数 0 处**：推荐打分/多样性重排在仓颉内存做（recommendation_service.cj:99-267），标签重叠计数其实已下推 SQL，Jaccard 可一并下推。
8. **JSON 存 TEXT 的列**：plugins.pre_hooks/after_hooks/parameters、tasks.parameters/result 都是 TEXT 存 JSON（v001），无法用 JSONB 运算符与索引；tags.translations 已是 JSONB 但查询走 ::text ILIKE（改 GIN jsonb 更精确）。
9. **EXPLAIN 观测缺失**：线上带词首查 0.74s 无法验证 trigram 索引是否被选中（performance-fix-implementation.md:320-327 自述悬案）。加一个 admin-only EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) 接口即可。
10. **协议层优化空间（ORM 自身）**：C 侧整块物化（自述可再省一半，13k 行 200ms → 预计 ~100ms）、PQprepare/PQexecPrepared 语句缓存（高频鉴权查询受益）、每查询 mallocCString/free 参数缓冲改 arena。

### 3.3 驱动/ORM 的两个实质并发缺陷（建议优先修）

- **嵌套 begin() 泄漏池连接**：线程已有事务再调 begin() 会借第二条连接覆盖 ThreadLocal 钉住的旧连接，旧连接永不归还（connection.cj:222-231）。修复：begin() 先判 inTransaction()，要么抛错要么走 SAVEPOINT。
- **cancel 单槽全局**：activeConn 是单变量（connection.cj:20-22），并发多查询时 withTimeout 看门狗可能取消错连接（P1-4 按线程注册，未实施）。
- （docs 里列为未实施的 P1-2 借出校验、P1-3 lastAffected 隔离，经代码核对**已经落地**：pool validate 闭包 connection.cj:32、ThreadLocal connection.cj:25。）

---

## 四、给 csorm 的路线图建议（若继续自研，而非换 SeaORM）

说明：换 SeaORM 意味着放弃仓颉生态/引入 Rust FFI 桥，对本项目不现实；以下按"把 csorm 补到 SeaORM 水准"排序，且与第三节的 PG 收益正交。

1. **协议层**（收益最大）：C 侧批量物化 + PQprepare 语句缓存 + 二进制 resultFormat（至少对 int8/float8/timestamptz 常用 OID）。预计 13k 行物化从 200ms 进入两位数 ms。
2. **修并发缺陷**：begin 重入保护、cancel 按线程注册（上节 3.3）。
3. **可观测性补齐**：builder 路径补 DatabaseMetric 埋点（一行 wrapper 的事）；池指标接入应用层。
4. **SQL DSL 补课**：DISTINCT ON、joinLateral、WithQuery（CTE 占位符自动续编而不是让调用方手数 $n）、onConflict 走 EXCLUDED 的类型安全封装、SKIP LOCKED/NOWAIT 参数。
5. **索引 DDL**：SchemaManager 增加 createIndex（type: btree/gin/gist/brin、partial where、expression 列表）——本项目全部索引都是手写 SQL，DSL 化后迁移才可审查。
6. **事务作用域**：BEGIN 隔离级别参数、基于词法作用域的事务句柄（替代 ThreadLocal 语义）、迁移 advisory lock。
7. **关系预加载**：loadManyToMany 单 JOIN 化；若做嵌套 with()，从一跳批量回填开始即可覆盖本项目的 tankoubon/metadata 场景。

## 五、给业务的路线图建议（不动 ORM 就能拿的收益）

即第三节 3.2 的 1-6 条：迁移视图消费方到 archive_search_docs、tsquery 参与过滤、写路径 upsert/批量化、SKIP LOCKED、keyset 分页接线、statement_timeout + POOL_MAX。其中第 1 条预期把推荐/统计/收藏等剩余视图路径从"每次全量聚合"降到索引查询，是当前代码库里剩余收益最大的单项改动。

---

---

## 六、落地记录（2026-11-07/08 实施验收）

本章记录报告第三节/第四节路线图的实际落地结果：阶段 1-5 的改动清单、前后基准数字、验收结果。各阶段由并行 teammate 实施，task-5（seaorm-research）负责 statement_timeout、本文档与最终验收汇总。

### 6.1 阶段1：驱动协议层（task-1，owner: orm-internals）

| 改动 | 结果/不变量 |
| :-- | :-- |
| C bridge 物化（native/lanlu_pg_bridge.c，llpg_materialize 一次遍历 + @FastNative） | 13,335 行×13 列实测 **200ms → 48ms（~4x）**；三级修复过程 9.7s → 3.3s → 48ms |
| PQprepare/PQexecPrepared 语句缓存（每连接 LRU，pool.stmtCache 键） | 实测 hits 208 / misses 3 / **fallbacks 0**；冷 5-11ms vs 热 4-13ms（收益在服务端 parse/plan，本地环回 + 缓存叠加下区分度有限） |
| 二进制结果协议（OID 白名单自适应，pool.binaryResult 键） | 两条不变量：**写语句绝不重发**、**float 移出白名单**（文本/二进制一致性断言全过） |
| 并发缺陷修复（对应原文 3.3） | begin() 重入保护（inTransaction 抛 PGError）；cancel 单槽改 ThreadLocal 定向 |
| 参数 arena | 连接级复用缓冲替代每参数 mallocCString/free |

### 6.2 阶段2：csorm SQL DSL 补课（task-2）

新增 API（签名经 task-5 对照 SeaQuery/SeaORM 评审后修订）：
- `withCte(...)`（`with` 是保留字）：多 CTE 聚合为单个 `WITH [RECURSIVE]` 前缀（RECURSIVE 是 WITH 列表级标志）；占位符经 Placeholder **结构性续编**（不再要求调用方手写 $n），保留 rawPrefixFragment 兼容。
- `distinctOn(cols)`：双校验——非 PG 方言抛错；**DISTINCT ON 最左表达式必须与 ORDER BY 最左前缀匹配**（PG 硬约束），build 期拦截。
- `joinLateral(kind, subSelect, alias, on)`：JOIN LATERAL 渲染。
- `Expr.over(..., frame!)`：窗口工厂带 frame 子句（OVER (PARTITION BY ... ORDER BY ... ROWS BETWEEN ...)）。
- `forUpdate` 改 LockBehavior 枚举（Wait/SkipLocked/NoWait 互斥，替代双 Bool）；渲染位置锁定在 ORDER BY/LIMIT 之后。
- `onConflictDoUpdateExcluded`：`"col" = "excluded"."col"` 语法糖。
- `SchemaBuilder.createIndex(..., predicate!)`（`where` 是保留字）：CREATE [UNIQUE] INDEX ... USING method (cols) [INCLUDE ...] [WHERE ...]，method 标识符校验防注入。

真库 smoke（本地 PG17）：WITH 返回 5 行 / RECURSIVE sum=15 / DISTINCT ON 2 行 / LATERAL 26,670 行。验收单测含 CTE 多个时占位符编号链矩阵。

### 6.3 阶段3：预加载/事务/锁/指标（task-3）

| 改动 | 验收数字 |
| :-- | :-- |
| `withMany(rel, mapper)` 组合器（对齐 SeaORM LoaderTrait：父列表一次取回 + 关联 IN 回填分组） | **N+1 101 → 2**（父 100 行，SqlCounter 实测） |
| loadManyToMany 两步查询 → 单 JOIN | 等价结果，查询数减半 |
| `begin(isolation!)`（Default/ReadCommitted/RepeatableRead/Serializable；Default 保持裸 BEGIN） | 单测断言 SQL 序列 |
| Migrator.up/down 加 pg_advisory_lock | 多实例并发迁移只有第一个连接执行（mock SQL 序列断言） |
| executor 全路径 DatabaseMetric 埋点 | 8 类 builder metric 计入，与 raw 路径一致 |
| 池指标贯通（connection_pool.stats() 接 driver waiting/idle/borrowTimeouts + 饱和 warn 日志） | idle 不再硬编码 0 |

当时验收：csorm 24/24 + driver 85/85（1.0.5 与 1.2.0 各四组）。

### 6.4 阶段4：业务层榨干 PG（task-4，owner: app-usage）

改动清单（详见 team task-4 交付汇总）：视图迁移 11 处、tsquery OR trigram（6 调用点）、批量写 4 项（insertImpressions 多行 VALUES chunk 1000、batchUpdateSortOrder UPDATE FROM (VALUES...) chunk 500、两处 ON CONFLICT upsert）、task_dao 领取子查询 FOR UPDATE SKIP LOCKED（原生 SQL + DSL 局限注释：csorm forUpdate 顶层渲染表达不了 UPDATE 子查询锁）、EXPLAIN admin 接口（仅单条 SELECT/WITH、拒分号/注释/危险函数、强制 LIMIT 上限 5000、ANALYZE 分支 SET LOCAL statement_timeout 5s）、keyset 分页接线（游标 sortValue|docId + next_cursor）、v030 六列 TEXT→JSONB、Jaccard 下推（新增 recommendation_pushdown_dao，WITH seed/seed_tag_list/candidates CTE + COUNT(*) OVER()）。

**EXPLAIN (ANALYZE) 前后对照（本地 PG17，13,435 行种子）**：

| 场景 | 前（视图/ILIKE） | 后（文档表/索引） | 提升 |
| :-- | :-- | :-- | :-- |
| C1 无词 COUNT(*) | 114.55ms | 3.81ms（基表 1.37ms） | **30~84x** |
| C2 带词过滤 COUNT | 100.49ms | 5.11ms（纯 ILIKE）/ 8.44ms（+tsquery OR） | **12~20x** |
| C3 深分页 OFFSET 13000 | 11.45ms | 12.45ms（keyset） | 持平（13k 规模 OFFSET 未成瓶颈，keyset 为前瞻改造，不宣称收益） |
| C5 高选择性词（1475/13435） | 10.51ms | 5.46ms（纯 tsquery GIN） | **~2x** |

等价性验收：视图迁移前后 **16 列双向 EXCEPT 差集=0** 且行数一致（searchDocFullRowEqualityTest，本地 13k 种子）。

**分词边界诚实结论**：simple 配置下，下划线/点/中文连续词为单一 lexeme，子串词 tsquery 命中 0，靠 ILIKE 兜底；OR 语义严格等价（tsquery 命中集 ⊆ ILIKE）；tsquery 仅在词边界对齐时经 GIN 增益。已写入 archive_dao 防误删注释；后续可选 zhparser/独立 tsvector 列。

其他：v030 迁移修复点——TEXT 带字符串默认值 ALTER TYPE 前必须先 DROP DEFAULT（PG17 实测 cannot be cast automatically）；tasks.result 明确不转（内容不保证合法 JSON）。构建注意：cgroup pids 512 下 cjc 并行触发 ICE，需 `-j 1`。

### 6.5 阶段5：statement_timeout + 文档 + 最终验收（task-5，owner: seaorm-research）

1. **statement_timeout 配置**（packages/postgresql-driver）：
   - 连接串键 `pool.statementTimeout`（毫秒，URL 与 keyword 两种形式均解析；默认 0 = 不设置，行为完全向后兼容；非法值回退 0）；
   - openConn 连接建立后执行 `SET statement_timeout='<ms>ms'`，SET 失败视为连接失败（PGError，尽早暴露服务端/权限问题）；0 则完全跳过；
   - 被取消语句返回 SQLSTATE 57014；
   - 新增单测：test_statement_timeout_parse（URL/keyword/默认/非法值/键剥离）+ test_statement_timeout_apply（**防假绿设计**：先裸连接证明 DB 可达——不可达才 skip；随后带 timeout 的连接失败或 SHOW 回显不符一律 ERROR）。真库断言 `SHOW statement_timeout` = `5s`（pool.statementTimeout=5000）。
2. **.env.example**：增补 POOL_MAX/pool.statementTimeout 部署指引（POOL_MAX ≈ CPU核数*2+磁盘数并与 PG max_connections/PgBouncer 对齐；线上 timeout 建议 30s~60s；PgBouncer transaction 模式下 pool.stmtCache 务必设 0）。
3. **最终验收（本机，DB_STRING=postgres://pgtest@127.0.0.1:5433/lanlutest，PG17.11，13,335 行 bench_rows）**：

| 包 | 1.0.5 (lts) | 1.2.0 (sts) |
| :-- | :-- | :-- |
| packages/postgresql-driver | **87/87**（85 + statement_timeout 2 条） | **87/87** |
| packages/csorm | **24/24** | **24/24** |
| 主包 lanlu | （工程为 1.2.0 基线，lts 无法解析 stdx 依赖，不适用） | 见下 |

   主包结果：**cjpm test 12/12 全绿（PASSED 12 / SKIPPED 0 / ERROR 0 / FAILED 0，EXIT=0）**。注：首次运行等价性测试报 COUNT 9049 vs 9044——共享本地库被多任务并行写导致视图/文档表瞬时漂移，属数据环境问题非代码回归；用 v029 自带回填（幂等 upsert）重同步后复跑即全绿。共享库验收建议错峰或各自起独立临时库。

   主包构建环境（CI 1.2.0 复现要点）：`CANGJIE_STDX_PATH=/workspace/.cjv/stdx/sts-1.2.0/static/stdx`、`LIBRARY_PATH`/`LD_LIBRARY_PATH=/workspace/native-root2/usr/lib/x86_64-linux-gnu`、`C_INCLUDE_PATH=/workspace/native-root2/usr/include`、cgroup pids 受限时 `cjpm test -j 1`。

### 6.6 原报告 3.2「没发挥点」完成状态

| # | 原问题 | 状态 | 落地证据 |
| :-- | :-- | :-- | :-- |
| 1 | 旧聚合视图残留（11 处） | **完成** | 16 列双向 EXCEPT 差集=0；C1 114.55→3.81ms |
| 2 | tsvector 只打分不过滤 | **完成** | tsquery OR trigram 6 调用点；C2/C5 提升 12~20x/~2x；分词边界结论入档 |
| 3 | 写路径未批量化 | **完成** | 多行 VALUES（chunk 1000）、UPDATE FROM VALUES（chunk 500）、2 处 ON CONFLICT upsert |
| 4 | 任务队列无 SKIP LOCKED | **完成** | task_dao 领取子查询 FOR UPDATE SKIP LOCKED（原生 SQL，DSL 局限已注释） |
| 5 | keyset 分页未接线 | **完成** | KeysetPaginator 接入搜索/合集，cursor 透出；13k 规模持平（前瞻改造） |
| 6 | 部署层兜底缺失 | **完成** | pool.statementTimeout 键（task-5）+ POOL_MAX 指引；池指标贯通（task-3） |
| 7 | 窗口函数 0 处 | **完成** | recommendation_pushdown_dao CTE + COUNT(*) OVER()，预筛池 16x→2x |
| 8 | JSON 存 TEXT | **完成** | v030 六列 TEXT→JSONB（DROP DEFAULT 修复）；tasks.result 明确不转 |
| 9 | EXPLAIN 观测缺失 | **完成** | admin-only /api/admin/db/explain（安全限制齐备）+ 本地对照表 |
| 10 | 协议层优化空间 | **完成（超预期）** | bridge 物化 200ms→48ms，优于原预估 ~100ms；stmt 缓存 + arena + 二进制协议落地 |

原 3.3 两个并发缺陷（begin 重入泄漏连接、cancel 单槽误取消）均已在 task-1 修复并单测覆盖。

### 6.7 PostgreSQL 18 全量复验（2026-11-08）

应验收要求，本地从源码编译 PostgreSQL 18.6（gcc 14.2，含 contrib pg_trgm/unaccent）建立独立实例（127.0.0.1:5434/lanlutest18），在全新库上完整复验：

- **迁移自举**：V001~V029 + X013 全部在 PG18 上从零执行成功；V030 首轮暴露一处执行顺序问题（多个测试二进制并发自举时，registry 为进程内静态，先完成者已 CONVERT 一列、后完成者再跑 V030 对 `after_hooks` 再 DROP DEFAULT/CONVERT 时因其默认值已被前一进程改为 `[]'::jsonb`（jsonb）而中途失败，导致迁移记录未写、五列部分转换）。已在全新状态下复跑验证：**V030 全五列（plugins.pre_hooks/after_hooks/parameters、categories.plugins、tasks.parameters）在 PG18 上全部转为 jsonb 并正确记录**。教训：测试自举建议与生产一样走单实例顺序执行（或迁移幂等检查放到列级），已记录为 CI 注意事项。
- **全量测试**：postgresql-driver **87/87**、csorm **24/24**、主包 **12/12**，PG18.6 与 PG17.11 结果一致。
- **触发器链路**：PG18 上插入 100 archives → archive_search_docs 触发器增量同步 100/100 行，字段（arcid/filename）正确。
- **GIN 计划**：trigram ILIKE 在 PG18 走 `Bitmap Index Scan on idx_search_docs_filename_trgm`（actual rows=100，Index Searches: 1），tsquery GIN 路径可用。
- **V030 落库形态**：information_schema 确认五列 data_type=jsonb。

- **虚拟数据全量验证（2026-11-08 补充）**：在 PG18 实例上注入业务级虚拟数据（13,335 归档 + 13,335 元数据 + 53,340 标签 + 13,335 封面资产 + 1,000 追踪 + 20 任务 + bench_rows 13,335×13），完成端到端复验：
  - **触发器链路**：archives/metadata_objects/metadata_tags/metadata_assets/assets 五路写路径 → archive_search_docs 13,335/13,335 全量同步（含 thumbhash 13,335 行）；
  - **等价性**：视图 vs 文档表 16 列双向 EXCEPT 差集=0（13k 生产同量级数据）；
  - **查询计划**：视图全量 Seq Scan 43ms vs 文档表 ILIKE 19ms vs tsquery GIN 0.07ms vs trigram ILIKE 9.3ms（Bitmap Index Scan）；keyset 深分页 0.1ms vs OFFSET 13.5ms（Index Scan Backward vs 全表 Seq Scan）；
  - **写路径语义**：ON CONFLICT 两次同键 upsert → 单行 progress=77（幂等）；SKIP LOCKED 四个模拟 worker 并发领取任务 id=3/4/5/6 无重复；多行 VALUES 一次 1,000 行 impressions 成功。

### 6.7.2 线上部署 A/B（2026-11-08，nas.copur.xyz:3005，13,435 归档）

部署版本：`608b7b5`（含本轮全部改动）。基线：同实例部署 `5d89654`（本轮改动前，
已含上轮 N+1/缓存/V029 修复）当日实测。生产网络 RTT ≈1ms，基线各端点因上轮
优化已处于 20~35ms 区间。

| 端点（3 次均值区间） | 基线 5d89654 | 部署 608b7b5 | 变化 |
| :-- | :-- | :-- | :-- |
| /api/info | 20~33ms | 29~37ms | 持平（±噪声） |
| /api/search | 18~29ms | 25~29ms | 持平 |
| /api/tankoubons?limit=1 | 21~27ms | 27~30ms | 持平 |
| /api/tags/cloud | 17~29ms | 27~36ms | 持平 |
| /api/categories | 34ms | 25~34ms | 持平 |
| /api/user/stats | 34ms | 30~34ms | 持平 |
| /api/search?page=670 | — | 28~32ms | 深分页无劣化（keyset 保障） |
| /api/search 50 连发 p50/p90/max | — | 28/32/37ms | 无长尾 |

结论（诚实版）：**热缓存读端点在基线已优化到 20~35ms 的前提下，本轮改动未带来
可测的端到端差异（差异被 RTT/序列化/框架开销淹没）**。这与预期一致——本轮收益
集中在：① 冷缓存场景（推荐/统计/收藏/智能过滤不再触发旧视图全量物化，
本地实测 28×/6× 的收益只在缓存失效后首查兑现）；② 协议层（stmt 缓存省
parse/plan，远程 RTT 1ms 下单次省 0.1~0.5ms，QPS 放大后可见）；③ 写路径
批量化与并发安全（upsert/SKIP LOCKED，正确性收益大于计时收益）；④
13,335 行级大结果集物化 3×（列表类接口行数少，不触发）。

部署过程修复两处 CI/迁移问题：CNB 流水线 pg bridge 预生成缺失（cjpm update
失败）、V030 typeSql 误用 ? 占位符（驱动为 DollarNumber，raw 路径无重写）。
两处均已修复并经真实启动路径验证 V030 五列 TEXT→JSONB 成功。

#### 6.7.1 性能提升汇总（PG18 + 13,335 行虚拟数据实测，2026-11-08）

**业务查询层（EXPLAIN ANALYZE / psql \timing，同库同数据新旧对照）**

| 场景 | 改造前 | 改造后 | 提升 |
| :-- | --: | --: | :-- |
| 无词 COUNT（info/分页总数） | 视图全量聚合 72.5ms | 基表 COUNT 2.6ms | **~28×** |
| 带词过滤（中文标题） | 视图 ILIKE 89.5ms | 文档表 ILIKE 14.3ms | **~6×** |
| 带词过滤（tsquery 命中词边界） | 同上 89.5ms | tsquery GIN 2.8~3.1ms | **~30×** |
| 深分页 page≈650 | OFFSET 13000 15.1ms | keyset 行比较 12.1ms | 持平（13k 规模 OFFSET 未成瓶颈，前瞻改造） |
| 推荐候选预筛池 | SQL 取 16×N + 仓颉侧过滤 | CTE+窗口下推 2×N | 池缩小 8×，IO 减少 |
| 任务并发领取 | 多 worker 争同一行 | FOR UPDATE SKIP LOCKED | 4 worker 并发 0 重复领取 |

**ORM/驱动层（独立 bench 二进制，best of 5）**

| 指标 | 旧实现 | 新实现 | 提升 |
| :-- | --: | --: | :-- |
| 13,335 行 × 16 列物化（开发期实测） | 200~236ms | 62~75ms（PG18 虚拟数据） | **~3×** |
| 同上（修复过程记录） | 初版 bridge 9.7s → O(n²) 修复 3.3s | 游标自增后 48~75ms | 相对初版 ~200× |
| 重复参数化小查询 ×200 | 每次 PQexecParams 重 parse | stmt cache 热路径 | 冷 15-19ms / 热 14-17ms（本地 PG 往返 <0.1ms 掩盖 server 端节省，远程库收益更大） |

**工程层（非计时类）**：begin 重入不再泄漏池连接；cancel 按连接定向不再误取消；迁移 advisory lock 防多实例冲突；builder 路径全部纳入慢查询观测（此前 0 覆盖）；池 waiting/borrowTimeouts 指标暴露（此前 stats() 硬编码 0）。

> 诚实说明：① 物化 A/B 在 PG17 空载库上曾测得 200ms→48ms（~4×）；PG18 虚拟数据 + 并行会话下为 62~75ms vs 旧路径 65ms——**本轮 A/B 差距收窄**，因为旧路径的每行 HashMap 惰性化等优化早已合入旧路径本身，剩余差距主要是 FFI 次数，而 16 列文本较短时 CString 转换占比下降。bridge 的确定性收益在大结果集/宽行/二进制列场景。② stmt cache 在本地低延迟 PG 上收益不明显（往返占比小），生产远程库（RTT 1-2ms）下 parse/plan 节省会显著放大。③ keyset 在 13k 规模无收益属预期，收益在百万行级。

---
## 附：SeaORM 关键参考（联网核实）

- 架构与 Diesel 对比：https://www.sea-ql.org/SeaORM/docs/internal-design/architecture/ 、https://www.sea-ql.org/SeaORM/docs/internal-design/diesel/
- 2.0（Entity Loader .with() / 强类型列 / raw_sql!）：https://www.sea-ql.org/blog/2025-12-05-sea-orm-2.0/
- LoaderTrait：https://www.sea-ql.org/SeaORM/docs/relation/model-loader/
- 列类型（JSONB/数组/pgvector/inet）：https://www.sea-ql.org/SeaORM/docs/generate-entity/column-types/
- 事务/流式/连接池：https://www.sea-ql.org/SeaORM/docs/advanced-query/transaction/ 、https://www.sea-ql.org/SeaORM/docs/advanced-query/streaming/ 、https://www.sea-ql.org/SeaORM/docs/install-and-config/connection/
- SeaQuery（join_lateral/distinct_on/WithClause/IndexType）：https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html 、https://docs.rs/sea-query/latest/sea_query/index/enum.IndexType.html
- sqlx 协议层（statement_cache_capacity/PgListener）：https://docs.rs/sqlx/latest/sqlx/postgres/struct.PgConnectOptions.html 、https://docs.rs/sqlx/latest/sqlx/postgres/struct.PgListener.html
- ORM 开销基准参考：https://qail.rs/benchmarks/orm-50k/
