package lanlu_client_next.storage

import rocksdb_ffi.{RocksDb, RocksDbColumnFamily, RocksDbOperationResult}
import std.convert.Parsable

// ---- 数据库 schema 版本与幂等迁移 ----
// 设置 DB 与缓存 DB 各自维护独立 schema version（meta CF 的 `db-schema` key）。
// 迁移按步骤执行，每步完成写 marker（`migrate:{step}`），任一步骤崩溃后重跑时
// 已完成的步骤直接跳过，保证幂等。
//
// 缓存 DB 的迁移只做「旧格式 → 新格式」的搬运与清理，失败允许丢弃并回源（缓存可重建）；
// 设置 DB 迁移绝不能静默回默认并覆盖旧数据（见 ServerRepository 的 v2→v3 迁移）。

public let SETTINGS_DB_SCHEMA: Int64 = 3
public let CACHE_DB_SCHEMA: Int64 = 1

private let SCHEMA_KEY = "db-schema".toArray()

public class DbSchema {
    private let db: RocksDb
    private let meta: RocksDbColumnFamily

    public init(db: RocksDb, meta: RocksDbColumnFamily) {
        this.db = db
        this.meta = meta
    }

    // 当前版本：无记录视为 0（全新库）。
    public func currentVersion(): Int64 {
        match (db.getBytesResult(meta, SCHEMA_KEY)) {
            case RocksDbOperationResult<Array<UInt8>>.Ok(v) =>
                let text = try {
                    String.fromUtf8(v)
                } catch (_: Exception) {
                    ""
                }
                return parseVersion(text)
            case _ => return 0
        }
    }

    // 写入版本（迁移全部完成后调用）。
    public func writeVersion(version: Int64): Bool {
        try {
            let _ = db.putBytesResult(meta, SCHEMA_KEY, "v${version}".toArray())
            return true
        } catch (_: Exception) {
            return false
        }
    }

    // 步骤 marker 已写：跳过该步骤（幂等重跑）。
    public func stepDone(step: String): Bool {
        try {
            match (db.getBytesResult(meta, "migrate:${step}".toArray())) {
                case RocksDbOperationResult<Array<UInt8>>.Ok(_) => return true
                case _ => return false
            }
        } catch (_: Exception) {
            return false
        }
    }

    public func markStepDone(step: String): Bool {
        try {
            let _ = db.putBytesResult(meta, "migrate:${step}".toArray(), "done".toArray())
            return true
        } catch (_: Exception) {
            return false
        }
    }

    // 删除所有迁移 marker 与版本（仅供测试/重建）。
    public func clearAll(): Unit {
        try {
            let _ = db.deleteBytesResult(meta, SCHEMA_KEY)
        } catch (_: Exception) {}
    }

    private static func parseVersion(text: String): Int64 {
        if (!text.startsWith("v")) {
            return 0
        }
        try {
            return Int64.parse(text[1..text.size])
        } catch (_: Exception) {
            return 0
        }
    }
}
