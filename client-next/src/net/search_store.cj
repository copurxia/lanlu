package lanlu_client_next.net

import lanlu_client_next.storage.{ObjectCodec, ObjectRepository, QueryMember, QueryPage, QueryRepository,
    StorageKeyCodec, StorageScope}
import rocksdb_ffi.{RocksDb, RocksDbColumnFamily, RocksDbError, RocksDbErrorKind, RocksDbOperationResult,
    RocksDbWriteBatch}
import std.collection.ArrayList
import std.convert.Parsable

public let MAX_SEARCH_ITEMS: Int64 = 100000
private let SEARCH_HOT_CACHE_SIZE: Int64 = 64

private class SearchItemCodec <: ObjectCodec<SearchItem> {
    public func typeName(): String {
        return "search-item"
    }

    public func schemaVersion(): UInt32 {
        return 1u32
    }

    public func encode(value: SearchItem): RocksDbOperationResult<Array<UInt8>> {
        return RocksDbOperationResult<Array<UInt8>>.Ok(
            StorageKeyCodec.encodeStrings(
                [
                    value.arcid,
                    value.title,
                    value.description,
                    value.tagsCsv,
                    value.archivetype,
                    value.filename,
                    "${value.coverAssetId}",
                    "${value.pagecount}",
                    "${value.progress}",
                    "${value.size}",
                    "${value.lastreadtime}",
                    if (value.isnew) {
                        "1"
                    } else {
                        "0"
                    },
                    if (value.isfavorite) {
                        "1"
                    } else {
                        "0"
                    },
                    value.itemType,
                    value.tankoubonId,
                    "${value.archiveCount}"
                ]
            )
        )
    }

    public func decode(payload: Array<UInt8>, schemaVersion: UInt32): RocksDbOperationResult<SearchItem> {
        if (schemaVersion != 1u32) {
            return decodeError("unsupported search-item schema")
        }
        let raw = match (StorageKeyCodec.decode(payload)) {
            case Some(value) => value
            case None => return decodeError("malformed search-item payload")
        }
        if (raw.size != 16) {
            return decodeError("search-item payload field count is invalid")
        }
        try {
            let fields = Array<String>(raw.size, {i => String.fromUtf8(raw[i])})
            let item = SearchItem()
            item.arcid = fields[0]
            item.title = fields[1]
            item.description = fields[2]
            item.tagsCsv = fields[3]
            item.archivetype = fields[4]
            item.filename = fields[5]
            item.coverAssetId = Int64.parse(fields[6])
            item.pagecount = Int64.parse(fields[7])
            item.progress = Int64.parse(fields[8])
            item.size = Int64.parse(fields[9])
            item.lastreadtime = Int64.parse(fields[10])
            item.isnew = fields[11] == "1"
            item.isfavorite = fields[12] == "1"
            item.itemType = fields[13]
            item.tankoubonId = fields[14]
            item.archiveCount = Int64.parse(fields[15])
            return RocksDbOperationResult<SearchItem>.Ok(item)
        } catch (_: Exception) {
            return decodeError("search-item payload contains invalid UTF-8 or numbers")
        }
    }

    private static func decodeError(message: String): RocksDbOperationResult<SearchItem> {
        return RocksDbOperationResult<SearchItem>.Err(RocksDbError(RocksDbErrorKind.DecodeFailure, message))
    }
}

/**
 * Exposes a query snapshot without retaining every decoded search item in application state.
 */
public class SearchItemView <: Iterable<SearchItem> {
    public let queryKey: String
    public let language: String
    private let searchStore: ?SearchStore
    private let serverHash: String
    private let accountScope: String
    private let memoryItems: ?Array<SearchItem>
    private let itemCount: Int64
    private let cacheRanks = Array<Int64>(SEARCH_HOT_CACHE_SIZE, repeat: -1)
    private let cacheItems = Array<Option<SearchItem>>(SEARCH_HOT_CACHE_SIZE, {_ => None})
    private var nextCacheSlot: Int64 = 0

    private init(
        queryKey: String,
        language: String,
        store: ?SearchStore,
        serverHash: String,
        accountScope: String,
        memory: ?Array<SearchItem>,
        count: Int64
    ) {
        this.queryKey = queryKey
        this.language = language
        searchStore = store
        this.serverHash = serverHash
        this.accountScope = accountScope
        memoryItems = memory
        itemCount = count
    }

    /** Creates an empty view for initial UI state. */
    public static func empty(queryKey!: String = "", language!: String = ""): SearchItemView {
        return SearchItemView(queryKey, language, None, "", "", Some(Array<SearchItem>()), 0)
    }

    /** Creates the bounded fallback used when the cache database is unavailable. */
    public static func memory(
        queryKey: String,
        language: String,
        items: ArrayList<SearchItem>
    ): SearchItemView {
        let values = items.toArray()
        return SearchItemView(queryKey, language, None, "", "", Some(values), values.size)
    }

    internal static func persisted(
        queryKey: String,
        language: String,
        store: SearchStore,
        serverHash: String,
        accountScope: String,
        count: Int64
    ): SearchItemView {
        return SearchItemView(queryKey, language, Some(store), serverHash, accountScope, None, count)
    }

    public prop size: Int64 {
        get() {
            return itemCount
        }
    }

    /** Loads one rank and retains it only in the fixed-size hot window. */
    public func itemAt(index: Int64): Option<SearchItem> {
        if (index < 0 || index >= itemCount) {
            return None
        }
        match (memoryItems) {
            case Some(values) => return Some(values[index])
            case None => ()
        }
        for (slot in 0..SEARCH_HOT_CACHE_SIZE) {
            if (cacheRanks[slot] == index) {
                return cacheItems[slot]
            }
        }
        let loaded = match (searchStore) {
            case Some(store) => store.loadItem(serverHash, accountScope, queryKey, index)
            case None => return None
        }
        match (loaded) {
            case RocksDbOperationResult<SearchItem>.Ok(item) =>
                cacheRanks[nextCacheSlot] = index
                cacheItems[nextCacheSlot] = Some(item)
                nextCacheSlot = (nextCacheSlot + 1) % SEARCH_HOT_CACHE_SIZE
                return Some(item)
            case _ => return None
        }
    }

    /** Returns one item or reports an invalid/unavailable rank. */
    public func at(index: Int64): SearchItem {
        return itemAt(index) ?? throw IndexOutOfBoundsException("search item is unavailable")
    }

    public operator func [](index: Int64): SearchItem {
        return at(index)
    }

    public func iterator(): Iterator<SearchItem> {
        return SearchItemIterator(this)
    }

    /** Persists a mutated stable archive/tank entity without rewriting query membership. */
    public func persist(item: SearchItem): Bool {
        return match (searchStore) {
            case Some(store) => match (store.putItem(serverHash, accountScope, language, item)) {
                case RocksDbOperationResult<Unit>.Ok(_) => true
                case _ => false
            }
            case None => false
        }
    }

    /**
     * Mutates the retained copy for `arcid` (memory array or hot window only) and returns it.
     * Purely in-memory: persisted views are NOT scanned rank by rank — that would be one
     * RocksDB point query per rank on the UI thread (measured 25.8ms for one meta sync).
     */
    public func updateCachedCopy(arcid: String, apply: (SearchItem) -> Unit): Option<SearchItem> {
        match (memoryItems) {
            case Some(values) =>
                for (value in values) {
                    if (value.arcid == arcid) {
                        apply(value)
                        return Some(value)
                    }
                }
                return None
            case None => ()
        }
        for (slot in 0..SEARCH_HOT_CACHE_SIZE) {
            match (cacheItems[slot]) {
                case Some(item) =>
                    if (item.arcid == arcid) {
                        apply(item)
                        return Some(item)
                    }
                case None => ()
            }
        }
        return None
    }

    /** Loads the canonical entity directly by its stable key, bypassing rank scans. */
    public func loadByArcid(arcid: String): Option<SearchItem> {
        match (searchStore) {
            case Some(store) => match (store.loadByArcid(serverHash, accountScope, language, arcid)) {
                case RocksDbOperationResult<SearchItem>.Ok(item) => Some(item)
                case _ => None
            }
            case None => None
        }
    }
}

private class SearchItemIterator <: Iterator<SearchItem> {
    private let items: SearchItemView
    private var index: Int64 = 0

    init(items: SearchItemView) {
        this.items = items
    }

    public func next(): Option<SearchItem> {
        while (index < items.size) {
            let value = items.itemAt(index)
            index += 1
            if (value.isSome()) {
                return value
            }
        }
        return None
    }
}

/**
 * Retains only matching ranks over a SearchItemView, never another array of decoded entities.
 */
public class SearchItemProjectionView <: Iterable<SearchItem> {
    private let source: SearchItemView
    private let ranks: Array<Int64>
    private let identity: Bool

    private init(source: SearchItemView, ranks: Array<Int64>, identity: Bool) {
        this.source = source
        this.ranks = ranks
        this.identity = identity
    }

    /** Projects every source rank without allocating an index array. */
    public static func all(source: SearchItemView): SearchItemProjectionView {
        return SearchItemProjectionView(source, [], true)
    }

    /** Evaluates a filter once and retains compact ranks instead of decoded SearchItem objects. */
    public static func filter(
        source: SearchItemView,
        predicate: (SearchItem) -> Bool
    ): SearchItemProjectionView {
        let selected = ArrayList<Int64>()
        for (i in 0..source.size) {
            match (source.itemAt(i)) {
                case Some(item) =>
                    if (predicate(item)) {
                        selected.add(i)
                    }
                case None => ()
            }
        }
        return SearchItemProjectionView(source, selected.toArray(), false)
    }

    public prop size: Int64 {
        get() {
            if (identity) {
                return source.size
            }
            return ranks.size
        }
    }

    public func itemAt(index: Int64): Option<SearchItem> {
        if (index < 0 || index >= size) {
            return None
        }
        return source.itemAt(if (identity) {
            index
        } else {
            ranks[index]
        })
    }

    public operator func [](index: Int64): SearchItem {
        return itemAt(index) ?? throw IndexOutOfBoundsException("projected search item is unavailable")
    }

    public func iterator(): Iterator<SearchItem> {
        return SearchItemProjectionIterator(this)
    }
}

private class SearchItemProjectionIterator <: Iterator<SearchItem> {
    private let items: SearchItemProjectionView
    private var index: Int64 = 0

    init(items: SearchItemProjectionView) {
        this.items = items
    }

    public func next(): Option<SearchItem> {
        while (index < items.size) {
            let value = items.itemAt(index)
            index += 1
            if (value.isSome()) {
                return value
            }
        }
        return None
    }
}

// Query snapshots share one canonical localized entity namespace per server/account.
class SearchStore {
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
        queryKey: String,
        language: String,
        items: ArrayList<SearchItem>,
        rankOffset!: Int64 = 0,
        replace!: Bool = true
    ): RocksDbOperationResult<SearchItemView> {
        if (rankOffset < 0 || items.size > MAX_SEARCH_ITEMS || rankOffset > MAX_SEARCH_ITEMS - items.size) {
            return RocksDbOperationResult<SearchItemView>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "search item count exceeds safety limit"))
        }
        let scope = StorageScope(serverHash, accountScope)
        let objectRepo = ObjectRepository<SearchItem>(db, scope, SearchItemCodec(), columnFamily: Some(objects))
        let queryRepo = QueryRepository(db, scope, columnFamily: Some(indexes))
        let batch = match (RocksDbWriteBatch.create()) {
            case RocksDbOperationResult<RocksDbWriteBatch>.Ok(value) => value
            case RocksDbOperationResult<RocksDbWriteBatch>.NotFound => return RocksDbOperationResult<SearchItemView>
                .Err(RocksDbError(RocksDbErrorKind.FfiFailure, "write batch create returned no batch"))
            case RocksDbOperationResult<RocksDbWriteBatch>.Err(error) => return RocksDbOperationResult<SearchItemView>
                .Err(error)
        }
        try {
            if (replace) {
                match (queryRepo.deleteQueryInto(batch, queryKey)) {
                    case RocksDbOperationResult<Unit>.Ok(_) => ()
                    case RocksDbOperationResult<Unit>.NotFound => ()
                    case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<SearchItemView>.Err(
                        error)
                }
            }
            for (i in 0..items.size) {
                let item = items[i]
                let id = entityId(language, queryKey, item, i)
                match (objectRepo.putInto(batch, id, item)) {
                    case RocksDbOperationResult<Unit>.Ok(_) => ()
                    case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<SearchItemView>.NotFound
                    case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<SearchItemView>.Err(
                        error)
                }
                match (queryRepo.addInto(batch, queryKey, UInt64(rankOffset + i), objectRepo.objectType(), id)) {
                    case RocksDbOperationResult<Unit>.Ok(_) => ()
                    case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<SearchItemView>.NotFound
                    case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<SearchItemView>.Err(
                        error)
                }
            }
            return match (db.commitWriteBatchResult(batch)) {
                case RocksDbOperationResult<Unit>.Ok(_) => RocksDbOperationResult<SearchItemView>.Ok(
                    SearchItemView.persisted(queryKey, language, this, serverHash, accountScope, rankOffset + items.size))
                case RocksDbOperationResult<Unit>.NotFound => RocksDbOperationResult<SearchItemView>.NotFound
                case RocksDbOperationResult<Unit>.Err(error) => RocksDbOperationResult<SearchItemView>.Err(error)
            }
        } finally {
            batch.close()
        }
    }

    func openView(
        serverHash: String,
        accountScope: String,
        queryKey: String,
        language: String
    ): RocksDbOperationResult<SearchItemView> {
        let scope = StorageScope(serverHash, accountScope)
        let queryRepo = QueryRepository(db, scope, columnFamily: Some(indexes))
        let last = match (queryRepo.readPage(queryKey, limit: 1, reverse: true)) {
            case RocksDbOperationResult<QueryPage>.Ok(value) => value
            case RocksDbOperationResult<QueryPage>.NotFound => return RocksDbOperationResult<SearchItemView>.NotFound
            case RocksDbOperationResult<QueryPage>.Err(error) => return RocksDbOperationResult<SearchItemView>.Err(
                error)
        }
        if (last.members.size == 0) {
            return RocksDbOperationResult<SearchItemView>.NotFound
        }
        if (last.members[0].rank >= UInt64(MAX_SEARCH_ITEMS)) {
            return RocksDbOperationResult<SearchItemView>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "stored search item count exceeds safety limit"))
        }
        return RocksDbOperationResult<SearchItemView>.Ok(
            SearchItemView.persisted(queryKey, language, this, serverHash, accountScope, Int64(last.members[0].rank) + 1))
    }

    func loadItem(
        serverHash: String,
        accountScope: String,
        queryKey: String,
        rank: Int64
    ): RocksDbOperationResult<SearchItem> {
        if (rank < 0) {
            return RocksDbOperationResult<SearchItem>.NotFound
        }
        let scope = StorageScope(serverHash, accountScope)
        let objectRepo = ObjectRepository<SearchItem>(db, scope, SearchItemCodec(), columnFamily: Some(objects))
        let queryRepo = QueryRepository(db, scope, columnFamily: Some(indexes))
        let member = match (queryRepo.readMemberAt(queryKey, UInt64(rank))) {
            case RocksDbOperationResult<QueryMember>.Ok(value) => value
            case RocksDbOperationResult<QueryMember>.NotFound => return RocksDbOperationResult<SearchItem>.NotFound
            case RocksDbOperationResult<QueryMember>.Err(error) => return RocksDbOperationResult<SearchItem>.Err(error)
        }
        if (member.entityType != objectRepo.objectType()) {
            return RocksDbOperationResult<SearchItem>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "search membership has wrong entity type"))
        }
        return objectRepo.get(member.entityId)
    }

    func putItem(
        serverHash: String,
        accountScope: String,
        language: String,
        item: SearchItem
    ): RocksDbOperationResult<Unit> {
        let id = stableEntityId(language, item) ?? return RocksDbOperationResult<Unit>.Err(
            RocksDbError(RocksDbErrorKind.Unsupported, "search item has no stable entity id"))
        let scope = StorageScope(serverHash, accountScope)
        let objectRepo = ObjectRepository<SearchItem>(db, scope, SearchItemCodec(), columnFamily: Some(objects))
        return objectRepo.put(id, item)
    }

    // 规范实体按 (language, arcid) 定址（与 stableEntityId 的 archive 分支同键）：
    // 元数据投影回写用它绕开按 rank 的全视图扫描。
    func loadByArcid(
        serverHash: String,
        accountScope: String,
        language: String,
        arcid: String
    ): RocksDbOperationResult<SearchItem> {
        if (arcid.size == 0) {
            return RocksDbOperationResult<SearchItem>.NotFound
        }
        let lang = if (language.size > 0) {
            language
        } else {
            "_"
        }
        let scope = StorageScope(serverHash, accountScope)
        let objectRepo = ObjectRepository<SearchItem>(db, scope, SearchItemCodec(), columnFamily: Some(objects))
        return objectRepo.get("${lang}:archive:${arcid}")
    }

    private static func entityId(language: String, queryKey: String, item: SearchItem, rank: Int64): String {
        match (stableEntityId(language, item)) {
            case Some(id) => return id
            case None => ()
        }
        let lang = if (language.size > 0) {
            language
        } else {
            "_"
        }
        return "${lang}:unkeyed:${queryKey}:${rank}"
    }

    private static func stableEntityId(language: String, item: SearchItem): Option<String> {
        let lang = if (language.size > 0) {
            language
        } else {
            "_"
        }
        if (item.itemType == "tankoubon" && item.tankoubonId.size > 0) {
            return Some("${lang}:tank:${item.tankoubonId}")
        }
        if (item.arcid.size > 0) {
            return Some("${lang}:archive:${item.arcid}")
        }
        return None
    }
}
