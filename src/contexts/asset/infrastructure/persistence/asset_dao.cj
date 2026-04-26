package lanlu.contexts.asset.infrastructure.persistence

import std.database.sql.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import stdx.log.*
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
    public static func create(
        ownerUserId: Option<Int64>,
        kind: String,
        originalFilename: String,
        contentType: String,
        fileExt: String,
        byteSize: Int64,
        thumbhash: String
    ): Option<Int64> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(rawConn) =>
                var result: Option<Int64> = None
                try (conn = rawConn) {
                    let rawStmt = conn.prepareStatement("""
                        INSERT INTO assets (owner_user_id, kind, original_filename, content_type, file_ext, byte_size, thumbhash)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        RETURNING id
                    """)
                    try (stmt = rawStmt) {
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
                        let rawRs = stmt.query()
                        try (rs = rawRs) {
                            if (rs.next()) {
                                let id = rs.getOrNull<Int64>(0) ?? 0
                                if (id > 0) { result = Some(id) }
                            }
                        }
                    }
                } catch (e: Exception) {
                    getLogger("asset_dao").error("create asset failed", ("error", e.message))
                    return None
                }
                return result
            case None =>
                getLogger("asset_dao").error("cannot connect to database")
                return None
        }
    }

    public static func getById(id: Int64): AssetRow {
        if (id <= 0) { return AssetRow() }
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(rawConn) =>
                var result = AssetRow()
                try (conn = rawConn) {
                    let rawStmt = conn.prepareStatement("""
                        SELECT id, owner_user_id, kind, original_filename, content_type, file_ext, byte_size, thumbhash, created_at
                        FROM assets
                        WHERE id = ?
                    """)
                    try (stmt = rawStmt) {
                        stmt.set(0, id)
                        let rawRs = stmt.query()
                        try (rs = rawRs) {
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
                                result = row
                            }
                        }
                    }
                } catch (e: Exception) {
                    getLogger("asset_dao").error("get asset failed", ("error", e.message))
                    return AssetRow()
                }
                return result
            case None =>
                getLogger("asset_dao").error("cannot connect to database")
                return AssetRow()
        }
    }

    public static func updateThumbhash(id: Int64, thumbhash: String): Bool {
        if (id <= 0) { return false }
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(rawConn) =>
                var result = false
                try (conn = rawConn) {
                    let rawStmt = conn.prepareStatement("UPDATE assets SET thumbhash = ? WHERE id = ?")
                    try (stmt = rawStmt) {
                        stmt.set(0, thumbhash)
                        stmt.set(1, id)
                        stmt.update()
                        result = true
                    }
                } catch (e: Exception) {
                    getLogger("asset_dao").error("update thumbhash failed", ("error", e.message))
                    return false
                }
                return result
            case None =>
                getLogger("asset_dao").error("cannot connect to database")
                return false
        }
    }

    public static func deleteById(id: Int64): Bool {
        if (id <= 0) { return true }
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(rawConn) =>
                var result = false
                try (conn = rawConn) {
                    let rawStmt = conn.prepareStatement("DELETE FROM assets WHERE id = ?")
                    try (stmt = rawStmt) {
                        stmt.set(0, id)
                        stmt.update()
                        result = true
                    }
                } catch (e: Exception) {
                    getLogger("asset_dao").error("delete asset failed", ("error", e.message))
                    return false
                }
                return result
            case None =>
                getLogger("asset_dao").error("cannot connect to database")
                return false
        }
    }
}
