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
    cron.post("/start", { ctx =>
        CronController.startService(ctx)
    })

    // 停止CronService
    cron.post("/stop", { ctx =>
        CronController.stopService(ctx)
    })

    // 验证Cron表达式
    cron.post("/validate", { ctx =>
        CronController.validateExpression(ctx)
    })

    // 获取可用的任务类型（与 TaskRunner 保持一致）
    cron.get("/task-types", { ctx =>
        CronController.getTaskTypes(ctx)
    })

    // 获取定时任务列表（分页）
    cron.get("/tasks", { ctx =>
        CronController.getTasks(ctx)
    })

    // 创建定时任务
    cron.post("/tasks", { ctx =>
        CronController.createTask(ctx)
    })

    // 获取单个定时任务
    cron.get("/tasks/:id", { ctx =>
        CronController.getTask(ctx)
    })

    // 更新定时任务
    cron.put("/tasks/:id", { ctx =>
        CronController.updateTask(ctx)
    })

    // 删除定时任务
    cron.delete("/tasks/:id", { ctx =>
        CronController.deleteTask(ctx)
    })

    // 手动触发定时任务
    cron.post("/tasks/:id/trigger", { ctx =>
        CronController.triggerTask(ctx)
    })

    // 启用定时任务
    cron.post("/tasks/:id/enable", { ctx =>
        CronController.enableTask(ctx)
    })

    // 禁用定时任务
    cron.post("/tasks/:id/disable", { ctx =>
        CronController.disableTask(ctx)
    })
}
