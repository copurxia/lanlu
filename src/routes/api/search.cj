package lanlu.routes.api

import ace_web.*
import ace_router.*
import lanlu.contexts.search.interfaces.http.SearchController
import lanlu.infrastructure.middleware.*

/**
 * API 搜索路由模块
 * 处理 /api/search 路径下的路由
 */
public class SearchRoutes {
    /**
     * 配置 API 搜索相关路由
     */
    public static func configure(router: Router) {
        router.group("/api/search") { search =>
            search.use(AuthMiddleware.requiredAuthMiddleware())

            // 搜索归档
            search.get("", { ctx: Context, next: Next =>
                SearchController.searchArchives(ctx)
            })
        }
    }
}