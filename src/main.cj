package lanlu

import lanlu.routes.*
import lanlu.shared.config.*
import lanlu.contexts.task.application.*
import lanlu.shared.utils.*
import lanlu.contexts.user.domain.*
import lanlu.contexts.system.application.*
import lanlu.contexts.plugin.domain.*
import lanlu.infrastructure.migrations.*
import lanlu.infrastructure.migrations.versions.*
import lanlu.infrastructure.migrations.extensions.*
import lanlu.infrastructure.kv.*
import lanlu.infrastructure.middleware.*
import std.convert.*
import ignite.*
import cjdotenv.load
import cjpminfo.*
import std.env.getVariable
import std.fs.exists

main(): Int64 {
    // 先加载环境变量（如果 .env 文件存在）
    if (exists(".env")) {
        load()
    }

    // 调试：检查环境变量是否正确加载
    let logLevel = getVariable("LOG_LEVEL") ?? "INFO"
    println("MAIN: LOG_LEVEL from config = '${logLevel}'")

    // 初始化日志系统（现在环境变量已经加载）
    initializeLogging()

    // 获取应用日志记录器
    let logger = getLogger("main")
    let version: String = @ModuleVer("1.0.0")
    let cjcVersion: String = @ModuleCjv("1.0.0")
    let gitCommitIdShort: String = @GitCommitIdShort("unknown")
    let gitBranch: String = @GitBranch("unknown")
    let appVersion: String = "${version}-${gitBranch}.${gitCommitIdShort}(${cjcVersion})"

    // 测试日志输出
    logger.debug("=== LOGGING SYSTEM TEST ===")
    logger.info("Starting LANLU server", ("version", appVersion))
    logger.info("Application starting... step 1: logging initialized")
    logger.debug("This is a debug message")
    logger.warn("This is a warning message")
    logger.debug("Application starting... step 2: logging test complete")

    // 引用 DatabaseConfig 以触发其静态初始化器，加载环境变量
    logger.debug("Application starting... step 3: triggering DatabaseConfig static init")
    logger.debug("Application starting... step 4: config loaded")

    let host = getVariable("HOST") ?? "0.0.0.0"
    let portStr = getVariable("PORT") ?? "8082"
    let port = UInt16.parse(portStr)

    logger.debug("Application starting... step 6: server config parsed")
    logger.debug("Server configuration", ("host", host), ("port", portStr))
    logger.debug("Application starting... step 7: database config loaded")

    // 注册并运行数据库迁移
    logger.debug("Application starting... step 8: running database migrations")
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
    ExtensionMigrationRegistry.register(X013_PgTrgmCurrentState())
    ExtensionMigrationRegistry.register(X013_UnaccentCurrentState())
    let migrationsOk = MigrationRunner.runPendingMigrations()
    logger.debug("Application starting... step 9: database migrations completed")
    if (migrationsOk) {
        logger.info("Database migrations completed successfully")
    } else {
        logger.error("Failed to run database migrations")
        return 1
    }

    let extensionMigrationsOk = ExtensionMigrationRunner.runReadyMigrations()
    if (extensionMigrationsOk) {
        logger.info("Extension migrations completed successfully")
    } else {
        logger.error("Failed to run extension migrations")
        return 1
    }

    // 初始化数据库连接池
    logger.debug("Application starting... step 9-pool: initializing connection pool")
    let poolInitialized = DatabaseConfig.initializePool()
    if (poolInitialized) {
        logger.info("Connection pool initialized successfully")
    } else {
        logger.error("Failed to initialize connection pool")
        return 1
    }

    let localKvInitialized = LocalKVService.initializeFromSettings()
    if (localKvInitialized) {
        logger.info("Local KV initialized successfully")
    } else {
        logger.error("Local KV unavailable; RocksDB is required for archive index and task KV")
        return 1
    }

    // 初始化用户认证（检查并创建默认管理员）
    logger.info("Application starting... step 9a: initializing auth")
    let authInitialized = UserModel.initialize()
    if (authInitialized) {
        logger.info("Auth initialized successfully")
    } else {
        logger.error("Failed to initialize auth")
        return 1
    }

    // 初始化系统设置
    logger.debug("Application starting... step 9c: initializing system settings")
    let settingsInitialized = SystemSettingsService.initializeFromEnv()
    if (settingsInitialized) {
        logger.info("System settings initialized successfully")
    } else {
        logger.error("Failed to initialize system settings")
        return 1
    }

    let configuredWasmRuntime = SystemSettingsService.getString("WASM_RUNTIME").trimAscii().toAsciiLower()
    if (configuredWasmRuntime != "wasmedge" && configuredWasmRuntime.size > 0) {
        logger.warn("WASM runtime setting is ignored; host runtime is now fixed to wasmedge", ("configured", configuredWasmRuntime))
    }
    let effectiveWasmRuntime = "wasmedge"

    let (wamrReady, wamrError) = WasmHostBridge.warmup()
    if (wamrReady) {
        logger.info("WASM runtime warmup ready", ("runtime", effectiveWasmRuntime))
    } else {
        logger.error("WASM runtime warmup failed", ("runtime", effectiveWasmRuntime), ("error", wamrError))
        return 1
    }

    // 启动 TaskPool（从tasks表领取pending任务执行）
    logger.debug("Application starting... step 10: starting taskpool service")
    let taskpool = TaskPoolService.getInstance()
    let taskpoolStarted = taskpool.start()
    if (taskpoolStarted) {
        logger.debug("TaskPool service started successfully")
    } else {
        logger.error("Failed to start TaskPool service")
        return 1
    }

    // 启动 CronService（定时任务调度服务，包含启动任务触发）
    logger.debug("Application starting... step 11: starting cron service")
    let cronService = CronService.getInstance()
    let cronStarted = cronService.start()
    if (cronStarted) {
        logger.debug("CronService started successfully")
    } else {
        logger.error("Failed to start CronService")
        return 1
    }

    // 创建 app 实例并配置路由
    logger.debug("Application starting... step 14: creating web server")
    let sslEnabled = SystemSettingsService.getBoolean("SSL_ENABLED")
    let sslCertFile = SystemSettingsService.getPath("SSL_CERT_FILE")
    let sslKeyFile = SystemSettingsService.getPath("SSL_KEY_FILE")

    if (sslEnabled) {
        if (sslCertFile.trimAscii().size == 0 || sslKeyFile.trimAscii().size == 0) {
            logger.error("SSL is enabled but certificate settings are incomplete",
                ("cert_file", sslCertFile),
                ("key_file", sslKeyFile))
            return 1
        }
        if (!exists(sslCertFile)) {
            logger.error("SSL certificate chain file does not exist", ("path", sslCertFile))
            return 1
        }
        if (!exists(sslKeyFile)) {
            logger.error("SSL private key file does not exist", ("path", sslKeyFile))
            return 1
        }
        logger.info("SSL/TLS enabled from system settings",
            ("cert_file", sslCertFile),
            ("key_file", sslKeyFile),
            ("http2", "alpn-auto"))
    } else {
        logger.info("SSL/TLS disabled in system settings")
    }

    // 10MB 分片上传需预留 multipart 包装开销，因此请求体上限略高于 10MB
    let app = App(config: Config(
        appName: "lanlu",
        appVersion: appVersion,
        serverHeader: "Lanlu",
        bodyLimit: 12 * 1024 * 1024,
        enableSwagger: true,
        enablePrintSwaggerUrl: false,
        enableBannerSignature: false,
        enableTlsPrecheck: true,
        tlsCertFile: if (sslEnabled) { sslCertFile } else { "" },
        tlsKeyFile: if (sslEnabled) { sslKeyFile } else { "" },
        ))

    installObservabilityMiddleware(app)

    // 注册所有路由
    logger.debug("Application starting... step 15: registering routes")
    Routes.register(app)
    logger.info("Application starting... step 16: routes registered")

    if (sslEnabled) {
        logger.info("Starting HTTPS server", ("http2", "enabled-via-alpn"), ("host", host), ("port", portStr))
    } else {
        logger.info("Starting HTTP server", ("host", host), ("port", portStr))
    }
    // 启动服务器
    logger.debug("Application starting... step 17: starting HTTP server")
    app.listen(host, port)

    return 0
}
