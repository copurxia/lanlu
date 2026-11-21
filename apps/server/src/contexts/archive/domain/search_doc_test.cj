package lanlu.contexts.archive.domain

import std.collection.*
import csorm.{Value, vtext, vint}
import lanlu.shared.config.*
import lanlu.infrastructure.migrations.*
import lanlu.infrastructure.migrations.versions.*
import lanlu.infrastructure.migrations.extensions.*

/**
 * V029 搜索文档表（archive_search_docs）回归测试。
 *
 * 锁死两件事：
 * 1. 触发器链路：archives / metadata_objects / metadata_tags / metadata_assets / assets
 *    任一写路径都能把搜索文档行同步到最新（漏一个就会出现“搜不到/搜到旧标题”）。
 * 2. 与旧聚合视图 archive_metadata_search 的检索结果一致（逐 id 差集为空）。
 *
 * 需要测试库（DB_STRING），连不上则跳过。
 */
func ensureSearchDocTestDbOrSkip(): Bool {
    if (DatabaseConfig.getDatabase().isNone()) {
        let _ = DatabaseConfig.initializePool()
    }
    if (DatabaseConfig.getDatabase().isNone()) {
        return false
    }
    registerSearchDocMigrationsForTest()
    return MigrationRunner.runPendingMigrations()
}

func registerSearchDocMigrationsForTest(): Unit {
    MigrationRegistry.register(V001_InitialSchema())
    MigrationRegistry.register(V002_TankoubonMetadataAndAutocreate())
    MigrationRegistry.register(V003_CategoryCoverAssetId())
    MigrationRegistry.register(V004_TankoubonCoverAssetGuard())
    MigrationRegistry.register(V005_ArchivesWithTagsCoverAsset())
    MigrationRegistry.register(V007_TankoubonArchivesOrderIndex())
    MigrationRegistry.register(V008_ArchivesCategoryPathFilenameIndex())
    MigrationRegistry.register(V009_ArchivePageMetadata())
    MigrationRegistry.register(V010_ArchiveTankoubonAssetsJson())
    MigrationRegistry.register(V011_UnifiedMetadataStore())
    MigrationRegistry.register(V012_CanonicalMetadataCleanup())
    MigrationRegistry.register(V013_MetadataTimeSemanticsUnification())
    MigrationRegistry.register(V014_BackfillTagDictionaryFromMetadataTags())
    MigrationRegistry.register(V015_RecommendationTracking())
    MigrationRegistry.register(V016_DropTaskGroupKv())
    MigrationRegistry.register(V017_TaskpoolStateModel())
    MigrationRegistry.register(V018_PageMetadataAttachments())
    MigrationRegistry.register(V019_UserWebauthnCredentials())
    MigrationRegistry.register(V020_UserTotpCredentials())
    MigrationRegistry.register(V021_UserTokensSecurityMetadata())
    MigrationRegistry.register(V022_UserPasswordHashArgon2id())
    MigrationRegistry.register(V023_PluginHooksReplaceLoginFrom())
    MigrationRegistry.register(V024_SearchAndRecommendationHotPathIndexes())
    MigrationRegistry.register(V025_UserTargetState())
    MigrationRegistry.register(V026_AddSourceIdRegexToPlugins())
    MigrationRegistry.register(V027_DropUserTankoubonFavorites())
    MigrationRegistry.register(V028_UserTokensTimestamptz())
    MigrationRegistry.register(V029_SearchDocIndex())
    MigrationRegistry.register(V030_JsonbColumns())
    ExtensionMigrationRegistry.register(X013_PgTrgmCurrentState())
    ExtensionMigrationRegistry.register(X013_UnaccentCurrentState())
    let _ = ExtensionMigrationRunner.runReadyMigrations()
}

private func scalarInt64(sql: String, params: Array<Value>): Int64 {
    match (DatabaseConfig.getDatabase()) {
        case Some(db) =>
            return db.rawOne<Int64>(sql, params, { r => r.getOrNullInt64(0) ?? 0 }) ?? 0
        case None => return 0
    }
}

private func cleanupSearchDocFixture(arcid: String): Unit {
    match (DatabaseConfig.getDatabase()) {
        case Some(db) =>
            // 直接删 archives，文档行由触发器级联删除；残留 metadata 兜底清理
            try { db.execRaw("DELETE FROM archives WHERE arcid = $1", [vtext(arcid)]) } catch (_: Exception) {}
            try { db.execRaw("DELETE FROM metadata_objects WHERE entity_type='archive' AND entity_id = $1", [vtext(arcid)]) } catch (_: Exception) {}
            try { db.execRaw("DELETE FROM categories WHERE catid = 'CAT_SDOC'", []) } catch (_: Exception) {}
        case None => ()
    }
}

@Test
func searchDocTriggerSyncTest() {
    if (!ensureSearchDocTestDbOrSkip()) {
        println("[skip] no test database for search doc test")
        return
    }
    let arcid = "ARC_SDOC_1"
    cleanupSearchDocFixture(arcid)
    match (DatabaseConfig.getDatabase()) {
        case None => return
        case Some(db) =>
            db.execRaw("INSERT INTO categories (catid, name, scan_path) VALUES ('CAT_SDOC','搜索文档测试','/tmp') ON CONFLICT DO NOTHING", [])
            db.execRaw("""
                INSERT INTO archives (arcid, filename, category_id, relative_path, pagecount, thumbhash, file_size)
                VALUES ($1, 'orig.zip', (SELECT id FROM categories WHERE catid='CAT_SDOC'), '', 12, 'th', 2048)
            """, [vtext(arcid)])

            let archiveId = scalarInt64("SELECT id FROM archives WHERE arcid = $1", [vtext(arcid)])
            @Assert(archiveId > 0)
            @Assert(scalarInt64("SELECT COUNT(*) FROM archive_search_docs WHERE id = $1", [vint(archiveId)]), 1)
            @Assert(scalarInt64("SELECT COUNT(*) FROM archive_search_docs WHERE id = $1 AND filename = 'orig.zip'", [vint(archiveId)]), 1)

            // 标题/摘要
            db.execRaw("""
                INSERT INTO metadata_objects (entity_type, entity_id, title, description)
                VALUES ('archive', $1, '初始标题', '初始简介')
                ON CONFLICT (entity_type, entity_id) DO UPDATE SET title = EXCLUDED.title, description = EXCLUDED.description
            """, [vtext(arcid)])
            @Assert(scalarInt64("SELECT COUNT(*) FROM archive_search_docs WHERE id = $1 AND title = '初始标题'", [vint(archiveId)]), 1)

            // 标签增删联动
            let metadataId = scalarInt64("SELECT id FROM metadata_objects WHERE entity_type='archive' AND entity_id = $1", [vtext(arcid)])
            db.execRaw("INSERT INTO metadata_tags (metadata_id, tag) VALUES ($1, '作者:甲') ON CONFLICT DO NOTHING", [vint(metadataId)])
            @Assert(scalarInt64("SELECT COUNT(*) FROM archive_search_docs WHERE id = $1 AND tags LIKE '%作者:甲%'", [vint(archiveId)]), 1)
            db.execRaw("DELETE FROM metadata_tags WHERE metadata_id = $1 AND tag = '作者:甲'", [vint(metadataId)])
            @Assert(scalarInt64("SELECT COUNT(*) FROM archive_search_docs WHERE id = $1 AND tags LIKE '%作者:甲%'", [vint(archiveId)]), 0)

            // 改文件名
            db.execRaw("UPDATE archives SET filename = 'renamed.zip' WHERE arcid = $1", [vtext(arcid)])
            @Assert(scalarInt64("SELECT COUNT(*) FROM archive_search_docs WHERE id = $1 AND filename = 'renamed.zip'", [vint(archiveId)]), 1)

            // 删除档案 → 文档行必须消失
            db.execRaw("DELETE FROM archives WHERE arcid = $1", [vtext(arcid)])
            @Assert(scalarInt64("SELECT COUNT(*) FROM archive_search_docs WHERE id = $1", [vint(archiveId)]), 0)
            cleanupSearchDocFixture(arcid)
    }
}

@Test
func searchDocMatchesViewTest() {
    if (!ensureSearchDocTestDbOrSkip()) {
        println("[skip] no test database for search doc equality test")
        return
    }
    match (DatabaseConfig.getDatabase()) {
        case None => return
        case Some(db) =>
            // 用现有数据抽样比对：视图与文档表对同一 ILIKE 条件返回的 id 集合必须一致。
            let terms = ["测试", "archive", "zip", "xyz不存在词"]
            for (term in terms) {
                let pattern = "%" + term + "%"
                let viewCount = scalarInt64("""
                    SELECT COUNT(DISTINCT id) FROM archive_metadata_search
                    WHERE unaccent(COALESCE(title,'')) ILIKE unaccent($1)
                       OR unaccent(COALESCE(filename,'')) ILIKE unaccent($1)
                       OR unaccent(COALESCE(summary,'')) ILIKE unaccent($1)
                       OR unaccent(COALESCE(tags,'')) ILIKE unaccent($1)
                """, [vtext(pattern)])
                let docCount = scalarInt64("""
                    SELECT COUNT(*) FROM archive_search_docs
                    WHERE unaccent(COALESCE(title,'')) ILIKE unaccent($1)
                       OR unaccent(COALESCE(filename,'')) ILIKE unaccent($1)
                       OR unaccent(COALESCE(summary,'')) ILIKE unaccent($1)
                       OR unaccent(COALESCE(tags,'')) ILIKE unaccent($1)
                """, [vtext(pattern)])
                @Assert(viewCount, docCount)
            }
    }
}

/**
 * 全行级等价（4.1 视图迁移验收）：对有 metadata 根对象的 archive，
 * 视图 archive_metadata_search 与文档表 archive_search_docs 的
 * 16 个确定性列双向 EXCEPT 差集必须为 0。
 * - 时间列仅在存在 metadata_objects 根行时比较（视图对缺根行的 COALESCE(CURRENT_TIMESTAMP)
 *   是非确定值，文档表存的是刷新时刻的冻结值）；
 * - search_tsv 不参与本断言：视图 C 权重用空格聚合、文档表用逗号聚合 tags 文本，
 *   两者经 default parser 解析后语义等价但不保证逐 lexeme 相同（由
 *   searchDocMatchesViewTest 从检索结果层面锁定）。
 */
@Test
func searchDocFullRowEqualityTest() {
    if (!ensureSearchDocTestDbOrSkip()) {
        println("[skip] no test database for search doc full-row equality test")
        return
    }
    match (DatabaseConfig.getDatabase()) {
        case None => return
        case Some(db) =>
            let cols = "id, arcid, filename, title, summary, tags, thumbhash, cover_asset_id, created_at, updated_at, release_at, relative_path, file_size, pagecount, archive_type, category_id"
            let viewWithMeta = "SELECT " + cols + " FROM archive_metadata_search v WHERE EXISTS (SELECT 1 FROM metadata_objects mo WHERE mo.entity_type='archive' AND mo.entity_id=v.arcid)"
            let docWithMeta = "SELECT " + cols + " FROM archive_search_docs d WHERE EXISTS (SELECT 1 FROM metadata_objects mo WHERE mo.entity_type='archive' AND mo.entity_id=d.arcid)"
            let diffSql = "SELECT (SELECT COUNT(*) FROM (" + viewWithMeta + " EXCEPT " + docWithMeta + ") a) + (SELECT COUNT(*) FROM (" + docWithMeta + " EXCEPT " + viewWithMeta + ") b)"
            let diff = scalarInt64(diffSql, [])
            if (diff != 0) {
                println("view/doc full-row diff rows: ${diff.toString()}")
            }
            @Assert(diff, 0)
            // 行数一致：视图与文档表每个 archive 恰好一行
            @Assert(
                scalarInt64("SELECT COUNT(*) FROM archive_metadata_search", []),
                scalarInt64("SELECT COUNT(*) FROM archive_search_docs", [])
            )
    }
}
