package lanlu.contexts.system.interfaces.http

import ignite.*
import std.fs.*
import lanlu.shared.utils.*

/**
 * 前端控制器
 * 处理前端静态文件服务
 */
public class FrontendController {

    private static func resolveRequestPath(ctx: Ctx): (String, String, String) {
        let path = ctx.paramsOpt("*") ?? ctx.path
        let cleanPath = if (path.contains("?")) { path.split("?")[0] } else { path }
        var relativePath = cleanPath
        while (relativePath.startsWith("/")) { relativePath = relativePath[1..relativePath.size] }
        (path, cleanPath, relativePath)
    }

    /**
     * 统一的路径服务函数
     * 根据请求路径自动判断是文件还是目录，目录时自动添加index.html
     * @param baseDir 前端静态文件的基础目录，默认为 "frontend/out"
     */
    public static func servePath(ctx: Ctx, baseDir!: String = "frontend/out") {
        try {
            // 获取并清理路径
            let (path, cleanPath, relativePath) = resolveRequestPath(ctx)
            println("Request path: ${path}, Clean path: ${cleanPath}, Relative path: ${relativePath}, Base dir: ${baseDir}")

            // 处理根路径
            if (relativePath.isEmpty()) {
                println("Root path request, using index.html")
                return serveFile(ctx, "${baseDir}/index.html")
            }

            // 构建基础路径
            let basePath = FileUtils.joinPath(baseDir, relativePath)
            println("Initial file path: ${basePath}")

            // 尝试直接访问文件
            if (exists(basePath) && !FileInfo(basePath).isDirectory()) {
                return serveFile(ctx, basePath)
            }

            // 尝试React路由映射（针对.txt文件）
            if (relativePath.endsWith(".txt")) {
                let dirPath = relativePath.replace(".txt", "")
                let txtIndexPath = FileUtils.joinPath(FileUtils.joinPath(baseDir, dirPath), "index.txt")
                println("Trying React route mapping: ${txtIndexPath}")
                
                if (exists(txtIndexPath)) {
                    return serveFile(ctx, txtIndexPath)
                }
            }

            // 尝试添加index.html
            let indexPath = FileUtils.joinPath(basePath, "index.html")
            println("Directory or file not found, trying with index.html: ${indexPath}")

            if (exists(indexPath)) {
                return serveFile(ctx, indexPath)
            }

            // 所有尝试都失败，返回404
            println("File not found: ${indexPath}")
            FrontendController.serve404(ctx)
            
        } catch (ex: Exception) {
            ctx.status(500).sendString("Error serving file: ${ex.message}")
        }
    }

    /**
     * 服务文件内容
     */
    private static func serveFile(ctx: Ctx, filePath: String) {
        println("Serving file: ${filePath}")

        if (!exists(filePath)) {
            println("File not found: ${filePath}")
            FrontendController.serve404(ctx)
            return
        }

        let (resolvedPath, logicalPath, isBrotli, varyAcceptEncoding) = resolveStaticAssetVariant(ctx, filePath)
        let fileInfo = FileInfo(resolvedPath)
        let fileSize = fileInfo.size
        let lastModified = fileInfo.lastModificationTime

        let bytes = File.readFrom(Path(resolvedPath))
        let contentType = getContentType(logicalPath)

        let etag = CacheUtils.generateETag("${resolvedPath}:${fileSize}:${lastModified}:${if (isBrotli) { "br" } else { "identity" }}")

        if (CacheUtils.checkIfNoneMatch(ctx, etag)) {
            applyVariantHeaders(ctx, isBrotli, varyAcceptEncoding, fileSize, false)
            sendNotModifiedByPolicy(ctx, logicalPath, etag)
            return
        }

        ctx.status(200)
        applyCacheHeadersByPolicy(ctx, logicalPath, etag)
        applyVariantHeaders(ctx, isBrotli, varyAcceptEncoding, fileSize, true)
        ctx.setHeader("Content-Type", contentType)
        ctx.send(bytes)
    }

    /**
     * 服务404
     * @param baseDir 前端静态文件的基础目录，默认为 "frontend/out"
     */
    public static func serve404(ctx: Ctx, baseDir!: String = "frontend/out") {
        try {
            // 尝试使用自定义404页面
            let custom404Path = "${baseDir}/404/index.html"
            if (exists(custom404Path)) {
                let bytes = File.readFrom(Path(custom404Path))
                CacheUtils.setNoCacheHeaders(ctx)
                ctx.setHeader("Content-Type", "text/html; charset=utf-8")
                ctx.status(404).send(bytes)
                return
            }

            // 如果自定义404不存在，返回默认错误信息
            CacheUtils.setNoCacheHeaders(ctx)
            ctx.status(404).sendString("404 - Page not found")
        } catch (ex: Exception) {
            CacheUtils.setNoCacheHeaders(ctx)
            ctx.status(500).sendString("Error serving 404 page: ${ex.message}")
        }
    }

    /**
     * 根据文件扩展名获取Content-Type
     */
    private static func getContentType(filePath: String): String {
        let defaultType = "application/octet-stream"
        let normalizedPath = filePath.trimAscii().toAsciiLower()

        // 简单的文件扩展名检查
        if (normalizedPath.endsWith(".html")) {
            return "text/html; charset=utf-8"
        } else if (normalizedPath.endsWith(".txt")) {
            return "text/plain; charset=utf-8"
        } else if (normalizedPath.endsWith(".css")) {
            return "text/css; charset=utf-8"
        } else if (normalizedPath.endsWith(".js")) {
            return "application/javascript; charset=utf-8"
        } else if (normalizedPath.endsWith(".json")) {
            return "application/json; charset=utf-8"
        } else if (normalizedPath.endsWith(".webmanifest")) {
            return "application/manifest+json; charset=utf-8"
        } else if (normalizedPath.endsWith(".png")) {
            return "image/png"
        } else if (normalizedPath.endsWith(".jpg") || normalizedPath.endsWith(".jpeg")) {
            return "image/jpeg"
        } else if (normalizedPath.endsWith(".gif")) {
            return "image/gif"
        } else if (normalizedPath.endsWith(".svg")) {
            return "image/svg+xml"
        } else if (normalizedPath.endsWith(".ico")) {
            return "image/x-icon"
        } else if (normalizedPath.endsWith(".woff")) {
            return "font/woff"
        } else if (normalizedPath.endsWith(".woff2")) {
            return "font/woff2"
        } else if (normalizedPath.endsWith(".ttf")) {
            return "font/ttf"
        } else if (normalizedPath.endsWith(".eot")) {
            return "application/vnd.ms-fontobject"
        } else {
            return defaultType
        }
    }

    /**
     * 为静态导出中的文本资源选择可用的预压缩 Brotli 变体。
     * 返回值依次为：
     * - 实际读取路径
     * - 逻辑资源路径（用于 Content-Type / 缓存策略）
     * - 是否返回 Brotli 变体
     * - 是否需要设置 Vary: Accept-Encoding
     */
    private static func resolveStaticAssetVariant(ctx: Ctx, filePath: String): (String, String, Bool, Bool) {
        if (!isBrotliNegotiableTextAsset(filePath)) {
            return (filePath, filePath, false, false)
        }

        let brotliPath = "${filePath}.br"
        if (clientAcceptsBrotli(ctx) && exists(brotliPath)) {
            return (brotliPath, filePath, true, true)
        }

        return (filePath, filePath, false, true)
    }

    private static func isBrotliNegotiableTextAsset(filePath: String): Bool {
        let normalized = filePath.trimAscii().toAsciiLower()
        return normalized.endsWith(".html") ||
            normalized.endsWith(".txt") ||
            normalized.endsWith(".json") ||
            normalized.endsWith(".css") ||
            normalized.endsWith(".js") ||
            normalized.endsWith(".svg") ||
            normalized.endsWith(".webmanifest")
    }

    private static func clientAcceptsBrotli(ctx: Ctx): Bool {
        let acceptEncoding = (ctx.header("Accept-Encoding") ?? "").trimAscii().toAsciiLower()
        if (acceptEncoding.size == 0) {
            return false
        }

        let parts = acceptEncoding.split(",")
        for (part in parts) {
            let token = part.trimAscii()
            if (token == "br" || token == "*") {
                return true
            }
            if ((token.startsWith("br;") || token.startsWith("*;")) && !isZeroQualityEncodingToken(token)) {
                return true
            }
        }
        return false
    }

    private static func isZeroQualityEncodingToken(token: String): Bool {
        let params = token.trimAscii().replace(" ", "").split(";")
        for (param in params) {
            if (!param.startsWith("q=")) {
                continue
            }
            let value = param[2..param.size]
            return value == "0" || value == "0.0" || value == "0.00" || value == "0.000" || value == "0.0000"
        }
        return false
    }

    private static func applyVariantHeaders(
        ctx: Ctx,
        isBrotli: Bool,
        varyAcceptEncoding: Bool,
        fileSize: Int64,
        includeContentLength: Bool
    ): Unit {
        if (varyAcceptEncoding) {
            ctx.setHeader("Vary", "Accept-Encoding")
        }
        if (isBrotli) {
            ctx.setHeader("Content-Encoding", "br")
        }
        if (includeContentLength) {
            ctx.setHeader("Content-Length", "${fileSize}")
        }
    }

    /**
     * 判断是否为可长期 immutable 缓存资源。
     * 仅对带内容哈希的 chunks 启用，避免把可变的 build 清单缓存过久。
     */
    private static func isImmutableFrontendAsset(filePath: String): Bool {
        return filePath.contains("/_next/static/chunks/")
    }

    /**
     * 判断是否应每次访问都重验证。
     * 典型场景：HTML/TXT 页面与 Next build 清单。
     */
    private static func shouldRevalidateEveryRequest(filePath: String): Bool {
        if (filePath.endsWith(".html") || filePath.endsWith(".txt")) {
            return true
        }
        if (filePath.contains("/_next/static/build/")) {
            return true
        }
        return false
    }

    private static func applyCacheHeadersByPolicy(ctx: Ctx, filePath: String, etag: String): Unit {
        if (isImmutableFrontendAsset(filePath)) {
            CacheUtils.setStaticCacheHeaders(ctx, etag)
            return
        }
        if (shouldRevalidateEveryRequest(filePath)) {
            CacheUtils.setRevalidateCacheHeaders(ctx, etag)
            return
        }
        CacheUtils.setDynamicCacheHeaders(ctx, etag)
    }

    private static func sendNotModifiedByPolicy(ctx: Ctx, filePath: String, etag: String): Unit {
        if (isImmutableFrontendAsset(filePath)) {
            CacheUtils.sendNotModified(ctx, etag)
            return
        }
        if (shouldRevalidateEveryRequest(filePath)) {
            CacheUtils.sendNotModifiedRevalidate(ctx, etag)
            return
        }
        CacheUtils.sendNotModifiedDynamic(ctx, etag)
    }

    /**
     * HEAD 请求：统一的路径服务函数
     * 根据请求路径检查文件是否存在，返回头部信息但不返回内容
     * @param baseDir 前端静态文件的基础目录，默认为 "frontend/out"
     */
    public static func servePathHead(ctx: Ctx, baseDir!: String = "frontend/out") {
        try {
            // 获取并清理路径
            let (path, cleanPath, relativePath) = resolveRequestPath(ctx)
            println("HEAD Request path: ${path}, Clean path: ${cleanPath}, Relative path: ${relativePath}, Base dir: ${baseDir}")

            // 处理根路径
            if (relativePath.isEmpty()) {
                println("Root path HEAD request, checking index.html")
                return serveFileHead(ctx, "${baseDir}/index.html")
            }

            // 构建基础路径
            let basePath = FileUtils.joinPath(baseDir, relativePath)
            println("HEAD Request initial file path: ${basePath}")

            // 尝试直接访问文件
            if (exists(basePath) && !FileInfo(basePath).isDirectory()) {
                return serveFileHead(ctx, basePath)
            }

            // 尝试React路由映射（针对.txt文件）
            if (relativePath.endsWith(".txt")) {
                let dirPath = relativePath.replace(".txt", "")
                let txtIndexPath = FileUtils.joinPath(FileUtils.joinPath(baseDir, dirPath), "index.txt")
                println("HEAD Request trying React route mapping: ${txtIndexPath}")

                if (exists(txtIndexPath)) {
                    return serveFileHead(ctx, txtIndexPath)
                }
            }

            // 尝试添加index.html
            let indexPath = FileUtils.joinPath(basePath, "index.html")
            println("HEAD Request directory or file not found, trying with index.html: ${indexPath}")

            if (exists(indexPath)) {
                return serveFileHead(ctx, indexPath)
            }

            // 所有尝试都失败，返回404
            println("HEAD Request file not found: ${indexPath}")
            FrontendController.serve404Head(ctx)

        } catch (ex: Exception) {
            ctx.status(500).sendString("Error serving file: ${ex.message}")
        }
    }

    /**
     * HEAD 请求：服务文件头部信息
     * 检查文件是否存在，设置头部信息，但不返回内容
     */
    private static func serveFileHead(ctx: Ctx, filePath: String) {
        println("HEAD Request serving file: ${filePath}")

        if (!exists(filePath)) {
            println("HEAD Request file not found: ${filePath}")
            FrontendController.serve404Head(ctx)
            return
        }

        let (resolvedPath, logicalPath, isBrotli, varyAcceptEncoding) = resolveStaticAssetVariant(ctx, filePath)
        let fileInfo = FileInfo(resolvedPath)
        let fileSize = fileInfo.size
        let lastModified = fileInfo.lastModificationTime
        let contentType = getContentType(logicalPath)

        let etag = CacheUtils.generateETag("${resolvedPath}:${fileSize}:${lastModified}:${if (isBrotli) { "br" } else { "identity" }}")

        if (CacheUtils.checkIfNoneMatch(ctx, etag)) {
            applyVariantHeaders(ctx, isBrotli, varyAcceptEncoding, fileSize, false)
            sendNotModifiedByPolicy(ctx, logicalPath, etag)
            return
        }

        applyCacheHeadersByPolicy(ctx, logicalPath, etag)
        applyVariantHeaders(ctx, isBrotli, varyAcceptEncoding, fileSize, true)
        ctx.setHeader("Content-Type", contentType)
        ctx.status(200)
    }

    /**
     * HEAD 请求：服务404头部信息
     * 返回404状态码和头部信息，但不返回错误页面内容
     * @param baseDir 前端静态文件的基础目录，默认为 "frontend/out"
     */
    public static func serve404Head(ctx: Ctx, baseDir!: String = "frontend/out") {
        try {
            // 尝试使用自定义404页面
            let custom404Path = "${baseDir}/404/index.html"
            if (exists(custom404Path)) {
                CacheUtils.setNoCacheHeaders(ctx)
                ctx.setHeader("Content-Type", "text/html; charset=utf-8")
                ctx.status(404)
                // HEAD 请求不返回内容，只返回状态码和头部
                return
            }

            // 如果自定义404不存在，返回默认错误头部
            CacheUtils.setNoCacheHeaders(ctx)
            ctx.setHeader("Content-Type", "text/plain; charset=utf-8")
            ctx.status(404)
            // HEAD 请求不返回内容
        } catch (ex: Exception) {
            CacheUtils.setNoCacheHeaders(ctx)
            ctx.setHeader("Content-Type", "text/plain; charset=utf-8")
            ctx.status(500)
            // HEAD 请求不返回内容
        }
    }
}
