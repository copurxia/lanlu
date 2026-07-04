package lanlu.contexts.asset.infrastructure.persistence

import ace_orm.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import lanlu.contexts.asset.domain.*
import stdx.log.*

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
    public static func create(
        ownerUserId: Option<Int64>,
        kind: String,
        originalFilename: String,
        contentType: String,
        fileExt: String,
        byteSize: Int64,
        thumbhash: String
    ): Option<Int64> {
        let logger = getLogger("asset_dao")
        let ownerParam: DbValue = match (ownerUserId) {
            case Some(uid) => DbInt(uid)
            case None => DbNull
        }
        try {
            let rows = DatabaseConfig.driver().query("""
                INSERT INTO assets (owner_user_id, kind, original_filename, content_type, file_ext, byte_size, thumbhash)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                RETURNING id
            """, [ownerParam, DbText(kind), DbText(originalFilename), DbText(contentType), DbText(fileExt), DbInt(byteSize), DbText(thumbhash)])
            if (rows.size > 0) {
                let id = rows[0].getInt("id")
                if (id > 0) { return Some(id) }
            }
            return None
        } catch (e: Exception) {
            logger.error("create asset failed", ("error", e.message))
            return None
        }
    }

    public static func getById(id: Int64): AssetRow {
        if (id <= 0) { return AssetRow() }
        let logger = getLogger("asset_dao")
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, owner_user_id, kind, original_filename, content_type, file_ext, byte_size, thumbhash, created_at
                FROM assets
                WHERE id = $1
            """, [DbInt(id)])
            if (rows.size > 0) {
                let r = rows[0]
                let row = AssetRow()
                row.id = r.getInt("id")
                row.ownerUserId = r.getInt("owner_user_id")
                row.kind = r.getText("kind")
                row.originalFilename = r.getText("original_filename")
                row.contentType = r.getText("content_type")
                row.fileExt = r.getText("file_ext")
                row.byteSize = r.getInt("byte_size")
                row.thumbhash = r.getText("thumbhash")
                row.createdAt = r.getText("created_at")
                return row
            }
            return AssetRow()
        } catch (e: Exception) {
            logger.error("get asset failed", ("error", e.message))
            return AssetRow()
        }
    }

    public static func updateThumbhash(id: Int64, thumbhash: String): Bool {
        if (id <= 0) { return false }
        let logger = getLogger("asset_dao")
        try {
            DatabaseConfig.driver().exec("UPDATE assets SET thumbhash = $1 WHERE id = $2", [DbText(thumbhash), DbInt(id)])
            return true
        } catch (e: Exception) {
            logger.error("update thumbhash failed", ("error", e.message))
            return false
        }
    }

    public static func deleteById(id: Int64): Bool {
        if (id <= 0) { return true }
        let logger = getLogger("asset_dao")
        try {
            DatabaseConfig.driver().exec("DELETE FROM assets WHERE id = $1", [DbInt(id)])
            return true
        } catch (e: Exception) {
            logger.error("delete asset failed", ("error", e.message))
            return false
        }
    }
}