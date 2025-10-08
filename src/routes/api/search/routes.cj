package lrr4cj.routes.api.search

import cjoy.*
import lrr4cj.controllers.*
import lrr4cj.middleware.*

/**
 * API 搜索路由模块
 * 处理 /api/search 路径下的路由
 */
public class SearchRoutes {
    /**
     * 配置 API 搜索相关路由
     */
    public static func configure(router: JoyRouters) {
        // 搜索归档
        router.get("/api/search", { ctx =>
            AuthMiddleware.requiredAuth(ctx)
            SearchController.searchArchives(ctx)
        })

        // 随机获取归档
        router.get("/api/search/random", { ctx =>
            AuthMiddleware.requiredAuth(ctx)
            SearchController.getRandomArchives(ctx)
        })

        // 清除搜索缓存
        router.delete("/api/search/cache", { ctx =>
            AuthMiddleware.requiredAuth(ctx)
            SearchController.clearSearchCache(ctx)
        })

        // 获取搜索建议
        router.get("/api/search/suggestions", { ctx =>
            AuthMiddleware.requiredAuth(ctx)
            SearchController.getSearchSuggestions(ctx)
        })
    }
}