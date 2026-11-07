package lanlu.contexts.tankoubon.domain

import std.collection.*
import lanlu.shared.config.*
import lanlu.infrastructure.migrations.*
import lanlu.infrastructure.migrations.versions.*
import lanlu.infrastructure.migrations.extensions.*
import lanlu.contexts.tankoubon.infrastructure.persistence.TankoubonDao

/**
 * getAllTankoubonsWithUser 批量路径回归测试。
 *
 * 核心断言：SQL 条数上限（N+1 防线）——全量列表的 SQL 必须有界，
 * 旧逐条路径为 合集数×4+ 条（实测 2319 合集 ≈ 1.15 万条/请求）。
 * 需要测试库（DB_STRING），连不上则跳过。
 */
func ensureTankoubonTestDbOrSkip(): Bool {
    if (DatabaseConfig.getDatabase().isNone()) {
        let _ = DatabaseConfig.initializePool()
    }
    if (DatabaseConfig.getDatabase().isNone()) {
        return false
    }
    // 注册并运行迁移（幂等：schema_migrations 表跳过已应用版本）
    registerAllMigrationsForTest()
    return MigrationRunner.runPendingMigrations()
}

func registerAllMigrationsForTest(): Unit {
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
    ExtensionMigrationRegistry.register(X013_PgTrgmCurrentState())
    ExtensionMigrationRegistry.register(X013_UnaccentCurrentState())
    let _ = ExtensionMigrationRunner.runReadyMigrations()
}

@Test
func tankoubonListSqlCountTest() {
    if (!ensureTankoubonTestDbOrSkip()) {
        println("[skip] no test database for tankoubon list test")
        return
    }
    let counter = SqlCounter.install()
    try {
        let result = TankoubonModel.getAllTankoubonsWithUser(1)
        let _ = result
        // 基础行 1 + 聚合 miss(主查询+2 类标签批查) + children 1 + 收藏 1 + 版本号 ≤2
        @Assert(counter.total() <= 8)
        // 逐条聚合路径的标志 SQL（含 has_new_archives 的单条聚合查询）不应再出现
        @Assert(counter.countOf("has_new_archives") <= 1)
    } finally {
        counter.uninstall()
    }
}

@Test
func tankoubonListResultShapeTest() {
    if (!ensureTankoubonTestDbOrSkip()) {
        println("[skip] no test database for tankoubon list test")
        return
    }
    let list = TankoubonModel.getAllTankoubonsWithUser(1)
    for (t in list) {
        @Assert(t.id.size > 0)
        @Assert(t.assets_raw.size > 0)
    }
}
