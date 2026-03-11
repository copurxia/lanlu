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
    categories.post("", { ctx =>
        CategoryController.createCategory(ctx)
    })

    // 触发媒体库扫描（需要管理员权限）
    categories.post("/scan", { ctx =>
        CategoryController.scanAllCategories(ctx)
    })

    // 更新分类（需要管理员权限）
    categories.put("/:id", { ctx =>
        CategoryController.updateCategory(ctx)
    })

    // 删除分类（需要管理员权限）
    categories.delete("/:id", { ctx =>
        CategoryController.deleteCategory(ctx)
    })

    // 触发分类扫描（需要管理员权限）
    categories.post("/:id/scan", { ctx =>
        CategoryController.scanCategory(ctx)
    })
}
