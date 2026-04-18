package lanlu.infrastructure.migrations.versions

import std.database.sql.*
import lanlu.infrastructure.migrations.*

public class V023_PluginHooksReplaceLoginFrom <: Migration {
    public func version(): String {
        return "023"
    }

    public func description(): String {
        return "Replace login_from with pre_hooks and after_hooks in plugins table"
    }

    public func up(conn: Connection): Bool {
        if (!MigrationHelpers.tableExists(conn, "plugins")) {
            return true
        }

        if (!MigrationHelpers.addColumnIfNotExists(conn, "plugins", "pre_hooks", "TEXT DEFAULT '[]'")) {
            return false
        }
        if (!MigrationHelpers.addColumnIfNotExists(conn, "plugins", "after_hooks", "TEXT DEFAULT '[]'")) {
            return false
        }

        if (MigrationHelpers.columnExists(conn, "plugins", "login_from")) {
            if (!MigrationHelpers.execUpdate(conn, """
                UPDATE plugins
                SET pre_hooks = CASE
                    WHEN COALESCE(BTRIM(login_from), '') = '' THEN '[]'
                    ELSE to_jsonb(ARRAY[BTRIM(login_from)])::text
                END
                WHERE COALESCE(BTRIM(pre_hooks), '') = '' OR BTRIM(pre_hooks) = '[]'
            """)) {
                return false
            }
            if (!MigrationHelpers.execUpdate(conn, "ALTER TABLE plugins DROP COLUMN IF EXISTS login_from")) {
                return false
            }
        }

        if (!MigrationHelpers.execUpdate(conn, "UPDATE plugins SET pre_hooks = '[]' WHERE COALESCE(BTRIM(pre_hooks), '') = ''")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(conn, "UPDATE plugins SET after_hooks = '[]' WHERE COALESCE(BTRIM(after_hooks), '') = ''")) {
            return false
        }
        return true
    }
}
