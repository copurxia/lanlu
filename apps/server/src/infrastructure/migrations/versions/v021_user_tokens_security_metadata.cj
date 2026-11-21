package lanlu.infrastructure.migrations.versions

import csorm.*
import lanlu.infrastructure.migrations.*

public class V021_UserTokensSecurityMetadata <: Migration {
    public func version(): String {
        return "V021"
    }

    public func description(): String {
        return "Add security metadata columns to user tokens"
    }

    public func up(db: Database): Bool {
        if (!MigrationHelpers.tableExists(db, "user_tokens")) {
            return true
        }

        MigrationHelpers.addColumnIfNotExists(db, "user_tokens", "last_used_ip", "VARCHAR(64) NOT NULL DEFAULT ''")
        MigrationHelpers.addColumnIfNotExists(db, "user_tokens", "user_agent", "TEXT NOT NULL DEFAULT ''")
        MigrationHelpers.addColumnIfNotExists(db, "user_tokens", "expires_at", "TIMESTAMP")
        return true
    }
}
