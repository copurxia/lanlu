package lrr4cj.migrations.versions

import std.database.sql.*
import lrr4cj.migrations.*
import lrr4cj.utils.*

/**
 * V006: Tag background image support (stored in assets, referenced by tags.background_asset_id).
 */
public class V006_TagBackgrounds <: Migration {
    private let logger = getLogger("migration_v006")

    public func version(): String {
        return "V006"
    }

    public func description(): String {
        return "Add background_asset_id to tags"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "tags")) {
            return true
        }
        MigrationHelpers.addColumnIfNotExists(conn, "tags", "background_asset_id", "BIGINT")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_tags_background_asset_id", "tags", "background_asset_id")
        logger.debug("tags.background_asset_id ensured")
        return true
    }
}

