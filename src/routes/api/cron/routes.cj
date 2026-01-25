package lanlu.routes.api.cron

import cjoy.*
import lanlu.controllers.*
import lanlu.middleware.*

/**
 * Cron定时任务API路由
 */
public func registerCronRoutes(router: JoyRouters) {
    // 获取CronService状态
    router.get("/api/cron/status", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CronController.getStatus(ctx)
    })

    // 启动CronService
    router.post("/api/cron/start", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CronController.startService(ctx)
    })

    // 停止CronService
    router.post("/api/cron/stop", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CronController.stopService(ctx)
    })

    // 验证Cron表达式
    router.post("/api/cron/validate", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CronController.validateExpression(ctx)
    })

    // 获取可用的任务类型（与 TaskRunner 保持一致）
    router.get("/api/cron/task-types", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CronController.getTaskTypes(ctx)
    })

    // 获取定时任务列表（分页）
    router.get("/api/cron/tasks", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CronController.getTasks(ctx)
    })

    // 创建定时任务
    router.post("/api/cron/tasks", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CronController.createTask(ctx)
    })

    // 获取单个定时任务
    router.get("/api/cron/tasks/{id}", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CronController.getTask(ctx)
    })

    // 更新定时任务
    router.put("/api/cron/tasks/{id}", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CronController.updateTask(ctx)
    })

    // 删除定时任务
    router.delete("/api/cron/tasks/{id}", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CronController.deleteTask(ctx)
    })

    // 手动触发定时任务
    router.post("/api/cron/tasks/{id}/trigger", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CronController.triggerTask(ctx)
    })

    // 启用定时任务
    router.post("/api/cron/tasks/{id}/enable", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CronController.enableTask(ctx)
    })

    // 禁用定时任务
    router.post("/api/cron/tasks/{id}/disable", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CronController.disableTask(ctx)
    })
}
