package lanlu.routes.api

import ace_web.*
import ace_router.*
import lanlu.contexts.tankoubon.interfaces.http.TankoubonController
import lanlu.infrastructure.middleware.*

/**
 * 单行本API路由
 */
public func registerTankoubonRoutes(router: Router) {
    router.group("/api/tankoubons") { tankoubon =>
        tankoubon.use(AuthMiddleware.requiredAuthMiddleware())

        // 获取所有单行本
        tankoubon.get("", { ctx: Context, next: Next => 
            TankoubonController.getTankoubons(ctx)
        })

        // 获取单行本统一 metadata
        tankoubon.get("/:id/metadata", { ctx: Context, next: Next =>
            TankoubonController.getMetadata(ctx)
        })

        // 创建新单行本
        tankoubon.put("", { ctx: Context, next: Next => 
            TankoubonController.createTankoubon(ctx)
        })

        // 更新单行本统一 metadata
        tankoubon.put("/:id/metadata", { ctx: Context, next: Next =>
            TankoubonController.updateMetadata(ctx)
        })

        // 删除单行本
        tankoubon.delete("/:id", { ctx: Context, next: Next => 
            TankoubonController.deleteTankoubon(ctx)
        })

        // 向单行本添加档案
        tankoubon.put("/:id/:archive", { ctx: Context, next: Next => 
            TankoubonController.addArchiveToTankoubon(ctx)
        })

        // 从单行本移除档案
        tankoubon.delete("/:id/:archive", { ctx: Context, next: Next => 
            TankoubonController.removeArchiveFromTankoubon(ctx)
        })

        // 添加收藏
        tankoubon.put("/:id/favorite", { ctx: Context, next: Next =>
            TankoubonController.addFavorite(ctx)
        })

        // 取消收藏
        tankoubon.delete("/:id/favorite", { ctx: Context, next: Next =>
            TankoubonController.removeFavorite(ctx)
        })
    }
}