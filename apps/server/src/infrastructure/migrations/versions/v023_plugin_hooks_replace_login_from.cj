package lanlu.infrastructure.migrations.versions

import csorm.*
import lanlu.infrastructure.migrations.*

public class V023_PluginHooksReplaceLoginFrom <: Migration {
    public func version(): String {
        return "V023"
    }

    public func description(): String {
        return "Replace login_from with pre_hooks and after_hooks in plugins table"
    }

    public func up(db: Database): Bool {
        if (!MigrationHelpers.tableExists(db, "plugins")) {
            return true
        }

        if (!MigrationHelpers.addColumnIfNotExists(db, "plugins", "pre_hooks", "TEXT DEFAULT '[]'")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(db, "plugins", "after_hooks", "TEXT DEFAULT '[]'")) {
            return false
        }

        if (MigrationHelpers.columnExists(db, "plugins", "login_from")) {
            if (!MigrationHelpers.execUpdate(db, """
                UPDATE plugins
                SET pre_hooks = CASE
                    WHEN COALESCE(BTRIM(login_from), '') = '' THEN '[]'
                    ELSE to_jsonb(ARRAY[BTRIM(login_from)])::text
                END
                WHERE COALESCE(BTRIM(pre_hooks), '') = '' OR BTRIM(pre_hooks) = '[]'
            """)) {
                return false
            }
            if (!MigrationHelpers.execUpdate(db, "ALTER TABLE plugins DROP COLUMN IF EXISTS login_from")) {
                return false
            }
        }

        if (!MigrationHelpers.execUpdate(db, "UPDATE plugins SET pre_hooks = '[]' WHERE COALESCE(BTRIM(pre_hooks), '') = ''")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "UPDATE plugins SET after_hooks = '[]' WHERE COALESCE(BTRIM(after_hooks), '') = ''")) {
            return false
        }
        return true
    }
}
