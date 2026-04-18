package lanlu.contexts.user.infrastructure.persistence

import std.database.sql.*
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, user_id, name, secret_b32, secret_hash, digits, period_seconds, algorithm, issuer,
                               created_at::text, COALESCE(verified_at::text, ''), last_used_step,
                               COALESCE(revoked_at::text, ''), updated_at::text
                        FROM user_totp_credentials
                        WHERE user_id = ? AND revoked_at IS NULL
                        ORDER BY id DESC
                        LIMIT 1
                    """)
                    try {
                        stmt.set(0, userId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return readCredential(rs)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return UserTotpCredentialRow()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let revokeStmt = conn.prepareStatement("""
                        UPDATE user_totp_credentials
                        SET revoked_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                        WHERE user_id = ? AND revoked_at IS NULL
                    """)
                    try {
                        revokeStmt.set(0, userId)
                        revokeStmt.update()
                    } finally {
                        revokeStmt.close()
                    }

                    let stmt = conn.prepareStatement("""
                        INSERT INTO user_totp_credentials (
                            user_id, name, secret_b32, secret_hash, digits, period_seconds, algorithm, issuer, verified_at
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                        RETURNING id
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, normalizeName(name))
                        stmt.set(2, encryptedSecret)
                        stmt.set(3, secretHash)
                        stmt.set(4, digits)
                        stmt.set(5, periodSeconds)
                        stmt.set(6, algorithm.trimAscii().toAsciiUpper())
                        stmt.set(7, issuer.trimAscii())
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let id = rs.getOrNull<Int64>(0) ?? 0
                                if (id > 0) {
                                    return Some(id)
                                }
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return None
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => ()
        }
        return None
    }

    public static func touchStep(credentialId: Int64, matchedStep: Int64): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE user_totp_credentials
                        SET last_used_step = ?, updated_at = CURRENT_TIMESTAMP
                        WHERE id = ? AND revoked_at IS NULL
                    """)
                    try {
                        stmt.set(0, matchedStep)
                        stmt.set(1, credentialId)
                        let updated = stmt.update()
                        return updated.rowCount > 0
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    public static func revoke(userId: Int64): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE user_totp_credentials
                        SET revoked_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                        WHERE user_id = ? AND revoked_at IS NULL
                    """)
                    try {
                        stmt.set(0, userId)
                        let updated = stmt.update()
                        return updated.rowCount > 0
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    public static func replaceRecoveryCodes(credentialId: Int64, codeHashes: Array<String>): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let deleteStmt = conn.prepareStatement("DELETE FROM user_totp_recovery_codes WHERE credential_id = ?")
                    try {
                        deleteStmt.set(0, credentialId)
                        deleteStmt.update()
                    } finally {
                        deleteStmt.close()
                    }

                    for (hash in codeHashes) {
                        let insertStmt = conn.prepareStatement("""
                            INSERT INTO user_totp_recovery_codes (credential_id, code_hash)
                            VALUES (?, ?)
                        """)
                        try {
                            insertStmt.set(0, credentialId)
                            insertStmt.set(1, hash)
                            insertStmt.update()
                        } finally {
                            insertStmt.close()
                        }
                    }
                    return true
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    public static func countUnusedRecoveryCodes(credentialId: Int64): Int64 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT COUNT(*)
                        FROM user_totp_recovery_codes
                        WHERE credential_id = ? AND used_at IS NULL
                    """)
                    try {
                        stmt.set(0, credentialId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<Int64>(0) ?? 0
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => ()
        }
        return 0
    }

    public static func consumeRecoveryCode(credentialId: Int64, codeHash: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE user_totp_recovery_codes
                        SET used_at = CURRENT_TIMESTAMP
                        WHERE credential_id = ? AND code_hash = ? AND used_at IS NULL
                    """)
                    try {
                        stmt.set(0, credentialId)
                        stmt.set(1, codeHash)
                        let updated = stmt.update()
                        return updated.rowCount > 0
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    private static func normalizeName(name: String): String {
        let trimmed = name.trimAscii()
        return if (trimmed.size > 0) { trimmed } else { "Authenticator App" }
    }

    private static func readCredential(rs: QueryResult): UserTotpCredentialRow {
        let row = UserTotpCredentialRow()
        row.id = rs.getOrNull<Int64>(0) ?? 0
        row.userId = rs.getOrNull<Int64>(1) ?? 0
        row.name = rs.getOrNull<String>(2) ?? ""
        row.encryptedSecret = rs.getOrNull<String>(3) ?? ""
        row.secretHash = rs.getOrNull<String>(4) ?? ""
        row.digits = rs.getOrNull<Int64>(5) ?? 6
        row.periodSeconds = rs.getOrNull<Int64>(6) ?? 30
        row.algorithm = rs.getOrNull<String>(7) ?? "SHA1"
        row.issuer = rs.getOrNull<String>(8) ?? "Lanlu"
        row.createdAt = rs.getOrNull<String>(9) ?? ""
        row.verifiedAt = rs.getOrNull<String>(10) ?? ""
        row.lastUsedStep = rs.getOrNull<Int64>(11) ?? -1
        row.revokedAt = rs.getOrNull<String>(12) ?? ""
        row.updatedAt = rs.getOrNull<String>(13) ?? ""
        return row
    }
}
