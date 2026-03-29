package lanlu.routes.api

import ignite.*
import lanlu.contexts.recommendation.interfaces.http.RecommendationController
import lanlu.infrastructure.middleware.*

public class RecommendationRoutes {
    public static func configure(router: App) {
        let recommendations = router.group("/api/recommendations")
        recommendations.use(AuthMiddleware.requiredAuthMiddleware())

        recommendations.get("", { ctx =>
            RecommendationController.getRecommendations(ctx)
        })

        recommendations.post("/interactions", { ctx =>
            RecommendationController.recordInteraction(ctx)
        })
    }
}
