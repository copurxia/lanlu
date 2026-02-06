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
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CronController.getStatus(ctx)
            case None => return
        }
    })

    // 启动CronService
    router.post("/api/cron/start", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CronController.startService(ctx)
            case None => return
        }
    })

    // 停止CronService
    router.post("/api/cron/stop", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CronController.stopService(ctx)
            case None => return
        }
    })

    // 验证Cron表达式
    router.post("/api/cron/validate", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CronController.validateExpression(ctx)
            case None => return
        }
    })

    // 获取可用的任务类型（与 TaskRunner 保持一致）
    router.get("/api/cron/task-types", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CronController.getTaskTypes(ctx)
            case None => return
        }
    })

    // 获取定时任务列表（分页）
    router.get("/api/cron/tasks", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CronController.getTasks(ctx)
            case None => return
        }
    })

    // 创建定时任务
    router.post("/api/cron/tasks", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CronController.createTask(ctx)
            case None => return
        }
    })

    // 获取单个定时任务
    router.get("/api/cron/tasks/{id}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CronController.getTask(ctx)
            case None => return
        }
    })

    // 更新定时任务
    router.put("/api/cron/tasks/{id}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CronController.updateTask(ctx)
            case None => return
        }
    })

    // 删除定时任务
    router.delete("/api/cron/tasks/{id}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CronController.deleteTask(ctx)
            case None => return
        }
    })

    // 手动触发定时任务
    router.post("/api/cron/tasks/{id}/trigger", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CronController.triggerTask(ctx)
            case None => return
        }
    })

    // 启用定时任务
    router.post("/api/cron/tasks/{id}/enable", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CronController.enableTask(ctx)
            case None => return
        }
    })

    // 禁用定时任务
    router.post("/api/cron/tasks/{id}/disable", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CronController.disableTask(ctx)
            case None => return
        }
    })
}
