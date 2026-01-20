package lrr4cj.routes.api.assets

import cjoy.*
import lrr4cj.controllers.*
import lrr4cj.middleware.*

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
