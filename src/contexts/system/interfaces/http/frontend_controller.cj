package lanlu.contexts.system.interfaces.http

import ignite.*
import std.fs.*
import lanlu.shared.utils.*

/**
 * 前端控制器
 * 处理前端静态文件服务
 */
public class FrontendController {

    /**
     * 统一的路径服务函数
     * 根据请求路径自动判断是文件还是目录，目录时自动添加index.html
     * @param baseDir 前端静态文件的基础目录，默认为 "frontend/out"
     */
    public static func servePath(ctx: Ctx, baseDir!: String = "frontend/out") {
        try {
            // 获取并清理路径
            let path = ctx.paramsOpt("*") ?? ""
            let cleanPath = if (path.contains("?")) { path.split("?")[0] } else { path }
            var relativePath = cleanPath
            while (relativePath.startsWith("/")) { relativePath = relativePath[1..relativePath.size] }
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

        let fileInfo = FileInfo(filePath)
        let fileSize = fileInfo.size
        let lastModified = fileInfo.lastModificationTime

        let bytes = File.readFrom(Path(filePath))
        let contentType = getContentType(filePath)

        let etag = CacheUtils.generateETag("${filePath}:${fileSize}:${lastModified}")

        if (CacheUtils.checkIfNoneMatch(ctx, etag)) {
            sendNotModifiedByPolicy(ctx, filePath, etag)
            return
        }

        applyCacheHeadersByPolicy(ctx, filePath, etag)
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

        // 简单的文件扩展名检查
        if (filePath.endsWith(".html")) {
            return "text/html; charset=utf-8"
        } else if (filePath.endsWith(".txt")) {
            return "text/plain; charset=utf-8"
        } else if (filePath.endsWith(".css")) {
            return "text/css; charset=utf-8"
        } else if (filePath.endsWith(".js")) {
            return "application/javascript; charset=utf-8"
        } else if (filePath.endsWith(".json")) {
            return "application/json; charset=utf-8"
        } else if (filePath.endsWith(".png")) {
            return "image/png"
        } else if (filePath.endsWith(".jpg") || filePath.endsWith(".jpeg")) {
            return "image/jpeg"
        } else if (filePath.endsWith(".gif")) {
            return "image/gif"
        } else if (filePath.endsWith(".svg")) {
            return "image/svg+xml"
        } else if (filePath.endsWith(".ico")) {
            return "image/x-icon"
        } else if (filePath.endsWith(".woff")) {
            return "font/woff"
        } else if (filePath.endsWith(".woff2")) {
            return "font/woff2"
        } else if (filePath.endsWith(".ttf")) {
            return "font/ttf"
        } else if (filePath.endsWith(".eot")) {
            return "application/vnd.ms-fontobject"
        } else {
            return defaultType
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
            let path = ctx.paramsOpt("*") ?? ""
            let cleanPath = if (path.contains("?")) { path.split("?")[0] } else { path }
            var relativePath = cleanPath
            while (relativePath.startsWith("/")) { relativePath = relativePath[1..relativePath.size] }
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

        let fileInfo = FileInfo(filePath)
        let fileSize = fileInfo.size
        let lastModified = fileInfo.lastModificationTime
        let contentType = getContentType(filePath)

        let etag = CacheUtils.generateETag("${filePath}:${fileSize}:${lastModified}")

        if (CacheUtils.checkIfNoneMatch(ctx, etag)) {
            sendNotModifiedByPolicy(ctx, filePath, etag)
            return
        }

        applyCacheHeadersByPolicy(ctx, filePath, etag)
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
