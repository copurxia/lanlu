package lanlu.contexts.user.interfaces.http

import ignite.*
import stdx.net.http.HttpStatusCode
import stdx.encoding.json.stream.*
import totp_cj.*
import lanlu.contexts.user.application.*
import lanlu.contexts.user.infrastructure.persistence.*
import lanlu.shared.utils.*
import lanlu.shared.views.*
import lanlu.shared.config.*

class TotpNameReq <: JsonDeserializable<TotpNameReq> {
    var name: String = ""

    public static func fromJson(r: JsonReader): TotpNameReq {
        let out = TotpNameReq()
        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            match (name) {
                case "name" => out.name = r.readValue<String>().trimAscii()
                case _ => r.skip()
            }
        }
        r.endObject()
        return out
    }
}

class TotpConfirmReq <: JsonDeserializable<TotpConfirmReq> {
    var challengeId: String = ""
    var code: String = ""
    var name: String = ""

    public static func fromJson(r: JsonReader): TotpConfirmReq {
        let out = TotpConfirmReq()
        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            match (name) {
                case "challengeId" => out.challengeId = r.readValue<String>().trimAscii()
                case "code" => out.code = r.readValue<String>().trimAscii()
                case "name" => out.name = r.readValue<String>().trimAscii()
                case _ => r.skip()
            }
        }
        r.endObject()
        return out
    }
}

class TotpCodeReq <: JsonDeserializable<TotpCodeReq> {
    var code: String = ""
    var recoveryCode: String = ""

    public static func fromJson(r: JsonReader): TotpCodeReq {
        let out = TotpCodeReq()
        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            match (name) {
                case "code" => out.code = r.readValue<String>().trimAscii()
                case "recoveryCode" => out.recoveryCode = r.readValue<String>().trimAscii()
                case _ => r.skip()
            }
        }
        r.endObject()
        return out
    }
}

class TotpLoginVerifyReq <: JsonDeserializable<TotpLoginVerifyReq> {
    var challengeId: String = ""
    var code: String = ""
    var recoveryCode: String = ""

    public static func fromJson(r: JsonReader): TotpLoginVerifyReq {
        let out = TotpLoginVerifyReq()
        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            match (name) {
                case "challengeId" => out.challengeId = r.readValue<String>().trimAscii()
                case "code" => out.code = r.readValue<String>().trimAscii()
                case "recoveryCode" => out.recoveryCode = r.readValue<String>().trimAscii()
                case _ => r.skip()
            }
        }
        r.endObject()
        return out
    }
}

class TotpEnrollStartDataView <: JsonSerializable {
    let challengeId: String
    let secret: String
    let manualEntryKey: String
    let otpauthUri: String
    let issuer: String
    let accountName: String

    public init(challengeId: String, secret: String, manualEntryKey: String, otpauthUri: String, issuer: String, accountName: String) {
        this.challengeId = challengeId
        this.secret = secret
        this.manualEntryKey = manualEntryKey
        this.otpauthUri = otpauthUri
        this.issuer = issuer
        this.accountName = accountName
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("challengeId").writeValue(challengeId)
        w.writeName("secret").writeValue(secret)
        w.writeName("manualEntryKey").writeValue(manualEntryKey)
        w.writeName("otpauthUri").writeValue(otpauthUri)
        w.writeName("issuer").writeValue(issuer)
        w.writeName("accountName").writeValue(accountName)
        w.endObject()
    }
}

class TotpRecoveryCodesDataView <: JsonSerializable {
    let recoveryCodes: Array<String>

    public init(recoveryCodes: Array<String>) {
        this.recoveryCodes = recoveryCodes
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("recoveryCodes").writeValue<Array<String>>(recoveryCodes)
        w.endObject()
    }
}

class TotpStatusDataView <: JsonSerializable {
    let enabled: Bool
    let credentialName: Option<String>
    let createdAt: Option<String>
    let recoveryCodesRemaining: Int64

    public init(enabled: Bool, credentialName: Option<String>, createdAt: Option<String>, recoveryCodesRemaining: Int64) {
        this.enabled = enabled
        this.credentialName = credentialName
        this.createdAt = createdAt
        this.recoveryCodesRemaining = recoveryCodesRemaining
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("enabled").writeValue(enabled)
        if (let Some(name) <- credentialName) { w.writeName("credentialName").writeValue(name) }
        if (let Some(createdAt) <- createdAt) { w.writeName("createdAt").writeValue(createdAt) }
        w.writeName("recoveryCodesRemaining").writeValue(recoveryCodesRemaining)
        w.endObject()
    }
}

public class TotpController {
    private static func reply<T>(ctx: Ctx, httpStatus: UInt16, resp: ApiResponse<T>): Unit where T <: JsonSerializable {
        ctx.status(httpStatus)
        ctx.json(JsonCodec.encode<ApiResponse<T>>(resp))
    }

    public static func loginVerify(ctx: Ctx): Unit {
        let req = try { JsonCodec.decode<TotpLoginVerifyReq>(ctx.bodyString()) } catch (_: Exception) { TotpLoginVerifyReq() }
        if (req.challengeId.size == 0) {
            reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "challengeId is required", None))
            return
        }
        let state = TotpAuthService.loadLoginChallenge(req.challengeId)
        match (state) {
            case Some(challenge) =>
                let credential = UserTotpCredentialDao.findActiveByUserId(challenge.userId)
                if (credential.id <= 0) {
                    let _ = TotpAuthService.deleteLoginChallenge(req.challengeId)
                    reply<String>(ctx, HttpStatusCode.STATUS_NOT_FOUND, ApiResponse<String>(404, "totp is not enabled", None))
                    return
                }
                if (!validateAuthFactor(credential, req.code, req.recoveryCode)) {
                    reply<String>(ctx, HttpStatusCode.STATUS_UNAUTHORIZED, ApiResponse<String>(401, "invalid totp or recovery code", None))
                    return
                }
                let row = UserDao.getById(challenge.userId)
                match (UserTokenDao.createToken(challenge.userId, challenge.tokenName, "session", AuthConfig.tokenPepper)) {
                    case Some(tokenRes) =>
                        let _ = TotpAuthService.deleteLoginChallenge(req.challengeId)
                        let user = UserView(row.id, row.username, None, Some(row.avatarAssetId), None)
                        let token = TokenView(tokenRes.tokenId, challenge.tokenName, tokenRes.prefix, Some(tokenRes.token), None, None, None)
                        reply<UserTokenPairView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<UserTokenPairView>(200, "ok", Some(UserTokenPairView(user, token))))
                    case None =>
                        reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to create token", None))
                }
            case None =>
                reply<String>(ctx, UInt16(410), ApiResponse<String>(410, "login challenge expired", None))
        }
    }

    public static func enrollStart(ctx: Ctx, userId: Int64): Unit {
        if (!TotpUtils.isConfigured()) {
            reply<String>(ctx, UInt16(503), ApiResponse<String>(503, "totp requires JWT_SECRET or AUTH_TOTP_SECRET_KEY", None))
            return
        }
        let existing = UserTotpCredentialDao.findActiveByUserId(userId)
        if (existing.id > 0) {
            reply<String>(ctx, UInt16(409), ApiResponse<String>(409, "totp already enabled", None))
            return
        }
        let req = if (ctx.bodyString().trimAscii().size > 0) {
            try { JsonCodec.decode<TotpNameReq>(ctx.bodyString()) } catch (_: Exception) { TotpNameReq() }
        } else {
            TotpNameReq()
        }
        let user = UserDao.getById(userId)
        let start = TotpAuthService.startEnrollment(userId, user.username, req.name)
        match (start) {
            case Some(result) =>
                let accountName = TotpAuthService.accountName(user.username)
                let otpauthUri = buildOtpAuthUri(result.state.issuer, accountName, result.state.secret,
                    algorithm: result.state.algorithm, digits: result.state.digits, periodSeconds: result.state.periodSeconds)
                let view = TotpEnrollStartDataView(result.challengeId, result.state.secret, result.state.secret, otpauthUri, result.state.issuer, accountName)
                reply<TotpEnrollStartDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<TotpEnrollStartDataView>(200, "ok", Some(view)))
            case None =>
                reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to start totp enrollment", None))
        }
    }

    public static func enrollConfirm(ctx: Ctx, userId: Int64): Unit {
        let req = try { JsonCodec.decode<TotpConfirmReq>(ctx.bodyString()) } catch (_: Exception) { TotpConfirmReq() }
        if (req.challengeId.size == 0 || req.code.size == 0) {
            reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "challengeId and code are required", None))
            return
        }
        match (TotpAuthService.loadEnrollment(req.challengeId)) {
            case Some(state) =>
                if (state.userId != userId) {
                    reply<String>(ctx, HttpStatusCode.STATUS_FORBIDDEN, ApiResponse<String>(403, "enrollment state does not belong to current user", None))
                    return
                }
                let verifyResult = TotpAuthService.verifyEnrollmentCode(state, req.code)
                if (!verifyResult.ok) {
                    reply<String>(ctx, HttpStatusCode.STATUS_UNAUTHORIZED, ApiResponse<String>(401, verifyResult.reason, None))
                    return
                }
                let credentialName = if (req.name.trimAscii().size > 0) { req.name.trimAscii() } else { state.name }
                let encryptedSecret = try {
                    TotpUtils.encryptSecret(state.secret, userId)
                } catch (_: Exception) {
                    reply<String>(ctx, UInt16(503), ApiResponse<String>(503, "totp requires JWT_SECRET or AUTH_TOTP_SECRET_KEY", None))
                    return
                }
                let secretHash = TotpUtils.hashSecret(state.secret)
                match (UserTotpCredentialDao.createOrReplace(
                    userId,
                    credentialName,
                    encryptedSecret,
                    secretHash,
                    state.digits,
                    state.periodSeconds,
                    state.algorithm,
                    state.issuer
                )) {
                    case Some(credentialId) =>
                        let recoveryCodes = TotpAuthService.createRecoveryCodes()
                        let recoveryHashes = TotpAuthService.recoveryCodeHashes(recoveryCodes)
                        if (!UserTotpCredentialDao.replaceRecoveryCodes(credentialId, recoveryHashes)) {
                            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to persist recovery codes", None))
                            return
                        }
                        let _ = UserTotpCredentialDao.touchStep(credentialId, verifyResult.matchedStep)
                        let _ = TotpAuthService.deleteEnrollment(req.challengeId)
                        reply<TotpRecoveryCodesDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<TotpRecoveryCodesDataView>(200, "ok", Some(TotpRecoveryCodesDataView(recoveryCodes))))
                    case None =>
                        reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to enable totp", None))
                }
            case None =>
                reply<String>(ctx, UInt16(410), ApiResponse<String>(410, "enrollment state expired", None))
        }
    }

    public static func status(ctx: Ctx, userId: Int64): Unit {
        let credential = UserTotpCredentialDao.findActiveByUserId(userId)
        if (credential.id <= 0) {
            reply<TotpStatusDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<TotpStatusDataView>(200, "ok", Some(TotpStatusDataView(false, None, None, 0))))
            return
        }
        let remaining = UserTotpCredentialDao.countUnusedRecoveryCodes(credential.id)
        reply<TotpStatusDataView>(
            ctx,
            HttpStatusCode.STATUS_OK,
            ApiResponse<TotpStatusDataView>(200, "ok", Some(TotpStatusDataView(true, Some(credential.name), Some(credential.createdAt), remaining)))
        )
    }

    public static func regenerateRecoveryCodes(ctx: Ctx, userId: Int64): Unit {
        let req = try { JsonCodec.decode<TotpCodeReq>(ctx.bodyString()) } catch (_: Exception) { TotpCodeReq() }
        let credential = UserTotpCredentialDao.findActiveByUserId(userId)
        if (credential.id <= 0) {
            reply<String>(ctx, HttpStatusCode.STATUS_NOT_FOUND, ApiResponse<String>(404, "totp is not enabled", None))
            return
        }
        let validation = TotpAuthService.validateCredential(credential, req.code)
        if (!validation.ok) {
            reply<String>(ctx, HttpStatusCode.STATUS_UNAUTHORIZED, ApiResponse<String>(401, validation.reason, None))
            return
        }
        let recoveryCodes = TotpAuthService.createRecoveryCodes()
        if (!UserTotpCredentialDao.replaceRecoveryCodes(credential.id, TotpAuthService.recoveryCodeHashes(recoveryCodes))) {
            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to replace recovery codes", None))
            return
        }
        let _ = UserTotpCredentialDao.touchStep(credential.id, validation.matchedStep)
        reply<TotpRecoveryCodesDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<TotpRecoveryCodesDataView>(200, "ok", Some(TotpRecoveryCodesDataView(recoveryCodes))))
    }

    public static func disable(ctx: Ctx, userId: Int64): Unit {
        let req = try { JsonCodec.decode<TotpCodeReq>(ctx.bodyString()) } catch (_: Exception) { TotpCodeReq() }
        let credential = UserTotpCredentialDao.findActiveByUserId(userId)
        if (credential.id <= 0) {
            reply<String>(ctx, HttpStatusCode.STATUS_NOT_FOUND, ApiResponse<String>(404, "totp is not enabled", None))
            return
        }
        if (!validateAuthFactor(credential, req.code, req.recoveryCode)) {
            reply<String>(ctx, HttpStatusCode.STATUS_UNAUTHORIZED, ApiResponse<String>(401, "invalid totp or recovery code", None))
            return
        }
        if (UserTotpCredentialDao.revoke(userId)) {
            reply<String>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<String>(200, "totp disabled", None))
        } else {
            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to disable totp", None))
        }
    }

    private static func validateAuthFactor(credential: UserTotpCredentialRow, code: String, recoveryCode: String): Bool {
        if (code.trimAscii().size > 0) {
            let validation = TotpAuthService.validateCredential(credential, code)
            if (!validation.ok) {
                return false
            }
            return UserTotpCredentialDao.touchStep(credential.id, validation.matchedStep)
        }
        if (recoveryCode.trimAscii().size > 0) {
            return TotpAuthService.useRecoveryCode(credential, recoveryCode)
        }
        return false
    }
}
