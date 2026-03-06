package lanlu.routes.api

import ignite.*
import lanlu.contexts.asset.interfaces.http.AssetController
import lanlu.contexts.asset.interfaces.http.AssetUploadController
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

        assets.post("/upload/init", { ctx =>
            match (AuthMiddleware.requireUser(ctx)) {
                case Some(uid) => AssetUploadController.initUpload(ctx, uid)
                case None => return
            }
        })

        assets.put("/upload/chunk", { ctx =>
            AssetUploadController.uploadChunk(ctx)
        })

        assets.delete("/upload/:taskId", { ctx =>
            AssetUploadController.cancelUpload(ctx)
        })
    }
}
