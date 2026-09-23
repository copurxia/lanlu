package lanlu_client_next.net

import lanlu_client_next.storage.{ObjectCodec, ObjectRepository, QueryMember, QueryPage, QueryRepository,
    StorageKeyCodec, StorageScope}
import rocksdb_ffi.{RocksDb, RocksDbColumnFamily, RocksDbOperationResult, RocksDbError, RocksDbErrorKind,
    RocksDbWriteBatch}
import std.collection.ArrayList

public let MAX_TAG_TRANSLATIONS: Int64 = 65536
private let TAG_TRANSLATION_HOT_CACHE_SIZE: Int64 = 64

// TagTranslation 主记录只保存 (canonical, translated) 规范对；同一 (lang, tag) 的翻译在
// 档案详情与合集详情之间共享，各 scope 只保存 query membership，不长期持有整张 HashMap。
private class TagTranslationCodec <: ObjectCodec<(String, String)> {
    public func typeName(): String {
        return "tag-translation"
    }

    public func schemaVersion(): UInt32 {
        return 1u32
    }

    public func encode(value: (String, String)): RocksDbOperationResult<Array<UInt8>> {
        let (canonical, translated) = value
        return RocksDbOperationResult<Array<UInt8>>.Ok(
            StorageKeyCodec.encodeStrings([canonical, translated]))
    }

    public func decode(payload: Array<UInt8>, schemaVersion: UInt32): RocksDbOperationResult<(String, String)> {
        if (schemaVersion != 1u32) {
            return decodeError("unsupported tag-translation schema")
        }
        let raw = match (StorageKeyCodec.decode(payload)) {
            case Some(value) => value
            case None => return decodeError("malformed tag-translation payload")
        }
        if (raw.size != 2) {
            return decodeError("tag-translation payload field count is invalid")
        }
        try {
            return RocksDbOperationResult<(String, String)>.Ok((String.fromUtf8(raw[0]), String.fromUtf8(raw[1])))
        } catch (_: Exception) {
            return decodeError("tag-translation payload contains invalid UTF-8")
        }
    }

    private static func decodeError(message: String): RocksDbOperationResult<(String, String)> {
        return RocksDbOperationResult<(String, String)>.Err(RocksDbError(RocksDbErrorKind.DecodeFailure, message))
    }
}

/**
 * Exposes one scope's tag translation membership without retaining the full map in state.
 * Only the fixed-size hot window keeps decoded entries between frames.
 */
public class TagTranslationView {
    public let queryKey: String
    public let language: String
    private let translationStore: ?TagTranslationStore
    private let serverHash: String
    private let accountScope: String
    private let memoryEntries: ?Array<(String, String)>
    private let entryCount: Int64
    private let cacheRanks = Array<Int64>(TAG_TRANSLATION_HOT_CACHE_SIZE, repeat: -1)
    private let cacheEntries = Array<Option<(String, String)>>(TAG_TRANSLATION_HOT_CACHE_SIZE, {_ => None})
    private var nextCacheSlot: Int64 = 0

    private init(
        queryKey: String,
        language: String,
        store: ?TagTranslationStore,
        serverHash: String,
        accountScope: String,
        memory: ?Array<(String, String)>,
        count: Int64
    ) {
        this.queryKey = queryKey
        this.language = language
        translationStore = store
        this.serverHash = serverHash
        this.accountScope = accountScope
        memoryEntries = memory
        entryCount = count
    }

    /** Creates an empty view for initial UI state. */
    public static func empty(queryKey!: String = "", language!: String = ""): TagTranslationView {
        return TagTranslationView(queryKey, language, None, "", "", Some(Array<(String, String)>()), 0)
    }

    /** Creates the bounded fallback used when the cache database is unavailable. */
    public static func memory(
        queryKey: String,
        language: String,
        entries: ArrayList<(String, String)>
    ): TagTranslationView {
        let values = entries.toArray()
        return TagTranslationView(queryKey, language, None, "", "", Some(values), values.size)
    }

    internal static func persisted(
        queryKey: String,
        language: String,
        store: TagTranslationStore,
        serverHash: String,
        accountScope: String,
        count: Int64
    ): TagTranslationView {
        return TagTranslationView(queryKey, language, Some(store), serverHash, accountScope, None, count)
    }

    public prop size: Int64 {
        get() {
            return entryCount
        }
    }

    /** Loads one rank and retains it only in the fixed-size hot window. */
    public func entryAt(index: Int64): Option<(String, String)> {
        if (index < 0 || index >= entryCount) {
            return None
        }
        match (memoryEntries) {
            case Some(values) => return Some(values[index])
            case None => ()
        }
        for (slot in 0..TAG_TRANSLATION_HOT_CACHE_SIZE) {
            if (cacheRanks[slot] == index) {
                return cacheEntries[slot]
            }
        }
        let loaded = match (translationStore) {
            case Some(store) => store.loadEntry(serverHash, accountScope, queryKey, index)
            case None => return None
        }
        match (loaded) {
            case RocksDbOperationResult<(String, String)>.Ok(entry) =>
                cacheRanks[nextCacheSlot] = index
                cacheEntries[nextCacheSlot] = Some(entry)
                nextCacheSlot = (nextCacheSlot + 1) % TAG_TRANSLATION_HOT_CACHE_SIZE
                return Some(entry)
            case _ => return None
        }
    }

    /**
     * Direct canonical lookup: returns the translated text for a canonical tag.
     * Uses the stable entity id when persisted, otherwise scans the memory fallback.
     */
    public func lookup(canonical: String): Option<String> {
        match (memoryEntries) {
            case Some(values) =>
                for ((raw, translated) in values) {
                    if (raw == canonical) {
                        return Some(translated)
                    }
                }
                return None
            case None => ()
        }
        match (translationStore) {
            case Some(store) => match (store.lookupEntry(serverHash, accountScope, language, canonical)) {
                case RocksDbOperationResult<(String, String)>.Ok((_, translated)) => return Some(translated)
                case _ => return None
            }
            case None => return None
        }
    }
}

// Translation lists share one canonical localized entity namespace per server/account.
class TagTranslationStore {
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
        entries: ArrayList<(String, String)>
    ): RocksDbOperationResult<TagTranslationView> {
        if (entries.size > MAX_TAG_TRANSLATIONS) {
            return RocksDbOperationResult<TagTranslationView>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "tag translation count exceeds safety limit"))
        }
        let scope = StorageScope(serverHash, accountScope)
        let objectRepo = ObjectRepository<(String, String)>(db, scope, TagTranslationCodec(),
            columnFamily: Some(objects))
        let queryRepo = QueryRepository(db, scope, columnFamily: Some(indexes))
        let batch = match (RocksDbWriteBatch.create()) {
            case RocksDbOperationResult<RocksDbWriteBatch>.Ok(value) => value
            case RocksDbOperationResult<RocksDbWriteBatch>.NotFound => return RocksDbOperationResult<TagTranslationView>
                .Err(RocksDbError(RocksDbErrorKind.FfiFailure, "write batch create returned no batch"))
            case RocksDbOperationResult<RocksDbWriteBatch>.Err(error) => return RocksDbOperationResult<TagTranslationView>
                .Err(error)
        }
        try {
            match (queryRepo.deleteQueryInto(batch, queryKey)) {
                case RocksDbOperationResult<Unit>.Ok(_) => ()
                case RocksDbOperationResult<Unit>.NotFound => ()
                case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<TagTranslationView>.Err(
                    error)
            }
            for (i in 0..entries.size) {
                let entry = entries[i]
                let id = stableEntityId(language, entry)
                match (objectRepo.putInto(batch, id, entry)) {
                    case RocksDbOperationResult<Unit>.Ok(_) => ()
                    case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<TagTranslationView>
                        .NotFound
                    case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<TagTranslationView>
                        .Err(error)
                }
                match (queryRepo.addInto(batch, queryKey, UInt64(i), objectRepo.objectType(), id)) {
                    case RocksDbOperationResult<Unit>.Ok(_) => ()
                    case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<TagTranslationView>
                        .NotFound
                    case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<TagTranslationView>
                        .Err(error)
                }
            }
            return match (db.commitWriteBatchResult(batch)) {
                case RocksDbOperationResult<Unit>.Ok(_) => RocksDbOperationResult<TagTranslationView>.Ok(
                    TagTranslationView.persisted(queryKey, language, this, serverHash, accountScope, entries.size))
                case RocksDbOperationResult<Unit>.NotFound => RocksDbOperationResult<TagTranslationView>.NotFound
                case RocksDbOperationResult<Unit>.Err(error) => RocksDbOperationResult<TagTranslationView>.Err(error)
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
    ): RocksDbOperationResult<TagTranslationView> {
        let scope = StorageScope(serverHash, accountScope)
        let queryRepo = QueryRepository(db, scope, columnFamily: Some(indexes))
        let last = match (queryRepo.readPage(queryKey, limit: 1, reverse: true)) {
            case RocksDbOperationResult<QueryPage>.Ok(value) => value
            case RocksDbOperationResult<QueryPage>.NotFound => return RocksDbOperationResult<TagTranslationView>
                .NotFound
            case RocksDbOperationResult<QueryPage>.Err(error) => return RocksDbOperationResult<TagTranslationView>.Err(
                error)
        }
        if (last.members.size == 0) {
            return RocksDbOperationResult<TagTranslationView>.NotFound
        }
        if (last.members[0].rank >= UInt64(MAX_TAG_TRANSLATIONS)) {
            return RocksDbOperationResult<TagTranslationView>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "stored tag translation count exceeds safety limit"))
        }
        return RocksDbOperationResult<TagTranslationView>.Ok(
            TagTranslationView.persisted(queryKey, language, this, serverHash, accountScope,
                Int64(last.members[0].rank) + 1))
    }

    func loadEntry(
        serverHash: String,
        accountScope: String,
        queryKey: String,
        rank: Int64
    ): RocksDbOperationResult<(String, String)> {
        if (rank < 0) {
            return RocksDbOperationResult<(String, String)>.NotFound
        }
        let scope = StorageScope(serverHash, accountScope)
        let objectRepo = ObjectRepository<(String, String)>(db, scope, TagTranslationCodec(),
            columnFamily: Some(objects))
        let queryRepo = QueryRepository(db, scope, columnFamily: Some(indexes))
        let member = match (queryRepo.readMemberAt(queryKey, UInt64(rank))) {
            case RocksDbOperationResult<QueryMember>.Ok(value) => value
            case RocksDbOperationResult<QueryMember>.NotFound => return RocksDbOperationResult<(String, String)>
                .NotFound
            case RocksDbOperationResult<QueryMember>.Err(error) => return RocksDbOperationResult<(String, String)>.Err(
                error)
        }
        if (member.entityType != objectRepo.objectType()) {
            return RocksDbOperationResult<(String, String)>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "tag translation membership has wrong entity type"))
        }
        return objectRepo.get(member.entityId)
    }

    // 直接按稳定主键读取规范翻译（不需要知道 rank）。
    func lookupEntry(
        serverHash: String,
        accountScope: String,
        language: String,
        canonical: String
    ): RocksDbOperationResult<(String, String)> {
        let scope = StorageScope(serverHash, accountScope)
        let objectRepo = ObjectRepository<(String, String)>(db, scope, TagTranslationCodec(),
            columnFamily: Some(objects))
        return objectRepo.get(stableEntityId(language, (canonical, "")))
    }

    // 写回规范主记录（如收藏/标签编辑同步翻译），不动 query membership。
    func putEntry(
        serverHash: String,
        accountScope: String,
        language: String,
        entry: (String, String)
    ): RocksDbOperationResult<Unit> {
        let scope = StorageScope(serverHash, accountScope)
        let objectRepo = ObjectRepository<(String, String)>(db, scope, TagTranslationCodec(),
            columnFamily: Some(objects))
        return objectRepo.put(stableEntityId(language, entry), entry)
    }

    private static func stableEntityId(language: String, entry: (String, String)): String {
        let (canonical, _) = entry
        let lang = if (language.size > 0) {
            language
        } else {
            "_"
        }
        return "${lang}:tag:${canonical}"
    }
}
