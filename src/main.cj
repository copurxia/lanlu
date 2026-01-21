package lrr4cj

import lrr4cj.routes.*
import lrr4cj.config.*
import lrr4cj.services.*
import lrr4cj.utils.*
import lrr4cj.models.*
import lrr4cj.migrations.*
import lrr4cj.migrations.versions.*
import std.convert.*
import cjoy.*
import cjdotenv.load
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

    // 测试日志输出
    logger.debug("=== LOGGING SYSTEM TEST ===")
    logger.info("Starting LRR4CJ server", ("version", "1.0.0"))
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
    MigrationRegistry.register(V002_TaskGroupKV())
    MigrationRegistry.register(V003_Assets())
    MigrationRegistry.register(V004_RemoveThumbnailSetting())
    MigrationRegistry.register(V005_TagIcons())
    MigrationRegistry.register(V006_TagBackgrounds())
    MigrationRegistry.register(V007_UpdateCronTasks())
    let migrationsOk = MigrationRunner.runPendingMigrations()
    logger.debug("Application starting... step 9: database migrations completed")
    if (migrationsOk) {
        logger.info("Database migrations completed successfully")
    } else {
        logger.error("Failed to run database migrations")
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

    // Migrate legacy thumbnails (./data/thumb) into assets storage, then cleanup legacy directory.
    // Best-effort and non-fatal.
    try {
        LegacyThumbnailCleanupService.migrateAndCleanup()
    } catch (_: Exception) {}

    // 启动 TaskPool（从tasks表领取pending任务执行）
    logger.info("Application starting... step 10: starting taskpool service")
    let taskpool = TaskPoolService.getInstance()
    let taskpoolStarted = taskpool.start()
    if (taskpoolStarted) {
        logger.info("TaskPool service started successfully")
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

    // 创建 joy 实例并配置路由
    logger.debug("Application starting... step 14: creating web server")
    let joy = Joy.default()

    // 注册所有路由
    logger.debug("Application starting... step 15: registering routes")
    Routes.register(joy.router)
    logger.info("Application starting... step 16: routes registered")

    logger.info("Starting HTTP server")
    // 启动服务器
    logger.debug("Application starting... step 17: starting HTTP server")
    joy.run(host, port)

    return 0
}
