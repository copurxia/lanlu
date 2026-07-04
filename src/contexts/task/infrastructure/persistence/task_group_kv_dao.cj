package lanlu.contexts.task.infrastructure.persistence

import ace_orm.*
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

    private static func readNumericValue(groupId: String, key: String): Int64 {
        try {
            let rows = DatabaseConfig.driver().query("SELECT v FROM task_group_kv WHERE group_id=$1 AND k=$2", [DbText(groupId), DbText(key)])
            if (rows.size > 0) {
                let valueStr = rows[0].getText("v")
                return Int64.parse(valueStr)
            }
        } catch (_: Exception) {
            return -1
        }
        return -1
    }

    public static func cleanupExpiredGroup(groupId: String): Unit {
        try {
            DatabaseConfig.driver().exec("""
                DELETE FROM task_group_kv
                WHERE group_id=$1
                  AND ttl_seconds > 0
                  AND ($2 - created_at) > ttl_seconds
            """, [DbText(groupId), DbInt(nowSeconds())])
        } catch (_: Exception) {
            // best-effort
        }
    }

    public static func upsert(groupId: String, key: String, value: String, ttlSeconds: Int64): Bool {
        try {
            // Best-effort cleanup of expired entries in this group.
            cleanupExpiredGroup(groupId)

            let currentSeconds = nowSeconds()
            let updated = DatabaseConfig.driver().exec("""
                UPDATE task_group_kv
                SET v = $1,
                    created_at = $2,
                    ttl_seconds = $3
                WHERE group_id = $4 AND k = $5
            """, [DbText(value), DbInt(currentSeconds), DbInt(ttlSeconds), DbText(groupId), DbText(key)])
            if (updated <= 0) {
                DatabaseConfig.driver().exec("""
                    INSERT INTO task_group_kv (group_id, k, v, created_at, ttl_seconds)
                    SELECT $1, $2, $3, $4, $5
                    WHERE NOT EXISTS (
                        SELECT 1 FROM task_group_kv WHERE group_id = $6 AND k = $7
                    )
                """, [DbText(groupId), DbText(key), DbText(value), DbInt(currentSeconds), DbInt(ttlSeconds), DbText(groupId), DbText(key)])
            }
            return true
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * Insert only when the key is absent. Returns true if inserted.
     */
    public static func insertIfAbsent(groupId: String, key: String, value: String, ttlSeconds: Int64): Bool {
        try {
            cleanupExpiredGroup(groupId)
            let updateResult = DatabaseConfig.driver().exec("""
                INSERT INTO task_group_kv (group_id, k, v, created_at, ttl_seconds)
                SELECT $1, $2, $3, $4, $5
                WHERE NOT EXISTS (
                    SELECT 1 FROM task_group_kv WHERE group_id = $6 AND k = $7
                )
            """, [DbText(groupId), DbText(key), DbText(value), DbInt(nowSeconds()), DbInt(ttlSeconds), DbText(groupId), DbText(key)])
            return updateResult > 0
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * Increment a numeric value stored in v. Returns the new value, or -1 on failure.
     */
    public static func increment(groupId: String, key: String, delta: Int64, ttlSeconds: Int64): Int64 {
        try {
            cleanupExpiredGroup(groupId)
            let currentSeconds = nowSeconds()
            let updated = DatabaseConfig.driver().exec("""
                UPDATE task_group_kv
                SET v = (CAST(v AS BIGINT) + $1)::text,
                    created_at = $2,
                    ttl_seconds = $3
                WHERE group_id = $4 AND k = $5
            """, [DbInt(delta), DbInt(currentSeconds), DbInt(ttlSeconds), DbText(groupId), DbText(key)])
            if (updated > 0) {
                return readNumericValue(groupId, key)
            }
            let inserted = DatabaseConfig.driver().exec("""
                INSERT INTO task_group_kv (group_id, k, v, created_at, ttl_seconds)
                SELECT $1, $2, $3, $4, $5
                WHERE NOT EXISTS (
                    SELECT 1 FROM task_group_kv WHERE group_id = $6 AND k = $7
                )
            """, [DbText(groupId), DbText(key), DbText(delta.toString()), DbInt(currentSeconds), DbInt(ttlSeconds), DbText(groupId), DbText(key)])
            if (inserted > 0) {
                return delta
            }
            return readNumericValue(groupId, key)
        } catch (_: Exception) {
            return -1
        }
    }

    public static func get(groupId: String, key: String): Option<String> {
        try {
            let rows = DatabaseConfig.driver().query(
                "SELECT v, created_at, ttl_seconds FROM task_group_kv WHERE group_id=$1 AND k=$2",
                [DbText(groupId), DbText(key)]
            )
            if (rows.size == 0) {
                return Option.None
            }
            let r = rows[0]
            let v = r.getText("v")
            let createdAt = r.getInt("created_at")
            let ttl = r.getInt("ttl_seconds")
            if (ttl > 0 && (nowSeconds() - createdAt) > ttl) {
                // Expired: delete and treat as missing.
                let _ = delete(groupId, key)
                return Option.None
            }
            return Option<String>.Some(v)
        } catch (_: Exception) {
            return Option.None
        }
    }

    public static func delete(groupId: String, key: String): Bool {
        try {
            DatabaseConfig.driver().exec("DELETE FROM task_group_kv WHERE group_id=$1 AND k=$2", [DbText(groupId), DbText(key)])
            return true
        } catch (_: Exception) {
            return false
        }
    }

    public static func deleteGroup(groupId: String): Unit {
        try {
            DatabaseConfig.driver().exec("DELETE FROM task_group_kv WHERE group_id=$1", [DbText(groupId)])
        } catch (_: Exception) {
            // best-effort
        }
    }

    public static func getKeys(groupId: String): Array<String> {
        try {
            // Best-effort cleanup to avoid returning expired keys.
            cleanupExpiredGroup(groupId)

            let rows = DatabaseConfig.driver().query("SELECT k FROM task_group_kv WHERE group_id=$1 ORDER BY k", [DbText(groupId)])
            var keys = ArrayList<String>()
            for (r in rows) {
                let k = r.getText("k")
                if (k.size > 0) {
                    keys.add(k)
                }
            }
            return keys.toArray()
        } catch (_: Exception) {
            return Array<String>()
        }
    }
}