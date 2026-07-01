package lanlu.routes.api

import ace_web.*
import ace_router.*
import lanlu.contexts.task.interfaces.http.TaskPoolController
import lanlu.infrastructure.middleware.*

/**
 * TaskPool API路由
 */
public func registerTaskPoolRoutes(router: Router) {
    // Canonical admin paths
    registerTaskPoolRoutesAt(router, "/api/admin/taskpool")
}

private func registerTaskPoolRoutesAt(router: Router, basePath: String) {
    router.group(basePath) { taskpool =>
        taskpool.use(AuthMiddleware.requireAdminMiddleware())

        // ========== 任务管理API ==========

        // 任务列表 SSE 流（按筛选与分页聚合）
        taskpool.get("/tasks", { ctx: Context, next: Next =>
            TaskPoolController.getTasks(ctx)
        })

        // 获取任务详情
        taskpool.get("/:taskId", { ctx: Context, next: Next =>
            TaskPoolController.getTaskDetail(ctx)
        })

        // 任务详情SSE流（用于替代前端高频轮询）
        taskpool.get("/:taskId/stream", { ctx: Context, next: Next =>
            TaskPoolController.streamTask(ctx)
        })

        // 取消单个任务
        taskpool.post("/:taskId/cancel", audited("taskpool.task.cancel", { ctx: Context, next: Next =>
            TaskPoolController.cancelTask(ctx)
        }, riskLevel: 2))

        // 重试失败的任务
        taskpool.post("/:taskId/retry", audited("taskpool.task.retry", { ctx: Context, next: Next =>
            TaskPoolController.retryTask(ctx)
        }, riskLevel: 2))

        // 响应运行中任务的 RPC 选择请求（用于 metadata preview 人工选择）
        taskpool.post("/:taskId/rpc/select", audited("taskpool.task.rpc_select", { ctx: Context, next: Next =>
            TaskPoolController.respondRpcSelect(ctx)
        }, riskLevel: 2))

        // 更新任务进度
        taskpool.put("/:taskId/progress", audited("taskpool.task.progress.update", { ctx: Context, next: Next =>
            TaskPoolController.updateTaskProgress(ctx)
        }, riskLevel: 3))
    }
}