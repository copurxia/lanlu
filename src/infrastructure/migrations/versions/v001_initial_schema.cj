package lanlu.infrastructure.migrations.versions

import ace_orm.{Driver, DbValue}
import lanlu.infrastructure.migrations.*
import lanlu.shared.utils.*

/**
 * V001: 初始数据库 schema
 * 创建所有核心表（基线迁移）
 */
public class V001_InitialSchema <: Migration {
    private let logger = getLogger("migration_v001")

    public func version(): String {
        return "V001"
    }

    public func description(): String {
        return "Initial database schema with all core tables"
    }

    public func up(drv: Driver): Bool {
        // 按依赖顺序创建所有表

        // 1. users 表
        if (!createUsersTable(drv)) { return false }

        // 2. user_tokens 表
        if (!createUserTokensTable(drv)) { return false }

        // 3. plugins 表
        if (!createPluginsTable(drv)) { return false }

        // 4. categories 表
        if (!createCategoriesTable(drv)) { return false }

        // 5. archives 表（依赖 categories）
        if (!createArchivesTable(drv)) { return false }

        // 6. tags 表
        if (!createTagsTable(drv)) { return false }

        // 7. archive_tags 表（依赖 archives, tags）
        if (!createArchiveTagsTable(drv)) { return false }

        // 8. user_archive_status 表（依赖 users, archives）
        if (!createUserArchiveStatusTable(drv)) { return false }

        // 9. user_favorites 表（依赖 users, archives）
        if (!createUserFavoritesTable(drv)) { return false }

        // 10. smart_filters 表
        if (!createSmartFiltersTable(drv)) { return false }

        // 11. tankoubons 表
        if (!createTankoubonsTable(drv)) { return false }

        // 12. tankoubon_archives 表（依赖 tankoubons, archives）
        if (!createTankoubonArchivesTable(drv)) { return false }

        // 13. tankoubon_tags 表（依赖 tankoubons, tags）
        if (!createTankoubonTagsTable(drv)) { return false }

        // 14. user_tankoubon_favorites 表（依赖 users, tankoubons）
        if (!createUserTankoubonFavoritesTable(drv)) { return false }

        // 15. tasks 表
        if (!createTasksTable(drv)) { return false }

        // 16. scheduled_tasks 表
        if (!createScheduledTasksTable(drv)) { return false }

        // 17. assets 表（通用资源表）
        if (!createAssetsTable(drv)) { return false }

        // 18. system_settings 表
        if (!createSystemSettingsTable(drv)) { return false }

        // 19. archives_with_tags 视图
        if (!createArchivesWithTagsView(drv)) { return false }

        return true
    }

    // ========== 表创建方法 ==========

    private func createUsersTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "users")) {
            logger.debug("users table already exists, checking columns")
            MigrationHelpers.addColumnIfNotExists(drv, "users", "password_salt", "VARCHAR(64) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(drv, "users", "password_hash_version", "VARCHAR(32) NOT NULL DEFAULT 'sha256_v1'")
            MigrationHelpers.addColumnIfNotExists(drv, "users", "updated_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
            MigrationHelpers.addColumnIfNotExists(drv, "users", "avatar_asset_id", "BIGINT")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_users_avatar_asset_id", "users", "avatar_asset_id")
            return true
        }

        logger.debug("Creating users table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE users (
                id SERIAL PRIMARY KEY,
                username VARCHAR(64) NOT NULL UNIQUE,
                password_salt VARCHAR(64) NOT NULL,
                password_hash TEXT NOT NULL,
                password_hash_version VARCHAR(32) NOT NULL DEFAULT 'sha256_v1',
                avatar_asset_id BIGINT,
                is_admin BOOLEAN DEFAULT false,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(drv, "idx_users_avatar_asset_id", "users", "avatar_asset_id")
        return true
    }

    private func createUserTokensTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "user_tokens")) {
            logger.debug("user_tokens table already exists, checking columns")
            // 添加可能缺失的列
            MigrationHelpers.addColumnIfNotExists(drv, "user_tokens", "name", "VARCHAR(255) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(drv, "user_tokens", "token_type", "VARCHAR(50) NOT NULL DEFAULT 'session'")
            MigrationHelpers.addColumnIfNotExists(drv, "user_tokens", "token_prefix", "VARCHAR(16) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(drv, "user_tokens", "token_hash", "VARCHAR(128) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(drv, "user_tokens", "last_used_at", "TIMESTAMP")
            MigrationHelpers.addColumnIfNotExists(drv, "user_tokens", "revoked_at", "TIMESTAMP")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_user_tokens_user_id", "user_tokens", "user_id")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_user_tokens_token_hash", "user_tokens", "token_hash")
            return true
        }

        logger.debug("Creating user_tokens table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE user_tokens (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL,
                name VARCHAR(255) NOT NULL DEFAULT '',
                token_type VARCHAR(50) NOT NULL DEFAULT 'session',
                token_prefix VARCHAR(16) NOT NULL DEFAULT '',
                token_hash VARCHAR(128) NOT NULL DEFAULT '',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_used_at TIMESTAMP,
                revoked_at TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(drv, "idx_user_tokens_user_id", "user_tokens", "user_id")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_user_tokens_token_hash", "user_tokens", "token_hash")
        return true
    }

    private func createPluginsTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "plugins")) {
            logger.debug("plugins table already exists, checking columns")
            // 添加可能缺失的列
            let columnsToAdd = [
                ("namespace", "VARCHAR(100) NOT NULL DEFAULT ''"),
                ("description", "TEXT DEFAULT ''"),
                ("author", "VARCHAR(255) DEFAULT ''"),
                ("entry", "VARCHAR(255) DEFAULT ''"),
                ("plugin_type", "VARCHAR(50) DEFAULT ''"),
                ("tags", "TEXT DEFAULT ''"),
                ("url_regex", "TEXT DEFAULT ''"),
                ("source_id_regex", "TEXT DEFAULT ''"),
                ("pre_hooks", "TEXT DEFAULT '[]'"),
                ("after_hooks", "TEXT DEFAULT '[]'"),
                ("permissions", "TEXT DEFAULT ''"),
                ("icon", "TEXT DEFAULT ''"),
                ("enabled", "BOOLEAN DEFAULT false"),
                ("installed", "BOOLEAN DEFAULT false"),
                ("has_schema", "BOOLEAN DEFAULT false"),
                ("parameters", "TEXT DEFAULT '[]'"),
                ("update_url", "TEXT DEFAULT ''"),
                ("created_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"),
                ("updated_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
            ]
            for ((col, def) in columnsToAdd) {
                MigrationHelpers.addColumnIfNotExists(drv, "plugins", col, def)
            }
            return true
        }

        logger.debug("Creating plugins table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE plugins (
                id SERIAL PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                version VARCHAR(50) NOT NULL,
                namespace VARCHAR(100) NOT NULL DEFAULT '',
                description TEXT DEFAULT '',
                author VARCHAR(255) DEFAULT '',
                entry VARCHAR(255) DEFAULT '',
                plugin_type VARCHAR(50) DEFAULT '',
                tags TEXT DEFAULT '',
                url_regex TEXT DEFAULT '',
                source_id_regex TEXT DEFAULT '',
                pre_hooks TEXT DEFAULT '[]',
                after_hooks TEXT DEFAULT '[]',
                permissions TEXT DEFAULT '',
                icon TEXT DEFAULT '',
                enabled BOOLEAN DEFAULT false,
                installed BOOLEAN DEFAULT false,
                has_schema BOOLEAN DEFAULT false,
                parameters TEXT DEFAULT '[]',
                update_url TEXT DEFAULT '',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)) {
            return false
        }
        return true
    }

    private func createCategoriesTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "categories")) {
            logger.debug("categories table already exists, checking columns")
            MigrationHelpers.addColumnIfNotExists(drv, "categories", "plugins", "TEXT DEFAULT '[]'")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_categories_catid", "categories", "catid")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_categories_enabled", "categories", "enabled")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_categories_sort_order", "categories", "sort_order")
            return true
        }

        logger.debug("Creating categories table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE categories (
                id SERIAL PRIMARY KEY,
                catid VARCHAR(255) NOT NULL UNIQUE,
                name VARCHAR(255) NOT NULL,
                scan_path TEXT NOT NULL,
                description TEXT DEFAULT '',
                icon VARCHAR(64) DEFAULT '',
                sort_order INTEGER DEFAULT 0,
                enabled BOOLEAN DEFAULT true,
                plugins TEXT DEFAULT '[]',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(drv, "idx_categories_catid", "categories", "catid")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_categories_enabled", "categories", "enabled")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_categories_sort_order", "categories", "sort_order")
        return true
    }

    private func createArchivesTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "archives")) {
            logger.debug("archives table already exists, checking columns and indexes")
            MigrationHelpers.addColumnIfNotExists(drv, "archives", "cover_asset_id", "BIGINT")
            // 添加 title_tsv 列（全文搜索）
            if (!MigrationHelpers.columnExists(drv, "archives", "title_tsv")) {
                try {
                    MigrationHelpers.execUpdate(drv, """
                        ALTER TABLE archives ADD COLUMN title_tsv tsvector
                        GENERATED ALWAYS AS (
                            setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
                            setweight(to_tsvector('simple', coalesce(filename, '')), 'B')
                        ) STORED
                    """)
                } catch (_: Exception) {}
            }
            // 创建索引
            MigrationHelpers.createIndexIfNotExists(drv, "idx_archives_category_id", "archives", "category_id")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_archives_cover_asset_id", "archives", "cover_asset_id")
            if (!MigrationHelpers.indexExists(drv, "idx_archives_title_tsv")) {
                try {
                    MigrationHelpers.execUpdate(drv, "CREATE INDEX idx_archives_title_tsv ON archives USING GIN (title_tsv)")
                } catch (_: Exception) {}
            }
            return true
        }

        logger.debug("Creating archives table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE archives (
                id SERIAL PRIMARY KEY,
                arcid VARCHAR(255) NOT NULL UNIQUE,
                title VARCHAR(1024) DEFAULT '',
                filename VARCHAR(1024) NOT NULL,
                summary TEXT DEFAULT '',
                thumbhash TEXT DEFAULT '',
                cover_asset_id BIGINT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                relative_path TEXT DEFAULT '',
                file_size BIGINT DEFAULT 0,
                pagecount INTEGER DEFAULT 0,
                archive_type VARCHAR(20) DEFAULT 'archive',
                category_id INTEGER NOT NULL,
                FOREIGN KEY (category_id) REFERENCES categories(id)
            )
        """)) {
            return false
        }

        // 添加 title_tsv 列
        try {
            MigrationHelpers.execUpdate(drv, """
                ALTER TABLE archives ADD COLUMN title_tsv tsvector
                GENERATED ALWAYS AS (
                    setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
                    setweight(to_tsvector('simple', coalesce(filename, '')), 'B')
                ) STORED
            """)
        } catch (_: Exception) {}

        // 创建索引
        MigrationHelpers.createIndexIfNotExists(drv, "idx_archives_category_id", "archives", "category_id")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_archives_cover_asset_id", "archives", "cover_asset_id")
        try {
            MigrationHelpers.execUpdate(drv, "CREATE INDEX idx_archives_title_tsv ON archives USING GIN (title_tsv)")
        } catch (_: Exception) {}

        return true
    }

    private func createTagsTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "tags")) {
            logger.debug("tags table already exists")
            MigrationHelpers.addColumnIfNotExists(drv, "tags", "icon_asset_id", "BIGINT")
            MigrationHelpers.addColumnIfNotExists(drv, "tags", "background_asset_id", "BIGINT")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_tags_namespace", "tags", "namespace")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_tags_name", "tags", "name")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_tags_icon_asset_id", "tags", "icon_asset_id")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_tags_background_asset_id", "tags", "background_asset_id")
            return true
        }

        logger.debug("Creating tags table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE tags (
                id SERIAL PRIMARY KEY,
                namespace VARCHAR(64) NOT NULL DEFAULT '',
                name VARCHAR(255) NOT NULL,
                translations JSONB NOT NULL DEFAULT '{}',
                icon_asset_id BIGINT,
                background_asset_id BIGINT,
                links TEXT DEFAULT '',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE (namespace, name)
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(drv, "idx_tags_namespace", "tags", "namespace")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_tags_name", "tags", "name")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_tags_icon_asset_id", "tags", "icon_asset_id")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_tags_background_asset_id", "tags", "background_asset_id")
        return true
    }

    private func createArchiveTagsTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "archive_tags")) {
            logger.debug("archive_tags table already exists")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_archive_tags_archive_id", "archive_tags", "archive_id")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_archive_tags_tag_id", "archive_tags", "tag_id")
            return true
        }

        logger.debug("Creating archive_tags table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE archive_tags (
                archive_id INTEGER NOT NULL,
                tag_id INTEGER NOT NULL,
                PRIMARY KEY (archive_id, tag_id),
                FOREIGN KEY (archive_id) REFERENCES archives(id) ON DELETE CASCADE,
                FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(drv, "idx_archive_tags_archive_id", "archive_tags", "archive_id")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_archive_tags_tag_id", "archive_tags", "tag_id")
        return true
    }

    private func createUserArchiveStatusTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "user_archive_status")) {
            logger.debug("user_archive_status table already exists")
            MigrationHelpers.addColumnIfNotExists(drv, "user_archive_status", "progress", "INTEGER DEFAULT 0")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_user_archive_status_user_id", "user_archive_status", "user_id")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_user_archive_status_archive_id", "user_archive_status", "archive_id")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_user_archive_status_progress", "user_archive_status", "progress")
            return true
        }

        logger.debug("Creating user_archive_status table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE user_archive_status (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL,
                archive_id INTEGER NOT NULL,
                is_new BOOLEAN DEFAULT true,
                progress INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE (user_id, archive_id),
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (archive_id) REFERENCES archives(id) ON DELETE CASCADE
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(drv, "idx_user_archive_status_user_id", "user_archive_status", "user_id")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_user_archive_status_archive_id", "user_archive_status", "archive_id")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_user_archive_status_progress", "user_archive_status", "progress")
        return true
    }

    private func createUserFavoritesTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "user_favorites")) {
            logger.debug("user_favorites table already exists")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_user_favorites_user_id", "user_favorites", "user_id")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_user_favorites_archive_id", "user_favorites", "archive_id")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_user_favorites_created_at", "user_favorites", "created_at")
            return true
        }

        logger.debug("Creating user_favorites table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE user_favorites (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL,
                archive_id INTEGER NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE (user_id, archive_id),
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (archive_id) REFERENCES archives(id) ON DELETE CASCADE
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(drv, "idx_user_favorites_user_id", "user_favorites", "user_id")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_user_favorites_archive_id", "user_favorites", "archive_id")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_user_favorites_created_at", "user_favorites", "created_at")
        return true
    }

    private func createSmartFiltersTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "smart_filters")) {
            logger.debug("smart_filters table already exists")
            return true
        }

        logger.debug("Creating smart_filters table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE smart_filters (
                id SERIAL PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                translations JSONB NOT NULL DEFAULT '{}',
                icon VARCHAR(64) DEFAULT '',
                query TEXT DEFAULT '',
                sort_by VARCHAR(64) DEFAULT '',
                sort_order VARCHAR(16) DEFAULT 'desc',
                date_from VARCHAR(32) DEFAULT '',
                date_to VARCHAR(32) DEFAULT '',
                newonly BOOLEAN DEFAULT false,
                untaggedonly BOOLEAN DEFAULT false,
                sort_order_num INTEGER DEFAULT 0,
                enabled BOOLEAN DEFAULT true,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)) {
            return false
        }

        // 插入默认的智能分类
        MigrationHelpers.execUpdate(drv, """
            INSERT INTO smart_filters (name, translations, icon, newonly, sort_order_num)
            VALUES ('未读档案', '{"en": {"text": "Unread Archives"}}', 'BookOpen', true, 1)
        """)
        MigrationHelpers.execUpdate(drv, """
            INSERT INTO smart_filters (name, translations, icon, untaggedonly, sort_order_num)
            VALUES ('无标签档案', '{"en": {"text": "Untagged Archives"}}', 'Tag', true, 2)
        """)
        MigrationHelpers.execUpdate(drv, """
            INSERT INTO smart_filters (name, translations, icon, date_from, sort_by, sort_order, sort_order_num)
            VALUES ('最近一周', '{"en": {"text": "Last Week"}}', 'Calendar', '-7', 'date_added', 'desc', 3)
        """)
        return true
    }

    private func createTankoubonsTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "tankoubons")) {
            logger.debug("tankoubons table already exists")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_tankoubons_tankoubon_id", "tankoubons", "tankoubon_id")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_tankoubons_name", "tankoubons", "name")
            return true
        }

        logger.debug("Creating tankoubons table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE tankoubons (
                id SERIAL PRIMARY KEY,
                tankoubon_id VARCHAR(255) NOT NULL UNIQUE,
                name VARCHAR(1024) NOT NULL,
                summary TEXT DEFAULT '',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(drv, "idx_tankoubons_tankoubon_id", "tankoubons", "tankoubon_id")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_tankoubons_name", "tankoubons", "name")
        return true
    }

    private func createTankoubonArchivesTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "tankoubon_archives")) {
            logger.debug("tankoubon_archives table already exists")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_tankoubon_archives_tankoubon_id", "tankoubon_archives", "tankoubon_id")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_tankoubon_archives_archive_id", "tankoubon_archives", "archive_id")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_tankoubon_archives_sort_order", "tankoubon_archives", "sort_order")
            return true
        }

        logger.debug("Creating tankoubon_archives table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE tankoubon_archives (
                id SERIAL PRIMARY KEY,
                tankoubon_id INTEGER NOT NULL,
                archive_id INTEGER NOT NULL,
                sort_order INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE (tankoubon_id, archive_id),
                FOREIGN KEY (tankoubon_id) REFERENCES tankoubons(id) ON DELETE CASCADE,
                FOREIGN KEY (archive_id) REFERENCES archives(id) ON DELETE CASCADE
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(drv, "idx_tankoubon_archives_tankoubon_id", "tankoubon_archives", "tankoubon_id")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_tankoubon_archives_archive_id", "tankoubon_archives", "archive_id")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_tankoubon_archives_sort_order", "tankoubon_archives", "sort_order")
        return true
    }

    private func createTankoubonTagsTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "tankoubon_tags")) {
            logger.debug("tankoubon_tags table already exists")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_tankoubon_tags_tankoubon_id", "tankoubon_tags", "tankoubon_id")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_tankoubon_tags_tag_id", "tankoubon_tags", "tag_id")
            return true
        }

        logger.debug("Creating tankoubon_tags table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE tankoubon_tags (
                tankoubon_id INTEGER NOT NULL,
                tag_id INTEGER NOT NULL,
                PRIMARY KEY (tankoubon_id, tag_id),
                FOREIGN KEY (tankoubon_id) REFERENCES tankoubons(id) ON DELETE CASCADE,
                FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(drv, "idx_tankoubon_tags_tankoubon_id", "tankoubon_tags", "tankoubon_id")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_tankoubon_tags_tag_id", "tankoubon_tags", "tag_id")
        return true
    }

    private func createUserTankoubonFavoritesTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "user_tankoubon_favorites")) {
            logger.debug("user_tankoubon_favorites table already exists")
            return true
        }

        logger.debug("Creating user_tankoubon_favorites table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE user_tankoubon_favorites (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL,
                tankoubon_id INTEGER NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE (user_id, tankoubon_id),
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (tankoubon_id) REFERENCES tankoubons(id) ON DELETE CASCADE
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(drv, "idx_user_tankoubon_favorites_user_id", "user_tankoubon_favorites", "user_id")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_user_tankoubon_favorites_tankoubon_id", "user_tankoubon_favorites", "tankoubon_id")
        return true
    }

    private func createTasksTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "tasks")) {
            logger.debug("tasks table already exists, checking columns")
            // 添加可能缺失的列
            MigrationHelpers.addColumnIfNotExists(drv, "tasks", "message", "TEXT")
            MigrationHelpers.addColumnIfNotExists(drv, "tasks", "priority", "INTEGER NOT NULL DEFAULT 50")
            MigrationHelpers.addColumnIfNotExists(drv, "tasks", "group_id", "VARCHAR(255)")
            MigrationHelpers.addColumnIfNotExists(drv, "tasks", "timeout_at", "TIMESTAMP")
            MigrationHelpers.addColumnIfNotExists(drv, "tasks", "trigger_source", "VARCHAR(50)")
            MigrationHelpers.addColumnIfNotExists(drv, "tasks", "wait_for_task_id", "BIGINT DEFAULT NULL")
            MigrationHelpers.addColumnIfNotExists(drv, "tasks", "phase", "VARCHAR(80)")
            MigrationHelpers.addColumnIfNotExists(drv, "tasks", "waiting_reason", "VARCHAR(80)")
            MigrationHelpers.addColumnIfNotExists(drv, "tasks", "active_key", "VARCHAR(255)")
            createTasksIndexes(drv)
            return true
        }

        logger.debug("Creating tasks table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE tasks (
                id SERIAL PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                task_type VARCHAR(100) NOT NULL,
                status VARCHAR(50) NOT NULL DEFAULT 'pending',
                progress INTEGER DEFAULT 0,
                message TEXT,
                plugin_namespace VARCHAR(100),
                parameters TEXT,
                result TEXT,
                priority INTEGER NOT NULL DEFAULT 50,
                group_id VARCHAR(255),
                timeout_at TIMESTAMP,
                trigger_source VARCHAR(50),
                wait_for_task_id BIGINT DEFAULT NULL,
                phase VARCHAR(80),
                waiting_reason VARCHAR(80),
                active_key VARCHAR(255),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                started_at TIMESTAMP,
                completed_at TIMESTAMP
            )
        """)) {
            return false
        }
        createTasksIndexes(drv)
        return true
    }

    private func createTasksIndexes(drv: Driver): Unit {
        // TaskPool 领取 pending：WHERE status='pending' ORDER BY priority, created_at, id
        MigrationHelpers.createIndexIfNotExists(
            drv,
            "idx_tasks_status_priority_created_id",
            "tasks",
            "status, priority, created_at, id"
        )
        // 依赖任务：WHERE wait_for_task_id=? AND status='waiting'
        MigrationHelpers.createIndexIfNotExists(
            drv,
            "idx_tasks_wait_for_status",
            "tasks",
            "wait_for_task_id, status"
        )
        // group 查询：WHERE group_id=? ORDER BY created_at
        MigrationHelpers.createIndexIfNotExists(
            drv,
            "idx_tasks_group_created_at",
            "tasks",
            "group_id, created_at"
        )
        MigrationHelpers.createIndexIfNotExists(
            drv,
            "idx_tasks_active_key_status",
            "tasks",
            "active_key, status"
        )
    }

    private func createScheduledTasksTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "scheduled_tasks")) {
            logger.debug("scheduled_tasks table already exists, checking columns")
            // 添加可能缺失的列
            MigrationHelpers.addColumnIfNotExists(drv, "scheduled_tasks", "task_parameters", "TEXT")
            MigrationHelpers.addColumnIfNotExists(drv, "scheduled_tasks", "priority", "INTEGER NOT NULL DEFAULT 50")
            MigrationHelpers.addColumnIfNotExists(drv, "scheduled_tasks", "timeout_seconds", "INTEGER NOT NULL DEFAULT 3600")
            MigrationHelpers.addColumnIfNotExists(drv, "scheduled_tasks", "last_run_status", "VARCHAR(20)")
            MigrationHelpers.addColumnIfNotExists(drv, "scheduled_tasks", "last_error", "TEXT")
            MigrationHelpers.addColumnIfNotExists(drv, "scheduled_tasks", "run_count", "INTEGER NOT NULL DEFAULT 0")
            MigrationHelpers.addColumnIfNotExists(drv, "scheduled_tasks", "success_count", "INTEGER NOT NULL DEFAULT 0")
            MigrationHelpers.addColumnIfNotExists(drv, "scheduled_tasks", "failure_count", "INTEGER NOT NULL DEFAULT 0")
            MigrationHelpers.addColumnIfNotExists(drv, "scheduled_tasks", "created_by", "VARCHAR(100)")
            MigrationHelpers.addColumnIfNotExists(drv, "scheduled_tasks", "updated_by", "VARCHAR(100)")
            return true
        }

        logger.debug("Creating scheduled_tasks table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE scheduled_tasks (
                id SERIAL PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                cron_expression VARCHAR(255) NOT NULL,
                task_type VARCHAR(50) NOT NULL,
                task_parameters TEXT,
                enabled BOOLEAN NOT NULL DEFAULT TRUE,
                priority INTEGER NOT NULL DEFAULT 50,
                timeout_seconds INTEGER NOT NULL DEFAULT 3600,
                last_run_at TIMESTAMP,
                last_run_status VARCHAR(20),
                last_error TEXT,
                next_run_at TIMESTAMP,
                run_count INTEGER NOT NULL DEFAULT 0,
                success_count INTEGER NOT NULL DEFAULT 0,
                failure_count INTEGER NOT NULL DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                created_by VARCHAR(100),
                updated_by VARCHAR(100)
            )
        """)) {
            return false
        }
        return true
    }

    private func createAssetsTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "assets")) {
            logger.debug("assets table already exists, checking columns")
            MigrationHelpers.addColumnIfNotExists(drv, "assets", "owner_user_id", "BIGINT")
            MigrationHelpers.addColumnIfNotExists(drv, "assets", "kind", "VARCHAR(50) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(drv, "assets", "original_filename", "VARCHAR(1024) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(drv, "assets", "content_type", "VARCHAR(255) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(drv, "assets", "file_ext", "VARCHAR(32) NOT NULL DEFAULT 'bin'")
            MigrationHelpers.addColumnIfNotExists(drv, "assets", "byte_size", "BIGINT NOT NULL DEFAULT 0")
            MigrationHelpers.addColumnIfNotExists(drv, "assets", "thumbhash", "TEXT NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(drv, "assets", "created_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_assets_owner_user_id", "assets", "owner_user_id")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_assets_kind", "assets", "kind")
            return true
        }

        logger.debug("Creating assets table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE assets (
                id SERIAL PRIMARY KEY,
                owner_user_id BIGINT,
                kind VARCHAR(50) NOT NULL DEFAULT '',
                original_filename VARCHAR(1024) NOT NULL DEFAULT '',
                content_type VARCHAR(255) NOT NULL DEFAULT '',
                file_ext VARCHAR(32) NOT NULL DEFAULT 'bin',
                byte_size BIGINT NOT NULL DEFAULT 0,
                thumbhash TEXT NOT NULL DEFAULT '',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(drv, "idx_assets_owner_user_id", "assets", "owner_user_id")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_assets_kind", "assets", "kind")
        return true
    }

    private func createSystemSettingsTable(drv: Driver): Bool {
        if (MigrationHelpers.tableExists(drv, "system_settings")) {
            logger.debug("system_settings table already exists, checking columns")
            // 添加可能缺失的列
            MigrationHelpers.addColumnIfNotExists(drv, "system_settings", "value_type", "VARCHAR(50) NOT NULL DEFAULT 'string'")
            MigrationHelpers.addColumnIfNotExists(drv, "system_settings", "category", "VARCHAR(100) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(drv, "system_settings", "description", "JSONB DEFAULT '{}'")
            MigrationHelpers.addColumnIfNotExists(drv, "system_settings", "is_encrypted", "BOOLEAN DEFAULT false")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_system_settings_category", "system_settings", "category")
            MigrationHelpers.createIndexIfNotExists(drv, "idx_system_settings_key", "system_settings", "key")
            return true
        }

        logger.debug("Creating system_settings table")
        if (!MigrationHelpers.execUpdate(drv, """
            CREATE TABLE system_settings (
                id SERIAL PRIMARY KEY,
                key VARCHAR(255) NOT NULL UNIQUE,
                value TEXT NOT NULL,
                value_type VARCHAR(50) NOT NULL DEFAULT 'string',
                category VARCHAR(100) NOT NULL DEFAULT '',
                description JSONB DEFAULT '{}',
                is_encrypted BOOLEAN DEFAULT false,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(drv, "idx_system_settings_category", "system_settings", "category")
        MigrationHelpers.createIndexIfNotExists(drv, "idx_system_settings_key", "system_settings", "key")
        return true
    }

    private func createArchivesWithTagsView(drv: Driver): Bool {
        // 总是重建视图以确保结构正确
        if (MigrationHelpers.viewExists(drv, "archives_with_tags")) {
            logger.debug("Dropping existing archives_with_tags view")
            MigrationHelpers.execUpdate(drv, "DROP VIEW archives_with_tags")
        }

        logger.debug("Creating archives_with_tags view")
        return MigrationHelpers.execUpdate(drv, """
            CREATE VIEW archives_with_tags AS
            SELECT
                a.id,
                a.arcid,
                a.filename,
                a.title,
                a.summary,
                a.thumbhash,
                a.cover_asset_id,
                a.created_at,
                a.updated_at,
                a.relative_path,
                a.file_size,
                a.pagecount,
                a.archive_type,
                a.category_id,
                COALESCE(string_agg(
                    CASE WHEN t.namespace != '' AND t.namespace IS NOT NULL
                         THEN t.namespace || ':' || t.name
                         ELSE t.name
                    END, ',' ORDER BY t.namespace, t.name), '') AS tags,
                a.title_tsv ||
                    setweight(to_tsvector('simple', COALESCE(string_agg(
                        CASE WHEN t.namespace != '' AND t.namespace IS NOT NULL
                             THEN t.namespace || ' ' || t.name
                             ELSE t.name
                        END, ' '), '')), 'C') AS search_tsv
            FROM archives a
            LEFT JOIN archive_tags atg ON atg.archive_id = a.id
            LEFT JOIN tags t ON t.id = atg.tag_id
            GROUP BY
                a.id, a.arcid, a.filename, a.title, a.summary, a.thumbhash, a.cover_asset_id,
                a.created_at, a.updated_at, a.relative_path, a.file_size,
                a.pagecount, a.archive_type, a.category_id, a.title_tsv
        """)
    }
}
