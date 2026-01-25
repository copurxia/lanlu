package lanlu.controllers

import cjoy.*
import std.fs.*
import lanlu.utils.*

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
    public static func servePath(ctx: JoyContext, baseDir!: String = "frontend/out") {
        try {
            // 获取并清理路径
            let path = ctx.getParam("*") ?? ""
            let cleanPath = if (path.contains("?")) { path.split("?")[0] } else { path }
            println("Request path: ${path}, Clean path: ${cleanPath}, Base dir: ${baseDir}")

            // 处理根路径
            if (cleanPath.isEmpty() || cleanPath == "/") {
                println("Root path request, using index.html")
                return serveFile(ctx, "${baseDir}/index.html")
            }

            // 构建基础路径
            let basePath = "${baseDir}/${cleanPath}"
            println("Initial file path: ${basePath}")

            // 尝试直接访问文件
            if (exists(basePath) && !FileInfo(basePath).isDirectory()) {
                return serveFile(ctx, basePath)
            }

            // 尝试React路由映射（针对.txt文件）
            if (cleanPath.endsWith(".txt")) {
                let dirPath = cleanPath.replace(".txt", "")
                let txtIndexPath = "${baseDir}/${dirPath}/index.txt"
                println("Trying React route mapping: ${txtIndexPath}")
                
                if (exists(txtIndexPath)) {
                    return serveFile(ctx, txtIndexPath)
                }
            }

            // 尝试添加index.html
            let indexPath = if (basePath.endsWith("/")) { 
                basePath + "index.html" 
            } else { 
                basePath + "/index.html" 
            }
            println("Directory or file not found, trying with index.html: ${indexPath}")

            if (exists(indexPath)) {
                return serveFile(ctx, indexPath)
            }

            // 所有尝试都失败，返回404
            println("File not found: ${indexPath}")
            FrontendController.serve404(ctx)
            
        } catch (ex: Exception) {
            ctx.status(500).string("Error serving file: ${ex.message}")
        }
    }

    /**
     * 服务文件内容
     */
    private static func serveFile(ctx: JoyContext, filePath: String) {
        println("Serving file: ${filePath}")

        if (!exists(filePath)) {
            println("File not found: ${filePath}")
            FrontendController.serve404(ctx)
            return
        }

        let fileInfo = FileInfo(filePath)
        let fileSize = fileInfo.size
        let lastModified = fileInfo.lastModificationTime

        let file = File(Path(filePath), Read)
        let buffer = Array<Byte>(1024 * 1024, {_ => 0}) // 1MB buffer
        let bytesRead = file.read(buffer)
        file.close()

        if (bytesRead > 0) {
            let contentType = getContentType(filePath)

            let etag = CacheUtils.generateETag("${filePath}:${fileSize}:${lastModified}")

            if (CacheUtils.checkIfNoneMatch(ctx, etag)) {
                ctx.status(304)
                return
            }

            // _next/static/ 下的资源使用长期缓存（带哈希，永不变化）
            if (filePath.contains("/_next/static/")) {
                CacheUtils.setStaticCacheHeaders(ctx, etag)
            } else {
                CacheUtils.setDynamicCacheHeaders(ctx, etag)
            }
            ctx.header("Content-Type", contentType)
            ctx.data(buffer.slice(0, bytesRead))
        } else {
            FrontendController.serve404(ctx)
        }
    }

    /**
     * 服务404
     * @param baseDir 前端静态文件的基础目录，默认为 "frontend/out"
     */
    public static func serve404(ctx: JoyContext, baseDir!: String = "frontend/out") {
        try {
            // 尝试使用自定义404页面
            let custom404Path = "${baseDir}/404/index.html"
            if (exists(custom404Path)) {
                let file = File(Path(custom404Path), Read)
                let buffer = Array<Byte>(1024 * 1024, {_ => 0}) // 1MB buffer
                let bytesRead = file.read(buffer)
                file.close()

                if (bytesRead > 0) {
                    ctx.header("Content-Type", "text/html; charset=utf-8")
                    ctx.status(404).data(buffer.slice(0, bytesRead))
                    return
                }
            }

            // 如果自定义404不存在，返回默认错误信息
            ctx.status(404).string("404 - Page not found")
        } catch (ex: Exception) {
            ctx.status(500).string("Error serving 404 page: ${ex.message}")
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
     * HEAD 请求：统一的路径服务函数
     * 根据请求路径检查文件是否存在，返回头部信息但不返回内容
     * @param baseDir 前端静态文件的基础目录，默认为 "frontend/out"
     */
    public static func servePathHead(ctx: JoyContext, baseDir!: String = "frontend/out") {
        try {
            // 获取并清理路径
            let path = ctx.getParam("*") ?? ""
            let cleanPath = if (path.contains("?")) { path.split("?")[0] } else { path }
            println("HEAD Request path: ${path}, Clean path: ${cleanPath}, Base dir: ${baseDir}")

            // 处理根路径
            if (cleanPath.isEmpty() || cleanPath == "/") {
                println("Root path HEAD request, checking index.html")
                return serveFileHead(ctx, "${baseDir}/index.html")
            }

            // 构建基础路径
            let basePath = "${baseDir}/${cleanPath}"
            println("HEAD Request initial file path: ${basePath}")

            // 尝试直接访问文件
            if (exists(basePath) && !FileInfo(basePath).isDirectory()) {
                return serveFileHead(ctx, basePath)
            }

            // 尝试React路由映射（针对.txt文件）
            if (cleanPath.endsWith(".txt")) {
                let dirPath = cleanPath.replace(".txt", "")
                let txtIndexPath = "${baseDir}/${dirPath}/index.txt"
                println("HEAD Request trying React route mapping: ${txtIndexPath}")

                if (exists(txtIndexPath)) {
                    return serveFileHead(ctx, txtIndexPath)
                }
            }

            // 尝试添加index.html
            let indexPath = if (basePath.endsWith("/")) {
                basePath + "index.html"
            } else {
                basePath + "/index.html"
            }
            println("HEAD Request directory or file not found, trying with index.html: ${indexPath}")

            if (exists(indexPath)) {
                return serveFileHead(ctx, indexPath)
            }

            // 所有尝试都失败，返回404
            println("HEAD Request file not found: ${indexPath}")
            FrontendController.serve404Head(ctx)

        } catch (ex: Exception) {
            ctx.status(500).string("Error serving file: ${ex.message}")
        }
    }

    /**
     * HEAD 请求：服务文件头部信息
     * 检查文件是否存在，设置头部信息，但不返回内容
     */
    private static func serveFileHead(ctx: JoyContext, filePath: String) {
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
            ctx.status(304)
            return
        }

        // _next/static/ 下的资源使用长期缓存（带哈希，永不变化）
        if (filePath.contains("/_next/static/")) {
            CacheUtils.setStaticCacheHeaders(ctx, etag)
        } else {
            CacheUtils.setDynamicCacheHeaders(ctx, etag)
        }
        ctx.header("Content-Type", contentType)
        ctx.status(200)
    }

    /**
     * HEAD 请求：服务404头部信息
     * 返回404状态码和头部信息，但不返回错误页面内容
     * @param baseDir 前端静态文件的基础目录，默认为 "frontend/out"
     */
    public static func serve404Head(ctx: JoyContext, baseDir!: String = "frontend/out") {
        try {
            // 尝试使用自定义404页面
            let custom404Path = "${baseDir}/404/index.html"
            if (exists(custom404Path)) {
                ctx.header("Content-Type", "text/html; charset=utf-8")
                ctx.status(404)
                // HEAD 请求不返回内容，只返回状态码和头部
                return
            }

            // 如果自定义404不存在，返回默认错误头部
            ctx.header("Content-Type", "text/plain; charset=utf-8")
            ctx.status(404)
            // HEAD 请求不返回内容
        } catch (ex: Exception) {
            ctx.header("Content-Type", "text/plain; charset=utf-8")
            ctx.status(500)
            // HEAD 请求不返回内容
        }
    }
}
