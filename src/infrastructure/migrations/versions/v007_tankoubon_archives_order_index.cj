package lanlu.infrastructure.migrations.versions

import csorm.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

/**
 * V007: Add composite index for tankoubon order queries.
 */
public class V007_TankoubonArchivesOrderIndex <: Migration {
    private let logger = getLogger("migration_v007")

    public func version(): String { return "V007" }

    public func description(): String {
        return "Add composite index on tankoubon_archives(tankoubon_id, archive_id, sort_order)"
    }

    public func up(db: Database): Bool {
        if (!MigrationHelpers.tableExists(db, "tankoubon_archives")) {
            logger.warn("tankoubon_archives table missing; skipping V007")
            return true
        }

        let indexName = "idx_tankoubon_archives_tank_archive_order"
        if (MigrationHelpers.indexExists(db, indexName)) {
            logger.debug("Index ${indexName} already exists")
            return true
        }

        logger.info("Creating index ${indexName} on tankoubon_archives(tankoubon_id, archive_id, sort_order)")
        return MigrationHelpers.execUpdate(db,
            "CREATE INDEX ${indexName} ON tankoubon_archives (tankoubon_id, archive_id, sort_order)"
        )
    }
}
