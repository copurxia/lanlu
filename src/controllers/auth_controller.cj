package lrr4cj.controllers

import std.convert.*
import cjoy.*
import stdx.net.http.HttpStatusCode
import lrr4cj.config.*
import lrr4cj.dao.*
import lrr4cj.utils.*
import lrr4cj.views.*
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

    public init(id: Int64, name: String, prefix: String, token: Option<String>,
                createdAt: Option<String>, lastUsedAt: Option<String>, revokedAt: Option<String>) {
        this.id = id
        this.name = name
        this.prefix = prefix
        this.token = token
        this.createdAt = createdAt
        this.lastUsedAt = lastUsedAt
        this.revokedAt = revokedAt
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

public class AuthController {
    private static func reply<T>(ctx: JoyContext, httpStatus: UInt16, resp: ApiResponse<T>): Unit where T <: JsonSerializable {
        ctx.status(httpStatus)
        ctx.json(JsonCodec.encode<ApiResponse<T>>(resp))
    }

    public static func register(ctx: JoyContext): Unit {
        let logger = getLogger("auth_controller")
        try {
            let requestBody = ctx.readString()
            var username = ""
            var password = ""
            var tokenName = "default"

            if (requestBody.trimAscii().size > 0) {
                try {
                    let req = JsonCodec.decode<AuthCredentialsReq>(requestBody)
                    username = req.username
                    password = req.password
                    if (req.tokenName.size > 0) { tokenName = req.tokenName }
                } catch (e: Exception) {
                    logger.warn("解析 register 请求JSON失败", ("error", e.message))
                }
            }

            if (username.size == 0 || password.size == 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "username and password are required", None))
                return
            }

            let userIdOpt = UserDao.createUser(username, password, AuthConfig.tokenPepper, false)
            match (userIdOpt) {
                case Some(userId) =>
                    match (UserTokenDao.createToken(userId, tokenName, "session", AuthConfig.tokenPepper)) {
                        case Some(tokenRes) =>
                            let row = UserDao.getById(userId)
                            let avatarAssetId = if (row.id > 0) { row.avatarAssetId } else { 0 }
                            let user = UserView(userId, username.trimAscii(), None, Some(avatarAssetId), None)
                            let token = TokenView(tokenRes.tokenId, tokenName, tokenRes.prefix, Some(tokenRes.token), None, None, None)
                            reply<UserTokenPairView>(ctx, HttpStatusCode.STATUS_CREATED, ApiResponse<UserTokenPairView>(201, "created", Some(UserTokenPairView(user, token))))
                        case None =>
                            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to create token", None))
                    }
                case None =>
                    // 可能是重复用户名或参数不合法
                    let existing = UserDao.getByUsername(username)
                    if (existing.id > 0) {
                        reply<String>(ctx, UInt16(409), ApiResponse<String>(409, "username already exists", None))
                    } else {
                        reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "invalid username or password", None))
                    }
            }
        } catch (e: Exception) {
            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, e.message, None))
        }
    }

    public static func login(ctx: JoyContext): Unit {
        let logger = getLogger("auth_controller")
        try {
            let requestBody = ctx.readString()
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

            match (UserDao.verifyPassword(username, password, AuthConfig.tokenPepper)) {
                case Some(userId) =>
                    match (UserTokenDao.createToken(userId, tokenName, "session", AuthConfig.tokenPepper)) {
                        case Some(tokenRes) =>
                            let row = UserDao.getById(userId)
                            let avatarAssetId = if (row.id > 0) { row.avatarAssetId } else { 0 }
                            let user = UserView(userId, username.trimAscii(), None, Some(avatarAssetId), None)
                            let token = TokenView(tokenRes.tokenId, tokenName, tokenRes.prefix, Some(tokenRes.token), None, None, None)
                            reply<UserTokenPairView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<UserTokenPairView>(200, "ok", Some(UserTokenPairView(user, token))))
                        case None =>
                            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to create token", None))
                    }
                case None =>
                    reply<String>(ctx, HttpStatusCode.STATUS_UNAUTHORIZED, ApiResponse<String>(401, "invalid credentials", None))
            }
        } catch (e: Exception) {
            logger.error("login 处理异常", ("error", e.message))
            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, e.message, None))
        }
    }

    public static func me(ctx: JoyContext, userId: Int64): Unit {
        let row = UserDao.getById(userId)
        let username = if (row.id > 0) { row.username } else { "" }
        let isAdmin = if (row.id > 0) { row.isAdmin } else { false }
        let avatarAssetId = if (row.id > 0) { row.avatarAssetId } else { 0 }
        let user = UserView(userId, username, Some(isAdmin), Some(avatarAssetId), None)
        reply<UserDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<UserDataView>(200, "ok", Some(UserDataView(user))))
    }

    public static func listTokens(ctx: JoyContext, userId: Int64): Unit {
        // 只列出API类型的token
        let tokens = UserTokenDao.listByUserAndType(userId, Some("api"))
        var views = Array<TokenView>()
        if (tokens.size > 0) {
            views = Array<TokenView>(tokens.size, { _ => TokenView(0, "", "", None, None, None, None) })
            for (i in 0..tokens.size) {
                let t = tokens[i]
                views[i] = TokenView(t.id, t.name, t.tokenPrefix, None, Some(t.createdAt), Some(t.lastUsedAt), Some(t.revokedAt))
            }
        }
        reply<TokensDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<TokensDataView>(200, "ok", Some(TokensDataView(views))))
    }

    // 列出登录设备（session类型的token）
    public static func listSessions(ctx: JoyContext, userId: Int64): Unit {
        let tokens = UserTokenDao.listByUserAndType(userId, Some("session"))
        var views = Array<TokenView>()
        if (tokens.size > 0) {
            views = Array<TokenView>(tokens.size, { _ => TokenView(0, "", "", None, None, None, None) })
            for (i in 0..tokens.size) {
                let t = tokens[i]
                views[i] = TokenView(t.id, t.name, t.tokenPrefix, None, Some(t.createdAt), Some(t.lastUsedAt), None)
            }
        }
        reply<SessionsDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<SessionsDataView>(200, "ok", Some(SessionsDataView(views))))
    }

    public static func createToken(ctx: JoyContext, userId: Int64): Unit {
        let requestBody = ctx.readString()
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

    public static func revokeToken(ctx: JoyContext, userId: Int64): Unit {
        let idStr = ctx.getParam("id") ?? ""
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

    public static func changePassword(ctx: JoyContext, userId: Int64): Unit {
        let logger = getLogger("auth_controller")
        try {
            let requestBody = ctx.readString()
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

            // 直接修改密码，不需要验证当前密码（已通过token认证）
            if (UserDao.changePassword(userId, newPassword, AuthConfig.tokenPepper)) {
                reply<String>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<String>(200, "password changed", None))
            } else {
                reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to change password", None))
            }
        } catch (e: Exception) {
            logger.error("changePassword 处理异常", ("error", e.message))
            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, e.message, None))
        }
    }

    public static func changeUsername(ctx: JoyContext, userId: Int64): Unit {
        let logger = getLogger("auth_controller")
        try {
            let requestBody = ctx.readString()
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

    public static func listUsers(ctx: JoyContext): Unit {
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

    public static func createUser(ctx: JoyContext): Unit {
        let logger = getLogger("auth_controller")
        try {
            let requestBody = ctx.readString()
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

    public static func updateUserRole(ctx: JoyContext): Unit {
        let logger = getLogger("auth_controller")
        try {
            let idStr = ctx.getParam("id") ?? ""
            if (idStr.size == 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "user id required", None))
                return
            }
            let targetUserId = try { Int64.parse(idStr) } catch (_: Exception) { 0 }
            if (targetUserId <= 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "invalid user id", None))
                return
            }

            let requestBody = ctx.readString()
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

    public static func deleteUser(ctx: JoyContext, userId: Int64): Unit {
        let logger = getLogger("auth_controller")
        try {
            let idStr = ctx.getParam("id") ?? ""
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

    public static func resetUserPassword(ctx: JoyContext): Unit {
        let logger = getLogger("auth_controller")
        try {
            let idStr = ctx.getParam("id") ?? ""
            if (idStr.size == 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "user id required", None))
                return
            }
            let targetUserId = try { Int64.parse(idStr) } catch (_: Exception) { 0 }
            if (targetUserId <= 0) {
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "invalid user id", None))
                return
            }

            let requestBody = ctx.readString()
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

            if (UserDao.resetUserPassword(targetUserId, newPassword, AuthConfig.tokenPepper)) {
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
