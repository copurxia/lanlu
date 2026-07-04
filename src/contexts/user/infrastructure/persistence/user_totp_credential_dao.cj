package lanlu.contexts.user.infrastructure.persistence

import ace_orm.*
import lanlu.shared.config.*

public class UserTotpCredentialRow {
    public var id: Int64 = 0
    public var userId: Int64 = 0
    public var name: String = ""
    public var encryptedSecret: String = ""
    public var secretHash: String = ""
    public var digits: Int64 = 6
    public var periodSeconds: Int64 = 30
    public var algorithm: String = "SHA1"
    public var issuer: String = "Lanlu"
    public var createdAt: String = ""
    public var verifiedAt: String = ""
    public var lastUsedStep: Int64 = -1
    public var revokedAt: String = ""
    public var updatedAt: String = ""

    public init() {}
}

public class UserTotpRecoveryCodeRow {
    public var id: Int64 = 0
    public var credentialId: Int64 = 0
    public var codeHash: String = ""
    public var usedAt: String = ""
    public var createdAt: String = ""

    public init() {}
}

public class UserTotpCredentialDao {
    public static func findActiveByUserId(userId: Int64): UserTotpCredentialRow {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, user_id, name, secret_b32, secret_hash, digits, period_seconds, algorithm, issuer,
                       created_at::text, COALESCE(verified_at::text, ''), last_used_step,
                       COALESCE(revoked_at::text, ''), updated_at::text
                FROM user_totp_credentials
                WHERE user_id = $1 AND revoked_at IS NULL
                ORDER BY id DESC
                LIMIT 1
            """, [DbInt(userId)])
            if (rows.size > 0) {
                return readCredential(rows[0])
            }
        } catch (_: Exception) {
            return UserTotpCredentialRow()
        }
        return UserTotpCredentialRow()
    }

    public static func createOrReplace(
        userId: Int64,
        name: String,
        encryptedSecret: String,
        secretHash: String,
        digits: Int64,
        periodSeconds: Int64,
        algorithm: String,
        issuer: String
    ): Option<Int64> {
        try {
            DatabaseConfig.driver().exec("""
                UPDATE user_totp_credentials
                SET revoked_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                WHERE user_id = $1 AND revoked_at IS NULL
            """, [DbInt(userId)])

            let rows = DatabaseConfig.driver().query("""
                INSERT INTO user_totp_credentials (
                    user_id, name, secret_b32, secret_hash, digits, period_seconds, algorithm, issuer, verified_at
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, CURRENT_TIMESTAMP)
                RETURNING id
            """, [DbInt(userId), DbText(normalizeName(name)), DbText(encryptedSecret), DbText(secretHash),
                  DbInt(digits), DbInt(periodSeconds), DbText(algorithm.trimAscii().toAsciiUpper()), DbText(issuer.trimAscii())])
            if (rows.size > 0) {
                let id = rows[0].getInt("id")
                if (id > 0) {
                    return Some(id)
                }
            }
        } catch (_: Exception) {
            return None
        }
        return None
    }

    public static func touchStep(credentialId: Int64, matchedStep: Int64): Bool {
        try {
            let affected = DatabaseConfig.driver().exec("""
                UPDATE user_totp_credentials
                SET last_used_step = $1, updated_at = CURRENT_TIMESTAMP
                WHERE id = $2 AND revoked_at IS NULL
            """, [DbInt(matchedStep), DbInt(credentialId)])
            return affected > 0
        } catch (_: Exception) {
            return false
        }
    }

    public static func revoke(userId: Int64): Bool {
        try {
            let affected = DatabaseConfig.driver().exec("""
                UPDATE user_totp_credentials
                SET revoked_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                WHERE user_id = $1 AND revoked_at IS NULL
            """, [DbInt(userId)])
            return affected > 0
        } catch (_: Exception) {
            return false
        }
    }

    public static func replaceRecoveryCodes(credentialId: Int64, codeHashes: Array<String>): Bool {
        try {
            DatabaseConfig.driver().exec("DELETE FROM user_totp_recovery_codes WHERE credential_id = $1", [DbInt(credentialId)])
            for (hash in codeHashes) {
                DatabaseConfig.driver().exec("""
                    INSERT INTO user_totp_recovery_codes (credential_id, code_hash)
                    VALUES ($1, $2)
                """, [DbInt(credentialId), DbText(hash)])
            }
            return true
        } catch (_: Exception) {
            return false
        }
    }

    public static func countUnusedRecoveryCodes(credentialId: Int64): Int64 {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT COUNT(*)
                FROM user_totp_recovery_codes
                WHERE credential_id = $1 AND used_at IS NULL
            """, [DbInt(credentialId)])
            if (rows.size > 0) {
                return rows[0].getInt("count")
            }
        } catch (_: Exception) {
            return 0
        }
        return 0
    }

    public static func consumeRecoveryCode(credentialId: Int64, codeHash: String): Bool {
        try {
            let affected = DatabaseConfig.driver().exec("""
                UPDATE user_totp_recovery_codes
                SET used_at = CURRENT_TIMESTAMP
                WHERE credential_id = $1 AND code_hash = $2 AND used_at IS NULL
            """, [DbInt(credentialId), DbText(codeHash)])
            return affected > 0
        } catch (_: Exception) {
            return false
        }
    }

    private static func normalizeName(name: String): String {
        let trimmed = name.trimAscii()
        return if (trimmed.size > 0) { trimmed } else { "Authenticator App" }
    }

    private static func readCredential(r: Row): UserTotpCredentialRow {
        let row = UserTotpCredentialRow()
        row.id = r.getInt("id")
        row.userId = r.getInt("user_id")
        row.name = r.getText("name")
        row.encryptedSecret = r.getText("secret_b32")
        row.secretHash = r.getText("secret_hash")
        row.digits = r.getInt("digits")
        row.periodSeconds = r.getInt("period_seconds")
        row.algorithm = r.getText("algorithm")
        row.issuer = r.getText("issuer")
        row.createdAt = r.getText("created_at")
        row.verifiedAt = r.getText("verified_at")
        row.lastUsedStep = r.getInt("last_used_step")
        row.revokedAt = r.getText("revoked_at")
        row.updatedAt = r.getText("updated_at")
        return row
    }
}