package lanlu.routes.api.assets

import cjoy.*
import lanlu.controllers.*
import lanlu.middleware.*

/**
 * Asset routes module
 */
public class AssetsRoutes {
    public static func configure(router: JoyRouters) {
        router.get("/api/assets/{id}", { ctx =>
            if (!AuthMiddleware.requiredAuth(ctx)) { return }
            AssetController.getAsset(ctx)
        })
    }
}
