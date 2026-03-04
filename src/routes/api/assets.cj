package lanlu.routes.api

import ignite.*
import lanlu.contexts.asset.interfaces.http.AssetController
import lanlu.infrastructure.middleware.*

/**
 * Asset routes module
 */
public class AssetsRoutes {
    public static func configure(router: App) {
        let assets = router.group("/api/assets")
        assets.use(AuthMiddleware.requiredAuthMiddleware())

        assets.get("/:id", { ctx =>
            AssetController.getAsset(ctx)
        })
    }
}
