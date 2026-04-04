package lanlu.infrastructure.migrations.versions

import std.database.sql.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

/**
 * V011: Introduce unified metadata store and backfill archive/page/tankoubon metadata.
 */
public class V011_UnifiedMetadataStore <: Migration {
    private let logger = getLogger("migration_v011")

    public func version(): String {
        return "V011"
    }

    public func description(): String {
        return "Create unified metadata tables and backfill archive/page/tankoubon metadata"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE IF NOT EXISTS metadata_objects (
                id BIGSERIAL PRIMARY KEY,
                entity_type VARCHAR(32) NOT NULL,
                entity_id TEXT NOT NULL,
                parent_entity_type VARCHAR(32) NOT NULL DEFAULT '',
                parent_entity_id TEXT NOT NULL DEFAULT '',
                title TEXT NOT NULL DEFAULT '',
                description TEXT NOT NULL DEFAULT '',
                volume_no INT NOT NULL DEFAULT 0,
                order_index INT NOT NULL DEFAULT 0,
                page_number INT NOT NULL DEFAULT 0,
                entry_path TEXT NOT NULL DEFAULT '',
                extra_data JSONB NOT NULL DEFAULT '{}'::jsonb,
                source_namespace VARCHAR(100) NOT NULL DEFAULT '',
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE (entity_type, entity_id)
            )
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE IF NOT EXISTS metadata_tags (
                metadata_id BIGINT NOT NULL,
                tag TEXT NOT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (metadata_id, tag),
                FOREIGN KEY (metadata_id) REFERENCES metadata_objects(id) ON DELETE CASCADE
            )
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE IF NOT EXISTS metadata_assets (
                metadata_id BIGINT NOT NULL,
                slot VARCHAR(32) NOT NULL,
                asset_id BIGINT NOT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (metadata_id, slot),
                FOREIGN KEY (metadata_id) REFERENCES metadata_objects(id) ON DELETE CASCADE
            )
        """)) {
            return false
        }

        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_metadata_objects_parent", "metadata_objects", "parent_entity_type, parent_entity_id")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_metadata_objects_type_order", "metadata_objects", "entity_type, parent_entity_id, order_index, page_number")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_metadata_tags_tag", "metadata_tags", "tag")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_metadata_assets_asset_id", "metadata_assets", "asset_id")) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_metadata_pages_parent_path
            ON metadata_objects (entity_type, parent_entity_id, entry_path)
            WHERE entity_type = 'page'
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            INSERT INTO metadata_objects (
                entity_type, entity_id, title, description, created_at, updated_at
            )
            SELECT 'archive', a.arcid, COALESCE(a.title, ''), COALESCE(a.summary, ''), a.created_at, a.updated_at
            FROM archives a
            WHERE NOT EXISTS (
                SELECT 1 FROM metadata_objects mo
                WHERE mo.entity_type = 'archive' AND mo.entity_id = a.arcid
            )
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            INSERT INTO metadata_objects (
                entity_type, entity_id, title, description, created_at, updated_at
            )
            SELECT 'tankoubon', t.tankoubon_id, COALESCE(t.name, ''), COALESCE(t.summary, ''), t.created_at, t.updated_at
            FROM tankoubons t
            WHERE NOT EXISTS (
                SELECT 1 FROM metadata_objects mo
                WHERE mo.entity_type = 'tankoubon' AND mo.entity_id = t.tankoubon_id
            )
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            INSERT INTO metadata_objects (
                entity_type,
                entity_id,
                parent_entity_type,
                parent_entity_id,
                title,
                description,
                order_index,
                page_number,
                entry_path,
                extra_data,
                created_at,
                updated_at
            )
            SELECT
                'page',
                a.arcid || ':' || COALESCE(NULLIF(apm.entry_path, ''), '__page_' || apm.page_number::TEXT),
                'archive',
                a.arcid,
                COALESCE(apm.title, ''),
                COALESCE(apm.description, ''),
                COALESCE(apm.sort_index, 0),
                COALESCE(apm.page_number, 0),
                COALESCE(NULLIF(apm.entry_path, ''), '__page_' || apm.page_number::TEXT),
                CASE
                    WHEN NULLIF(COALESCE(apm.thumbhash, ''), '') IS NULL THEN
                        jsonb_set(
                            '{}'::jsonb,
                            '{hidden_in_files}',
                            CAST(CASE WHEN COALESCE(apm.hidden_in_files, false) THEN 'true' ELSE 'false' END AS JSONB),
                            true
                        )
                    ELSE
                        jsonb_set(
                            jsonb_set(
                                '{}'::jsonb,
                                '{hidden_in_files}',
                                CAST(CASE WHEN COALESCE(apm.hidden_in_files, false) THEN 'true' ELSE 'false' END AS JSONB),
                                true
                            ),
                            '{thumbhash}',
                            CAST(
                                '"' ||
                                REPLACE(REPLACE(COALESCE(apm.thumbhash, ''), '\', '\\'), '"', '\"') ||
                                '"' AS JSONB
                            ),
                            true
                        )
                END,
                apm.created_at,
                apm.updated_at
            FROM archive_page_metadata apm
            JOIN archives a ON a.id = apm.archive_id
            WHERE NOT EXISTS (
                SELECT 1 FROM metadata_objects mo
                WHERE mo.entity_type = 'page'
                  AND mo.entity_id = a.arcid || ':' || COALESCE(NULLIF(apm.entry_path, ''), '__page_' || apm.page_number::TEXT)
            )
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            INSERT INTO metadata_tags (metadata_id, tag)
            SELECT mo.id,
                   CASE WHEN tg.namespace != '' AND tg.namespace IS NOT NULL
                        THEN tg.namespace || ':' || tg.name
                        ELSE tg.name
                   END AS tag_str
            FROM metadata_objects mo
            JOIN archives a ON mo.entity_type = 'archive' AND mo.entity_id = a.arcid
            JOIN archive_tags atg ON atg.archive_id = a.id
            JOIN tags tg ON tg.id = atg.tag_id
            WHERE NOT EXISTS (
                SELECT 1
                FROM metadata_tags mt
                WHERE mt.metadata_id = mo.id
                  AND mt.tag = CASE
                      WHEN tg.namespace != '' AND tg.namespace IS NOT NULL
                          THEN tg.namespace || ':' || tg.name
                      ELSE tg.name
                  END
            )
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            INSERT INTO metadata_tags (metadata_id, tag)
            SELECT mo.id,
                   CASE WHEN tg.namespace != '' AND tg.namespace IS NOT NULL
                        THEN tg.namespace || ':' || tg.name
                        ELSE tg.name
                   END AS tag_str
            FROM metadata_objects mo
            JOIN tankoubons t ON mo.entity_type = 'tankoubon' AND mo.entity_id = t.tankoubon_id
            JOIN tankoubon_tags tt ON tt.tankoubon_id = t.id
            JOIN tags tg ON tg.id = tt.tag_id
            WHERE NOT EXISTS (
                SELECT 1
                FROM metadata_tags mt
                WHERE mt.metadata_id = mo.id
                  AND mt.tag = CASE
                      WHEN tg.namespace != '' AND tg.namespace IS NOT NULL
                          THEN tg.namespace || ':' || tg.name
                      ELSE tg.name
                  END
            )
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            UPDATE metadata_assets ma
            SET asset_id = src.asset_id,
                updated_at = CURRENT_TIMESTAMP
            FROM (
                SELECT mo.id AS metadata_id, kv.key AS slot, kv.value::BIGINT AS asset_id
                FROM metadata_objects mo
                JOIN archives a ON mo.entity_type = 'archive' AND mo.entity_id = a.arcid
                CROSS JOIN LATERAL jsonb_each_text(COALESCE(a.assets, '{}'::jsonb)) kv(key, value)
                WHERE kv.key IN ('cover', 'backdrop', 'clearlogo')
                  AND kv.value ~ '^[0-9]+$'
                  AND kv.value::BIGINT > 0
            ) src
            WHERE ma.metadata_id = src.metadata_id
              AND ma.slot = src.slot
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at)
            SELECT src.metadata_id, src.slot, src.asset_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            FROM (
                SELECT mo.id AS metadata_id, kv.key AS slot, kv.value::BIGINT AS asset_id
                FROM metadata_objects mo
                JOIN archives a ON mo.entity_type = 'archive' AND mo.entity_id = a.arcid
                CROSS JOIN LATERAL jsonb_each_text(COALESCE(a.assets, '{}'::jsonb)) kv(key, value)
                WHERE kv.key IN ('cover', 'backdrop', 'clearlogo')
                  AND kv.value ~ '^[0-9]+$'
                  AND kv.value::BIGINT > 0
            ) src
            WHERE NOT EXISTS (
                SELECT 1 FROM metadata_assets ma
                WHERE ma.metadata_id = src.metadata_id
                  AND ma.slot = src.slot
            )
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            UPDATE metadata_assets ma
            SET asset_id = src.asset_id,
                updated_at = CURRENT_TIMESTAMP
            FROM (
                SELECT mo.id AS metadata_id, kv.key AS slot, kv.value::BIGINT AS asset_id
                FROM metadata_objects mo
                JOIN tankoubons t ON mo.entity_type = 'tankoubon' AND mo.entity_id = t.tankoubon_id
                CROSS JOIN LATERAL jsonb_each_text(COALESCE(t.assets, '{}'::jsonb)) kv(key, value)
                WHERE kv.key IN ('cover', 'backdrop', 'clearlogo')
                  AND kv.value ~ '^[0-9]+$'
                  AND kv.value::BIGINT > 0
            ) src
            WHERE ma.metadata_id = src.metadata_id
              AND ma.slot = src.slot
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at)
            SELECT src.metadata_id, src.slot, src.asset_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            FROM (
                SELECT mo.id AS metadata_id, kv.key AS slot, kv.value::BIGINT AS asset_id
                FROM metadata_objects mo
                JOIN tankoubons t ON mo.entity_type = 'tankoubon' AND mo.entity_id = t.tankoubon_id
                CROSS JOIN LATERAL jsonb_each_text(COALESCE(t.assets, '{}'::jsonb)) kv(key, value)
                WHERE kv.key IN ('cover', 'backdrop', 'clearlogo')
                  AND kv.value ~ '^[0-9]+$'
                  AND kv.value::BIGINT > 0
            ) src
            WHERE NOT EXISTS (
                SELECT 1 FROM metadata_assets ma
                WHERE ma.metadata_id = src.metadata_id
                  AND ma.slot = src.slot
            )
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            UPDATE metadata_assets ma
            SET asset_id = src.asset_id,
                updated_at = src.updated_at
            FROM (
                SELECT mo.id AS metadata_id, 'thumb' AS slot, apm.thumb_asset_id AS asset_id, apm.updated_at AS updated_at
                FROM metadata_objects mo
                JOIN archives a ON mo.entity_type = 'page' AND mo.parent_entity_type = 'archive' AND mo.parent_entity_id = a.arcid
                JOIN archive_page_metadata apm
                  ON apm.archive_id = a.id
                 AND COALESCE(NULLIF(apm.entry_path, ''), '__page_' || apm.page_number::TEXT) = mo.entry_path
                WHERE COALESCE(apm.thumb_asset_id, 0) > 0
            ) src
            WHERE ma.metadata_id = src.metadata_id
              AND ma.slot = src.slot
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at)
            SELECT src.metadata_id, src.slot, src.asset_id, src.updated_at, src.updated_at
            FROM (
                SELECT mo.id AS metadata_id, 'thumb' AS slot, apm.thumb_asset_id AS asset_id, apm.updated_at AS updated_at
                FROM metadata_objects mo
                JOIN archives a ON mo.entity_type = 'page' AND mo.parent_entity_type = 'archive' AND mo.parent_entity_id = a.arcid
                JOIN archive_page_metadata apm
                  ON apm.archive_id = a.id
                 AND COALESCE(NULLIF(apm.entry_path, ''), '__page_' || apm.page_number::TEXT) = mo.entry_path
                WHERE COALESCE(apm.thumb_asset_id, 0) > 0
            ) src
            WHERE NOT EXISTS (
                SELECT 1 FROM metadata_assets ma
                WHERE ma.metadata_id = src.metadata_id
                  AND ma.slot = src.slot
            )
        """)) {
            return false
        }

        logger.info("V011 migration applied")
        return true
    }
}
