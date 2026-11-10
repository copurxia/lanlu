package lanlu_client_next.net

import lanlu_client_next.storage.{CACHE_DB_SCHEMA, DbSchema, ObjectCodec, ObjectRepository, StorageKeyCodec,
    StorageScope}
import rocksdb_ffi.{RocksDb, RocksDbColumnFamily, RocksDbError, RocksDbErrorKind, RocksDbOperationResult,
    RocksDbPrefixCursor, RocksDbWriteBatch}
import std.collection.ArrayList
import std.env.getVariable
import std.fs.{exists, Directory, Path}
import std.io.{ByteBuffer, readToEnd}
import std.sync.Mutex
import std.time.DateTime
import stdx.encoding.json.stream.*

// 离线响应缓存值：原始 HTTP body（第一阶段不引入 DTO serializer）。
// 通过 ObjectRepository 的版本化 envelope 承载 schema、savedAt、expiresAt（TTL）与 payload；
// account scope 由 StorageScope 编码进 key，server/account 双重隔离。
private class CachedResponseCodec <: ObjectCodec<String> {
    public func typeName(): String {
        return "cached-response"
    }

    public func schemaVersion(): UInt32 {
        return 1u32
    }

    public func encode(value: String): RocksDbOperationResult<Array<UInt8>> {
        return RocksDbOperationResult<Array<UInt8>>.Ok(value.toArray())
    }

    public func decode(payload: Array<UInt8>, schemaVersion: UInt32): RocksDbOperationResult<String> {
        if (schemaVersion != 1u32) {
            return RocksDbOperationResult<String>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "unsupported cached-response schema"))
        }
        try {
            return RocksDbOperationResult<String>.Ok(String.fromUtf8(payload))
        } catch (_: Exception) {
            return RocksDbOperationResult<String>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "cached-response payload is not valid UTF-8"))
        }
    }
}

// 离线缓存（第二个 RocksDB 实例，独立于设置库）：
// - resp:{serverHash}:{accountScope}:{path?query} → {"saved_at":..,"body":..}：GET 响应原始 body 快照，
//   供网络异常时读穿透回退（离线回读走各端点原有解析路径，零新 DTO）。
// - progress:{serverHash}:{accountScope}:{arcid} → {"page":N,"queued_at":..}：离线阅读进度队列，
//   服务端恢复后由 model 逐条补报。
// serverHash 隔离服务器，accountScope 隔离同一服务器上的不同本地会话，禁止跨账号回读；
// 打开失败降级为不可用（方法全部静默），不阻断启动。

public func defaultOfflineCacheRoot(): String {
    let home = getVariable("HOME") ?? "."
    "${home}/.cache/lanlu-client-next/offline-kv"
}

// 待补报进度条目：除页码外携带重试状态（retryCount/nextAttemptAt/lastError）。
public class PendingProgressEntry {
    public let arcid: String
    public let page: Int64
    public let retryCount: Int64
    public let nextAttemptAt: Int64
    public let lastError: String

    public init(arcid: String, page: Int64, retryCount: Int64, nextAttemptAt: Int64, lastError: String) {
        this.arcid = arcid
        this.page = page
        this.retryCount = retryCount
        this.nextAttemptAt = nextAttemptAt
        this.lastError = lastError
    }
}

// 只读诊断快照：DB 路径/schema 由调用方与 diagnostics() 组合；不暴露 key 中的账号信息。
public class CacheDiagnostics {
    public var schemaVersion: Int64 = 0
    public var respCount: Int64 = 0
    public var progressCount: Int64 = 0
    public var objectCount: Int64 = 0
    public var expiredCount: Int64 = 0
}

// 离线回退通知（跨线程安全）：worker 线程 mark 置位（仅方法调用，规避 cjc 1.1.3 的
// GC WriteStaticRef 屏障缺陷——闭包直接写捕获引用字段会 SIGSEGV），UI pump 轮询 take 取走。
public class OfflineNotice {    private let mutex = Mutex()
    private var pending = false

    public func mark(): Unit {
        synchronized(mutex) {
            pending = true
        }
    }

    // 取走并清除标志；UI 线程调用。
    public func take(): Bool {
        synchronized(mutex) {
            let p = pending
            pending = false
            p
        }
    }
}

public class OfflineCache {
    private let db: RocksDb
    private let meta: RocksDbColumnFamily
    private let objects: RocksDbColumnFamily
    private let indexes: RocksDbColumnFamily
    private let pageStore: PageStore
    private let searchStore: SearchStore
    private let tankStore: TankoubonStore
    private let tagTranslationStore: TagTranslationStore
    private let blobStore: BlobCacheStore
    // scan+delete 组合操作加锁；单键 put/get 由 RocksDB C API 保证线程安全。
    private let cacheMutex = Mutex()

    private init(db: RocksDb, meta: RocksDbColumnFamily, objects: RocksDbColumnFamily,
        indexes: RocksDbColumnFamily) {
        this.db = db
        this.meta = meta
        this.objects = objects
        this.indexes = indexes
        pageStore = PageStore(db, objects, indexes)
        searchStore = SearchStore(db, objects, indexes)
        tankStore = TankoubonStore(db, objects, indexes)
        tagTranslationStore = TagTranslationStore(db, objects, indexes)
        blobStore = BlobCacheStore(db, objects, indexes)
    }

    public func blob(): BlobCacheStore {
        return blobStore
    }

    public static func open(path: String): ?OfflineCache {
        try {
            if (!exists(Path(path))) {
                Directory.create(Path(path), recursive: true)
            }
            match (RocksDb.openLowMemory(path)) {
                case (true, Some(db), _) =>
                    let meta = match (db.ensureColumnFamilyResult("meta")) {
                        case RocksDbOperationResult<RocksDbColumnFamily>.Ok(value) => value
                        case _ =>
                            db.close()
                            return None
                    }
                    let objects = match (db.ensureColumnFamilyResult("objects")) {
                        case RocksDbOperationResult<RocksDbColumnFamily>.Ok(value) => value
                        case _ =>
                            db.close()
                            return None
                    }
                    let indexes = match (db.ensureColumnFamilyResult("indexes")) {
                        case RocksDbOperationResult<RocksDbColumnFamily>.Ok(value) => value
                        case _ =>
                            db.close()
                            return None
                    }
                    // 缓存 DB 独立 schema version：迁移（旧 resp:/progress: 格式读取时自动搬运）
                    // 幂等可重跑，版本写回保证重开后直接识别当前版本。
                    let schema = DbSchema(db, meta)
                    if (schema.currentVersion() != CACHE_DB_SCHEMA) {
                        let _ = schema.writeVersion(CACHE_DB_SCHEMA)
                    }
                    return Some(OfflineCache(db, meta, objects, indexes))
                case (_, _, _) => return None
            }
        } catch (_: Exception) {
            return None
        }
    }

    // 只读诊断：返回 schema 版本与缓存状态概览；不输出 key 中的账号信息或 payload。
    public func diagnostics(): CacheDiagnostics {
        let out = CacheDiagnostics()
        out.schemaVersion = DbSchema(db, meta).currentVersion()
        out.respCount = countPrefix("resp:")
        out.progressCount = countPrefix("progress:")
        out.objectCount = countPrefix("objects:")
        out.expiredCount = 0 // envelope 过期由读路径惰性清理；此处不遍历 payload
        return out
    }

    private func countPrefix(prefix: String): Int64 {
        var count: Int64 = 0
        try {
            let cursor = match (db.openPrefixCursorResult(prefix.toArray(), limit: 100000)) {
                case RocksDbOperationResult<RocksDbPrefixCursor>.Ok(value) => value
                case _ => return 0
            }
            try {
                while (cursor.isValid() && count < 100000) {
                    count += 1
                    cursor.next()
                }
            } finally {
                cursor.close()
            }
        } catch (_: Exception) {}
        count
    }

    private func respKey(serverHash: String, accountScope: String, path: String): String {
        "resp:${serverHash}:${accountScope}:${path}"
    }

    private func progressKey(serverHash: String, accountScope: String, arcid: String): String {
        "progress:${serverHash}:${accountScope}:${arcid}"
    }

    // 在线请求成功后写入响应快照（原始 body），按集中策略表决定 TTL；写失败静默。
    // 安全页数据（会话/令牌/通行密钥/TOTP）即使误调用也拒绝落库。
    public func storeResponse(serverHash: String, accountScope: String, path: String, body: String): Unit {
        if (!isCacheablePath(path)) {
            return
        }
        storeResponseTtl(serverHash, accountScope, path, body, responsePolicyFor(path).ttlMs)
    }

    public func storeResponseTtl(serverHash: String, accountScope: String, path: String, body: String,
        ttlMs: Int64): Unit {
        try {
            let repo = responseRepository(serverHash, accountScope)
            let _ = repo.put(path, body, ttlMs: ttlMs)
        } catch (_: Exception) {}
    }

    // 网络异常回退读：命中返回缓存 body，未命中/解析失败返回 None。
    // 默认按策略表决定是否允许 stale 离线读取（allowStaleOffline）。
    public func getResponse(serverHash: String, accountScope: String, path: String): Option<String> {
        if (!isCacheablePath(path)) {
            return None
        }
        return getResponseStale(serverHash, accountScope, path, responsePolicyFor(path).allowStaleOffline)
    }

    public func getResponseStale(serverHash: String, accountScope: String, path: String, allowStale: Bool,
        nowMs!: Int64 = DateTime.now().toUnixTimeStamp().toMilliseconds()):
        Option<String> {
        try {
            let repo = responseRepository(serverHash, accountScope)
            match (repo.get(path, allowStale: allowStale, nowMs: nowMs)) {
                case RocksDbOperationResult<String>.Ok(body) => return Some(body)
                case _ => ()
            }
            // 迁移兼容：旧 resp:{server}:{account}:{path} JSON key 只读，命中即迁移为新格式。
            match (db.getBytesResult(respKey(serverHash, accountScope, path).toArray())) {
                case RocksDbOperationResult<Array<UInt8>>.Ok(v) =>
                    let body = parseJsonStringField(String.fromUtf8(v), "body", "")
                    if (body.size > 0) {
                        let _ = db.deleteResult(respKey(serverHash, accountScope, path))
                        let _ = repo.put(path, body, ttlMs: responsePolicyFor(path).ttlMs)
                        return Some(body)
                    }
                    return None
                case _ => return None
            }
        } catch (_: Exception) {
            return None
        }
    }

    // mutation 后按 invalidation registry 精确删除/过期相关响应；不影响其他 query。
    public func deleteResponsePrefix(serverHash: String, accountScope: String, pathPrefix: String): Unit {
        try {
            let scope = StorageScope(serverHash, accountScope)
            let repo = ObjectRepository<String>(db, scope, CachedResponseCodec(), columnFamily: Some(objects))
            let entityPrefix = repo.entityPrefix()
            let batch = match (RocksDbWriteBatch.create()) {
                case RocksDbOperationResult<RocksDbWriteBatch>.Ok(value) => value
                case _ => return
            }
            try {
                let cursor = match (db.openPrefixCursorResult(objects, entityPrefix, limit: 512)) {
                    case RocksDbOperationResult<RocksDbPrefixCursor>.Ok(value) => value
                    case _ =>
                        batch.close()
                        return
                }
                var deleted = false
                try {
                    while (cursor.isValid()) {
                        let key = match (cursor.keyBytes()) {
                            case RocksDbOperationResult<Array<UInt8>>.Ok(value) => value
                            case _ => break
                        }
                        let id = responseIdFromEntityKey(key)
                        if (id.isSome() && id.getOrThrow().startsWith(pathPrefix)) {
                            let _ = batch.deleteBytes(objects, key)
                            deleted = true
                        }
                        cursor.next()
                    }
                } finally {
                    cursor.close()
                }
                if (deleted) {
                    let _ = db.commitWriteBatchResult(batch)
                }
            } finally {
                batch.close()
            }
            // 兼容旧格式 resp: 前缀 key。
            let _ = db.deletePrefixResult("resp:${serverHash}:${accountScope}:${pathPrefix}".toArray())
        } catch (_: Exception) {}
    }

    // 从实体 key 反解出响应 path（objects/{server}/{account}/cached-response/{path}）。
    private static func responseIdFromEntityKey(key: Array<UInt8>): Option<String> {
        match (StorageKeyCodec.decode(key)) {
            case Some(parts) =>
                if (parts.size != 5) {
                    return None
                }
                try {
                    return Some(String.fromUtf8(parts[4]))
                } catch (_: Exception) {
                    return None
                }
            case None => return None
        }
    }

    private func responseRepository(serverHash: String, accountScope: String): ObjectRepository<String> {
        return ObjectRepository<String>(db, StorageScope(serverHash, accountScope), CachedResponseCodec(),
            columnFamily: Some(objects))
    }

    // 在线页表规范化为对象记录 + ordered membership；失败时由调用方退回有界内存视图。
    public func storePages(
        serverHash: String,
        accountScope: String,
        arcid: String,
        pages: ArrayList<PageInfo>
    ): Option<ArchivePageView> {
        match (pageStore.writeSnapshot(serverHash, accountScope, arcid, pages)) {
            case RocksDbOperationResult<ArchivePageView>.Ok(value) => return Some(value)
            case _ => return None
        }
    }

    public func openPages(serverHash: String, accountScope: String, arcid: String): Option<ArchivePageView> {
        match (pageStore.openView(serverHash, accountScope, arcid)) {
            case RocksDbOperationResult<ArchivePageView>.Ok(value) => return Some(value)
            case _ => return None
        }
    }

    // 元数据编辑成功后只更新单页主记录（新 envelope revision），不重写整本页表。
    public func updatePage(
        serverHash: String,
        accountScope: String,
        arcid: String,
        rank: Int64,
        page: PageInfo
    ): Bool {
        match (pageStore.putPageAt(serverHash, accountScope, arcid, rank, page)) {
            case RocksDbOperationResult<Unit>.Ok(_) => return true
            case _ => return false
        }
    }

    // 查询结果规范化为共享主记录 + ordered membership；失败时调用方退回内存视图。
    public func storeSearchItems(
        serverHash: String,
        accountScope: String,
        queryKey: String,
        language: String,
        items: SearchItemView
    ): Option<SearchItemView> {
        let values = ArrayList<SearchItem>()
        for (item in items) {
            values.add(item)
        }
        match (searchStore.writeSnapshot(serverHash, accountScope, queryKey, language, values)) {
            case RocksDbOperationResult<SearchItemView>.Ok(value) => return Some(value)
            case _ => return None
        }
    }

    // 大查询逐页写入：第一页先替换旧 membership，后续页只追加连续 rank。
    public func storeSearchItemPage(
        serverHash: String,
        accountScope: String,
        queryKey: String,
        language: String,
        rankOffset: Int64,
        replace: Bool,
        items: SearchItemView
    ): Option<SearchItemView> {
        let values = ArrayList<SearchItem>()
        for (item in items) {
            values.add(item)
        }
        match (searchStore.writeSnapshot(serverHash, accountScope, queryKey, language, values,
            rankOffset: rankOffset, replace: replace)) {
            case RocksDbOperationResult<SearchItemView>.Ok(value) => return Some(value)
            case _ => return None
        }
    }

    public func openSearchItems(
        serverHash: String,
        accountScope: String,
        queryKey: String,
        language: String
    ): Option<SearchItemView> {
        match (searchStore.openView(serverHash, accountScope, queryKey, language)) {
            case RocksDbOperationResult<SearchItemView>.Ok(value) => return Some(value)
            case _ => return None
        }
    }

    // 合集列表（父合集/相关合集/全部合集）规范化为共享主记录 + ordered membership；
    // 失败时调用方退回内存视图。
    public func storeTanks(
        serverHash: String,
        accountScope: String,
        queryKey: String,
        language: String,
        tanks: TankoubonView
    ): Option<TankoubonView> {
        let values = ArrayList<TankoubonInfo>()
        for (tank in tanks) {
            values.add(tank)
        }
        match (tankStore.writeSnapshot(serverHash, accountScope, queryKey, language, values)) {
            case RocksDbOperationResult<TankoubonView>.Ok(value) => return Some(value)
            case _ => return None
        }
    }

    public func openTanks(
        serverHash: String,
        accountScope: String,
        queryKey: String,
        language: String
    ): Option<TankoubonView> {
        match (tankStore.openView(serverHash, accountScope, queryKey, language)) {
            case RocksDbOperationResult<TankoubonView>.Ok(value) => return Some(value)
            case _ => return None
        }
    }

    // 单合集规范主记录写回（收藏切换等），不动 query membership。
    public func persistTank(
        serverHash: String,
        accountScope: String,
        language: String,
        tank: TankoubonInfo
    ): Bool {
        match (tankStore.putTank(serverHash, accountScope, language, tank)) {
            case RocksDbOperationResult<Unit>.Ok(_) => return true
            case _ => return false
        }
    }

    // 标签翻译规范化为共享主记录 + ordered membership；失败时调用方退回内存视图。
    public func storeTagTranslations(
        serverHash: String,
        accountScope: String,
        queryKey: String,
        language: String,
        entries: ArrayList<(String, String)>
    ): Option<TagTranslationView> {
        match (tagTranslationStore.writeSnapshot(serverHash, accountScope, queryKey, language, entries)) {
            case RocksDbOperationResult<TagTranslationView>.Ok(value) => return Some(value)
            case _ => return None
        }
    }

    public func openTagTranslations(
        serverHash: String,
        accountScope: String,
        queryKey: String,
        language: String
    ): Option<TagTranslationView> {
        match (tagTranslationStore.openView(serverHash, accountScope, queryKey, language)) {
            case RocksDbOperationResult<TagTranslationView>.Ok(value) => return Some(value)
            case _ => return None
        }
    }

    // 进度入队：同一档案后写覆盖页码（对齐 RN offlineProgressQueue）；已有记录的重试
    // 状态（retryCount/nextAttemptAt/lastError）保留，用户翻页只更新页码与入队时间。
    public func enqueueProgress(serverHash: String, accountScope: String, arcid: String, page: Int64): Unit {
        try {
            let key = progressKey(serverHash, accountScope, arcid)
            var retryCount: Int64 = 0
            var nextAttemptAt: Int64 = 0
            var lastError = ""
            match (db.getBytesResult(key.toArray())) {
                case RocksDbOperationResult<Array<UInt8>>.Ok(v) =>
                    let existing = String.fromUtf8(v)
                    retryCount = parseJsonInt64Field(existing, "retry_count", 0)
                    nextAttemptAt = parseJsonInt64Field(existing, "next_attempt_at", 0)
                    lastError = parseJsonStringField(existing, "last_error", "")
                case _ => ()
            }
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("page").writeValue(page)
            w.writeName("queued_at").writeValue(DateTime.now().toUnixTimeStamp().toMilliseconds())
            w.writeName("retry_count").writeValue(retryCount)
            w.writeName("next_attempt_at").writeValue(nextAttemptAt)
            w.writeName("last_error").writeValue(lastError)
            w.endObject()
            w.flush()
            let _ = db.putBytesResult(key.toArray(), readToEnd(out))
        } catch (_: Exception) {}
    }

    // 补报失败后更新重试状态：递增 retry count、按指数退避设置 nextAttemptAt、记录 lastError。
    // 记录不被删除，下次 listProgressEntries 到期后继续尝试。
    public func markProgressFailed(serverHash: String, accountScope: String, arcid: String, error: String): Unit {
        try {
            let key = progressKey(serverHash, accountScope, arcid)
            var retryCount: Int64 = 0
            match (db.getBytesResult(key.toArray())) {
                case RocksDbOperationResult<Array<UInt8>>.Ok(v) =>
                    retryCount = parseJsonInt64Field(String.fromUtf8(v), "retry_count", 0)
                case _ => ()
            }
            let now = DateTime.now().toUnixTimeStamp().toMilliseconds()
            // 指数退避：1s、2s、4s……上限 60s，避免离线场景下高频重试。
            var power: Int64 = 1
            var remaining = retryCount + 1
            while (remaining > 1 && power < 60) {
                power *= 2
                remaining -= 1
            }
            let backoffMs = min(60000, 1000 * power)
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("retry_count").writeValue(retryCount + 1)
            w.writeName("next_attempt_at").writeValue(now + backoffMs)
            w.writeName("last_error").writeValue(if (error.size > 128) {
                error[0..128]
            } else {
                error
            })
            w.endObject()
            w.flush()
            let _ = db.putBytesResult(key.toArray(), readToEnd(out))
        } catch (_: Exception) {}
    }

    // 分批读取某服务器的待补报进度（仅 nextAttemptAt 已到的记录）：(arcid, page)，
    // 避免把整个 outbox 扫入数组。
    public func listProgress(
        serverHash: String,
        accountScope: String,
        limit!: Int64 = 64
    ): ArrayList<(String, Int64)> {
        let entries = listProgressEntries(serverHash, accountScope, limit: limit)
        let out = ArrayList<(String, Int64)>()
        for (e in entries) {
            out.add((e.arcid, e.page))
        }
        out
    }

    public func listProgressEntries(
        serverHash: String,
        accountScope: String,
        limit!: Int64 = 64,
        includeBackoff!: Bool = false
    ): ArrayList<PendingProgressEntry> {
        let out = ArrayList<PendingProgressEntry>()
        let prefix = "progress:${serverHash}:${accountScope}:"
        let now = DateTime.now().toUnixTimeStamp().toMilliseconds()
        synchronized(cacheMutex) {
            let cursor = match (db.openPrefixCursorResult(prefix.toArray(), limit: limit)) {
                case RocksDbOperationResult<RocksDbPrefixCursor>.Ok(value) => value
                case _ => return out
            }
            try {
                while (cursor.isValid() && out.size < limit) {
                    let key = match (cursor.keyBytes()) {
                        case RocksDbOperationResult<Array<UInt8>>.Ok(value) => String.fromUtf8(value)
                        case _ => break
                    }
                    let value = match (cursor.valueBytes()) {
                        case RocksDbOperationResult<Array<UInt8>>.Ok(bytes) => String.fromUtf8(bytes)
                        case _ => break
                    }
                    let arcid = key[prefix.size..key.size]
                    if (arcid.size > 0) {
                        let nextAttemptAt = parseJsonInt64Field(value, "next_attempt_at", 0)
                        if (includeBackoff || nextAttemptAt <= now) {
                            out.add(
                                PendingProgressEntry(
                                    arcid,
                                    parseJsonInt64Field(value, "page", 0),
                                    parseJsonInt64Field(value, "retry_count", 0),
                                    nextAttemptAt,
                                    parseJsonStringField(value, "last_error", "")
                                )
                            )
                        }
                    }
                    cursor.next()
                }
            } finally {
                cursor.close()
            }
        }
        out
    }

    // 补报成功后的 batch ack：一次确认删除多条，比逐条 delete 减少写放大。
    public func ackProgressBatch(serverHash: String, accountScope: String, arcids: ArrayList<String>): Bool {
        if (arcids.size == 0) {
            return true
        }
        try {
            let batch = match (RocksDbWriteBatch.create()) {
                case RocksDbOperationResult<RocksDbWriteBatch>.Ok(value) => value
                case _ => return false
            }
            try {
                for (arcid in arcids) {
                    let _ = batch.deleteBytes(progressKey(serverHash, accountScope, arcid).toArray())
                }
                match (db.commitWriteBatchResult(batch)) {
                    case RocksDbOperationResult<Unit>.Ok(_) => return true
                    case _ => return false
                }
            } finally {
                batch.close()
            }
        } catch (_: Exception) {
            return false
        }
    }

    // 补报成功后删除队列项。
    public func deleteProgress(serverHash: String, accountScope: String, arcid: String): Bool {
        try {
            match (db.deleteResult(progressKey(serverHash, accountScope, arcid))) {
                case RocksDbOperationResult<Unit>.Ok(_) => return true
                case _ => return false
            }
        } catch (_: Exception) {
            return false
        }
    }

    // 清理某服务器的全部离线数据（响应 + 进度），供“清理图片缓存”入口联动。
    public func clearServer(serverHash: String): Unit {
        synchronized(cacheMutex) {
            for (p in ["resp:${serverHash}:", "progress:${serverHash}:"]) {
                let _ = db.deletePrefixResult(p.toArray())
            }
            match (db.columnFamily("objects")) {
                case Some(cf) => let _ = db.deletePrefixResult(cf, StorageKeyCodec.encodeStrings(["objects", serverHash]))
                case None => ()
            }
            match (db.columnFamily("indexes")) {
                case Some(cf) => let _ = db.deletePrefixResult(cf, StorageKeyCodec.encodeStrings(["indexes", serverHash]))
                case None => ()
            }
        }
    }

    public func close(): Unit {
        try {
            db.close()
        } catch (_: Exception) {}
    }

    // 仅供迁移测试：直接写入/检查旧格式 key（生产代码不调用）。
    public func putRawBytesForTest(key: Array<UInt8>, value: Array<UInt8>): Unit {
        let _ = db.putBytesResult(key, value)
    }

    public func hasRawKeyForTest(key: Array<UInt8>): Bool {
        match (db.getBytesResult(key)) {
            case RocksDbOperationResult<Array<UInt8>>.Ok(_) => return true
            case _ => return false
        }
    }
}

// ---- JSON 字段快路径（offline 值结构固定，缺失/坏数据回 fallback）----

private func parseJsonStringField(body: String, field: String, fallback: String): String {
    var out = fallback
    var buf = ByteBuffer()
    unsafe { buf.write(body.rawData()) }
    let r = JsonReader(buf)
    try {
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        if (n == field) {
                            out = decodeRaw<String>(r.readValueBytes(), fallback)
                        } else {
                            r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => break
            }
        }
    } catch (_: Exception) {}
    out
}

private func parseJsonInt64Field(body: String, field: String, fallback: Int64): Int64 {
    var out = fallback
    var buf = ByteBuffer()
    unsafe { buf.write(body.rawData()) }
    let r = JsonReader(buf)
    try {
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        if (n == field) {
                            out = decodeRaw<Int64>(r.readValueBytes(), fallback)
                        } else {
                            r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => break
            }
        }
    } catch (_: Exception) {}
    out
}
