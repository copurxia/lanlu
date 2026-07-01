package lanlu.routes.api

import ace_web.*
import ace_router.*
import lanlu.contexts.task.interfaces.http.CronController
import lanlu.infrastructure.middleware.*

/**
 * Cron定时任务API路由
 */
public func registerCronRoutes(router: Router) {
    // Canonical admin paths
    registerCronRoutesAt(router, "/api/admin/cron")
}

private func registerCronRoutesAt(router: Router, basePath: String) {
    router.group(basePath) { cron =>
        cron.use(AuthMiddleware.requireAdminMiddleware())

        // 获取CronService状态
        cron.get("/status", { ctx: Context, next: Next =>
            CronController.getStatus(ctx)
        })

        // 启动CronService
        cron.post("/start", audited("cron.service.start", { ctx: Context, next: Next =>
            CronController.startService(ctx)
        }, riskLevel: 2))

        // 停止CronService
        cron.post("/stop", audited("cron.service.stop", { ctx: Context, next: Next =>
            CronController.stopService(ctx)
        }, riskLevel: 2))

        // 验证Cron表达式
        cron.post("/validate", audited("cron.expression.validate", { ctx: Context, next: Next =>
            CronController.validateExpression(ctx)
        }, riskLevel: 4))

        // 获取可用的任务类型（与 TaskRunner 保持一致）
        cron.get("/task-types", { ctx: Context, next: Next =>
            CronController.getTaskTypes(ctx)
        })

        // 获取定时任务列表（分页）
        cron.get("/tasks", { ctx: Context, next: Next =>
            CronController.getTasks(ctx)
        })

        // 创建定时任务
        cron.post("/tasks", audited("cron.task.create", { ctx: Context, next: Next =>
            CronController.createTask(ctx)
        }, riskLevel: 2))

        // 获取单个定时任务
        cron.get("/tasks/:id", { ctx: Context, next: Next =>
            CronController.getTask(ctx)
        })

        // 更新定时任务
        cron.put("/tasks/:id", audited("cron.task.update", { ctx: Context, next: Next =>
            CronController.updateTask(ctx)
        }, riskLevel: 2))

        // 删除定时任务
        cron.delete("/tasks/:id", audited("cron.task.delete", { ctx: Context, next: Next =>
            CronController.deleteTask(ctx)
        }, riskLevel: 2))

        // 手动触发定时任务
        cron.post("/tasks/:id/trigger", audited("cron.task.trigger", { ctx: Context, next: Next =>
            CronController.triggerTask(ctx)
        }, riskLevel: 2))

        // 启用定时任务
        cron.post("/tasks/:id/enable", audited("cron.task.enable", { ctx: Context, next: Next =>
            CronController.enableTask(ctx)
        }, riskLevel: 3))

        // 禁用定时任务
        cron.post("/tasks/:id/disable", audited("cron.task.disable", { ctx: Context, next: Next =>
            CronController.disableTask(ctx)
        }, riskLevel: 3))
    }
}