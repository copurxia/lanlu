package lanlu.routes.api

import ignite.*
import lanlu.contexts.asset.interfaces.http.AssetController
import lanlu.contexts.asset.interfaces.http.AssetUploadController
import lanlu.infrastructure.middleware.*

private func withUser(action: (Ctx, Int64) -> Unit): Handler {
    { ctx =>
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) => action(ctx, userId)
            case None => return
        }
    }
}

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

        assets.post("/upload/init", audited("asset.upload.init", withUser({ ctx, userId =>
            AssetUploadController.initUpload(ctx, userId)
        }), riskLevel: 2))

        assets.put("/upload/chunk", audited("asset.upload.chunk", { ctx =>
            AssetUploadController.uploadChunk(ctx)
        }, riskLevel: 3))

        assets.delete("/upload/:taskId", audited("asset.upload.cancel", { ctx =>
            AssetUploadController.cancelUpload(ctx)
        }, riskLevel: 3))
    }
}
