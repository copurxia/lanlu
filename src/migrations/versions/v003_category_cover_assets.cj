package lanlu.migrations.versions

import std.database.sql.*
import lanlu.migrations.*
import lanlu.utils.*

/**
 * V003: Add category cover assets support.
 * - Adds `categories.cover_assets` column to store a JSON array of asset ids used as category "cover" mosaic.
 */
public class V003_CategoryCoverAssets <: Migration {
    private let logger = getLogger("migration_v003")

    public func version(): String {
        return "V003"
    }

    public func description(): String {
        return "Add categories.cover_assets column for category covers"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "categories")) {
            // If categories table doesn't exist yet, V001 should create it.
            logger.warn("categories table missing; skipping V003")
            return true
        }

        // Keep it idempotent.
        MigrationHelpers.addColumnIfNotExists(conn, "categories", "cover_assets", "TEXT DEFAULT '[]'")
        return true
    }
}

