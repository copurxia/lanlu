package lanlu.contexts.user.interfaces.http

import std.collection.*
import std.convert.*
import ignite.*
import stdx.net.http.HttpStatusCode
import lanlu.shared.config.*
import lanlu.contexts.user.application.*
import lanlu.contexts.user.infrastructure.persistence.*
import lanlu.shared.utils.*
import lanlu.shared.views.*
import stdx.encoding.json.stream.*

// ===== json.stream DTOs / views =====

class AuthCredentialsReq <: JsonDeserializable<AuthCredentialsReq> {
    var username: String = ""
    var password: String = ""
    var tokenName: String = ""

    public static func fromJson(r: JsonReader): AuthCredentialsReq {
        let res = AuthCredentialsReq()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "username" => res.username = r.readValue<String>().trimAscii()
                            case "password" => res.password = r.readValue<String>()
                            case "tokenName" => res.tokenName = r.readValue<String>().trimAscii()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }
        return res
    }
}

class TokenNameReq <: JsonDeserializable<TokenNameReq> {
    var name: String = ""

    public static func fromJson(r: JsonReader): TokenNameReq {
        let res = TokenNameReq()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "name" => res.name = r.readValue<String>().trimAscii()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }
        return res
    }
}

class NewPasswordReq <: JsonDeserializable<NewPasswordReq> {
    var newPassword: String = ""
    var currentPassword: String = ""

    public static func fromJson(r: JsonReader): NewPasswordReq {
        let res = NewPasswordReq()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "newPassword" => res.newPassword = r.readValue<String>()
                            case "currentPassword" => res.currentPassword = r.readValue<String>()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }
        return res
    }
}

class NewUsernameReq <: JsonDeserializable<NewUsernameReq> {
    var newUsername: String = ""

    public static func fromJson(r: JsonReader): NewUsernameReq {
        let res = NewUsernameReq()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "newUsername" => res.newUsername = r.readValue<String>().trimAscii()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }
        return res
    }
}

class CreateUserReq <: JsonDeserializable<CreateUserReq> {
    var username: String = ""
    var isAdmin: Bool = false

    public static func fromJson(r: JsonReader): CreateUserReq {
        let res = CreateUserReq()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "username" => res.username = r.readValue<String>().trimAscii()
                            case "isAdmin" =>
                                let s = r.readValue<String>().trimAscii()
                                res.isAdmin = s == "true" || s == "1"
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }
        return res
    }
}

class StepUpPasswordReq <: JsonDeserializable<StepUpPasswordReq> {
    var password: String = ""

    public static func fromJson(r: JsonReader): StepUpPasswordReq {
        let res = StepUpPasswordReq()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "password" => res.password = r.readValue<String>()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }
        return res
    }
}

class StepUpMethodsDataView <: JsonSerializable {
    let methods: Array<String>

    public init(methods: Array<String>) {
        this.methods = methods
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("methods").writeValue<Array<String>>(methods)
        w.endObject()
    }
}

class UserView <: JsonSerializable {
    let id: Int64
    let username: String
    let isAdmin: Option<Bool>
    let avatarAssetId: Option<Int64>
    let createdAt: Option<String>

    public init(id: Int64, username: String, isAdmin: Option<Bool>, avatarAssetId: Option<Int64>, createdAt: Option<String>) {
        this.id = id
        this.username = username
        this.isAdmin = isAdmin
        this.avatarAssetId = avatarAssetId
        this.createdAt = createdAt
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("id").writeValue(id)
        w.writeName("username").writeValue(username)
        if (let Some(v) <- isAdmin) { w.writeName("isAdmin").writeValue(v) }
        if (let Some(v) <- avatarAssetId) { w.writeName("avatarAssetId").writeValue(v) }
        if (let Some(v) <- createdAt) { w.writeName("createdAt").writeValue(v) }
        w.endObject()
    }
}

class TokenView <: JsonSerializable {
    let id: Int64
    let name: String
    let prefix: String
    let token: Option<String>
    let createdAt: Option<String>
    let lastUsedAt: Option<String>
    let revokedAt: Option<String>
    let current: Option<Bool>
    let lastUsedIp: Option<String>
    let userAgent: Option<String>
    let expiresAt: Option<String>

    public init(id: Int64, name: String, prefix: String, token: Option<String>,
                createdAt: Option<String>, lastUsedAt: Option<String>, revokedAt: Option<String>,
                current!: Option<Bool> = None, lastUsedIp!: Option<String> = None,
                userAgent!: Option<String> = None, expiresAt!: Option<String> = None) {
        this.id = id
        this.name = name
        this.prefix = prefix
        this.token = token
        this.createdAt = createdAt
        this.lastUsedAt = lastUsedAt
        this.revokedAt = revokedAt
        this.current = current
        this.lastUsedIp = lastUsedIp
        this.userAgent = userAgent
        this.expiresAt = expiresAt
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("id").writeValue(id)
        w.writeName("name").writeValue(name)
        w.writeName("prefix").writeValue(prefix)
        if (let Some(v) <- token) { w.writeName("token").writeValue(v) }
        if (let Some(v) <- createdAt) { w.writeName("createdAt").writeValue(v) }
        if (let Some(v) <- lastUsedAt) { w.writeName("lastUsedAt").writeValue(v) }
        if (let Some(v) <- revokedAt) { w.writeName("revokedAt").writeValue(v) }
        if (let Some(v) <- current) { w.writeName("current").writeValue(v) }
        if (let Some(v) <- lastUsedIp) { w.writeName("lastUsedIp").writeValue(v) }
        if (let Some(v) <- userAgent) { w.writeName("userAgent").writeValue(v) }
        if (let Some(v) <- expiresAt) { w.writeName("expiresAt").writeValue(v) }
        w.endObject()
    }
}

class UserTokenPairView <: JsonSerializable {
    let user: UserView
    let token: TokenView

    public init(user: UserView, token: TokenView) {
        this.user = user
        this.token = token
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("user").writeValue(user)
        w.writeName("token").writeValue(token)
        w.endObject()
    }
}

class UsersDataView <: JsonSerializable {
    let users: Array<UserView>
    public init(users: Array<UserView>) { this.users = users }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("users").writeValue<Array<UserView>>(users)
        w.endObject()
    }
}

class TokensDataView <: JsonSerializable {
    let tokens: Array<TokenView>
    public init(tokens: Array<TokenView>) { this.tokens = tokens }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("tokens").writeValue<Array<TokenView>>(tokens)
        w.endObject()
    }
}

class SessionsDataView <: JsonSerializable {
    let sessions: Array<TokenView>
    public init(sessions: Array<TokenView>) { this.sessions = sessions }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("sessions").writeValue<Array<TokenView>>(sessions)
        w.endObject()
    }
}

class TokenDataView <: JsonSerializable {
    let token: TokenView
    public init(token: TokenView) { this.token = token }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("token").writeValue(token)
        w.endObject()
    }
}

class UserDataView <: JsonSerializable {
    let user: UserView
    public init(user: UserView) { this.user = user }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("user").writeValue(user)
        w.endObject()
    }
}

class UserAndPasswordView <: JsonSerializable {
    let user: UserView
    let generatedPassword: String
    public init(user: UserView, generatedPassword: String) {
        this.user = user
        this.generatedPassword = generatedPassword
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("user").writeValue(user)
        w.writeName("generatedPassword").writeValue(generatedPassword)
        w.endObject()
    }
}

class LoginPendingTotpDataView <: JsonSerializable {
    let requiresTotp: Bool
    let challengeId: String
    let methods: Array<String>

    public init(challengeId: String) {
        this.requiresTotp = true
        this.challengeId = challengeId
        this.methods = ["totp", "recovery_code"]
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("requiresTotp").writeValue(requiresTotp)
        w.writeName("challengeId").writeValue(challengeId)
        w.writeName("methods").writeValue<Array<String>>(methods)
        w.endObject()
    }
}

public class AuthController {
    private static func reply<T>(ctx: Ctx, httpStatus: UInt16, resp: ApiResponse<T>): Unit where T <: JsonSerializable {
        ctx.status(httpStatus)
        ctx.json(JsonCodec.encode<ApiResponse<T>>(resp))
    }

    private static func verifyStepUpPassword(ctx: Ctx, userId: Int64, currentPassword: String): Bool {
        if (currentPassword.trimAscii().size == 0) {
            AuthSecurityHttpUtils.setAuthFailureReason(ctx, "reauth_missing")
            reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "currentPassword is required", None))
            return false
        }

        if (!UserDao.verifyPasswordByUserId(userId, currentPassword, AuthConfig.tokenPepper)) {
            AuthSecurityHttpUtils.setAuthFailureReason(ctx, "reauth_failed")
            reply<String>(ctx, HttpStatusCode.STATUS_UNAUTHORIZED, ApiResponse<String>(401, "current password is invalid", None))
            return false
        }
        return true
    }

    public static func login(ctx: Ctx): Unit {
        let logger = getLogger("auth_controller")
        try {
            let requestBody = ctx.bodyString()
            var username = ""
            var password = ""
            var tokenName = "login"

            if (requestBody.trimAscii().size > 0) {
                try {
                    let req = JsonCodec.decode<AuthCredentialsReq>(requestBody)
                    username = req.username
                    password = req.password
                    if (req.tokenName.size > 0) { tokenName = req.tokenName }
                } catch (e: Exception) {
                    logger.warn("解析 login 请求JSON失败", ("error", e.message))
                }
            }

            if (username.size == 0 || password.size == 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "username and password are required", None))
                return
            }

            let loginIdentifier = "${username.trimAscii().toAsciiLower()}"
            if (!AuthSecurityHttpUtils.checkRateLimit(ctx, "auth_login", loginIdentifier, "too many login attempts")) {
                return
            }

            match (UserDao.verifyPassword(username, password, AuthConfig.tokenPepper)) {
                case Some(userId) =>
                    AuthSecurityService.clearFailures("auth_login", ctx.ip, loginIdentifier)
                    let row = UserDao.getById(userId)
                    let activeTotp = UserTotpCredentialDao.findActiveByUserId(userId)
                    if (activeTotp.id > 0) {
                        match (TotpAuthService.createLoginChallenge(userId, row.username, tokenName)) {
                            case Some(challenge) =>
                                reply<LoginPendingTotpDataView>(
                                    ctx,
                                    UInt16(202),
                                    ApiResponse<LoginPendingTotpDataView>(202, "totp required", Some(LoginPendingTotpDataView(challenge.challengeId)))
                                )
                            case None =>
                                reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to create login challenge", None))
                        }
                    } else {
                        match (UserTokenDao.createToken(userId, tokenName, "session", AuthConfig.tokenPepper)) {
                            case Some(tokenRes) =>
                                AuthHttpUtils.setSessionCookie(ctx, tokenRes.token)
                                let avatarAssetId = if (row.id > 0) { row.avatarAssetId } else { 0 }
                                let user = UserView(userId, username.trimAscii(), None, Some(avatarAssetId), None)
                                let token = TokenView(tokenRes.tokenId, tokenName, tokenRes.prefix, Some(tokenRes.token), None, None, None)
                                reply<UserTokenPairView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<UserTokenPairView>(200, "ok", Some(UserTokenPairView(user, token))))
                            case None =>
                                reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to create token", None))
                        }
                    }
                case None =>
                    AuthSecurityService.recordFailure("auth_login", ctx.ip, loginIdentifier)
                    AuthSecurityHttpUtils.setAuthFailureReason(ctx, "invalid_credentials")
                    reply<String>(ctx, HttpStatusCode.STATUS_UNAUTHORIZED, ApiResponse<String>(401, "invalid credentials", None))
            }
        } catch (e: Exception) {
            logger.error("login 处理异常", ("error", e.message))
            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, e.message, None))
        }
    }

    public static func me(ctx: Ctx, userId: Int64): Unit {
        let row = UserDao.getById(userId)
        let username = if (row.id > 0) { row.username } else { "" }
        let isAdmin = if (row.id > 0) { row.isAdmin } else { false }
        let avatarAssetId = if (row.id > 0) { row.avatarAssetId } else { 0 }
        let user = UserView(userId, username, Some(isAdmin), Some(avatarAssetId), None)
        reply<UserDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<UserDataView>(200, "ok", Some(UserDataView(user))))
    }

    public static func stepUpOptions(ctx: Ctx, userId: Int64): Unit {
        let methods = ArrayList<String>()
        methods.add("password")
        let totpCredential = UserTotpCredentialDao.findActiveByUserId(userId)
        if (totpCredential.id > 0) {
            methods.add("totp")
        }
        let passkeys = UserWebauthnCredentialDao.listActiveByUser(userId)
        if (passkeys.size > 0) {
            methods.add("passkey")
        }
        reply<StepUpMethodsDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<StepUpMethodsDataView>(200, "ok", Some(StepUpMethodsDataView(methods.toArray()))))
    }

    public static func stepUpVerifyPassword(ctx: Ctx, userId: Int64): Unit {
        let req = try { JsonCodec.decode<StepUpPasswordReq>(ctx.bodyString()) } catch (_: Exception) { StepUpPasswordReq() }
        if (!verifyStepUpPassword(ctx, userId, req.password)) {
            return
        }
        let tokenId = AuthSecurityHttpUtils.currentTokenId(ctx)
        if (tokenId <= 0) {
            AuthSecurityHttpUtils.setAuthFailureReason(ctx, "reauth_failed")
            reply<String>(ctx, HttpStatusCode.STATUS_UNAUTHORIZED, ApiResponse<String>(401, "current session is invalid", None))
            return
        }
        if (!AuthSecurityService.grantStepUp(userId, tokenId, "password")) {
            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to grant step up", None))
            return
        }
        reply<String>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<String>(200, "step up verified", None))
    }

    public static func listTokens(ctx: Ctx, userId: Int64): Unit {
        // 只列出API类型的token
        let tokens = UserTokenDao.listByUserAndType(userId, Some("api"))
        var views = Array<TokenView>()
        if (tokens.size > 0) {
            views = Array<TokenView>(tokens.size, { _ => TokenView(0, "", "", None, None, None, None) })
            for (i in 0..tokens.size) {
                let t = tokens[i]
                views[i] = TokenView(
                    t.id,
                    t.name,
                    t.tokenPrefix,
                    None,
                    Some(t.createdAt),
                    Some(t.lastUsedAt),
                    Some(t.revokedAt),
                    lastUsedIp: Some(t.lastUsedIp),
                    userAgent: Some(t.userAgent),
                    expiresAt: Some(t.expiresAt)
                )
            }
        }
        reply<TokensDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<TokensDataView>(200, "ok", Some(TokensDataView(views))))
    }

    // 列出登录设备（session类型的token）
    public static func listSessions(ctx: Ctx, userId: Int64): Unit {
        let tokens = UserTokenDao.listByUserAndType(userId, Some("session"))
        let currentSessionId = AuthSecurityHttpUtils.currentTokenId(ctx)
        var views = Array<TokenView>()
        if (tokens.size > 0) {
            views = Array<TokenView>(tokens.size, { _ => TokenView(0, "", "", None, None, None, None) })
            for (i in 0..tokens.size) {
                let t = tokens[i]
                views[i] = TokenView(
                    t.id,
                    t.name,
                    t.tokenPrefix,
                    None,
                    Some(t.createdAt),
                    Some(t.lastUsedAt),
                    None,
                    current: Some(t.id == currentSessionId),
                    lastUsedIp: Some(t.lastUsedIp),
                    userAgent: Some(t.userAgent),
                    expiresAt: Some(t.expiresAt)
                )
            }
        }
        reply<SessionsDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<SessionsDataView>(200, "ok", Some(SessionsDataView(views))))
    }

    public static func createToken(ctx: Ctx, userId: Int64): Unit {
        let requestBody = ctx.bodyString()
        var tokenName = "token"
        if (requestBody.trimAscii().size > 0) {
            try {
                let req = JsonCodec.decode<TokenNameReq>(requestBody)
                if (req.name.size > 0) { tokenName = req.name }
            } catch (_: Exception) {
                ()
            }
        }

        // 手动创建的token类型为api
        match (UserTokenDao.createToken(userId, tokenName, "api", AuthConfig.tokenPepper)) {
            case Some(tokenRes) =>
                let token = TokenView(tokenRes.tokenId, tokenName, tokenRes.prefix, Some(tokenRes.token), None, None, None)
                reply<TokenDataView>(ctx, HttpStatusCode.STATUS_CREATED, ApiResponse<TokenDataView>(201, "created", Some(TokenDataView(token))))
            case None =>
                reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to create token", None))
        }
    }

    public static func revokeToken(ctx: Ctx, userId: Int64): Unit {
        let idStr = ctx.paramsOpt("id") ?? ""
        if (idStr.size == 0) {
            reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "token id required", None))
            return
        }
        let tokenId = try { Int64.parse(idStr) } catch (_: Exception) { 0 }
        if (tokenId <= 0) {
            reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "invalid token id", None))
            return
        }

        if (UserTokenDao.revoke(userId, tokenId)) {
            reply<String>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<String>(200, "revoked", None))
        } else {
            reply<String>(ctx, HttpStatusCode.STATUS_NOT_FOUND, ApiResponse<String>(404, "token not found", None))
        }
    }

    public static func changePassword(ctx: Ctx, userId: Int64): Unit {
        let logger = getLogger("auth_controller")
        try {
            let requestBody = ctx.bodyString()
            var newPassword = ""

            if (requestBody.trimAscii().size > 0) {
                try {
                    let req = JsonCodec.decode<NewPasswordReq>(requestBody)
                    newPassword = req.newPassword
                } catch (e: Exception) {
                    logger.warn("解析 changePassword 请求JSON失败", ("error", e.message))
                }
            }

            if (newPassword.size == 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "newPassword is required", None))
                return
            }

            if (newPassword.size < 6 || newPassword.size > 256) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "password must be 6-256 characters", None))
                return
            }

            // 检查用户是否存在
            let user = UserDao.getById(userId)
            if (user.id <= 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_NOT_FOUND, ApiResponse<String>(404, "user not found", None))
                return
            }

            if (!AuthSecurityHttpUtils.requireRecentStepUp(ctx, userId)) {
                return
            }

            if (UserDao.changePassword(userId, newPassword, AuthConfig.tokenPepper)) {
                let _ = UserTokenDao.revokeAllByUserAndType(userId, "session")
                AuthHttpUtils.clearSessionCookie(ctx)
                reply<String>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<String>(200, "password changed", None))
            } else {
                reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to change password", None))
            }
        } catch (e: Exception) {
            logger.error("changePassword 处理异常", ("error", e.message))
            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, e.message, None))
        }
    }

    public static func logout(ctx: Ctx): Unit {
        let tokenIdStr = ctx.getLocal("auth_token_id") ?? ""
        if (tokenIdStr.size > 0) {
            let tokenId = try { Int64.parse(tokenIdStr) } catch (_: Exception) { 0 }
            if (tokenId > 0) {
                let _ = UserTokenDao.revokeById(tokenId)
            }
        }
        AuthHttpUtils.clearSessionCookie(ctx)
        reply<String>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<String>(200, "logged out", None))
    }

    public static func revokeSession(ctx: Ctx, userId: Int64): Unit {
        let idStr = ctx.paramsOpt("id") ?? ""
        if (idStr.size == 0) {
            reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "session id required", None))
            return
        }
        let sessionId = try { Int64.parse(idStr) } catch (_: Exception) { 0 }
        if (sessionId <= 0) {
            reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "invalid session id", None))
            return
        }

        if (UserTokenDao.revokeByUserAndType(userId, sessionId, "session")) {
            if (sessionId == AuthSecurityHttpUtils.currentTokenId(ctx)) {
                AuthHttpUtils.clearSessionCookie(ctx)
            }
            reply<String>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<String>(200, "session revoked", None))
        } else {
            reply<String>(ctx, HttpStatusCode.STATUS_NOT_FOUND, ApiResponse<String>(404, "session not found", None))
        }
    }

    public static func revokeOtherSessions(ctx: Ctx, userId: Int64): Unit {
        let currentSessionId = AuthSecurityHttpUtils.currentTokenId(ctx)
        if (currentSessionId <= 0) {
            AuthSecurityHttpUtils.replyUnauthorized(ctx, "current session is invalid", failureReason: "reauth_failed")
            return
        }

        if (UserTokenDao.revokeAllByUserAndTypeExcept(userId, "session", currentSessionId)) {
            reply<String>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<String>(200, "other sessions revoked", None))
        } else {
            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to revoke other sessions", None))
        }
    }

    public static func changeUsername(ctx: Ctx, userId: Int64): Unit {
        let logger = getLogger("auth_controller")
        try {
            let requestBody = ctx.bodyString()
            var newUsername = ""

            if (requestBody.trimAscii().size > 0) {
                try {
                    let req = JsonCodec.decode<NewUsernameReq>(requestBody)
                    newUsername = req.newUsername
                } catch (e: Exception) {
                    logger.warn("解析 changeUsername 请求JSON失败", ("error", e.message))
                }
            }

            if (newUsername.size == 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "newUsername is required", None))
                return
            }

            if (newUsername.size < 3 || newUsername.size > 64) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "username must be 3-64 characters", None))
                return
            }

            // 检查用户是否存在
            let user = UserDao.getById(userId)
            if (user.id <= 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_NOT_FOUND, ApiResponse<String>(404, "user not found", None))
                return
            }

            if (UserDao.changeUsername(userId, newUsername)) {
                let userView = UserView(userId, newUsername.trimAscii(), None, None, None)
                reply<UserDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<UserDataView>(200, "username changed", Some(UserDataView(userView))))
            } else {
                // 可能是用户名已被使用
                let existing = UserDao.getByUsername(newUsername)
                if (existing.id > 0 && existing.id != userId) {
                    reply<String>(ctx, HttpStatusCode.STATUS_CONFLICT, ApiResponse<String>(409, "username already exists", None))
                } else {
                    reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "invalid username", None))
                }
            }
        } catch (e: Exception) {
            logger.error("changeUsername 处理异常", ("error", e.message))
            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, e.message, None))
        }
    }

    // ===== 用户管理相关接口（仅管理员可访问）=====

    public static func listUsers(ctx: Ctx): Unit {
        let users = UserDao.listAllUsers()
        var views = Array<UserView>()
        if (users.size > 0) {
            views = Array<UserView>(users.size, { _ => UserView(0, "", None, None, None) })
            for (i in 0..users.size) {
                let u = users[i]
                views[i] = UserView(u.id, u.username, Some(u.isAdmin), None, Some(u.createdAt))
            }
        }
        reply<UsersDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<UsersDataView>(200, "ok", Some(UsersDataView(views))))
    }

    public static func createUser(ctx: Ctx): Unit {
        let logger = getLogger("auth_controller")
        try {
            let requestBody = ctx.bodyString()
            var username = ""
            var isAdmin = false

            if (requestBody.trimAscii().size > 0) {
                try {
                    let req = JsonCodec.decode<CreateUserReq>(requestBody)
                    username = req.username
                    isAdmin = req.isAdmin
                } catch (e: Exception) {
                    logger.warn("解析 createUser 请求JSON失败", ("error", e.message))
                }
            }

            if (username.size == 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "username is required", None))
                return
            }

            // 生成随机密码
            let generatedPassword = AuthUtils.generateTokenHex(bytesLen: 8) // 16位随机密码

            match (UserDao.createUser(username, generatedPassword, AuthConfig.tokenPepper, isAdmin)) {
                case Some(newUserId) =>
                    let userRow = UserDao.getById(newUserId)
                    let userView = UserView(userRow.id, userRow.username, Some(userRow.isAdmin), None, Some(userRow.createdAt))
                    reply<UserAndPasswordView>(ctx, HttpStatusCode.STATUS_CREATED, ApiResponse<UserAndPasswordView>(201, "created", Some(UserAndPasswordView(userView, generatedPassword))))
                case None =>
                    // 可能是重复用户名
                    let existing = UserDao.getByUsername(username)
                    if (existing.id > 0) {
                        reply<String>(ctx, UInt16(409), ApiResponse<String>(409, "username already exists", None))
                    } else {
                        reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "invalid username", None))
                    }
            }
        } catch (e: Exception) {
            logger.error("createUser 处理异常", ("error", e.message))
            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, e.message, None))
        }
    }

    public static func updateUserRole(ctx: Ctx): Unit {
        let logger = getLogger("auth_controller")
        try {
            let idStr = ctx.paramsOpt("id") ?? ""
            if (idStr.size == 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "user id required", None))
                return
            }
            let targetUserId = try { Int64.parse(idStr) } catch (_: Exception) { 0 }
            if (targetUserId <= 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "invalid user id", None))
                return
            }

            let requestBody = ctx.bodyString()
            var isAdmin = false

            if (requestBody.trimAscii().size > 0) {
                try {
                    let req = JsonCodec.decode<CreateUserReq>(requestBody)
                    // Reuse CreateUserReq for isAdmin parsing, ignore username.
                    isAdmin = req.isAdmin
                } catch (e: Exception) {
                    logger.warn("解析 updateUserRole 请求JSON失败", ("error", e.message))
                }
            }

            if (UserDao.updateUserRole(targetUserId, isAdmin)) {
                reply<String>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<String>(200, "user role updated", None))
            } else {
                reply<String>(ctx, HttpStatusCode.STATUS_NOT_FOUND, ApiResponse<String>(404, "user not found", None))
            }
        } catch (e: Exception) {
            logger.error("updateUserRole 处理异常", ("error", e.message))
            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, e.message, None))
        }
    }

    public static func deleteUser(ctx: Ctx, userId: Int64): Unit {
        let logger = getLogger("auth_controller")
        try {
            let idStr = ctx.paramsOpt("id") ?? ""
            if (idStr.size == 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "user id required", None))
                return
            }
            let targetUserId = try { Int64.parse(idStr) } catch (_: Exception) { 0 }
            if (targetUserId <= 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "invalid user id", None))
                return
            }

            // 不允许删除自己
            if (targetUserId == userId) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "cannot delete your own account", None))
                return
            }

            if (UserDao.deleteUser(targetUserId)) {
                reply<String>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<String>(200, "user deleted", None))
            } else {
                reply<String>(ctx, HttpStatusCode.STATUS_NOT_FOUND, ApiResponse<String>(404, "user not found", None))
            }
        } catch (e: Exception) {
            logger.error("deleteUser 处理异常", ("error", e.message))
            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, e.message, None))
        }
    }

    public static func resetUserPassword(ctx: Ctx): Unit {
        let logger = getLogger("auth_controller")
        try {
            let idStr = ctx.paramsOpt("id") ?? ""
            if (idStr.size == 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "user id required", None))
                return
            }
            let targetUserId = try { Int64.parse(idStr) } catch (_: Exception) { 0 }
            if (targetUserId <= 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "invalid user id", None))
                return
            }

            let requestBody = ctx.bodyString()
            var newPassword = ""

            if (requestBody.trimAscii().size > 0) {
                try {
                    let req = JsonCodec.decode<NewPasswordReq>(requestBody)
                    newPassword = req.newPassword
                } catch (e: Exception) {
                    logger.warn("解析 resetUserPassword 请求JSON失败", ("error", e.message))
                }
            }

            if (newPassword.size == 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "newPassword is required", None))
                return
            }

            if (newPassword.size < 6 || newPassword.size > 256) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "password must be 6-256 characters", None))
                return
            }

            let adminUserId = try { Int64.parse(ctx.getLocal("actor") ?? "0") } catch (_: Exception) { 0 }
            if (adminUserId <= 0) {
                AuthSecurityHttpUtils.setAuthFailureReason(ctx, "reauth_missing")
                reply<String>(ctx, HttpStatusCode.STATUS_UNAUTHORIZED, ApiResponse<String>(401, "administrator session is invalid", None))
                return
            }

            if (!AuthSecurityHttpUtils.requireRecentStepUp(ctx, adminUserId)) {
                return
            }

            if (UserDao.resetUserPassword(targetUserId, newPassword, AuthConfig.tokenPepper)) {
                let _ = UserTokenDao.revokeAllByUserAndType(targetUserId, "session")
                reply<String>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<String>(200, "password reset", None))
            } else {
                reply<String>(ctx, HttpStatusCode.STATUS_NOT_FOUND, ApiResponse<String>(404, "user not found", None))
            }
        } catch (e: Exception) {
            logger.error("resetUserPassword 处理异常", ("error", e.message))
            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, e.message, None))
        }
    }
}
