package lanlu.routes.api

import ignite.*
import lanlu.contexts.plugin.interfaces.http.SourcePluginController
import lanlu.infrastructure.middleware.*

public func registerSourcePluginsRoutes(router: App) {
    registerSourcePluginsRoutesAt(router, "/api/admin/source-plugins")
}

private func registerSourcePluginsRoutesAt(router: App, basePath: String) {
    let source = router.group(basePath)
    source.use(AuthMiddleware.requireAdminMiddleware())

    source.get("", { ctx =>
        SourcePluginController.listSourcePlugins(ctx)
    })

    source.post("/:namespace/action/:action", audited("source.action", { ctx =>
        SourcePluginController.sourceAction(ctx)
    }, riskLevel: 3))

    source.post("/:namespace/download", audited("source.download", { ctx =>
        SourcePluginController.sourceDownload(ctx)
    }, riskLevel: 2))
}
