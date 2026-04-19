package lanlu.infrastructure.migrations.versions

import std.database.sql.*
import lanlu.infrastructure.migrations.*

/**
 * V024: Add composite indexes for search and recommendation hot paths.
 */
public class V024_SearchAndRecommendationHotPathIndexes <: Migration {
    public func version(): String {
        return "V024"
    }

    public func description(): String {
        return "Add composite indexes for search and recommendation hot paths"
    }

    public func up(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "user_archive_status")) {
            if (!MigrationHelpers.createIndexIfNotExists(
                conn,
                "idx_user_archive_status_user_archive_state_time",
                "user_archive_status",
                "user_id, archive_id, is_new, updated_at DESC"
            )) {
                return false
            }
        }

        if (MigrationHelpers.tableExists(conn, "user_favorites")) {
            if (!MigrationHelpers.createIndexIfNotExists(
                conn,
                "idx_user_favorites_user_archive_created",
                "user_favorites",
                "user_id, archive_id, created_at DESC"
            )) {
                return false
            }
        }

        if (MigrationHelpers.tableExists(conn, "recommendation_impressions")) {
            if (!MigrationHelpers.createIndexIfNotExists(
                conn,
                "idx_reco_impressions_user_scene_item_time",
                "recommendation_impressions",
                "user_id, scene, item_type, shown_at DESC"
            )) {
                return false
            }
            if (!MigrationHelpers.createIndexIfNotExists(
                conn,
                "idx_reco_impressions_session_scene_item_time",
                "recommendation_impressions",
                "session_key, scene, item_type, shown_at DESC"
            )) {
                return false
            }
        }

        return true
    }
}
