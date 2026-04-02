package lanlu.infrastructure.middleware

import ignite.*
import stdx.net.http.HttpStatusCode
import std.time.DateTime
import std.convert.*
import lanlu.shared.views.*
import lanlu.shared.config.*
import lanlu.infrastructure.kv.*
import lanlu.contexts.user.infrastructure.persistence.*
import lanlu.shared.utils.*

/**
 * 认证中间件
 */
public class AuthMiddleware {
    // Throttle token last_used_at updates to reduce write load.
    private static let tokenTouchThrottleSeconds: Int64 = 300  // 5 minutes
    private static let tokenTouchThrottleNamespace = "auth_token_touch_throttle"

    /**
     * 从请求中解析 Bearer token
     * 支持三种方式（按优先级）：
     * 1. Authorization: Bearer <token>
     * 2. URL 查询参数: ?token=<token>（用于 SSE/EventSource）
     * 3. Cookie: auth_token=<token>
     */
    private static func getBearerToken(ctx: Ctx): Option<String> {
        let authHeader = ctx.header("Authorization") ?? ""
        let trimmed = authHeader.trimAscii()

        // 优先读取 Authorization: Bearer <token>
        if (trimmed.size > 0) {
            if (trimmed.startsWith("Bearer ") || trimmed.startsWith("bearer ")) {
                let bytes = trimmed.toArray()
                if (bytes.size > 7) {
                    let rest = bytes.slice(7, bytes.size - 7)
                    let token = String.fromUtf8(rest).trimAscii()
                    if (token.size > 0) { return Some(token) }
                }
            }
        }

        // 回退到 URL 查询参数 ?token=<token>（用于 EventSource）
        let queryToken = ctx.query("token") ?? ""
        if (queryToken.size > 0) {
            return Some(queryToken)
        }

        // 回退到 Cookie: auth_token=<token>
        let cookieHeader = ctx.header("Cookie") ?? ""
        let cookie = cookieHeader.trimAscii()
        if (cookie.size == 0) {
            return None
        }

        let pairs = cookie.split(";")
        for (pair in pairs) {
            let kv = pair.trimAscii()
            if (kv.size == 0) { continue }
            let eqOpt = kv.indexOf("=")
            match (eqOpt) {
                case Some(eq) =>
                    let name = kv[0..eq].trimAscii()
                    let value = kv[(eq + 1)..].trimAscii()
                    if (name == "auth_token" && value.size > 0) {
                        return Some(value)
                    }
                case None => ()
            }
        }

        return None
    }


    /**
     * 可选获取用户ID（不会返回401错误）
     * 如果用户已登录返回 Some(userId)，否则返回 None
     */
    public static func optionalUser(ctx: Ctx): Option<Int64> {
        match (getBearerToken(ctx)) {
            case Some(tokenRaw) =>
                match (getUserIdByToken(tokenRaw)) {
                    case Some(uid) => return Some(uid)
                    case None =>
                        match (AuthUtils.tryDecodeBase64ToUtf8(tokenRaw)) {
                            case Some(decoded) =>
                                match (getUserIdByToken(decoded)) {
                                    case Some(uid2) => return Some(uid2)
                                    case None => ()
                                }
                            case None => ()
                        }
                }
            case None => ()
        }
        return None
    }
    
    /**
     * 需要用户身份认证
     */
    public static func requiredAuth(ctx: Ctx): Bool {
        // Bearer token：按用户 token 校验
        match (getBearerToken(ctx)) {
            case Some(tokenRaw) =>
                if (isValidUserToken(tokenRaw)) {
                    return true
                }
                // 兼容 LANraragi 文档：Bearer base64(token)
                match (AuthUtils.tryDecodeBase64ToUtf8(tokenRaw)) {
                    case Some(decoded) =>
                        if (isValidUserToken(decoded)) {
                            return true
                        }
                    case None => ()
                }
            case None => ()
        }

        ctx.status(HttpStatusCode.STATUS_UNAUTHORIZED)
        ResponseView.errorJson(ctx, "This API is protected and requires login.", 401)
        return false
    }

    /**
     * 需要用户身份（仅用户 token 生效）
     */
    public static func requireUser(ctx: Ctx): Option<Int64> {
        match (getBearerToken(ctx)) {
            case Some(tokenRaw) =>
                match (getUserIdByToken(tokenRaw)) {
                    case Some(uid) => return Some(uid)
                    case None =>
                        match (AuthUtils.tryDecodeBase64ToUtf8(tokenRaw)) {
                            case Some(decoded) =>
                                match (getUserIdByToken(decoded)) {
                                    case Some(uid2) => return Some(uid2)
                                    case None => ()
                                }
                            case None => ()
                        }
                }
            case None => ()
        }

        ctx.status(HttpStatusCode.STATUS_UNAUTHORIZED)
        ResponseView.errorJson(ctx, "This API is protected and requires login.", 401)
        return None
    }

    /**
     * 需要管理员身份
     */
    public static func requireAdmin(ctx: Ctx): Option<Int64> {
        match (requireUser(ctx)) {
            case Some(userId) =>
                if (UserDao.isAdmin(userId)) {
                    return Some(userId)
                } else {
                    ctx.status(HttpStatusCode.STATUS_FORBIDDEN)
                    ResponseView.errorJson(ctx, "Administrator privileges required.", 403)
                    return None
                }
            case None => return None
        }
    }

    /**
     * 认证中间件（需要登录）
     */
    public static func requiredAuthMiddleware(): Handler {
        { ctx =>
            if (!requiredAuth(ctx)) {
                return
            }
            ctx.next()
        }
    }

    /**
     * 认证中间件（需要管理员）
     */
    public static func requireAdminMiddleware(): Handler {
        { ctx =>
            match (requireAdmin(ctx)) {
                case Some(_) => ctx.next()
                case None => return
            }
        }
    }

    private static func isValidUserToken(token: String): Bool {
        match (getUserIdByToken(token)) {
            case Some(_) => return true
            case None => return false
        }
    }

    private static func getUserIdByToken(token: String): Option<Int64> {
        let trimmed = token.trimAscii()
        if (trimmed.size == 0) {
            return None
        }

        let tokenHash = AuthUtils.sha256Hex("${trimmed}:${AuthConfig.tokenPepper}")
        let row = UserTokenDao.findActiveByHash(tokenHash)
        if (row.id > 0 && row.userId > 0) {
            // 轻量触达，记录 last_used（节流）
            let nowSec = DateTime.now().toUnixTimeStamp().toSeconds()
            if (shouldTouchToken(row.id, nowSec)) {
                UserTokenDao.touch(row.id)
            }
            return Some(row.userId)
        }
        return None
    }

    private static func shouldTouchToken(tokenId: Int64, nowSec: Int64): Bool {
        let cacheKey = "token:${tokenId.toString()}"
        match (PersistentCacheService.get(tokenTouchThrottleNamespace, cacheKey)) {
            case Some(lastValue) =>
                try {
                    let last = Int64.parse(lastValue)
                    if (nowSec - last < tokenTouchThrottleSeconds) {
                        return false
                    }
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }

        let _ = PersistentCacheService.set(
            tokenTouchThrottleNamespace,
            cacheKey,
            nowSec.toString(),
            tokenTouchThrottleSeconds
        )
        return true
    }
}
