package lrr4cj.migrations.versions

import std.database.sql.*
import lrr4cj.migrations.*
import lrr4cj.utils.*

/**
 * V003: Generic assets table + link archive covers and user avatars to assets.
 */
public class V003_Assets <: Migration {
    private let logger = getLogger("migration_v003")

    public func version(): String {
        return "V003"
    }

    public func description(): String {
        return "Create assets table; add cover_asset_id to archives and avatar_asset_id to users"
    }

    public func up(conn: Connection): Bool {
        if (!ensureAssetsTable(conn)) { return false }
        if (!ensureArchiveCoverAssetColumn(conn)) { return false }
        if (!ensureUserAvatarAssetColumn(conn)) { return false }
        return true
    }

    private func ensureAssetsTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "assets")) {
            logger.debug("assets table already exists, checking columns")
            MigrationHelpers.addColumnIfNotExists(conn, "assets", "owner_user_id", "BIGINT")
            MigrationHelpers.addColumnIfNotExists(conn, "assets", "kind", "VARCHAR(50) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(conn, "assets", "original_filename", "VARCHAR(1024) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(conn, "assets", "content_type", "VARCHAR(255) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(conn, "assets", "file_ext", "VARCHAR(32) NOT NULL DEFAULT 'bin'")
            MigrationHelpers.addColumnIfNotExists(conn, "assets", "byte_size", "BIGINT NOT NULL DEFAULT 0")
            MigrationHelpers.addColumnIfNotExists(conn, "assets", "thumbhash", "TEXT NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(conn, "assets", "created_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_assets_owner_user_id", "assets", "owner_user_id")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_assets_kind", "assets", "kind")
            return true
        }

        logger.debug("Creating assets table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE assets (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                owner_user_id BIGINT,
                kind VARCHAR(50) NOT NULL DEFAULT '',
                original_filename VARCHAR(1024) NOT NULL DEFAULT '',
                content_type VARCHAR(255) NOT NULL DEFAULT '',
                file_ext VARCHAR(32) NOT NULL DEFAULT 'bin',
                byte_size BIGINT NOT NULL DEFAULT 0,
                thumbhash TEXT NOT NULL DEFAULT '',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(conn, "idx_assets_owner_user_id", "assets", "owner_user_id")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_assets_kind", "assets", "kind")
        return true
    }

    private func ensureArchiveCoverAssetColumn(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "archives")) {
            // Should not happen if V001 ran, but keep migration resilient.
            return true
        }
        MigrationHelpers.addColumnIfNotExists(conn, "archives", "cover_asset_id", "BIGINT")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_archives_cover_asset_id", "archives", "cover_asset_id")
        return true
    }

    private func ensureUserAvatarAssetColumn(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "users")) {
            return true
        }
        MigrationHelpers.addColumnIfNotExists(conn, "users", "avatar_asset_id", "BIGINT")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_users_avatar_asset_id", "users", "avatar_asset_id")
        return true
    }
}

