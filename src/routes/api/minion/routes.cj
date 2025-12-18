package lrr4cj.routes.api.minion

import cjoy.*
import lrr4cj.controllers.*
import lrr4cj.middleware.*

/**
 * Minion API路由
 */
public func registerMinionRoutes(router: JoyRouters) {
    // ========== 插件管理API ==========
    // 注意：任务相关的API已迁移到 TaskPoolController

    // 获取所有插件详情
    router.get("/api/plugins", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => MinionController.getAllPlugins(ctx)
            case None => return
        }
    })

    // 根据类型获取插件
    router.get("/api/plugins/{type}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => MinionController.getPluginsByType(ctx)
            case None => return
        }
    })

    // 获取插件配置
    router.get("/api/plugins/{namespace}/config", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => MinionController.getPluginConfig(ctx)
            case None => return
        }
    })

    // 更新插件配置
    router.put("/api/plugins/{namespace}/config", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => MinionController.updatePluginConfig(ctx)
            case None => return
        }
    })

    // 启用或禁用插件
    router.put("/api/plugins/{namespace}/enabled", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => MinionController.setPluginEnabled(ctx)
            case None => return
        }
    })

    // 发现并注册插件
    router.post("/api/plugins/discover", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => MinionController.discoverPlugins(ctx)
            case None => return
        }
    })

    // 获取插件配置Schema
    router.get("/api/plugins/{namespace}/schema", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => MinionController.getPluginSchema(ctx)
            case None => return
        }
    })
}
