package lanlu.infrastructure.migrations.versions

import std.database.sql.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

public class V020_UserTotpCredentials <: Migration {
    private let logger = getLogger("migration_v020")

    public func version(): String {
        return "V020"
    }

    public func description(): String {
        return "Create user totp credentials and recovery codes tables"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.createTableIfNotExists(conn, "user_totp_credentials", """
            CREATE TABLE user_totp_credentials (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL,
                name VARCHAR(255) NOT NULL DEFAULT '',
                secret_b32 TEXT NOT NULL,
                secret_hash VARCHAR(128) NOT NULL DEFAULT '',
                digits INTEGER NOT NULL DEFAULT 6,
                period_seconds INTEGER NOT NULL DEFAULT 30,
                algorithm VARCHAR(16) NOT NULL DEFAULT 'SHA1',
                issuer VARCHAR(255) NOT NULL DEFAULT 'Lanlu',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                verified_at TIMESTAMP,
                last_used_step BIGINT NOT NULL DEFAULT -1,
                revoked_at TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        """)) {
            return false
        }

        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_credentials", "name", "VARCHAR(255) NOT NULL DEFAULT ''")
        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_credentials", "secret_b32", "TEXT NOT NULL DEFAULT ''")
        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_credentials", "secret_hash", "VARCHAR(128) NOT NULL DEFAULT ''")
        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_credentials", "digits", "INTEGER NOT NULL DEFAULT 6")
        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_credentials", "period_seconds", "INTEGER NOT NULL DEFAULT 30")
        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_credentials", "algorithm", "VARCHAR(16) NOT NULL DEFAULT 'SHA1'")
        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_credentials", "issuer", "VARCHAR(255) NOT NULL DEFAULT 'Lanlu'")
        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_credentials", "created_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_credentials", "verified_at", "TIMESTAMP")
        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_credentials", "last_used_step", "BIGINT NOT NULL DEFAULT -1")
        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_credentials", "revoked_at", "TIMESTAMP")
        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_credentials", "updated_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_totp_credentials_user_id", "user_totp_credentials", "user_id")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_totp_credentials_secret_hash", "user_totp_credentials", "secret_hash")
        let _ = MigrationHelpers.execUpdate(
            conn,
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_user_totp_credentials_active_user ON user_totp_credentials (user_id) WHERE revoked_at IS NULL"
        )

        if (!MigrationHelpers.createTableIfNotExists(conn, "user_totp_recovery_codes", """
            CREATE TABLE user_totp_recovery_codes (
                id SERIAL PRIMARY KEY,
                credential_id INTEGER NOT NULL,
                code_hash VARCHAR(128) NOT NULL,
                used_at TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (credential_id) REFERENCES user_totp_credentials(id) ON DELETE CASCADE
            )
        """)) {
            return false
        }
        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_recovery_codes", "credential_id", "INTEGER NOT NULL DEFAULT 0")
        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_recovery_codes", "code_hash", "VARCHAR(128) NOT NULL DEFAULT ''")
        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_recovery_codes", "used_at", "TIMESTAMP")
        MigrationHelpers.addColumnIfNotExists(conn, "user_totp_recovery_codes", "created_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_totp_recovery_codes_credential_id", "user_totp_recovery_codes", "credential_id")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_totp_recovery_codes_code_hash", "user_totp_recovery_codes", "code_hash")

        logger.debug("user_totp credentials tables ready")
        return true
    }
}
