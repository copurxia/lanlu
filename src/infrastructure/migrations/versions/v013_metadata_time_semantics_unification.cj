package lanlu.infrastructure.migrations.versions

import std.database.sql.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

/**
 * V013: Move archive/tankoubon time semantics into metadata_objects.
 */
public class V013_MetadataTimeSemanticsUnification <: Migration {
    private let logger = getLogger("migration_v013")

    public func version(): String {
        return "V013"
    }

    public func description(): String {
        return "Unify archive/tankoubon time fields in metadata_objects and add release_at"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.addColumnIfNotExists(conn, "metadata_objects", "release_at", "TIMESTAMP NULL")) {
            return false
        }

        if (!ensureRootMetadata(conn)) {
            return false
        }

        if (!backfillRootTimeColumns(conn)) {
            return false
        }

        if (!backfillReleaseAt(conn)) {
            return false
        }

        if (!createMetadataTimeIndexes(conn)) {
            return false
        }

        if (!dropLegacyTimeDependents(conn)) {
            return false
        }

        if (!recreateArchiveMetadataSearchView(conn)) {
            return false
        }

        logger.info("V013 migration applied")
        return true
    }

    private func ensureRootMetadata(conn: Connection): Bool {
        if (!MigrationHelpers.execUpdate(conn, """
            INSERT INTO metadata_objects (
                entity_type, entity_id, title, description, created_at, updated_at
            )
            SELECT
                'archive',
                a.arcid,
                '',
                '',
                COALESCE(a.created_at, CURRENT_TIMESTAMP),
                COALESCE(a.updated_at, COALESCE(a.created_at, CURRENT_TIMESTAMP))
            FROM archives a
            WHERE NOT EXISTS (
                SELECT 1
                FROM metadata_objects mo
                WHERE mo.entity_type = 'archive'
                  AND mo.entity_id = a.arcid
            )
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            INSERT INTO metadata_objects (
                entity_type, entity_id, title, description, created_at, updated_at
            )
            SELECT
                'tankoubon',
                t.tankoubon_id,
                '',
                '',
                COALESCE(t.created_at, CURRENT_TIMESTAMP),
                COALESCE(t.updated_at, COALESCE(t.created_at, CURRENT_TIMESTAMP))
            FROM tankoubons t
            WHERE NOT EXISTS (
                SELECT 1
                FROM metadata_objects mo
                WHERE mo.entity_type = 'tankoubon'
                  AND mo.entity_id = t.tankoubon_id
            )
        """)) {
            return false
        }

        return true
    }

    private func backfillRootTimeColumns(conn: Connection): Bool {
        if (!MigrationHelpers.execUpdate(conn, """
            UPDATE metadata_objects mo
            SET created_at = COALESCE(mo.created_at, a.created_at),
                updated_at = COALESCE(mo.updated_at, a.updated_at, a.created_at)
            FROM archives a
            WHERE mo.entity_type = 'archive'
              AND mo.entity_id = a.arcid
              AND (mo.created_at IS NULL OR mo.updated_at IS NULL)
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            UPDATE metadata_objects mo
            SET created_at = COALESCE(mo.created_at, t.created_at),
                updated_at = COALESCE(mo.updated_at, t.updated_at, t.created_at)
            FROM tankoubons t
            WHERE mo.entity_type = 'tankoubon'
              AND mo.entity_id = t.tankoubon_id
              AND (mo.created_at IS NULL OR mo.updated_at IS NULL)
        """)) {
            return false
        }

        return true
    }

    /**
     * Deterministic release_at backfill:
     * - only from structured unix timestamp values in extra_data.release_at / extra_data.release_date
     * - otherwise keep NULL (no guessing).
     */
    private func backfillReleaseAt(conn: Connection): Bool {
        return MigrationHelpers.execUpdate(conn, """
            UPDATE metadata_objects
            SET release_at = CASE
                WHEN COALESCE(extra_data ->> 'release_at', '') ~ '^[0-9]{9,}$'
                    THEN to_timestamp((extra_data ->> 'release_at')::BIGINT)
                WHEN COALESCE(extra_data ->> 'release_date', '') ~ '^[0-9]{9,}$'
                    THEN to_timestamp((extra_data ->> 'release_date')::BIGINT)
                ELSE release_at
            END
            WHERE release_at IS NULL
              AND (
                COALESCE(extra_data ->> 'release_at', '') ~ '^[0-9]{9,}$'
                OR COALESCE(extra_data ->> 'release_date', '') ~ '^[0-9]{9,}$'
              )
        """)
    }

    private func createMetadataTimeIndexes(conn: Connection): Bool {
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_metadata_objects_entity_created_at", "metadata_objects", "entity_type, created_at")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_metadata_objects_entity_updated_at", "metadata_objects", "entity_type, updated_at")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_metadata_objects_entity_release_at", "metadata_objects", "entity_type, release_at")) {
            return false
        }
        return true
    }

    private func dropLegacyTimeDependents(conn: Connection): Bool {
        if (!dropLegacyRelation(conn, "archive_metadata_search")) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, "DROP INDEX IF EXISTS idx_archives_created_at")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(conn, "DROP INDEX IF EXISTS idx_archives_updated_at")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(conn, "DROP INDEX IF EXISTS idx_tankoubons_created_at")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(conn, "DROP INDEX IF EXISTS idx_tankoubons_updated_at")) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, "ALTER TABLE archives DROP COLUMN IF EXISTS created_at")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(conn, "ALTER TABLE archives DROP COLUMN IF EXISTS updated_at")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(conn, "ALTER TABLE tankoubons DROP COLUMN IF EXISTS created_at")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(conn, "ALTER TABLE tankoubons DROP COLUMN IF EXISTS updated_at")) {
            return false
        }

        return true
    }

    private func dropLegacyRelation(conn: Connection, name: String): Bool {
        if (MigrationHelpers.viewExists(conn, name)) {
            if (!MigrationHelpers.execUpdate(conn, "DROP VIEW IF EXISTS ${name}")) {
                return false
            }
        }
        if (MigrationHelpers.tableExists(conn, name)) {
            if (!MigrationHelpers.execUpdate(conn, "DROP TABLE IF EXISTS ${name}")) {
                return false
            }
        }
        return true
    }

    private func recreateArchiveMetadataSearchView(conn: Connection): Bool {
        return MigrationHelpers.execUpdate(conn, """
            CREATE VIEW archive_metadata_search AS
            SELECT
                a.id,
                a.arcid,
                a.filename,
                COALESCE(mo.title, '') AS title,
                COALESCE(mo.description, '') AS summary,
                COALESCE(cover_asset.thumbhash, COALESCE(a.thumbhash, '')) AS thumbhash,
                COALESCE(cover.asset_id, 0) AS cover_asset_id,
                COALESCE(mo.created_at, CURRENT_TIMESTAMP) AS created_at,
                COALESCE(mo.updated_at, COALESCE(mo.created_at, CURRENT_TIMESTAMP)) AS updated_at,
                mo.release_at AS release_at,
                a.relative_path,
                a.file_size,
                a.pagecount,
                a.archive_type,
                a.category_id,
                COALESCE(string_agg(mt.tag, ',' ORDER BY mt.tag), '') AS tags,
                (
                    setweight(to_tsvector('simple', COALESCE(mo.title, '')), 'A') ||
                    setweight(to_tsvector('simple', COALESCE(a.filename, '')), 'B') ||
                    setweight(to_tsvector('simple', COALESCE(string_agg(mt.tag, ' ' ORDER BY mt.tag), '')), 'C')
                ) AS search_tsv
            FROM archives a
            LEFT JOIN metadata_objects mo
                   ON mo.entity_type = 'archive'
                  AND mo.entity_id = a.arcid
            LEFT JOIN metadata_tags mt ON mt.metadata_id = mo.id
            LEFT JOIN metadata_assets cover
                   ON cover.metadata_id = mo.id
                  AND cover.slot = 'cover'
            LEFT JOIN assets cover_asset ON cover_asset.id = cover.asset_id
            GROUP BY
                a.id, a.arcid, a.filename, mo.title, mo.description,
                cover.asset_id, cover_asset.thumbhash,
                a.thumbhash, mo.created_at, mo.updated_at, mo.release_at,
                a.relative_path, a.file_size, a.pagecount, a.archive_type, a.category_id
        """)
    }
}
