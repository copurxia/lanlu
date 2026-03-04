package lanlu.infrastructure.migrations.versions

import std.database.sql.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

/**
 * V009: 创建 archive_page_metadata 表
 * 用于存储页面级元数据（标题、描述、缩略图、排序与显示控制）
 */
public class V009_ArchivePageMetadata <: Migration {
    private let logger = getLogger("migration_v009")

    public func version(): String {
        return "V009"
    }

    public func description(): String {
        return "Create archive_page_metadata table for page-level metadata"
    }

    public func up(conn: Connection): Bool {
        let createTableSql = """
            CREATE TABLE IF NOT EXISTS archive_page_metadata (
                id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                archive_id BIGINT NOT NULL,
                page_number INT NOT NULL,
                entry_path TEXT NOT NULL DEFAULT '',
                title VARCHAR(512) DEFAULT '',
                description TEXT DEFAULT '',
                sort_index INT DEFAULT 0,
                hidden_in_files BOOLEAN DEFAULT false,
                thumb_asset_id BIGINT DEFAULT 0,
                thumbhash VARCHAR(128) DEFAULT '',
                extra_data JSONB DEFAULT '{}',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """

        if (!MigrationHelpers.createTableIfNotExists(conn, "archive_page_metadata", createTableSql)) {
            return false
        }

        if (!MigrationHelpers.addColumnIfNotExists(conn, "archive_page_metadata", "entry_path", "TEXT NOT NULL DEFAULT ''")) { return false }
        if (!MigrationHelpers.addColumnIfNotExists(conn, "archive_page_metadata", "sort_index", "INT DEFAULT 0")) { return false }
        if (!MigrationHelpers.addColumnIfNotExists(conn, "archive_page_metadata", "hidden_in_files", "BOOLEAN DEFAULT false")) { return false }

        if (!backfillEntryPath(conn)) {
            return false
        }

        // 旧版本唯一约束是 (archive_id, page_number)，新版本改为 (archive_id, entry_path)
        if (oldPageNumberConstraintExists(conn)) {
            if (!MigrationHelpers.execUpdate(
                conn,
                "ALTER TABLE archive_page_metadata DROP CONSTRAINT archive_page_metadata_archive_id_page_number_key"
            )) {
                return false
            }
        }

        // 先删除旧索引定义，再创建新的 path 唯一索引
        if (MigrationHelpers.indexExists(conn, "idx_apm_archive_entry")) {
            if (!MigrationHelpers.execUpdate(conn, "DROP INDEX idx_apm_archive_entry")) {
                return false
            }
        }
        if (!MigrationHelpers.indexExists(conn, "idx_apm_archive_entry")) {
            if (!MigrationHelpers.execUpdate(
                conn,
                "CREATE UNIQUE INDEX idx_apm_archive_entry ON archive_page_metadata (archive_id, entry_path)"
            )) {
                return false
            }
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_apm_archive_id", "archive_page_metadata", "archive_id")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_apm_archive_page", "archive_page_metadata", "archive_id, page_number")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(conn, "idx_apm_archive_sort", "archive_page_metadata", "archive_id, sort_index, page_number")) {
            return false
        }

        logger.info("V009 migration applied")
        return true
    }

    public func down(conn: Connection): Bool {
        return MigrationHelpers.execUpdate(conn, "DROP TABLE IF EXISTS archive_page_metadata")
    }

    private func backfillEntryPath(conn: Connection): Bool {
        try {
            let queryStmt = conn.prepareStatement(
                "SELECT id, page_number FROM archive_page_metadata WHERE entry_path IS NULL OR LENGTH(entry_path) = 0 ORDER BY id"
            )
            try {
                let updateStmt = conn.prepareStatement(
                    "UPDATE archive_page_metadata SET entry_path = ? WHERE id = ?"
                )
                try {
                    let rs = queryStmt.query()
                    try {
                        while (rs.next()) {
                            let id = rs.getOrNull<Int64>(0) ?? 0
                            let pageNo = rs.getOrNull<Int32>(1) ?? 0
                            if (id <= 0) {
                                continue
                            }
                            let entryPath = if (pageNo > 0) { "__page_${pageNo}" } else { "__page_0" }
                            updateStmt.set(0, entryPath)
                            updateStmt.set(1, id)
                            let _ = updateStmt.update()
                        }
                    } finally {
                        rs.close()
                    }
                } finally {
                    updateStmt.close()
                }
            } finally {
                queryStmt.close()
            }
            return true
        } catch (e: Exception) {
            logger.error("Failed to backfill entry_path in archive_page_metadata", ("error", e.message))
            return false
        }
    }

    private func oldPageNumberConstraintExists(conn: Connection): Bool {
        let stmt = conn.prepareStatement(
            "SELECT EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid WHERE t.relname = ? AND c.conname = ?)"
        )
        try {
            stmt.set(0, "archive_page_metadata")
            stmt.set(1, "archive_page_metadata_archive_id_page_number_key")
            let rs = stmt.query()
            try {
                if (rs.next()) {
                    try {
                        return rs.getOrNull<Bool>(0) ?? false
                    } catch (_: Exception) {
                        let n = rs.getOrNull<Int32>(0) ?? 0
                        return n != 0
                    }
                }
                return false
            } finally {
                rs.close()
            }
        } finally {
            stmt.close()
        }
    }
}
