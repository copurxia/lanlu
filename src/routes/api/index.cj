package lanlu.routes.api

import cjoy.*
import lanlu.routes.api.archives.*
import lanlu.routes.api.search.*
import lanlu.routes.api.categories.*
import lanlu.routes.api.plugins.*
import lanlu.routes.api.taskpool.*
import lanlu.routes.api.tankoubons.*
import lanlu.routes.api.auth.*
import lanlu.routes.api.tags.*
import lanlu.routes.api.user.*
import lanlu.routes.api.assets.*
import lanlu.routes.api.smart_filters.*
import lanlu.routes.api.cron.*
import lanlu.controllers.*
import lanlu.middleware.*

/**
 * API路由注册
 */
public func registerApiRoutes(router: JoyRouters) {
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
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        InfoController.getServerInfo(ctx)
    })
}

/**
 * 注册系统设置路由
 */
private func registerSystemSettingsRoutes(router: JoyRouters) {
    // 获取所有设置
    router.get("/api/system/settings", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => SystemSettingsController.getAllSettings(ctx)
            case None => return
        }
    })

    // 按分类获取设置
    // 更新单个设置
    router.put("/api/system/settings", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => SystemSettingsController.updateSetting(ctx)
            case None => return
        }
    })

    // 批量更新设置
    router.put("/api/system/settings/batch", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => SystemSettingsController.updateSettings(ctx)
            case None => return
        }
    })

    // 获取设置分类
    router.get("/api/system/settings/categories", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => SystemSettingsController.getCategories(ctx)
            case None => return
        }
    })

    // 重新加载设置缓存
    router.post("/api/system/settings/reload", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => SystemSettingsController.reloadCache(ctx)
            case None => return
        }
    })
}
