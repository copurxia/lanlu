package lrr4cj

import lrr4cj.routes.*
import lrr4cj.config.*
import lrr4cj.services.*
import lrr4cj.utils.*
import lrr4cj.dao.*
import lrr4cj.models.*
import std.io.*
import std.convert.*
import cjoy.*
import dotenv.Dotenv

main(): Int64 {
    // 先加载环境变量
    let config = Dotenv.createConfig()

    // 调试：检查环境变量是否正确加载
    let logLevel = config.read("LOG_LEVEL", "NOT_FOUND")
    println("MAIN: LOG_LEVEL from config = '${logLevel}'")

    // 初始化日志系统（现在环境变量已经加载）
    initializeLoggingWithConfig(Some(config))

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
    let _ = DatabaseConfig.host
    logger.info("Application starting... step 4: config loaded")

    let host = config.read("HOST", "0.0.0.0")
    let portStr = config.read("PORT", "8082")
    let port = UInt16.parse(portStr)

    logger.info("Application starting... step 6: server config parsed")
    logger.info("Server configuration", ("host", host), ("port", portStr))
    logger.info("Application starting... step 7: database config loaded")
    logger.info("Database connection", ("host", DatabaseConfig.host), ("port", DatabaseConfig.port.toString()), ("database", DatabaseConfig.database))

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

    // 初始化Minion任务表
    logger.info("Application starting... step 9a: initializing minion task tables")
    let minionTablesInitialized = MinionModel.initialize()
    if (minionTablesInitialized) {
        logger.info("Minion task tables initialized successfully")
    } else {
        logger.error("Failed to initialize minion task tables")
        return 1
    }

    // 启动 Shinobu 后台服务
    logger.info("Application starting... step 10: starting shinobu service")
    let shinobuService = ShinobuService.getInstance()
    let shinobuStarted = shinobuService.start()
    logger.info("Application starting... step 11: shinobu service started")
    if (shinobuStarted) {
        logger.info("Shinobu service started successfully")
    } else {
        logger.error("Failed to start Shinobu service")
        return 1
    }

    // 自动插件发现并强制更新 - 启动时执行
    logger.info("Application starting... step 12: auto plugin discovery with force update")
    var discoveredPlugins: Array<PluginData> = Array<PluginData>()
    try {
        let pluginService = PluginService.getInstance()
        discoveredPlugins = pluginService.discoverPlugins()
        logger.info("Application starting... step 13: plugin discovery complete", ("discovered", discoveredPlugins.size.toString()))

        // 强制更新所有插件到数据库（包括schema）
        var updatedCount = 0
        for (plugin in discoveredPlugins) {
            logger.info("Updating plugin: ${plugin.name} (${plugin.namespace})", ("has_schema", plugin.has_schema.toString()))

            // 强制更新现有插件的schema，不管是否存在
            let existingPlugin = PluginDao.getPluginByNamespace(plugin.namespace)
            if (existingPlugin.namespace.size > 0) {
                // 插件已存在，强制更新参数和权限
                existingPlugin.parameters = plugin.parameters
                existingPlugin.has_schema = plugin.has_schema
                existingPlugin.permissions = plugin.permissions
                if (PluginDao.update(existingPlugin)) {
                    updatedCount += 1
                    logger.info("Force updated plugin schema: ${plugin.name}")
                } else {
                    logger.error("Failed to update plugin schema: ${plugin.name}")
                }
            } else {
                // 插件不存在，创建新插件
                if (PluginDao.create(plugin)) {
                    updatedCount += 1
                    logger.info("Created new plugin: ${plugin.name}")
                } else {
                    logger.error("Failed to create plugin: ${plugin.name}")
                }
            }
        }
        logger.info("Auto plugin discovery completed", ("total", discoveredPlugins.size.toString()), ("updated", updatedCount.toString()))
        logger.info("Discovered plugins", ("count", discoveredPlugins.size.toString()))
    } catch (e: Exception) {
        logger.error("Plugin discovery failed", ("error", e.message))
        logger.info("Application starting... step 13: plugin discovery completed with errors")
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
