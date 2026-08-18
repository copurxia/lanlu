package lanlu_client_next.net

import lanlu_client_next.storage.{ObjectCodec, ObjectRepository, QueryMember, QueryPage, QueryRepository,
    StorageKeyCodec, StorageScope}
import rocksdb_ffi.{RocksDb, RocksDbColumnFamily, RocksDbOperationResult, RocksDbError, RocksDbErrorKind,
    RocksDbWriteBatch}
import std.collection.ArrayList
import std.convert.Parsable

public let MAX_ARCHIVE_PAGES: Int64 = 100000
private let PAGE_HOT_CACHE_SIZE: Int64 = 64

private func addPageType(stats: PageTypeStat, pageType: String): Unit {
    match (pageType) {
        case "image" => stats.image += 1
        case "video" => stats.video += 1
        case "audio" => stats.audio += 1
        case "html" => stats.html += 1
        case _ => ()
    }
}

private func pageStatsOf(pages: Iterable<PageInfo>): PageTypeStat {
    let stats = PageTypeStat()
    for (page in pages) {
        addPageType(stats, page.pageType)
    }
    return stats
}

private class PageInfoCodec <: ObjectCodec<PageInfo> {
    private let arcid: String

    init(arcid: String) {
        this.arcid = arcid
    }

    public func typeName(): String {
        return "page:${arcid}"
    }

    public func schemaVersion(): UInt32 {
        return 1u32
    }

    public func encode(value: PageInfo): RocksDbOperationResult<Array<UInt8>> {
        let fields = ArrayList<String>()
        fields.add(value.id)
        fields.add(value.sourcePath)
        fields.add(value.pageType)
        fields.add(value.title)
        fields.add(value.description)
        fields.add(value.releaseAt)
        fields.add("${value.orderIndex}")
        fields.add(if (value.hiddenInFiles) {
            "1"
        } else {
            "0"
        })
        fields.add("${value.lyricsAssetId}")
        fields.add("${value.thumbAssetId}")
        fields.add("${value.subtitleAttachments.size}")
        for (attachment in value.subtitleAttachments) {
            fields.add("${attachment.assetId}")
            fields.add(attachment.kind)
            fields.add(attachment.name)
            fields.add(attachment.language)
            fields.add("${attachment.orderIndex}")
        }
        return RocksDbOperationResult<Array<UInt8>>.Ok(StorageKeyCodec.encodeStrings(fields.toArray()))
    }

    public func decode(payload: Array<UInt8>, schemaVersion: UInt32): RocksDbOperationResult<PageInfo> {
        if (schemaVersion != 1u32) {
            return decodeError("unsupported page-info schema")
        }
        let raw = match (StorageKeyCodec.decode(payload)) {
            case Some(value) => value
            case None => return decodeError("malformed page-info payload")
        }
        if (raw.size < 11) {
            return decodeError("page-info payload is missing fields")
        }
        try {
            let fields = Array<String>(raw.size, {i => String.fromUtf8(raw[i])})
            let attachmentCount = parseNonNegative(fields[10])
            if (attachmentCount > MAX_ARCHIVE_PAGES || fields.size != 11 + attachmentCount * 5) {
                return decodeError("page-info attachment fields are invalid")
            }
            let page = PageInfo()
            page.id = fields[0]
            page.sourcePath = fields[1]
            page.pageType = fields[2]
            page.title = fields[3]
            page.description = fields[4]
            page.releaseAt = fields[5]
            page.orderIndex = Int64.parse(fields[6])
            page.hiddenInFiles = fields[7] == "1"
            page.lyricsAssetId = Int64.parse(fields[8])
            page.thumbAssetId = Int64.parse(fields[9])
            for (i in 0..attachmentCount) {
                let base = 11 + i * 5
                let attachment = SubtitleAttachment()
                attachment.assetId = Int64.parse(fields[base])
                attachment.kind = fields[base + 1]
                attachment.name = fields[base + 2]
                attachment.language = fields[base + 3]
                attachment.orderIndex = Int64.parse(fields[base + 4])
                page.subtitleAttachments.add(attachment)
            }
            return RocksDbOperationResult<PageInfo>.Ok(page)
        } catch (_: Exception) {
            return decodeError("page-info payload contains invalid UTF-8 or numbers")
        }
    }

    private static func parseNonNegative(value: String): Int64 {
        let parsed = Int64.parse(value)
        if (parsed < 0) {
            throw IllegalArgumentException("negative attachment count")
        }
        return parsed
    }

    private static func decodeError(message: String): RocksDbOperationResult<PageInfo> {
        return RocksDbOperationResult<PageInfo>.Err(RocksDbError(RocksDbErrorKind.DecodeFailure, message))
    }
}

// Page objects stay in RocksDB. The view retains only count/statistics plus a fixed-size hot window.
public class ArchivePageView <: Iterable<PageInfo> {
    public let arcid: String
    private let pageStore: ?PageStore
    private let serverHash: String
    private let accountScope: String
    private let memoryPages: ?Array<PageInfo>
    private let pageCount: Int64
    private let pageStats: PageTypeStat
    private let cacheRanks = Array<Int64>(PAGE_HOT_CACHE_SIZE, repeat: -1)
    private let cachePages = Array<Option<PageInfo>>(PAGE_HOT_CACHE_SIZE, {_ => None})
    private var nextCacheSlot: Int64 = 0

    private init(
        arcid: String,
        store: ?PageStore,
        serverHash: String,
        accountScope: String,
        memory: ?Array<PageInfo>,
        count: Int64,
        stats: PageTypeStat
    ) {
        this.arcid = arcid
        pageStore = store
        this.serverHash = serverHash
        this.accountScope = accountScope
        memoryPages = memory
        pageCount = count
        pageStats = stats
    }

    public static func empty(arcid!: String = ""): ArchivePageView {
        return ArchivePageView(arcid, None, "", "", Some(Array<PageInfo>()), 0, PageTypeStat())
    }

    public static func memory(arcid: String, pages: ArrayList<PageInfo>): ArchivePageView {
        let values = pages.toArray()
        return ArchivePageView(arcid, None, "", "", Some(values), values.size, pageStatsOf(pages))
    }

    internal static func persisted(
        arcid: String,
        store: PageStore,
        serverHash: String,
        accountScope: String,
        count: Int64,
        stats: PageTypeStat
    ): ArchivePageView {
        return ArchivePageView(arcid, Some(store), serverHash, accountScope, None, count, stats)
    }

    public prop size: Int64 {
        get() {
            return pageCount
        }
    }

    public prop stats: PageTypeStat {
        get() {
            return pageStats
        }
    }

    public func itemAt(index: Int64): Option<PageInfo> {
        if (index < 0 || index >= pageCount) {
            return None
        }
        match (memoryPages) {
            case Some(values) => return Some(values[index])
            case None => ()
        }
        for (slot in 0..PAGE_HOT_CACHE_SIZE) {
            if (cacheRanks[slot] == index) {
                return cachePages[slot]
            }
        }
        let loaded = match (pageStore) {
            case Some(store) => store.loadPage(serverHash, accountScope, arcid, index)
            case None => return None
        }
        match (loaded) {
            case RocksDbOperationResult<PageInfo>.Ok(page) =>
                cacheRanks[nextCacheSlot] = index
                cachePages[nextCacheSlot] = Some(page)
                nextCacheSlot = (nextCacheSlot + 1) % PAGE_HOT_CACHE_SIZE
                return Some(page)
            case _ => return None
        }
    }

    public func at(index: Int64): PageInfo {
        return itemAt(index) ?? throw IndexOutOfBoundsException("archive page is unavailable")
    }

    /** Drops one rank from the hot window so the next itemAt re-reads the canonical record. */
    public func invalidateRank(index: Int64): Unit {
        for (slot in 0..PAGE_HOT_CACHE_SIZE) {
            if (cacheRanks[slot] == index) {
                cacheRanks[slot] = -1
                cachePages[slot] = None
            }
        }
    }

    public operator func [](index: Int64): PageInfo {
        return at(index)
    }

    public func iterator(): Iterator<PageInfo> {
        return ArchivePageIterator(this)
    }
}

private class ArchivePageIterator <: Iterator<PageInfo> {
    private let pages: ArchivePageView
    private var index: Int64 = 0

    init(pages: ArchivePageView) {
        this.pages = pages
    }

    public func next(): Option<PageInfo> {
        while (index < pages.size) {
            let value = pages.itemAt(index)
            index += 1
            if (value.isSome()) {
                return value
            }
        }
        return None
    }
}

// One repository instance is shared by all views for an OfflineCache. Per-archive namespaces avoid id collisions.
class PageStore {
    private let db: RocksDb
    private let objects: RocksDbColumnFamily
    private let indexes: RocksDbColumnFamily

    init(db: RocksDb, objects: RocksDbColumnFamily, indexes: RocksDbColumnFamily) {
        this.db = db
        this.objects = objects
        this.indexes = indexes
    }

    func writeSnapshot(
        serverHash: String,
        accountScope: String,
        arcid: String,
        pages: ArrayList<PageInfo>
    ): RocksDbOperationResult<ArchivePageView> {
        if (pages.size > MAX_ARCHIVE_PAGES) {
            return RocksDbOperationResult<ArchivePageView>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "archive page count exceeds safety limit"))
        }
        let scope = StorageScope(serverHash, accountScope)
        let objectRepo = ObjectRepository<PageInfo>(db, scope, PageInfoCodec(arcid), columnFamily: Some(objects))
        let queryRepo = QueryRepository(db, scope, columnFamily: Some(indexes))
        let query = pageQuery(arcid)
        let batch = match (RocksDbWriteBatch.create()) {
            case RocksDbOperationResult<RocksDbWriteBatch>.Ok(value) => value
            case RocksDbOperationResult<RocksDbWriteBatch>.NotFound => return RocksDbOperationResult<ArchivePageView>
                .Err(RocksDbError(RocksDbErrorKind.FfiFailure, "write batch create returned no batch"))
            case RocksDbOperationResult<RocksDbWriteBatch>.Err(error) => return RocksDbOperationResult<ArchivePageView>
                .Err(error)
        }
        try {
            match (objectRepo.deleteAllInto(batch)) {
                case RocksDbOperationResult<Unit>.Ok(_) => ()
                case RocksDbOperationResult<Unit>.NotFound => ()
                case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<ArchivePageView>.Err(
                    error)
            }
            match (queryRepo.deleteQueryInto(batch, query)) {
                case RocksDbOperationResult<Unit>.Ok(_) => ()
                case RocksDbOperationResult<Unit>.NotFound => ()
                case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<ArchivePageView>.Err(
                    error)
            }
            for (i in 0..pages.size) {
                let page = pages[i]
                let id = pageEntityId(page, i)
                match (objectRepo.putInto(batch, id, page)) {
                    case RocksDbOperationResult<Unit>.Ok(_) => ()
                    case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<ArchivePageView>
                        .NotFound
                    case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<ArchivePageView>.Err(
                        error)
                }
                match (queryRepo.addInto(batch, query, UInt64(i), objectRepo.objectType(), id)) {
                    case RocksDbOperationResult<Unit>.Ok(_) => ()
                    case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<ArchivePageView>
                        .NotFound
                    case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<ArchivePageView>.Err(
                        error)
                }
            }
            match (db.commitWriteBatchResult(batch)) {
                case RocksDbOperationResult<Unit>.Ok(_) => return RocksDbOperationResult<ArchivePageView>.Ok(
                    ArchivePageView.persisted(arcid, this, serverHash, accountScope, pages.size, pageStatsOf(pages)))
                case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<ArchivePageView>.NotFound
                case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<ArchivePageView>.Err(
                    error)
            }
        } finally {
            batch.close()
        }
    }

    func openView(
        serverHash: String,
        accountScope: String,
        arcid: String
    ): RocksDbOperationResult<ArchivePageView> {
        let scope = StorageScope(serverHash, accountScope)
        let queryRepo = QueryRepository(db, scope, columnFamily: Some(indexes))
        let last = match (queryRepo.readPage(pageQuery(arcid), limit: 1, reverse: true)) {
            case RocksDbOperationResult<QueryPage>.Ok(value) => value
            case RocksDbOperationResult<QueryPage>.NotFound => return RocksDbOperationResult<ArchivePageView>.NotFound
            case RocksDbOperationResult<QueryPage>.Err(error) => return RocksDbOperationResult<ArchivePageView>.Err(
                error)
        }
        if (last.members.size == 0) {
            return RocksDbOperationResult<ArchivePageView>.NotFound
        }
        if (last.members[0].rank >= UInt64(MAX_ARCHIVE_PAGES)) {
            return RocksDbOperationResult<ArchivePageView>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "stored archive page count exceeds safety limit"))
        }
        let count = Int64(last.members[0].rank) + 1
        let view = ArchivePageView.persisted(arcid, this, serverHash, accountScope, count, PageTypeStat())
        let stats = view.stats
        for (page in view) {
            addPageType(stats, page.pageType)
        }
        return RocksDbOperationResult<ArchivePageView>.Ok(view)
    }

    func loadPage(
        serverHash: String,
        accountScope: String,
        arcid: String,
        rank: Int64
    ): RocksDbOperationResult<PageInfo> {
        if (rank < 0) {
            return RocksDbOperationResult<PageInfo>.NotFound
        }
        let scope = StorageScope(serverHash, accountScope)
        let objectRepo = ObjectRepository<PageInfo>(db, scope, PageInfoCodec(arcid), columnFamily: Some(objects))
        let queryRepo = QueryRepository(db, scope, columnFamily: Some(indexes))
        let member = match (queryRepo.readMemberAt(pageQuery(arcid), UInt64(rank))) {
            case RocksDbOperationResult<QueryMember>.Ok(value) => value
            case RocksDbOperationResult<QueryMember>.NotFound => return RocksDbOperationResult<PageInfo>.NotFound
            case RocksDbOperationResult<QueryMember>.Err(error) => return RocksDbOperationResult<PageInfo>.Err(error)
        }
        if (member.entityType != objectRepo.objectType()) {
            return RocksDbOperationResult<PageInfo>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "archive page membership has wrong entity type"))
        }
        return objectRepo.get(member.entityId)
    }

    // 元数据编辑成功后的单页更新：只写该 rank 的主记录（新 envelope revision），
    // 不动 count/类型统计/其他 membership，避免整本页表重写。
    func putPageAt(
        serverHash: String,
        accountScope: String,
        arcid: String,
        rank: Int64,
        page: PageInfo
    ): RocksDbOperationResult<Unit> {
        if (rank < 0) {
            return RocksDbOperationResult<Unit>.NotFound
        }
        let scope = StorageScope(serverHash, accountScope)
        let objectRepo = ObjectRepository<PageInfo>(db, scope, PageInfoCodec(arcid), columnFamily: Some(objects))
        let queryRepo = QueryRepository(db, scope, columnFamily: Some(indexes))
        let member = match (queryRepo.readMemberAt(pageQuery(arcid), UInt64(rank))) {
            case RocksDbOperationResult<QueryMember>.Ok(value) => value
            case RocksDbOperationResult<QueryMember>.NotFound => return RocksDbOperationResult<Unit>.NotFound
            case RocksDbOperationResult<QueryMember>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
        }
        if (member.entityType != objectRepo.objectType()) {
            return RocksDbOperationResult<Unit>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "archive page membership has wrong entity type"))
        }
        return objectRepo.put(member.entityId, page)
    }

    private static func pageQuery(arcid: String): String {
        return "archive-pages:${arcid}"
    }

    private static func pageEntityId(page: PageInfo, rank: Int64): String {
        if (page.id.size > 0) {
            return page.id
        }
        if (page.sourcePath.size > 0) {
            return page.sourcePath
        }
        return "rank:${rank}"
    }
}
