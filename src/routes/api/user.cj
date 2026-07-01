package lanlu.routes.api

import ace_web.*
import ace_router.*
import lanlu.contexts.user.interfaces.http.UserStatsController
import lanlu.infrastructure.middleware.*

/**
 * 用户统计路由模块
 * 处理 /api/user 路径下的路由
 */
public class UserRoutes {
    /**
     * 配置用户统计相关路由
     */
    public static func configure(router: Router) {
        router.group("/api/user") { user =>
            user.use(AuthMiddleware.requiredAuthMiddleware())

            // 获取用户统计数据
            user.get("/stats", { ctx: Context, next: Next =>
                UserStatsController.getUserStats(ctx)
            })

            // 获取阅读趋势
            user.get("/trend", { ctx: Context, next: Next =>
                UserStatsController.getTrend(ctx)
            })
        }
    }
}