package lanlu.infrastructure.migrations.versions

import csorm.*
import lanlu.infrastructure.migrations.*

public class V022_UserPasswordHashArgon2id <: Migration {
    public func version(): String {
        return "V022"
    }

    public func description(): String {
        return "Add password hash versioning and expand user password hash storage for Argon2id"
    }

    public func up(db: Database): Bool {
        if (!MigrationHelpers.tableExists(db, "users")) {
            return true
        }

        if (!MigrationHelpers.execUpdate(db, "ALTER TABLE users ALTER COLUMN password_hash TYPE TEXT")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(db, "users", "password_hash_version", "VARCHAR(32) NOT NULL DEFAULT 'sha256_v1'")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "UPDATE users SET password_hash_version = 'sha256_v1' WHERE COALESCE(TRIM(password_hash_version), '') = ''")) {
            return false
        }
        return true
    }
}
