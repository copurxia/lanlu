package lanlu.routes.api

import ace_web.*
import ace_router.*
import lanlu.contexts.asset.interfaces.http.AssetController
import lanlu.contexts.asset.interfaces.http.AssetUploadController
import lanlu.infrastructure.middleware.*

private func withUser(action: (Context, Int64) -> Unit): Middleware {
    { ctx: Context, next: Next =>
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
    public static func configure(router: Router) {
        router.group("/api/assets") { assets =>
            assets.use(AuthMiddleware.requiredAuthMiddleware())

            assets.get("/:id", { ctx: Context, next: Next =>
                AssetController.getAsset(ctx)
            })

            assets.post("/upload/init", audited("asset.upload.init", withUser({ ctx, userId =>
                AssetUploadController.initUpload(ctx, userId)
            }), riskLevel: 2))

            assets.put("/upload/chunk", audited("asset.upload.chunk", { ctx: Context, next: Next =>
                AssetUploadController.uploadChunk(ctx)
            }, riskLevel: 3))

            assets.delete("/upload/:taskId", audited("asset.upload.cancel", { ctx: Context, next: Next =>
                AssetUploadController.cancelUpload(ctx)
            }, riskLevel: 3))
        }
    }
}