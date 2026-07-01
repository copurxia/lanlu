package lanlu.routes.api

import ace_web.*
import ace_router.*
import lanlu.contexts.smart_filter.interfaces.http.SmartFilterController
import lanlu.infrastructure.middleware.*

/**
 * 智能分类 API 路由
 */
public func registerSmartFilterRoutes(router: Router) {
    router.group("/api/smart_filters") { smartFilters =>
        smartFilters.use(AuthMiddleware.requiredAuthMiddleware())

        // 获取启用的智能分类列表
        smartFilters.get("", { ctx: Context, next: Next =>
            SmartFilterController.getEnabledFilters(ctx)
        })
    }

    router.group("/api/admin/smart_filters") { adminSmartFilters =>
        adminSmartFilters.use(AuthMiddleware.requireAdminMiddleware())

        // 管理端：获取所有智能分类
        adminSmartFilters.get("", { ctx: Context, next: Next =>
            SmartFilterController.adminList(ctx)
        })

        // 管理端：获取单个智能分类
        adminSmartFilters.get("/:id", { ctx: Context, next: Next =>
            SmartFilterController.adminGet(ctx)
        })

        // 管理端：创建智能分类
        adminSmartFilters.post("", audited("smart_filter.admin.create", { ctx: Context, next: Next =>
            SmartFilterController.adminCreate(ctx)
        }, riskLevel: 2))

        // 管理端：更新智能分类
        adminSmartFilters.put("/:id", audited("smart_filter.admin.update", { ctx: Context, next: Next =>
            SmartFilterController.adminUpdate(ctx)
        }, riskLevel: 2))

        // 管理端：删除智能分类
        adminSmartFilters.delete("/:id", audited("smart_filter.admin.delete", { ctx: Context, next: Next =>
            SmartFilterController.adminDelete(ctx)
        }, riskLevel: 2))

        // 管理端：批量更新排序顺序
        adminSmartFilters.post("/reorder", audited("smart_filter.admin.reorder", { ctx: Context, next: Next =>
            SmartFilterController.adminReorder(ctx)
        }, riskLevel: 3))

        // 管理端：切换启用状态
        adminSmartFilters.post("/:id/toggle", audited("smart_filter.admin.toggle", { ctx: Context, next: Next =>
            SmartFilterController.adminToggle(ctx)
        }, riskLevel: 3))
    }
}