package lanlu.routes.api.user

import cjoy.*
import lanlu.controllers.*
import lanlu.middleware.*

/**
 * 用户统计路由模块
 * 处理 /api/user 路径下的路由
 */
public class UserRoutes {
    /**
     * 配置用户统计相关路由
     */
    public static func configure(router: JoyRouters) {
        // 上传当前用户头像
        router.put("/api/user/avatar", { ctx =>
            match (AuthMiddleware.requireUser(ctx)) {
                case Some(uid) => UserController.uploadAvatar(ctx, uid)
                case None => ()
            }
        })

        // 获取用户统计数据
        router.get("/api/user/stats", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            UserStatsController.getUserStats(ctx)
        })

        // 获取阅读趋势
        router.get("/api/user/trend", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            UserStatsController.getTrend(ctx)
        })
    }
}
