package lanlu.infrastructure.migrations.versions

import std.database.sql.*
import lanlu.infrastructure.migrations.*

public class V021_UserTokensSecurityMetadata <: Migration {
    public func version(): String {
        return "021"
    }

    public func description(): String {
        return "Add security metadata columns to user tokens"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "user_tokens")) {
            return true
        }

        MigrationHelpers.addColumnIfNotExists(conn, "user_tokens", "last_used_ip", "VARCHAR(64) NOT NULL DEFAULT ''")
        MigrationHelpers.addColumnIfNotExists(conn, "user_tokens", "user_agent", "TEXT NOT NULL DEFAULT ''")
        MigrationHelpers.addColumnIfNotExists(conn, "user_tokens", "expires_at", "TIMESTAMP")
        return true
    }
}
