package lanlu.infrastructure.migrations.versions

import ace_orm.{Driver, DbValue}
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

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

    public func up(drv: Driver): Bool {
        if (!MigrationHelpers.tableExists(drv, "tankoubons")) {
            logger.warn("tankoubons table missing; skipping V004")
            return true
        }

        MigrationHelpers.addColumnIfNotExists(drv, "tankoubons", "cover_asset_id", "BIGINT DEFAULT 0")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_tankoubons_cover_asset_id", "tankoubons", "cover_asset_id")
        return true
    }
}
