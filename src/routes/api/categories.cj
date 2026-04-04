package lanlu.routes.api

import ignite.*
import lanlu.contexts.category.interfaces.http.CategoryController
import lanlu.infrastructure.middleware.*

/**
 * 分类API路由（新结构）
 */
public func registerCategoryRoutes(router: App) {
    let categories = router.group("/api/categories")
    categories.use(AuthMiddleware.requireAdminMiddleware())

    // 获取所有分类（管理员）
    categories.get("", { ctx =>
        CategoryController.getCategories(ctx)
    })

    // 创建新分类（需要管理员权限）
    categories.post("", audited("category.create", { ctx =>
        CategoryController.createCategory(ctx)
    }, riskLevel: 2))

    // 触发媒体库扫描（需要管理员权限）
    categories.post("/scan", audited("category.scan_all", { ctx =>
        CategoryController.scanAllCategories(ctx)
    }, riskLevel: 2))

    // 更新分类（需要管理员权限）
    categories.put("/:id", audited("category.update", { ctx =>
        CategoryController.updateCategory(ctx)
    }, riskLevel: 2))

    // 删除分类（需要管理员权限）
    categories.delete("/:id", audited("category.delete", { ctx =>
        CategoryController.deleteCategory(ctx)
    }, riskLevel: 2))

    // 触发分类扫描（需要管理员权限）
    categories.post("/:id/scan", audited("category.scan_one", { ctx =>
        CategoryController.scanCategory(ctx)
    }, riskLevel: 2))
}
