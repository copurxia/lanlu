package lanlu.routes.api.shinobu

import cjoy.*
import lanlu.controllers.*
import lanlu.middleware.*

/**
 * Shinobu API路由
 */
public func registerShinobuRoutes(router: JoyRouters) {
    // 获取Shinobu状态
    router.get("/api/shinobu", { ctx => 
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        ShinobuController.getShinobuStatus(ctx)
    })
    
    // 停止Shinobu
    router.post("/api/shinobu/stop", { ctx => 
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        ShinobuController.stopShinobu(ctx)
    })
    
    // 重启Shinobu
    router.post("/api/shinobu/restart", { ctx => 
        if (!AuthMiddleware.requiredAuth(ctx)) { return }
        ShinobuController.restartShinobu(ctx)
    })
}
