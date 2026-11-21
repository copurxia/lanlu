package lanlu.infrastructure.migrations.extensions

import csorm.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

/**
 * X013: Reconcile pg_trgm-backed indexes for the current schema state.
 */
public class X013_PgTrgmCurrentState <: ExtensionMigration {
    private let logger = getLogger("extension_migration_x013_pg_trgm_current_state")

    public func version(): String { return "X013TRGM" }

    public func description(): String {
        return "Reconcile pg_trgm indexes for schema V013"
    }

    public func requiredExtensions(): Array<String> {
        return ["pg_trgm"]
    }

    public func targetSchemaVersion(): String {
        return "V013"
    }

    public func up(db: Database): Bool {
        if (!MigrationHelpers.ensureExtensionInstalled("pg_trgm")) {
            logger.warn("pg_trgm not installed and auto-install failed")
            return false
        }

        if (!MigrationHelpers.tableExists(db, "tags")) {
            logger.warn("tags table missing; skipping X013 pg_trgm reconciliation")
            return true
        }

        let indexName = "idx_tags_translations_trgm"
        if (MigrationHelpers.indexExists(db, indexName)) {
            logger.debug("Index ${indexName} already exists")
        } else {
            logger.info("Creating trigram index ${indexName} on tags(translations::text)")
            if (!MigrationHelpers.execUpdate(db,
                "CREATE INDEX ${indexName} ON tags USING GIN ((translations::text) gin_trgm_ops)"
            )) {
                logger.warn("Failed to create trigram index; skipping")
                return true
            }
        }

        // tags.name ILIKE '%...%' acceleration
        let nameIndex = "idx_tags_name_trgm"
        if (MigrationHelpers.indexExists(db, nameIndex)) {
            logger.debug("Index ${nameIndex} already exists")
        } else {
            logger.info("Creating trigram index ${nameIndex} on tags(name)")
            if (!MigrationHelpers.execUpdate(db,
                "CREATE INDEX ${nameIndex} ON tags USING GIN (name gin_trgm_ops)"
            )) {
                logger.warn("Failed to create trigram index on tags.name; skipping")
                return true
            }
        }

        // archives title/filename/summary ILIKE '%...%' acceleration
        if (!MigrationHelpers.tableExists(db, "archives")) {
            logger.warn("archives table missing; skipping archive trigram indexes")
            return true
        }

        let titleIndex = "idx_archives_title_trgm"
        if (MigrationHelpers.indexExists(db, titleIndex)) {
            logger.info("Dropping legacy trigram index ${titleIndex}")
            if (!MigrationHelpers.execUpdate(db, "DROP INDEX IF EXISTS ${titleIndex}")) {
                logger.warn("Failed to drop legacy trigram index on archives.title; skipping")
                return true
            }
        }

        let filenameIndex = "idx_archives_filename_trgm"
        if (MigrationHelpers.indexExists(db, filenameIndex)) {
            logger.debug("Index ${filenameIndex} already exists")
        } else {
            logger.info("Creating trigram index ${filenameIndex} on archives(filename)")
            if (!MigrationHelpers.execUpdate(db,
                "CREATE INDEX ${filenameIndex} ON archives USING GIN (filename gin_trgm_ops)"
            )) {
                logger.warn("Failed to create trigram index on archives.filename; skipping")
                return true
            }
        }

        let summaryIndex = "idx_archives_summary_trgm"
        if (MigrationHelpers.indexExists(db, summaryIndex)) {
            logger.info("Dropping legacy trigram index ${summaryIndex}")
            if (!MigrationHelpers.execUpdate(db, "DROP INDEX IF EXISTS ${summaryIndex}")) {
                logger.warn("Failed to drop legacy trigram index on archives.summary; skipping")
                return true
            }
        }
        return true
    }

}
