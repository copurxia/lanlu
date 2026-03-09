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
                id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
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
                jsonb_strip_nulls(jsonb_build_object(
                    'hidden_in_files', COALESCE(apm.hidden_in_files, false),
                    'thumbhash', NULLIF(COALESCE(apm.thumbhash, ''), '')
                )),
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
            ON CONFLICT DO NOTHING
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
            ON CONFLICT DO NOTHING
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at)
            SELECT mo.id, kv.key, kv.value::BIGINT, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            FROM metadata_objects mo
            JOIN archives a ON mo.entity_type = 'archive' AND mo.entity_id = a.arcid
            CROSS JOIN LATERAL jsonb_each_text(COALESCE(a.assets, '{}'::jsonb)) kv(key, value)
            WHERE kv.key IN ('cover', 'backdrop', 'clearlogo')
              AND kv.value ~ '^[0-9]+$'
              AND kv.value::BIGINT > 0
            ON CONFLICT (metadata_id, slot) DO UPDATE SET
                asset_id = EXCLUDED.asset_id,
                updated_at = CURRENT_TIMESTAMP
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at)
            SELECT mo.id, kv.key, kv.value::BIGINT, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            FROM metadata_objects mo
            JOIN tankoubons t ON mo.entity_type = 'tankoubon' AND mo.entity_id = t.tankoubon_id
            CROSS JOIN LATERAL jsonb_each_text(COALESCE(t.assets, '{}'::jsonb)) kv(key, value)
            WHERE kv.key IN ('cover', 'backdrop', 'clearlogo')
              AND kv.value ~ '^[0-9]+$'
              AND kv.value::BIGINT > 0
            ON CONFLICT (metadata_id, slot) DO UPDATE SET
                asset_id = EXCLUDED.asset_id,
                updated_at = CURRENT_TIMESTAMP
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at)
            SELECT mo.id, 'thumb', apm.thumb_asset_id, apm.created_at, apm.updated_at
            FROM metadata_objects mo
            JOIN archives a ON mo.entity_type = 'page' AND mo.parent_entity_type = 'archive' AND mo.parent_entity_id = a.arcid
            JOIN archive_page_metadata apm
              ON apm.archive_id = a.id
             AND COALESCE(NULLIF(apm.entry_path, ''), '__page_' || apm.page_number::TEXT) = mo.entry_path
            WHERE COALESCE(apm.thumb_asset_id, 0) > 0
            ON CONFLICT (metadata_id, slot) DO UPDATE SET
                asset_id = EXCLUDED.asset_id,
                updated_at = EXCLUDED.updated_at
        """)) {
            return false
        }

        logger.info("V011 migration applied")
        return true
    }
}
