package lanlu.contexts.user.infrastructure.persistence

import ace_orm.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
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

        try {
            let rows = DatabaseConfig.driver().query("""
                INSERT INTO user_tokens (user_id, name, token_type, token_prefix, token_hash)
                VALUES ($1, $2, $3, $4, $5)
                RETURNING id
            """, [DbInt(userId), DbText(name.trimAscii()), DbText(actualType), DbText(prefix), DbText(tokenHash)])
            if (rows.size > 0) {
                let tokenId = rows[0].getInt("id")
                if (tokenId > 0) {
                    return Some(CreateTokenResult(tokenId, token, prefix))
                }
            }
            return None
        } catch (_: Exception) {
            return None
        }
    }

    public static func findActiveByHash(tokenHash: String): UserTokenRow {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, user_id, name, token_type, token_prefix, token_hash, created_at,
                       COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, ''),
                       COALESCE(last_used_ip, ''), COALESCE(user_agent, ''), COALESCE(expires_at::text, '')
                FROM user_tokens
                WHERE token_hash = $1 AND revoked_at IS NULL
            """, [DbText(tokenHash)])
            if (rows.size > 0) {
                return readRow(rows[0])
            }
            return UserTokenRow()
        } catch (_: Exception) {
            return UserTokenRow()
        }
    }

    public static func touch(tokenId: Int64): Bool {
        return touchUsage(tokenId, "", "")
    }

    public static func touchUsage(tokenId: Int64, ip: String, userAgent: String): Bool {
        try {
            DatabaseConfig.driver().exec("""
                UPDATE user_tokens
                SET last_used_at = CURRENT_TIMESTAMP,
                    last_used_ip = $1,
                    user_agent = $2
                WHERE id = $3
            """, [DbText(ip.trimAscii()), DbText(userAgent.trimAscii()), DbInt(tokenId)])
            return true
        } catch (_: Exception) {
            return false
        }
    }

    public static func listByUser(userId: Int64): Array<UserTokenRow> {
        return listByUserAndType(userId, None)
    }

    public static func listByUserAndType(userId: Int64, tokenType: Option<String>): Array<UserTokenRow> {
        var out: ArrayList<UserTokenRow> = ArrayList<UserTokenRow>()
        try {
            let (sql, params) = match (tokenType) {
                case Some(t) => ("""
                    SELECT id, user_id, name, token_type, token_prefix, token_hash, created_at,
                           COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, ''),
                           COALESCE(last_used_ip, ''), COALESCE(user_agent, ''), COALESCE(expires_at::text, '')
                    FROM user_tokens
                    WHERE user_id = $1 AND token_type = $2 AND revoked_at IS NULL
                    ORDER BY id DESC
                """, [DbInt(userId), DbText(t)])
                case None => ("""
                    SELECT id, user_id, name, token_type, token_prefix, token_hash, created_at,
                           COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, ''),
                           COALESCE(last_used_ip, ''), COALESCE(user_agent, ''), COALESCE(expires_at::text, '')
                    FROM user_tokens
                    WHERE user_id = $1 AND revoked_at IS NULL
                    ORDER BY id DESC
                """, [DbInt(userId)])
            }
            let rows = DatabaseConfig.driver().query(sql, params)
            for (r in rows) {
                out.add(readRow(r))
            }
        } catch (_: Exception) {
            ()
        }
        return out.toArray()
    }

    public static func revoke(userId: Int64, tokenId: Int64): Bool {
        try {
            let affected = DatabaseConfig.driver().exec("UPDATE user_tokens SET revoked_at = CURRENT_TIMESTAMP WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL", [DbInt(tokenId), DbInt(userId)])
            return affected > 0
        } catch (_: Exception) {
            return false
        }
    }

    public static func revokeById(tokenId: Int64): Bool {
        try {
            let affected = DatabaseConfig.driver().exec("UPDATE user_tokens SET revoked_at = CURRENT_TIMESTAMP WHERE id = $1 AND revoked_at IS NULL", [DbInt(tokenId)])
            return affected > 0
        } catch (_: Exception) {
            return false
        }
    }

    public static func revokeByUserAndType(userId: Int64, tokenId: Int64, tokenType: String): Bool {
        let normalizedType = tokenType.trimAscii()
        if (userId <= 0 || tokenId <= 0 || normalizedType.size == 0) {
            return false
        }
        try {
            let affected = DatabaseConfig.driver().exec("""
                UPDATE user_tokens
                SET revoked_at = CURRENT_TIMESTAMP
                WHERE id = $1 AND user_id = $2 AND token_type = $3 AND revoked_at IS NULL
            """, [DbInt(tokenId), DbInt(userId), DbText(normalizedType)])
            return affected > 0
        } catch (_: Exception) {
            return false
        }
    }

    public static func revokeAllByUserAndType(userId: Int64, tokenType: String): Bool {
        let normalizedType = tokenType.trimAscii()
        if (userId <= 0 || normalizedType.size == 0) {
            return false
        }
        try {
            let affected = DatabaseConfig.driver().exec("""
                UPDATE user_tokens
                SET revoked_at = CURRENT_TIMESTAMP
                WHERE user_id = $1 AND token_type = $2 AND revoked_at IS NULL
            """, [DbInt(userId), DbText(normalizedType)])
            return affected >= 0
        } catch (_: Exception) {
            return false
        }
    }

    public static func revokeAllByUserAndTypeExcept(userId: Int64, tokenType: String, excludedTokenId: Int64): Bool {
        let normalizedType = tokenType.trimAscii()
        if (userId <= 0 || normalizedType.size == 0 || excludedTokenId <= 0) {
            return false
        }
        try {
            let affected = DatabaseConfig.driver().exec("""
                UPDATE user_tokens
                SET revoked_at = CURRENT_TIMESTAMP
                WHERE user_id = $1 AND token_type = $2 AND id <> $3 AND revoked_at IS NULL
            """, [DbInt(userId), DbText(normalizedType), DbInt(excludedTokenId)])
            return affected >= 0
        } catch (_: Exception) {
            return false
        }
    }

    private static func readRow(r: Row): UserTokenRow {
        let row = UserTokenRow()
        row.id = r.getInt("id")
        row.userId = r.getInt("user_id")
        row.name = r.getText("name")
        row.tokenType = r.getText("token_type")
        row.tokenPrefix = r.getText("token_prefix")
        row.tokenHash = r.getText("token_hash")
        row.createdAt = r.getText("created_at")
        row.lastUsedAt = r.getText("last_used_at")
        row.revokedAt = r.getText("revoked_at")
        row.lastUsedIp = r.getText("last_used_ip")
        row.userAgent = r.getText("user_agent")
        row.expiresAt = r.getText("expires_at")
        return row
    }
}