package lanlu.contexts.user.infrastructure.persistence

import std.collection.*
import std.database.sql.*
import std.io.{ByteBuffer, readToEnd}
import lanlu.shared.config.*
import stdx.encoding.json.stream.*
import webauthn_cj.*

public class UserWebauthnCredentialRow {
    public var id: Int64 = 0
    public var userId: Int64 = 0
    public var name: String = ""
    public var credentialIdB64Url: String = ""
    public var algorithm: String = "ES256"
    public var publicKeyB64: String = ""
    public var signCount: Int64 = 0
    public var aaguid: String = ""
    public var transportsJson: String = "[]"
    public var userVerified: Bool = false
    public var backupEligible: Bool = false
    public var backupState: Bool = false
    public var attestationFormat: String = "none"
    public var createdAt: String = ""
    public var lastUsedAt: String = ""
    public var revokedAt: String = ""

    public init() {}

    public func toPasskey(): Passkey {
        return Passkey(
            credentialIdB64Url,
            algorithm,
            publicKeyB64,
            signCount,
            transports: parseJsonStringArrayPayload(transportsJson),
            userVerified: userVerified,
            backupEligible: backupEligible,
            backupState: backupState,
            aaguid: aaguid,
            attestationFormat: attestationFormat
        )
    }
}

public class UserWebauthnCredentialDao {
    public static func listActiveByUser(userId: Int64): Array<UserWebauthnCredentialRow> {
        var out = ArrayList<UserWebauthnCredentialRow>()
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, user_id, name, credential_id_b64url, algorithm, public_key_b64, sign_count, aaguid,
                               transports_json, user_verified, backup_eligible, backup_state, attestation_format,
                               created_at::text, COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, '')
                        FROM user_webauthn_credentials
                        WHERE user_id = ? AND revoked_at IS NULL
                        ORDER BY id DESC
                    """)
                    try {
                        stmt.set(0, userId)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                out.add(readRow(rs))
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

    public static func findActiveByCredentialId(credentialId: String): UserWebauthnCredentialRow {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT id, user_id, name, credential_id_b64url, algorithm, public_key_b64, sign_count, aaguid,
                               transports_json, user_verified, backup_eligible, backup_state, attestation_format,
                               created_at::text, COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, '')
                        FROM user_webauthn_credentials
                        WHERE credential_id_b64url = ? AND revoked_at IS NULL
                        LIMIT 1
                    """)
                    try {
                        stmt.set(0, credentialId.trimAscii())
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return readRow(rs)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return UserWebauthnCredentialRow()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => ()
        }
        return UserWebauthnCredentialRow()
    }

    public static func create(userId: Int64, name: String, passkey: Passkey): Option<Int64> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO user_webauthn_credentials (
                            user_id, name, credential_id_b64url, algorithm, public_key_b64, sign_count, aaguid,
                            transports_json, user_verified, backup_eligible, backup_state, attestation_format
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        RETURNING id
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, normalizeName(name))
                        stmt.set(2, passkey.credentialId)
                        stmt.set(3, passkey.algorithm)
                        stmt.set(4, passkey.publicKey)
                        stmt.set(5, passkey.counter)
                        stmt.set(6, passkey.aaguid)
                        stmt.set(7, toJsonStringArray(passkey.transports))
                        stmt.set(8, passkey.userVerified)
                        stmt.set(9, passkey.backupEligible)
                        stmt.set(10, passkey.backupState)
                        stmt.set(11, passkey.attestationFormat)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let insertedId = rs.getOrNull<Int64>(0) ?? 0
                                if (insertedId > 0) {
                                    return Some(insertedId)
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

    public static func touchAndUpdateCredential(
        userId: Int64,
        credentialId: String,
        signCount: Int64,
        backupEligible: Bool,
        backupState: Bool
    ): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE user_webauthn_credentials
                        SET sign_count = ?, backup_eligible = ?, backup_state = ?, last_used_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                        WHERE user_id = ? AND credential_id_b64url = ? AND revoked_at IS NULL
                    """)
                    try {
                        stmt.set(0, signCount)
                        stmt.set(1, backupEligible)
                        stmt.set(2, backupState)
                        stmt.set(3, userId)
                        stmt.set(4, credentialId.trimAscii())
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

    public static func revoke(userId: Int64, id: Int64): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        UPDATE user_webauthn_credentials
                        SET revoked_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                        WHERE id = ? AND user_id = ? AND revoked_at IS NULL
                    """)
                    try {
                        stmt.set(0, id)
                        stmt.set(1, userId)
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

    private static func readRow(rs: QueryResult): UserWebauthnCredentialRow {
        let row = UserWebauthnCredentialRow()
        row.id = rs.getOrNull<Int64>(0) ?? 0
        row.userId = rs.getOrNull<Int64>(1) ?? 0
        row.name = rs.getOrNull<String>(2) ?? ""
        row.credentialIdB64Url = rs.getOrNull<String>(3) ?? ""
        row.algorithm = rs.getOrNull<String>(4) ?? "ES256"
        row.publicKeyB64 = rs.getOrNull<String>(5) ?? ""
        row.signCount = rs.getOrNull<Int64>(6) ?? 0
        row.aaguid = rs.getOrNull<String>(7) ?? ""
        row.transportsJson = rs.getOrNull<String>(8) ?? "[]"
        row.userVerified = rs.getOrNull<Bool>(9) ?? false
        row.backupEligible = rs.getOrNull<Bool>(10) ?? false
        row.backupState = rs.getOrNull<Bool>(11) ?? false
        row.attestationFormat = rs.getOrNull<String>(12) ?? "none"
        row.createdAt = rs.getOrNull<String>(13) ?? ""
        row.lastUsedAt = rs.getOrNull<String>(14) ?? ""
        row.revokedAt = rs.getOrNull<String>(15) ?? ""
        return row
    }

    private static func normalizeName(name: String): String {
        let trimmed = name.trimAscii()
        return if (trimmed.size > 0) { trimmed } else { "Passkey" }
    }

    private static func toJsonStringArray(values: Array<String>): String {
        if (values.size == 0) {
            return "[]"
        }
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startArray()
        for (value in values) {
            w.writeValue(value)
        }
        w.endArray()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

}

private func parseJsonStringArrayPayload(payload: String): Array<String> {
    let trimmed = payload.trimAscii()
    if (trimmed.size == 0) {
        return Array<String>()
    }
    try {
        let reader = JsonReader(ByteBuffer(trimmed.toArray()))
        if (reader.peek() != Some(BeginArray)) {
            return Array<String>()
        }
        let out = ArrayList<String>()
        reader.startArray()
        while (reader.peek() != EndArray) {
            out.add(reader.readValue<String>())
        }
        reader.endArray()
        return out.toArray()
    } catch (_: Exception) {
        return Array<String>()
    }
}
