package lanlu.infrastructure.migrations.versions

import std.database.sql.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

public class V019_UserWebauthnCredentials <: Migration {
    private let logger = getLogger("migration_v019")

    public func version(): String {
        return "V019"
    }

    public func description(): String {
        return "Create user webauthn credentials table"
    }

    public func up(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "user_webauthn_credentials")) {
            logger.debug("user_webauthn_credentials already exists, checking columns")
            MigrationHelpers.addColumnIfNotExists(conn, "user_webauthn_credentials", "name", "VARCHAR(255) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(conn, "user_webauthn_credentials", "algorithm", "VARCHAR(32) NOT NULL DEFAULT 'ES256'")
            MigrationHelpers.addColumnIfNotExists(conn, "user_webauthn_credentials", "public_key_b64", "TEXT NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(conn, "user_webauthn_credentials", "sign_count", "BIGINT NOT NULL DEFAULT 0")
            MigrationHelpers.addColumnIfNotExists(conn, "user_webauthn_credentials", "aaguid", "VARCHAR(64) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(conn, "user_webauthn_credentials", "transports_json", "TEXT NOT NULL DEFAULT '[]'")
            MigrationHelpers.addColumnIfNotExists(conn, "user_webauthn_credentials", "user_verified", "BOOLEAN NOT NULL DEFAULT false")
            MigrationHelpers.addColumnIfNotExists(conn, "user_webauthn_credentials", "backup_eligible", "BOOLEAN NOT NULL DEFAULT false")
            MigrationHelpers.addColumnIfNotExists(conn, "user_webauthn_credentials", "backup_state", "BOOLEAN NOT NULL DEFAULT false")
            MigrationHelpers.addColumnIfNotExists(conn, "user_webauthn_credentials", "attestation_format", "VARCHAR(64) NOT NULL DEFAULT 'none'")
            MigrationHelpers.addColumnIfNotExists(conn, "user_webauthn_credentials", "last_used_at", "TIMESTAMP")
            MigrationHelpers.addColumnIfNotExists(conn, "user_webauthn_credentials", "revoked_at", "TIMESTAMP")
            MigrationHelpers.addColumnIfNotExists(conn, "user_webauthn_credentials", "created_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
            MigrationHelpers.addColumnIfNotExists(conn, "user_webauthn_credentials", "updated_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_user_webauthn_credentials_user_id", "user_webauthn_credentials", "user_id")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_user_webauthn_credentials_credential_id", "user_webauthn_credentials", "credential_id_b64url")
            return true
        }

        logger.debug("Creating user_webauthn_credentials table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE user_webauthn_credentials (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL,
                name VARCHAR(255) NOT NULL DEFAULT '',
                credential_id_b64url TEXT NOT NULL UNIQUE,
                algorithm VARCHAR(32) NOT NULL DEFAULT 'ES256',
                public_key_b64 TEXT NOT NULL DEFAULT '',
                sign_count BIGINT NOT NULL DEFAULT 0,
                aaguid VARCHAR(64) NOT NULL DEFAULT '',
                transports_json TEXT NOT NULL DEFAULT '[]',
                user_verified BOOLEAN NOT NULL DEFAULT false,
                backup_eligible BOOLEAN NOT NULL DEFAULT false,
                backup_state BOOLEAN NOT NULL DEFAULT false,
                attestation_format VARCHAR(64) NOT NULL DEFAULT 'none',
                last_used_at TIMESTAMP,
                revoked_at TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        """)) {
            return false
        }

        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_webauthn_credentials_user_id", "user_webauthn_credentials", "user_id")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_webauthn_credentials_credential_id", "user_webauthn_credentials", "credential_id_b64url")
        return true
    }
}
