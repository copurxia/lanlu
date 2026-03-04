package lanlu.routes.api

import ignite.*
import lanlu.contexts.user.interfaces.http.UserController
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
    public static func configure(router: App) {
        let user = router.group("/api/user")
        user.use(AuthMiddleware.requiredAuthMiddleware())

        // 上传当前用户头像
        router.put("/api/user/avatar", { ctx =>
            match (AuthMiddleware.requireUser(ctx)) {
                case Some(uid) => UserController.uploadAvatar(ctx, uid)
                case None => ()
            }
        })

        // 获取用户统计数据
        user.get("/stats", { ctx =>
            UserStatsController.getUserStats(ctx)
        })

        // 获取阅读趋势
        user.get("/trend", { ctx =>
            UserStatsController.getTrend(ctx)
        })
    }
}
