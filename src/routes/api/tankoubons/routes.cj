package lanlu.routes.api.tankoubons

import cjoy.*
import lanlu.controllers.*
import lanlu.middleware.*

/**
 * 单行本API路由
 */
public func registerTankoubonRoutes(router: JoyRouters) {
    // 获取所有单行本
    router.get("/api/tankoubons", { ctx => 
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TankoubonController.getTankoubons(ctx)
    })
    
    // 根据ID获取单行本
    router.get("/api/tankoubons/{id}", { ctx => 
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TankoubonController.getTankoubonById(ctx)
    })

    // 获取合集封面（cover 或 fallback 到首个 archive）
    router.get("/api/tankoubons/{id}/thumbnail", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TankoubonController.getThumbnail(ctx)
    })
    
    // 创建新单行本
    router.put("/api/tankoubons", { ctx => 
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TankoubonController.createTankoubon(ctx)
    })
    
    // 更新单行本
    router.put("/api/tankoubons/{id}", { ctx => 
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TankoubonController.updateTankoubon(ctx)
    })
    
    // 删除单行本
    router.delete("/api/tankoubons/{id}", { ctx => 
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TankoubonController.deleteTankoubon(ctx)
    })
    
    // 向单行本添加档案
    router.put("/api/tankoubons/{id}/{archive}", { ctx => 
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TankoubonController.addArchiveToTankoubon(ctx)
    })
    
    // 从单行本移除档案
    router.delete("/api/tankoubons/{id}/{archive}", { ctx => 
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TankoubonController.removeArchiveFromTankoubon(ctx)
    })

    // 添加收藏
    router.put("/api/tankoubons/{id}/favorite", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TankoubonController.addFavorite(ctx)
    })

    // 取消收藏
    router.delete("/api/tankoubons/{id}/favorite", { ctx =>
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        TankoubonController.removeFavorite(ctx)
    })
}
