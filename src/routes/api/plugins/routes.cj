package lrr4cj.routes.api.plugins

import cjoy.*
import lrr4cj.controllers.*
import lrr4cj.middleware.*

/**
 * 插件管理API路由
 */
public func registerPluginsRoutes(router: JoyRouters) {
    // ========== 插件管理API ==========

    // 获取所有插件详情
    router.get("/api/plugins", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => PluginsController.getAllPlugins(ctx)
            case None => return
        }
    })

    // 根据类型获取插件
    router.get("/api/plugins/{type}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => PluginsController.getPluginsByType(ctx)
            case None => return
        }
    })

    // 获取插件配置
    router.get("/api/plugins/{namespace}/config", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => PluginsController.getPluginConfig(ctx)
            case None => return
        }
    })

    // 更新插件配置
    router.put("/api/plugins/{namespace}/config", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => PluginsController.updatePluginConfig(ctx)
            case None => return
        }
    })

    // 启用或禁用插件
    router.put("/api/plugins/{namespace}/enabled", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => PluginsController.setPluginEnabled(ctx)
            case None => return
        }
    })

    // 获取插件配置Schema
    router.get("/api/plugins/{namespace}/schema", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => PluginsController.getPluginSchema(ctx)
            case None => return
        }
    })
}