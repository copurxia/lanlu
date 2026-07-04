package lanlu.infrastructure.migrations.versions

import ace_orm.{Driver, DbValue, OrmException}
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

    public func up(drv: Driver): Bool {
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

        if (!MigrationHelpers.createTableIfNotExists(drv, "archive_page_metadata", createTableSql)) {
            return false
        }

        if (!MigrationHelpers.addColumnIfNotExists(drv, "archive_page_metadata", "entry_path", "TEXT NOT NULL DEFAULT ''")) { return false }
        if (!MigrationHelpers.addColumnIfNotExists(drv, "archive_page_metadata", "sort_index", "INT DEFAULT 0")) { return false }
        if (!MigrationHelpers.addColumnIfNotExists(drv, "archive_page_metadata", "hidden_in_files", "BOOLEAN DEFAULT false")) { return false }

        if (!backfillEntryPath(drv)) {
            return false
        }

        // 旧版本唯一约束是 (archive_id, page_number)，新版本改为 (archive_id, entry_path)
        if (oldPageNumberConstraintExists(drv)) {
            if (!MigrationHelpers.execUpdate(
                drv,
                "ALTER TABLE archive_page_metadata DROP CONSTRAINT archive_page_metadata_archive_id_page_number_key"
            )) {
                return false
            }
        }

        // 先删除旧索引定义，再创建新的 path 唯一索引
        if (MigrationHelpers.indexExists(drv, "idx_apm_archive_entry")) {
            if (!MigrationHelpers.execUpdate(drv, "DROP INDEX idx_apm_archive_entry")) {
                return false
            }
        }
        if (!MigrationHelpers.indexExists(drv, "idx_apm_archive_entry")) {
            if (!MigrationHelpers.execUpdate(
                drv,
                "CREATE UNIQUE INDEX idx_apm_archive_entry ON archive_page_metadata (archive_id, entry_path)"
            )) {
                return false
            }
        }
        if (!MigrationHelpers.createIndexIfNotExists(drv, "idx_apm_archive_id", "archive_page_metadata", "archive_id")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(drv, "idx_apm_archive_page", "archive_page_metadata", "archive_id, page_number")) {
            return false
        }
        if (!MigrationHelpers.createIndexIfNotExists(drv, "idx_apm_archive_sort", "archive_page_metadata", "archive_id, sort_index, page_number")) {
            return false
        }

        logger.info("V009 migration applied")
        return true
    }

    public func down(drv: Driver): Bool {
        return MigrationHelpers.execUpdate(drv, "DROP TABLE IF EXISTS archive_page_metadata")
    }

    private func backfillEntryPath(drv: Driver): Bool {
        try {
            // 查询需要回填的行(entry_path 为空)
            let rows = drv.query(
                "SELECT id, page_number FROM archive_page_metadata WHERE entry_path IS NULL OR LENGTH(entry_path) = 0 ORDER BY id",
                []
            )
            for (r in rows) {
                let id = r.getInt("id")
                let pageNo = Int32(r.getInt("page_number"))
                if (id <= 0) {
                    continue
                }
                let entryPath = if (pageNo > 0) { "__page_${pageNo}" } else { "__page_0" }
                drv.exec(
                    "UPDATE archive_page_metadata SET entry_path = $1 WHERE id = $2",
                    [DbText(entryPath), DbInt(id)]
                )
            }
            return true
        } catch (e: Exception) {
            logger.error("Failed to backfill entry_path in archive_page_metadata", ("error", e.message))
            return false
        }
    }

    private func oldPageNumberConstraintExists(drv: Driver): Bool {
        try {
            let rows = drv.query(
                "SELECT EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid WHERE t.relname = $1 AND c.conname = $2)",
                [DbText("archive_page_metadata"), DbText("archive_page_metadata_archive_id_page_number_key")]
            )
            if (rows.size > 0) {
                return rows[0].getBool("exists")
            }
            return false
        } catch (e: Exception) {
            logger.error("oldPageNumberConstraintExists failed: ${e.message}")
            return false
        }
    }
}