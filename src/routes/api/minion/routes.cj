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
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        MinionController.getTasksWithPagination(ctx)
    })

    // 根据ID获取任务
    router.get("/api/minion/tasks/{id}", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        MinionController.getTaskById(ctx)
    })

    // ========== 插件管理API ==========

    // 获取所有插件详情
    router.get("/api/plugins", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        MinionController.getAllPlugins(ctx)
    })

    // 根据类型获取插件
    router.get("/api/plugins/{type}", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        MinionController.getPluginsByType(ctx)
    })

    // 获取插件配置
    router.get("/api/plugins/{namespace}/config", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        MinionController.getPluginConfig(ctx)
    })

    // 更新插件配置
    router.put("/api/plugins/{namespace}/config", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        MinionController.updatePluginConfig(ctx)
    })

    // 启用或禁用插件
    router.put("/api/plugins/{namespace}/enabled", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        MinionController.setPluginEnabled(ctx)
    })

    // 发现并注册插件
    router.post("/api/plugins/discover", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        MinionController.discoverPlugins(ctx)
    })

    // 获取插件配置Schema
    router.get("/api/plugins/{namespace}/schema", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        MinionController.getPluginSchema(ctx)
    })
}
