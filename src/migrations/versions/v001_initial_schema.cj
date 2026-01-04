package lrr4cj.migrations.versions

import std.database.sql.*
import lrr4cj.migrations.*
import lrr4cj.utils.*

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

    public func up(conn: Connection): Bool {
        // 按依赖顺序创建所有表

        // 1. users 表
        if (!createUsersTable(conn)) { return false }

        // 2. user_tokens 表
        if (!createUserTokensTable(conn)) { return false }

        // 3. plugins 表
        if (!createPluginsTable(conn)) { return false }

        // 4. categories 表
        if (!createCategoriesTable(conn)) { return false }

        // 5. archives 表（依赖 categories）
        if (!createArchivesTable(conn)) { return false }

        // 6. tags 表
        if (!createTagsTable(conn)) { return false }

        // 7. archive_tags 表（依赖 archives, tags）
        if (!createArchiveTagsTable(conn)) { return false }

        // 8. user_archive_status 表（依赖 users, archives）
        if (!createUserArchiveStatusTable(conn)) { return false }

        // 9. user_favorites 表（依赖 users, archives）
        if (!createUserFavoritesTable(conn)) { return false }

        // 10. smart_filters 表
        if (!createSmartFiltersTable(conn)) { return false }

        // 11. tankoubons 表
        if (!createTankoubonsTable(conn)) { return false }

        // 12. tankoubon_archives 表（依赖 tankoubons, archives）
        if (!createTankoubonArchivesTable(conn)) { return false }

        // 13. tankoubon_tags 表（依赖 tankoubons, tags）
        if (!createTankoubonTagsTable(conn)) { return false }

        // 14. user_tankoubon_favorites 表（依赖 users, tankoubons）
        if (!createUserTankoubonFavoritesTable(conn)) { return false }

        // 15. tasks 表
        if (!createTasksTable(conn)) { return false }

        // 16. scheduled_tasks 表
        if (!createScheduledTasksTable(conn)) { return false }

        // 17. system_settings 表
        if (!createSystemSettingsTable(conn)) { return false }

        // 18. archives_with_tags 视图
        if (!createArchivesWithTagsView(conn)) { return false }

        return true
    }

    // ========== 表创建方法 ==========

    private func createUsersTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "users")) {
            logger.debug("users table already exists, checking columns")
            MigrationHelpers.addColumnIfNotExists(conn, "users", "password_salt", "VARCHAR(64) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(conn, "users", "updated_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
            return true
        }

        logger.debug("Creating users table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE users (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                username VARCHAR(64) NOT NULL UNIQUE,
                password_salt VARCHAR(64) NOT NULL,
                password_hash VARCHAR(64) NOT NULL,
                is_admin BOOLEAN DEFAULT false,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)) {
            return false
        }
        return true
    }

    private func createUserTokensTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "user_tokens")) {
            logger.debug("user_tokens table already exists, checking columns")
            // 添加可能缺失的列
            MigrationHelpers.addColumnIfNotExists(conn, "user_tokens", "name", "VARCHAR(255) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(conn, "user_tokens", "token_type", "VARCHAR(50) NOT NULL DEFAULT 'session'")
            MigrationHelpers.addColumnIfNotExists(conn, "user_tokens", "token_prefix", "VARCHAR(16) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(conn, "user_tokens", "token_hash", "VARCHAR(128) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(conn, "user_tokens", "last_used_at", "TIMESTAMP")
            MigrationHelpers.addColumnIfNotExists(conn, "user_tokens", "revoked_at", "TIMESTAMP")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_user_tokens_user_id", "user_tokens", "user_id")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_user_tokens_token_hash", "user_tokens", "token_hash")
            return true
        }

        logger.debug("Creating user_tokens table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE user_tokens (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
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
        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_tokens_user_id", "user_tokens", "user_id")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_tokens_token_hash", "user_tokens", "token_hash")
        return true
    }

    private func createPluginsTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "plugins")) {
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
                ("login_from", "VARCHAR(100) DEFAULT ''"),
                ("permissions", "TEXT DEFAULT ''"),
                ("icon", "TEXT DEFAULT ''"),
                ("enabled", "BOOLEAN DEFAULT false"),
                ("installed", "BOOLEAN DEFAULT false"),
                ("has_schema", "BOOLEAN DEFAULT false"),
                ("parameters", "TEXT DEFAULT '[]'"),
                ("created_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"),
                ("updated_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
            ]
            for ((col, def) in columnsToAdd) {
                MigrationHelpers.addColumnIfNotExists(conn, "plugins", col, def)
            }
            return true
        }

        logger.debug("Creating plugins table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE plugins (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                name VARCHAR(255) NOT NULL,
                version VARCHAR(50) NOT NULL,
                namespace VARCHAR(100) NOT NULL DEFAULT '',
                description TEXT DEFAULT '',
                author VARCHAR(255) DEFAULT '',
                entry VARCHAR(255) DEFAULT '',
                plugin_type VARCHAR(50) DEFAULT '',
                tags TEXT DEFAULT '',
                url_regex TEXT DEFAULT '',
                login_from VARCHAR(100) DEFAULT '',
                permissions TEXT DEFAULT '',
                icon TEXT DEFAULT '',
                enabled BOOLEAN DEFAULT false,
                installed BOOLEAN DEFAULT false,
                has_schema BOOLEAN DEFAULT false,
                parameters TEXT DEFAULT '[]',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)) {
            return false
        }
        return true
    }

    private func createCategoriesTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "categories")) {
            logger.debug("categories table already exists, checking columns")
            MigrationHelpers.addColumnIfNotExists(conn, "categories", "plugins", "TEXT DEFAULT '[]'")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_categories_catid", "categories", "catid")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_categories_enabled", "categories", "enabled")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_categories_sort_order", "categories", "sort_order")
            return true
        }

        logger.debug("Creating categories table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE categories (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
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
        MigrationHelpers.createIndexIfNotExists(conn, "idx_categories_catid", "categories", "catid")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_categories_enabled", "categories", "enabled")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_categories_sort_order", "categories", "sort_order")
        return true
    }

    private func createArchivesTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "archives")) {
            logger.debug("archives table already exists, checking columns and indexes")
            // 添加 title_tsv 列（全文搜索）
            if (!MigrationHelpers.columnExists(conn, "archives", "title_tsv")) {
                try {
                    MigrationHelpers.execUpdate(conn, """
                        ALTER TABLE archives ADD COLUMN title_tsv tsvector
                        GENERATED ALWAYS AS (
                            setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
                            setweight(to_tsvector('simple', coalesce(filename, '')), 'B')
                        ) STORED
                    """)
                } catch (_: Exception) {}
            }
            // 创建索引
            MigrationHelpers.createIndexIfNotExists(conn, "idx_archives_category_id", "archives", "category_id")
            if (!MigrationHelpers.indexExists(conn, "idx_archives_title_tsv")) {
                try {
                    MigrationHelpers.execUpdate(conn, "CREATE INDEX idx_archives_title_tsv ON archives USING GIN (title_tsv)")
                } catch (_: Exception) {}
            }
            return true
        }

        logger.debug("Creating archives table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE archives (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                arcid VARCHAR(255) NOT NULL UNIQUE,
                title VARCHAR(1024) DEFAULT '',
                filename VARCHAR(1024) NOT NULL,
                summary TEXT DEFAULT '',
                thumbhash TEXT DEFAULT '',
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
            MigrationHelpers.execUpdate(conn, """
                ALTER TABLE archives ADD COLUMN title_tsv tsvector
                GENERATED ALWAYS AS (
                    setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
                    setweight(to_tsvector('simple', coalesce(filename, '')), 'B')
                ) STORED
            """)
        } catch (_: Exception) {}

        // 创建索引
        MigrationHelpers.createIndexIfNotExists(conn, "idx_archives_category_id", "archives", "category_id")
        try {
            MigrationHelpers.execUpdate(conn, "CREATE INDEX idx_archives_title_tsv ON archives USING GIN (title_tsv)")
        } catch (_: Exception) {}

        return true
    }

    private func createTagsTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "tags")) {
            logger.debug("tags table already exists")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_tags_namespace", "tags", "namespace")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_tags_name", "tags", "name")
            return true
        }

        logger.debug("Creating tags table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE tags (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                namespace VARCHAR(64) NOT NULL DEFAULT '',
                name VARCHAR(255) NOT NULL,
                translations JSONB NOT NULL DEFAULT '{}',
                links TEXT DEFAULT '',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE (namespace, name)
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(conn, "idx_tags_namespace", "tags", "namespace")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_tags_name", "tags", "name")
        return true
    }

    private func createArchiveTagsTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "archive_tags")) {
            logger.debug("archive_tags table already exists")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_archive_tags_archive_id", "archive_tags", "archive_id")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_archive_tags_tag_id", "archive_tags", "tag_id")
            return true
        }

        logger.debug("Creating archive_tags table")
        if (!MigrationHelpers.execUpdate(conn, """
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
        MigrationHelpers.createIndexIfNotExists(conn, "idx_archive_tags_archive_id", "archive_tags", "archive_id")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_archive_tags_tag_id", "archive_tags", "tag_id")
        return true
    }

    private func createUserArchiveStatusTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "user_archive_status")) {
            logger.debug("user_archive_status table already exists")
            MigrationHelpers.addColumnIfNotExists(conn, "user_archive_status", "progress", "INTEGER DEFAULT 0")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_user_archive_status_user_id", "user_archive_status", "user_id")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_user_archive_status_archive_id", "user_archive_status", "archive_id")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_user_archive_status_progress", "user_archive_status", "progress")
            return true
        }

        logger.debug("Creating user_archive_status table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE user_archive_status (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
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
        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_archive_status_user_id", "user_archive_status", "user_id")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_archive_status_archive_id", "user_archive_status", "archive_id")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_archive_status_progress", "user_archive_status", "progress")
        return true
    }

    private func createUserFavoritesTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "user_favorites")) {
            logger.debug("user_favorites table already exists")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_user_favorites_user_id", "user_favorites", "user_id")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_user_favorites_archive_id", "user_favorites", "archive_id")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_user_favorites_created_at", "user_favorites", "created_at")
            return true
        }

        logger.debug("Creating user_favorites table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE user_favorites (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
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
        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_favorites_user_id", "user_favorites", "user_id")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_favorites_archive_id", "user_favorites", "archive_id")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_favorites_created_at", "user_favorites", "created_at")
        return true
    }

    private func createSmartFiltersTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "smart_filters")) {
            logger.debug("smart_filters table already exists")
            return true
        }

        logger.debug("Creating smart_filters table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE smart_filters (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
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
        MigrationHelpers.execUpdate(conn, """
            INSERT INTO smart_filters (name, translations, icon, newonly, sort_order_num)
            VALUES ('未读档案', '{"en": {"text": "Unread Archives"}}', 'BookOpen', true, 1)
        """)
        MigrationHelpers.execUpdate(conn, """
            INSERT INTO smart_filters (name, translations, icon, untaggedonly, sort_order_num)
            VALUES ('无标签档案', '{"en": {"text": "Untagged Archives"}}', 'Tag', true, 2)
        """)
        MigrationHelpers.execUpdate(conn, """
            INSERT INTO smart_filters (name, translations, icon, date_from, sort_by, sort_order, sort_order_num)
            VALUES ('最近一周', '{"en": {"text": "Last Week"}}', 'Calendar', '-7', 'date_added', 'desc', 3)
        """)
        return true
    }

    private func createTankoubonsTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "tankoubons")) {
            logger.debug("tankoubons table already exists")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubons_tankoubon_id", "tankoubons", "tankoubon_id")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubons_name", "tankoubons", "name")
            return true
        }

        logger.debug("Creating tankoubons table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE tankoubons (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
                tankoubon_id VARCHAR(255) NOT NULL UNIQUE,
                name VARCHAR(1024) NOT NULL,
                summary TEXT DEFAULT '',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)) {
            return false
        }
        MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubons_tankoubon_id", "tankoubons", "tankoubon_id")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubons_name", "tankoubons", "name")
        return true
    }

    private func createTankoubonArchivesTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "tankoubon_archives")) {
            logger.debug("tankoubon_archives table already exists")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubon_archives_tankoubon_id", "tankoubon_archives", "tankoubon_id")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubon_archives_archive_id", "tankoubon_archives", "archive_id")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubon_archives_sort_order", "tankoubon_archives", "sort_order")
            return true
        }

        logger.debug("Creating tankoubon_archives table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE tankoubon_archives (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
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
        MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubon_archives_tankoubon_id", "tankoubon_archives", "tankoubon_id")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubon_archives_archive_id", "tankoubon_archives", "archive_id")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubon_archives_sort_order", "tankoubon_archives", "sort_order")
        return true
    }

    private func createTankoubonTagsTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "tankoubon_tags")) {
            logger.debug("tankoubon_tags table already exists")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubon_tags_tankoubon_id", "tankoubon_tags", "tankoubon_id")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubon_tags_tag_id", "tankoubon_tags", "tag_id")
            return true
        }

        logger.debug("Creating tankoubon_tags table")
        if (!MigrationHelpers.execUpdate(conn, """
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
        MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubon_tags_tankoubon_id", "tankoubon_tags", "tankoubon_id")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_tankoubon_tags_tag_id", "tankoubon_tags", "tag_id")
        return true
    }

    private func createUserTankoubonFavoritesTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "user_tankoubon_favorites")) {
            logger.debug("user_tankoubon_favorites table already exists")
            return true
        }

        logger.debug("Creating user_tankoubon_favorites table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE user_tankoubon_favorites (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
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
        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_tankoubon_favorites_user_id", "user_tankoubon_favorites", "user_id")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_user_tankoubon_favorites_tankoubon_id", "user_tankoubon_favorites", "tankoubon_id")
        return true
    }

    private func createTasksTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "tasks")) {
            logger.debug("tasks table already exists, checking columns")
            // 添加可能缺失的列
            MigrationHelpers.addColumnIfNotExists(conn, "tasks", "message", "TEXT")
            MigrationHelpers.addColumnIfNotExists(conn, "tasks", "priority", "INTEGER NOT NULL DEFAULT 50")
            MigrationHelpers.addColumnIfNotExists(conn, "tasks", "group_id", "VARCHAR(255)")
            MigrationHelpers.addColumnIfNotExists(conn, "tasks", "timeout_at", "TIMESTAMP")
            MigrationHelpers.addColumnIfNotExists(conn, "tasks", "trigger_source", "VARCHAR(50)")
            MigrationHelpers.addColumnIfNotExists(conn, "tasks", "wait_for_task_id", "BIGINT DEFAULT NULL")
            return true
        }

        logger.debug("Creating tasks table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE tasks (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
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
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                started_at TIMESTAMP,
                completed_at TIMESTAMP
            )
        """)) {
            return false
        }
        return true
    }

    private func createScheduledTasksTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "scheduled_tasks")) {
            logger.debug("scheduled_tasks table already exists, checking columns")
            // 添加可能缺失的列
            MigrationHelpers.addColumnIfNotExists(conn, "scheduled_tasks", "task_parameters", "TEXT")
            MigrationHelpers.addColumnIfNotExists(conn, "scheduled_tasks", "priority", "INTEGER NOT NULL DEFAULT 50")
            MigrationHelpers.addColumnIfNotExists(conn, "scheduled_tasks", "timeout_seconds", "INTEGER NOT NULL DEFAULT 3600")
            MigrationHelpers.addColumnIfNotExists(conn, "scheduled_tasks", "last_run_status", "VARCHAR(20)")
            MigrationHelpers.addColumnIfNotExists(conn, "scheduled_tasks", "last_error", "TEXT")
            MigrationHelpers.addColumnIfNotExists(conn, "scheduled_tasks", "run_count", "INTEGER NOT NULL DEFAULT 0")
            MigrationHelpers.addColumnIfNotExists(conn, "scheduled_tasks", "success_count", "INTEGER NOT NULL DEFAULT 0")
            MigrationHelpers.addColumnIfNotExists(conn, "scheduled_tasks", "failure_count", "INTEGER NOT NULL DEFAULT 0")
            MigrationHelpers.addColumnIfNotExists(conn, "scheduled_tasks", "created_by", "VARCHAR(100)")
            MigrationHelpers.addColumnIfNotExists(conn, "scheduled_tasks", "updated_by", "VARCHAR(100)")
            return true
        }

        logger.debug("Creating scheduled_tasks table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE scheduled_tasks (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
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

    private func createSystemSettingsTable(conn: Connection): Bool {
        if (MigrationHelpers.tableExists(conn, "system_settings")) {
            logger.debug("system_settings table already exists, checking columns")
            // 添加可能缺失的列
            MigrationHelpers.addColumnIfNotExists(conn, "system_settings", "value_type", "VARCHAR(50) NOT NULL DEFAULT 'string'")
            MigrationHelpers.addColumnIfNotExists(conn, "system_settings", "category", "VARCHAR(100) NOT NULL DEFAULT ''")
            MigrationHelpers.addColumnIfNotExists(conn, "system_settings", "description", "JSONB DEFAULT '{}'")
            MigrationHelpers.addColumnIfNotExists(conn, "system_settings", "is_encrypted", "BOOLEAN DEFAULT false")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_system_settings_category", "system_settings", "category")
            MigrationHelpers.createIndexIfNotExists(conn, "idx_system_settings_key", "system_settings", "key")
            return true
        }

        logger.debug("Creating system_settings table")
        if (!MigrationHelpers.execUpdate(conn, """
            CREATE TABLE system_settings (
                id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
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
        MigrationHelpers.createIndexIfNotExists(conn, "idx_system_settings_category", "system_settings", "category")
        MigrationHelpers.createIndexIfNotExists(conn, "idx_system_settings_key", "system_settings", "key")
        return true
    }

    private func createArchivesWithTagsView(conn: Connection): Bool {
        // 总是重建视图以确保结构正确
        if (MigrationHelpers.viewExists(conn, "archives_with_tags")) {
            logger.debug("Dropping existing archives_with_tags view")
            MigrationHelpers.execUpdate(conn, "DROP VIEW archives_with_tags")
        }

        logger.debug("Creating archives_with_tags view")
        return MigrationHelpers.execUpdate(conn, """
            CREATE VIEW archives_with_tags AS
            SELECT
                a.id,
                a.arcid,
                a.filename,
                a.title,
                a.summary,
                a.thumbhash,
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
                a.id, a.arcid, a.filename, a.title, a.summary, a.thumbhash,
                a.created_at, a.updated_at, a.relative_path, a.file_size,
                a.pagecount, a.archive_type, a.category_id, a.title_tsv
        """)
    }
}
