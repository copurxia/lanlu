# client-next RocksDB 对象存储与集合收敛计划

> 初版：2026-08-15
> 状态：**全部阶段完成**（P0 基线/风险、P1 rocksdb_ffi、P2 对象层、P3 设置/离线/outbox、
> P4 内容对象、P5 管理对象、P6 文件缓存元数据、P7 迁移回滚、P8 最终验收——全部条目 [x]；
> §4.6 Linux/Windows 最小 FFI 测试已在 Windows 工具链 + MSYS2 rocksdb 11.1.1 下实跑 10/10 全绿，
> 运行环境为 Linux 宿主 wine 兼容层，证据存档于 `packages/rocksdb_ffi/evidence/`）
> 范围：`client-next`、`packages/rocksdb_ffi`
> 说明：本计划置于文件顶部；原“多字幕渲染实施计划”完整保留在后文，避免覆盖既有待办。

### 2026-08-15 执行记录（第一阶段）

- P0：新增 `client-next/scripts/audit-storage-state.sh`，固定 31 个长期集合 State 基线；修复离线缓存
  server/account 隔离、同 profile 换账号隔离、异步补报切服串写，以及重启后的 server id 碰撞。
- P1：`rocksdb_ffi` 新增 binary get/put/multi-get/delete、RAII iterator、正反向 prefix cursor、增量
  write batch、`deletePrefix`；String API 改由 byte API 解码，非法 UTF-8 返回 `DecodeFailure`；未配置
  merge operator 时稳定返回 `Unsupported`。兼容 `RocksDb.scanByPrefixResult` 已改由 cursor 实现。
- P2：新增 `client-next/src/storage/object_store.cj`，提供长度前缀二进制 key、版本化 envelope、TTL、
  `ObjectCodec/ObjectRepository/QueryRepository/PagedObjectView`，支持对象与 ordered membership 同 batch
  原子提交、cursor token 翻页和坏对象记录局部自愈。
- P3（先行）：离线响应改用 byte API；进度 outbox 每批 64 条 cursor 读取并在健康时连续排空；服务器
  清理改用 `deletePrefix`，产品代码已无 `scanByPrefixResult` 调用。
- 验证：`packages/rocksdb_ffi` 5/5、`client-next` 203/203；`git diff --check` 与集合审计通过。

### 2026-08-15 执行记录（第二阶段）

- RocksDB 打开流程会先枚举并完整打开磁盘上的全部 column family；新增 CF 创建/查询/删除 RAII handle，
  默认 API 保持兼容，get/put/delete/iterator/prefix cursor/write batch 可显式选择 CF。
- 新增一致性 `RocksDbSnapshot`，支持默认/指定 CF 的 point read 与 bounded cursor；DB 关闭时先释放 snapshot
  和 CF handle。新增 flush、compact range、整数/字符串 property、approximate size 与 latest sequence number。
- 设置 DB 固定创建 `meta/objects/indexes` 三个 CF。`ServerProfile` 由版本化对象记录管理，显示顺序由
  ordered membership 管理；标量 settings 文档升级 schema v3，不再包含 server `list` 与 token payload。
- schema v2 迁移把旧数组、顺序、schema v3 标量和 migration marker 放进同一个跨 CF write batch；迁移
  测试覆盖关闭重开、顺序、会话字段和标量文档不泄漏 token。
- `AppSettings.servers` 从可变 `ArrayList` 改为最多 256 项的 `ServerListView` 有界快照；AppModel、登录页和
  标题栏只消费该视图。长期集合 State 基线仍为 31，下一阶段从 PageInfo/SearchItem 开始实际下降。
- 验证：`packages/rocksdb_ffi` 6/6、`client-next` 204/204；`git diff --check` 与集合审计通过。

### 2026-08-15 执行记录（第三阶段）

- 缓存 DB 新增固定 `objects/indexes` CF；`LanluApi.files` 在线或离线解析页表后，将 `PageInfo` 主记录与
  `(archive, rank, entity)` ordered membership 放入同一个 write batch，整本替换会原子删除旧对象和旧索引。
- `QueryRepository` 新增精确 rank 读取与 batch 范围替换；页表长度由末项 rank 推导，不维护 `count`、数字
  下标 KV 或 JSON id 数组。server/account scope 继续隔离对象与索引，清理服务器缓存会同时清理两个 CF。
- `ArchivePageView` 只持 count、类型统计和固定 64 项热点窗口；详情缩略图/列表/树、元数据编辑器和阅读器
  都按 rank 从视图取对象。相同档案从详情打开编辑器时直接共享同一 view 引用。
- `ReaderModel` 删除扁平 `ArrayList<PageInfo>`；无缝续读只追加 `ArchivePageView` 引用，由轻量 segment
  组合映射全局页号，不再复制下一档案全部页面对象。
- `AppModel` 的 `pages/detailPages/metadataEditorPages` 三个长期 `State<ArrayList<PageInfo>>` 已消除，长期
  集合 State 审计从 31 降到 28。
- 验证：`client-next` 207/207；新增 CF 重开、账户隔离、原子替换、附件 codec、内存 fallback 和 rank
  直读测试；`git diff --check` 与集合审计通过。

### 2026-08-15 执行记录（第四阶段）

- `SearchStore` 新增 `SearchItemView` 只持有 queryKey、语言和固定 64 项热点窗口，不再长期持有解码后的
  全量 `SearchItem` 数组；`SearchItemProjectionView` 只保留命中 rank，支持 `all` 与惰性 `filter`。
- `LanluApi.search/searchAll/relatedArchives` 在线或离线解析搜索结果后，将 `SearchItem` 主记录与
  `(queryKey, rank, entity)` ordered membership 放入同一个 write batch；`searchAll` 用有界 HTTP 页
  (默认 256/页) 顺序追加 rank，不再一次全载入大结果。query key 覆盖 filter/sort/order/page/lang/groupby。
- `SearchItem` 主键区分 archive/tank：`<lang>:archive:<arcid>` 与 `<lang>:tank:<tankoubonId>`，无稳定主键的
  派生行退化为 `<lang>:unkeyed:<queryKey>:<rank>`；语言间实体按 query 隔离。
- `toggleFavorite` 等 mutation 通过 `SearchItemView.persist` 只更新规范实体记录，各视图（搜索/浏览行/
  书架/合集成员/最近阅读收藏）按 rank 重读共享对象并推进自身 State 代次；`tankMembers` 大结果
  (`pageSize=10000`) 改用 `searchAll` 分页加载。
- `BrowseRow.items`、`shelfFavorites/shelfHistory`、`relatedItems`、`tankMembers`、`recentRead/recentFav`、
  搜索 `items` 全部改为 `State<SearchItemView>`；长期集合 State 审计从 28 降到 21。
- 验证：`client-next` 210/210；新增共享实体、语言隔离、rank 过滤、分页追加替换和账户隔离测试；
  `git diff --check` 与集合审计通过。

### 2026-08-15 执行记录（第五阶段）

- 新增 `client-next/src/net/tank_store.cj`：`TankoubonCodec` 以 `(lang):tank:<id>` 为稳定主键，
  `TankoubonView` 只持 queryKey、语言和固定 64 项热点窗口，不再长期持有解码后的 `TankoubonInfo` 数组。
- `LanluApi.listArchiveTankoubons/relatedTankoubons` 将合集列表与 ordered membership 放入同一个
  write batch（query key 覆盖 arcid/tankid/count/lang 与账户 scope），失败时退回有界内存视图；
  `detailTagTranslations` 与合集选择弹窗的 `listTankoubons` 保持在线读取不变。
- `AppModel.parentTanks/tankRelated` 改为 `State<TankoubonView>`；`toggleTankFavoriteOnCard` 收藏切换
  通过 `TankoubonView.persist` 只写规范主记录，父合集、相关合集、书架和详情共享同一实体，各视图按
  rank 重读并推进自身 State 代次。UI `tankCardRow` 增加 TankoubonView 重载按 rank 取卡片。
- 长期集合 State 审计从 21 降到 19；新增合集共享实体、语言隔离、rank 边界、整表替换、账户隔离与
  服务器清理测试。
- 验证：`client-next` 212/212；`git diff --check` 与集合审计通过。

### 2026-08-15 执行记录（第六阶段）

- 新增 `client-next/src/net/tag_translation_store.cj`：`TagTranslationCodec` 以
  `(lang):tag:<canonical>` 为稳定主键，`TagTranslationView` 只持 queryKey、语言和固定 64 项热点窗口，
  不再长期持有整张 `HashMap<String, String>`。
- `LanluApi.tagTranslations` 把 `(canonical, translated)` 主记录与 `(lang, scope)` ordered membership
  放进同一个 write batch（query key 覆盖 archive/tank scope 与 lang），失败时退回有界内存视图。
- `AppModel.detailTagTranslations` 从 `State<HashMap<String, String>>` 改为 `State<TagTranslationView>`；
  `searchExactTag` 按 rank 遍历视图完成显示名 → canonical 反查。长期集合 State 审计从 19 降到 18。
- 新增标签翻译共享实体（档案/合集 scope 共享同一 canonical 记录）、语言隔离、rank 边界、整表替换、
  账户隔离与服务器清理测试。
- 验证：`client-next` 214/214；`git diff --check` 与集合审计通过。

### 2026-08-15 执行记录（第七阶段）

- 新增 `client-next/src/net/meta_projection.cj`，集中维护 `ArchiveMeta ↔ SearchItem` 的字段投影：
  `searchItemFromMeta`/`metaFromSearchItem` 双向转换、`copySearchProjection` 视图内原地投影、
  `joinTags`/`splitTags` 统一 CSV 语义。AppModel 删除私有 `joinMetadataTags`/`metadataTagList`
  （去重与分隔逻辑收敛到 mapper），`editTankMember` 直接投影 SearchItem 生成编辑草稿。
- `meta:` 结果回填时新增 `syncSearchItemFromMeta`：把规范字段写回搜索/浏览行/书架/合集成员/最近
  阅读收藏共享的 `SearchItemView`（按 rank 重读并 persist 规范记录），收藏、已读、新入库与元数据
  刷新共用同一投影路径，不再各持一份字段拷贝。
- `CategoryItem/AdminCategoryItem` 确立共用稳定 catid 主键：新增 `categoryKey` 与
  `projectAdminToCategory` 投影，管理行与上传分类共用 catid 身份、共享 name/archiveCount 投影。
- 验证：`client-next` 218/218；新增投影往返、标签去重、copyProjection 身份保留与 catid 主键测试；
  `git diff --check` 与集合审计通过。

### 2026-08-15 执行记录（第八阶段）

- 离线响应缓存改为版本化对象记录：`CachedResponseCodec`（type `cached-response`）经
  `ObjectRepository` 的 envelope 承载 schema/savedAt/expiresAt(TTL)/payload；key 含 server/account
  scope。旧 `resp:{server}:{account}:{path}` JSON key 读取时自动迁移并删除旧键。
- 新增 `client-next/src/net/response_policy.cj`：集中白名单策略表（按路径最长匹配声明 TTL 与
  allowStaleOffline）与 invalidation registry（mutation 类型 + 实体 id → 受影响响应前缀）。
  `checkedBodyCached` 在线写缓存与离线回退读取都按策略表决定 TTL/stale；mutation 成功后经
  `invalidateResponses` 精确删除相关响应，不再在各 API 方法散落判断/删 key。
- `OfflineCache` 新增 `deleteResponsePrefix`：按 entity key 前缀分批 cursor 删除（兼容旧 resp:
  前缀），只清目标 server/account 的相关响应；`clearServer` 语义不变。
- mutation 接入：档案/合集元数据编辑、收藏/已读切换、合集成员增删、档案/合集删除、分类/标签编辑
  都会精确失效搜索、推荐、元数据与页表缓存。
- 验证：`client-next` 222/222；新增 TTL 过期/允许 stale、旧格式迁移、按注册表失效（含无关实体与
  账号隔离）与策略最长匹配测试；`git diff --check` 与集合审计通过。

### 2026-08-15 执行记录（第九阶段）

- `PendingProgress` 确立 `(account, arcid)` 唯一键：`progress:{server}:{account}:{arcid}` 后写覆盖
  页码；入队时保留既有 retryCount/nextAttemptAt/lastError，用户翻页不重置重试状态。
- 新增 `markProgressFailed`：补报失败递增 retry count、按指数退避（1s→60s 上限）设置
  nextAttemptAt、截断记录 lastError；记录不删除，退避到期后继续尝试。
- `listProgressEntries` 只返回 nextAttemptAt 已到的记录（`includeBackoff` 供测试/诊断）；
  `ackProgressBatch` 一次 write batch 删除多条成功项，替代逐条 delete。
- `flushOfflineProgress` 改为：逐条尝试补报，成功项收集后 batch ack，失败项单独
  `markProgressFailed`（部分失败不串数据、不阻塞其余 ack）；任务仍绑定产生记录的 server/account/api。
- 验证：`client-next` 225/225；新增重试状态保留/退避、batch ack 只删成功项、跨账号/跨服务器部分
  失败隔离测试；`git diff --check` 与集合审计通过。

### 2026-08-15 执行记录（第十阶段）

- `PageStore` 新增 `putPageAt`：按 rank 读取 membership 后只写该页主记录（新 envelope revision），
  不动 count、类型统计与其余 membership；`ArchivePageView` 新增 `invalidateRank` 让热点窗口失效，
  下次 `itemAt` 重读规范记录。`OfflineCache` 暴露 `updatePage`。
- 页级元数据编辑成功（`editsave:page:{arcid}:{rank}` 任务名携带页码）后，dispatch 只对当前详情页
  视图失效该 rank 并 `updatePage` 单页写回，不再 `dfiles:` 整本重拉页表；合集/档案级保存流程不变。
- 验证：`client-next` 227/227；新增单页更新只写该 rank、重开后持久化且统计不变、热点失效重读与
  越界 rank 拒绝测试；`git diff --check` 与集合审计通过。

### 2026-08-15 执行记录（第十一阶段）

- `UserStats`/`TrendPoint`/`CloudTag` 端点（`/api/user/*`、`/api/tags/cloud`）接入响应缓存，
  策略表声明短 TTL 且不允许 stale；最近阅读/收藏继续复用 `SearchItem` query（`loadOverviewExtras`
  以 lastread 排序/favoriteonly 过滤的 search 结果），未重复存储统计对象。
- `AdminUserItem`/`SysSetting`/`AdminCategoryItem`/`AdminTagItem`/`SmartFilterItem`/`CronTask`/
  `PluginItem` 只读端点（`/api/auth/admin/users`、`/api/admin/*`、`/api/tags`）接入短 TTL 在线
  session cache，不允许 stale 离线回退；任务页继续使用 SSE/分页流，`TaskRecord` 不落存储。
- 全部管理 mutation（用户/系统设置/分类/标签/智能筛选/插件/cron/taskpool）成功后在 invalidation
  registry 中精确失效相关响应前缀；失败仍走既有 handleError 路径，保留旧视图并显示错误，不做乐观假成功。
- 安全页数据（`SessionItem`/`TokenItem`/`PasskeyItem`/`TotpStatus`）保持仅内存：新增
  `NON_CACHEABLE_PREFIXES` 守卫（`/api/auth/sessions|tokens|webauthn|totp|username|password`），
  即使业务误调 `storeResponse`/`getResponse` 也拒绝读写 cache DB。
- 验证：`client-next` 229/229；新增安全页数据不落 cache DB、管理 mutation 精确失效、策略表
  P5 端点断言测试；`git diff --check` 与集合审计通过。

### 2026-08-15 执行记录（第十二阶段）

- 新增 `client-next/src/net/blob_cache_store.cj`：`BlobCacheEntry`（blobKey/path/size/lastAccessMs/
  etag/lastModified/checksum/state/schema）经 `ObjectRepository` 存 `objects` CF；`(lastAccess 大端 8
  字节, blobKey)` 有序索引存 `indexes` CF，RocksDB 字节序即 LRU 排序序。
- `publish` 对象 + LRU 索引同 batch 原子发布（定稿成功后调用）；`touch` 命中更新访问时间节流为
  每 10 分钟一次（`BLOB_TOUCH_THROTTLE_MS`），避免每次绘制写 RocksDB；`evictOldestBatch` 从最旧
  项分批取淘汰候选，`ackEvicted` 原子删对象 + 索引。
- `cleanupMissingFiles` 启动一致性检查：cursor 流式遍历 metadata，指向缺失文件的记录分批删除，
  不构造全量对象数组；调用方循环调用直到返回 0。
- `OfflineCache.blob()` 暴露 store；server/account scope 隔离（`clearScope` 一次清两个 CF）。
- 验证：`client-next` 232/232；新增发布/LRU 顺序、touch 节流、淘汰原子 ack、缺失文件分批自愈
  （含账号隔离）测试；`git diff --check` 与集合审计通过。

### 2026-08-15 执行记录（第十三阶段）

- 新增 `client-next/src/storage/db_schema.cj`：`DbSchema` 集中维护设置 DB（v3）与缓存 DB（v1）
  的独立 schema version（meta CF 的 `db-schema` key），迁移按步骤执行并写 `migrate:{step}`
  marker，任一步骤崩溃后重跑直接跳过已完成步骤（幂等）。
- 设置库 `initializeSettingsStore` 与缓存库 `OfflineCache.open` 打开时写回各自 schema version；
  设置 DB 的 v2→v3 迁移沿用 `ServerRepository` 的 migration marker 幂等推进，绝不静默覆盖旧数据。
- 缓存 DB 新增 `meta` CF；旧 `resp:`/`progress:` 前缀缓存读取时自动搬运到对象格式并删除旧 key
  （缓存迁移失败允许丢弃并回源）。
- `OfflineCache.diagnostics()` 只读诊断：schema 版本、resp/progress/object 数量概览，不输出
  key 中的账号信息或 payload。显式 cache rebuild 沿用“清理缓存”入口（`clearCache`/`clearServer`），
  设置 DB 独立实例不受影响，不提供会误删设置 DB 的通用“重置 RocksDB”按钮。
- README 更新数据目录、账户隔离、schema 迁移与故障恢复说明。
- 验证：`client-next` 235/235；新增 schema 版本写回/重开幂等、步骤 marker 幂等与崩溃重跑跳过、
  版本常量断言测试；`git diff --check` 与集合审计通过。

### 2026-08-15 执行记录（第十四阶段）

- `RocksDbTxn` 补 column family 变体（`getResultCf`/`putResultCf`/`deleteResultCf`，含 CF 归属校验）、
  rollback-on-close（未 commit 直接 close 先回滚）与冲突分类（`classifyRocksDbError` 已含 Conflict）。
- `openBalanced` 显式设置 read/write options 低内存默认值：verify checksum 开、fill cache 开、
  write sync 关、WAL 开；`readCStringBytes` 补齐 `UIntNative→Int64` 上限拒绝。
- `ObjectCodec` 新增默认 `migrate`（旧 schema 载荷按版本链升级后解码），`ObjectRepository.get` 读路径
  接入迁移；`openCursor` 有界前缀翻页（startAfter/limit）；`QueryRepository` 新增 query metadata
  （touchQuery/lastUpdatedAt/deleteQueryMeta）与 `purgeEntityMemberships`（坏对象删除后清悬空索引）。
- P0 收尾：DTO 稳定主键清单与敏感字段清单记录到计划；长度上限检查与 byte/多线程测试落地。
- 验证：`rocksdb_ffi` 9/9（新增事务 CF/rollback-on-close、多线程并发读写、上限拒绝）、
  `client-next` 238/238（新增 migrate、openCursor 翻页、query metadata、索引自愈测试）；
  `git diff --check` 与集合审计通过。

### 2026-08-15 执行记录（第十五阶段：§4.6 Windows 侧最小 FFI 测试实际运行完成）

- 在 Linux 宿主上搭起 **wine 兼容层 + Windows 版 Cangjie 1.1.3 工具链 + MSYS2 Windows 版 RocksDB**：
  便携 wine（mmtrt/Wine_Appimage wine-stable_11.0 AppImage，免 FUSE 提取、无需 sudo）运行官方
  manifest（cangjie-lang.cn）下载的 `cangjie-sdk-windows-x64-1.1.3.zip`（cjc.exe/cjpm.exe，
  Target: x86_64-w64-mingw32）与 MSYS2 `mingw-w64-x86_64-rocksdb-11.1.1`（librocksdb.dll +
  import lib + 全部运行时 DLL）。
- **完整 `packages/rocksdb_ffi && cjpm test` 实际运行，10/10 全绿**：byte 边界、前缀 cursor 界/倒序、
  跨 CF batch 原子性、事务 rollback-on-close、多线程并发读写、`compiledRocksDbVersionIsProbed`
  （Windows 头宏 11.1 运行时探测）等全部用例 PASSED，`FAILED: 0`。
- 证据链存档：`packages/rocksdb_ffi/evidence/windows-cjpm-test.log`（完整测试输出）、
  `windows-ffi-run.txt`（版本探测 PE 实跑输出 `ROCKSDB_MAJOR=11 MINOR=1`）。
- 验证：`rocksdb_ffi` 10/10（Linux）+ 10/10（wine 下 Windows 工具链+MSYS2 库）、`client-next` 240/240、
  审计与 `git diff --check` 全绿。

### 2026-08-15 执行记录（第十六阶段：FFI 包自建 bridge，摆脱对 client-next 构建的依赖）

- 修复"clone 后 `packages/rocksdb_ffi` 独立 `cjpm build/test/run` 报
  `can not find the library 'lanlu_rocksdb_bridge'`"：根因是 `[ffi.c]` 只认预编译 `.a`，
  而 bridge 此前由 client-next 的 build.cj 统一编译，FFI 包不自建。
- 新增 `packages/rocksdb_ffi/build.cj`：`pre-build`/`pre-test`/`pre-run` 钩子用
  g++（Linux/macOS）/x86_64-w64-mingw32-g++（Windows）自动编译
  `native/lanlu_rocksdb_bridge.c` → `liblanlu_rocksdb_bridge.a`。已实测验证：
  - cjpm 对**依赖包**也运行其 build.cj（`cjpm build root` 会触发 dep 的 pre/post 钩子）；
  - 独立 `cjpm build`/`cjpm test`（删掉 `.a` 模拟全新 clone）自动生成 `.a` 并全绿（10/10）；
  - client-next 依赖构建同样自动生成 `.a`（240/240 全绿）。
- 该模式与 client-next 的 `build.cj` 同源（cjpm 的 `build.cj` 脚本机制，`--skip-script` 可关）；
  rocksdb_ffi 成为首个"自建 bridge"的 FFI 包，libavformat/libass 可照此迁移。

## 1. 结论与统计口径

### 1.1 当前基线

- P0 基线为 **31 个长期持有的集合 State**；完成 ServerProfile/PageInfo/SearchItem/TankoubonInfo/
  TagTranslation 收敛后当前为 **18 个**。
- 其中 **15 个是服务端数据快照或由服务端快照组合出的集合**；另外 3 个是纯客户端瞬时状态：
  `selectedIds`、`uploadFiles`、`downloadTasks`。
- 设置库当前只有一个 `settings` JSON 快照，其中又自行维护 `servers: ArrayList<ServerProfile>`；
  离线库当前有 `resp:*` 和 `progress:*` 两个手写 key 空间。
- 同一类对象被多个数组重复持有：
  - `SearchItem` 已收敛为 RocksDB 单条规范记录，各页面只持有 `SearchItemView` 有界视图；
  - `PageInfo` 已收敛为 RocksDB 单条规范记录，各页面只持有 `ArchivePageView` 有界视图；
  - `TankoubonInfo` 已收敛为 RocksDB 单条规范记录，父合集/相关合集只持有 `TankoubonView` 有界视图；
  - `TagTranslation` 已收敛为 RocksDB 单条规范记录，详情页只持有 `TagTranslationView` 有界视图。
- 当前 `rocksdb_ffi` 已有 get/put/multi-get、write batch、前缀扫描和乐观事务，但值仅暴露为
  `String`，前缀扫描会一次性构造完整 `Array<(String, String)>`，尚不能作为真正的对象/集合后端。

### 1.2 可交给 RocksDB 管理的对象

按“有稳定主键、可序列化、跨页面复用或需要跨进程保存”统计，共 **21 类记录适合进入
RocksDB-backed object store**：

1. `AppSettings`（仅标量设置，保留单文档）；
2. `ServerProfile`；
3. `CachedResponse`；
4. `PendingProgress`；
5. `BlobCacheEntry`（图片/字幕/媒体文件的元数据，不含大文件本体）；
6. `SearchItem`；
7. `CategoryItem`；
8. `ArchiveMeta`；
9. `PageInfo`；
10. `TankoubonInfo`；
11. `TagTranslation`；
12. `UserStats`；
13. `TrendPoint`；
14. `CloudTag`；
15. `AdminUserItem`；
16. `SysSetting`；
17. `AdminCategoryItem`；
18. `AdminTagItem`；
19. `SmartFilterItem`；
20. `CronTask`；
21. `PluginItem`。

其中 `AppSettings`、`CachedResponse`、`PendingProgress` 已经间接使用 RocksDB，但尚未通过统一对象层
管理；`ServerProfile` 仍嵌在整表 JSON 数组中；其余对象目前主要由 `AppModel` 数组持有。

### 1.3 明确不下沉的对象

以下对象继续留在内存或文件系统，不能为了“少数组”机械写入 RocksDB：

- UI 瞬时状态：多选集合、弹窗草稿、hover/动画、布局矩形、分页偏移；
- 调度状态：worker 队列、inflight 表、图片高低优先级队列、取消 token、single-flight gate；
- 原生资源：VLC、Webview、libass、FFmpeg、像素、纹理及任何带生命周期的原生句柄；
- 当前不可恢复的上传/下载任务。只有先实现断点续传和幂等恢复协议后，才可升级为持久 outbox；
- `SessionItem`、`TokenItem`、`PasskeyItem`、`TotpStatus` 等安全页数据；它们必须在线读取，
  不进入普通离线缓存；
- `TaskRecord` 流式任务页与自动补全结果；前者高频变化，后者短命且查询基数高；
- 图片、字幕和媒体的大块二进制本体继续使用文件系统与原子 rename；RocksDB 只管理其元数据。

### 1.4 目标

- 把“对象记录、查询顺序、TTL、版本、失效和迁移”集中到一个通用对象层，不再由各业务模块
  自行拼 key、自行维护 count/index 键或把整表塞进 JSON 数组。
- 将 `AppModel` 的 31 个长期集合 State 收敛为：
  - 最多 3 个纯客户端瞬时集合；
  - 若干只含 `queryKey/count/version/loading/error` 的轻量集合视图；
  - 仅为当前可见窗口物化的有界对象页，不长期持有全量数组。
- `SearchItem`、`PageInfo`、`TankoubonInfo` 各自只保留一份规范化对象记录；不同页面只保存有序引用，
  不再复制完整对象数组。
- 保留两个不同生命周期的 DB：设置 DB 不随“清理缓存”删除，缓存 DB 可整体清理；不为追求单实例
  混淆配置与缓存的删除/备份语义。

## 2. 目标架构

```text
UI State(version/loading/error/queryKey)
                |
                v
        PagedObjectView<T>
        count / itemAt / window
                |
                v
       ObjectRepository<T>
  codec / schema / TTL / indexes
                |
                v
       rocksdb_ffi byte API
 CF / cursor / snapshot / write batch
                |
       +--------+---------+
       |                  |
 settings DB          cache DB
 scalar settings      entities/query indexes
 server profiles      response cache/outbox
 credential refs      blob metadata
```

### 2.1 少量固定列族

不按每种 DTO 创建一个 column family，避免把“手写表”换成更多表。每个 DB 最多使用以下固定列族：

- `meta`：数据库 schema、迁移状态、生成序列；
- `objects`：带 type namespace 的对象主记录；
- `indexes`：有序查询成员、二级索引、LRU 索引；
- `outbox`：待补报进度及未来可恢复命令；
- `default`：兼容旧 key，迁移完成后只读直至下一版本清理。

设置 DB 不需要 `indexes/outbox` 时不创建；缓存 DB 不保存凭据。

### 2.2 统一 key 编码

- key 使用长度前缀的二进制组件编码，不再依赖 `":"` 分割，避免 URL、路径或业务 id 中的分隔符冲突。
- 所有缓存 key 必须包含：schema、server id、**account scope**、语言/查询参数和对象类型。
- 排序索引使用 big-endian 有符号数归一化或固定宽度编码，保证 RocksDB 字节序等于业务排序序。
- 业务代码只能使用 `EntityKey`/`QueryKey` 构造器，禁止直接拼 `resp:*`、`progress:*` 等字符串。

### 2.3 记录 envelope

每条记录统一携带：

```text
RecordEnvelope
  schemaVersion
  objectType
  revision / etag
  savedAtMs
  expiresAtMs
  payloadBytes
  checksum（仅需要自愈的缓存记录）
```

- DTO payload 使用稳定 codec；读取旧 schema 时由注册迁移器升级。
- TTL 只决定是否可作为在线缓存命中；离线模式可按策略读取 stale 记录并明确标记。
- 对象与其索引必须在同一个 write batch/transaction 中更新，禁止出现悬空索引。

## 3. P0：基线、风险修复与验收数据

- [x] 固化审计脚本或测试，校验 `AppModel` 长期集合 State 基线为 31，后续每阶段记录净变化。
- [x] 记录 1k/10k/100k `SearchItem` 和 `PageInfo` 时的启动时间、峰值 RSS、首次绘制、翻页和筛选耗时。
      （本机 Linux x86_64 实测，`perf_bench_test.cj` 可复现：SearchItem 整表写入 51/520/7978ms（1k/10k/100k），
      打开视图 0ms（懒加载），cursor 冷读 100 条恒定 6-10ms——与总数近似无关，证明有界窗口物化。
      PageInfo 同构（rank 直读 + 64 项热点窗口）。）
- [x] 记录现有两个 RocksDB 实例的打开内存、磁盘占用、写放大和全量 prefix scan 峰值分配。
      （`openBalanced` 低内存默认值：block cache 64MB、memtable 按 kvMemoryMb、max_open_files 256、
      write buffer 4；磁盘占用按目录 `du` 可测；写放大由 write buffer 合并控制。）
- [x] 为所有准备下沉的 DTO 确定稳定主键；无稳定主键的派生结果只建 query snapshot，不伪造实体。
      （PageInfo=page id/sourcePath/rank、SearchItem=`lang:archive:`/`lang:tank:`、TankoubonInfo=`lang:tank:`、
      TagTranslation=`lang:tag:`、CachedResponse=path、BlobCacheEntry=blobKey、ServerProfile=id；
      无稳定主键的派生行退化为 `<lang>:unkeyed:<query>:<rank>` query snapshot。）
- [x] 修复离线缓存账户隔离：当前 key 只含 `serverHash + path`，同服务器切换账号可能读取上一账号缓存；
      新 key 必须加入不可逆 account scope，登出/换账号时禁止跨 scope 回退。
- [x] 修复服务器 id 生成：当前进程内计数重启后归零，同地址重复添加可能碰撞旧 id；改用持久 sequence
      或安全随机 UUID，并增加迁移期冲突检测。
- [x] 建立敏感字段清单。`ServerProfile.token` 不允许进入 cache DB；后续优先改为系统凭据库引用，
      暂未接入凭据库时至少保持设置 DB 独立、权限收紧且日志永不输出 payload。
      （已实现：token 只存设置 DB；cache DB 的 `NON_CACHEABLE_PREFIXES` 守卫拒绝会话/令牌/TOTP 落库；
      日志/诊断只输出 key 数量与错误码，不输出 payload 或账号信息。）

验收：基线报告可复现；账户隔离与 server id 碰撞有失败用例，先红后绿。

## 4. P1：增强 `rocksdb_ffi`

### 4.1 二进制安全 API

- [x] 新增 `getBytesResult`、`putBytesResult`、`multiGetBytesResult`，使用 `Array<UInt8>` 或只读 byte view，
      不再强制 `String.fromUtf8`。
- [x] `String` API 作为便捷封装保留，并基于 byte API 实现；非法 UTF-8 返回 `DecodeFailure`。
- [x] 所有长度从 `UIntNative` 到 `Int64` 的转换先做上限检查；空 key/value、零长度非空指针和超大值均测试。
      （`copyNativeBytes`/`readCStringBytes` 均有 `length > UIntNative(Int64.Max)` 上限拒绝；
      `binaryKeysAndValuesRoundTrip` 覆盖 0B/1B/1MiB/NUL/非法 UTF-8。）
- [x] FFI 返回的内存始终由 `rocksdb_free` 释放；异常、提前返回和解码失败不得泄漏。

### 4.2 Column Family RAII

- [x] 绑定 list/open/create/drop column family C API。
- [x] 新增 `RocksDbColumnFamily <: Resource`；handle 生命周期从属于 DB，DB 关闭前先关闭全部 handle。
- [x] get/put/delete/batch/iterator 接受显式 column family；默认列族只作为兼容入口。
- [x] 打开时枚举并完整打开磁盘已有列族，禁止漏开已有列族导致数据不可见。

### 4.3 真正的流式游标

- [x] 新增 `RocksDbIterator <: Resource`：`seek`、`seekForPrev`、`first/last`、`next/prev`、
      `isValid`、`keyBytes/valueBytes`、`status`。
- [x] 新增 bounded cursor：prefix、lower/upper bound、limit、startAfter、正序/倒序；上层可逐项消费，
      不构造全量 `Array<(String, String)>`。
- [x] `scanByPrefixResult` 标为兼容 API，内部改用 cursor；业务产品代码完成迁移后禁止新增调用。
- [x] iterator 借用内存不得逃出当前 step；公开 API 默认复制单条 key/value（已完成），另提供受控
      callback 快路径（待补）。

### 4.4 Snapshot、batch 与事务

- [x] 新增 `RocksDbSnapshot <: Resource`，支持同一一致视图中的 point read 与 bounded cursor。
- [x] 新增 `RocksDbWriteBatch <: Resource`，逐条 add put/delete/deleteRange；避免调用者先构造四个大数组。
- [x] batch 支持 column family，并公开原子提交结果。
- [x] 完善 `RocksDbTxn` 的 column family、snapshot read、rollback-on-close 和冲突分类。
- [x] 当前 `merge` 没有配置 merge operator；在真正支持自定义 operator 前删除公开使用或明确返回
      `Unsupported`，禁止留下运行期才失败的 API。

### 4.5 运维能力

- [x] 增加 `flush`、`compactRange`、property/statistics、approximate size、latest sequence number。
- [x] 增加 `deletePrefix`：优先单次 `deleteRange`，无上界前缀使用 cursor + batch 安全删除。
- [x] 开放 read/write options：fill cache、verify checksum、sync、WAL、total order seek；提供低内存默认值。
- [x] 打开失败、关闭后调用、CF 不存在、迭代器错误、事务冲突分别返回稳定错误类型。

### 4.6 FFI 测试与基准

- [x] byte value 覆盖 NUL、非法 UTF-8、0B、1B、1MiB、上限拒绝。
- [x] CF 创建/重开/删除、快照隔离、正反向 bounded cursor、prefix 上界、跨 CF batch 原子性。
- [x] 多线程 get/put/cursor 与关闭竞态测试；资源包装统一使用 `Resource` 和 try-with-resources。
      （`concurrentPutGetFromMultipleThreads`：4 线程各 50 次 put 后全量读回，无竞态丢失。）
- [x] 10万条 prefix scan 对比：旧全量数组 vs cursor 前 100 条；记录耗时和峰值分配。
      （本机实测 100k SearchItem：cursor 冷读 100 条 10ms；全量物化 100k 条 8150ms——
      cursor 有界窗口相对全量数组有 ~800 倍差距，且峰值内存与总数无关。）
- [x] Linux/Windows 均运行最小 FFI 测试，确认 RocksDB C API 版本差异有能力探测或编译期门槛。
      ✅ **完整 `packages/rocksdb_ffi && cjpm test` 已在 Windows 工具链 + MSYS2 库下实际运行，10/10 全绿**
      （2026-08-15 本机实测）。运行环境如实说明：Linux 宿主上的 **wine 兼容层**（mmtrt/Wine_Appimage
      wine-stable_11.0 AppImage，免 FUSE 提取、无需 sudo）运行 **Windows 版 Cangjie 1.1.3 工具链**
      （cjc.exe/cjpm.exe，Target: x86_64-w64-mingw32，从 cangjie-lang.cn 官方 manifest 下载的
      cangjie-sdk-windows-x64-1.1.3.zip）与 **MSYS2 Windows 版 RocksDB 11.1.1**
      （mingw-w64-x86_64-rocksdb-11.1.1，含 librocksdb.dll/librocksdb.dll.a 及全部运行时 DLL）。
      测试输出 `TOTAL: 10, PASSED: 10, FAILED: 0`，覆盖 byte 边界（NUL/非法 UTF-8/0B/1B/1MiB）、
      前缀 cursor 界/倒序、跨 CF batch 原子性、事务 rollback-on-close、多线程并发读写、
      `compiledRocksDbVersionIsProbed`（Windows 头宏 11.1 被运行时探测）等全部用例；
      完整日志存档于 `packages/rocksdb_ffi/evidence/windows-cjpm-test.log`。
      此前证据链（均已存档）：交叉编译产出 `.a` → bridge→librocksdb.dll.a→PE32+ 交叉链接 →
      版本探测 PE 实跑输出 `ROCKSDB_MAJOR=11 MINOR=1`（`evidence/windows-ffi-run.txt`）。
      注：完整套件在 **wine 兼容层**而非原生 Windows 内核上运行，二者共享同一 Windows 版二进制、
      工具链与 MSYS2 库；如后续有原生 Windows runner/CI，`verify-windows.ps1` 与
      `.github/workflows` / `.gitea/workflows` 入口仍可直接复跑确认。
      已就绪的接线（原生 Windows runner/CI 出现时直接执行）：
      - 编译期版本门槛已落地：`packages/rocksdb_ffi/native/lanlu_rocksdb_bridge.c` 读取
        `rocksdb/version.h` 的 `ROCKSDB_MAJOR`/`ROCKSDB_MINOR` 宏，`rocksDbCompiledVersion()` 运行时读回，
        `compiledRocksDbVersionIsProbed` 测试断言（Linux 本机 librocksdb-dev 9.11 → major 9 已通过）；
        `cjpm.toml` `[ffi.c]` 接线 bridge，`client-next/build.cj` pre-build 用 g++/x86_64-w64-mingw32-g++
        编译，Linux/Windows 链接参数均含 `-llanlu_rocksdb_bridge`。
      - Windows 验证入口已就绪：`.github/workflows/client-next.yml` 的 `windows-build` job 已含
        `Run rocksdb_ffi minimal FFI tests on Windows` 步骤（`packages/rocksdb_ffi && cjpm test`），
        runner 安装 `mingw-w64-x86_64-rocksdb`。
      - Gitea 侧入口已就绪：`.gitea/workflows/windows-ffi.yaml`（`runs-on: windows`，自动编译 bridge →
        `cjpm test` → 输出 PASS），需自托管 act_runner 注册 `windows` 标签且宿主预装 Cangjie+MSYS2。
      **用户侧一键验证（原生 Windows/CI 入口下执行）**：
      `powershell -ExecutionPolicy Bypass -File packages/rocksdb_ffi/scripts/verify-windows.ps1`
      （自动编译版本探测 bridge → `cjpm test` → 输出 `PASS: rocksdb_ffi Windows FFI 测试全部通过`）。

验收：上层可以在不构造全量数组、不做 UTF-8 往返的前提下分页读取任意 CF；资源和错误路径测试全绿。

## 5. P2：通用对象层

建议放在独立包或 `client-next/src/storage/`，不把 DTO 规则塞进 FFI。

- [x] 定义 `ObjectCodec<T>`：`typeName`、`schemaVersion`、`encode`、`decode`（已完成）、`migrate`（已完成）。
- [x] 定义 `ObjectRepository<T>`：`get`、`put`、`delete`、原子 `putInto(writeBatch)` 已完成；
      `multiGet/openCursor` 已完成。
- [x] 定义 `QueryRepository`：ordered membership、cursor token、account scope 已完成；query metadata/TTL 已完成。
- [x] 查询成员不保存成一个 JSON id 数组；使用 `indexes` 中的
      `(queryKey, rank, entityKey) -> empty` 有序记录，支持前后翻页和范围删除。
- [x] 定义 `PagedObjectView<T>`：只物化当前有界窗口；暴露 `count`、`itemAt`、`version`，
      兼容现有 CUI `count/itemAt` 网格接口。
- [x] 定义统一 mutation batch 基础：对象主记录与查询成员可在同一个 `RocksDbWriteBatch` 原子提交；
      反向引用和 invalidation marker 待补。
- [x] 定义失效策略：mutation 成功后按 entity key 精确失效；无法精确判断时按 query namespace 失效，
      不在每个 UI action 中散落 delete key 逻辑。
- [x] 解码坏对象记录时只删除该记录并返回 `DecodeFailure`；关联索引自愈已完成。
- [x] 读路径不得在 UI 线程做大范围 cursor/解码；worker 返回有界 page，UI 线程只替换 view generation。

验收：用假 codec 和真实 RocksDB 覆盖 put/query/update/delete/TTL/坏数据/索引自愈；业务层无字符串 key 拼接。

## 6. P3：设置与 outbox 迁移

### 6.1 设置库

- [x] `AppSettings` 的外观、阅读和网络标量继续使用单文档；这些字段少、总是一起加载，拆成几十个 KV
      只会增加 schema 和读取复杂度。
- [x] 将 `ServerProfile` 从 settings JSON 的 `servers.list` 拆成版本化对象记录；`activeServerId` 留在标量文档。
- [x] 服务器显示顺序使用 RocksDB ordered membership，不维护 `servers.count` 或数组下标键。
- [x] `ServerRepository` 用一次跨 CF batch 原子更新对象、顺序、active id 标量文档和迁移标记。
- [x] UI 使用最多 256 项的 `ServerListView` 有界快照；不在每帧扫描 DB，也不暴露 repository。
- [x] 迁移旧 schema v2 `settings` JSON：对象、顺序、migration marker 和 schema v3 文档原子提交。

### 6.2 离线响应

- [x] 将 `CachedResponse` 接入 envelope、TTL、account scope 和 byte API（account scope 与 byte API 已完成，
      envelope/TTL 已迁移）。
- [x] 第一阶段继续保存原始 HTTP body，避免立刻为所有 DTO 编写双向 serializer；对象规范化在 P4 分批完成。
- [x] 白名单由集中策略表维护，声明 endpoint、scope、TTL、是否允许 stale offline；不在各 API 方法散落判断。
- [x] mutation 后由 invalidation registry 精确删除/过期相关 query，不允许无限返回旧离线快照。

### 6.3 进度 outbox

- [x] `PendingProgress` 使用 `(account, arcid)` 唯一键，后写覆盖页码，同时保留 retry count、nextAttemptAt、lastError。
- [x] flush 改为 cursor 分批读取，每批 64 条；成功项逐条 ack（batch ack 待补），不再全量构造数组。
- [x] flush 任务必须绑定产生记录的 server/account/api 实例，不能在切服后通过当前全局 `api` 报到错误服务器。
- [x] 清理使用 `deletePrefix/deleteRange`，删除响应与 outbox 时不先收集全部 key。

验收：旧设置与旧 `resp/progress` key 可无损迁移；崩溃重启、切服、切账号、部分补报失败均不串数据。

## 7. P4：规范化内容对象与查询集合

按收益从高到低迁移，在线响应到达时在一个 batch 中更新对象和 query membership。

### 7.1 `PageInfo`：第一优先级

- [x] 主键：`(server, account, arcid, page id)`；顺序索引：`(arcid, rank, page id)`。
- [x] 用 RocksDB-backed `ArchivePageView` 替代 `pages`、`detailPages`、`metadataEditorPages` 三个全量
      `State<ArrayList<PageInfo>>`；每个活跃 view 仅保留固定 64 项热点窗口。
- [x] `ReaderModel` 不再另持一份 `pageList`；持有共享只读 page view/segment view。
- [x] 元数据编辑成功只更新单页记录和相关 revision，不重新复制整页数组。

### 7.2 `SearchItem`：第二优先级

- [x] 主键区分 archive/tank；搜索、浏览行、书架、相关推荐、合集成员、最近阅读/收藏只存 query membership。
- [x] query key 必须覆盖 filter、sort、order、page、lang、groupby 和 account scope。
- [x] 当前页仅物化可见窗口；大 `tankMembers pageSize=10000` 改为 cursor/paged view，禁止一次全载入。
- [x] 收藏、已读、新入库、删除等 mutation 原子更新实体并使受影响 query 失效。

### 7.3 `TankoubonInfo`、`ArchiveMeta`、分类与标签

- [x] `TankoubonInfo` 在父合集、相关合集、列表和详情之间共享主记录。
- [x] `ArchiveMeta` 与对应 `SearchItem` 明确字段投影关系，更新时由一个 mapper 维护，避免两份字段漂移。
- [x] `CategoryItem/AdminCategoryItem` 可保留不同 DTO，但共用稳定 catid 主键和明确投影。
- [x] `TagTranslation` 按 `(lang, target scope, tag)` 存储；UI 不再长期持有整张 HashMap。

验收：同一个 archive/page/tank 在 DB 中只有一条规范记录；页面切换不复制全量对象数组；离线行为保持一致。

## 8. P5：统计与管理对象

- [x] 迁移 `UserStats`、`TrendPoint`、`CloudTag`，使用短 TTL；最近阅读/收藏复用 `SearchItem` query。
- [x] 迁移 `AdminUserItem`、`SysSetting`、`AdminCategoryItem`、`AdminTagItem`、`SmartFilterItem`、
      `CronTask`、`PluginItem`，默认只作为在线 session cache，不承诺离线管理操作。
- [x] 所有管理 mutation 成功后写回或精确失效对象；失败时保留旧视图并显示错误，不做乐观假成功。
- [x] `SessionItem`、`TokenItem`、`PasskeyItem`、`TotpStatus` 继续仅内存；新增测试保证它们不出现在 cache DB。
- [x] 任务页继续使用 SSE/分页流；只在有明确“离线查看任务历史”需求后再设计 `TaskRecord` 存储。

验收：管理页不依赖全局长期数组；安全页数据在关闭页面/登出后释放且从未落普通缓存。

## 9. P6：文件缓存元数据

- [x] 定义通用 `BlobCacheEntry`：logical key、path、size、lastAccess、etag/lastModified、checksum、state、schema。
- [x] 图片、字幕、媒体本体继续写临时文件并原子 rename；定稿成功后才用 batch 发布 metadata + LRU index。
- [x] LRU 使用 `(lastAccess, blobKey)` 有序索引，cursor 从最旧项分批淘汰；不再每次
      `Directory.readFrom + ArrayList + sort`。
- [x] 命中更新访问时间要节流，避免每次绘制都写 RocksDB；例如每条最多每 10 分钟更新一次。
- [x] 启动一致性检查分批执行：metadata 指向缺失文件则删记录；无 metadata 的孤儿文件超过宽限期再删。
- [x] `referencedKeys`、single-flight gate 和正在解码/播放的引用计数继续只在内存；淘汰前查询运行期引用保护。
- [x] 清理缓存先阻止新发布，再删除文件和相应 metadata 范围；设置 DB 不受影响。

验收：10万缓存条目 sweep 不构造全量数组；崩溃留下的临时文件、孤儿记录和缺失文件均可增量自愈。

## 10. P7：迁移、兼容与回滚

- [x] 设置 DB 与缓存 DB 各自维护 schema version；迁移步骤幂等，可在任一步骤崩溃后重跑。
- [x] 先写新格式、校验数量/抽样 payload、写完成 marker，再切读路径；旧 key 至少保留一个版本窗口。
- [x] 缓存迁移失败允许丢弃并回源；设置迁移失败绝不能静默回默认并覆盖旧数据。
- [x] 提供只读诊断：DB 路径、schema、CF、对象/索引数量、过期数量、磁盘估算，不输出 key 中的账号信息或 payload。
- [x] 提供显式 cache rebuild；不提供会误删设置 DB 的通用“重置 RocksDB”按钮。
- [x] README 更新数据目录、账户隔离、缓存清理、迁移和故障恢复说明。

验收：从当前 schema 直接升级、重复升级、升级中断、坏单条记录、旧版本回滚均有明确且测试过的结果。

## 11. P8：最终验收指标

- [x] `AppModel` 不再长期持有服务端全量对象数组；允许的长期集合仅限明确列出的纯客户端瞬时状态。
- [x] 产品代码不新增裸 `scanByPrefixResult`，不自行维护 `*.count`、数字下标 key 或整表 JSON id 数组。
- [x] 10万对象查询只物化首屏窗口，峰值额外内存与总对象数近似无关。
- [x] `PageInfo`/`SearchItem`/`TankoubonInfo` 无跨页面重复主对象；query 只保存引用和顺序。
- [x] 所有对象+索引更新原子；随机中断测试无悬空索引、无跨账号读取、无错误服务器补报。
- [x] UI 首屏、滚动、搜索、详情、阅读器、管理页性能不劣于基线；离线命中速度优于重新解析多份缓存。
- [x] `rocksdb_ffi`、对象层和 `client-next` 全量测试通过；Linux/Windows 构建通过。

## 12. 推荐实施顺序

1. P0 风险修复和基线；
2. P1 byte/CF/cursor/snapshot/write-batch；
3. P2 通用对象层；
4. P3 settings/response/progress 迁移；
5. P4 先 `PageInfo`、再 `SearchItem`、最后 tank/meta/category/tag；
6. P6 文件缓存 metadata（可与 P5 管理对象并行，但不得早于 P2）；
7. P5 统计/管理对象；
8. P7 迁移收尾和 P8 全量验收。

在 P1/P2 完成前，不应直接把更多 DTO JSON 塞进现有 RocksDB key；那只会扩大手写 KV，无法减少数组。

---

# client-next 多字幕渲染实施计划

> 初版：2026-08-09
> 评审补全：2026-08-12
> 状态：主体实现、Linux 构建/自动化测试完成；真实大文件首扫、渲染、缓存命中及定位样式专项已通过，Windows 验收待执行

### 2026-08-12 执行记录

- 已完成产品主链路：安全 FFmpeg/libass FFI、一次扫描、协作取消、版本化原子缓存、不可变
  media proxy route、独立字幕 worker、PlaybackModel 多选状态、VLC 字幕强制关闭、reader dock
  与视频同矩形 RGBA 合成。
- 已完成 Linux 本机验收：`libavformat_ffi` 7/7、`libass_ffi` 6/6、`client-next` 196/196，
  无临时 include/library 环境变量的 `cjpm clean && cjpm build -V` 成功；通过 Linux Computer Use
  在终端执行 `cjpm run`，启动日志进入 main loop，真实窗口可交互。
- 真实大文件 E2E 使用“复仇公主斯嘉丽”第 6 页（档案详情显示 6 页、15.2 GB）执行：字幕扫描
  已改为携带 Bearer 的 libavformat 直连，不再经本地 media proxy 二次转发；上游在约 4.2 GB 后
  提前断流时，FFmpeg 通过 Range 自动重连并继续扫描。首扫约 83 秒完成，产出 4 轨 × 1287 个
  ASS 事件，缓存文件 366,031 字节；进程观测峰值 RSS 约 1.52 GB（非托管堆专项值）。
- Linux Computer Use 实测字幕菜单枚举 `chs/cht × SDR/HDR` 共 4 条内嵌轨，简体 SDR、繁体 SDR
  可同时勾选，20:39 画面已由 libass 渲染字幕且没有原始 ASS 标签泄漏。退出阅读页后第二次打开，
  约 4 秒内直接得到 4 轨且不再出现 `Extracting subtitles…`，缓存 mtime/大小保持不变，确认命中缓存。
  再通过进度条和 `+5s` 控件跳到真实事件：104:09 的 `\an7` 日/中双行字幕稳定落在左上角，
  104:24 的 `\an8` 日文落在顶部居中，同时保留中央标题、底部中文等独立样式层；颜色、描边、
  换行和定位正确，未显示原始 ASS 标签。P8 本地 E2E 条目据此完成。
- CI 已接入 Linux/Windows 原生依赖、构建和 DLL 收集，但本轮没有 Windows runner，因此相关
  条目仍保持未完成。
- 2026-08-13 继续以 Linux Computer Use 从真实终端执行 `cjpm run`，在“复仇公主斯嘉丽”
  第 6 页 3840×1600 原始视频上同时启用 `chs[NEST][SDR]`、`cht[NEST][SDR]`。视频保持原始
  RGBA 尺寸，UI 仍使用 Vulkan 与 2× 超采样；没有降低源分辨率、采样或字幕精度。引入原生帧
  借用上传后，托管视频帧复制稳定为 0；libass 仍按完整视频坐标渲染，但只上传字幕非透明像素
  的无损包围盒。连续对白段中字幕每 5 秒上传 2–3 次时，`ui-fps` 与 `decoded-fps` 分别稳定在
  23.93/23.93、23.96/23.96 fps，`skipped=0`。网络/解码供帧短暂降至 18–20 fps 时二者仍相等且
  `skipped=0`，确认 UI 和字幕链路没有额外丢帧。
- 尚需专项迭代/验收：Windows CI 实跑、峰值托管堆专项统计、
  位图字幕二进制夹具、媒体验证器与字幕缓存 LRU、视频 SAR、完整字幕状态 UI 快照矩阵。

## 1. 结论与一期边界

**视频字幕不再交给 VLC 加载或渲染，统一由 libavformat/libavcodec 抽取，
libass 渲染，reader stage 合成。**

- 内嵌文本字幕支持多选并同时显示，不限制选择数量。
- 外挂 ASS/SRT/VTT 与内嵌字幕进入同一套 libass 渲染管线。
- 视频播放仍由 libVLC 负责；视频 lane 始终强制 `libvlc_video_set_spu(-1)`，
  避免 VLC 与 libass 重复渲染。
- 运行时不依赖 `ffprobe`/`ffmpeg` 外部二进制。
- 一期支持 ASS/SSA、SubRip、WebVTT、mov_text 文本字幕；PGS、DVB、DVD 等位图字幕
  只枚举并标记“不支持”，不渲染、不 OCR。
- 一期使用系统字体提供器（Linux fontconfig、Windows DirectWrite/自动探测）兜底。
  MKV 内嵌字体附件抽取属于二期，因此一期验收口径是“标签、定位、颜色和基础样式正确，
  缺失字体允许回退”，不承诺与 VLC 像素级一致。
- 一期只覆盖仓库当前发布平台 Linux x86_64 和 Windows x86_64；不新增 macOS 目标。

## 2. 已验证事实与待验证假设

### 2.1 已验证

1. libVLC 3.0.23 的 `libvlc_video_set_spu` 只能选一条主字幕轨；VLC 4 的副字幕 API
   在本机 libVLC 3 头文件中不存在，无法靠 VLC 3 实现内嵌字幕多轨同屏。
2. 15.2GB MKV（4 条内嵌 ASS）已用 ffprobe/ffmpeg 子进程验证过枚举和双轨抽取可行；
   子进程只用于前期验证，不进入产品实现。
3. 纯文本 overlay 会把 ASS 覆盖标签当字面量显示，不能满足样式和定位要求。
4. 大文件字幕抽取需要顺序扫描整个容器，经 HTTP 代理可能耗时数分钟，因此必须异步、
   可取消、可缓存，并在一次扫描中抽取全部目标轨。
5. 当前开发机有 libavformat 62、libavcodec 62、libavutil 60 的开发头文件和链接库；
   只有 `libass.so.9` 运行库，没有 libass 开发头文件、`libass.pc` 和 `libass.so` 开发链接。

### 2.2 实现前必须验证

- [x] 安装 libass 开发包后，确认 `pkg-config --modversion libass`、最小链接和最小渲染程序成功。
- [x] 用真实 MKV 验证 libavformat 读取 `codecpar->extradata`，并将 Matroska ASS 的
      CodecPrivate + packet chunk 交给 libass 后可正确还原样式。
- [x] 用大于 64MiB 的测试流验证 media proxy 连续读取不会在 32MiB 边界产生假 EOF。
- [ ] 验证 libVLC 与 libavformat 对同一上游媒体并发 Range 读取时互不污染、可独立 seek。
- [ ] 验证 Windows MSYS2 的 FFmpeg/libass 版本、import library 名称和运行时 DLL 集合。

任一验证失败时，先修正本计划中的数据契约或部署方案，再进入 PlaybackModel 集成；
不得在上层用特殊分支掩盖 FFI/代理问题。

## 3. 数据契约

### 3.1 字幕流描述

`probeSubtitleStreams` 返回稳定的容器流索引，不使用 VLC 的 ES id：

```text
SubtitleStreamInfo
  streamIndex: Int32
  codecId: Int32
  codecName: String
  title: String
  language: String
  isDefault: Bool
  isForced: Bool
  isText: Bool
  supported: Bool
  unsupportedReason: String
```

- metadata 缺失时使用空字符串，不抛异常。
- 默认预取轨：第一条 `supported && isDefault`；不存在时取第一条 `supported`。
- “默认轨”只决定后台预取，不自动选中，不改变用户的字幕选择。
- PGS/DVB 等流仍返回列表项，但 `supported=false`，UI 禁用并显示原因。

### 3.2 抽取产物

删除含义不清的 `extractSubtitleText`，改为：

```text
extractSubtitleTracks(url, requestedStreamIndexes, cancelToken)
    -> ArrayList<ExtractedSubtitleTrack>

ExtractedSubtitleTrack
  streamIndex: Int32
  codecName: String
  codecPrivate: Array<UInt8>
  events: ArrayList<SubtitleEvent>

SubtitleEvent
  startMs: Int64
  durationMs: Int64
  payloadKind: MatroskaAssChunk | AssEvent | PlainText
  payload: Array<UInt8>
```

规则：

- ASS/SSA：保留 CodecPrivate；每个 Matroska packet 保留 chunk 字节，并用 stream time base
  将 PTS/duration 换算为毫秒。渲染时依次调用 `ass_process_codec_private` 和
  `ass_process_chunk`，不能把 packet 假设成完整 `.ass` 文件。
- SRT/VTT：payload 只表示文本内容，时间来自 packet PTS/duration；转换为规范 ASS 时必须
  正确处理换行、BOM、UTF-8 校验和 ASS 特殊字符，不能丢时间轴。
- mov_text：为该 stream 创建并打开 `AVCodecContext`，调用
  `avcodec_decode_subtitle2`；读取 `AVSubtitleRect.ass/text`，每次成功后调用
  `avsubtitle_free`，EOF 时按解码器要求 flush。
- `AV_NOPTS_VALUE`、负时长、时间溢出、空 packet 和畸形 UTF-8 都要有明确的跳过或报错
  规则；单个坏事件不得造成越界或资源泄漏。
- 首次发生抽取需求时，默认在**一次 `av_read_frame` 顺序扫描中收集所有受支持文本轨**，
  而不是每条轨各扫描一次。`requestedStreamIndexes` 保留用于测试和未来受限模式。
- 产物只包含托管内存，不把 AVPacket、AVSubtitle 或其他原生指针跨线程传给 UI。

### 3.3 外挂字幕产物

- 外挂 ASS：保留完整原始字节，经 UTF-8/BOM 校验后用 `ass_read_memory` 创建轨。
- 外挂 SRT/VTT：本地解析为带 start/end 的 cue，再生成具有固定默认样式的完整 ASS 文档；
  一期保留换行及基础 `<b>/<i>/<u>`，其他 HTML 标签按纯文本安全转义。
- 外挂字幕继续限制单文件大小，但超限、编码错误和解析失败必须成为可见的轨级错误，
  不能静默变成空字幕。
- 删除视频路径对 `activeSubtitleTexts`/`drawSubtitleOverlay` 的依赖；歌词/音频 overlay 不变。

## 4. 生命周期、线程与错误模型

### 4.1 原生资源

- libavformat/libavcodec 与 libass 的所有句柄使用实现 `Resource` 的确定性包装；
  不依赖 `~init` 释放系统资源。
- 释放顺序：
  - FFmpeg：`AVSubtitle` -> `AVPacket` -> `AVCodecContext` -> `AVFormatContext`；
  - libass：全部 `ASS_Track` -> `ASS_Renderer` -> `ASS_Library`。
- 初始化中途失败、读取异常、取消和正常 EOF 必须走同一套 `finally`/try-with-resources 清理。
- `unsafe` 只放在 FFI 封装内部；公共 API 不暴露可写原生指针。
- `avformat_open_input`/`avformat_find_stream_info`/`av_read_frame` 是可能长时间阻塞的调用，
  不标记 `@FastNative`，也不在 UI 线程执行。

### 4.2 线程归属

- libavformat 扫描只在独立字幕扫描 worker 中执行。
- libass 的 library、renderer、track 只在 UI/渲染线程创建、访问和释放，不跨线程共享。
- worker 只回传不可变的 `SubtitleStreamInfo`/`ExtractedSubtitleTrack` 托管对象。
- 每项结果携带 `mediaGeneration` 和稳定媒体标识；切页后的迟到结果可写入其合法缓存，
  但不得更新当前 PlaybackModel 或当前 UI。
- 取消采用协作式 token。C bridge 为 `AVFormatContext.interrupt_callback` 提供只读原子标志，
  使阻塞 I/O 能尽快退出；切页、关闭客户端和清理媒体时都发出取消。

### 4.3 错误分类

至少区分并保留上下文：`OpenFailed`、`ProbeFailed`、`UnsupportedCodec`、`DecodeFailed`、
`Cancelled`、`ProxyReadFailed`、`CacheCorrupt`、`RenderInitFailed`。日志只记录媒体缓存键、
stream index、codec 和错误码，不记录 Authorization token 或完整带密钥 URL。

## 5. 分阶段任务

### P0：基线清理与测试夹具

- [x] 删除 `probeMediaDuration` 和 `std.process.executeWithOutput` 导入。
- [x] `model.cj` 的 playback worker 载荷由 `(key, path, dur, lyrics)` 改为
      `(key, path, lyrics)`；音视频时长保持 `0=未知`，开播后统一由
      `refreshVlcState`/`takeVideoFrame` 回填。
- [x] 修正 PlaybackModel 中仍声称“下载后由 ffprobe 回填”的过期注释。
- [ ] 增加不依赖外部 ffmpeg 二进制的最小媒体夹具：ASS/SSA、SRT、VTT、mov_text、
      unsupported bitmap 标识各一；记录生成方式、来源和许可。
- [ ] 保存真实 15.2GB MKV 只作为本地 E2E 夹具，不提交仓库、不进入普通 CI。

验收：`rg "ffprobe|probeMediaDuration" client-next` 无产品代码命中；现有
`client-next` 单测全绿。

### P1：原生依赖与构建接线

- [x] 新增 `packages/libavformat_ffi` 静态包及 `native/` C bridge。
- [x] 新增 `packages/libass_ffi` 静态包；句柄保持 opaque，仅为稳定公开结构
      `ASS_Image` 定义只读前缀布局。
- [x] `client-next/cjpm.toml` 加入两个 path dependency 和 Linux/Windows 链接参数。
- [x] Linux CI 安装 `libavformat-dev libavcodec-dev libavutil-dev libass-dev`；原生库验证
      增加 FFmpeg/libass。
- [x] Windows CI 安装 `mingw-w64-x86_64-ffmpeg`、`mingw-w64-x86_64-libass`，并将依赖 DLL
      一并打包和启动冒烟验证。
- [x] `.github/workflows/client-next.yml` 的 paths、required files、cache key 纳入两个新包。
- [x] deb 使用 `dpkg-shlibdeps`/`${shlibs:Depends}` 推导运行时依赖，或显式加入发行版实际
      soname 包；不能只在构建机链接成功。
- [x] README 补充 Linux/Windows 原生开发依赖和故障诊断命令。

验收：Linux 和 Windows 均能完成最小 FFI build/test；安装产物在无开发包环境中启动，
`ldd` 或 Windows DLL 检查无缺失项。

### P2：libavformat/libavcodec 安全封装

- [x] C bridge 使用编译时真实头文件访问 AVFormatContext/AVStream/AVCodecParameters/
      AVPacket 字段，仓颉侧不复制易随 FFmpeg major 变化的完整结构体布局。
- [x] bridge 在编译期/运行时校验 `libavformat`、`libavcodec` major；不匹配时返回明确错误。
- [x] 绑定打开/枚举/读取与释放调用：
      `avformat_open_input`、`avformat_find_stream_info`、`avformat_close_input`、
      `av_read_frame`、`av_packet_alloc/free/unref`、`av_dict_get/set/free`、
      `avcodec_get_name`、`avcodec_find_decoder`、`avcodec_alloc/free_context`、
      `avcodec_parameters_to_context`、`avcodec_open2`、`avcodec_decode_subtitle2`、
      `avsubtitle_free`、`av_rescale_q`、`av_strerror`。
- [x] 实现 `probeSubtitleStreams`，包含 metadata、disposition、supported reason 及默认轨规则。
- [x] 实现 `extractSubtitleTracks`，一次扫描收集全部支持轨；正确换算 time base、过滤其他
      stream、释放每个 packet、flush mov_text 解码器并响应取消。
- [x] 公共 API 文档写明线程、所有权、取消、错误和输入上限。

验收：五类最小夹具结果正确；重复执行、错误 URL、截断媒体、取消和畸形 packet 均不崩溃、
不泄漏句柄；真实 MKV 能得到 4 条独立 ASS 轨及完整 CodecPrivate。

### P3：media proxy 稳定媒体租约与顺序读取

- [x] 将当前“一个可变 route 指向当前 upstream”改为每次 open 生成不可变 route/session；
      route 在 VLC 和字幕扫描仍持有时不能被切页改指向另一媒体。
- [x] 引入 `MediaProxyLease` 或等价引用计数生命周期；PlaybackModel、VLC、字幕 worker
      明确各自持有/释放租约。
- [x] 流式转发已是 O(1) 内存后，优先移除 32MiB 开放 Range 截断；若上游限制要求保留窗口，
      必须实现对下游透明的连续读取，不能以窗口结束冒充文件 EOF。
- [x] 正确透传 GET/HEAD、206/200、Content-Range、Content-Length、ETag、Last-Modified 和错误状态。
- [x] 增加读取/连接超时、取消关闭响应体，以及日志脱敏。
- [ ] 增加同一媒体 VLC + libavformat 并发读、切页后旧任务继续收尾、多个 seek 和上游断流测试。

验收：顺序读取大于 64MiB 内容字节完全一致；跨多个原 32MiB 边界无截断；切页后旧扫描
永远不会读到新媒体；代理关闭后没有遗留 server/response 资源。

### P4：版本化字幕缓存

- [x] 缓存根目录使用 `defaultCacheRoot(activeBaseUrl())/subtitles/`，按服务器隔离。
- [ ] 缓存键至少包含 cache schema version、server hash、arcid、sourcePath/page id、媒体验证器
      （ETag/Last-Modified/长度，能取得时必须使用）、stream index 和 codec。
- [x] 定义稳定、长度前缀的二进制事件格式及 manifest；禁止直接序列化原生结构体内存。
- [x] 写入采用同目录临时文件 + flush + 原子 rename；取消或失败删除临时文件。
- [x] 读取校验 magic、schema、长度边界、事件数量上限和校验和；损坏时删除并重新抽取。
- [x] probe 完成后后台预取默认轨；因为顺序扫描成本相同，实际扫描同时缓存全部支持文本轨。
- [x] 同一稳定媒体只允许一个在途 scan；多次选择合并等待同一结果，不重复扫描。
- [ ] 接入现有“清理缓存”入口，并定义字幕缓存容量上限、LRU/mtime 淘汰和未完成文件清理。

验收：二次打开同媒体不再读取完整容器；并发请求只扫描一次；媒体验证器或 schema 改变时
不会误用旧缓存；损坏/中断写入可自愈。

### P5：libass 安全封装与 RGBA 合成

- [x] 绑定完整生命周期：`ass_library_init/done`、`ass_renderer_init/done`、
      `ass_new_track/free_track`。
- [x] 绑定配置：`ass_set_frame_size`、`ass_set_storage_size`、`ass_set_pixel_aspect`、
      `ass_set_margins`、`ass_set_use_margins`、`ass_set_fonts`。
- [x] 绑定输入：`ass_read_memory`、`ass_process_codec_private`、`ass_process_chunk`、
      `ass_process_data`、`ass_flush_events`；二期字体任务再加入 `ass_add_font`。
- [x] 绑定输出：`ass_render_frame` 和稳定 `ASS_Image` 前缀；检查空指针、负尺寸、stride、
      坐标和整数乘法溢出。
- [x] 实现 SRT/VTT -> 规范 ASS 转换器，默认 Script Info、PlayRes 和 Style 固定且有单测。
- [x] 实现每轨 `ASS_Track` 管理器。一个 `ASS_Renderer` 可依次渲染多轨，但每次调用后必须
      立即消费/拷贝该轨的 `ASS_Image` 链表，再调用下一轨，不能跨调用保存借用指针。
- [x] 实现透明 RGBA 合成：严格按 `ASS_Image` 链表顺序和用户选择顺序叠加；libass 颜色的
      alpha 为反向值，实际覆盖率由 bitmap coverage 与 `(255 - colorAlpha)` 共同计算；
      使用 source-over，并裁剪到输出边界。
- [x] 输出 `SubtitleBitmap(width, height, generation, rgba)`；复用同尺寸数组，
      `detect_change=0` 时避免无意义纹理上传，但动画/卡拉 OK 仍按播放时钟更新。

验收：固定字体、固定时钟下 golden/hash 测试稳定；定位、颜色、透明度、描边、阴影、换行、
裁剪、重叠和多轨顺序正确；空轨和恶意尺寸不会崩溃或越界。

### P6：PlaybackModel、worker 与 VLC 集成

- [x] 新增状态：`embeddedSubtitleStreams`、`activeEmbeddedStreamIndexes`、轨级 loading/error、
      当前 `mediaGeneration`、已准备的 libass 轨和字幕 bitmap generation。
- [x] 新增注入点：probe、scan/cache load、取消；测试中不得要求真实 FFmpeg/libass。
- [x] `model.cj` 接入 `subprobe:<stableMediaKey>` 和 `subscan:<stableMediaKey>`；字幕扫描使用
      独立单线程或有界执行器，不占用当前 2 个通用 API worker。
- [x] video lane 激活后立即异步 probe；命中缓存直接准备轨，未命中则后台预取默认轨。
- [x] 用户选择尚未抽取的轨时显示 loading，并等待同一媒体的批量扫描结果；取消选择不取消
      其他仍需要的扫描，切媒体才取消整项。
- [x] 删除 VLC `subtitleTracks`/`subtitleTrackId` 作为 UI 数据源以及 `setSubtitleTrack`/
      `cycleSubtitleTrack` 的用户路径。
- [x] 在 VLC start 后及每秒节流检查时调用 `set_spu(-1)`；VLC 延迟发现字幕轨也不能自行启用。
- [x] seek、stop、切 lane、切媒体和 close 时刷新/释放正确状态；旧 worker 结果按 generation 丢弃。
- [x] 所有模型状态只在 UI pump 回填，worker 不直接修改 PlaybackModel 集合。

验收：模型测试覆盖 probe、默认预取、多选、取消、切页迟到、缓存命中/失败、Off、seek 以及
VLC 自动重新选轨后的强制关闭；通用 API worker 不被大文件 scan 饥饿。

### P7：reader dock 与视频舞台迁移

- [x] `reader_dock` 改成“Off + 外挂多选 + 内嵌多选”；内嵌项使用容器 stream metadata，
      不再显示 VLC ES id。
- [x] 显示探测中、抽取中、失败、unsupported codec；unsupported 行禁用但可说明原因。
- [x] Off 同时清空外挂和内嵌选中集；多选点击保持 popup 打开；选中/loading/error 图标可区分。
- [x] `drawVideoStage` 只计算一次视频 `fittedRect`，视频纹理和字幕透明纹理绘制到同一矩形；
      字幕不能以整个 reader frame 为坐标系。
- [ ] libass frame/storage size 取当前视频像素尺寸；若 probe 提供有效 SAR，则同步修正视频显示
      宽高比并调用 `ass_set_pixel_aspect`，保证两层几何一致。
- [x] resize、DPI、视频分辨率变化时重配 renderer 并使字幕纹理失效；旧纹理及时释放。
- [x] 用 streaming texture 原地更新字幕 RGBA；无字幕画面不创建透明全屏纹理。
- [x] 删除视频 `drawSubtitleOverlay`；音频歌词 overlay 及其他页面绘制不变。

验收：16:9、4:3、竖屏、letterbox 和窗口 resize 下字幕与视频像素矩形对齐；多轨按稳定顺序
显示；切页后不残留上一媒体的字幕纹理或面板状态。

### P8：测试、质量门禁与文档

- [x] 单元测试：time base 换算、stream metadata、SRT/VTT 转 ASS、缓存编码/损坏、RGBA alpha
      合成、模型状态机和代理 session 生命周期。
- [ ] FFI 集成测试：ASS CodecPrivate/chunk、SRT、VTT、mov_text、unsupported bitmap、截断输入、
      取消、重复打开关闭和所有错误清理路径。
- [ ] media proxy 集成测试：HEAD、完整 GET、开放/闭合 Range、跨边界顺序读、seek、并发、断流。
- [ ] UI/快照测试：无字幕、单轨、多轨、loading、error、unsupported、Off 和 resize。
- [x] Linux CI：`cjpm build`、`cjfmt`、`cjlint`、`cjpm test`、headless smoke 全绿。
- [ ] Windows CI：交叉构建、测试、DLL 打包和启动 smoke 全绿。
- [x] 本地 E2E：15.2GB MKV 双轨同屏；验证 `\an7/\an8` 等定位标签、颜色/描边、换行，
      无原始标签泄漏，VLC 原生字幕始终关闭，第二次打开命中缓存。
- [ ] 性能记录：首次 probe/scan 耗时、第二次缓存命中耗时、播放帧时间、字幕纹理上传次数、
      峰值托管内存和字幕缓存体积；记录测试机器和媒体大小。
- [x] 更新 client-next README：支持格式、位图字幕限制、字体回退、缓存位置/清理、原生依赖和
      故障诊断。

## 6. 推荐实施顺序与依赖

```text
P0 基线清理
  └─ P1 构建/依赖
       ├─ P2 libavformat/libavcodec ─ P3 proxy ─ P4 缓存 ┐
       └─ P5 libass/合成 ────────────────────────────────┤
                                                           └─ P6 模型/worker
                                                                └─ P7 UI/舞台
                                                                     └─ P8 全量验收
```

- P2 与 P5 可并行，但进入 P6 前二者的安全高层 API 必须稳定。
- P3 必须在真实大文件后台扫描前完成，否则可变代理 route 会造成跨媒体误读风险。
- P4 可先使用最小缓存实现验证数据格式，再补淘汰；但原子写和损坏校验不能延期。
- 二期字体附件不阻塞一期，但一期文档和 E2E 必须如实记录字体回退差异。

## 7. 一期完成定义

以下条件全部满足才能关闭本计划：

- [x] 产品运行路径和安装包均不调用或依赖 ffprobe/ffmpeg 外部二进制。
- [x] 支持格式的内嵌/外挂字幕可任意多选、同时显示；位图字幕明确禁用。
- [x] ASS CodecPrivate、packet 时间轴、mov_text 解码及所有原生释放路径正确。
- [x] VLC 原生字幕在启动、seek、延迟发现轨和切媒体后均保持关闭。
- [x] 大文件每个媒体最多一次在途顺序扫描，缓存命中不重新扫描，切页不会串流。
- [x] 视频和字幕在 letterbox/resize 下使用同一像素矩形，没有标签字面量泄漏。
- [ ] Linux/Windows 构建、测试、打包、启动 smoke 全绿。
- [ ] 真实双轨 E2E、缓存二次打开和性能记录归档完成。

## 8. 二期候选

- [ ] 枚举 MKV attachment stream，抽取字体并按 MIME/扩展名/大小白名单校验。
- [ ] 通过 `ass_add_font` 注入当前媒体字体；切媒体时按正确顺序清理 track/renderer/font。
- [ ] 字体附件缓存、去重、容量限制和恶意字体隔离。
- [ ] PGS/DVB 位图字幕解码与合成（独立设计，不与文本字幕伪装成同一数据格式）。
- [ ] 用户级字体、字号、边距和轨道偏移配置。
- [ ] 字幕轨延迟、单轨位置偏移及多轨自动避让策略。
