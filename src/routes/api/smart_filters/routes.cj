package lanlu.routes.api.smart_filters

import cjoy.*
import lanlu.controllers.*
import lanlu.middleware.*

/**
 * 智能分类 API 路由
 */
public func registerSmartFilterRoutes(router: JoyRouters) {
    // 公开接口：获取启用的智能分类列表
    router.get("/api/smart_filters", { ctx =>
        SmartFilterController.getEnabledFilters(ctx)
    })

    // 管理端：获取所有智能分类
    router.get("/api/admin/smart_filters", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => SmartFilterController.adminList(ctx)
            case None => return
        }
    })

    // 管理端：获取单个智能分类
    router.get("/api/admin/smart_filters/{id}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => SmartFilterController.adminGet(ctx)
            case None => return
        }
    })

    // 管理端：创建智能分类
    router.post("/api/admin/smart_filters", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => SmartFilterController.adminCreate(ctx)
            case None => return
        }
    })

    // 管理端：更新智能分类
    router.put("/api/admin/smart_filters/{id}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => SmartFilterController.adminUpdate(ctx)
            case None => return
        }
    })

    // 管理端：删除智能分类
    router.delete("/api/admin/smart_filters/{id}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => SmartFilterController.adminDelete(ctx)
            case None => return
        }
    })

    // 管理端：批量更新排序顺序
    router.post("/api/admin/smart_filters/reorder", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => SmartFilterController.adminReorder(ctx)
            case None => return
        }
    })

    // 管理端：切换启用状态
    router.post("/api/admin/smart_filters/{id}/toggle", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => SmartFilterController.adminToggle(ctx)
            case None => return
        }
    })
}
