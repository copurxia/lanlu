package lanlu.routes.api.plugins

import cjoy.*
import lanlu.controllers.*
import lanlu.middleware.*

/**
 * 插件管理API路由
 */
public func registerPluginsRoutes(router: JoyRouters) {
    // Canonical admin paths
    registerPluginsRoutesAt(router, "/api/admin/plugins")
}

private func registerPluginsRoutesAt(router: JoyRouters, basePath: String) {
    // ========== 插件管理API ==========

    // 获取所有插件详情
    router.get(basePath, { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => PluginsController.getAllPlugins(ctx)
            case None => return
        }
    })

    // 获取插件配置
    router.get("${basePath}/{namespace}/config", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => PluginsController.getPluginConfig(ctx)
            case None => return
        }
    })

    // 更新插件配置
    router.put("${basePath}/{namespace}/config", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => PluginsController.updatePluginConfig(ctx)
            case None => return
        }
    })

    // 启用或禁用插件
    router.put("${basePath}/{namespace}/enabled", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => PluginsController.setPluginEnabled(ctx)
            case None => return
        }
    })

    // 安装/更新插件
    router.post("${basePath}/install", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => PluginsController.installPlugin(ctx)
            case None => return
        }
    })

    // 删除插件
    router.delete("${basePath}/{namespace}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => PluginsController.deletePlugin(ctx)
            case None => return
        }
    })

    // 更新插件（使用插件声明的 update_url）
    router.post("${basePath}/{namespace}/update", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => PluginsController.updatePlugin(ctx)
            case None => return
        }
    })

    // 检查插件更新（使用 update_url；优先走 ETag 条件请求，force 可跳过）
    router.post("${basePath}/{namespace}/check_update", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => PluginsController.checkUpdatePlugin(ctx)
            case None => return
        }
    })
}
