package lanlu.routes.api

import ignite.*
import lanlu.contexts.task.interfaces.http.TaskPoolController
import lanlu.infrastructure.middleware.*

/**
 * TaskPool API路由
 */
public func registerTaskPoolRoutes(router: App) {
    // Canonical admin paths
    registerTaskPoolRoutesAt(router, "/api/admin/taskpool")
}

private func registerTaskPoolRoutesAt(router: App, basePath: String) {
    let taskpool = router.group(basePath)
    taskpool.use(AuthMiddleware.requireAdminMiddleware())

    // ========== 任务管理API ==========

    // 分页获取任务列表
    taskpool.get("/tasks", { ctx =>
        TaskPoolController.getTasks(ctx)
    })

    // 获取任务详情
    taskpool.get("/:taskId", { ctx =>
        TaskPoolController.getTaskDetail(ctx)
    })

    // 任务详情SSE流（用于替代前端高频轮询）
    taskpool.get("/:taskId/stream", { ctx =>
        TaskPoolController.streamTask(ctx)
    })

    // 取消单个任务
    taskpool.post("/:taskId/cancel", { ctx =>
        TaskPoolController.cancelTask(ctx)
    })

    // 重试失败的任务
    taskpool.post("/:taskId/retry", { ctx =>
        TaskPoolController.retryTask(ctx)
    })

    // 响应运行中任务的 RPC 选择请求（用于 metadata preview 人工选择）
    taskpool.post("/:taskId/rpc/select", { ctx =>
        TaskPoolController.respondRpcSelect(ctx)
    })

    // 更新任务进度
    taskpool.put("/:taskId/progress", { ctx =>
        TaskPoolController.updateTaskProgress(ctx)
    })
}
