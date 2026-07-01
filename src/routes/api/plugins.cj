package lanlu.routes.api

import ace_web.*
import ace_router.*
import lanlu.contexts.plugin.interfaces.http.PluginsController
import lanlu.infrastructure.middleware.*

/**
 * 插件管理API路由
 */
public func registerPluginsRoutes(router: Router) {
    // Canonical admin paths
    registerPluginsRoutesAt(router, "/api/admin/plugins")
}

private func registerPluginsRoutesAt(router: Router, basePath: String) {
    router.group(basePath) { plugins =>
        plugins.use(AuthMiddleware.requireAdminMiddleware())

        // ========== 插件管理API ==========

        // 获取所有插件详情
        plugins.get("", { ctx: Context, next: Next =>
            PluginsController.getAllPlugins(ctx)
        })

        // 获取插件配置
        plugins.get("/:namespace/config", { ctx: Context, next: Next =>
            PluginsController.getPluginConfig(ctx)
        })

        // 更新插件配置
        plugins.put("/:namespace/config", audited("plugin.config.update", { ctx: Context, next: Next =>
            PluginsController.updatePluginConfig(ctx)
        }, riskLevel: 2))

        // 启用或禁用插件
        plugins.put("/:namespace/enabled", audited("plugin.enabled.update", { ctx: Context, next: Next =>
            PluginsController.setPluginEnabled(ctx)
        }, riskLevel: 2))

        // 安装/更新插件
        plugins.post("/install", audited("plugin.install", { ctx: Context, next: Next =>
            PluginsController.installPlugin(ctx)
        }, riskLevel: 2))

        // 删除插件
        plugins.delete("/:namespace", audited("plugin.delete", { ctx: Context, next: Next =>
            PluginsController.deletePlugin(ctx)
        }, riskLevel: 2))

        // 更新插件（使用插件声明的 update_url）
        plugins.post("/:namespace/update", audited("plugin.update", { ctx: Context, next: Next =>
            PluginsController.updatePlugin(ctx)
        }, riskLevel: 2))

        // 检查插件更新（使用 update_url；优先走 ETag 条件请求，force 可跳过）
        plugins.post("/:namespace/check_update", audited("plugin.check_update", { ctx: Context, next: Next =>
            PluginsController.checkUpdatePlugin(ctx)
        }, riskLevel: 3))
    }
}