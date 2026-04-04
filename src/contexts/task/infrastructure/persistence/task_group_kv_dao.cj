package lanlu.contexts.task.infrastructure.persistence

import std.database.sql.*
import std.collection.*
import std.time.*
import std.convert.*
import lanlu.shared.config.*

/**
 * task_group_kv DAO
 *
 * 注意：不要 import lanlu.models.*，避免 dao <-> models 循环依赖。
 */
public class TaskGroupKVDao {
    private static func nowSeconds(): Int64 {
        return DateTime.now().toUnixTimeStamp().toSeconds()
    }

    private static func readNumericValue(conn: Connection, groupId: String, key: String): Int64 {
        let stmt = conn.prepareStatement("SELECT v FROM task_group_kv WHERE group_id=? AND k=?")
        try {
            stmt.set(0, groupId)
            stmt.set(1, key)
            let rs = stmt.query()
            try {
                if (rs.next()) {
                    let valueStr = rs.getOrNull<String>(0) ?? ""
                    return Int64.parse(valueStr)
                }
            } finally {
                rs.close()
            }
        } catch (_: Exception) {
            return -1
        } finally {
            stmt.close()
        }
        return -1
    }

    private static func getAnyConnection(): Option<Connection> {
        // Prefer pooled connections; fall back to direct connections if pool isn't ready yet.
        let pooled = DatabaseConfig.getPooledConnection()
        if (!pooled.isNone()) {
            return pooled
        }
        return DatabaseConfig.createConnection()
    }

    public static func cleanupExpiredGroup(groupId: String): Unit {
        let connOpt = getAnyConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        DELETE FROM task_group_kv
                        WHERE group_id=?
                          AND ttl_seconds > 0
                          AND (? - created_at) > ttl_seconds
                    """)
                    try {
                        stmt.set(0, groupId)
                        stmt.set(1, nowSeconds())
                        stmt.update()
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    // best-effort
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => ()
        }
    }

    public static func upsert(groupId: String, key: String, value: String, ttlSeconds: Int64): Bool {
        let connOpt = getAnyConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // Best-effort cleanup of expired entries in this group.
                    cleanupExpiredGroup(groupId)

                    let stmt = conn.prepareStatement("""
                        UPDATE task_group_kv
                        SET v = ?,
                            created_at = ?,
                            ttl_seconds = ?
                        WHERE group_id = ? AND k = ?
                    """)
                    let insertStmt = conn.prepareStatement("""
                        INSERT INTO task_group_kv (group_id, k, v, created_at, ttl_seconds)
                        SELECT ?, ?, ?, ?, ?
                        WHERE NOT EXISTS (
                            SELECT 1 FROM task_group_kv WHERE group_id = ? AND k = ?
                        )
                    """)
                    try {
                        let currentSeconds = nowSeconds()
                        stmt.set(0, value)
                        stmt.set(1, currentSeconds)
                        stmt.set(2, ttlSeconds)
                        stmt.set(3, groupId)
                        stmt.set(4, key)
                        let updated = stmt.update()
                        if (updated.rowCount <= 0) {
                            insertStmt.set(0, groupId)
                            insertStmt.set(1, key)
                            insertStmt.set(2, value)
                            insertStmt.set(3, currentSeconds)
                            insertStmt.set(4, ttlSeconds)
                            insertStmt.set(5, groupId)
                            insertStmt.set(6, key)
                            insertStmt.update()
                        }
                        return true
                    } finally {
                        stmt.close()
                        insertStmt.close()
                    }
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * Insert only when the key is absent. Returns true if inserted.
     */
    public static func insertIfAbsent(groupId: String, key: String, value: String, ttlSeconds: Int64): Bool {
        let connOpt = getAnyConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    cleanupExpiredGroup(groupId)
                    let stmt = conn.prepareStatement("""
                        INSERT INTO task_group_kv (group_id, k, v, created_at, ttl_seconds)
                        SELECT ?, ?, ?, ?, ?
                        WHERE NOT EXISTS (
                            SELECT 1 FROM task_group_kv WHERE group_id = ? AND k = ?
                        )
                    """)
                    try {
                        stmt.set(0, groupId)
                        stmt.set(1, key)
                        stmt.set(2, value)
                        stmt.set(3, nowSeconds())
                        stmt.set(4, ttlSeconds)
                        stmt.set(5, groupId)
                        stmt.set(6, key)
                        let updateResult = stmt.update()
                        return updateResult.rowCount > 0
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * Increment a numeric value stored in v. Returns the new value, or -1 on failure.
     */
    public static func increment(groupId: String, key: String, delta: Int64, ttlSeconds: Int64): Int64 {
        let connOpt = getAnyConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    cleanupExpiredGroup(groupId)
                    let updateStmt = conn.prepareStatement("""
                        UPDATE task_group_kv
                        SET v = (CAST(v AS BIGINT) + ?)::text,
                            created_at = ?,
                            ttl_seconds = ?
                        WHERE group_id = ? AND k = ?
                    """)
                    let insertStmt = conn.prepareStatement("""
                        INSERT INTO task_group_kv (group_id, k, v, created_at, ttl_seconds)
                        SELECT ?, ?, ?, ?, ?
                        WHERE NOT EXISTS (
                            SELECT 1 FROM task_group_kv WHERE group_id = ? AND k = ?
                        )
                    """)
                    try {
                        let currentSeconds = nowSeconds()
                        updateStmt.set(0, delta)
                        updateStmt.set(1, currentSeconds)
                        updateStmt.set(2, ttlSeconds)
                        updateStmt.set(3, groupId)
                        updateStmt.set(4, key)
                        let updated = updateStmt.update()
                        if (updated.rowCount > 0) {
                            return readNumericValue(conn, groupId, key)
                        }
                        insertStmt.set(0, groupId)
                        insertStmt.set(1, key)
                        insertStmt.set(2, delta.toString())
                        insertStmt.set(3, currentSeconds)
                        insertStmt.set(4, ttlSeconds)
                        insertStmt.set(5, groupId)
                        insertStmt.set(6, key)
                        let inserted = insertStmt.update()
                        if (inserted.rowCount > 0) {
                            return delta
                        }
                        return readNumericValue(conn, groupId, key)
                    } finally {
                        updateStmt.close()
                        insertStmt.close()
                    }
                } catch (_: Exception) {
                    return -1
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return -1
        }
    }

    public static func get(groupId: String, key: String): Option<String> {
        let connOpt = getAnyConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT v, created_at, ttl_seconds FROM task_group_kv WHERE group_id=? AND k=?"
                    )
                    try {
                        stmt.set(0, groupId)
                        stmt.set(1, key)
                        let rs = stmt.query()
                        try {
                            if (!rs.next()) {
                                return Option.None
                            }
                            let v = rs.getOrNull<String>(0) ?? ""
                            let createdAt = rs.getOrNull<Int64>(1) ?? 0
                            let ttl = rs.getOrNull<Int64>(2) ?? 0
                            if (ttl > 0 && (nowSeconds() - createdAt) > ttl) {
                                // Expired: delete and treat as missing.
                                let _ = delete(groupId, key)
                                return Option.None
                            }
                            return Option<String>.Some(v)
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return Option.None
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return Option.None
        }
    }

    public static func delete(groupId: String, key: String): Bool {
        let connOpt = getAnyConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("DELETE FROM task_group_kv WHERE group_id=? AND k=?")
                    try {
                        stmt.set(0, groupId)
                        stmt.set(1, key)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    public static func deleteGroup(groupId: String): Unit {
        let connOpt = getAnyConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("DELETE FROM task_group_kv WHERE group_id=?")
                    try {
                        stmt.set(0, groupId)
                        stmt.update()
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    // best-effort
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => ()
        }
    }

    public static func getKeys(groupId: String): Array<String> {
        let connOpt = getAnyConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    // Best-effort cleanup to avoid returning expired keys.
                    cleanupExpiredGroup(groupId)

                    let stmt = conn.prepareStatement("SELECT k FROM task_group_kv WHERE group_id=? ORDER BY k")
                    try {
                        stmt.set(0, groupId)
                        let rs = stmt.query()
                        try {
                            var keys = ArrayList<String>()
                            while (rs.next()) {
                                let k = rs.getOrNull<String>(0) ?? ""
                                if (k.size > 0) {
                                    keys.add(k)
                                }
                            }
                            return keys.toArray()
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return Array<String>()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return Array<String>()
        }
    }
}
