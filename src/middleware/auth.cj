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
     * 可选认证中间件
     */
    public static func optionalAuth(ctx: JoyContext) {
        // 可选认证，不做任何处理
    }
    
    /**
     * 任何有效凭据即可（用户token 或 API_KEY）
     */
    public static func requiredAuth(ctx: JoyContext): Bool {
        // 1) Bearer token：优先按用户 token 校验
        match (getBearerToken(ctx)) {
            case Some(tokenRaw) =>
                if (isValidUserToken(tokenRaw)) {
                    return true
                }
                // 2) 兼容 LANraragi 文档：Bearer base64(api_key)
                match (AuthUtils.tryDecodeBase64ToUtf8(tokenRaw)) {
                    case Some(decoded) =>
                        if (isValidUserToken(decoded)) {
                            return true
                        }
                        if (isValidApiKey(decoded)) {
                            return true
                        }
                    case None => ()
                }
                // 3) 回退：检查 API_KEY
                if (isValidApiKey(tokenRaw)) {
                    return true
                }
            case None => ()
        }

        ctx.status(HttpStatusCode.STATUS_UNAUTHORIZED)
        ResponseView.errorJson(ctx, "This API is protected and requires login or an API Key.", 401)
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

    private static func isValidApiKey(token: String): Bool {
        let expected = AuthConfig.apiKey.trimAscii()
        if (expected.size == 0) { return false }
        return token.trimAscii() == expected
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
