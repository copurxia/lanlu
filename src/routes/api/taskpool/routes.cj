package lanlu.routes.api.taskpool

import cjoy.*
import lanlu.controllers.*
import lanlu.middleware.*

/**
 * TaskPool API路由
 */
public func registerTaskPoolRoutes(router: JoyRouters) {
    // Canonical admin paths
    registerTaskPoolRoutesAt(router, "/api/admin/taskpool")
}

private func registerTaskPoolRoutesAt(router: JoyRouters, basePath: String) {
    // ========== 任务管理API ==========

    // 分页获取任务列表
    router.get("${basePath}/tasks", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TaskPoolController.getTasks(ctx)
            case None => return
        }
    })

    // 获取任务详情
    router.get("${basePath}/{taskId}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TaskPoolController.getTaskDetail(ctx)
            case None => return
        }
    })

    // 取消单个任务
    router.post("${basePath}/{taskId}/cancel", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TaskPoolController.cancelTask(ctx)
            case None => return
        }
    })

    // 重试失败的任务
    router.post("${basePath}/{taskId}/retry", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => TaskPoolController.retryTask(ctx)
            case None => return
        }
    })
}
