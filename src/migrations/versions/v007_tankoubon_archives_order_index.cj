package lanlu.migrations.versions

import std.database.sql.*
import lanlu.migrations.*
import lanlu.utils.*

/**
 * V007: Add composite index for tankoubon order queries.
 */
public class V007_TankoubonArchivesOrderIndex <: Migration {
    private let logger = getLogger("migration_v007")

    public func version(): String { return "V007" }

    public func description(): String {
        return "Add composite index on tankoubon_archives(tankoubon_id, archive_id, sort_order)"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "tankoubon_archives")) {
            logger.warn("tankoubon_archives table missing; skipping V007")
            return true
        }

        let indexName = "idx_tankoubon_archives_tank_archive_order"
        if (MigrationHelpers.indexExists(conn, indexName)) {
            logger.debug("Index ${indexName} already exists")
            return true
        }

        logger.info("Creating index ${indexName} on tankoubon_archives(tankoubon_id, archive_id, sort_order)")
        return MigrationHelpers.execUpdate(conn,
            "CREATE INDEX ${indexName} ON tankoubon_archives (tankoubon_id, archive_id, sort_order)"
        )
    }
}
