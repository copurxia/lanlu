package lanlu.routes

import ace_web.*
import ace_router.*
import lanlu.routes.api.*

/**
 * 路由注册模块
 * 负责统一注册所有路由
 */
public class Routes {
    public static func register(router: Router) {
        registerApiRoutes(router)
    }
}