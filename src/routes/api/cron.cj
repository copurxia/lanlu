package lanlu.routes.api

import ignite.*
import lanlu.contexts.task.interfaces.http.CronController
import lanlu.infrastructure.middleware.*

/**
 * Cron定时任务API路由
 */
public func registerCronRoutes(router: App) {
    // Canonical admin paths
    registerCronRoutesAt(router, "/api/admin/cron")
}

private func registerCronRoutesAt(router: App, basePath: String) {
    let cron = router.group(basePath)
    cron.use(AuthMiddleware.requireAdminMiddleware())

    // 获取CronService状态
    cron.get("/status", { ctx =>
        CronController.getStatus(ctx)
    })

    // 启动CronService
    cron.post("/start", audited("cron.service.start", { ctx =>
        CronController.startService(ctx)
    }, riskLevel: 2))

    // 停止CronService
    cron.post("/stop", audited("cron.service.stop", { ctx =>
        CronController.stopService(ctx)
    }, riskLevel: 2))

    // 验证Cron表达式
    cron.post("/validate", audited("cron.expression.validate", { ctx =>
        CronController.validateExpression(ctx)
    }, riskLevel: 4))

    // 获取可用的任务类型（与 TaskRunner 保持一致）
    cron.get("/task-types", { ctx =>
        CronController.getTaskTypes(ctx)
    })

    // 获取定时任务列表（分页）
    cron.get("/tasks", { ctx =>
        CronController.getTasks(ctx)
    })

    // 创建定时任务
    cron.post("/tasks", audited("cron.task.create", { ctx =>
        CronController.createTask(ctx)
    }, riskLevel: 2))

    // 获取单个定时任务
    cron.get("/tasks/:id", { ctx =>
        CronController.getTask(ctx)
    })

    // 更新定时任务
    cron.put("/tasks/:id", audited("cron.task.update", { ctx =>
        CronController.updateTask(ctx)
    }, riskLevel: 2))

    // 删除定时任务
    cron.delete("/tasks/:id", audited("cron.task.delete", { ctx =>
        CronController.deleteTask(ctx)
    }, riskLevel: 2))

    // 手动触发定时任务
    cron.post("/tasks/:id/trigger", audited("cron.task.trigger", { ctx =>
        CronController.triggerTask(ctx)
    }, riskLevel: 2))

    // 启用定时任务
    cron.post("/tasks/:id/enable", audited("cron.task.enable", { ctx =>
        CronController.enableTask(ctx)
    }, riskLevel: 3))

    // 禁用定时任务
    cron.post("/tasks/:id/disable", audited("cron.task.disable", { ctx =>
        CronController.disableTask(ctx)
    }, riskLevel: 3))
}
