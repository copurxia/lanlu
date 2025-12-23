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
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            SearchController.searchArchives(ctx)
        })

        // 随机获取归档
        router.get("/api/search/random", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            SearchController.getRandomArchives(ctx)
        })

        // 获取搜索建议
        router.get("/api/search/suggestions", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            SearchController.getSearchSuggestions(ctx)
        })
    }
}
