package lrr4cj

import lrr4cj.routes.*
import lrr4cj.config.*
import lrr4cj.services.*
import std.env.*
import std.convert.*
import cjoy.*
import dotenv.Dotenv

main(): Int64 {
    // 从环境变量读取配置
    Dotenv.config()
    
    // 引用 DatabaseConfig 以触发其静态初始化器，加载环境变量
    let _ = DatabaseConfig.host
    
    let host = getVariable("HOST") ?? "0.0.0.0"
    let portStr = getVariable("PORT") ?? "8084"
    let port = UInt16.parse(portStr)
    
    println("Starting server on ${host}:${port}")
    println("Database: ${DatabaseConfig.host}:${DatabaseConfig.port}/${DatabaseConfig.database}")
    
    // 启动 Shinobu 后台服务
    println("Starting Shinobu background service...")
    let shinobuService = ShinobuService()
    let shinobuStarted = shinobuService.start()
    if (shinobuStarted) {
        println("Shinobu service started successfully")
    } else {
        println("Failed to start Shinobu service")
    }
    
    // 创建 joy 实例并配置路由
    let joy = Joy.default()
    
    // 注册所有路由
    Routes.register(joy.router)
    
    // 启动服务器
    joy.run(host, port)
    
    return 0
}
