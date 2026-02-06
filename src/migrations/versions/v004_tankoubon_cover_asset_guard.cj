package lanlu.migrations.versions

import std.database.sql.*
import lanlu.migrations.*
import lanlu.utils.*

/**
 * V004: Ensure Tankoubon cover column exists for all deployments.
 * Some old databases may predate V002 migration execution.
 */
public class V004_TankoubonCoverAssetGuard <: Migration {
    private let logger = getLogger("migration_v004")

    public func version(): String { return "V004" }

    public func description(): String {
        return "Ensure tankoubons.cover_asset_id exists and is indexed"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "tankoubons")) {
            logger.warn("tankoubons table missing; skipping V004")
            return true
        }

        MigrationHelpers.addColumnIfNotExists(conn, "tankoubons", "cover_asset_id", "BIGINT DEFAULT 0")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubons_cover_asset_id", "tankoubons", "cover_asset_id")
        return true
    }
}
