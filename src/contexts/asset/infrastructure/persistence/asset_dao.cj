package lanlu.contexts.asset.infrastructure.persistence

import csorm.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import lanlu.contexts.asset.domain.*

public class AssetRow {
    public var id: Int64 = 0
    public var ownerUserId: Int64 = 0
    public var kind: String = ""
    public var originalFilename: String = ""
    public var contentType: String = ""
    public var fileExt: String = ""
    public var byteSize: Int64 = 0
    public var thumbhash: String = ""
    public var createdAt: String = ""

    public mut prop assetKind: AssetKind {
        get() {
            AssetKind.fromDb(kind)
        }
        set(value) {
            kind = value.toDb()
        }
    }

    public init() {}
}

public class AssetDao {
    private static let logger = getLogger("asset_dao")

    public static func create(
        ownerUserId: Option<Int64>,
        kind: String,
        originalFilename: String,
        contentType: String,
        fileExt: String,
        byteSize: Int64,
        thumbhash: String
    ): Option<Int64> {
        let params: Array<Value> = [
            match (ownerUserId) {
                case Some(uid) => vint(uid)
                case None => vnull()
            },
            vtext(kind),
            vtext(originalFilename),
            vtext(contentType),
            vtext(fileExt),
            vint(byteSize),
            vtext(thumbhash)
        ]
        let sql = """
            INSERT INTO assets (owner_user_id, kind, original_filename, content_type, file_ext, byte_size, thumbhash)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            RETURNING id
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<Int64>(sql, params, { r => r.getInt64(0) })
                } catch (e: Exception) {
                    logger.error("create asset failed", ("error", e.message))
                    return None
                }
            case None => return None
        }
    }

    public static func getById(id: Int64): AssetRow {
        if (id <= 0) { return AssetRow() }
        let params: Array<Value> = [vint(id)]
        let sql = """
            SELECT id, owner_user_id, kind, original_filename, content_type, file_ext, byte_size, thumbhash, created_at
            FROM assets
            WHERE id = $1
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<AssetRow>(sql, params, { row =>
                        let r = AssetRow()
                        r.id = row.getOrNullInt64(0) ?? 0
                        r.ownerUserId = row.getOrNullInt64(1) ?? 0
                        r.kind = row.getOrNullText(2) ?? ""
                        r.originalFilename = row.getOrNullText(3) ?? ""
                        r.contentType = row.getOrNullText(4) ?? ""
                        r.fileExt = row.getOrNullText(5) ?? ""
                        r.byteSize = row.getOrNullInt64(6) ?? 0
                        r.thumbhash = row.getOrNullText(7) ?? ""
                        r.createdAt = row.getOrNullText(8) ?? ""
                        return r
                    })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return AssetRow()
                } catch (e: Exception) {
                    logger.error("get asset failed", ("error", e.message))
                    return AssetRow()
                }
            case None => return AssetRow()
        }
    }

    public static func updateThumbhash(id: Int64, thumbhash: String): Bool {
        if (id <= 0) { return false }
        let params: Array<Value> = [vtext(thumbhash), vint(id)]
        let sql = "UPDATE assets SET thumbhash = $1 WHERE id = $2"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let affected = db.execRaw(sql, params)
                    return affected > 0
                } catch (e: Exception) {
                    logger.error("update thumbhash failed", ("error", e.message))
                    return false
                }
            case None => return false
        }
    }

    public static func deleteById(id: Int64): Bool {
        if (id <= 0) { return true }
        let params: Array<Value> = [vint(id)]
        let sql = "DELETE FROM assets WHERE id = $1"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("delete asset failed", ("error", e.message))
                    return false
                }
            case None => return false
        }
    }
}