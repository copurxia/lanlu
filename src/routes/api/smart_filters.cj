package lanlu.routes.api

import ignite.*
import lanlu.contexts.smart_filter.interfaces.http.SmartFilterController
import lanlu.infrastructure.middleware.*

/**
 * 智能分类 API 路由
 */
public func registerSmartFilterRoutes(router: App) {
    let smartFilters = router.group("/api/smart_filters")
    smartFilters.use(AuthMiddleware.requiredAuthMiddleware())

    // 获取启用的智能分类列表
    smartFilters.get("", { ctx =>
        SmartFilterController.getEnabledFilters(ctx)
    })

    let adminSmartFilters = router.group("/api/admin/smart_filters")
    adminSmartFilters.use(AuthMiddleware.requireAdminMiddleware())

    // 管理端：获取所有智能分类
    adminSmartFilters.get("", { ctx =>
        SmartFilterController.adminList(ctx)
    })

    // 管理端：获取单个智能分类
    adminSmartFilters.get("/:id", { ctx =>
        SmartFilterController.adminGet(ctx)
    })

    // 管理端：创建智能分类
    adminSmartFilters.post("", { ctx =>
        SmartFilterController.adminCreate(ctx)
    })

    // 管理端：更新智能分类
    adminSmartFilters.put("/:id", { ctx =>
        SmartFilterController.adminUpdate(ctx)
    })

    // 管理端：删除智能分类
    adminSmartFilters.delete("/:id", { ctx =>
        SmartFilterController.adminDelete(ctx)
    })

    // 管理端：批量更新排序顺序
    adminSmartFilters.post("/reorder", { ctx =>
        SmartFilterController.adminReorder(ctx)
    })

    // 管理端：切换启用状态
    adminSmartFilters.post("/:id/toggle", { ctx =>
        SmartFilterController.adminToggle(ctx)
    })
}
