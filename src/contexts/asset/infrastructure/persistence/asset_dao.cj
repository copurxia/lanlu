package lanlu.contexts.asset.infrastructure.persistence

import std.database.sql.*
import lanlu.shared.config.*
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
    public static func create(
        ownerUserId: Option<Int64>,
        kind: String,
        originalFilename: String,
        contentType: String,
        fileExt: String,
        byteSize: Int64,
        thumbhash: String
    ): Option<Int64> {
        return DatabaseConfig.withPooledConnection<Option<Int64>>("asset_dao", "create asset failed", None, { conn =>
            DatabaseConfig.withStatement<Option<Int64>>(conn, """
                INSERT INTO assets (owner_user_id, kind, original_filename, content_type, file_ext, byte_size, thumbhash)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                RETURNING id
            """, { stmt =>
                match (ownerUserId) {
                    case Some(uid) => stmt.set(0, uid)
                    case None => stmt.setNull(0)
                }
                stmt.set(1, kind)
                stmt.set(2, originalFilename)
                stmt.set(3, contentType)
                stmt.set(4, fileExt)
                stmt.set(5, byteSize)
                stmt.set(6, thumbhash)
                DatabaseConfig.withQueryResult<Option<Int64>>(stmt, { rs =>
                    if (rs.next()) {
                        let id = rs.getOrNull<Int64>(0) ?? 0
                        if (id > 0) { return Some(id) }
                    }
                    return None
                })
            })
        })
    }

    public static func getById(id: Int64): AssetRow {
        if (id <= 0) { return AssetRow() }
        return DatabaseConfig.withPooledConnection<AssetRow>("asset_dao", "get asset failed", AssetRow(), { conn =>
            DatabaseConfig.withStatement<AssetRow>(conn, """
                SELECT id, owner_user_id, kind, original_filename, content_type, file_ext, byte_size, thumbhash, created_at
                FROM assets
                WHERE id = ?
            """, { stmt =>
                stmt.set(0, id)
                DatabaseConfig.withQueryResult<AssetRow>(stmt, { rs =>
                    if (rs.next()) {
                        let row = AssetRow()
                        row.id = rs.getOrNull<Int64>(0) ?? 0
                        row.ownerUserId = rs.getOrNull<Int64>(1) ?? 0
                        row.kind = rs.getOrNull<String>(2) ?? ""
                        row.originalFilename = rs.getOrNull<String>(3) ?? ""
                        row.contentType = rs.getOrNull<String>(4) ?? ""
                        row.fileExt = rs.getOrNull<String>(5) ?? ""
                        row.byteSize = rs.getOrNull<Int64>(6) ?? 0
                        row.thumbhash = rs.getOrNull<String>(7) ?? ""
                        row.createdAt = rs.getOrNull<String>(8) ?? ""
                        return row
                    }
                    return AssetRow()
                })
            })
        })
    }

    public static func updateThumbhash(id: Int64, thumbhash: String): Bool {
        if (id <= 0) { return false }
        return DatabaseConfig.withPooledConnection<Bool>("asset_dao", "update thumbhash failed", false, { conn =>
            DatabaseConfig.withStatement<Bool>(conn, "UPDATE assets SET thumbhash = ? WHERE id = ?", { stmt =>
                stmt.set(0, thumbhash)
                stmt.set(1, id)
                stmt.update()
                return true
            })
        })
    }

    public static func deleteById(id: Int64): Bool {
        if (id <= 0) { return true }
        return DatabaseConfig.withPooledConnection<Bool>("asset_dao", "delete asset failed", false, { conn =>
            DatabaseConfig.withStatement<Bool>(conn, "DELETE FROM assets WHERE id = ?", { stmt =>
                stmt.set(0, id)
                stmt.update()
                return true
            })
        })
    }
}
