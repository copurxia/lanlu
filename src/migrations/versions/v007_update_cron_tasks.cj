package lrr4cj.migrations.versions

import std.database.sql.*
import lrr4cj.migrations.*
import lrr4cj.utils.*

/**
 * V007: Update legacy scheduled task types after task runner rename/removal.
 *
 * - scheduled_tasks.task_type 'clear_thumbhash' -> 'regenerate_cover'
 * - scheduled_tasks.task_parameters updated to full regeneration defaults
 */
public class V007_UpdateCronTasks <: Migration {
    private let logger = getLogger("migration_v007")

    public func version(): String {
        return "V007"
    }

    public func description(): String {
        return "Update legacy cron tasks: clear_thumbhash -> regenerate_cover"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "scheduled_tasks")) {
            return true
        }

        // Best-effort update. Keep it idempotent: running twice should be safe.
        let params = "{\"mode\":\"all\",\"deleteOldCover\":true,\"batchSize\":200}"
        let ok = MigrationHelpers.execUpdate(conn, """
            UPDATE scheduled_tasks
            SET task_type = 'regenerate_cover',
                name = '重生成封面',
                task_parameters = '${params}',
                updated_at = CURRENT_TIMESTAMP
            WHERE task_type = 'clear_thumbhash'
        """)

        if (ok) {
            logger.debug("scheduled_tasks clear_thumbhash migrated to regenerate_cover")
        }
        return ok
    }
}

