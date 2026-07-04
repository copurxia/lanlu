package lanlu.contexts.user.infrastructure.persistence

import std.collection.*
import ace_orm.*
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
        let out = ArrayList<UserWebauthnCredentialRow>()
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, user_id, name, credential_id_b64url, algorithm, public_key_b64, sign_count, aaguid,
                       transports_json, user_verified, backup_eligible, backup_state, attestation_format,
                       created_at::text, COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, '')
                FROM user_webauthn_credentials
                WHERE user_id = $1 AND revoked_at IS NULL
                ORDER BY id DESC
            """, [DbInt(userId)])
            for (r in rows) {
                out.add(readRow(r))
            }
        } catch (_: Exception) {
            ()
        }
        return out.toArray()
    }

    public static func findActiveByCredentialId(credentialId: String): UserWebauthnCredentialRow {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, user_id, name, credential_id_b64url, algorithm, public_key_b64, sign_count, aaguid,
                       transports_json, user_verified, backup_eligible, backup_state, attestation_format,
                       created_at::text, COALESCE(last_used_at::text, ''), COALESCE(revoked_at::text, '')
                FROM user_webauthn_credentials
                WHERE credential_id_b64url = $1 AND revoked_at IS NULL
                LIMIT 1
            """, [DbText(credentialId.trimAscii())])
            if (rows.size > 0) {
                return readRow(rows[0])
            }
        } catch (_: Exception) {
            return UserWebauthnCredentialRow()
        }
        return UserWebauthnCredentialRow()
    }

    public static func create(userId: Int64, name: String, passkey: Passkey): Option<Int64> {
        try {
            let rows = DatabaseConfig.driver().query("""
                INSERT INTO user_webauthn_credentials (
                    user_id, name, credential_id_b64url, algorithm, public_key_b64, sign_count, aaguid,
                    transports_json, user_verified, backup_eligible, backup_state, attestation_format
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
                RETURNING id
            """, [DbInt(userId), DbText(normalizeName(name)), DbText(passkey.credentialId), DbText(passkey.algorithm),
                  DbText(passkey.publicKey), DbInt(passkey.counter), DbText(passkey.aaguid), DbText(toJsonStringArray(passkey.transports)),
                  DbBool(passkey.userVerified), DbBool(passkey.backupEligible), DbBool(passkey.backupState), DbText(passkey.attestationFormat)])
            if (rows.size > 0) {
                let insertedId = rows[0].getInt("id")
                if (insertedId > 0) {
                    return Some(insertedId)
                }
            }
        } catch (_: Exception) {
            return None
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
        try {
            let affected = DatabaseConfig.driver().exec("""
                UPDATE user_webauthn_credentials
                SET sign_count = $1, backup_eligible = $2, backup_state = $3, last_used_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                WHERE user_id = $4 AND credential_id_b64url = $5 AND revoked_at IS NULL
            """, [DbInt(signCount), DbBool(backupEligible), DbBool(backupState), DbInt(userId), DbText(credentialId.trimAscii())])
            return affected > 0
        } catch (_: Exception) {
            return false
        }
    }

    public static func revoke(userId: Int64, id: Int64): Bool {
        try {
            let affected = DatabaseConfig.driver().exec("""
                UPDATE user_webauthn_credentials
                SET revoked_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL
            """, [DbInt(id), DbInt(userId)])
            return affected > 0
        } catch (_: Exception) {
            return false
        }
    }

    private static func readRow(r: Row): UserWebauthnCredentialRow {
        let row = UserWebauthnCredentialRow()
        row.id = r.getInt("id")
        row.userId = r.getInt("user_id")
        row.name = r.getText("name")
        row.credentialIdB64Url = r.getText("credential_id_b64url")
        row.algorithm = r.getText("algorithm")
        row.publicKeyB64 = r.getText("public_key_b64")
        row.signCount = r.getInt("sign_count")
        row.aaguid = r.getText("aaguid")
        row.transportsJson = r.getText("transports_json")
        row.userVerified = r.getBool("user_verified")
        row.backupEligible = r.getBool("backup_eligible")
        row.backupState = r.getBool("backup_state")
        row.attestationFormat = r.getText("attestation_format")
        row.createdAt = r.getText("created_at")
        row.lastUsedAt = r.getText("last_used_at")
        row.revokedAt = r.getText("revoked_at")
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