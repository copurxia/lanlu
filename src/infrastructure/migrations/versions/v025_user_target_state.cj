package lanlu.infrastructure.migrations.versions

import ace_orm.{Driver, DbValue}
import lanlu.infrastructure.migrations.*

/**
 * V025: Create user_target_status and user_target_favorites tables for generalized user-target state persistence.
 */
public class V025_UserTargetState <: Migration {
    public func version(): String {
        return "V025"
    }

    public func description(): String {
        return "Create user_target_status and user_target_favorites tables for generalized user-target state persistence"
    }

    public func up(drv: Driver): Bool {
        if (!MigrationHelpers.createTableIfNotExists(drv, "user_target_status", """
            CREATE TABLE IF NOT EXISTS user_target_status (
                id BIGSERIAL PRIMARY KEY,
                user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                target_type VARCHAR(32) NOT NULL,
                target_id VARCHAR(1024) NOT NULL,
                is_new BOOLEAN NOT NULL DEFAULT true,
                progress INTEGER NOT NULL DEFAULT 0,
                last_read_time BIGINT NOT NULL DEFAULT 0,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE (user_id, target_type, target_id)
            )
        """)) {
            return false
        }

        if (!MigrationHelpers.createIndexIfNotExists(
            drv,
            "idx_user_target_status_user_type_id",
            "user_target_status",
            "user_id, target_type, target_id"
        )) {
            return false
        }

        if (!MigrationHelpers.createTableIfNotExists(drv, "user_target_favorites", """
            CREATE TABLE IF NOT EXISTS user_target_favorites (
                id BIGSERIAL PRIMARY KEY,
                user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                target_type VARCHAR(32) NOT NULL,
                target_id VARCHAR(1024) NOT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE (user_id, target_type, target_id)
            )
        """)) {
            return false
        }

        if (!MigrationHelpers.createIndexIfNotExists(
            drv,
            "idx_user_target_favorites_user_type_id",
            "user_target_favorites",
            "user_id, target_type, target_id"
        )) {
            return false
        }

        return true
    }
}
