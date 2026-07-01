package lanlu.routes.api

import ace_web.*
import ace_router.*
import lanlu.contexts.category.interfaces.http.CategoryController
import lanlu.infrastructure.middleware.*

/**
 * 分类API路由（新结构）
 */
public func registerCategoryRoutes(router: Router) {
    router.group("/api/categories") { userCategories =>
        userCategories.use(AuthMiddleware.requiredAuthMiddleware())

        // 获取所有分类（所有登录用户）
        userCategories.get("", { ctx: Context, next: Next =>
            CategoryController.getCategories(ctx)
        })
    }

    router.group("/api/categories") { adminCategories =>
        adminCategories.use(AuthMiddleware.requireAdminMiddleware())

        // 创建新分类（需要管理员权限）
        adminCategories.post("", audited("category.create", { ctx: Context, next: Next =>
            CategoryController.createCategory(ctx)
        }, riskLevel: 2))

        // 触发媒体库扫描（需要管理员权限）
        adminCategories.post("/scan", audited("category.scan_all", { ctx: Context, next: Next =>
            CategoryController.scanAllCategories(ctx)
        }, riskLevel: 2))

        // 更新分类（需要管理员权限）
        adminCategories.put("/:id", audited("category.update", { ctx: Context, next: Next =>
            CategoryController.updateCategory(ctx)
        }, riskLevel: 2))

        // 删除分类（需要管理员权限）
        adminCategories.delete("/:id", audited("category.delete", { ctx: Context, next: Next =>
            CategoryController.deleteCategory(ctx)
        }, riskLevel: 2))

        // 触发分类扫描（需要管理员权限）
        adminCategories.post("/:id/scan", audited("category.scan_one", { ctx: Context, next: Next =>
            CategoryController.scanCategory(ctx)
        }, riskLevel: 2))
    }
}