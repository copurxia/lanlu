package lanlu.routes

import ignite.*
import lanlu.routes.api.*

/**
 * 路由注册模块
 * 负责统一注册所有路由
 */
public class Routes {
    /**
     * 注册所有路由
     */
    public static func register(router: App) {
        // 注册所有 API 路由（包括 /api/info）
        // 注意：避免在这里重复单独注册子模块，否则会触发 Ignite 路由冲突
        registerApiRoutes(router)
    }
}
