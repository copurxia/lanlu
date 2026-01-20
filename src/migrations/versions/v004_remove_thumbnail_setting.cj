package lrr4cj.migrations.versions

import std.database.sql.*
import lrr4cj.migrations.*
import lrr4cj.utils.*

/**
 * V004: Remove legacy THUMBNAIL_PATH system setting (thumbnails are stored in assets now).
 */
public class V004_RemoveThumbnailSetting <: Migration {
    private let logger = getLogger("migration_v004")

    public func version(): String {
        return "V004"
    }

    public func description(): String {
        return "Remove THUMBNAIL_PATH system setting"
    }

    public func up(conn: Connection): Bool {
        // system_settings table is created in V001; keep this migration resilient anyway.
        if (!MigrationHelpers.tableExists(conn, "system_settings")) {
            return true
        }

        try {
            let _ = MigrationHelpers.execUpdate(conn, "DELETE FROM system_settings WHERE key = 'THUMBNAIL_PATH'")
            logger.debug("Deleted THUMBNAIL_PATH from system_settings")
        } catch (e: Exception) {
            logger.warn("Failed to delete THUMBNAIL_PATH setting", ("error", e.message))
        }
        return true
    }
}

