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

        // Avoid CREATE EXTENSION here; some drivers/DBs error on it and poison the connection.
        // If pg_trgm isn't already installed, skip index creation (best-effort optimization).
        if (!isExtensionInstalled(conn, "pg_trgm")) {
            logger.warn("pg_trgm not installed; skipping trigram index creation")
            return true
        }

        let indexName = "idx_tags_translations_trgm"
        if (MigrationHelpers.indexExists(conn, indexName)) {
            logger.debug("Index ${indexName} already exists")
            return true
        }

        logger.info("Creating trigram index ${indexName} on tags(translations::text)")
        if (!MigrationHelpers.execUpdate(conn,
            "CREATE INDEX ${indexName} ON tags USING GIN ((translations::text) gin_trgm_ops)"
        )) {
            logger.warn("Failed to create trigram index; skipping")
            return true
        }
        return true
    }

    private func isExtensionInstalled(conn: Connection, name: String): Bool {
        try {
            let stmt = conn.prepareStatement(
                "SELECT 1 FROM pg_extension WHERE extname = ? LIMIT 1"
            )
            try {
                stmt.set(0, name)
                let rs = stmt.query()
                try {
                    return rs.next()
                } finally {
                    rs.close()
                }
            } finally {
                stmt.close()
            }
        } catch (e: Exception) {
            logger.warn("Failed to query pg_extension", ("error", e.message))
            return false
        }
    }
}
