package lanlu.infrastructure.middleware

import ace_web.*
import lanlu.shared.http_ext.*
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
     * 支持两种方式（按优先级）：
     * 1. Authorization: Bearer <token>
     * 2. Cookie: auth_token=<token>
     */
    private static func getBearerToken(ctx: Context): Option<String> {
        let authHeader = ctx.header("authorization") ?? ""
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

        // 回退到 Cookie: auth_token=<token>
        let cookieHeader = ctx.header("cookie") ?? ""
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
    public static func optionalUser(ctx: Context): Option<Int64> {
        // 若上游中间件（requiredAuth/requireUser）已完成鉴权并绑定 actor，直接复用，避免重复查库
        match (getLocalStr(ctx, "actor")) {
            case Some(actorStr) =>
                match (parseUserId(actorStr)) {
                    case Some(userId) => return Some(userId)
                    case None => ()
                }
            case None => ()
        }
        match (getBearerToken(ctx)) {
            case Some(tokenRaw) =>
                match (getTokenRowByToken(ctx, tokenRaw)) {
                    case Some(row) =>
                        bindTokenContext(ctx, row)
                        return Some(row.userId)
                    case None =>
                        match (AuthUtils.tryDecodeBase64ToUtf8(tokenRaw)) {
                            case Some(decoded) =>
                                match (getTokenRowByToken(ctx, decoded)) {
                                    case Some(row2) =>
                                        bindTokenContext(ctx, row2)
                                        return Some(row2.userId)
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
     * 将 actor 本地变量解析为 userId，失败返回 None
     */
    private static func parseUserId(actorStr: String): Option<Int64> {
        try {
            return Some(Int64.parse(actorStr))
        } catch (_: Exception) {
            return None
        }
    }
    
    /**
     * 需要用户身份认证
     */
    public static func requiredAuth(ctx: Context): Bool {
        // Bearer token：按用户 token 校验
        match (getBearerToken(ctx)) {
            case Some(tokenRaw) =>
                match (getTokenRowByToken(ctx, tokenRaw)) {
                    case Some(row) =>
                        bindTokenContext(ctx, row)
                        return true
                    case None => ()
                }
                // 兼容 LANraragi 文档：Bearer base64(token)
                match (AuthUtils.tryDecodeBase64ToUtf8(tokenRaw)) {
                    case Some(decoded) =>
                        match (getTokenRowByToken(ctx, decoded)) {
                            case Some(row2) =>
                                bindTokenContext(ctx, row2)
                                return true
                            case None => ()
                        }
                    case None => ()
                }
            case None => ()
        }

        ctx.setHeader("X-Auth-Session-Invalid", "1")
        ctx.status = HttpStatusCode.STATUS_UNAUTHORIZED
        ResponseView.errorJson(ctx, "This API is protected and requires login.", 401)
        return false
    }

    /**
     * 需要用户身份（仅用户 token 生效）
     */
    public static func requireUser(ctx: Context): Option<Int64> {
        // 若上游中间件（requiredAuth/requireUser）已完成鉴权并绑定 actor，直接复用，避免重复查库
        match (getLocalStr(ctx, "actor")) {
            case Some(actorStr) =>
                match (parseUserId(actorStr)) {
                    case Some(userId) => return Some(userId)
                    case None => ()
                }
            case None => ()
        }
        match (getBearerToken(ctx)) {
            case Some(tokenRaw) =>
                match (getTokenRowByToken(ctx, tokenRaw)) {
                    case Some(row) =>
                        bindTokenContext(ctx, row)
                        return Some(row.userId)
                    case None =>
                        match (AuthUtils.tryDecodeBase64ToUtf8(tokenRaw)) {
                            case Some(decoded) =>
                                match (getTokenRowByToken(ctx, decoded)) {
                                    case Some(row2) =>
                                        bindTokenContext(ctx, row2)
                                        return Some(row2.userId)
                                    case None => ()
                                }
                            case None => ()
                        }
                }
            case None => ()
        }

        ctx.setHeader("X-Auth-Session-Invalid", "1")
        ctx.status = HttpStatusCode.STATUS_UNAUTHORIZED
        ResponseView.errorJson(ctx, "This API is protected and requires login.", 401)
        return None
    }

    /**
     * 需要管理员身份
     */
    public static func requireAdmin(ctx: Context): Option<Int64> {
        match (requireUser(ctx)) {
            case Some(userId) =>
                if (UserDao.isAdmin(userId)) {
                    return Some(userId)
                } else {
                    ctx.status = HttpStatusCode.STATUS_FORBIDDEN
                    ResponseView.errorJson(ctx, "Administrator privileges required.", 403)
                    return None
                }
            case None => return None
        }
    }

    /**
     * 认证中间件（需要登录）
     */
    public static func requiredAuthMiddleware(): Middleware {
        { ctx: Context, next: Next =>
            if (!requiredAuth(ctx)) {
                return
            }
            next()
        }
    }

    /**
     * 认证中间件（需要管理员）
     */
    public static func requireAdminMiddleware(): Middleware {
        { ctx: Context, next: Next =>
            match (requireAdmin(ctx)) {
                case Some(_) => next()
                case None => return
            }
        }
    }

    private static func getTokenRowByToken(ctx: Context, token: String): Option<UserTokenRow> {
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
                let userAgent = ctx.header("user-agent") ?? ""
                UserTokenDao.touchUsage(row.id, "", userAgent)
            }
            return Some(row)
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

    private static func bindActor(ctx: Context, userId: Int64): Unit {
        setLocalStr(ctx, "actor", userId.toString())
    }

    private static func bindTokenContext(ctx: Context, row: UserTokenRow): Unit {
        bindActor(ctx, row.userId)
        setLocalStr(ctx, "auth_token_id", row.id.toString())
        setLocalStr(ctx, "auth_token_type", row.tokenType)
    }
}
