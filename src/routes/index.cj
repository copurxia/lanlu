package lanlu.routes

import ignite.*
import lanlu.routes.api.*
import lanlu.contexts.system.interfaces.http.FrontendController

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
        
        // 注册前端页面路由
        registerFrontendRoutes(router)
        
        // 未来可以添加更多路由模块
        // AdminRoutes.configure(router)
        // ProductRoutes.configure(router)
    }
    
    /**
     * 注册前端页面路由
     * 使用统一的通配符路由处理所有前端请求，由servePath函数智能处理
     */
    private static func registerFrontendRoutes(router: App) {
        // 处理所有前端请求（首页、页面路由、静态文件等）
        router.get("/", { ctx =>
            FrontendController.servePath(ctx)
        })

        // 处理所有前端HEAD请求（用于Next.js静态导出预检）
        router.head("/", { ctx =>
            FrontendController.servePathHead(ctx)
        })

        router.get("*", { ctx =>
            FrontendController.servePath(ctx)
        })

        router.head("*", { ctx =>
            FrontendController.servePathHead(ctx)
        })
    }
}
