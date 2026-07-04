package lanlu.infrastructure.migrations.versions

import ace_orm.{Driver, DbValue}
import lanlu.infrastructure.migrations.*

public class V023_PluginHooksReplaceLoginFrom <: Migration {
    public func version(): String {
        return "V023"
    }

    public func description(): String {
        return "Replace login_from with pre_hooks and after_hooks in plugins table"
    }

    public func up(drv: Driver): Bool {
        if (!MigrationHelpers.tableExists(drv, "plugins")) {
            return true
        }

        if (!MigrationHelpers.addColumnIfNotExists(drv, "plugins", "pre_hooks", "TEXT DEFAULT '[]'")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(drv, "plugins", "after_hooks", "TEXT DEFAULT '[]'")) {
            return false
        }

        if (MigrationHelpers.columnExists(drv, "plugins", "login_from")) {
            if (!MigrationHelpers.execUpdate(drv, """
                UPDATE plugins
                SET pre_hooks = CASE
                    WHEN COALESCE(BTRIM(login_from), '') = '' THEN '[]'
                    ELSE to_jsonb(ARRAY[BTRIM(login_from)])::text
                END
                WHERE COALESCE(BTRIM(pre_hooks), '') = '' OR BTRIM(pre_hooks) = '[]'
            """)) {
                return false
            }
            if (!MigrationHelpers.execUpdate(drv, "ALTER TABLE plugins DROP COLUMN IF EXISTS login_from")) {
                return false
            }
        }

        if (!MigrationHelpers.execUpdate(drv, "UPDATE plugins SET pre_hooks = '[]' WHERE COALESCE(BTRIM(pre_hooks), '') = ''")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(drv, "UPDATE plugins SET after_hooks = '[]' WHERE COALESCE(BTRIM(after_hooks), '') = ''")) {
            return false
        }
        return true
    }
}
