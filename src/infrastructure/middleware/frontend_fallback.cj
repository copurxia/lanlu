package lanlu.infrastructure.middleware

import ignite.*
import lanlu.contexts.system.interfaces.http.FrontendController

public func installFrontendFallbackMiddleware(app: App): Unit {
    app.use(frontendFallbackMiddleware())
}

public func frontendFallbackMiddleware(baseDir!: String = "frontend/out"): Handler {
    { ctx =>
        ctx.next()

        match (ctx.route()) {
            case Some(_) => return
            case None => ()
        }

        let method = ctx.method.trimAscii().toAsciiUpper()
        if (method != "GET" && method != "HEAD") {
            return
        }

        if (ctx.responseStatus != 404) {
            return
        }

        if (method == "HEAD") {
            FrontendController.servePathHead(ctx, baseDir: baseDir)
            return
        }

        FrontendController.servePath(ctx, baseDir: baseDir)
    }
}
