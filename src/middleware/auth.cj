package lrr4cj.middleware

import cjoy.*
import stdx.net.http.HttpStatusCode
import lrr4cj.views.*
import lrr4cj.config.*
import lrr4cj.dao.*
import lrr4cj.utils.*

/**
 * 认证中间件
 */
public class AuthMiddleware {
    /**
     * 从请求中解析 Bearer token
     */
    private static func getBearerToken(ctx: JoyContext): Option<String> {
        let authHeader = ctx.getHeader("Authorization") ?? ""
        let trimmed = authHeader.trimAscii()
        if (trimmed.size == 0) {
            // Fallback: 从查询参数中读取 token
            let tokenParam = ctx.getQuery("token") ?? ""
            let tokenTrimmed = tokenParam.trimAscii()
            if (tokenTrimmed.size > 0) {
                return Some(tokenTrimmed)
            }
            return None
        }

        // 兼容大小写与格式问题
        // 期望格式: "Bearer <token>"
        if (trimmed.startsWith("Bearer ") || trimmed.startsWith("bearer ")) {
            let bytes = trimmed.toArray()
            if (bytes.size <= 7) { return None }
            let rest = bytes.slice(7, bytes.size - 7)
            let token = String.fromUtf8(rest).trimAscii()
            if (token.size > 0) { return Some(token) }
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
        ResponseView.errorJson(ctx, "This API is protected and requires login or an API Key.", 401)
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
            // 轻量触达，记录 last_used
            UserTokenDao.touch(row.id)
            return Some(row.userId)
        }
        return None
    }
}
