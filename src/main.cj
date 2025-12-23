package lrr4cj

import lrr4cj.routes.*
import lrr4cj.config.*
import lrr4cj.services.*
import lrr4cj.utils.*
import lrr4cj.models.*
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
    logger.info("=== LOGGING SYSTEM TEST ===")
    logger.info("Starting LRR4CJ server", ("version", "1.0.0"))
    logger.info("Application starting... step 1: logging initialized")
    logger.debug("This is a debug message")
    logger.warn("This is a warning message")
    logger.info("Application starting... step 2: logging test complete")

    // 引用 DatabaseConfig 以触发其静态初始化器，加载环境变量
    logger.info("Application starting... step 3: triggering DatabaseConfig static init")
    logger.info("Application starting... step 4: config loaded")

    let host = getVariable("HOST") ?? "0.0.0.0"
    let portStr = getVariable("PORT") ?? "8082"
    let port = UInt16.parse(portStr)

    logger.info("Application starting... step 6: server config parsed")
    logger.info("Server configuration", ("host", host), ("port", portStr))
    logger.info("Application starting... step 7: database config loaded")

    // 初始化数据库
    logger.info("Application starting... step 8: initializing database")
    let dbInitialized = DatabaseConfig.initializeDatabase()
    logger.info("Application starting... step 9: database initialized")
    if (dbInitialized) {
        logger.info("Database initialized successfully")
    } else {
        logger.error("Failed to initialize database")
        return 1
    }

    // 初始化用户/Token表
    logger.info("Application starting... step 9a: initializing auth tables")
    let authTablesInitialized = UserModel.initialize()
    if (authTablesInitialized) {
        logger.info("Auth tables initialized successfully")
    } else {
        logger.error("Failed to initialize auth tables")
        return 1
    }

    // 初始化Task任务表
    logger.info("Application starting... step 9b: initializing task tables")
    let taskTablesInitialized = TaskModel.initialize()
    if (taskTablesInitialized) {
        logger.info("Task tables initialized successfully")
    } else {
        logger.error("Failed to initialize task tables")
        return 1
    }

    // 初始化系统设置
    logger.info("Application starting... step 9c: initializing system settings")
    let settingsInitialized = SystemSettingsService.initializeFromEnv()
    if (settingsInitialized) {
        logger.info("System settings initialized successfully")
    } else {
        logger.error("Failed to initialize system settings")
        return 1
    }

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
    logger.info("Application starting... step 11: starting cron service")
    let cronService = CronService.getInstance()
    let cronStarted = cronService.start()
    if (cronStarted) {
        logger.info("CronService started successfully")
    } else {
        logger.error("Failed to start CronService")
        return 1
    }

    // 创建 joy 实例并配置路由
    logger.info("Application starting... step 14: creating web server")
    let joy = Joy.default()

    // 注册所有路由
    logger.info("Application starting... step 15: registering routes")
    Routes.register(joy.router)
    logger.info("Application starting... step 16: routes registered")

    logger.info("Starting HTTP server")
    // 启动服务器
    logger.info("Application starting... step 17: starting HTTP server")
    joy.run(host, port)

    return 0
}
