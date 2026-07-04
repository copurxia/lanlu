package lanlu.infrastructure.migrations.versions

import ace_orm.{Driver, DbValue}
import lanlu.infrastructure.migrations.*

/**
 * V016: Drop legacy PostgreSQL-backed task_group_kv table after migrating task KV to RocksDB.
 */
public class V016_DropTaskGroupKv <: Migration {
    public func version(): String {
        return "V016"
    }

    public func description(): String {
        return "Drop legacy task_group_kv table"
    }

    public func up(drv: Driver): Bool {
        if (!MigrationHelpers.tableExists(drv, "task_group_kv")) {
            return true
        }
        return MigrationHelpers.execUpdate(drv, "DROP TABLE IF EXISTS task_group_kv")
    }
}
