package lanlu.infrastructure.migrations.versions

import std.database.sql.*
import lanlu.infrastructure.migrations.*

public class V022_UserPasswordHashArgon2id <: Migration {
    public func version(): String {
        return "022"
    }

    public func description(): String {
        return "Add password hash versioning and expand user password hash storage for Argon2id"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "users")) {
            return true
        }

        if (!MigrationHelpers.execUpdate(conn, "ALTER TABLE users ALTER COLUMN password_hash TYPE TEXT")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(conn, "users", "password_hash_version", "VARCHAR(32) NOT NULL DEFAULT 'sha256_v1'")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(conn, "UPDATE users SET password_hash_version = 'sha256_v1' WHERE COALESCE(TRIM(password_hash_version), '') = ''")) {
            return false
        }
        return true
    }
}
