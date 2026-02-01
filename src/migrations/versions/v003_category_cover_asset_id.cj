package lanlu.migrations.versions

import std.database.sql.*
import lanlu.migrations.*
import lanlu.utils.*

/**
 * V003: Category cover image support.
 * Adds `categories.cover_asset_id` to store the generated cover image asset id.
 */
public class V003_CategoryCoverAssetId <: Migration {
    private let logger = getLogger("migration_v003")

    public func version(): String { return "V003" }

    public func description(): String {
        return "Add categories.cover_asset_id column for category cover image"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "categories")) {
            logger.warn("categories table missing; skipping V003")
            return true
        }

        MigrationHelpers.addColumnIfNotExists(conn, "categories", "cover_asset_id", "BIGINT DEFAULT 0")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_categories_cover_asset_id", "categories", "cover_asset_id")
        return true
    }
}

