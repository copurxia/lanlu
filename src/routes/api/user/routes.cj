package lrr4cj.routes.api.user

import cjoy.*
import lrr4cj.controllers.*
import lrr4cj.middleware.*

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
        router.get("/api/user/reading-trend", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            UserStatsController.getReadingTrend(ctx)
        })

        // 获取最近活动
        router.get("/api/user/recent-activity", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            UserStatsController.getRecentActivity(ctx)
        })
    }
}
