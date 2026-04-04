package lanlu.infrastructure.migrations.versions

import std.database.sql.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

/**
 * V015: Add recommendation tracking tables and supporting indexes.
 */
public class V015_RecommendationTracking <: Migration {
    public func version(): String {
        return "V015"
    }

    public func description(): String {
        return "Add recommendation tracking tables and indexes"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE IF NOT EXISTS recommendation_impressions (
                id BIGSERIAL PRIMARY KEY,
                user_id BIGINT NOT NULL DEFAULT 0,
                session_key TEXT NOT NULL DEFAULT '',
                scene VARCHAR(64) NOT NULL,
                seed_entity_type VARCHAR(32) NOT NULL DEFAULT '',
                seed_entity_id TEXT NOT NULL DEFAULT '',
                item_type VARCHAR(32) NOT NULL,
                item_id TEXT NOT NULL,
                position INT NOT NULL DEFAULT 0,
                shown_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE IF NOT EXISTS recommendation_interactions (
                id BIGSERIAL PRIMARY KEY,
                user_id BIGINT NOT NULL DEFAULT 0,
                session_key TEXT NOT NULL DEFAULT '',
                scene VARCHAR(64) NOT NULL,
                seed_entity_type VARCHAR(32) NOT NULL DEFAULT '',
                seed_entity_id TEXT NOT NULL DEFAULT '',
                item_type VARCHAR(32) NOT NULL,
                item_id TEXT NOT NULL,
                interaction_type VARCHAR(32) NOT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        """)) {
            return false
        }

        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_metadata_tags_tag_metadata", "metadata_tags", "tag, metadata_id")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_user_archive_status_user_updated", "user_archive_status", "user_id, updated_at DESC")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_user_favorites_user_created", "user_favorites", "user_id, created_at DESC")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_user_tank_favorites_user_created", "user_tankoubon_favorites", "user_id, created_at DESC")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubon_archives_tank_sort", "tankoubon_archives", "tankoubon_id, sort_order, archive_id")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_reco_impressions_user_scene_time", "recommendation_impressions", "user_id, scene, shown_at DESC")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_reco_impressions_session_scene_time", "recommendation_impressions", "session_key, scene, shown_at DESC")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_reco_interactions_user_scene_time", "recommendation_interactions", "user_id, scene, created_at DESC")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_reco_interactions_item_type_id", "recommendation_interactions", "item_type, item_id, created_at DESC")) {
            return false
        }

        return true
    }
}
