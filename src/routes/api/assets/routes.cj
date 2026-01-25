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
            AssetController.getAsset(ctx)
        })

        router.post("/api/assets", { ctx =>
            match (AuthMiddleware.requireUser(ctx)) {
                case Some(uid) => AssetController.uploadAsset(ctx, uid)
                case None => ()
            }
        })
    }
}
