package lanlu.routes.api

import ace_web.*
import ace_router.*
import lanlu.contexts.recommendation.interfaces.http.RecommendationController
import lanlu.infrastructure.middleware.*

public class RecommendationRoutes {
    public static func configure(router: Router) {
        router.group("/api/recommendations") { recommendations =>
            recommendations.use(AuthMiddleware.requiredAuthMiddleware())

            recommendations.get("", { ctx: Context, next: Next =>
                RecommendationController.getRecommendations(ctx)
            })

            recommendations.post("/interactions", audited("recommendation.interaction.record", { ctx: Context, next: Next =>
                RecommendationController.recordInteraction(ctx)
            }, riskLevel: 4))
        }
    }
}