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

        recommendations.post("/interactions", audited("recommendation.interaction.record", { ctx =>
            RecommendationController.recordInteraction(ctx)
        }, riskLevel: 4))
    }
}
