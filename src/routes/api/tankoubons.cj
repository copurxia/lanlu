package lanlu.routes.api

import ignite.*
import lanlu.contexts.tankoubon.interfaces.http.TankoubonController
import lanlu.infrastructure.middleware.*

/**
 * 单行本API路由
 */
public func registerTankoubonRoutes(router: App) {
    let tankoubon = router.group("/api/tankoubons")
    tankoubon.use(AuthMiddleware.requiredAuthMiddleware())

    // 获取所有单行本
    tankoubon.get("", { ctx => 
        TankoubonController.getTankoubons(ctx)
    })
    
    // 根据ID获取单行本
    tankoubon.get("/:id", { ctx => 
        TankoubonController.getTankoubonById(ctx)
    })

    // 获取单行本统一 metadata
    tankoubon.get("/:id/metadata", { ctx =>
        TankoubonController.getMetadata(ctx)
    })

    // 创建新单行本
    tankoubon.put("", { ctx => 
        TankoubonController.createTankoubon(ctx)
    })
    
    // 更新单行本
    tankoubon.put("/:id", { ctx => 
        TankoubonController.updateTankoubon(ctx)
    })

    // 更新单行本统一 metadata
    tankoubon.put("/:id/metadata", { ctx =>
        TankoubonController.updateMetadata(ctx)
    })
    
    // 删除单行本
    tankoubon.delete("/:id", { ctx => 
        TankoubonController.deleteTankoubon(ctx)
    })
    
    // 向单行本添加档案
    tankoubon.put("/:id/:archive", { ctx => 
        TankoubonController.addArchiveToTankoubon(ctx)
    })
    
    // 从单行本移除档案
    tankoubon.delete("/:id/:archive", { ctx => 
        TankoubonController.removeArchiveFromTankoubon(ctx)
    })

    // 添加收藏
    tankoubon.put("/:id/favorite", { ctx =>
        TankoubonController.addFavorite(ctx)
    })

    // 取消收藏
    tankoubon.delete("/:id/favorite", { ctx =>
        TankoubonController.removeFavorite(ctx)
    })
}
