package lanlu.shared.utils

import ignite.*
import stdx.net.http.HttpStatusCode
import stdx.crypto.digest.*
import stdx.encoding.hex.*

/**
 * HTTP 缓存工具类
 */
public class CacheUtils {

    /**
     * 生成 ETag（基于内容哈希）
     * 返回带双引号的 ETag 值，如 "abc123def456"
     */
    public static func generateETag(content: String): String {
        var sha1Instance = SHA1()
        sha1Instance.write(content.toArray())
        let hash: Array<Byte> = sha1Instance.finish()
        let hexStr = toHexString(hash)
        // 取前16个字符作为 ETag
        let shortHash = String.fromUtf8(hexStr.toArray().slice(0, 16))
        return "\"${shortHash}\""
    }

    /**
     * 检查 If-None-Match 条件
     * 返回 true 表示资源未修改，应返回 304
     */
    public static func checkIfNoneMatch(ctx: Ctx, etag: String): Bool {
        let ifNoneMatch = ctx.header("If-None-Match") ?? ""
        if (ifNoneMatch.size > 0) {
            let trimmed = ifNoneMatch.trimAscii()
            // 直接比较 ETag 值
            if (trimmed == etag || trimmed == "*") {
                return true
            }
            // 支持多个 ETag 值（逗号分隔）
            if (trimmed.contains(",")) {
                let parts = trimmed.split(",")
                for (part in parts) {
                    let partTrimmed = part.trimAscii()
                    if (partTrimmed == etag) {
                        return true
                    }
                }
            }
        }
        return false
    }

    /**
     * 设置静态资源缓存头（用于缩略图等不变的资源）
     * 缓存时间：1年
     */
    public static func setStaticCacheHeaders(ctx: Ctx, etag: String): Unit {
        ctx.setHeader("Cache-Control", "public, max-age=31536000, immutable")
        ctx.setHeader("ETag", etag)
    }

    /**
     * 设置动态资源缓存头（用于页面图片等可能变化的资源）
     * 缓存时间：24小时
     */
    public static func setDynamicCacheHeaders(ctx: Ctx, etag: String): Unit {
        ctx.setHeader("Cache-Control", "public, max-age=86400")
        ctx.setHeader("ETag", etag)
    }

    /**
     * 设置每次访问都需重验证的缓存头（用于 HTML、构建清单等）
     */
    public static func setRevalidateCacheHeaders(ctx: Ctx, etag: String): Unit {
        ctx.setHeader("Cache-Control", "public, no-cache, must-revalidate")
        ctx.setHeader("ETag", etag)
    }

    /**
     * 设置不缓存头（用于占位符等临时资源）
     */
    public static func setNoCacheHeaders(ctx: Ctx): Unit {
        ctx.setHeader("Cache-Control", "no-cache, no-store, must-revalidate")
        ctx.setHeader("Pragma", "no-cache")
        ctx.setHeader("Expires", "0")
    }

    /**
     * 发送 304 Not Modified 响应
     */
    public static func sendNotModified(ctx: Ctx, etag: String): Unit {
        ctx.setHeader("ETag", etag)
        ctx.setHeader("Cache-Control", "public, max-age=31536000, immutable")
        ctx.status(HttpStatusCode.STATUS_NOT_MODIFIED)
    }

    /**
     * 发送 304 Not Modified 响应（用于动态资源）
     */
    public static func sendNotModifiedDynamic(ctx: Ctx, etag: String): Unit {
        ctx.setHeader("ETag", etag)
        ctx.setHeader("Cache-Control", "public, max-age=86400")
        ctx.status(HttpStatusCode.STATUS_NOT_MODIFIED)
    }

    /**
     * 发送 304 Not Modified 响应（用于每次重验证资源）
     */
    public static func sendNotModifiedRevalidate(ctx: Ctx, etag: String): Unit {
        ctx.setHeader("ETag", etag)
        ctx.setHeader("Cache-Control", "public, no-cache, must-revalidate")
        ctx.status(HttpStatusCode.STATUS_NOT_MODIFIED)
    }
}
