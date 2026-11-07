package lanlu.infrastructure.migrations.versions

import csorm.*
import lanlu.infrastructure.migrations.*

/**
 * V029: 反规范化搜索文档表 + 触发器增量维护 + GIN 索引。
 *
 * 背景：archive_metadata_search 是带 GROUP BY/string_agg 的视图，带词搜索
 * （ILIKE '%term%'）必须全量物化 13k+ 行，且 title/summary/tags 上没有
 * trigram 索引（filename 有，但被 unaccent 包裹后同样失效），线上实测 3.6~4.8s。
 * 参照 LANraragi（Redis 搜索索引）/ Komga（Lucene 索引）的通行做法，
 * 用一张反规范化文档表承载可搜索文本，写路径由触发器增量同步，
 * 查询侧可直接命中 GIN trigram / tsvector 索引。
 */
public class V029_SearchDocIndex <: Migration {
    public func version(): String {
        return "V029"
    }

    public func description(): String {
        return "Denormalized archive search document table with trigger-synced GIN indexes"
    }

    public func up(db: Database): Bool {
        if (!MigrationHelpers.tableExists(db, "archives")) {
            return true
        }

        // 1. 文档表：每个 archive 一行，字段与搜索用视图对齐（+ 聚合后的 tags / tsvector）
        if (!MigrationHelpers.execUpdate(db, """
            CREATE TABLE IF NOT EXISTS archive_search_docs (
                id BIGINT PRIMARY KEY,
                arcid TEXT NOT NULL,
                filename TEXT NOT NULL DEFAULT '',
                title TEXT NOT NULL DEFAULT '',
                summary TEXT NOT NULL DEFAULT '',
                tags TEXT NOT NULL DEFAULT '',
                thumbhash TEXT NOT NULL DEFAULT '',
                cover_asset_id BIGINT NOT NULL DEFAULT 0,
                created_at TIMESTAMP,
                updated_at TIMESTAMP,
                release_at TIMESTAMP,
                relative_path TEXT NOT NULL DEFAULT '',
                file_size BIGINT NOT NULL DEFAULT 0,
                pagecount INT NOT NULL DEFAULT 0,
                archive_type TEXT NOT NULL DEFAULT '',
                category_id INT,
                search_tsv tsvector
            )
        """)) {
            return false
        }

        // 2. 单行刷新函数（所有触发器与回填共用）
        if (!MigrationHelpers.execUpdate(db, """
            CREATE OR REPLACE FUNCTION lanlu_refresh_search_doc(p_archive_id BIGINT)
            RETURNS VOID AS $$
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM archives WHERE id = p_archive_id) THEN
                    DELETE FROM archive_search_docs WHERE id = p_archive_id;
                    RETURN;
                END IF;

                INSERT INTO archive_search_docs AS d (
                    id, arcid, filename, title, summary, tags, thumbhash,
                    cover_asset_id, created_at, updated_at, release_at,
                    relative_path, file_size, pagecount, archive_type, category_id, search_tsv
                )
                SELECT
                    a.id, a.arcid, a.filename,
                    COALESCE(mo.title, ''),
                    COALESCE(mo.description, ''),
                    COALESCE(t.tags, ''),
                    COALESCE(ca.thumbhash, COALESCE(a.thumbhash, '')),
                    COALESCE(cov.asset_id, 0),
                    COALESCE(mo.created_at, CURRENT_TIMESTAMP),
                    COALESCE(mo.updated_at, COALESCE(mo.created_at, CURRENT_TIMESTAMP)),
                    mo.release_at,
                    a.relative_path, a.file_size, a.pagecount, a.archive_type, a.category_id,
                    setweight(to_tsvector('simple', COALESCE(mo.title, '')), 'A') ||
                    setweight(to_tsvector('simple', COALESCE(a.filename, '')), 'B') ||
                    setweight(to_tsvector('simple', COALESCE(t.tags, '')), 'C')
                FROM archives a
                LEFT JOIN metadata_objects mo
                       ON mo.entity_type = 'archive' AND mo.entity_id = a.arcid
                LEFT JOIN LATERAL (
                    SELECT string_agg(mt.tag, ',' ORDER BY mt.tag) AS tags
                    FROM metadata_tags mt WHERE mt.metadata_id = mo.id
                ) t ON true
                LEFT JOIN metadata_assets cov
                       ON cov.metadata_id = mo.id AND cov.slot = 'cover'
                LEFT JOIN assets ca ON ca.id = cov.asset_id
                WHERE a.id = p_archive_id
                ON CONFLICT (id) DO UPDATE SET
                    arcid = EXCLUDED.arcid,
                    filename = EXCLUDED.filename,
                    title = EXCLUDED.title,
                    summary = EXCLUDED.summary,
                    tags = EXCLUDED.tags,
                    thumbhash = EXCLUDED.thumbhash,
                    cover_asset_id = EXCLUDED.cover_asset_id,
                    created_at = EXCLUDED.created_at,
                    updated_at = EXCLUDED.updated_at,
                    release_at = EXCLUDED.release_at,
                    relative_path = EXCLUDED.relative_path,
                    file_size = EXCLUDED.file_size,
                    pagecount = EXCLUDED.pagecount,
                    archive_type = EXCLUDED.archive_type,
                    category_id = EXCLUDED.category_id,
                    search_tsv = EXCLUDED.search_tsv;
            END;
            $$ LANGUAGE plpgsql
        """)) {
            return false
        }

        // 3. 触发器：archives 本体
        if (!MigrationHelpers.execUpdate(db, """
            CREATE OR REPLACE FUNCTION lanlu_search_doc_sync_archive()
            RETURNS TRIGGER AS $$
            BEGIN
                PERFORM lanlu_refresh_search_doc(COALESCE(NEW.id, OLD.id));
                RETURN COALESCE(NEW, OLD);
            END;
            $$ LANGUAGE plpgsql
        """)) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "DROP TRIGGER IF EXISTS trg_archive_search_doc ON archives")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, """
            CREATE TRIGGER trg_archive_search_doc
            AFTER INSERT OR DELETE OR UPDATE OF arcid, filename, pagecount, file_size,
                relative_path, archive_type, category_id, thumbhash
            ON archives
            FOR EACH ROW EXECUTE FUNCTION lanlu_search_doc_sync_archive()
        """)) {
            return false
        }

        // 4. 触发器：metadata_objects（归档标题/摘要/时间）
        if (!MigrationHelpers.execUpdate(db, """
            CREATE OR REPLACE FUNCTION lanlu_search_doc_sync_metadata_object()
            RETURNS TRIGGER AS $$
            DECLARE
                v_entity_type TEXT;
                v_entity_id TEXT;
            BEGIN
                IF TG_OP = 'DELETE' THEN
                    v_entity_type := OLD.entity_type;
                    v_entity_id := OLD.entity_id;
                ELSE
                    v_entity_type := NEW.entity_type;
                    v_entity_id := NEW.entity_id;
                END IF;
                IF v_entity_type = 'archive' THEN
                    PERFORM lanlu_refresh_search_doc(a.id) FROM archives a WHERE a.arcid = v_entity_id;
                END IF;
                RETURN COALESCE(NEW, OLD);
            END;
            $$ LANGUAGE plpgsql
        """)) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "DROP TRIGGER IF EXISTS trg_metadata_object_search_doc ON metadata_objects")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, """
            CREATE TRIGGER trg_metadata_object_search_doc
            AFTER INSERT OR DELETE OR UPDATE OF title, description, release_at, created_at, updated_at, entity_id
            ON metadata_objects
            FOR EACH ROW EXECUTE FUNCTION lanlu_search_doc_sync_metadata_object()
        """)) {
            return false
        }

        // 5. 触发器：metadata_tags（标签集合变化）
        if (!MigrationHelpers.execUpdate(db, """
            CREATE OR REPLACE FUNCTION lanlu_search_doc_sync_metadata_tag()
            RETURNS TRIGGER AS $$
            DECLARE
                v_metadata_id BIGINT;
                v_arcid TEXT;
            BEGIN
                IF TG_OP = 'DELETE' THEN
                    v_metadata_id := OLD.metadata_id;
                ELSE
                    v_metadata_id := NEW.metadata_id;
                END IF;
                SELECT mo.entity_id INTO v_arcid
                FROM metadata_objects mo
                WHERE mo.id = v_metadata_id AND mo.entity_type = 'archive';
                IF v_arcid IS NOT NULL THEN
                    PERFORM lanlu_refresh_search_doc(a.id) FROM archives a WHERE a.arcid = v_arcid;
                END IF;
                RETURN COALESCE(NEW, OLD);
            END;
            $$ LANGUAGE plpgsql
        """)) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "DROP TRIGGER IF EXISTS trg_metadata_tag_search_doc ON metadata_tags")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, """
            CREATE TRIGGER trg_metadata_tag_search_doc
            AFTER INSERT OR DELETE ON metadata_tags
            FOR EACH ROW EXECUTE FUNCTION lanlu_search_doc_sync_metadata_tag()
        """)) {
            return false
        }

        // 6. 触发器：metadata_assets（封面资产变化）
        if (!MigrationHelpers.execUpdate(db, """
            CREATE OR REPLACE FUNCTION lanlu_search_doc_sync_metadata_asset()
            RETURNS TRIGGER AS $$
            DECLARE
                v_metadata_id BIGINT;
                v_arcid TEXT;
            BEGIN
                IF TG_OP = 'DELETE' THEN
                    v_metadata_id := OLD.metadata_id;
                ELSE
                    v_metadata_id := NEW.metadata_id;
                END IF;
                SELECT mo.entity_id INTO v_arcid
                FROM metadata_objects mo
                WHERE mo.id = v_metadata_id AND mo.entity_type = 'archive';
                IF v_arcid IS NOT NULL THEN
                    PERFORM lanlu_refresh_search_doc(a.id) FROM archives a WHERE a.arcid = v_arcid;
                END IF;
                RETURN COALESCE(NEW, OLD);
            END;
            $$ LANGUAGE plpgsql
        """)) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "DROP TRIGGER IF EXISTS trg_metadata_asset_search_doc ON metadata_assets")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, """
            CREATE TRIGGER trg_metadata_asset_search_doc
            AFTER INSERT OR DELETE OR UPDATE OF asset_id, slot
            ON metadata_assets
            FOR EACH ROW EXECUTE FUNCTION lanlu_search_doc_sync_metadata_asset()
        """)) {
            return false
        }

        // 7. 触发器：assets.thumbhash 变化（封面缩略图哈希）
        if (!MigrationHelpers.execUpdate(db, """
            CREATE OR REPLACE FUNCTION lanlu_search_doc_sync_asset_thumbhash()
            RETURNS TRIGGER AS $$
            BEGIN
                IF NEW.thumbhash IS DISTINCT FROM OLD.thumbhash THEN
                    UPDATE archive_search_docs
                       SET thumbhash = COALESCE(NEW.thumbhash, '')
                     WHERE cover_asset_id = NEW.id;
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql
        """)) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, "DROP TRIGGER IF EXISTS trg_asset_search_doc ON assets")) {
            return false
        }
        if (!MigrationHelpers.execUpdate(db, """
            CREATE TRIGGER trg_asset_search_doc
            AFTER UPDATE OF thumbhash ON assets
            FOR EACH ROW EXECUTE FUNCTION lanlu_search_doc_sync_asset_thumbhash()
        """)) {
            return false
        }

        // 8. 回填（幂等 upsert）
        if (!MigrationHelpers.execUpdate(db, """
            INSERT INTO archive_search_docs AS d (
                id, arcid, filename, title, summary, tags, thumbhash,
                cover_asset_id, created_at, updated_at, release_at,
                relative_path, file_size, pagecount, archive_type, category_id, search_tsv
            )
            SELECT
                a.id, a.arcid, a.filename,
                COALESCE(mo.title, ''),
                COALESCE(mo.description, ''),
                COALESCE(t.tags, ''),
                COALESCE(ca.thumbhash, COALESCE(a.thumbhash, '')),
                COALESCE(cov.asset_id, 0),
                COALESCE(mo.created_at, CURRENT_TIMESTAMP),
                COALESCE(mo.updated_at, COALESCE(mo.created_at, CURRENT_TIMESTAMP)),
                mo.release_at,
                a.relative_path, a.file_size, a.pagecount, a.archive_type, a.category_id,
                setweight(to_tsvector('simple', COALESCE(mo.title, '')), 'A') ||
                setweight(to_tsvector('simple', COALESCE(a.filename, '')), 'B') ||
                setweight(to_tsvector('simple', COALESCE(t.tags, '')), 'C')
            FROM archives a
            LEFT JOIN metadata_objects mo
                   ON mo.entity_type = 'archive' AND mo.entity_id = a.arcid
            LEFT JOIN LATERAL (
                SELECT string_agg(mt.tag, ',' ORDER BY mt.tag) AS tags
                FROM metadata_tags mt WHERE mt.metadata_id = mo.id
            ) t ON true
            LEFT JOIN metadata_assets cov
                   ON cov.metadata_id = mo.id AND cov.slot = 'cover'
            LEFT JOIN assets ca ON ca.id = cov.asset_id
            ON CONFLICT (id) DO UPDATE SET
                arcid = EXCLUDED.arcid,
                filename = EXCLUDED.filename,
                title = EXCLUDED.title,
                summary = EXCLUDED.summary,
                tags = EXCLUDED.tags,
                thumbhash = EXCLUDED.thumbhash,
                cover_asset_id = EXCLUDED.cover_asset_id,
                created_at = EXCLUDED.created_at,
                updated_at = EXCLUDED.updated_at,
                release_at = EXCLUDED.release_at,
                relative_path = EXCLUDED.relative_path,
                file_size = EXCLUDED.file_size,
                pagecount = EXCLUDED.pagecount,
                archive_type = EXCLUDED.archive_type,
                category_id = EXCLUDED.category_id,
                search_tsv = EXCLUDED.search_tsv
        """)) {
            return false
        }

        // 9. 索引：trigram（表达式必须与查询侧完全一致：unaccent(COALESCE(col,''))）
        // 版本迁移先于扩展迁移执行，这里自带 IMMUTABLE unaccent 包装（与 X013UACC 幂等一致）。
        if (!MigrationHelpers.extensionInstalled(db, "unaccent") ||
            !MigrationHelpers.extensionInstalled(db, "pg_trgm")) {
            // 扩展不可用时跳过索引，搜索退化为顺序扫描（功能不受影响）
            return true
        }
        if (!MigrationHelpers.execUpdate(db, """
            CREATE OR REPLACE FUNCTION lanlu_immutable_unaccent(input TEXT)
            RETURNS TEXT
            LANGUAGE SQL
            IMMUTABLE
            PARALLEL SAFE
            AS $$
                SELECT public.unaccent('public.unaccent'::regdictionary, input)
            $$
        """)) {
            return false
        }

        let trigramIndexes: Array<(String, String)> = [
            ("idx_search_docs_title_trgm", "lanlu_immutable_unaccent(COALESCE(title, ''))"),
            ("idx_search_docs_filename_trgm", "lanlu_immutable_unaccent(COALESCE(filename, ''))"),
            ("idx_search_docs_summary_trgm", "lanlu_immutable_unaccent(COALESCE(summary, ''))"),
            ("idx_search_docs_tags_trgm", "lanlu_immutable_unaccent(COALESCE(tags, ''))")
        ]
        for ((indexName, expr) in trigramIndexes) {
            if (!MigrationHelpers.indexExists(db, indexName)) {
                if (!MigrationHelpers.execUpdate(db,
                    "CREATE INDEX ${indexName} ON archive_search_docs USING GIN ((${expr}) gin_trgm_ops)"
                )) {
                    // pg_trgm 未安装时跳过，搜索仍可用（退化为顺序扫描）
                    return true
                }
            }
        }

        // 标签搜索仍走 metadata_tags EXISTS（语义要求按“标签”匹配），同样补 trigram 索引。
        if (MigrationHelpers.tableExists(db, "metadata_tags") &&
            !MigrationHelpers.indexExists(db, "idx_metadata_tags_tag_unaccent_trgm")) {
            if (!MigrationHelpers.execUpdate(db,
                "CREATE INDEX idx_metadata_tags_tag_unaccent_trgm ON metadata_tags USING GIN ((lanlu_immutable_unaccent(tag)) gin_trgm_ops)"
            )) {
                return true
            }
        }

        // 10. 索引：tsvector（相关度）+ 排序/过滤列
        if (!MigrationHelpers.indexExists(db, "idx_search_docs_tsv")) {
            if (!MigrationHelpers.execUpdate(db,
                "CREATE INDEX idx_search_docs_tsv ON archive_search_docs USING GIN (search_tsv)"
            )) {
                return true
            }
        }
        let btreeIndexes: Array<(String, String)> = [
            ("idx_search_docs_title", "title"),
            ("idx_search_docs_arcid", "arcid"),
            ("idx_search_docs_category", "category_id"),
            ("idx_search_docs_created", "created_at"),
            ("idx_search_docs_updated", "updated_at"),
            ("idx_search_docs_release", "release_at"),
            ("idx_search_docs_pagecount", "pagecount"),
            ("idx_search_docs_file_size", "file_size")
        ]
        for ((indexName, column) in btreeIndexes) {
            if (!MigrationHelpers.indexExists(db, indexName)) {
                if (!MigrationHelpers.createIndexIfNotExists(db, indexName, "archive_search_docs", column)) {
                    return false
                }
            }
        }

        return true
    }
}
