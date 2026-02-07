package lanlu.migrations.versions

import std.database.sql.*
import lanlu.migrations.*
import lanlu.utils.*

/**
 * V006: Speed up translated tag search (tags.translations::text ILIKE '%...%')
 * by enabling pg_trgm and adding a trigram GIN index.
 */
public class V006_TagTranslationTrgmIndex <: Migration {
    private let logger = getLogger("migration_v006")

    public func version(): String { return "V006" }

    public func description(): String {
        return "Add pg_trgm + GIN trigram index for tags.translations::text"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "tags")) {
            logger.warn("tags table missing; skipping V006")
            return true
        }

        // Some databases disallow CREATE EXTENSION or have it disabled. When that happens,
        // the failing statement may abort the current transaction and prevent recording the
        // migration. Use a SAVEPOINT so we can safely continue and still mark the migration
        // as applied (best-effort optimization).
        MigrationHelpers.execUpdate(conn, "SAVEPOINT v006_pg_trgm")
        if (!MigrationHelpers.execUpdate(conn, "CREATE EXTENSION IF NOT EXISTS pg_trgm")) {
            MigrationHelpers.execUpdate(conn, "ROLLBACK TO SAVEPOINT v006_pg_trgm")
            MigrationHelpers.execUpdate(conn, "RELEASE SAVEPOINT v006_pg_trgm")
            logger.warn("Failed to enable pg_trgm; skipping trigram index creation")
            return true
        }
        MigrationHelpers.execUpdate(conn, "RELEASE SAVEPOINT v006_pg_trgm")

        let indexName = "idx_tags_translations_trgm"
        if (MigrationHelpers.indexExists(conn, indexName)) {
            logger.debug("Index ${indexName} already exists")
            return true
        }

        logger.info("Creating trigram index ${indexName} on tags(translations::text)")
        MigrationHelpers.execUpdate(conn, "SAVEPOINT v006_idx")
        if (!MigrationHelpers.execUpdate(conn,
            "CREATE INDEX ${indexName} ON tags USING GIN ((translations::text) gin_trgm_ops)"
        )) {
            MigrationHelpers.execUpdate(conn, "ROLLBACK TO SAVEPOINT v006_idx")
            MigrationHelpers.execUpdate(conn, "RELEASE SAVEPOINT v006_idx")
            logger.warn("Failed to create trigram index; skipping")
            return true
        }
        MigrationHelpers.execUpdate(conn, "RELEASE SAVEPOINT v006_idx")
        return true
    }
}
