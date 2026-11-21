package lanlu.infrastructure.migrations.versions

import csorm.*
import lanlu.infrastructure.migrations.*

/**
 * V017: Add persisted taskpool state-model columns for richer waiting semantics and active-task dedupe.
 */
public class V017_TaskpoolStateModel <: Migration {
    public func version(): String {
        return "V017"
    }

    public func description(): String {
        return "Add task phase, waiting_reason, and active_key columns"
    }

    public func up(db: Database): Bool {
        if (!MigrationHelpers.tableExists(db, "tasks")) {
            return false
        }

        if (!MigrationHelpers.addColumnIfNotExists(db, "tasks", "phase", "VARCHAR(80)")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(db, "tasks", "waiting_reason", "VARCHAR(80)")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(db, "tasks", "active_key", "VARCHAR(255)")) {
            return false
        }

        if (!MigrationHelpers.createIndexIfNotExists(db, "idx_tasks_active_key_status", "tasks", "active_key, status")) {
            return false
        }

        if (!MigrationHelpers.execUpdate(db, """
            UPDATE tasks
            SET phase = CASE
                WHEN status = 'pending' THEN 'queued'
                WHEN status = 'running' THEN 'executing'
                WHEN status = 'waiting' THEN 'waiting'
                WHEN status = 'completed' THEN 'completed'
                WHEN status = 'failed' THEN 'failed'
                WHEN status = 'stopped' THEN 'stopped'
                ELSE phase
            END
            WHERE phase IS NULL
        """)) {
            return false
        }

        if (!MigrationHelpers.execUpdate(db, """
            UPDATE tasks
            SET waiting_reason = 'task_dependency'
            WHERE status = 'waiting' AND wait_for_task_id IS NOT NULL AND waiting_reason IS NULL
        """)) {
            return false
        }

        return true
    }
}
