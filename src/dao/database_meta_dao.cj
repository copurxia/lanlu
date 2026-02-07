package lanlu.dao

import std.database.sql.*
import lanlu.config.*
import lanlu.utils.*
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

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("SELECT extname, extversion FROM pg_extension ORDER BY extname")
                    try {
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let name = rs.getOrNull<String>(0) ?? ""
                                let version = rs.getOrNull<String>(1) ?? ""
                                if (name.size > 0) {
                                    out[name] = version
                                }
                            }
                        } finally { rs.close() }
                    } finally { stmt.close() }
                } catch (e: Exception) {
                    getLogger("db_meta_dao").warn("Failed to query pg_extension", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                getLogger("db_meta_dao").warn("Cannot get DB connection")
        }

        return out
    }
}
