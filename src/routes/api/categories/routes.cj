package lanlu.routes.api.categories

import cjoy.*
import lanlu.controllers.*
import lanlu.middleware.*

/**
 * 分类API路由（新结构）
 */
public func registerCategoryRoutes(router: JoyRouters) {
    // 获取所有分类
    router.get("/api/categories", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CategoryController.getCategories(ctx)
    })

    // 根据ID获取分类
    router.get("/api/categories/{id}", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CategoryController.getCategoryById(ctx)
    })

    // 创建新分类（需要管理员权限）
    router.post("/api/categories", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CategoryController.createCategory(ctx)
            case None => return
        }
    })

    // 更新分类（需要管理员权限）
    router.put("/api/categories/{id}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CategoryController.updateCategory(ctx)
            case None => return
        }
    })

    // 删除分类（需要管理员权限）
    router.delete("/api/categories/{id}", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CategoryController.deleteCategory(ctx)
            case None => return
        }
    })

    // 触发分类扫描（需要管理员权限）
    router.post("/api/categories/{id}/scan", { ctx =>
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(_) => CategoryController.scanCategory(ctx)
            case None => return
        }
    })

}
