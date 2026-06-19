package lanlu.infrastructure.migrations.versions

import std.database.sql.*
import lanlu.infrastructure.migrations.*

public class V026_AddSourceIdRegexToPlugins <: Migration {
    public func version(): String {
        return "V026"
    }

    public func description(): String {
        return "Add source_id_regex column to plugins table"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "plugins")) {
            return true
        }

        if (!MigrationHelpers.addColumnIfNotExists(conn, "plugins", "source_id_regex", "TEXT DEFAULT ''")) {
            return false
        }

        return true
    }
}
