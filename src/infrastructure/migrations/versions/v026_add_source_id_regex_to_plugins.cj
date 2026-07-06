package lanlu.infrastructure.migrations.versions

import csorm.*
import lanlu.infrastructure.migrations.*

public class V026_AddSourceIdRegexToPlugins <: Migration {
    public func version(): String {
        return "V026"
    }

    public func description(): String {
        return "Add source_id_regex column to plugins table"
    }

    public func up(db: Database): Bool {
        if (!MigrationHelpers.tableExists(db, "plugins")) {
            return true
        }

        if (!MigrationHelpers.addColumnIfNotExists(db, "plugins", "source_id_regex", "TEXT DEFAULT ''")) {
            return false
        }

        return true
    }
}
