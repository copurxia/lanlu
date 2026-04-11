package lanlu.infrastructure.migrations.versions

import std.database.sql.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

/**
 * V018: Introduce page metadata attachments and migrate legacy lyrics_asset_id.
 */
public class V018_PageMetadataAttachments <: Migration {
    private let logger = getLogger("migration_v018")

    public func version(): String {
        return "V018"
    }

    public func description(): String {
        return "Create page metadata attachment table and migrate legacy lyrics asset references"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE IF NOT EXISTS metadata_page_assets (
                id BIGSERIAL PRIMARY KEY,
                metadata_id BIGINT NOT NULL,
                slot VARCHAR(32) NOT NULL,
                asset_id BIGINT NOT NULL,
                name TEXT NOT NULL DEFAULT '',
                mime_type TEXT NOT NULL DEFAULT '',
                kind VARCHAR(32) NOT NULL DEFAULT '',
                language VARCHAR(32) NOT NULL DEFAULT '',
                order_index INT NOT NULL DEFAULT 0,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (metadata_id) REFERENCES metadata_objects(id) ON DELETE CASCADE,
                UNIQUE (metadata_id, slot, name)
            )
        """)) {
            return false
        }

        // Repair legacy/partially migrated schemas where table already exists but misses new columns.
        if (!MigrationHelpers.addColumnIfNotExists(conn, "metadata_page_assets", "metadata_id", "BIGINT NOT NULL DEFAULT 0")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(conn, "metadata_page_assets", "slot", "VARCHAR(32) NOT NULL DEFAULT ''")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(conn, "metadata_page_assets", "asset_id", "BIGINT NOT NULL DEFAULT 0")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(conn, "metadata_page_assets", "name", "TEXT NOT NULL DEFAULT ''")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(conn, "metadata_page_assets", "mime_type", "TEXT NOT NULL DEFAULT ''")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(conn, "metadata_page_assets", "kind", "VARCHAR(32) NOT NULL DEFAULT ''")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(conn, "metadata_page_assets", "language", "VARCHAR(32) NOT NULL DEFAULT ''")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(conn, "metadata_page_assets", "order_index", "INT NOT NULL DEFAULT 0")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(conn, "metadata_page_assets", "created_at", "TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(conn, "metadata_page_assets", "updated_at", "TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP")) {
            return false
        }

        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_metadata_page_assets_metadata", "metadata_page_assets", "metadata_id")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_metadata_page_assets_asset", "metadata_page_assets", "asset_id")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_metadata_page_assets_slot", "metadata_page_assets", "slot")) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            INSERT INTO metadata_page_assets (
                metadata_id, slot, asset_id, name, mime_type, kind, language, order_index, created_at, updated_at
            )
            SELECT
                mo.id,
                'lyrics',
                CAST(mo.extra_data ->> 'lyrics_asset_id' AS BIGINT),
                'lyrics.lrc',
                'text/plain',
                'lrc',
                '',
                0,
                CURRENT_TIMESTAMP,
                CURRENT_TIMESTAMP
            FROM metadata_objects mo
            WHERE mo.entity_type = 'page'
              AND COALESCE(mo.extra_data ->> 'lyrics_asset_id', '') ~ '^[0-9]+$'
              AND CAST(mo.extra_data ->> 'lyrics_asset_id' AS BIGINT) > 0
              AND NOT EXISTS (
                  SELECT 1
                  FROM metadata_page_assets mpa
                  WHERE mpa.metadata_id = mo.id
                    AND mpa.slot = 'lyrics'
                    AND mpa.name = 'lyrics.lrc'
              )
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            UPDATE metadata_objects
            SET extra_data = CASE
                WHEN jsonb_exists(COALESCE(extra_data, '{}'::jsonb), 'lyrics_asset_id')
                    THEN COALESCE(extra_data, '{}'::jsonb) - 'lyrics_asset_id'
                ELSE extra_data
            END
            WHERE entity_type = 'page'
              AND jsonb_exists(COALESCE(extra_data, '{}'::jsonb), 'lyrics_asset_id')
        """)) {
            return false
        }

        logger.info("V018 migration applied")
        return true
    }
}
