package lrr4cj.migrations.versions

import std.database.sql.*
import lrr4cj.migrations.*
import lrr4cj.utils.*

/**
 * V005: Tag icon support (stored in assets, referenced by tags.icon_asset_id).
 */
public class V005_TagIcons <: Migration {
    private let logger = getLogger("migration_v005")

    public func version(): String {
        return "V005"
    }

    public func description(): String {
        return "Add icon_asset_id to tags"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "tags")) {
            return true
        }
        MigrationHelpers.addColumnIfNotExists(conn, "tags", "icon_asset_id", "BIGINT")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_tags_icon_asset_id", "tags", "icon_asset_id")
        logger.debug("tags.icon_asset_id ensured")
        return true
    }
}

