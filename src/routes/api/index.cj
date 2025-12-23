package lrr4cj.routes.api

import cjoy.*
import lrr4cj.routes.api.archives.*
import lrr4cj.routes.api.database.*
import lrr4cj.routes.api.search.*
import lrr4cj.routes.api.categories.*
import lrr4cj.routes.api.plugins.*
import lrr4cj.routes.api.taskpool.*
import lrr4cj.routes.api.tankoubons.*
import lrr4cj.routes.api.shinobu.*
import lrr4cj.routes.api.auth.*
import lrr4cj.routes.api.tags.*
import lrr4cj.routes.api.user.*
import lrr4cj.routes.api.smart_filters.*
import lrr4cj.routes.api.cron.*
import lrr4cj.controllers.*

/**
 * API路由注册
 */
public func registerApiRoutes(router: JoyRouters) {
    // 注册档案相关路由
    ArchiveRoutes.configure(router)

    // 注册数据库相关路由
    DatabaseRoutes.configure(router)

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

    // 注册Shinobu相关路由
    registerShinobuRoutes(router)

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

    // 注册服务器信息路由
    router.get("/api/info", { ctx =>
        InfoController.getServerInfo(ctx)
    })
}

/**
 * 注册系统设置路由
 */
private func registerSystemSettingsRoutes(router: JoyRouters) {
    // 获取所有设置
    router.get("/api/system/settings", { ctx =>
        SystemSettingsController.getAllSettings(ctx)
    })

    // 按分类获取设置
    router.get("/api/system/settings/category/{category}", { ctx =>
        SystemSettingsController.getSettingsByCategory(ctx)
    })

    // 更新单个设置
    router.put("/api/system/settings", { ctx =>
        SystemSettingsController.updateSetting(ctx)
    })

    // 批量更新设置
    router.put("/api/system/settings/batch", { ctx =>
        SystemSettingsController.updateSettings(ctx)
    })

    // 获取设置分类
    router.get("/api/system/settings/categories", { ctx =>
        SystemSettingsController.getCategories(ctx)
    })

    // 重新加载设置缓存
    router.post("/api/system/settings/reload", { ctx =>
        SystemSettingsController.reloadCache(ctx)
    })
}
