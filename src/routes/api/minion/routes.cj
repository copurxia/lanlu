package lrr4cj.routes.api.minion

import cjoy.*
import lrr4cj.controllers.*
import lrr4cj.middleware.*

/**
 * Minion API路由
 */
public func registerMinionRoutes(router: JoyRouters) {
    // ========== Minion任务API ==========

    // 分页获取任务列表
    router.get("/api/minion/tasks", { ctx =>
        AuthMiddleware.requiredAuth(ctx)
        MinionController.getTasksWithPagination(ctx)
    })

    // 根据ID获取任务
    router.get("/api/minion/tasks/{id}", { ctx =>
        AuthMiddleware.requiredAuth(ctx)
        MinionController.getTaskById(ctx)
    })

    // ========== 插件管理API ==========

    // 获取所有插件详情
    router.get("/api/plugins", { ctx =>
        AuthMiddleware.requiredAuth(ctx)
        MinionController.getAllPlugins(ctx)
    })

    // 根据类型获取插件
    router.get("/api/plugins/{type}", { ctx =>
        AuthMiddleware.requiredAuth(ctx)
        MinionController.getPluginsByType(ctx)
    })

    // 获取插件配置
    router.get("/api/plugins/{namespace}/config", { ctx =>
        AuthMiddleware.requiredAuth(ctx)
        MinionController.getPluginConfig(ctx)
    })

    // 更新插件配置
    router.put("/api/plugins/{namespace}/config", { ctx =>
        AuthMiddleware.requiredAuth(ctx)
        MinionController.updatePluginConfig(ctx)
    })

    // 启用或禁用插件
    router.put("/api/plugins/{namespace}/enabled", { ctx =>
        AuthMiddleware.requiredAuth(ctx)
        MinionController.setPluginEnabled(ctx)
    })

    // 发现并注册插件
    router.post("/api/plugins/discover", { ctx =>
        AuthMiddleware.requiredAuth(ctx)
        MinionController.discoverPlugins(ctx)
    })

    // 获取插件配置Schema
    router.get("/api/plugins/{namespace}/schema", { ctx =>
        AuthMiddleware.requiredAuth(ctx)
        MinionController.getPluginSchema(ctx)
    })
}