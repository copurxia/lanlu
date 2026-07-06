package lanlu.infrastructure.migrations.versions

import csorm.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

/**
 * V012: Remove legacy metadata storage and rebuild metadata-driven search views.
 */
public class V012_CanonicalMetadataCleanup <: Migration {
    private let logger = getLogger("migration_v012")

    public func version(): String {
        return "V012"
    }

    public func description(): String {
        return "Drop legacy metadata tables and rebuild canonical metadata search view"
    }

    public func up(db: Database): Bool {
        if (!ensureRootMetadata(db)) {
            return false
        }

        if (!backfillTagsFromLegacyRelations(db)) {
            return false
        }

        if (!backfillAssetsFromLegacyColumns(db)) {
            return false
        }

        // Drop obsolete structures. Object type drift exists across historical branches,
        // so check actual type first to avoid PostgreSQL "is not a view/table" errors.
        if (!dropLegacyRelation(db, "archive_page_metadata")) {
            return false
        }
        if (!dropLegacyRelation(db, "archive_metadata_search")) {
            return false
        }
        if (!dropLegacyRelation(db, "archives_with_tags")) {
            return false
        }
        if (!dropLegacyRelation(db, "archive_tags")) {
            return false
        }
        if (!dropLegacyRelation(db, "tankoubon_tags")) {
            return false
        }

        if (!dropLegacyColumnsAndIndexes(db)) {
            return false
        }

        if (!recreateArchiveMetadataSearchView(db)) {
            return false
        }

        logger.info("V012 migration applied")
        return true
    }

    private func ensureRootMetadata(db: Database): Bool {
        if (!MigrationHelpers.execUpdate(db, """
            INSERT INTO metadata_objects (
                entity_type, entity_id, title, description, created_at, updated_at
            )
            SELECT
                'archive',
                a.arcid,
                COALESCE(a.title, ''),
                COALESCE(a.summary, ''),
                a.created_at,
                a.updated_at
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

        if (!MigrationHelpers.execUpdate(db, """
            INSERT INTO metadata_objects (
                entity_type, entity_id, title, description, created_at, updated_at
            )
            SELECT
                'tankoubon',
                t.tankoubon_id,
                COALESCE(t.name, ''),
                COALESCE(t.summary, ''),
                t.created_at,
                t.updated_at
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

    private func backfillTagsFromLegacyRelations(db: Database): Bool {
        if (MigrationHelpers.tableExists(db, "archive_tags") && MigrationHelpers.tableExists(db, "tags")) {
            if (!MigrationHelpers.execUpdate(db, """
                INSERT INTO metadata_tags (metadata_id, tag)
                SELECT
                    mo.id,
                    CASE
                        WHEN COALESCE(tg.namespace, '') != '' THEN tg.namespace || ':' || tg.name
                        ELSE tg.name
                    END AS tag_str
                FROM metadata_objects mo
                JOIN archives a
                  ON mo.entity_type = 'archive'
                 AND mo.entity_id = a.arcid
                JOIN archive_tags atg ON atg.archive_id = a.id
                JOIN tags tg ON tg.id = atg.tag_id
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM metadata_tags mt
                    WHERE mt.metadata_id = mo.id
                      AND mt.tag = CASE
                          WHEN COALESCE(tg.namespace, '') != '' THEN tg.namespace || ':' || tg.name
                          ELSE tg.name
                      END
                )
            """)) {
                return false
            }
        } else {
            logger.warn("archive_tags relation missing; skipping legacy archive tag backfill")
        }

        if (MigrationHelpers.tableExists(db, "tankoubon_tags") && MigrationHelpers.tableExists(db, "tags")) {
            if (!MigrationHelpers.execUpdate(db, """
                INSERT INTO metadata_tags (metadata_id, tag)
                SELECT
                    mo.id,
                    CASE
                        WHEN COALESCE(tg.namespace, '') != '' THEN tg.namespace || ':' || tg.name
                        ELSE tg.name
                    END AS tag_str
                FROM metadata_objects mo
                JOIN tankoubons t
                  ON mo.entity_type = 'tankoubon'
                 AND mo.entity_id = t.tankoubon_id
                JOIN tankoubon_tags tt ON tt.tankoubon_id = t.id
                JOIN tags tg ON tg.id = tt.tag_id
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM metadata_tags mt
                    WHERE mt.metadata_id = mo.id
                      AND mt.tag = CASE
                          WHEN COALESCE(tg.namespace, '') != '' THEN tg.namespace || ':' || tg.name
                          ELSE tg.name
                      END
                )
            """)) {
                return false
            }
        } else {
            logger.warn("tankoubon_tags relation missing; skipping legacy tankoubon tag backfill")
        }

        return true
    }

    private func backfillAssetsFromLegacyColumns(db: Database): Bool {
        if (MigrationHelpers.columnExists(db, "archives", "assets")) {
            if (!MigrationHelpers.execUpdate(db, """
                UPDATE metadata_assets ma
                SET asset_id = src.asset_id,
                    updated_at = CURRENT_TIMESTAMP
                FROM (
                    SELECT
                        mo.id AS metadata_id,
                        LOWER(TRIM(kv.key)) AS slot,
                        (kv.value)::BIGINT AS asset_id
                    FROM metadata_objects mo
                    JOIN archives a
                      ON mo.entity_type = 'archive'
                     AND mo.entity_id = a.arcid
                    CROSS JOIN LATERAL jsonb_each_text(COALESCE(a.assets, '{}'::jsonb)) kv(key, value)
                    WHERE kv.value ~ '^[0-9]+$'
                      AND (kv.value)::BIGINT > 0
                ) src
                WHERE ma.metadata_id = src.metadata_id
                  AND ma.slot = src.slot
            """)) {
                return false
            }
            if (!MigrationHelpers.execUpdate(db, """
                INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at)
                SELECT src.metadata_id, src.slot, src.asset_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                FROM (
                    SELECT
                        mo.id AS metadata_id,
                        LOWER(TRIM(kv.key)) AS slot,
                        (kv.value)::BIGINT AS asset_id
                    FROM metadata_objects mo
                    JOIN archives a
                      ON mo.entity_type = 'archive'
                     AND mo.entity_id = a.arcid
                    CROSS JOIN LATERAL jsonb_each_text(COALESCE(a.assets, '{}'::jsonb)) kv(key, value)
                    WHERE kv.value ~ '^[0-9]+$'
                      AND (kv.value)::BIGINT > 0
                ) src
                WHERE NOT EXISTS (
                    SELECT 1 FROM metadata_assets ma
                    WHERE ma.metadata_id = src.metadata_id
                      AND ma.slot = src.slot
                )
            """)) {
                return false
            }
        }

        if (MigrationHelpers.columnExists(db, "archives", "cover_asset_id")) {
            if (!MigrationHelpers.execUpdate(db, """
                UPDATE metadata_assets ma
                SET asset_id = src.asset_id,
                    updated_at = CURRENT_TIMESTAMP
                FROM (
                    SELECT
                        mo.id AS metadata_id,
                        'cover' AS slot,
                        a.cover_asset_id AS asset_id
                    FROM metadata_objects mo
                    JOIN archives a
                      ON mo.entity_type = 'archive'
                     AND mo.entity_id = a.arcid
                    WHERE COALESCE(a.cover_asset_id, 0) > 0
                ) src
                WHERE ma.metadata_id = src.metadata_id
                  AND ma.slot = src.slot
            """)) {
                return false
            }
            if (!MigrationHelpers.execUpdate(db, """
                INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at)
                SELECT src.metadata_id, src.slot, src.asset_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                FROM (
                    SELECT
                        mo.id AS metadata_id,
                        'cover' AS slot,
                        a.cover_asset_id AS asset_id
                    FROM metadata_objects mo
                    JOIN archives a
                      ON mo.entity_type = 'archive'
                     AND mo.entity_id = a.arcid
                    WHERE COALESCE(a.cover_asset_id, 0) > 0
                ) src
                WHERE NOT EXISTS (
                    SELECT 1 FROM metadata_assets ma
                    WHERE ma.metadata_id = src.metadata_id
                      AND ma.slot = src.slot
                )
            """)) {
                return false
            }
        }

        if (MigrationHelpers.columnExists(db, "tankoubons", "assets")) {
            if (!MigrationHelpers.execUpdate(db, """
                UPDATE metadata_assets ma
                SET asset_id = src.asset_id,
                    updated_at = CURRENT_TIMESTAMP
                FROM (
                    SELECT
                        mo.id AS metadata_id,
                        LOWER(TRIM(kv.key)) AS slot,
                        (kv.value)::BIGINT AS asset_id
                    FROM metadata_objects mo
                    JOIN tankoubons t
                      ON mo.entity_type = 'tankoubon'
                     AND mo.entity_id = t.tankoubon_id
                    CROSS JOIN LATERAL jsonb_each_text(COALESCE(t.assets, '{}'::jsonb)) kv(key, value)
                    WHERE kv.value ~ '^[0-9]+$'
                      AND (kv.value)::BIGINT > 0
                ) src
                WHERE ma.metadata_id = src.metadata_id
                  AND ma.slot = src.slot
            """)) {
                return false
            }
            if (!MigrationHelpers.execUpdate(db, """
                INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at)
                SELECT src.metadata_id, src.slot, src.asset_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                FROM (
                    SELECT
                        mo.id AS metadata_id,
                        LOWER(TRIM(kv.key)) AS slot,
                        (kv.value)::BIGINT AS asset_id
                    FROM metadata_objects mo
                    JOIN tankoubons t
                      ON mo.entity_type = 'tankoubon'
                     AND mo.entity_id = t.tankoubon_id
                    CROSS JOIN LATERAL jsonb_each_text(COALESCE(t.assets, '{}'::jsonb)) kv(key, value)
                    WHERE kv.value ~ '^[0-9]+$'
                      AND (kv.value)::BIGINT > 0
                ) src
                WHERE NOT EXISTS (
                    SELECT 1 FROM metadata_assets ma
                    WHERE ma.metadata_id = src.metadata_id
                      AND ma.slot = src.slot
                )
            """)) {
                return false
            }
        }

        if (MigrationHelpers.columnExists(db, "tankoubons", "cover_asset_id")) {
            if (!MigrationHelpers.execUpdate(db, """
                UPDATE metadata_assets ma
                SET asset_id = src.asset_id,
                    updated_at = CURRENT_TIMESTAMP
                FROM (
                    SELECT
                        mo.id AS metadata_id,
                        'cover' AS slot,
                        t.cover_asset_id AS asset_id
                    FROM metadata_objects mo
                    JOIN tankoubons t
                      ON mo.entity_type = 'tankoubon'
                     AND mo.entity_id = t.tankoubon_id
                    WHERE COALESCE(t.cover_asset_id, 0) > 0
                ) src
                WHERE ma.metadata_id = src.metadata_id
                  AND ma.slot = src.slot
            """)) {
                return false
            }
            if (!MigrationHelpers.execUpdate(db, """
                INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at)
                SELECT src.metadata_id, src.slot, src.asset_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                FROM (
                    SELECT
                        mo.id AS metadata_id,
                        'cover' AS slot,
                        t.cover_asset_id AS asset_id
                    FROM metadata_objects mo
                    JOIN tankoubons t
                      ON mo.entity_type = 'tankoubon'
                     AND mo.entity_id = t.tankoubon_id
                    WHERE COALESCE(t.cover_asset_id, 0) > 0
                ) src
                WHERE NOT EXISTS (
                    SELECT 1 FROM metadata_assets ma
                    WHERE ma.metadata_id = src.metadata_id
                      AND ma.slot = src.slot
                )
            """)) {
                return false
            }
        }

        return true
    }

    private func dropLegacyColumnsAndIndexes(db: Database): Bool {
        if (!MigrationHelpers.execUpdate(db, "DROP INDEX IF EXISTS idx_archives_title_trgm")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "DROP INDEX IF EXISTS idx_archives_summary_trgm")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "DROP INDEX IF EXISTS idx_archives_cover_asset_id")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "DROP INDEX IF EXISTS idx_archives_title_tsv")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "DROP INDEX IF EXISTS idx_tankoubons_name")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "DROP INDEX IF EXISTS idx_tankoubons_cover_asset_id")) {
            return false
        }

        if (!MigrationHelpers.execUpdate(db, "ALTER TABLE archives DROP COLUMN IF EXISTS title_tsv")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "ALTER TABLE archives DROP COLUMN IF EXISTS title")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "ALTER TABLE archives DROP COLUMN IF EXISTS summary")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "ALTER TABLE archives DROP COLUMN IF EXISTS cover_asset_id")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "ALTER TABLE archives DROP COLUMN IF EXISTS assets")) {
            return false
        }

        if (!MigrationHelpers.execUpdate(db, "ALTER TABLE tankoubons DROP COLUMN IF EXISTS name")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "ALTER TABLE tankoubons DROP COLUMN IF EXISTS summary")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "ALTER TABLE tankoubons DROP COLUMN IF EXISTS cover_asset_id")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "ALTER TABLE tankoubons DROP COLUMN IF EXISTS assets")) {
            return false
        }
        return true
    }

    private func dropLegacyRelation(db: Database, name: String): Bool {
        if (MigrationHelpers.viewExists(db, name)) {
            if (!MigrationHelpers.execUpdate(db, "DROP VIEW IF EXISTS ${name}")) {
                return false
            }
        }
        if (MigrationHelpers.tableExists(db, name)) {
            if (!MigrationHelpers.execUpdate(db, "DROP TABLE IF EXISTS ${name}")) {
                return false
            }
        }
        return true
    }

    private func recreateArchiveMetadataSearchView(db: Database): Bool {
        return MigrationHelpers.execUpdate(db, """
            CREATE VIEW archive_metadata_search AS
            SELECT
                a.id,
                a.arcid,
                a.filename,
                COALESCE(mo.title, '') AS title,
                COALESCE(mo.description, '') AS summary,
                COALESCE(cover_asset.thumbhash, COALESCE(a.thumbhash, '')) AS thumbhash,
                COALESCE(cover.asset_id, 0) AS cover_asset_id,
                a.created_at,
                a.updated_at,
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
                a.thumbhash, a.created_at, a.updated_at, a.relative_path,
                a.file_size, a.pagecount, a.archive_type, a.category_id
        """)
    }
}
