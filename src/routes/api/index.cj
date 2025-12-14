package lrr4cj.routes.api

import cjoy.*
import lrr4cj.routes.api.archives.*
import lrr4cj.routes.api.database.*
import lrr4cj.routes.api.search.*
import lrr4cj.routes.api.categories.*
import lrr4cj.routes.api.minion.*
import lrr4cj.routes.api.tankoubons.*
import lrr4cj.routes.api.shinobu.*
import lrr4cj.routes.api.auth.*
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

    // 注册Minion相关路由
    registerMinionRoutes(router)

    // 注册单行本相关路由
    registerTankoubonRoutes(router)

    // 注册Shinobu相关路由
    registerShinobuRoutes(router)

    // 注册认证/用户token相关路由
    registerAuthRoutes(router)
    
    // 注册服务器信息路由
    router.get("/api/info", { ctx =>
        InfoController.getServerInfo(ctx)
    })
}
