package lanlu.infrastructure.migrations.versions

import std.database.sql.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

/**
 * V010: Add assets jsonb columns to archives/tankoubons and backfill cover mapping.
 */
public class V010_ArchiveTankoubonAssetsJson <: Migration {
    private let logger = getLogger("migration_v010")

    public func version(): String {
        return "V010"
    }

    public func description(): String {
        return "Add assets jsonb to archives and tankoubons with cover backfill"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.addColumnIfNotExists(conn, "archives", "assets", "JSONB NOT NULL DEFAULT '{}'::jsonb")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(conn, "tankoubons", "assets", "JSONB NOT NULL DEFAULT '{}'::jsonb")) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            UPDATE archives
            SET assets = jsonb_set(
                COALESCE(assets, '{}'::jsonb),
                '{cover}',
                CAST(CAST(cover_asset_id AS TEXT) AS JSONB),
                true
            )
            WHERE COALESCE(cover_asset_id, 0) > 0
              AND NOT jsonb_exists(COALESCE(assets, '{}'::jsonb), 'cover')
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            UPDATE tankoubons
            SET assets = jsonb_set(
                COALESCE(assets, '{}'::jsonb),
                '{cover}',
                CAST(CAST(cover_asset_id AS TEXT) AS JSONB),
                true
            )
            WHERE COALESCE(cover_asset_id, 0) > 0
              AND NOT jsonb_exists(COALESCE(assets, '{}'::jsonb), 'cover')
        """)) {
            return false
        }

        logger.info("V010 migration applied")
        return true
    }
}
