package lanlu.contexts.system.infrastructure.persistence

import ace_orm.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import std.collection.*

/**
 * DB metadata queries (extensions, etc.)
 */
public class DatabaseMetaDao {
    /**
     * Return installed extensions as a map: extname -> extversion.
     * Best-effort: returns empty map on any error.
     */
    public static func getInstalledExtensions(): HashMap<String, String> {
        var out: HashMap<String, String> = HashMap<String, String>()
        try {
            let rows = DatabaseConfig.driver().query("SELECT extname, extversion FROM pg_extension ORDER BY extname", [])
            for (r in rows) {
                let name = r.getText("extname")
                let version = r.getText("extversion")
                if (name.size > 0) {
                    out[name] = version
                }
            }
        } catch (e: Exception) {
            getLogger("db_meta_dao").warn("Failed to query pg_extension", ("error", e.message))
        }
        return out
    }
}