package lrr4cj.routes.api.taskpool

import cjoy.*
import lrr4cj.controllers.*
import lrr4cj.middleware.*

/**
 * TaskPool API路由
 */
public func registerTaskPoolRoutes(router: JoyRouters) {
    // ========== 任务管理API ==========

    // 分页获取任务列表
    router.get("/api/taskpool/tasks", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TaskPoolController.getTasks(ctx)
            case None => return
        }
    })

    // 获取任务详情
    router.get("/api/taskpool/{taskId}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TaskPoolController.getTaskDetail(ctx)
            case None => return
        }
    })

    // 取消单个任务
    router.post("/api/taskpool/{taskId}/cancel", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TaskPoolController.cancelTask(ctx)
            case None => return
        }
    })

    // 重试失败的任务
    router.post("/api/taskpool/{taskId}/retry", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TaskPoolController.retryTask(ctx)
            case None => return
        }
    })

    // 按 group_id 查询任务列表
    router.get("/api/taskpool/group/{groupId}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TaskPoolController.getTasksByGroup(ctx)
            case None => return
        }
    })

    // 批量取消任务（按 group_id）
    router.post("/api/taskpool/group/{groupId}/cancel", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TaskPoolController.cancelTasksByGroup(ctx)
            case None => return
        }
    })

    // 获取任务监控指标
    router.get("/api/taskpool/metrics", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TaskPoolController.getMetrics(ctx)
            case None => return
        }
    })
}
