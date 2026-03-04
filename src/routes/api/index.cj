package lanlu.routes.api

import ignite.*
import lanlu.contexts.system.interfaces.http.InfoController
import lanlu.contexts.system.interfaces.http.SystemSettingsController
import lanlu.infrastructure.middleware.*

/**
 * API路由注册
 */
public func registerApiRoutes(router: App) {
    // 注册档案相关路由
    ArchiveRoutes.configure(router)

    // 注册搜索相关路由
    SearchRoutes.configure(router)

    // 注册分类相关路由
    registerCategoryRoutes(router)

    // 注册插件相关路由
    registerPluginsRoutes(router)

    // 注册TaskPool相关路由（任务管理）
    registerTaskPoolRoutes(router)

    // 注册单行本相关路由
    registerTankoubonRoutes(router)

    // 注册认证/用户token相关路由
    registerAuthRoutes(router)

    // 注册标签路由
    registerTagRoutes(router)

    // 注册智能分类路由
    registerSmartFilterRoutes(router)

    // 注册Cron定时任务路由
    registerCronRoutes(router)

    // 注册系统设置路由
    registerSystemSettingsRoutes(router)

    // 注册用户统计路由
    UserRoutes.configure(router)

    // 注册资源文件路由
    AssetsRoutes.configure(router)

    // 注册服务器信息路由
    router.get("/api/info", { ctx =>
        InfoController.getServerInfo(ctx)
    })
}

/**
 * 注册系统设置路由
 */
private func registerSystemSettingsRoutes(router: App) {
    // Canonical admin paths
    registerSystemSettingsRoutesAt(router, "/api/admin/system/settings")
}

private func registerSystemSettingsRoutesAt(router: App, basePath: String) {
    let settings = router.group(basePath)
    settings.use(AuthMiddleware.requireAdminMiddleware())

    // 获取所有设置
    settings.get("", { ctx =>
        SystemSettingsController.getAllSettings(ctx)
    })

    // 更新单个设置
    settings.put("", { ctx =>
        SystemSettingsController.updateSetting(ctx)
    })

    // 批量更新设置
    settings.put("/batch", { ctx =>
        SystemSettingsController.updateSettings(ctx)
    })

    // 获取设置分类
    settings.get("/categories", { ctx =>
        SystemSettingsController.getCategories(ctx)
    })

    // 重新加载设置缓存
    settings.post("/reload", { ctx =>
        SystemSettingsController.reloadCache(ctx)
    })
}
