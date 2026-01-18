package lrr4cj.migrations.versions

import std.database.sql.*
import lrr4cj.migrations.*
import lrr4cj.utils.*

/**
 * V002: Task group KV store (DB-backed TaskGroupKVStore)
 */
public class V002_TaskGroupKV <: Migration {
    private let logger = getLogger("migration_v002")

    public func version(): String {
        return "V002"
    }

    public func description(): String {
        return "Create task_group_kv table for TaskGroupKVStore persistence"
    }

    public func up(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "task_group_kv")) {
            logger.debug("task_group_kv table already exists, checking columns")
            MigrationHelpers.addColumnIfNotExists(conn, "task_group_kv", "group_id", "VARCHAR(255) NOT NULL")
            MigrationHelpers.addColumnIfNotExists(conn, "task_group_kv", "k", "VARCHAR(255) NOT NULL")
            MigrationHelpers.addColumnIfNotExists(conn, "task_group_kv", "v", "TEXT NOT NULL")
            MigrationHelpers.addColumnIfNotExists(conn, "task_group_kv", "created_at", "BIGINT NOT NULL DEFAULT 0")
            MigrationHelpers.addColumnIfNotExists(conn, "task_group_kv", "ttl_seconds", "BIGINT NOT NULL DEFAULT 0")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_task_group_kv_group_id", "task_group_kv", "group_id")
            return true
        }

        logger.debug("Creating task_group_kv table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE task_group_kv (
                group_id VARCHAR(255) NOT NULL,
                k VARCHAR(255) NOT NULL,
                v TEXT NOT NULL,
                created_at BIGINT NOT NULL,
                ttl_seconds BIGINT NOT NULL DEFAULT 0,
                PRIMARY KEY (group_id, k)
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(conn, "idx_task_group_kv_group_id", "task_group_kv", "group_id")
        return true
    }
}

