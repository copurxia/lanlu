package lanlu.infrastructure.migrations.versions

import csorm.*
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

/**
 * V002: Tankoubon metadata + auto-create support
 * - Add cover_asset_id to tankoubons
 * - Add auto_created + source_category_id + source_relative_path for directory-based auto Tankoubons
 */
public class V002_TankoubonMetadataAndAutocreate <: Migration {
    private let logger = getLogger("migration_v002")

    public func version(): String {
        return "V002"
    }

    public func description(): String {
        return "Tankoubon metadata (cover) and directory auto-create source mapping"
    }

    public func up(db: Database): Bool {
        if (!MigrationHelpers.tableExists(db, "tankoubons")) {
            // Base schema not present; nothing to do here.
            return true
        }

        // Cover support (aligns with archives.cover_asset_id semantics).
        MigrationHelpers.addColumnIfNotExists(db, "tankoubons", "cover_asset_id", "BIGINT DEFAULT 0")

        // Auto-create bookkeeping (directory -> Tankoubon mapping).
        MigrationHelpers.addColumnIfNotExists(db, "tankoubons", "auto_created", "BOOLEAN DEFAULT false")
        MigrationHelpers.addColumnIfNotExists(db, "tankoubons", "source_category_id", "INTEGER")
        MigrationHelpers.addColumnIfNotExists(db, "tankoubons", "source_relative_path", "TEXT DEFAULT ''")

        MigrationHelpers.createIndexIfNotExists(db, "idx_tankoubons_cover_asset_id", "tankoubons", "cover_asset_id")
        MigrationHelpers.createIndexIfNotExists(db, "idx_tankoubons_auto_created", "tankoubons", "auto_created")

        // Unique constraint for auto-created Tankoubons per (category, relative_path).
        // Use a partial unique index so manual Tankoubons are unaffected.
        try {
            MigrationHelpers.execUpdate(db, """
                CREATE UNIQUE INDEX IF NOT EXISTS uniq_tankoubons_auto_source
                ON tankoubons (source_category_id, source_relative_path)
                WHERE auto_created = true AND COALESCE(source_relative_path, '') != ''
            """)
        } catch (_: Exception) {
            // Non-fatal.
        }

        logger.debug("V002 migration applied")
        return true
    }
}

