package lanlu.infrastructure.migrations.versions

import csorm.*
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

    public func up(db: Database): Bool {
        let createTableSql = """
            CREATE TABLE IF NOT EXISTS archive_page_metadata (
                id BIGSERIAL PRIMARY KEY,
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

        if (!MigrationHelpers.createTableIfNotExists(db, "archive_page_metadata", createTableSql)) {
            return false
        }

        if (!MigrationHelpers.addColumnIfNotExists(db, "archive_page_metadata", "entry_path", "TEXT NOT NULL DEFAULT ''")) { return false }
        if (!MigrationHelpers.addColumnIfNotExists(db, "archive_page_metadata", "sort_index", "INT DEFAULT 0")) { return false }
        if (!MigrationHelpers.addColumnIfNotExists(db, "archive_page_metadata", "hidden_in_files", "BOOLEAN DEFAULT false")) { return false }

        if (!backfillEntryPath(db)) {
            return false
        }

        // 旧版本唯一约束是 (archive_id, page_number)，新版本改为 (archive_id, entry_path)
        if (oldPageNumberConstraintExists(db)) {
            if (!MigrationHelpers.execUpdate(
                db,
                "ALTER TABLE archive_page_metadata DROP CONSTRAINT archive_page_metadata_archive_id_page_number_key"
            )) {
                return false
            }
        }

        // 先删除旧索引定义，再创建新的 path 唯一索引
        if (MigrationHelpers.indexExists(db, "idx_apm_archive_entry")) {
            if (!MigrationHelpers.execUpdate(db, "DROP INDEX idx_apm_archive_entry")) {
                return false
            }
        }
        if (!MigrationHelpers.indexExists(db, "idx_apm_archive_entry")) {
            if (!MigrationHelpers.execUpdate(
                db,
                "CREATE UNIQUE INDEX idx_apm_archive_entry ON archive_page_metadata (archive_id, entry_path)"
            )) {
                return false
            }
        }
        if (!MigrationHelpers.createIndexIfNotExists(db, "idx_apm_archive_id", "archive_page_metadata", "archive_id")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(db, "idx_apm_archive_page", "archive_page_metadata", "archive_id, page_number")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(db, "idx_apm_archive_sort", "archive_page_metadata", "archive_id, sort_index, page_number")) {
            return false
        }

        logger.info("V009 migration applied")
        return true
    }

    public func down(db: Database): Bool {
        return MigrationHelpers.execUpdate(db, "DROP TABLE IF EXISTS archive_page_metadata")
    }

    private func backfillEntryPath(db: Database): Bool {
        try {
            let rows = db.raw<(Int64, Int32)>(
                "SELECT id, page_number FROM archive_page_metadata WHERE entry_path IS NULL OR LENGTH(entry_path) = 0 ORDER BY id",
                [],
                { row => (row.getInt64(0), row.getInt32(1)) }
            )
            for ((id, pageNo) in rows) {
                if (id <= 0) { continue }
                let entryPath = if (pageNo > 0) { "__page_${pageNo}" } else { "__page_0" }
                db.execRaw(
                    "UPDATE archive_page_metadata SET entry_path = $1 WHERE id = $2",
                    [vtext(entryPath), vint(id)]
                )
            }
            return true
        } catch (e: Exception) {
            logger.error("Failed to backfill entry_path in archive_page_metadata", ("error", e.message))
            return false
        }
    }

    private func oldPageNumberConstraintExists(db: Database): Bool {
        match (db.rawOne<Bool>(
            "SELECT EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid WHERE t.relname = $1 AND c.conname = $2)",
            [vtext("archive_page_metadata"), vtext("archive_page_metadata_archive_id_page_number_key")],
            { row => row.getOrNullBool(0) ?? false }
        )) {
            case Some(b) => b
            case None => false
        }
    }
}
