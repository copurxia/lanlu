package lanlu.migrations.versions

import std.database.sql.*
import lanlu.migrations.*
import lanlu.utils.*

/**
 * V005: Add cover_asset_id to archives_with_tags view.
 */
public class V005_ArchivesWithTagsCoverAsset <: Migration {
    private let logger = getLogger("migration_v005")

    public func version(): String { return "V005" }

    public func description(): String {
        return "Update archives_with_tags view to include cover_asset_id"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.viewExists(conn, "archives_with_tags")) {
            logger.warn("archives_with_tags view missing; skipping V005")
            return true
        }

        logger.info("Recreating archives_with_tags view with cover_asset_id")
        MigrationHelpers.execUpdate(conn, "DROP VIEW archives_with_tags")
        return MigrationHelpers.execUpdate(conn, """
            CREATE VIEW archives_with_tags AS
            SELECT
                a.id,
                a.arcid,
                a.filename,
                a.title,
                a.summary,
                a.thumbhash,
                a.cover_asset_id,
                a.created_at,
                a.updated_at,
                a.relative_path,
                a.file_size,
                a.pagecount,
                a.archive_type,
                a.category_id,
                COALESCE(string_agg(
                    CASE WHEN t.namespace != '' AND t.namespace IS NOT NULL
                         THEN t.namespace || ':' || t.name
                         ELSE t.name
                    END, ',' ORDER BY t.namespace, t.name), '') AS tags,
                a.title_tsv ||
                    setweight(to_tsvector('simple', COALESCE(string_agg(
                        CASE WHEN t.namespace != '' AND t.namespace IS NOT NULL
                             THEN t.namespace || ' ' || t.name
                             ELSE t.name
                        END, ' '), '')), 'C') AS search_tsv
            FROM archives a
            LEFT JOIN archive_tags atg ON atg.archive_id = a.id
            LEFT JOIN tags t ON t.id = atg.tag_id
            GROUP BY
                a.id, a.arcid, a.filename, a.title, a.summary, a.thumbhash, a.cover_asset_id,
                a.created_at, a.updated_at, a.relative_path, a.file_size,
                a.pagecount, a.archive_type, a.category_id, a.title_tsv
        """)
    }
}
