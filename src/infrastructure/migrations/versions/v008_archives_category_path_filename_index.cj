package lanlu.infrastructure.migrations.versions

import std.database.sql.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

/**
 * V008: Accelerate archive existence lookup during scan.
 */
public class V008_ArchivesCategoryPathFilenameIndex <: Migration {
    private let logger = getLogger("migration_v008")

    public func version(): String { return "V008" }

    public func description(): String {
        return "Add composite index on archives(category_id, relative_path, filename)"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "archives")) {
            logger.warn("archives table missing; skipping V008")
            return true
        }

        let indexName = "idx_archives_category_relpath_filename"
        if (MigrationHelpers.indexExists(conn, indexName)) {
            logger.debug("Index ${indexName} already exists")
            return true
        }

        logger.info("Creating index ${indexName} on archives(category_id, relative_path, filename)")
        return MigrationHelpers.execUpdate(
            conn,
            "CREATE INDEX ${indexName} ON archives (category_id, relative_path, filename)"
        )
    }
}
