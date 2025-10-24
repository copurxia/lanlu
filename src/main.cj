package lrr4cj

import lrr4cj.routes.*
import lrr4cj.config.*
import lrr4cj.services.*
import lrr4cj.utils.*
import std.env.*
import std.convert.*
import cjoy.*
import dotenv.Dotenv

main(): Int64 {
    // 初始化日志系统
    initializeLogging()

    // 获取应用日志记录器
    let logger = getLogger("main")

    logger.info("Starting LRR4CJ server", ("version", "1.0.0"))

    // 引用 DatabaseConfig 以触发其静态初始化器，加载环境变量
    let _ = DatabaseConfig.host

    let host = getVariable("HOST") ?? "0.0.0.0"
    let portStr = getVariable("PORT") ?? "8084"
    let port = UInt16.parse(portStr)

    logger.info("Server configuration", ("host", host), ("port", portStr))
    logger.info("Database connection", ("host", DatabaseConfig.host), ("port", DatabaseConfig.port.toString()), ("database", DatabaseConfig.database))

    // 启动 Shinobu 后台服务
    logger.info("Starting Shinobu background service...")
    let shinobuService = ShinobuService()
    let shinobuStarted = shinobuService.start()
    if (shinobuStarted) {
        logger.info("Shinobu service started successfully")
    } else {
        logger.error("Failed to start Shinobu service")
        return 1
    }

    // 创建 joy 实例并配置路由
    let joy = Joy.default()

    // 注册所有路由
    Routes.register(joy.router)

    logger.info("Starting HTTP server")
    // 启动服务器
    joy.run(host, port)

    return 0
}
