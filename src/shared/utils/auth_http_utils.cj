package lanlu.shared.utils

import ignite.*

public class AuthHttpUtils {
    private static let sessionCookieName = "auth_token"
    private static let sessionCookieMaxAgeSeconds = 30 * 24 * 60 * 60

    public static func setSessionCookie(ctx: Ctx, token: String): Unit {
        let secure = isSecureRequest(ctx)
        let secureAttr = if (secure) { "; Secure" } else { "" }
        ctx.setHeader(
            "Set-Cookie",
            "${sessionCookieName}=${token}; Path=/; Max-Age=${sessionCookieMaxAgeSeconds}; HttpOnly; SameSite=Lax${secureAttr}"
        )
    }

    public static func clearSessionCookie(ctx: Ctx): Unit {
        let secure = isSecureRequest(ctx)
        let secureAttr = if (secure) { "; Secure" } else { "" }
        ctx.setHeader(
            "Set-Cookie",
            "${sessionCookieName}=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax${secureAttr}"
        )
    }

    private static func isSecureRequest(ctx: Ctx): Bool {
        let forwardedProto = (ctx.header("X-Forwarded-Proto") ?? "").trimAscii().toAsciiLower()
        if (forwardedProto == "https") {
            return true
        }
        let forwardedSsl = (ctx.header("X-Forwarded-Ssl") ?? "").trimAscii().toAsciiLower()
        if (forwardedSsl == "on") {
            return true
        }
        return false
    }
}
