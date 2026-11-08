package lanlu.contexts.user.infrastructure.persistence

import csorm.*
import std.collection.*
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
        let params: Array<Value> = [vint(userId)]
        let sql = """
            SELECT id, user_id, name, credential_id_b64url, algorithm, public_key_b64, sign_count, aaguid,
                   transports_json, user_verified, backup_eligible, backup_state, attestation_format,
                   created_at::text, COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, '')
            FROM user_webauthn_credentials
            WHERE user_id = $1 AND revoked_at IS NULL
            ORDER BY id DESC
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<UserWebauthnCredentialRow>(sql, params, { row => readRow(row) })
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

    public static func findActiveByCredentialId(credentialId: String): UserWebauthnCredentialRow {
        let params: Array<Value> = [vtext(credentialId.trimAscii())]
        let sql = """
            SELECT id, user_id, name, credential_id_b64url, algorithm, public_key_b64, sign_count, aaguid,
                   transports_json, user_verified, backup_eligible, backup_state, attestation_format,
                   created_at::text, COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, '')
            FROM user_webauthn_credentials
            WHERE credential_id_b64url = $1 AND revoked_at IS NULL
            LIMIT 1
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<UserWebauthnCredentialRow>(sql, params, { row => readRow(row) })
                    if (rows.size > 0) {
                        return rows[0]
                    }
                    return UserWebauthnCredentialRow()
                } catch (_: Exception) {
                    return UserWebauthnCredentialRow()
                }
            case None => ()
        }
        return UserWebauthnCredentialRow()
    }

    public static func create(userId: Int64, name: String, passkey: Passkey): Option<Int64> {
        let params: Array<Value> = [
            vint(userId),
            vtext(normalizeName(name)),
            vtext(passkey.credentialId),
            vtext(passkey.algorithm),
            vtext(passkey.publicKey),
            vint(passkey.counter),
            vtext(passkey.aaguid),
            vtext(toJsonStringArray(passkey.transports)),
            vbool(passkey.userVerified),
            vbool(passkey.backupEligible),
            vbool(passkey.backupState),
            vtext(passkey.attestationFormat)
        ]
        let sql = """
            INSERT INTO user_webauthn_credentials (
                user_id, name, credential_id_b64url, algorithm, public_key_b64, sign_count, aaguid,
                transports_json, user_verified, backup_eligible, backup_state, attestation_format
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
            RETURNING id
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let idOpt = db.rawOne<Int64>(sql, params, { r => r.getInt64(0) })
                    match (idOpt) {
                        case Some(insertedId) =>
                            if (insertedId > 0) {
                                return Some(insertedId)
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

    public static func touchAndUpdateCredential(
        userId: Int64,
        credentialId: String,
        signCount: Int64,
        backupEligible: Bool,
        backupState: Bool
    ): Bool {
        let params: Array<Value> = [
            vint(signCount),
            vbool(backupEligible),
            vbool(backupState),
            vint(userId),
            vtext(credentialId.trimAscii())
        ]
        let sql = """
            UPDATE user_webauthn_credentials
            SET sign_count = $1, backup_eligible = $2, backup_state = $3, last_used_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
            WHERE user_id = $4 AND credential_id_b64url = $5 AND revoked_at IS NULL
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

    public static func revoke(userId: Int64, id: Int64): Bool {
        let params: Array<Value> = [vint(id), vint(userId)]
        let sql = """
            UPDATE user_webauthn_credentials
            SET revoked_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
            WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL
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

    private static func readRow(row: Row): UserWebauthnCredentialRow {
        let r = UserWebauthnCredentialRow()
        r.id = row.getOrNullInt64(0) ?? 0
        r.userId = row.getOrNullInt64(1) ?? 0
        r.name = row.getOrNullText(2) ?? ""
        r.credentialIdB64Url = row.getOrNullText(3) ?? ""
        r.algorithm = row.getOrNullText(4) ?? "ES256"
        r.publicKeyB64 = row.getOrNullText(5) ?? ""
        r.signCount = row.getOrNullInt64(6) ?? 0
        r.aaguid = row.getOrNullText(7) ?? ""
        r.transportsJson = row.getOrNullText(8) ?? "[]"
        r.userVerified = row.getOrNullBool(9) ?? false
        r.backupEligible = row.getOrNullBool(10) ?? false
        r.backupState = row.getOrNullBool(11) ?? false
        r.attestationFormat = row.getOrNullText(12) ?? "none"
        r.createdAt = row.getOrNullText(13) ?? ""
        r.lastUsedAt = row.getOrNullText(14) ?? ""
        r.revokedAt = row.getOrNullText(15) ?? ""
        return r
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