package lanlu.infrastructure.middleware

import ace_web.*
import lanlu.contexts.system.interfaces.http.FrontendController

public func installFrontendFallbackMiddleware(app: App): Unit {
    app.use(frontendFallbackMiddleware())
}

public func frontendFallbackMiddleware(baseDir!: String = "frontend/out"): Middleware {
    { ctx: Context, next: Next =>
        next()

        let method = ctx.method.trimAscii().toAsciiUpper()
        if (method != "GET" && method != "HEAD") {
            return
        }

        if (ctx.status != 404) {
            return
        }

        // 短路：已知非静态资源路径直接返回 404，避免每个探测请求都触发
        // servePath 的多次 exists/FileInfo 文件系统调用风暴，降低 fd 瞬时压力
        if (isKnownNonAssetPath(ctx.path)) {
            ctx.status = 404
            return
        }

        if (method == "HEAD") {
            FrontendController.servePathHead(ctx, baseDir: baseDir)
            return
        }

        FrontendController.servePath(ctx, baseDir: baseDir)
    }
}

/**
 * 判断请求路径是否为已知非前端静态资源路径。
 * 命中时跳过静态文件服务，直接 404，避免无谓的文件系统探测。
 */
private func isKnownNonAssetPath(path: String): Bool {
    let cleanPath = if (path.contains("?")) {
        path.split("?")[0]
    } else {
        path
    }
    let lower = cleanPath.trimAscii().toAsciiLower()
    // favicon/robots/well-known 等站点元数据，前端 out 中不存在对应文件
    if (lower == "/favicon.ico" || lower == "/robots.txt" || lower == "/sitemap.xml" ||
        lower == "/apple-touch-icon.png" || lower == "/apple-touch-icon-precomposed.png" ||
        lower == "/manifest.json" || lower == "/ads.txt" || lower == "/security.txt") {
        return true
    }
    // .well-known 前缀及隐藏路径通常无对应静态文件
    if (lower.startsWith("/.well-known/") || lower.startsWith("/.")) {
        return true
    }
    return false
}
