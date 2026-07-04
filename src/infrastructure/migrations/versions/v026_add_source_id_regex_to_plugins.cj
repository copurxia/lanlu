package lanlu.infrastructure.migrations.versions

import ace_orm.{Driver, DbValue}
import lanlu.infrastructure.migrations.*

public class V026_AddSourceIdRegexToPlugins <: Migration {
    public func version(): String {
        return "V026"
    }

    public func description(): String {
        return "Add source_id_regex column to plugins table"
    }

    public func up(drv: Driver): Bool {
        if (!MigrationHelpers.tableExists(drv, "plugins")) {
            return true
        }

        if (!MigrationHelpers.addColumnIfNotExists(drv, "plugins", "source_id_regex", "TEXT DEFAULT ''")) {
            return false
        }

        return true
    }
}
