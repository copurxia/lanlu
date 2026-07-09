package lanlu.contexts.user.infrastructure.persistence

import csorm.*
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
        let params: Array<Value> = [vint(userId)]
        let sql = """
            SELECT id, user_id, name, secret_b32, secret_hash, digits, period_seconds, algorithm, issuer,
                   created_at::text, COALESCE(verified_at::text, ''), last_used_step,
                   COALESCE(revoked_at::text, ''), updated_at::text
            FROM user_totp_credentials
            WHERE user_id = $1 AND revoked_at IS NULL
            ORDER BY id DESC
            LIMIT 1
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<UserTotpCredentialRow>(sql, params, { row => readCredential(row) })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return UserTotpCredentialRow()
                } catch (_: Exception) {
                    return UserTotpCredentialRow()
                }
            case None => ()
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
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    // Revoke existing active credentials for this user
                    let revokeSql = """
                        UPDATE user_totp_credentials
                        SET revoked_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                        WHERE user_id = $1 AND revoked_at IS NULL
                    """
                    db.execRaw(revokeSql, [vint(userId)])

                    let params: Array<Value> = [
                        vint(userId),
                        vtext(normalizeName(name)),
                        vtext(encryptedSecret),
                        vtext(secretHash),
                        vint(digits),
                        vint(periodSeconds),
                        vtext(algorithm.trimAscii().toAsciiUpper()),
                        vtext(issuer.trimAscii())
                    ]
                    let insertSql = """
                        INSERT INTO user_totp_credentials (
                            user_id, name, secret_b32, secret_hash, digits, period_seconds, algorithm, issuer, verified_at
                        )
                        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, CURRENT_TIMESTAMP)
                        RETURNING id
                    """
                    let idOpt = db.rawOne<Int64>(insertSql, params, { r => r.getInt64(0) })
                    match (idOpt) {
                        case Some(id) =>
                            if (id > 0) {
                                return Some(id)
                            }
                        case None => ()
                    }
                    return None
                } catch (_: Exception) {
                    return None
                }
            case None => ()
        }
        return None
    }

    public static func touchStep(credentialId: Int64, matchedStep: Int64): Bool {
        let params: Array<Value> = [vint(matchedStep), vint(credentialId)]
        let sql = """
            UPDATE user_totp_credentials
            SET last_used_step = $1, updated_at = CURRENT_TIMESTAMP
            WHERE id = $2 AND revoked_at IS NULL
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

    public static func revoke(userId: Int64): Bool {
        let params: Array<Value> = [vint(userId)]
        let sql = """
            UPDATE user_totp_credentials
            SET revoked_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
            WHERE user_id = $1 AND revoked_at IS NULL
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

    public static func replaceRecoveryCodes(credentialId: Int64, codeHashes: Array<String>): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let deleteSql = "DELETE FROM user_totp_recovery_codes WHERE credential_id = $1"
                    db.execRaw(deleteSql, [vint(credentialId)])

                    let insertSql = """
                        INSERT INTO user_totp_recovery_codes (credential_id, code_hash)
                        VALUES ($1, $2)
                    """
                    for (hash in codeHashes) {
                        db.execRaw(insertSql, [vint(credentialId), vtext(hash)])
                    }
                    return true
                } catch (_: Exception) {
                    return false
                }
            case None => return false
        }
    }

    public static func countUnusedRecoveryCodes(credentialId: Int64): Int64 {
        let params: Array<Value> = [vint(credentialId)]
        let sql = """
            SELECT COUNT(*)
            FROM user_totp_recovery_codes
            WHERE credential_id = $1 AND used_at IS NULL
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Int64>(sql, params, { r => r.getOrNullInt64(0) ?? 0 })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return 0
                } catch (_: Exception) {
                    return 0
                }
            case None => ()
        }
        return 0
    }

    public static func consumeRecoveryCode(credentialId: Int64, codeHash: String): Bool {
        let params: Array<Value> = [vint(credentialId), vtext(codeHash)]
        let sql = """
            UPDATE user_totp_recovery_codes
            SET used_at = CURRENT_TIMESTAMP
            WHERE credential_id = $1 AND code_hash = $2 AND used_at IS NULL
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

    private static func normalizeName(name: String): String {
        let trimmed = name.trimAscii()
        return if (trimmed.size > 0) { trimmed } else { "Authenticator App" }
    }

    private static func readCredential(row: Row): UserTotpCredentialRow {
        let r = UserTotpCredentialRow()
        r.id = row.getOrNullInt64(0) ?? 0
        r.userId = row.getOrNullInt64(1) ?? 0
        r.name = row.getOrNullText(2) ?? ""
        r.encryptedSecret = row.getOrNullText(3) ?? ""
        r.secretHash = row.getOrNullText(4) ?? ""
        r.digits = row.getOrNullInt64(5) ?? 6
        r.periodSeconds = row.getOrNullInt64(6) ?? 30
        r.algorithm = row.getOrNullText(7) ?? "SHA1"
        r.issuer = row.getOrNullText(8) ?? "Lanlu"
        r.createdAt = row.getOrNullText(9) ?? ""
        r.verifiedAt = row.getOrNullText(10) ?? ""
        r.lastUsedStep = row.getOrNullInt64(11) ?? -1
        r.revokedAt = row.getOrNullText(12) ?? ""
        r.updatedAt = row.getOrNullText(13) ?? ""
        return r
    }
}