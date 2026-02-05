package lanlu.routes

import cjoy.*
import lanlu.routes.api.archives.*
import lanlu.routes.api.search.*
import lanlu.routes.api.categories.*
import lanlu.routes.api.plugins.*
import lanlu.routes.api.tankoubons.*
import lanlu.routes.api.*
import lanlu.controllers.*

/**
 * 路由注册模块
 * 负责统一注册所有路由
 */
public class Routes {
    /**
     * 注册所有路由
     */
    public static func register(router: JoyRouters) {
        // 注册 API 归档路由
        ArchiveRoutes.configure(router)
        
        // 注册 API 搜索路由
        SearchRoutes.configure(router)
        
        // 注册 API 分类路由
        registerCategoryRoutes(router)
        
        // 注册 API 插件路由
        registerPluginsRoutes(router)
        
        // 注册 API 单行本路由
        registerTankoubonRoutes(router)
        
        // 注册所有 API 路由（包括 /api/info）
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
    private static func registerFrontendRoutes(router: JoyRouters) {
        // 处理所有前端请求（首页、页面路由、静态文件等）
        router.get("*", { ctx =>
            FrontendController.servePath(ctx)
        })

        // 处理所有前端HEAD请求（用于Next.js静态导出预检）
        router.head("*", { ctx =>
            FrontendController.servePathHead(ctx)
        })
    }
}
