package lanlu.middleware

import cjoy.*
import stdx.net.http.HttpStatusCode
import std.time.DateTime
import std.collection.*
import std.sync.*
import lanlu.views.*
import lanlu.config.*
import lanlu.dao.*
import lanlu.utils.*

/**
 * 认证中间件
 */
public class AuthMiddleware {
    // Throttle token last_used_at updates to reduce write load.
    private static let tokenTouchThrottleSeconds: Int64 = 300  // 5 minutes
    private static var tokenTouchCache: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    private static let tokenTouchMutex: Mutex = Mutex()

    /**
     * 从请求中解析 Bearer token
     */
    private static func getBearerToken(ctx: JoyContext): Option<String> {
        let authHeader = ctx.getHeader("Authorization") ?? ""
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
        let cookieHeader = ctx.getHeader("Cookie") ?? ""
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
    public static func optionalUser(ctx: JoyContext): Option<Int64> {
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
    public static func requiredAuth(ctx: JoyContext): Bool {
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
    public static func requireUser(ctx: JoyContext): Option<Int64> {
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
    public static func requireAdmin(ctx: JoyContext): Option<Int64> {
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
            var shouldTouch = false
            tokenTouchMutex.lock()
            match (tokenTouchCache.get(row.id)) {
                case Some(last) =>
                    if (nowSec - last >= tokenTouchThrottleSeconds) {
                        tokenTouchCache[row.id] = nowSec
                        shouldTouch = true
                    }
                case None =>
                    tokenTouchCache[row.id] = nowSec
                    shouldTouch = true
            }
            tokenTouchMutex.unlock()
            if (shouldTouch) {
                UserTokenDao.touch(row.id)
            }
            return Some(row.userId)
        }
        return None
    }
}
