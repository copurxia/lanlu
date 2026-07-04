package lanlu.infrastructure.migrations.versions

import ace_orm.{Driver, DbValue}
import lanlu.infrastructure.migrations.*

public class V021_UserTokensSecurityMetadata <: Migration {
    public func version(): String {
        return "V021"
    }

    public func description(): String {
        return "Add security metadata columns to user tokens"
    }

    public func up(drv: Driver): Bool {
        if (!MigrationHelpers.tableExists(drv, "user_tokens")) {
            return true
        }

        MigrationHelpers.addColumnIfNotExists(drv, "user_tokens", "last_used_ip", "VARCHAR(64) NOT NULL DEFAULT ''")
        MigrationHelpers.addColumnIfNotExists(drv, "user_tokens", "user_agent", "TEXT NOT NULL DEFAULT ''")
        MigrationHelpers.addColumnIfNotExists(drv, "user_tokens", "expires_at", "TIMESTAMP")
        return true
    }
}
