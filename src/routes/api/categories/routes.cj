package lrr4cj.routes.api.categories

import cjoy.*
import lrr4cj.controllers.*
import lrr4cj.middleware.*

/**
 * 分类API路由
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
    
    // 创建新分类
    router.post("/api/categories", { ctx => 
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CategoryController.createCategory(ctx)
    })
    
    // 更新分类
    router.put("/api/categories/{id}", { ctx => 
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CategoryController.updateCategory(ctx)
    })
    
    // 删除分类
    router.delete("/api/categories/{id}", { ctx => 
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CategoryController.deleteCategory(ctx)
    })
    
    // 向分类添加档案
    router.post("/api/categories/{category_id}/archives/{archive_id}", { ctx => 
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CategoryController.addArchiveToCategory(ctx)
    })
    
    // 从分类移除档案
    router.delete("/api/categories/{category_id}/archives/{archive_id}", { ctx => 
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        CategoryController.removeArchiveFromCategory(ctx)
    })
}
