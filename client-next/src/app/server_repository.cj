package lanlu_client_next.app

import lanlu_client_next.storage.{ObjectCodec, ObjectRepository, QueryPage, QueryRepository, StorageKeyCodec,
    StorageScope}
import rocksdb_ffi.{RocksDb, RocksDbColumnFamily, RocksDbOperationResult, RocksDbError, RocksDbErrorKind,
    RocksDbWriteBatch}
import std.collection.ArrayList

private let SERVER_SCOPE = StorageScope("settings", "local")
private let SERVER_ORDER_QUERY = "server-order"
private let SERVER_MIGRATION_KEY = "migration:server-profiles:v3".toArray()
private let SERVER_MIGRATION_VALUE = "complete".toArray()
public let MAX_SAVED_SERVERS: Int64 = 256

private class ServerProfileCodec <: ObjectCodec<ServerProfile> {
    public func typeName(): String {
        return "server-profile"
    }

    public func schemaVersion(): UInt32 {
        return 1u32
    }

    public func encode(value: ServerProfile): RocksDbOperationResult<Array<UInt8>> {
        return RocksDbOperationResult<Array<UInt8>>.Ok(
            StorageKeyCodec.encodeStrings(
                [value.id, value.name, value.baseUrl, value.token, value.username, value.lastUsedAt]))
    }

    public func decode(
        payload: Array<UInt8>,
        schemaVersion: UInt32
    ): RocksDbOperationResult<ServerProfile> {
        if (schemaVersion != 1u32) {
            return decodeError("unsupported server-profile schema")
        }
        let parts = match (StorageKeyCodec.decode(payload)) {
            case Some(value) => value
            case None => return decodeError("malformed server-profile payload")
        }
        if (parts.size != 6) {
            return decodeError("invalid server-profile field count")
        }
        try {
            let profile = ServerProfile()
            profile.id = String.fromUtf8(parts[0])
            profile.name = String.fromUtf8(parts[1])
            profile.baseUrl = normalizeServerUrl(String.fromUtf8(parts[2]))
            profile.token = String.fromUtf8(parts[3])
            profile.username = String.fromUtf8(parts[4])
            profile.lastUsedAt = String.fromUtf8(parts[5])
            return RocksDbOperationResult<ServerProfile>.Ok(profile)
        } catch (_: Exception) {
            return decodeError("server-profile payload is not valid UTF-8")
        }
    }

    private func decodeError(message: String): RocksDbOperationResult<ServerProfile> {
        return RocksDbOperationResult<ServerProfile>.Err(RocksDbError(RocksDbErrorKind.DecodeFailure, message))
    }
}

// Server objects and their display order live in separate fixed CFs. The UI
// receives at most one bounded immutable snapshot through ServerListView.
class ServerRepository {
    private let db: RocksDb
    private let meta: RocksDbColumnFamily
    private let objectFamily: RocksDbColumnFamily
    private let indexFamily: RocksDbColumnFamily
    private let objects: ObjectRepository<ServerProfile>
    private let queries: QueryRepository

    init(
        db: RocksDb,
        meta: RocksDbColumnFamily,
        objectFamily: RocksDbColumnFamily,
        indexFamily: RocksDbColumnFamily
    ) {
        this.db = db
        this.meta = meta
        this.objectFamily = objectFamily
        this.indexFamily = indexFamily
        objects = ObjectRepository<ServerProfile>(db, SERVER_SCOPE, ServerProfileCodec(),
            columnFamily: Some(objectFamily))
        queries = QueryRepository(db, SERVER_SCOPE, columnFamily: Some(indexFamily))
    }

    func isMigrated(): Bool {
        match (db.getBytesResult(meta, SERVER_MIGRATION_KEY)) {
            case RocksDbOperationResult<Array<UInt8>>.Ok(_) => return true
            case _ => return false
        }
    }

    func load(): RocksDbOperationResult<Array<ServerProfile>> {
        let page = match (queries.readPage(SERVER_ORDER_QUERY, limit: MAX_SAVED_SERVERS + 1)) {
            case RocksDbOperationResult<QueryPage>.Ok(value) => value
            case RocksDbOperationResult<QueryPage>.NotFound => return RocksDbOperationResult<Array<ServerProfile>>.Ok(
                [])
            case RocksDbOperationResult<QueryPage>.Err(error) => return RocksDbOperationResult<Array<ServerProfile>>
                .Err(error)
        }
        if (page.members.size > MAX_SAVED_SERVERS) {
            return RocksDbOperationResult<Array<ServerProfile>>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "saved server list exceeds bounded view capacity"))
        }
        let loaded = ArrayList<ServerProfile>()
        for (member in page.members) {
            if (member.entityType != objects.objectType()) {
                continue
            }
            match (objects.get(member.entityId)) {
                case RocksDbOperationResult<ServerProfile>.Ok(profile) => loaded.add(profile)
                case RocksDbOperationResult<ServerProfile>.NotFound => ()
                case RocksDbOperationResult<ServerProfile>.Err(error) => return RocksDbOperationResult<Array<ServerProfile>>
                    .Err(error)
            }
        }
        return RocksDbOperationResult<Array<ServerProfile>>.Ok(loaded.toArray())
    }

    func writeSnapshot(
        profiles: Array<ServerProfile>,
        settingsJson: String
    ): RocksDbOperationResult<Unit> {
        if (profiles.size > MAX_SAVED_SERVERS) {
            return RocksDbOperationResult<Unit>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "saved server list exceeds bounded view capacity"))
        }
        let oldPage = match (queries.readPage(SERVER_ORDER_QUERY, limit: MAX_SAVED_SERVERS + 1)) {
            case RocksDbOperationResult<QueryPage>.Ok(value) => value
            case RocksDbOperationResult<QueryPage>.NotFound => QueryPage([], None)
            case RocksDbOperationResult<QueryPage>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
        }
        if (oldPage.members.size > MAX_SAVED_SERVERS) {
            return RocksDbOperationResult<Unit>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "saved server index exceeds bounded view capacity"))
        }

        let batch = match (RocksDbWriteBatch.create()) {
            case RocksDbOperationResult<RocksDbWriteBatch>.Ok(value) => value
            case RocksDbOperationResult<RocksDbWriteBatch>.NotFound => return RocksDbOperationResult<Unit>.Err(
                RocksDbError(RocksDbErrorKind.FfiFailure, "write batch create returned no batch"))
            case RocksDbOperationResult<RocksDbWriteBatch>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
        }
        try {
            for (member in oldPage.members) {
                match (queries.deleteMemberInto(batch, SERVER_ORDER_QUERY, member.rank, member.entityType,
                    member.entityId)) {
                    case RocksDbOperationResult<Unit>.Ok(_) => ()
                    case RocksDbOperationResult<Unit>.NotFound => ()
                    case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
                }
                if (!containsProfileId(profiles, member.entityId)) {
                    match (objects.deleteInto(batch, member.entityId)) {
                        case RocksDbOperationResult<Unit>.Ok(_) => ()
                        case RocksDbOperationResult<Unit>.NotFound => ()
                        case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
                    }
                }
            }
            for (i in 0..profiles.size) {
                let profile = profiles[i]
                match (objects.putInto(batch, profile.id, profile)) {
                    case RocksDbOperationResult<Unit>.Ok(_) => ()
                    case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<Unit>.NotFound
                    case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
                }
                match (queries.addInto(batch, SERVER_ORDER_QUERY, UInt64(i), objects.objectType(), profile.id)) {
                    case RocksDbOperationResult<Unit>.Ok(_) => ()
                    case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<Unit>.NotFound
                    case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
                }
            }
            match (batch.put("settings", settingsJson)) {
                case RocksDbOperationResult<Unit>.Ok(_) => ()
                case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<Unit>.NotFound
                case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
            }
            match (batch.putBytes(meta, SERVER_MIGRATION_KEY, SERVER_MIGRATION_VALUE)) {
                case RocksDbOperationResult<Unit>.Ok(_) => ()
                case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<Unit>.NotFound
                case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
            }
            return db.commitWriteBatchResult(batch)
        } finally {
            batch.close()
        }
    }

    func clear(): Unit {
        let _ = db.deleteResult("settings")
        let _ = db.deletePrefixResult(indexFamily, Array<UInt8>())
        let _ = db.deletePrefixResult(objectFamily, Array<UInt8>())
        let _ = db.deleteBytesResult(meta, SERVER_MIGRATION_KEY)
    }

    private static func containsProfileId(profiles: Array<ServerProfile>, id: String): Bool {
        for (profile in profiles) {
            if (profile.id == id) {
                return true
            }
        }
        return false
    }
}
