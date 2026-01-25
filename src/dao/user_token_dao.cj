package lanlu.dao

import std.database.sql.*
import stdx.log.*
import lanlu.config.*
import lanlu.utils.*
import std.collection.*

public class UserTokenRow {
    public var id: Int64 = 0
    public var userId: Int64 = 0
    public var name: String = ""
    public var tokenType: String = ""  // "session" 登录设备, "api" 手动创建的API token
    public var tokenPrefix: String = ""
    public var tokenHash: String = ""
    public var createdAt: String = ""
    public var lastUsedAt: String = ""
    public var revokedAt: String = ""

    public init() {}
}

public class CreateTokenResult {
    public var tokenId: Int64
    public var token: String
    public var prefix: String

    public init(tokenId: Int64, token: String, prefix: String) {
        this.tokenId = tokenId
        this.token = token
        this.prefix = prefix
    }
}

public class UserTokenDao {
    // 注意：表创建已由迁移系统处理，createTable() 方法已移除

    public static func createToken(userId: Int64, name: String, tokenType: String, pepper: String): Option<CreateTokenResult> {
        let token = AuthUtils.generateTokenHex(bytesLen: 32)
        let prefix = if (token.size >= 8) {
            String.fromUtf8(token.toArray().slice(0, 8))
        } else {
            token
        }
        let tokenHash = AuthUtils.sha256Hex("${token}:${pepper}")
        let actualType = if (tokenType == "api" || tokenType == "session") { tokenType } else { "session" }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO user_tokens (user_id, name, token_type, token_prefix, token_hash)
                        VALUES (?, ?, ?, ?, ?)
                        RETURNING id
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, name.trimAscii())
                        stmt.set(2, actualType)
                        stmt.set(3, prefix)
                        stmt.set(4, tokenHash)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let tokenId = rs.getOrNull<Int64>(0) ?? 0
                                if (tokenId > 0) {
                                    return Some(CreateTokenResult(tokenId, token, prefix))
                                }
                            }
                        } finally {
                            rs.close()
                        }
                        return None
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return None
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return None
        }
    }

    public static func findActiveByHash(tokenHash: String): UserTokenRow {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, user_id, name, token_type, token_prefix, token_hash, created_at,
                               COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, '')
                        FROM user_tokens
                        WHERE token_hash = ? AND revoked_at IS NULL
                    """)
                    try {
                        stmt.set(0, tokenHash)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let row = UserTokenRow()
                                row.id = rs.getOrNull<Int64>(0) ?? 0
                                row.userId = rs.getOrNull<Int64>(1) ?? 0
                                row.name = rs.getOrNull<String>(2) ?? ""
                                row.tokenType = rs.getOrNull<String>(3) ?? "session"
                                row.tokenPrefix = rs.getOrNull<String>(4) ?? ""
                                row.tokenHash = rs.getOrNull<String>(5) ?? ""
                                row.createdAt = rs.getOrNull<String>(6) ?? ""
                                row.lastUsedAt = rs.getOrNull<String>(7) ?? ""
                                row.revokedAt = rs.getOrNull<String>(8) ?? ""
                                return row
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return UserTokenRow()
                } catch (_: Exception) {
                    return UserTokenRow()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return UserTokenRow()
        }
    }

    public static func touch(tokenId: Int64): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("UPDATE user_tokens SET last_used_at = CURRENT_TIMESTAMP WHERE id = ?")
                    stmt.set(0, tokenId)
                    stmt.update()
                    stmt.close()
                    return true
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    public static func listByUser(userId: Int64): Array<UserTokenRow> {
        return listByUserAndType(userId, None)
    }

    public static func listByUserAndType(userId: Int64, tokenType: Option<String>): Array<UserTokenRow> {
        var out: ArrayList<UserTokenRow> = ArrayList<UserTokenRow>()
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let sql = match (tokenType) {
                        case Some(t) => """
                            SELECT id, user_id, name, token_type, token_prefix, token_hash, created_at,
                                   COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, '')
                            FROM user_tokens
                            WHERE user_id = ? AND token_type = ? AND revoked_at IS NULL
                            ORDER BY id DESC
                        """
                        case None => """
                            SELECT id, user_id, name, token_type, token_prefix, token_hash, created_at,
                                   COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, '')
                            FROM user_tokens
                            WHERE user_id = ? AND revoked_at IS NULL
                            ORDER BY id DESC
                        """
                    }
                    let stmt = conn.prepareStatement(sql)
                    try {
                        stmt.set(0, userId)
                        match (tokenType) {
                            case Some(t) => stmt.set(1, t)
                            case None => ()
                        }
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let row = UserTokenRow()
                                row.id = rs.getOrNull<Int64>(0) ?? 0
                                row.userId = rs.getOrNull<Int64>(1) ?? 0
                                row.name = rs.getOrNull<String>(2) ?? ""
                                row.tokenType = rs.getOrNull<String>(3) ?? "session"
                                row.tokenPrefix = rs.getOrNull<String>(4) ?? ""
                                row.tokenHash = rs.getOrNull<String>(5) ?? ""
                                row.createdAt = rs.getOrNull<String>(6) ?? ""
                                row.lastUsedAt = rs.getOrNull<String>(7) ?? ""
                                row.revokedAt = rs.getOrNull<String>(8) ?? ""
                                out.add(row)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    ()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => ()
        }
        return out.toArray()
    }

    public static func revoke(userId: Int64, tokenId: Int64): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("UPDATE user_tokens SET revoked_at = CURRENT_TIMESTAMP WHERE id = ? AND user_id = ? AND revoked_at IS NULL")
                    stmt.set(0, tokenId)
                    stmt.set(1, userId)
                    let updated = stmt.update()
                    stmt.close()
                    return updated.rowCount > 0
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }
}
