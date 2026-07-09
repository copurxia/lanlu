package lanlu.contexts.system.infrastructure.persistence

import csorm.*
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
        let out: HashMap<String, String> = HashMap<String, String>()
        let logger = getLogger("db_meta_dao")

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<Row>("SELECT extname, extversion FROM pg_extension ORDER BY extname", [], { r => r })
                    for (row in rows) {
                        let name = row.getOrNullText(0) ?? ""
                        let version = row.getOrNullText(1) ?? ""
                        if (name.size > 0) {
                            out[name] = version
                        }
                    }
                } catch (e: Exception) {
                    logger.warn("Failed to query pg_extension", ("error", e.message))
                }
            case None =>
                logger.warn("Cannot get DB connection")
        }

        return out
    }
}