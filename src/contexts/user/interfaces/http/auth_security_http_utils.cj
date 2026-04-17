package lanlu.contexts.user.interfaces.http

import ignite.*
import std.convert.*
import stdx.net.http.HttpStatusCode
import stdx.encoding.json.stream.*
import lanlu.contexts.user.application.*
import lanlu.shared.views.*

public class AuthSecurityHttpUtils {
    public static func setAuthFailureReason(ctx: Ctx, reason: String): Unit {
        ctx.setLocal("auth_failure_reason", reason)
    }

    public static func setRateLimitScope(ctx: Ctx, scope: String): Unit {
        ctx.setLocal("auth_rate_limit_scope", scope)
    }

    public static func currentTokenId(ctx: Ctx): Int64 {
        return try { Int64.parse(ctx.getLocal("auth_token_id") ?? "0") } catch (_: Exception) { 0 }
    }

    public static func checkRateLimit(ctx: Ctx, scope: String, identifier: String, message: String): Bool {
        let decision = AuthSecurityService.checkRateLimit(scope, ctx.ip, identifier)
        if (decision.allowed) {
            return true
        }

        setAuthFailureReason(ctx, "rate_limited")
        setRateLimitScope(ctx, scope)
        if (decision.retryAfterSeconds > 0) {
            ctx.setHeader("Retry-After", decision.retryAfterSeconds.toString())
        }
        ctx.status(UInt16(429))
        ctx.json(JsonCodec.encode<ApiResponse<String>>(ApiResponse<String>(429, message, None)))
        return false
    }

    public static func requireRecentStepUp(ctx: Ctx, userId: Int64): Bool {
        let tokenId = currentTokenId(ctx)
        if (tokenId <= 0 || !AuthSecurityService.hasRecentStepUp(userId, tokenId)) {
            setAuthFailureReason(ctx, "step_up_required")
            ctx.setHeader("X-Auth-Step-Up-Required", "1")
            ctx.status(UInt16(428))
            ctx.json(JsonCodec.encode<ApiResponse<String>>(ApiResponse<String>(428, "step up authentication required", None)))
            return false
        }
        return true
    }

    public static func replyUnauthorized(ctx: Ctx, message: String, failureReason!: String = ""): Unit {
        if (failureReason.trimAscii().size > 0) {
            setAuthFailureReason(ctx, failureReason)
        }
        ctx.status(HttpStatusCode.STATUS_UNAUTHORIZED)
        ctx.json(JsonCodec.encode<ApiResponse<String>>(ApiResponse<String>(401, message, None)))
    }
}
