package lanlu_client_next.storage

import rocksdb_ffi.{RocksDb, RocksDbColumnFamily, RocksDbOperationResult, RocksDbError, RocksDbErrorKind,
    RocksDbPrefixCursor, RocksDbWriteBatch}
import std.collection.ArrayList
import std.time.DateTime

public class StorageScope {
    public let serverId: String
    public let accountScope: String

    public init(serverId: String, accountScope: String) {
        this.serverId = serverId
        this.accountScope = accountScope
    }
}

// 每个组件使用 4 字节大端长度前缀；组件内容可以安全包含 NUL、冒号和任意 UTF-8 字节。
public class StorageKeyCodec {
    public static func encode(components: Array<Array<UInt8>>): Array<UInt8> {
        let out = ArrayList<UInt8>()
        for (component in components) {
            appendUInt32(out, UInt32(component.size))
            for (byte in component) {
                out.add(byte)
            }
        }
        return out.toArray()
    }

    public static func decode(key: Array<UInt8>): Option<Array<Array<UInt8>>> {
        let components = ArrayList<Array<UInt8>>()
        var offset: Int64 = 0
        while (offset < key.size) {
            if (key.size - offset < 4) {
                return None
            }
            let length = readUInt32(key, offset)
            offset += 4
            if (UInt64(length) > UInt64(key.size - offset)) {
                return None
            }
            let size = Int64(length)
            let componentStart = offset
            components.add(Array<UInt8>(size, {i => key[componentStart + i]}))
            offset += size
        }
        return Some(components.toArray())
    }

    public static func encodeStrings(components: Array<String>): Array<UInt8> {
        return encode(Array<Array<UInt8>>(components.size, {i => components[i].toArray()}))
    }

    public static func rankBytes(rank: UInt64): Array<UInt8> {
        let out = ArrayList<UInt8>()
        appendUInt64(out, rank)
        return out.toArray()
    }

    // 返回按字节序紧邻 prefix 的排他上界；None 仅可能出现在全 0xFF 前缀。
    public static func prefixUpperBound(prefix: Array<UInt8>): Option<Array<UInt8>> {
        let upper = prefix.clone()
        var i = upper.size - 1
        while (i >= 0) {
            if (upper[i] < 255u8) {
                upper[i] += 1u8
                return Some(upper[0..i + 1].clone())
            }
            i -= 1
        }
        return None
    }

    public static func decodeRank(bytes: Array<UInt8>): Option<UInt64> {
        if (bytes.size != 8) {
            return None
        }
        return Some(readUInt64(bytes, 0))
    }

    private static func appendUInt32(out: ArrayList<UInt8>, value: UInt32): Unit {
        let number = UInt64(value)
        out.add(UInt8((number / 16777216u64) % 256u64))
        out.add(UInt8((number / 65536u64) % 256u64))
        out.add(UInt8((number / 256u64) % 256u64))
        out.add(UInt8(number % 256u64))
    }

    private static func appendUInt64(out: ArrayList<UInt8>, value: UInt64): Unit {
        var divisor = 72057594037927936u64
        for (_ in 0..8) {
            out.add(UInt8((value / divisor) % 256u64))
            divisor /= 256u64
        }
    }

    private static func readUInt32(bytes: Array<UInt8>, offset: Int64): UInt32 {
        return UInt32(UInt64(bytes[offset]) * 16777216u64 + UInt64(bytes[offset + 1]) * 65536u64 +
            UInt64(bytes[offset + 2]) * 256u64 + UInt64(bytes[offset + 3]))
    }

    private static func readUInt64(bytes: Array<UInt8>, offset: Int64): UInt64 {
        var result = 0u64
        for (i in 0..8) {
            result = result * 256u64 + UInt64(bytes[offset + i])
        }
        return result
    }
}

public class RecordEnvelope {
    public let schemaVersion: UInt32
    public let objectType: String
    public let savedAtMs: Int64
    public let expiresAtMs: Int64
    public let payload: Array<UInt8>

    public init(
        schemaVersion: UInt32,
        objectType: String,
        savedAtMs: Int64,
        expiresAtMs: Int64,
        payload: Array<UInt8>
    ) {
        this.schemaVersion = schemaVersion
        this.objectType = objectType
        this.savedAtMs = savedAtMs
        this.expiresAtMs = expiresAtMs
        this.payload = payload
    }

    public func encode(): Array<UInt8> {
        return StorageKeyCodec.encode(
            [
                [0x4Cu8, 0x4Fu8, 0x42u8, 1u8],
                uint32Bytes(schemaVersion),
                StorageKeyCodec.rankBytes(UInt64(savedAtMs)),
                StorageKeyCodec.rankBytes(UInt64(expiresAtMs)),
                objectType.toArray(),
                payload
            ]
        )
    }

    public static func decode(bytes: Array<UInt8>): RocksDbOperationResult<RecordEnvelope> {
        let parts = match (StorageKeyCodec.decode(bytes)) {
            case Some(value) => value
            case None => return decodeError("record envelope has invalid component lengths")
        }
        if (parts.size != 6 || parts[0].size != 4 || parts[0][0] != 0x4Cu8 || parts[0][1] != 0x4Fu8 || parts[0][2] !=
            0x42u8 || parts[0][3] != 1u8 || parts[1].size != 4) {
            return decodeError("record envelope magic or field count is invalid")
        }
        let savedAt = StorageKeyCodec.decodeRank(parts[2]) ?? return decodeError("invalid savedAt")
        let expiresAt = StorageKeyCodec.decodeRank(parts[3]) ?? return decodeError("invalid expiresAt")
        if (savedAt > UInt64(Int64.Max) || expiresAt > UInt64(Int64.Max)) {
            return decodeError("record envelope timestamp exceeds Int64")
        }
        let schema = UInt32(UInt64(parts[1][0]) * 16777216u64 + UInt64(parts[1][1]) * 65536u64 + UInt64(parts[1][2]) *
            256u64 + UInt64(parts[1][3]))
        try {
            return RocksDbOperationResult<RecordEnvelope>.Ok(
                RecordEnvelope(schema, String.fromUtf8(parts[4]), Int64(savedAt), Int64(expiresAt), parts[5]))
        } catch (_: Exception) {
            return decodeError("record envelope object type is not valid UTF-8")
        }
    }

    private static func uint32Bytes(value: UInt32): Array<UInt8> {
        let number = UInt64(value)
        return [UInt8((number / 16777216u64) % 256u64), UInt8((number / 65536u64) % 256u64),
            UInt8((number / 256u64) % 256u64), UInt8(number % 256u64)]
    }

    private static func decodeError(message: String): RocksDbOperationResult<RecordEnvelope> {
        return RocksDbOperationResult<RecordEnvelope>.Err(RocksDbError(RocksDbErrorKind.DecodeFailure, message))
    }
}

public interface ObjectCodec<T> {
    func typeName(): String
    func schemaVersion(): UInt32
    func encode(value: T): RocksDbOperationResult<Array<UInt8>>
    func decode(payload: Array<UInt8>, schemaVersion: UInt32): RocksDbOperationResult<T>

    // 旧 schema 载荷升级到当前 schema；返回新 schema 的 payload 字节。
    // 默认无迁移（原样返回），codec 覆盖此方法即可支持按版本链升级。
    func migrate(payload: Array<UInt8>, fromSchema: UInt32): RocksDbOperationResult<Array<UInt8>> {
        if (fromSchema == schemaVersion()) {
            return RocksDbOperationResult<Array<UInt8>>.Ok(payload)
        }
        return RocksDbOperationResult<Array<UInt8>>.Err(
            RocksDbError(RocksDbErrorKind.DecodeFailure, "unsupported schema ${fromSchema}, no migrate"))
    }
}

public class ObjectRepository<T> {
    private let db: RocksDb
    private let scope: StorageScope
    private let codec: ObjectCodec<T>
    private let columnFamily: Option<RocksDbColumnFamily>

    public init(
        db: RocksDb,
        scope: StorageScope,
        codec: ObjectCodec<T>,
        columnFamily!: Option<RocksDbColumnFamily> = None
    ) {
        this.db = db
        this.scope = scope
        this.codec = codec
        this.columnFamily = columnFamily
    }

    public func entityKey(id: String): Array<UInt8> {
        return StorageKeyCodec.encodeStrings(
            [
                "objects",
                scope.serverId,
                scope.accountScope,
                codec.typeName(),
                id
            ]
        )
    }

    public func entityPrefix(): Array<UInt8> {
        return StorageKeyCodec.encodeStrings(
            [
                "objects",
                scope.serverId,
                scope.accountScope,
                codec.typeName()
            ]
        )
    }

    public func objectType(): String {
        return codec.typeName()
    }

    public func put(
        id: String,
        value: T,
        ttlMs!: Int64 = 0,
        savedAtMs!: Int64 = currentTimeMs()
    ): RocksDbOperationResult<Unit> {
        let created = RocksDbWriteBatch.create()
        let batch = match (created) {
            case RocksDbOperationResult<RocksDbWriteBatch>.Ok(result) => result
            case RocksDbOperationResult<RocksDbWriteBatch>.NotFound => return RocksDbOperationResult<Unit>.Err(
                RocksDbError(RocksDbErrorKind.FfiFailure, "write batch create returned no batch"))
            case RocksDbOperationResult<RocksDbWriteBatch>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
        }
        try {
            match (putInto(batch, id, value, ttlMs: ttlMs, savedAtMs: savedAtMs)) {
                case RocksDbOperationResult<Unit>.Ok(_) => return db.commitWriteBatchResult(batch)
                case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<Unit>.NotFound
                case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
            }
        } finally {
            batch.close()
        }
    }

    public func putInto(
        batch: RocksDbWriteBatch,
        id: String,
        value: T,
        ttlMs!: Int64 = 0,
        savedAtMs!: Int64 = currentTimeMs()
    ): RocksDbOperationResult<Unit> {
        let payload = match (codec.encode(value)) {
            case RocksDbOperationResult<Array<UInt8>>.Ok(result) => result
            case RocksDbOperationResult<Array<UInt8>>.NotFound => return RocksDbOperationResult<Unit>.NotFound
            case RocksDbOperationResult<Array<UInt8>>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
        }
        if (savedAtMs < 0 || ttlMs < 0 || (ttlMs > 0 && savedAtMs > Int64.Max - ttlMs)) {
            return RocksDbOperationResult<Unit>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "record timestamp or TTL is out of range"))
        }
        let expiresAtMs = if (ttlMs == 0) {
            0
        } else {
            savedAtMs + ttlMs
        }
        let envelope = RecordEnvelope(codec.schemaVersion(), codec.typeName(), savedAtMs, expiresAtMs, payload)
        return match (columnFamily) {
            case Some(cf) => batch.putBytes(cf, entityKey(id), envelope.encode())
            case None => batch.putBytes(entityKey(id), envelope.encode())
        }
    }

    public func get(
        id: String,
        allowStale!: Bool = false,
        nowMs!: Int64 = currentTimeMs()
    ): RocksDbOperationResult<T> {
        let key = entityKey(id)
        let readResult = match (columnFamily) {
            case Some(cf) => db.getBytesResult(cf, key)
            case None => db.getBytesResult(key)
        }
        let bytes = match (readResult) {
            case RocksDbOperationResult<Array<UInt8>>.Ok(value) => value
            case RocksDbOperationResult<Array<UInt8>>.NotFound => return RocksDbOperationResult<T>.NotFound
            case RocksDbOperationResult<Array<UInt8>>.Err(error) => return RocksDbOperationResult<T>.Err(error)
        }
        let envelope = match (RecordEnvelope.decode(bytes)) {
            case RocksDbOperationResult<RecordEnvelope>.Ok(value) => value
            case RocksDbOperationResult<RecordEnvelope>.NotFound => return RocksDbOperationResult<T>.NotFound
            case RocksDbOperationResult<RecordEnvelope>.Err(error) =>
                deleteBadRecord(key)
                return RocksDbOperationResult<T>.Err(error)
        }
        if (envelope.objectType != codec.typeName()) {
            deleteBadRecord(key)
            return RocksDbOperationResult<T>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "record object type does not match repository codec"))
        }
        if (!allowStale && envelope.expiresAtMs > 0 && envelope.expiresAtMs <= nowMs) {
            deleteBadRecord(key)
            return RocksDbOperationResult<T>.NotFound
        }
        // schema 落后时先按版本链迁移载荷，再解码（ObjectCodec.migrate 幂等）。
        let payload = match (codec.migrate(envelope.payload, envelope.schemaVersion)) {
            case RocksDbOperationResult<Array<UInt8>>.Ok(value) => value
            case RocksDbOperationResult<Array<UInt8>>.NotFound => return RocksDbOperationResult<T>.NotFound
            case RocksDbOperationResult<Array<UInt8>>.Err(error) =>
                deleteBadRecord(key)
                return RocksDbOperationResult<T>.Err(error)
        }
        match (codec.decode(payload, codec.schemaVersion())) {
            case RocksDbOperationResult<T>.Ok(value) => return RocksDbOperationResult<T>.Ok(value)
            case RocksDbOperationResult<T>.NotFound => return RocksDbOperationResult<T>.NotFound
            case RocksDbOperationResult<T>.Err(error) =>
                deleteBadRecord(key)
                return RocksDbOperationResult<T>.Err(error)
        }
    }

    public func delete(id: String): RocksDbOperationResult<Unit> {
        return match (columnFamily) {
            case Some(cf) => db.deleteBytesResult(cf, entityKey(id))
            case None => db.deleteBytesResult(entityKey(id))
        }
    }

    public func deleteInto(batch: RocksDbWriteBatch, id: String): RocksDbOperationResult<Unit> {
        return match (columnFamily) {
            case Some(cf) => batch.deleteBytes(cf, entityKey(id))
            case None => batch.deleteBytes(entityKey(id))
        }
    }

    public func deleteAllInto(batch: RocksDbWriteBatch): RocksDbOperationResult<Unit> {
        let prefix = entityPrefix()
        let upper = StorageKeyCodec.prefixUpperBound(prefix) ?? return RocksDbOperationResult<Unit>.Err(
            RocksDbError(RocksDbErrorKind.Unsupported, "object prefix has no finite upper bound"))
        return match (columnFamily) {
            case Some(cf) => batch.deleteRangeBytes(cf, prefix, upper)
            case None => batch.deleteRangeBytes(prefix, upper)
        }
    }

    public func multiGet(
        ids: Array<String>,
        allowStale!: Bool = false,
        nowMs!: Int64 = currentTimeMs()
    ): RocksDbOperationResult<Array<Option<T>>> {
        let values = ArrayList<Option<T>>()
        for (id in ids) {
            match (get(id, allowStale: allowStale, nowMs: nowMs)) {
                case RocksDbOperationResult<T>.Ok(value) => values.add(Some(value))
                case RocksDbOperationResult<T>.NotFound => values.add(None)
                case RocksDbOperationResult<T>.Err(error) => return RocksDbOperationResult<Array<Option<T>>>.Err(error)
            }
        }
        return RocksDbOperationResult<Array<Option<T>>>.Ok(values.toArray())
    }

    // 有界前缀 cursor：按实体 id 顺序逐项读对象，不构造全量数组。
    // startAfter 为上一页的 entityId（排他），limit 为单页上限。
    public func openCursor(
        startAfter!: Option<String> = None,
        limit!: Int64 = 64,
        allowStale!: Bool = false,
        nowMs!: Int64 = currentTimeMs()
    ): RocksDbOperationResult<ObjectPage<T>> {
        if (limit <= 0) {
            return RocksDbOperationResult<ObjectPage<T>>.Ok(ObjectPage([], None))
        }
        let prefix = entityPrefix()
        let startKey: Option<Array<UInt8>> = match (startAfter) {
            case Some(id) => Some(entityKey(id))
            case None => None
        }
        let opened = match (columnFamily) {
            case Some(cf) => db.openPrefixCursorResult(cf, prefix, startAfter: startKey, limit: limit)
            case None => db.openPrefixCursorResult(prefix, startAfter: startKey, limit: limit)
        }
        let cursor = match (opened) {
            case RocksDbOperationResult<RocksDbPrefixCursor>.Ok(value) => value
            case RocksDbOperationResult<RocksDbPrefixCursor>.NotFound => return RocksDbOperationResult<ObjectPage<T>>
                .Ok(ObjectPage([], None))
            case RocksDbOperationResult<RocksDbPrefixCursor>.Err(error) => return RocksDbOperationResult<ObjectPage<T>>
                .Err(error)
        }
        let values = ArrayList<(String, T)>()
        var nextAfter: Option<String> = None
        try {
            while (cursor.isValid()) {
                let key = match (cursor.keyBytes()) {
                    case RocksDbOperationResult<Array<UInt8>>.Ok(value) => value
                    case RocksDbOperationResult<Array<UInt8>>.NotFound => break
                    case RocksDbOperationResult<Array<UInt8>>.Err(error) => return RocksDbOperationResult<ObjectPage<T>>
                        .Err(error)
                }
                let id = match (entityIdFromKey(key)) {
                    case Some(value) => value
                    case None =>
                        cursor.next()
                        continue
                }
                match (get(id, allowStale: allowStale, nowMs: nowMs)) {
                    case RocksDbOperationResult<T>.Ok(value) =>
                        values.add((id, value))
                        nextAfter = Some(id)
                    case RocksDbOperationResult<T>.NotFound => ()
                    case RocksDbOperationResult<T>.Err(_) => ()
                }
                cursor.next()
            }
            return RocksDbOperationResult<ObjectPage<T>>.Ok(ObjectPage(values.toArray(), nextAfter))
        } finally {
            cursor.close()
        }
    }

    // 从实体 key（objects/{server}/{account}/{type}/{id}）反解实体 id。
    private func entityIdFromKey(key: Array<UInt8>): Option<String> {
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

    private static func currentTimeMs(): Int64 {
        return DateTime.now().toUnixTimeStamp().toMilliseconds()
    }

    private func deleteBadRecord(key: Array<UInt8>): Unit {
        match (columnFamily) {
            case Some(cf) => let _ = db.deleteBytesResult(cf, key)
            case None => let _ = db.deleteBytesResult(key)
        }
    }
}

// 对象有界页：值数组 + 下一页排他起点（entityId）。
public class ObjectPage<T> {
    public let values: Array<(String, T)>
    public let nextAfter: Option<String>

    public init(values: Array<(String, T)>, nextAfter: Option<String>) {
        this.values = values
        this.nextAfter = nextAfter
    }
}

public class QueryMember {
    public let rank: UInt64
    public let entityType: String
    public let entityId: String

    public init(rank: UInt64, entityType: String, entityId: String) {
        this.rank = rank
        this.entityType = entityType
        this.entityId = entityId
    }
}

public class QueryPage {
    public let members: Array<QueryMember>
    public let nextToken: Option<Array<UInt8>>

    public init(members: Array<QueryMember>, nextToken: Option<Array<UInt8>>) {
        this.members = members
        this.nextToken = nextToken
    }
}

public class QueryRepository {
    private let db: RocksDb
    private let scope: StorageScope
    private let columnFamily: Option<RocksDbColumnFamily>

    public init(
        db: RocksDb,
        scope: StorageScope,
        columnFamily!: Option<RocksDbColumnFamily> = None
    ) {
        this.db = db
        this.scope = scope
        this.columnFamily = columnFamily
    }

    public func queryPrefix(queryKey: String): Array<UInt8> {
        return StorageKeyCodec.encodeStrings(["indexes", scope.serverId, scope.accountScope, queryKey])
    }

    public func membershipKey(queryKey: String, rank: UInt64, entityType: String, entityId: String): Array<UInt8> {
        let prefixParts = ["indexes".toArray(), scope.serverId.toArray(), scope.accountScope.toArray(),
            queryKey.toArray(), StorageKeyCodec.rankBytes(rank), entityType.toArray(), entityId.toArray()]
        return StorageKeyCodec.encode(prefixParts)
    }

    public func rankPrefix(queryKey: String, rank: UInt64): Array<UInt8> {
        return StorageKeyCodec.encode(
            [
                "indexes".toArray(),
                scope.serverId.toArray(),
                scope.accountScope.toArray(),
                queryKey.toArray(),
                StorageKeyCodec.rankBytes(rank)
            ]
        )
    }

    public func addInto(
        batch: RocksDbWriteBatch,
        queryKey: String,
        rank: UInt64,
        entityType: String,
        entityId: String
    ): RocksDbOperationResult<Unit> {
        return match (columnFamily) {
            case Some(cf) => batch.putBytes(cf, membershipKey(queryKey, rank, entityType, entityId), Array<UInt8>())
            case None => batch.putBytes(membershipKey(queryKey, rank, entityType, entityId), Array<UInt8>())
        }
    }

    public func deleteMemberInto(
        batch: RocksDbWriteBatch,
        queryKey: String,
        rank: UInt64,
        entityType: String,
        entityId: String
    ): RocksDbOperationResult<Unit> {
        let key = membershipKey(queryKey, rank, entityType, entityId)
        return match (columnFamily) {
            case Some(cf) => batch.deleteBytes(cf, key)
            case None => batch.deleteBytes(key)
        }
    }

    public func deleteQuery(queryKey: String): RocksDbOperationResult<Unit> {
        return match (columnFamily) {
            case Some(cf) => db.deletePrefixResult(cf, queryPrefix(queryKey))
            case None => db.deletePrefixResult(queryPrefix(queryKey))
        }
    }

    public func deleteQueryInto(batch: RocksDbWriteBatch, queryKey: String): RocksDbOperationResult<Unit> {
        let prefix = queryPrefix(queryKey)
        let upper = StorageKeyCodec.prefixUpperBound(prefix) ?? return RocksDbOperationResult<Unit>.Err(
            RocksDbError(RocksDbErrorKind.Unsupported, "query prefix has no finite upper bound"))
        return match (columnFamily) {
            case Some(cf) => batch.deleteRangeBytes(cf, prefix, upper)
            case None => batch.deleteRangeBytes(prefix, upper)
        }
    }

    // ordered membership 的 rank 是连续页序，因此可按精确 rank 前缀读取，不维护 count/index KV 表。
    public func readMemberAt(queryKey: String, rank: UInt64): RocksDbOperationResult<QueryMember> {
        let prefix = rankPrefix(queryKey, rank)
        let opened = match (columnFamily) {
            case Some(cf) => db.openPrefixCursorResult(cf, prefix, limit: 1)
            case None => db.openPrefixCursorResult(prefix, limit: 1)
        }
        let cursor = match (opened) {
            case RocksDbOperationResult<RocksDbPrefixCursor>.Ok(value) => value
            case RocksDbOperationResult<RocksDbPrefixCursor>.NotFound => return RocksDbOperationResult<QueryMember>
                .NotFound
            case RocksDbOperationResult<RocksDbPrefixCursor>.Err(error) => return RocksDbOperationResult<QueryMember>
                .Err(error)
        }
        try {
            if (!cursor.isValid()) {
                return RocksDbOperationResult<QueryMember>.NotFound
            }
            let key = match (cursor.keyBytes()) {
                case RocksDbOperationResult<Array<UInt8>>.Ok(value) => value
                case RocksDbOperationResult<Array<UInt8>>.NotFound => return RocksDbOperationResult<QueryMember>
                    .NotFound
                case RocksDbOperationResult<Array<UInt8>>.Err(error) => return RocksDbOperationResult<QueryMember>.Err(
                    error)
            }
            return decodeMemberKey(key)
        } finally {
            cursor.close()
        }
    }

    public func readPage(
        queryKey: String,
        startAfter!: Option<Array<UInt8>> = None,
        limit!: Int64 = 64,
        reverse!: Bool = false
    ): RocksDbOperationResult<QueryPage> {
        let prefix = queryPrefix(queryKey)
        let opened = match (columnFamily) {
            case Some(cf) => db.openPrefixCursorResult(cf, prefix, startAfter: startAfter, limit: limit,
                reverse: reverse)
            case None => db.openPrefixCursorResult(prefix, startAfter: startAfter, limit: limit, reverse: reverse)
        }
        let cursor = match (opened) {
            case RocksDbOperationResult<RocksDbPrefixCursor>.Ok(value) => value
            case RocksDbOperationResult<RocksDbPrefixCursor>.NotFound => return RocksDbOperationResult<QueryPage>.Ok(
                QueryPage([], None))
            case RocksDbOperationResult<RocksDbPrefixCursor>.Err(error) => return RocksDbOperationResult<QueryPage>
                .Err(error)
        }
        let members = ArrayList<QueryMember>()
        var nextToken: Option<Array<UInt8>> = None
        try {
            while (cursor.isValid()) {
                let key = match (cursor.keyBytes()) {
                    case RocksDbOperationResult<Array<UInt8>>.Ok(value) => value
                    case RocksDbOperationResult<Array<UInt8>>.NotFound => break
                    case RocksDbOperationResult<Array<UInt8>>.Err(error) => return RocksDbOperationResult<QueryPage>
                        .Err(error)
                }
                match (decodeMemberKey(key)) {
                    case RocksDbOperationResult<QueryMember>.Ok(value) => members.add(value)
                    case RocksDbOperationResult<QueryMember>.NotFound => ()
                    case RocksDbOperationResult<QueryMember>.Err(error) => return RocksDbOperationResult<QueryPage>
                        .Err(error)
                }
                nextToken = Some(key)
                cursor.next()
            }
            match (cursor.status()) {
                case RocksDbOperationResult<Unit>.Ok(_) => ()
                case RocksDbOperationResult<Unit>.NotFound => ()
                case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<QueryPage>.Err(error)
            }
            return RocksDbOperationResult<QueryPage>.Ok(QueryPage(members.toArray(), nextToken))
        } finally {
            cursor.close()
        }
    }

    private func decodeMemberKey(key: Array<UInt8>): RocksDbOperationResult<QueryMember> {
        let parts = match (StorageKeyCodec.decode(key)) {
            case Some(value) => value
            case None => return RocksDbOperationResult<QueryMember>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "query membership key is malformed"))
        }
        if (parts.size != 7) {
            return RocksDbOperationResult<QueryMember>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "query membership field count is invalid"))
        }
        let rank = StorageKeyCodec.decodeRank(parts[4]) ?? return RocksDbOperationResult<QueryMember>.Err(
            RocksDbError(RocksDbErrorKind.DecodeFailure, "query membership rank is invalid"))
        try {
            return RocksDbOperationResult<QueryMember>.Ok(
                QueryMember(rank, String.fromUtf8(parts[5]), String.fromUtf8(parts[6])))
        } catch (_: Exception) {
            return RocksDbOperationResult<QueryMember>.Err(
                RocksDbError(RocksDbErrorKind.DecodeFailure, "query membership id is not valid UTF-8"))
        }
    }

    // ---- query metadata（TTL/版本）----
    // indexes CF 存 `{server}/{account}/query-meta/{queryKey}` -> 大端 lastUpdatedAt。
    // 只作在线缓存的版本/过期参考，不维护 count（数量由末项 rank 推导）。

    private func metaKey(queryKey: String): Array<UInt8> {
        StorageKeyCodec.encodeStrings(["indexes", scope.serverId, scope.accountScope, "query-meta", queryKey])
    }

    public func touchQuery(queryKey: String, atMs!: Int64 = DateTime.now().toUnixTimeStamp().toMilliseconds()):
        RocksDbOperationResult<Unit> {
        let key = metaKey(queryKey)
        let batch = RocksDbWriteBatch.create()
        let b = match (batch) {
            case RocksDbOperationResult<RocksDbWriteBatch>.Ok(value) => value
            case RocksDbOperationResult<RocksDbWriteBatch>.NotFound => return RocksDbOperationResult<Unit>.NotFound
            case RocksDbOperationResult<RocksDbWriteBatch>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
        }
        try {
            let written = match (columnFamily) {
                case Some(cf) => b.putBytes(cf, key, StorageKeyCodec.rankBytes(UInt64(atMs)))
                case None => b.putBytes(key, StorageKeyCodec.rankBytes(UInt64(atMs)))
            }
            match (written) {
                case RocksDbOperationResult<Unit>.Ok(_) => ()
                case RocksDbOperationResult<Unit>.NotFound => return RocksDbOperationResult<Unit>.NotFound
                case RocksDbOperationResult<Unit>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
            }
            return db.commitWriteBatchResult(b)
        } finally {
            b.close()
        }
    }

    public func lastUpdatedAt(queryKey: String): RocksDbOperationResult<Int64> {
        let key = metaKey(queryKey)
        let read = match (columnFamily) {
            case Some(cf) => db.getBytesResult(cf, key)
            case None => db.getBytesResult(key)
        }
        match (read) {
            case RocksDbOperationResult<Array<UInt8>>.Ok(bytes) =>
                if (bytes.size != 8) {
                    return RocksDbOperationResult<Int64>.Err(
                        RocksDbError(RocksDbErrorKind.DecodeFailure, "query meta timestamp is invalid"))
                }
                let ms = StorageKeyCodec.decodeRank(bytes) ?? return RocksDbOperationResult<Int64>.Err(
                    RocksDbError(RocksDbErrorKind.DecodeFailure, "query meta timestamp is invalid"))
                if (ms > UInt64(Int64.Max)) {
                    return RocksDbOperationResult<Int64>.Err(
                        RocksDbError(RocksDbErrorKind.DecodeFailure, "query meta timestamp exceeds Int64"))
                }
                return RocksDbOperationResult<Int64>.Ok(Int64(ms))
            case RocksDbOperationResult<Array<UInt8>>.NotFound => return RocksDbOperationResult<Int64>.NotFound
            case RocksDbOperationResult<Array<UInt8>>.Err(error) => return RocksDbOperationResult<Int64>.Err(error)
        }
    }

    public func deleteQueryMeta(queryKey: String): RocksDbOperationResult<Unit> {
        return match (columnFamily) {
            case Some(cf) => db.deleteBytesResult(cf, metaKey(queryKey))
            case None => db.deleteBytesResult(metaKey(queryKey))
        }
    }

    // 坏对象索引自愈：实体解码失败被删除后，删除所有引用该 entity 的 query membership，
    // 避免悬空索引。返回删除条数。
    public func purgeEntityMemberships(entityType: String, entityId: String): Int64 {
        var removed: Int64 = 0
        let target = StorageKeyCodec.encodeStrings(["indexes", scope.serverId, scope.accountScope])
        let cursor = match (columnFamily) {
            case Some(cf) => db.openPrefixCursorResult(cf, target, limit: 4096)
            case None => db.openPrefixCursorResult(target, limit: 4096)
        }
        let opened = match (cursor) {
            case RocksDbOperationResult<RocksDbPrefixCursor>.Ok(value) => value
            case _ => return 0
        }
        try {
            while (opened.isValid()) {
                let key = match (opened.keyBytes()) {
                    case RocksDbOperationResult<Array<UInt8>>.Ok(value) => value
                    case _ => break
                }
                match (StorageKeyCodec.decode(key)) {
                    case Some(parts) =>
                        if (parts.size == 7) {
                            let typeName = try {
                                String.fromUtf8(parts[5])
                            } catch (_: Exception) {
                                ""
                            }
                            let idText = try {
                                String.fromUtf8(parts[6])
                            } catch (_: Exception) {
                                ""
                            }
                            if (typeName == entityType && idText == entityId) {
                                match (columnFamily) {
                                    case Some(cf) => let _ = db.deleteBytesResult(cf, key)
                                    case None => let _ = db.deleteBytesResult(key)
                                }
                                removed += 1
                            }
                        }
                    case None => ()
                }
                opened.next()
            }
        } finally {
            opened.close()
        }
        removed
    }
}

// 只保存一个有界页面；切页时整体替换，避免 view 随查询总量持续增长。
public class PagedObjectView<T> {
    private let objects: ObjectRepository<T>
    private let queries: QueryRepository
    private var pageItems: Array<T> = []
    private var pageToken: Option<Array<UInt8>> = None
    private var viewVersion: Int64 = 0

    public init(objects: ObjectRepository<T>, queries: QueryRepository) {
        this.objects = objects
        this.queries = queries
    }

    public func load(
        queryKey: String,
        startAfter!: Option<Array<UInt8>> = None,
        limit!: Int64 = 64,
        reverse!: Bool = false,
        allowStale!: Bool = false,
        nowMs!: Int64 = DateTime.now().toUnixTimeStamp().toMilliseconds()
    ): RocksDbOperationResult<Unit> {
        let queryPage = match (queries.readPage(queryKey, startAfter: startAfter, limit: limit, reverse: reverse)) {
            case RocksDbOperationResult<QueryPage>.Ok(value) => value
            case RocksDbOperationResult<QueryPage>.NotFound => QueryPage([], None)
            case RocksDbOperationResult<QueryPage>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
        }
        let loaded = ArrayList<T>()
        for (member in queryPage.members) {
            if (member.entityType != objects.objectType()) {
                continue
            }
            match (objects.get(member.entityId, allowStale: allowStale, nowMs: nowMs)) {
                case RocksDbOperationResult<T>.Ok(value) => loaded.add(value)
                case RocksDbOperationResult<T>.NotFound => ()
                case RocksDbOperationResult<T>.Err(error) => return RocksDbOperationResult<Unit>.Err(error)
            }
        }
        pageItems = loaded.toArray()
        pageToken = queryPage.nextToken
        viewVersion += 1
        return RocksDbOperationResult<Unit>.Ok(())
    }

    public func count(): Int64 {
        return pageItems.size
    }

    public func itemAt(index: Int64): Option<T> {
        if (index < 0 || index >= pageItems.size) {
            return None
        }
        return Some(pageItems[index])
    }

    public func nextToken(): Option<Array<UInt8>> {
        return pageToken
    }

    public func version(): Int64 {
        return viewVersion
    }
}
