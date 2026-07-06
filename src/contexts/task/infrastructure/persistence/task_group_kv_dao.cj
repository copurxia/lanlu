package lanlu.contexts.task.infrastructure.persistence

import csorm.*
import postgresql_driver.*
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

    private static func readNumericValue(db: Database, groupId: String, key: String): Int64 {
        let sql = "SELECT v FROM task_group_kv WHERE group_id=$1 AND k=$2"
        let params: Array<Value> = [vtext(groupId), vtext(key)]
        try {
            let vOpt = db.rawOne<String>(sql, params, { row => row.getOrNullText(0) ?? "" })
            match (vOpt) {
                case Some(valueStr) =>
                    if (valueStr.size > 0) {
                        return Int64.parse(valueStr)
                    }
                case None => ()
            }
        } catch (_: Exception) {
            return -1
        }
        return -1
    }

    public static func cleanupExpiredGroup(groupId: String): Unit {
        let sql = """
            DELETE FROM task_group_kv
            WHERE group_id=$1
              AND ttl_seconds > 0
              AND ($2 - created_at) > ttl_seconds
        """
        let params: Array<Value> = [vtext(groupId), vint(nowSeconds())]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                } catch (_: Exception) {
                    // best-effort
                }
            case None => ()
        }
    }

    public static func upsert(groupId: String, key: String, value: String, ttlSeconds: Int64): Bool {
        let updateSql = """
            UPDATE task_group_kv
            SET v = $1,
                created_at = $2,
                ttl_seconds = $3
            WHERE group_id = $4 AND k = $5
        """
        let insertSql = """
            INSERT INTO task_group_kv (group_id, k, v, created_at, ttl_seconds)
            SELECT $1, $2, $3, $4, $5
            WHERE NOT EXISTS (
                SELECT 1 FROM task_group_kv WHERE group_id = $6 AND k = $7
            )
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    // Best-effort cleanup of expired entries in this group.
                    cleanupExpiredGroup(groupId)

                    let currentSeconds = nowSeconds()
                    let updateParams: Array<Value> = [
                        vtext(value),
                        vint(currentSeconds),
                        vint(ttlSeconds),
                        vtext(groupId),
                        vtext(key)
                    ]
                    let updated = db.execRaw(updateSql, updateParams)
                    if (updated <= 0) {
                        let insertParams: Array<Value> = [
                            vtext(groupId),
                            vtext(key),
                            vtext(value),
                            vint(currentSeconds),
                            vint(ttlSeconds),
                            vtext(groupId),
                            vtext(key)
                        ]
                        db.execRaw(insertSql, insertParams)
                    }
                    return true
                } catch (_: Exception) {
                    return false
                }
            case None => return false
        }
    }

    /**
     * Insert only when the key is absent. Returns true if inserted.
     */
    public static func insertIfAbsent(groupId: String, key: String, value: String, ttlSeconds: Int64): Bool {
        let sql = """
            INSERT INTO task_group_kv (group_id, k, v, created_at, ttl_seconds)
            SELECT $1, $2, $3, $4, $5
            WHERE NOT EXISTS (
                SELECT 1 FROM task_group_kv WHERE group_id = $6 AND k = $7
            )
        """
        let params: Array<Value> = [
            vtext(groupId),
            vtext(key),
            vtext(value),
            vint(nowSeconds()),
            vint(ttlSeconds),
            vtext(groupId),
            vtext(key)
        ]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    cleanupExpiredGroup(groupId)
                    let affected = db.execRaw(sql, params)
                    return affected > 0
                } catch (_: Exception) {
                    return false
                }
            case None => return false
        }
    }

    /**
     * Increment a numeric value stored in v. Returns the new value, or -1 on failure.
     */
    public static func increment(groupId: String, key: String, delta: Int64, ttlSeconds: Int64): Int64 {
        let updateSql = """
            UPDATE task_group_kv
            SET v = (CAST(v AS BIGINT) + $1)::text,
                created_at = $2,
                ttl_seconds = $3
            WHERE group_id = $4 AND k = $5
        """
        let insertSql = """
            INSERT INTO task_group_kv (group_id, k, v, created_at, ttl_seconds)
            SELECT $1, $2, $3, $4, $5
            WHERE NOT EXISTS (
                SELECT 1 FROM task_group_kv WHERE group_id = $6 AND k = $7
            )
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    cleanupExpiredGroup(groupId)
                    let currentSeconds = nowSeconds()
                    let updateParams: Array<Value> = [
                        vint(delta),
                        vint(currentSeconds),
                        vint(ttlSeconds),
                        vtext(groupId),
                        vtext(key)
                    ]
                    let updated = db.execRaw(updateSql, updateParams)
                    if (updated > 0) {
                        return readNumericValue(db, groupId, key)
                    }
                    let insertParams: Array<Value> = [
                        vtext(groupId),
                        vtext(key),
                        vtext(delta.toString()),
                        vint(currentSeconds),
                        vint(ttlSeconds),
                        vtext(groupId),
                        vtext(key)
                    ]
                    let inserted = db.execRaw(insertSql, insertParams)
                    if (inserted > 0) {
                        return delta
                    }
                    return readNumericValue(db, groupId, key)
                } catch (_: Exception) {
                    return -1
                }
            case None => return -1
        }
    }

    public static func get(groupId: String, key: String): Option<String> {
        let sql = "SELECT v, created_at, ttl_seconds FROM task_group_kv WHERE group_id=$1 AND k=$2"
        let params: Array<Value> = [vtext(groupId), vtext(key)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rowOpt = db.rawOne<(String, Int64, Int64)>(sql, params, { row =>
                        (row.getOrNullText(0) ?? "", row.getOrNullInt64(1) ?? 0, row.getOrNullInt64(2) ?? 0)
                    })
                    match (rowOpt) {
                        case Some((v, createdAt, ttl)) =>
                            if (ttl > 0 && (nowSeconds() - createdAt) > ttl) {
                                // Expired: delete and treat as missing.
                                let _ = delete(groupId, key)
                                return Option.None
                            }
                            return Option<String>.Some(v)
                        case None =>
                            return Option.None
                    }
                } catch (_: Exception) {
                    return Option.None
                }
            case None => return Option.None
        }
    }

    public static func delete(groupId: String, key: String): Bool {
        let sql = "DELETE FROM task_group_kv WHERE group_id=$1 AND k=$2"
        let params: Array<Value> = [vtext(groupId), vtext(key)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (_: Exception) {
                    return false
                }
            case None => return false
        }
    }

    public static func deleteGroup(groupId: String): Unit {
        let sql = "DELETE FROM task_group_kv WHERE group_id=$1"
        let params: Array<Value> = [vtext(groupId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                } catch (_: Exception) {
                    // best-effort
                }
            case None => ()
        }
    }

    public static func getKeys(groupId: String): Array<String> {
        let sql = "SELECT k FROM task_group_kv WHERE group_id=$1 ORDER BY k"
        let params: Array<Value> = [vtext(groupId)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    // Best-effort cleanup to avoid returning expired keys.
                    cleanupExpiredGroup(groupId)

                    let rows = db.raw<String>(sql, params, { row => row.getOrNullText(0) ?? "" })
                    var keys = ArrayList<String>()
                    for (k in rows) {
                        if (k.size > 0) {
                            keys.add(k)
                        }
                    }
                    return keys.toArray()
                } catch (_: Exception) {
                    return Array<String>()
                }
            case None => return Array<String>()
        }
    }
}