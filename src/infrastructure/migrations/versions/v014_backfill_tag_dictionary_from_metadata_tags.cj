package lanlu.infrastructure.migrations.versions

import std.database.sql.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

/**
 * V014: Backfill tags dictionary entries from canonical metadata_tags.
 */
public class V014_BackfillTagDictionaryFromMetadataTags <: Migration {
    private let logger = getLogger("migration_v014")

    public func version(): String {
        return "V014"
    }

    public func description(): String {
        return "Backfill tags table from metadata_tags canonical relations"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "tags")) {
            logger.warn("tags table missing; skipping V014")
            return true
        }
        if (!MigrationHelpers.tableExists(conn, "metadata_tags")) {
            logger.warn("metadata_tags table missing; skipping V014")
            return true
        }

        if (!MigrationHelpers.execUpdate(conn, """
            WITH normalized AS (
                SELECT DISTINCT
                    CASE
                        WHEN position(':' IN btrim(tag)) > 0
                            THEN btrim(substring(btrim(tag) FROM 1 FOR position(':' IN btrim(tag)) - 1))
                        ELSE ''
                    END AS namespace,
                    CASE
                        WHEN position(':' IN btrim(tag)) > 0
                            THEN btrim(substring(btrim(tag) FROM position(':' IN btrim(tag)) + 1))
                        ELSE btrim(tag)
                    END AS name
                FROM metadata_tags
                WHERE btrim(tag) <> ''
            )
            INSERT INTO tags (namespace, name)
            SELECT namespace, name
            FROM normalized
            WHERE name <> ''
            ON CONFLICT (namespace, name) DO UPDATE
            SET updated_at = CURRENT_TIMESTAMP
        """)) {
            return false
        }

        logger.info("V014 migration applied")
        return true
    }
}
