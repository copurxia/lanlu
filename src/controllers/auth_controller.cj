package lrr4cj.controllers

import stdx.encoding.json.*
import std.convert.*
import cjoy.*
import stdx.net.http.HttpStatusCode
import lrr4cj.config.*
import lrr4cj.dao.*
import lrr4cj.middleware.*
import lrr4cj.utils.*

public class AuthController {
    private static func jsonValueToString(value: JsonValue): String {
        match (value) {
            case s: JsonString => return s.getValue()
            case _ => return value.toString()
        }
    }

    private static func getJsonString(obj: JsonObject, key: String): String {
        let fields = obj.getFields()
        if (!fields.contains(key)) {
            return ""
        }
        return jsonValueToString(fields[key]).trimAscii()
    }

    private static func escapeJsonString(str: String): String {
        var escaped = str
        escaped = escaped.replace("\\", "\\\\")
        escaped = escaped.replace("\"", "\\\"")
        escaped = escaped.replace("\b", "\\b")
        escaped = escaped.replace("\f", "\\f")
        escaped = escaped.replace("\n", "\\n")
        escaped = escaped.replace("\r", "\\r")
        escaped = escaped.replace("\t", "\\t")
        return escaped
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
                    let bodyJson = JsonValue.fromStr(requestBody)
                    match (bodyJson) {
                        case obj: JsonObject =>
                            username = getJsonString(obj, "username")
                            password = getJsonString(obj, "password")
                            let tn = getJsonString(obj, "tokenName")
                            if (tn.size > 0) {
                                tokenName = tn
                            }
                        case _ => ()
                    }
                } catch (e: Exception) {
                    logger.warn("解析 register 请求JSON失败", ("error", e.message))
                }
            }

            if (username.size == 0 || password.size == 0) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json("{\"code\":400,\"message\":\"username and password are required\",\"data\":null}")
                return
            }

            let userIdOpt = UserDao.createUser(username, password, AuthConfig.tokenPepper)
            match (userIdOpt) {
                case Some(userId) =>
                    match (UserTokenDao.createToken(userId, tokenName, "session", AuthConfig.tokenPepper)) {
                        case Some(tokenRes) =>
                            ctx.status(HttpStatusCode.STATUS_CREATED)
                            ctx.json("{\"code\":201,\"message\":\"created\",\"data\":{\"user\":{\"id\":${userId},\"username\":\"${escapeJsonString(username.trimAscii())}\"},\"token\":{\"id\":${tokenRes.tokenId},\"name\":\"${escapeJsonString(tokenName)}\",\"prefix\":\"${escapeJsonString(tokenRes.prefix)}\",\"token\":\"${escapeJsonString(tokenRes.token)}\"}}}")
                        case None =>
                            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                            ctx.json("{\"code\":500,\"message\":\"failed to create token\",\"data\":null}")
                    }
                case None =>
                    // 可能是重复用户名或参数不合法
                    let existing = UserDao.getByUsername(username)
                    if (existing.id > 0) {
                        ctx.status(409)
                        ctx.json("{\"code\":409,\"message\":\"username already exists\",\"data\":null}")
                    } else {
                        ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                        ctx.json("{\"code\":400,\"message\":\"invalid username or password\",\"data\":null}")
                    }
            }
        } catch (e: Exception) {
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ctx.json("{\"code\":500,\"message\":\"${escapeJsonString(e.message)}\",\"data\":null}")
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
                    let bodyJson = JsonValue.fromStr(requestBody)
                    match (bodyJson) {
                        case obj: JsonObject =>
                            username = getJsonString(obj, "username")
                            password = getJsonString(obj, "password")
                            let tn = getJsonString(obj, "tokenName")
                            if (tn.size > 0) {
                                tokenName = tn
                            }
                        case _ => ()
                    }
                } catch (e: Exception) {
                    logger.warn("解析 login 请求JSON失败", ("error", e.message))
                }
            }

            if (username.size == 0 || password.size == 0) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json("{\"code\":400,\"message\":\"username and password are required\",\"data\":null}")
                return
            }

            match (UserDao.verifyPassword(username, password, AuthConfig.tokenPepper)) {
                case Some(userId) =>
                    match (UserTokenDao.createToken(userId, tokenName, "session", AuthConfig.tokenPepper)) {
                        case Some(tokenRes) =>
                            ctx.status(HttpStatusCode.STATUS_OK)
                            ctx.json("{\"code\":200,\"message\":\"ok\",\"data\":{\"user\":{\"id\":${userId},\"username\":\"${escapeJsonString(username.trimAscii())}\"},\"token\":{\"id\":${tokenRes.tokenId},\"name\":\"${escapeJsonString(tokenName)}\",\"prefix\":\"${escapeJsonString(tokenRes.prefix)}\",\"token\":\"${escapeJsonString(tokenRes.token)}\"}}}")
                        case None =>
                            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                            ctx.json("{\"code\":500,\"message\":\"failed to create token\",\"data\":null}")
                    }
                case None =>
                    ctx.status(HttpStatusCode.STATUS_UNAUTHORIZED)
                    ctx.json("{\"code\":401,\"message\":\"invalid credentials\",\"data\":null}")
            }
        } catch (e: Exception) {
            logger.error("login 处理异常", ("error", e.message))
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ctx.json("{\"code\":500,\"message\":\"${escapeJsonString(e.message)}\",\"data\":null}")
        }
    }

    public static func me(ctx: JoyContext, userId: Int64): Unit {
        let row = UserDao.getById(userId)
        let username = if (row.id > 0) { row.username } else { "" }
        ctx.status(HttpStatusCode.STATUS_OK)
        ctx.json("{\"code\":200,\"message\":\"ok\",\"data\":{\"user\":{\"id\":${userId},\"username\":\"${escapeJsonString(username)}\"}}}")
    }

    public static func listTokens(ctx: JoyContext, userId: Int64): Unit {
        // 只列出API类型的token
        let tokens = UserTokenDao.listByUserAndType(userId, Some("api"))
        var json = "["
        for (i in 0..tokens.size) {
            if (i > 0) { json += "," }
            let t = tokens[i]
            json += "{"
            json += "\"id\":${t.id},"
            json += "\"name\":\"${escapeJsonString(t.name)}\","
            json += "\"prefix\":\"${escapeJsonString(t.tokenPrefix)}\","
            json += "\"createdAt\":\"${escapeJsonString(t.createdAt)}\","
            json += "\"lastUsedAt\":\"${escapeJsonString(t.lastUsedAt)}\","
            json += "\"revokedAt\":\"${escapeJsonString(t.revokedAt)}\""
            json += "}"
        }
        json += "]"
        ctx.status(HttpStatusCode.STATUS_OK)
        ctx.json("{\"code\":200,\"message\":\"ok\",\"data\":{\"tokens\":${json}}}")
    }

    // 列出登录设备（session类型的token）
    public static func listSessions(ctx: JoyContext, userId: Int64): Unit {
        let tokens = UserTokenDao.listByUserAndType(userId, Some("session"))
        var json = "["
        for (i in 0..tokens.size) {
            if (i > 0) { json += "," }
            let t = tokens[i]
            json += "{"
            json += "\"id\":${t.id},"
            json += "\"name\":\"${escapeJsonString(t.name)}\","
            json += "\"prefix\":\"${escapeJsonString(t.tokenPrefix)}\","
            json += "\"createdAt\":\"${escapeJsonString(t.createdAt)}\","
            json += "\"lastUsedAt\":\"${escapeJsonString(t.lastUsedAt)}\""
            json += "}"
        }
        json += "]"
        ctx.status(HttpStatusCode.STATUS_OK)
        ctx.json("{\"code\":200,\"message\":\"ok\",\"data\":{\"sessions\":${json}}}")
    }

    public static func createToken(ctx: JoyContext, userId: Int64): Unit {
        let requestBody = ctx.readString()
        var tokenName = "token"
        if (requestBody.trimAscii().size > 0) {
            try {
                let bodyJson = JsonValue.fromStr(requestBody)
                match (bodyJson) {
                    case obj: JsonObject =>
                        let tn = getJsonString(obj, "name")
                        if (tn.size > 0) {
                            tokenName = tn
                        }
                    case _ => ()
                }
            } catch (_: Exception) {
                ()
            }
        }

        // 手动创建的token类型为api
        match (UserTokenDao.createToken(userId, tokenName, "api", AuthConfig.tokenPepper)) {
            case Some(tokenRes) =>
                ctx.status(HttpStatusCode.STATUS_CREATED)
                ctx.json("{\"code\":201,\"message\":\"created\",\"data\":{\"token\":{\"id\":${tokenRes.tokenId},\"name\":\"${escapeJsonString(tokenName)}\",\"prefix\":\"${escapeJsonString(tokenRes.prefix)}\",\"token\":\"${escapeJsonString(tokenRes.token)}\"}}}")
            case None =>
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ctx.json("{\"code\":500,\"message\":\"failed to create token\",\"data\":null}")
        }
    }

    public static func revokeToken(ctx: JoyContext, userId: Int64): Unit {
        let idStr = ctx.getParam("id") ?? ""
        if (idStr.size == 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json("{\"code\":400,\"message\":\"token id required\",\"data\":null}")
            return
        }
        let tokenId = try { Int64.parse(idStr) } catch (_: Exception) { 0 }
        if (tokenId <= 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json("{\"code\":400,\"message\":\"invalid token id\",\"data\":null}")
            return
        }

        if (UserTokenDao.revoke(userId, tokenId)) {
            ctx.status(HttpStatusCode.STATUS_OK)
            ctx.json("{\"code\":200,\"message\":\"revoked\",\"data\":null}")
        } else {
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ctx.json("{\"code\":404,\"message\":\"token not found\",\"data\":null}")
        }
    }

    public static func changePassword(ctx: JoyContext, userId: Int64): Unit {
        let logger = getLogger("auth_controller")
        try {
            let requestBody = ctx.readString()
            var oldPassword = ""
            var newPassword = ""

            if (requestBody.trimAscii().size > 0) {
                try {
                    let bodyJson = JsonValue.fromStr(requestBody)
                    match (bodyJson) {
                        case obj: JsonObject =>
                            oldPassword = getJsonString(obj, "oldPassword")
                            newPassword = getJsonString(obj, "newPassword")
                        case _ => ()
                    }
                } catch (e: Exception) {
                    logger.warn("解析 changePassword 请求JSON失败", ("error", e.message))
                }
            }

            if (oldPassword.size == 0 || newPassword.size == 0) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json("{\"code\":400,\"message\":\"oldPassword and newPassword are required\",\"data\":null}")
                return
            }

            if (newPassword.size < 6 || newPassword.size > 256) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json("{\"code\":400,\"message\":\"password must be 6-256 characters\",\"data\":null}")
                return
            }

            // 验证旧密码
            let user = UserDao.getById(userId)
            if (user.id <= 0) {
                ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                ctx.json("{\"code\":404,\"message\":\"user not found\",\"data\":null}")
                return
            }

            match (UserDao.verifyPassword(user.username, oldPassword, AuthConfig.tokenPepper)) {
                case Some(_) =>
                    if (UserDao.changePassword(userId, newPassword, AuthConfig.tokenPepper)) {
                        ctx.status(HttpStatusCode.STATUS_OK)
                        ctx.json("{\"code\":200,\"message\":\"password changed\",\"data\":null}")
                    } else {
                        ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                        ctx.json("{\"code\":500,\"message\":\"failed to change password\",\"data\":null}")
                    }
                case None =>
                    ctx.status(HttpStatusCode.STATUS_UNAUTHORIZED)
                    ctx.json("{\"code\":401,\"message\":\"invalid old password\",\"data\":null}")
            }
        } catch (e: Exception) {
            logger.error("changePassword 处理异常", ("error", e.message))
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ctx.json("{\"code\":500,\"message\":\"${escapeJsonString(e.message)}\",\"data\":null}")
        }
    }
}
