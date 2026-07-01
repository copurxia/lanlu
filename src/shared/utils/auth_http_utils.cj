package lanlu.shared.utils

import ace_web.*

public class AuthHttpUtils {
    private static let sessionCookieName = "auth_token"
    private static let sessionCookieMaxAgeSeconds = 30 * 24 * 60 * 60

    public static func setSessionCookie(ctx: Context, token: String): Unit {
        let secure = isSecureRequest(ctx)
        let secureAttr = if (secure) { "; Secure" } else { "" }
        ctx.setHeader(
            "Set-Cookie",
            "${sessionCookieName}=${token}; Path=/; Max-Age=${sessionCookieMaxAgeSeconds}; HttpOnly; SameSite=Lax${secureAttr}"
        )
    }

    public static func clearSessionCookie(ctx: Context): Unit {
        let secure = isSecureRequest(ctx)
        let secureAttr = if (secure) { "; Secure" } else { "" }
        ctx.setHeader(
            "Set-Cookie",
            "${sessionCookieName}=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax${secureAttr}"
        )
    }

    private static func isSecureRequest(ctx: Context): Bool {
        let forwardedProto = (ctx.header("x-forwarded-proto") ?? "").trimAscii().toAsciiLower()
        if (forwardedProto == "https") {
            return true
        }
        let forwardedSsl = (ctx.header("x-forwarded-ssl") ?? "").trimAscii().toAsciiLower()
        if (forwardedSsl == "on") {
            return true
        }
        return false
    }
}
