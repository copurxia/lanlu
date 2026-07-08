package lanlu.contexts.user.infrastructure.persistence

import csorm.*
import postgresql_driver.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import lanlu.shared.enums.*
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
    public var lastUsedIp: String = ""
    public var userAgent: String = ""
    public var expiresAt: String = ""

    public init() {}

    /** 令牌类型枚举视图（csorm ActiveEnum 落地）。 */
    public mut prop tokenTypeEnum: TokenType {
        get() { TokenType.parse(tokenType) }
        set(v) { tokenType = v.toValue() }
    }
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
        let actualType = TokenType.parse(tokenType).toValue()  // 非法值回退 session（与原逻辑一致）

        let params: Array<Value> = [
            vint(userId),
            vtext(name.trimAscii()),
            vtext(actualType),
            vtext(prefix),
            vtext(tokenHash)
        ]
        let sql = """
            INSERT INTO user_tokens (user_id, name, token_type, token_prefix, token_hash)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING id
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let tokenIdOpt = db.rawOne<Int64>(sql, params, { r => r.getInt64(0) })
                    match (tokenIdOpt) {
                        case Some(tokenId) =>
                            if (tokenId > 0) {
                                return Some(CreateTokenResult(tokenId, token, prefix))
                            }
                        case None => ()
                    }
                    return None
                } catch (_: Exception) {
                    return None
                }
            case None => return None
        }
    }

    public static func findActiveByHash(tokenHash: String): UserTokenRow {
        let params: Array<Value> = [vtext(tokenHash)]
        let sql = """
            SELECT id, user_id, name, token_type, token_prefix, token_hash, created_at,
                   COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, ''),
                   COALESCE(last_used_ip, ''), COALESCE(user_agent, ''), COALESCE(expires_at::text, '')
            FROM user_tokens
            WHERE token_hash = $1 AND revoked_at IS NULL
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<UserTokenRow>(sql, params, { row =>
                        let r = UserTokenRow()
                        r.id = row.getOrNullInt64(0) ?? 0
                        r.userId = row.getOrNullInt64(1) ?? 0
                        r.name = row.getOrNullText(2) ?? ""
                        r.tokenType = row.getOrNullText(3) ?? "session"
                        r.tokenPrefix = row.getOrNullText(4) ?? ""
                        r.tokenHash = row.getOrNullText(5) ?? ""
                        r.createdAt = row.getOrNullText(6) ?? ""
                        r.lastUsedAt = row.getOrNullText(7) ?? ""
                        r.revokedAt = row.getOrNullText(8) ?? ""
                        r.lastUsedIp = row.getOrNullText(9) ?? ""
                        r.userAgent = row.getOrNullText(10) ?? ""
                        r.expiresAt = row.getOrNullText(11) ?? ""
                        return r
                    })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return UserTokenRow()
                } catch (_: Exception) {
                    return UserTokenRow()
                }
            case None => return UserTokenRow()
        }
    }

    public static func touch(tokenId: Int64): Bool {
        return touchUsage(tokenId, "", "")
    }

    public static func touchUsage(tokenId: Int64, ip: String, userAgent: String): Bool {
        let params: Array<Value> = [
            vtext(ip.trimAscii()),
            vtext(userAgent.trimAscii()),
            vint(tokenId)
        ]
        let sql = """
            UPDATE user_tokens
            SET last_used_at = CURRENT_TIMESTAMP,
                last_used_ip = $1,
                user_agent = $2
            WHERE id = $3
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (_: Exception) {
                    return false
                }
            case None => return false
        }
    }

    public static func listByUser(userId: Int64): Array<UserTokenRow> {
        return listByUserAndType(userId, None)
    }

    public static func listByUserAndType(userId: Int64, tokenType: Option<String>): Array<UserTokenRow> {
        var out: ArrayList<UserTokenRow> = ArrayList<UserTokenRow>()
        let (sql, params) = match (tokenType) {
            case Some(t) => ("""
                SELECT id, user_id, name, token_type, token_prefix, token_hash, created_at,
                       COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, ''),
                       COALESCE(last_used_ip, ''), COALESCE(user_agent, ''), COALESCE(expires_at::text, '')
                FROM user_tokens
                WHERE user_id = $1 AND token_type = $2 AND revoked_at IS NULL
                ORDER BY id DESC
            """, [vint(userId), vtext(t)])
            case None => ("""
                SELECT id, user_id, name, token_type, token_prefix, token_hash, created_at,
                       COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, ''),
                       COALESCE(last_used_ip, ''), COALESCE(user_agent, ''), COALESCE(expires_at::text, '')
                FROM user_tokens
                WHERE user_id = $1 AND revoked_at IS NULL
                ORDER BY id DESC
            """, [vint(userId)])
        }
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<UserTokenRow>(sql, params, { row =>
                        let r = UserTokenRow()
                        r.id = row.getOrNullInt64(0) ?? 0
                        r.userId = row.getOrNullInt64(1) ?? 0
                        r.name = row.getOrNullText(2) ?? ""
                        r.tokenType = row.getOrNullText(3) ?? "session"
                        r.tokenPrefix = row.getOrNullText(4) ?? ""
                        r.tokenHash = row.getOrNullText(5) ?? ""
                        r.createdAt = row.getOrNullText(6) ?? ""
                        r.lastUsedAt = row.getOrNullText(7) ?? ""
                        r.revokedAt = row.getOrNullText(8) ?? ""
                        r.lastUsedIp = row.getOrNullText(9) ?? ""
                        r.userAgent = row.getOrNullText(10) ?? ""
                        r.expiresAt = row.getOrNullText(11) ?? ""
                        return r
                    })
                    for (row in rows) {
                        out.add(row)
                    }
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
        return out.toArray()
    }

    public static func revoke(userId: Int64, tokenId: Int64): Bool {
        let params: Array<Value> = [vint(tokenId), vint(userId)]
        let sql = "UPDATE user_tokens SET revoked_at = CURRENT_TIMESTAMP WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let affected = db.execRaw(sql, params)
                    return affected > 0
                } catch (_: Exception) {
                    return false
                }
            case None => return false
        }
    }

    public static func revokeById(tokenId: Int64): Bool {
        let params: Array<Value> = [vint(tokenId)]
        let sql = "UPDATE user_tokens SET revoked_at = CURRENT_TIMESTAMP WHERE id = $1 AND revoked_at IS NULL"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let affected = db.execRaw(sql, params)
                    return affected > 0
                } catch (_: Exception) {
                    return false
                }
            case None => return false
        }
    }

    public static func revokeByUserAndType(userId: Int64, tokenId: Int64, tokenType: String): Bool {
        let normalizedType = tokenType.trimAscii()
        if (userId <= 0 || tokenId <= 0 || normalizedType.size == 0) {
            return false
        }

        let params: Array<Value> = [vint(tokenId), vint(userId), vtext(normalizedType)]
        let sql = """
            UPDATE user_tokens
            SET revoked_at = CURRENT_TIMESTAMP
            WHERE id = $1 AND user_id = $2 AND token_type = $3 AND revoked_at IS NULL
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let affected = db.execRaw(sql, params)
                    return affected > 0
                } catch (_: Exception) {
                    return false
                }
            case None => return false
        }
    }

    public static func revokeAllByUserAndType(userId: Int64, tokenType: String): Bool {
        let normalizedType = tokenType.trimAscii()
        if (userId <= 0 || normalizedType.size == 0) {
            return false
        }

        let params: Array<Value> = [vint(userId), vtext(normalizedType)]
        let sql = """
            UPDATE user_tokens
            SET revoked_at = CURRENT_TIMESTAMP
            WHERE user_id = $1 AND token_type = $2 AND revoked_at IS NULL
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let affected = db.execRaw(sql, params)
                    return affected >= 0
                } catch (_: Exception) {
                    return false
                }
            case None => return false
        }
    }

    public static func revokeAllByUserAndTypeExcept(userId: Int64, tokenType: String, excludedTokenId: Int64): Bool {
        let normalizedType = tokenType.trimAscii()
        if (userId <= 0 || normalizedType.size == 0 || excludedTokenId <= 0) {
            return false
        }

        let params: Array<Value> = [vint(userId), vtext(normalizedType), vint(excludedTokenId)]
        let sql = """
            UPDATE user_tokens
            SET revoked_at = CURRENT_TIMESTAMP
            WHERE user_id = $1 AND token_type = $2 AND id <> $3 AND revoked_at IS NULL
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let affected = db.execRaw(sql, params)
                    return affected >= 0
                } catch (_: Exception) {
                    return false
                }
            case None => return false
        }
    }
}