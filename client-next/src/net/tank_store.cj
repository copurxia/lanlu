package lanlu_client_next.net

import lanlu_client_next.storage.{ObjectCodec, ObjectRepository, QueryMember, QueryPage, QueryRepository,
    StorageKeyCodec, StorageScope}
import rocksdb_ffi.{RocksDb, RocksDbColumnFamily, RocksDbOperationResult, RocksDbError, RocksDbErrorKind,
    RocksDbWriteBatch}
import std.collection.ArrayList
import std.convert.Parsable

public let MAX_TANK_LIST_ITEMS: Int64 = 4096
private let TANK_HOT_CACHE_SIZE: Int64 = 64

// TankoubonInfo 主记录只保存一份规范对象；父合集、相关合集、列表和详情都通过 query membership
// 引用同一实体，收藏等 mutation 只更新规范记录，各视图按 rank 重读共享对象。
private class TankoubonCodec <: ObjectCodec<TankoubonInfo> {
    public func typeName(): String {
        return "tankoubon"
    }

    public func schemaVersion(): UInt32 {
        return 1u32
    }

    public func encode(value: TankoubonInfo): RocksDbOperationResult<Array<UInt8>> {
        let fields = ArrayList<String>()
        fields.add(value.id)
        fields.add(value.name)
        fields.add(value.description)
        fields.add(value.coverArcid)
        fields.add("${value.archiveCount}")
        fields.add("${value.totalPages}")
        fields.add("${value.progress}")
        fields.add("${value.coverAssetId}")
        fields.add("${value.backdropAssetId}")
        fields.add("${value.clearlogoAssetId}")
        fields.add(value.createdAt)
        fields.add(value.updatedAt)
        fields.add(if (value.isfavorite) {
            "1"
        } else {
            "0"
        })
        fields.add("${value.tags.size}")
        for (tag in value.tags) {
            fields.add(tag)
        }
        return RocksDbOperationResult<Array<UInt8>>.Ok(StorageKeyCodec.encodeStrings(fields.toArray()))
    }

    public func decode(payload: Array<UInt8>, schemaVersion: UInt32): RocksDbOperationResult<TankoubonInfo> {
        if (schemaVersion != 1u32) {
            return decodeError("unsupported tankoubon schema")
        }
        let raw = match (StorageKeyCodec.decode(payload)) {
            case Some(value) => value
            case None => return decodeError("malformed tankoubon payload")
        }
        if (raw.size < 14) {
            return decodeError("tankoubon payload is missing fields")
        }
        try {
            let fields = Array<String>(raw.size, {i => String.fromUtf8(raw[i])})
            let tagCount = Int64.parse(fields[13])
            if (tagCount < 0 || raw.size != 14 + tagCount) {
                return decodeError("tankoubon payload tags are invalid")
            }
            let tank = TankoubonInfo()
            tank.id = fields[0]
            tank.name = fields[1]
            tank.description = fields[2]
            tank.coverArcid = fields[3]
            tank.archiveCount = Int64.parse(fields[4])
            tank.totalPages = Int64.parse(fields[5])
            tank.progress = Float32.parse(fields[6])
            tank.coverAssetId = Int64.parse(fields[7])
            tank.backdropAssetId = Int64.parse(fields[8])
            tank.clearlogoAssetId = Int64.parse(fields[9])
            tank.createdAt = fields[10]
            tank.updatedAt = fields[11]
            tank.isfavorite = fields[12] == "1"
            for (i in 0..tagCount) {
                tank.tags.add(fields[14 + i])
            }
            return RocksDbOperationResult<TankoubonInfo>.Ok(tank)
        } catch (_: Exception) {
            return decodeError("tankoubon payload contains invalid UTF-8 or numbers")
        }
    }

    private static func decodeError(message: String): RocksDbOperationResult<TankoubonInfo> {
        return RocksDbOperationResult<TankoubonInfo>.Err(RocksDbError(RocksDbErrorKind.DecodeFailure, message))
    }
}

/**
 * Exposes a tank list query without retaining every decoded tank in application state.
 * Only the fixed-size hot window keeps decoded records between frames.
 */
public class TankoubonView <: Iterable<TankoubonInfo> {
    public let queryKey: String
    public let language: String
    private let tankStore: ?TankoubonStore
    private let serverHash: String
    private let accountScope: String
    private let memoryItems: ?Array<TankoubonInfo>
    private let itemCount: Int64
    private let cacheRanks = Array<Int64>(TANK_HOT_CACHE_SIZE, repeat: -1)
    private let cacheItems = Array<Option<TankoubonInfo>>(TANK_HOT_CACHE_SIZE, {_ => None})
    private var nextCacheSlot: Int64 = 0

    private init(
        queryKey: String,
        language: String,
        store: ?TankoubonStore,
        serverHash: String,
        accountScope: String,
        memory: ?Array<TankoubonInfo>,
        count: Int64
    ) {
        this.queryKey = queryKey
        this.language = language
        tankStore = store
        this.serverHash = serverHash
        this.accountScope = accountScope
        memoryItems = memory
        itemCount = count
    }

    /** Creates an empty view for initial UI state. */
    public static func empty(queryKey!: String = "", language!: String = ""): TankoubonView {
        return TankoubonView(queryKey, language, None, "", "", Some(Array<TankoubonInfo>()), 0)
    }

    /** Creates the bounded fallback used when the cache database is unavailable. */
    public static func memory(
        queryKey: String,
        language: String,
        items: ArrayList<TankoubonInfo>
    ): TankoubonView {
        let values = items.toArray()
        return TankoubonView(queryKey, language, None, "", "", Some(values), values.size)
    }

    internal static func persisted(
        queryKey: String,
        language: String,
        store: TankoubonStore,
        serverHash: String,
        accountScope: String,
        count: Int64
    ): TankoubonView {
        return TankoubonView(queryKey, language, Some(store), serverHash, accountScope, None, count)
    }

    public prop size: Int64 {
        get() {
            return itemCount
        }
    }

    /** Loads one rank and retains it only in the fixed-size hot window. */
    public func itemAt(index: Int64): Option<TankoubonInfo> {
        if (index < 0 || index >= itemCount) {
            return None
        }
        match (memoryItems) {
            case Some(values) => return Some(values[index])
            case None => ()
        }
        for (slot in 0..TANK_HOT_CACHE_SIZE) {
            if (cacheRanks[slot] == index) {
                return cacheItems[slot]
            }
        }
        let loaded = match (tankStore) {
            case Some(store) => store.loadTank(serverHash, accountScope, queryKey, index)
            case None => return None
        }
        match (loaded) {
            case RocksDbOperationResult<TankoubonInfo>.Ok(item) =>
                cacheRanks[nextCacheSlot] = index
                cacheItems[nextCacheSlot] = Some(item)
                nextCacheSlot = (nextCacheSlot + 1) % TANK_HOT_CACHE_SIZE
                return Some(item)
            case _ => return None
        }
    }

    /** Returns one item or reports an invalid/unavailable rank. */
    public func at(index: Int64): TankoubonInfo {
        return itemAt(index) ?? throw IndexOutOfBoundsException("tank list item is unavailable")
    }

    public operator func [](index: Int64): TankoubonInfo {
        return at(index)
    }

    public func iterator(): Iterator<TankoubonInfo> {
        return TankoubonViewIterator(this)
    }

    /** Persists a mutated canonical tank record without rewriting query membership. */
    public func persist(tank: TankoubonInfo): Bool {
        return match (tankStore) {
            case Some(store) => match (store.putTank(serverHash, accountScope, language, tank)) {
                case RocksDbOperationResult<Unit>.Ok(_) => true
                case _ => false
            }
            case None => false
        }
    }
}

private class TankoubonViewIterator <: Iterator<TankoubonInfo> {
    private let view: TankoubonView
    private var index: Int64 = 0

    init(view: TankoubonView) {
        this.view = view
    }

    public func next(): Option<TankoubonInfo> {
        while (index < view.size) {
            let value = view.itemAt(index)
            index += 1
            if (value.isSome()) {
                return value
            }
        }
        return None
    }
}

// Tank lists share one canonical localized entity namespace per server/account.
class TankoubonStore {
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
        tanks: ArrayList<TankoubonInfo>,
        rankOffset!: Int64 = 0,
        replace!: Bool = true
    ): RocksDbOperationResult<TankoubonView> {
        if (rankOffset < 0 || tanks.size > MAX_TANK_LIST_ITEMS || rankOffset > MAX_TANK_LIST_ITEMS - tanks.size) {
            return RocksDbOperationResult<TankoubonView>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "tank list count exceeds safety limit"))
        }
        let scope = StorageScope(serverHash, accountScope)
        let objectRepo = ObjectRepository<TankoubonInfo>(db, scope, TankoubonCodec(), columnFamily: Some(objects))
        let queryRepo = QueryRepository(db, scope, columnFamily: Some(indexes))
        let batch = match (RocksDbWriteBatch.create()) {
            case RocksDbOperationResult<RocksDbWriteBatch>.Ok(value) => value
            case RocksDbOperationResult<RocksDbWriteBatch>.NotFound => return RocksDbOperationResult<TankoubonView>
                .Err(RocksDbError(RocksDbErrorKind.FfiFailure, "write batch create returned no batch"))
            case RocksDbOperationResult<RocksDbWriteBatch>.Err(error) => return RocksDbOperationResult<TankoubonView>
                .Err(error)
        }
        try {
            if (replace) {
                match (queryRepo.deleteQueryInto(batch, queryKey)) {
                    case RocksDbOperationResult<Unit>.Ok(_) => ()
                    case RocksDbOperationResult<Unit>.NotFound => ()
                    case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<TankoubonView>.Err(
                        error)
                }
            }
            for (i in 0..tanks.size) {
                let tank = tanks[i]
                let id = tankEntityId(language, tank, i)
                match (objectRepo.putInto(batch, id, tank)) {
                    case RocksDbOperationResult<Unit>.Ok(_) => ()
                    case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<TankoubonView>.NotFound
                    case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<TankoubonView>.Err(
                        error)
                }
                match (queryRepo.addInto(batch, queryKey, UInt64(rankOffset + i), objectRepo.objectType(), id)) {
                    case RocksDbOperationResult<Unit>.Ok(_) => ()
                    case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<TankoubonView>.NotFound
                    case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<TankoubonView>.Err(
                        error)
                }
            }
            return match (db.commitWriteBatchResult(batch)) {
                case RocksDbOperationResult<Unit>.Ok(_) => RocksDbOperationResult<TankoubonView>.Ok(
                    TankoubonView.persisted(queryKey, language, this, serverHash, accountScope, rankOffset + tanks.size))
                case RocksDbOperationResult<Unit>.NotFound => RocksDbOperationResult<TankoubonView>.NotFound
                case RocksDbOperationResult<Unit>.Err(error) => RocksDbOperationResult<TankoubonView>.Err(error)
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
    ): RocksDbOperationResult<TankoubonView> {
        let scope = StorageScope(serverHash, accountScope)
        let queryRepo = QueryRepository(db, scope, columnFamily: Some(indexes))
        let last = match (queryRepo.readPage(queryKey, limit: 1, reverse: true)) {
            case RocksDbOperationResult<QueryPage>.Ok(value) => value
            case RocksDbOperationResult<QueryPage>.NotFound => return RocksDbOperationResult<TankoubonView>.NotFound
            case RocksDbOperationResult<QueryPage>.Err(error) => return RocksDbOperationResult<TankoubonView>.Err(
                error)
        }
        if (last.members.size == 0) {
            return RocksDbOperationResult<TankoubonView>.NotFound
        }
        if (last.members[0].rank >= UInt64(MAX_TANK_LIST_ITEMS)) {
            return RocksDbOperationResult<TankoubonView>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "stored tank list count exceeds safety limit"))
        }
        return RocksDbOperationResult<TankoubonView>.Ok(
            TankoubonView.persisted(queryKey, language, this, serverHash, accountScope,
                Int64(last.members[0].rank) + 1))
    }

    func loadTank(
        serverHash: String,
        accountScope: String,
        queryKey: String,
        rank: Int64
    ): RocksDbOperationResult<TankoubonInfo> {
        if (rank < 0) {
            return RocksDbOperationResult<TankoubonInfo>.NotFound
        }
        let scope = StorageScope(serverHash, accountScope)
        let objectRepo = ObjectRepository<TankoubonInfo>(db, scope, TankoubonCodec(), columnFamily: Some(objects))
        let queryRepo = QueryRepository(db, scope, columnFamily: Some(indexes))
        let member = match (queryRepo.readMemberAt(queryKey, UInt64(rank))) {
            case RocksDbOperationResult<QueryMember>.Ok(value) => value
            case RocksDbOperationResult<QueryMember>.NotFound => return RocksDbOperationResult<TankoubonInfo>.NotFound
            case RocksDbOperationResult<QueryMember>.Err(error) => return RocksDbOperationResult<TankoubonInfo>.Err(
                error)
        }
        if (member.entityType != objectRepo.objectType()) {
            return RocksDbOperationResult<TankoubonInfo>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "tank list membership has wrong entity type"))
        }
        return objectRepo.get(member.entityId)
    }

    // 单合集详情/列表写回规范主记录，不动任何 query membership。
    func putTank(
        serverHash: String,
        accountScope: String,
        language: String,
        tank: TankoubonInfo
    ): RocksDbOperationResult<Unit> {
        let id = stableEntityId(language, tank) ?? return RocksDbOperationResult<Unit>.Err(
            RocksDbError(RocksDbErrorKind.Unsupported, "tank has no stable entity id"))
        let scope = StorageScope(serverHash, accountScope)
        let objectRepo = ObjectRepository<TankoubonInfo>(db, scope, TankoubonCodec(), columnFamily: Some(objects))
        return objectRepo.put(id, tank)
    }

    private static func tankEntityId(language: String, tank: TankoubonInfo, rank: Int64): String {
        match (stableEntityId(language, tank)) {
            case Some(id) => return id
            case None => ()
        }
        let lang = if (language.size > 0) {
            language
        } else {
            "_"
        }
        return "${lang}:unkeyed:${rank}"
    }

    private static func stableEntityId(language: String, tank: TankoubonInfo): Option<String> {
        if (tank.id.size > 0) {
            let lang = if (language.size > 0) {
                language
            } else {
                "_"
            }
            return Some("${lang}:tank:${tank.id}")
        }
        return None
    }
}
