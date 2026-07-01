package lanlu.routes.api

import ace_web.*
import ace_router.*
import lanlu.contexts.plugin.interfaces.http.SourcePluginController
import lanlu.infrastructure.middleware.*

public func registerSourcePluginsRoutes(router: Router) {
    registerSourcePluginsRoutesAt(router, "/api/admin/source-plugins")
}

private func registerSourcePluginsRoutesAt(router: Router, basePath: String) {
    router.group(basePath) { source =>
        source.use(AuthMiddleware.requireAdminMiddleware())

        source.get("", { ctx: Context, next: Next =>
            SourcePluginController.listSourcePlugins(ctx)
        })

        source.post("/:namespace/action/:action", audited("source.action", { ctx: Context, next: Next =>
            SourcePluginController.sourceAction(ctx)
        }, riskLevel: 3))

        source.post("/:namespace/download", audited("source.download", { ctx: Context, next: Next =>
            SourcePluginController.sourceDownload(ctx)
        }, riskLevel: 2))

        // source_reader 通过 /:namespace/action/:action 统一入口，
        // 媒体准备由 WASM 插件内部处理，不开放通用代理端点。
    }
}