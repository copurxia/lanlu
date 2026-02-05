package lanlu.routes.api.assets

import cjoy.*
import lanlu.controllers.*

/**
 * Asset routes module
 */
public class AssetsRoutes {
    public static func configure(router: JoyRouters) {
        router.get("/api/assets/{id}", { ctx =>
            AssetController.getAsset(ctx)
        })
    }
}
