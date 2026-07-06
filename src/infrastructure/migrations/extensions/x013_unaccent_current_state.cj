package lanlu.infrastructure.migrations.extensions

import csorm.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

/**
 * X013: Reconcile unaccent-backed indexes for the current schema state.
 */
public class X013_UnaccentCurrentState <: ExtensionMigration {
    private let logger = getLogger("extension_migration_x013_unaccent_current_state")

    public func version(): String { return "X013UACC" }

    public func description(): String {
        return "Reconcile unaccent indexes for schema V013"
    }

    public func requiredExtensions(): Array<String> {
        return ["unaccent", "pg_trgm"]
    }

    public func targetSchemaVersion(): String {
        return "V013"
    }

    public func up(db: Database): Bool {
        if (!MigrationHelpers.ensureExtensionInstalled("unaccent")) {
            logger.warn("unaccent not installed and auto-install failed")
            return false
        }
        if (!MigrationHelpers.ensureExtensionInstalled("pg_trgm")) {
            logger.warn("pg_trgm not installed and auto-install failed")
            return false
        }

        if (!MigrationHelpers.execUpdate(db, """
            CREATE OR REPLACE FUNCTION lanlu_immutable_unaccent(input TEXT)
            RETURNS TEXT
            LANGUAGE SQL
            IMMUTABLE
            PARALLEL SAFE
            AS $$
                SELECT unaccent('unaccent', input)
            $$        
        """)) {
            logger.warn("Failed to create immutable unaccent wrapper")
            return false
        }

        if (MigrationHelpers.tableExists(db, "tags")) {
            let nameIndex = "idx_tags_name_unaccent_trgm"
            if (!MigrationHelpers.indexExists(db, nameIndex)) {
                logger.info("Creating trigram index ${nameIndex} on lanlu_immutable_unaccent(tags.name)")
                if (!MigrationHelpers.execUpdate(db,
                    "CREATE INDEX ${nameIndex} ON tags USING GIN ((lanlu_immutable_unaccent(name)) gin_trgm_ops)"
                )) {
                    logger.warn("Failed to create trigram index on lanlu_immutable_unaccent(tags.name); skipping")
                }
            }

            let translationsIndex = "idx_tags_translations_unaccent_trgm"
            if (!MigrationHelpers.indexExists(db, translationsIndex)) {
                logger.info("Creating trigram index ${translationsIndex} on lanlu_immutable_unaccent(tags.translations::text)")
                if (!MigrationHelpers.execUpdate(db,
                    "CREATE INDEX ${translationsIndex} ON tags USING GIN ((lanlu_immutable_unaccent(translations::text)) gin_trgm_ops)"
                )) {
                    logger.warn("Failed to create trigram index on lanlu_immutable_unaccent(tags.translations::text); skipping")
                }
            }
        }

        if (MigrationHelpers.tableExists(db, "archives")) {
            let filenameIndex = "idx_archives_filename_unaccent_trgm"
            if (!MigrationHelpers.indexExists(db, filenameIndex)) {
                logger.info("Creating trigram index ${filenameIndex} on lanlu_immutable_unaccent(archives.filename)")
                if (!MigrationHelpers.execUpdate(db,
                    "CREATE INDEX ${filenameIndex} ON archives USING GIN ((lanlu_immutable_unaccent(filename)) gin_trgm_ops)"
                )) {
                    logger.warn("Failed to create trigram index on lanlu_immutable_unaccent(archives.filename); skipping")
                }
            }
        }

        return true
    }
}
