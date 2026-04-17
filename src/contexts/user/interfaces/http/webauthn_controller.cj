package lanlu.contexts.user.interfaces.http

import std.collection.*
import std.convert.*
import std.io.ByteBuffer
import std.time.DateTime
import ignite.*
import lanlu.contexts.user.infrastructure.persistence.*
import lanlu.infrastructure.kv.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import lanlu.shared.views.*
import stdx.crypto.digest.*
import stdx.encoding.json.stream.*
import stdx.net.http.HttpStatusCode
import webauthn_cj.*

class WebauthnRegisterOptionsReq <: JsonDeserializable<WebauthnRegisterOptionsReq> {
    var name: String = ""

    public static func fromJson(r: JsonReader): WebauthnRegisterOptionsReq {
        let out = WebauthnRegisterOptionsReq()
        if (r.peek() != Some(BeginObject)) {
            return out
        }
        r.startObject()
        while (r.peek() != EndObject) {
            let key = r.readName()
            match (key) {
                case "name" => out.name = r.readValue<String>().trimAscii()
                case _ => r.skip()
            }
        }
        r.endObject()
        return out
    }
}

class WebauthnAuthenticateOptionsReq <: JsonDeserializable<WebauthnAuthenticateOptionsReq> {
    var username: String = ""

    public static func fromJson(r: JsonReader): WebauthnAuthenticateOptionsReq {
        let out = WebauthnAuthenticateOptionsReq()
        if (r.peek() != Some(BeginObject)) {
            return out
        }
        r.startObject()
        while (r.peek() != EndObject) {
            let key = r.readName()
            match (key) {
                case "username" => out.username = r.readValue<String>().trimAscii()
                case _ => r.skip()
            }
        }
        r.endObject()
        return out
    }
}

class WebauthnRegistrationCredentialReq <: JsonDeserializable<WebauthnRegistrationCredentialReq> {
    var id: String = ""
    var rawId: String = ""
    var clientDataJson: String = ""
    var attestationObject: String = ""
    var transports: Array<String> = Array<String>()

    public static func fromJson(r: JsonReader): WebauthnRegistrationCredentialReq {
        let out = WebauthnRegistrationCredentialReq()
        if (r.peek() != Some(BeginObject)) {
            return out
        }
        r.startObject()
        while (r.peek() != EndObject) {
            let key = r.readName()
            match (key) {
                case "id" => out.id = r.readValue<String>().trimAscii()
                case "rawId" => out.rawId = r.readValue<String>().trimAscii()
                case "clientDataJSON" => out.clientDataJson = r.readValue<String>().trimAscii()
                case "attestationObject" => out.attestationObject = r.readValue<String>().trimAscii()
                case "transports" =>
                    if (r.peek() == Some(BeginArray)) {
                        let items = ArrayList<String>()
                        r.startArray()
                        while (r.peek() != EndArray) {
                            items.add(r.readValue<String>())
                        }
                        r.endArray()
                        out.transports = items.toArray()
                    } else {
                        r.skip()
                    }
                case _ => r.skip()
            }
        }
        r.endObject()
        return out
    }
}

class WebauthnAuthenticationCredentialReq <: JsonDeserializable<WebauthnAuthenticationCredentialReq> {
    var id: String = ""
    var rawId: String = ""
    var clientDataJson: String = ""
    var authenticatorData: String = ""
    var signature: String = ""
    var userHandle: String = ""

    public static func fromJson(r: JsonReader): WebauthnAuthenticationCredentialReq {
        let out = WebauthnAuthenticationCredentialReq()
        if (r.peek() != Some(BeginObject)) {
            return out
        }
        r.startObject()
        while (r.peek() != EndObject) {
            let key = r.readName()
            match (key) {
                case "id" => out.id = r.readValue<String>().trimAscii()
                case "rawId" => out.rawId = r.readValue<String>().trimAscii()
                case "clientDataJSON" => out.clientDataJson = r.readValue<String>().trimAscii()
                case "authenticatorData" => out.authenticatorData = r.readValue<String>().trimAscii()
                case "signature" => out.signature = r.readValue<String>().trimAscii()
                case "userHandle" => out.userHandle = r.readValue<String>().trimAscii()
                case _ => r.skip()
            }
        }
        r.endObject()
        return out
    }
}

class WebauthnRegisterVerifyReq <: JsonDeserializable<WebauthnRegisterVerifyReq> {
    var challengeId: String = ""
    var name: String = ""
    var credential: WebauthnRegistrationCredentialReq = WebauthnRegistrationCredentialReq()

    public static func fromJson(r: JsonReader): WebauthnRegisterVerifyReq {
        let out = WebauthnRegisterVerifyReq()
        if (r.peek() != Some(BeginObject)) {
            return out
        }
        r.startObject()
        while (r.peek() != EndObject) {
            let key = r.readName()
            match (key) {
                case "challengeId" => out.challengeId = r.readValue<String>().trimAscii()
                case "name" => out.name = r.readValue<String>().trimAscii()
                case "credential" => out.credential = WebauthnRegistrationCredentialReq.fromJson(r)
                case _ => r.skip()
            }
        }
        r.endObject()
        return out
    }
}

class WebauthnAuthenticateVerifyReq <: JsonDeserializable<WebauthnAuthenticateVerifyReq> {
    var challengeId: String = ""
    var credential: WebauthnAuthenticationCredentialReq = WebauthnAuthenticationCredentialReq()

    public static func fromJson(r: JsonReader): WebauthnAuthenticateVerifyReq {
        let out = WebauthnAuthenticateVerifyReq()
        if (r.peek() != Some(BeginObject)) {
            return out
        }
        r.startObject()
        while (r.peek() != EndObject) {
            let key = r.readName()
            match (key) {
                case "challengeId" => out.challengeId = r.readValue<String>().trimAscii()
                case "credential" => out.credential = WebauthnAuthenticationCredentialReq.fromJson(r)
                case _ => r.skip()
            }
        }
        r.endObject()
        return out
    }
}

class StoredRegistrationState <: JsonSerializable & JsonDeserializable<StoredRegistrationState> {
    var userId: Int64 = 0
    var challenge: String = ""
    var rpId: String = ""
    var origins: Array<String> = Array<String>()
    var createdAtSeconds: Int64 = 0
    var timeoutMs: Int64 = 0
    var userHandle: String = ""
    var userName: String = ""
    var userDisplayName: String = ""
    var excludeCredentialIds: Array<String> = Array<String>()
    var credentialName: String = ""

    public static func fromJson(r: JsonReader): StoredRegistrationState {
        let out = StoredRegistrationState()
        if (r.peek() != Some(BeginObject)) {
            return out
        }
        r.startObject()
        while (r.peek() != EndObject) {
            let key = r.readName()
            match (key) {
                case "userId" => out.userId = r.readValue<Int64>()
                case "challenge" => out.challenge = r.readValue<String>()
                case "rpId" => out.rpId = r.readValue<String>()
                case "origins" => out.origins = readStringArray(r)
                case "createdAtSeconds" => out.createdAtSeconds = r.readValue<Int64>()
                case "timeoutMs" => out.timeoutMs = r.readValue<Int64>()
                case "userHandle" => out.userHandle = r.readValue<String>()
                case "userName" => out.userName = r.readValue<String>()
                case "userDisplayName" => out.userDisplayName = r.readValue<String>()
                case "excludeCredentialIds" => out.excludeCredentialIds = readStringArray(r)
                case "credentialName" => out.credentialName = r.readValue<String>()
                case _ => r.skip()
            }
        }
        r.endObject()
        return out
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("userId").writeValue(userId)
        w.writeName("challenge").writeValue(challenge)
        w.writeName("rpId").writeValue(rpId)
        w.writeName("origins")
        writeStringArray(w, origins)
        w.writeName("createdAtSeconds").writeValue(createdAtSeconds)
        w.writeName("timeoutMs").writeValue(timeoutMs)
        w.writeName("userHandle").writeValue(userHandle)
        w.writeName("userName").writeValue(userName)
        w.writeName("userDisplayName").writeValue(userDisplayName)
        w.writeName("excludeCredentialIds")
        writeStringArray(w, excludeCredentialIds)
        w.writeName("credentialName").writeValue(credentialName)
        w.endObject()
    }
}

class StoredAuthenticationState <: JsonSerializable & JsonDeserializable<StoredAuthenticationState> {
    var userId: Int64 = 0
    var challenge: String = ""
    var rpId: String = ""
    var origins: Array<String> = Array<String>()
    var createdAtSeconds: Int64 = 0
    var timeoutMs: Int64 = 0

    public static func fromJson(r: JsonReader): StoredAuthenticationState {
        let out = StoredAuthenticationState()
        if (r.peek() != Some(BeginObject)) {
            return out
        }
        r.startObject()
        while (r.peek() != EndObject) {
            let key = r.readName()
            match (key) {
                case "userId" => out.userId = r.readValue<Int64>()
                case "challenge" => out.challenge = r.readValue<String>()
                case "rpId" => out.rpId = r.readValue<String>()
                case "origins" => out.origins = readStringArray(r)
                case "createdAtSeconds" => out.createdAtSeconds = r.readValue<Int64>()
                case "timeoutMs" => out.timeoutMs = r.readValue<Int64>()
                case _ => r.skip()
            }
        }
        r.endObject()
        return out
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("userId").writeValue(userId)
        w.writeName("challenge").writeValue(challenge)
        w.writeName("rpId").writeValue(rpId)
        w.writeName("origins")
        writeStringArray(w, origins)
        w.writeName("createdAtSeconds").writeValue(createdAtSeconds)
        w.writeName("timeoutMs").writeValue(timeoutMs)
        w.endObject()
    }
}

class WebauthnCredentialDescriptorView <: JsonSerializable {
    let id: String
    let credentialType: String

    public init(id: String, credentialType!: String = "public-key") {
        this.id = id
        this.credentialType = credentialType
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("id").writeValue(id)
        w.writeName("type").writeValue(credentialType)
        w.endObject()
    }
}

class WebauthnPubKeyCredParamView <: JsonSerializable {
    let credentialType: String
    let alg: Int64

    public init(alg: Int64, credentialType!: String = "public-key") {
        this.credentialType = credentialType
        this.alg = alg
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("type").writeValue(credentialType)
        w.writeName("alg").writeValue(alg)
        w.endObject()
    }
}

class WebauthnUserView <: JsonSerializable {
    let id: String
    let name: String
    let displayName: String

    public init(id: String, name: String, displayName: String) {
        this.id = id
        this.name = name
        this.displayName = displayName
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("id").writeValue(id)
        w.writeName("name").writeValue(name)
        w.writeName("displayName").writeValue(displayName)
        w.endObject()
    }
}

class WebauthnRpView <: JsonSerializable {
    let id: String
    let name: String

    public init(id: String, name: String) {
        this.id = id
        this.name = name
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("id").writeValue(id)
        w.writeName("name").writeValue(name)
        w.endObject()
    }
}

class WebauthnAuthenticatorSelectionView <: JsonSerializable {
    let residentKey: String
    let userVerification: String

    public init(residentKey: String, userVerification: String) {
        this.residentKey = residentKey
        this.userVerification = userVerification
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("residentKey").writeValue(residentKey)
        w.writeName("userVerification").writeValue(userVerification)
        w.endObject()
    }
}

class WebauthnRegistrationPublicKeyView <: JsonSerializable {
    let challenge: String
    let rp: WebauthnRpView
    let user: WebauthnUserView
    let timeout: Int64
    let pubKeyCredParams: Array<WebauthnPubKeyCredParamView>
    let excludeCredentials: Array<WebauthnCredentialDescriptorView>
    let attestation: String
    let authenticatorSelection: WebauthnAuthenticatorSelectionView

    public init(
        challenge: String,
        rp: WebauthnRpView,
        user: WebauthnUserView,
        timeout: Int64,
        pubKeyCredParams: Array<WebauthnPubKeyCredParamView>,
        excludeCredentials: Array<WebauthnCredentialDescriptorView>,
        attestation: String,
        authenticatorSelection: WebauthnAuthenticatorSelectionView
    ) {
        this.challenge = challenge
        this.rp = rp
        this.user = user
        this.timeout = timeout
        this.pubKeyCredParams = pubKeyCredParams
        this.excludeCredentials = excludeCredentials
        this.attestation = attestation
        this.authenticatorSelection = authenticatorSelection
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("challenge").writeValue(challenge)
        w.writeName("rp").writeValue(rp)
        w.writeName("user").writeValue(user)
        w.writeName("timeout").writeValue(timeout)
        w.writeName("pubKeyCredParams").writeValue<Array<WebauthnPubKeyCredParamView>>(pubKeyCredParams)
        w.writeName("excludeCredentials").writeValue<Array<WebauthnCredentialDescriptorView>>(excludeCredentials)
        w.writeName("attestation").writeValue(attestation)
        w.writeName("authenticatorSelection").writeValue(authenticatorSelection)
        w.endObject()
    }
}

class WebauthnAuthenticationPublicKeyView <: JsonSerializable {
    let challenge: String
    let timeout: Int64
    let rpId: String
    let allowCredentials: Array<WebauthnCredentialDescriptorView>
    let userVerification: String

    public init(
        challenge: String,
        timeout: Int64,
        rpId: String,
        allowCredentials: Array<WebauthnCredentialDescriptorView>,
        userVerification: String
    ) {
        this.challenge = challenge
        this.timeout = timeout
        this.rpId = rpId
        this.allowCredentials = allowCredentials
        this.userVerification = userVerification
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("challenge").writeValue(challenge)
        w.writeName("timeout").writeValue(timeout)
        w.writeName("rpId").writeValue(rpId)
        w.writeName("allowCredentials").writeValue<Array<WebauthnCredentialDescriptorView>>(allowCredentials)
        w.writeName("userVerification").writeValue(userVerification)
        w.endObject()
    }
}

class WebauthnRegisterOptionsDataView <: JsonSerializable {
    let challengeId: String
    let publicKey: WebauthnRegistrationPublicKeyView

    public init(challengeId: String, publicKey: WebauthnRegistrationPublicKeyView) {
        this.challengeId = challengeId
        this.publicKey = publicKey
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("challengeId").writeValue(challengeId)
        w.writeName("publicKey").writeValue(publicKey)
        w.endObject()
    }
}

class WebauthnAuthenticateOptionsDataView <: JsonSerializable {
    let challengeId: String
    let publicKey: WebauthnAuthenticationPublicKeyView

    public init(challengeId: String, publicKey: WebauthnAuthenticationPublicKeyView) {
        this.challengeId = challengeId
        this.publicKey = publicKey
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("challengeId").writeValue(challengeId)
        w.writeName("publicKey").writeValue(publicKey)
        w.endObject()
    }
}

class WebauthnCredentialSummaryView <: JsonSerializable {
    let id: Int64
    let name: String
    let credentialId: String
    let algorithm: String
    let transports: Array<String>
    let userVerified: Bool
    let backupEligible: Bool
    let backupState: Bool
    let createdAt: String
    let lastUsedAt: String

    public init(row: UserWebauthnCredentialRow) {
        this.id = row.id
        this.name = row.name
        this.credentialId = row.credentialIdB64Url
        this.algorithm = row.algorithm
        this.transports = parseTransports(row.transportsJson)
        this.userVerified = row.userVerified
        this.backupEligible = row.backupEligible
        this.backupState = row.backupState
        this.createdAt = row.createdAt
        this.lastUsedAt = row.lastUsedAt
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("id").writeValue(id)
        w.writeName("name").writeValue(name)
        w.writeName("credentialId").writeValue(credentialId)
        w.writeName("algorithm").writeValue(algorithm)
        w.writeName("transports")
        writeStringArray(w, transports)
        w.writeName("userVerified").writeValue(userVerified)
        w.writeName("backupEligible").writeValue(backupEligible)
        w.writeName("backupState").writeValue(backupState)
        w.writeName("createdAt").writeValue(createdAt)
        w.writeName("lastUsedAt").writeValue(lastUsedAt)
        w.endObject()
    }
}

class WebauthnCredentialListDataView <: JsonSerializable {
    let credentials: Array<WebauthnCredentialSummaryView>

    public init(credentials: Array<WebauthnCredentialSummaryView>) {
        this.credentials = credentials
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("credentials").writeValue<Array<WebauthnCredentialSummaryView>>(credentials)
        w.endObject()
    }
}

public class WebauthnController {
    private static let registerNamespace = "webauthn:registration"
    private static let authenticationNamespace = "webauthn:authentication"
    private static let stateTtlSeconds: Int64 = 300

    private static func reply<T>(ctx: Ctx, httpStatus: UInt16, resp: ApiResponse<T>): Unit where T <: JsonSerializable {
        ctx.status(httpStatus)
        ctx.json(JsonCodec.encode<ApiResponse<T>>(resp))
    }

    public static func registerOptions(ctx: Ctx, userId: Int64): Unit {
        let requestBody = ctx.bodyString()
        let req = if (requestBody.trimAscii().size > 0) {
            try { JsonCodec.decode<WebauthnRegisterOptionsReq>(requestBody) } catch (_: Exception) { WebauthnRegisterOptionsReq() }
        } else {
            WebauthnRegisterOptionsReq()
        }
        let user = UserDao.getById(userId)
        if (user.id <= 0) {
            reply<String>(ctx, HttpStatusCode.STATUS_NOT_FOUND, ApiResponse<String>(404, "user not found", None))
            return
        }

        let existingRows = UserWebauthnCredentialDao.listActiveByUser(userId)
        let excludeCredentialIds = Array<String>(existingRows.size, { i => existingRows[i].credentialIdB64Url })
        let builderOpt = buildWebauthn(ctx)
        match (builderOpt) {
            case Some(webauthn) =>
                try {
                    let start = webauthn.startPasskeyRegistration(
                        deriveUserHandle(userId),
                        user.username,
                        user.username,
                        excludeCredentialIds: excludeCredentialIds,
                        nowSeconds: nowSeconds()
                    )
                    let challengeId = AuthUtils.generateTokenHex(bytesLen: 16)
                    let stored = StoredRegistrationState()
                    stored.userId = userId
                    stored.challenge = start.state.challenge
                    stored.rpId = start.state.rpId
                    stored.origins = start.state.origins
                    stored.createdAtSeconds = start.state.createdAtSeconds
                    stored.timeoutMs = start.state.timeoutMs
                    stored.userHandle = start.state.userHandle
                    stored.userName = start.state.userName
                    stored.userDisplayName = start.state.userDisplayName
                    stored.excludeCredentialIds = start.state.excludeCredentialIds
                    stored.credentialName = if (req.name.size > 0) { req.name } else { "Passkey" }
                    if (!PersistentCacheService.set(registerNamespace, challengeId, JsonCodec.encode<StoredRegistrationState>(stored), stateTtlSeconds)) {
                        reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to persist registration state", None))
                        return
                    }
                    let excludeViews = Array<WebauthnCredentialDescriptorView>(start.options.excludeCredentials.size, { i =>
                        WebauthnCredentialDescriptorView(start.options.excludeCredentials[i].id)
                    })
                    let paramViews = Array<WebauthnPubKeyCredParamView>(start.options.pubKeyCredParams.size, { i =>
                        WebauthnPubKeyCredParamView(start.options.pubKeyCredParams[i])
                    })
                    let view = WebauthnRegisterOptionsDataView(
                        challengeId,
                        WebauthnRegistrationPublicKeyView(
                            start.options.challenge,
                            WebauthnRpView(start.options.rp.id, start.options.rp.name),
                            WebauthnUserView(start.options.user.id, start.options.user.name, start.options.user.displayName),
                            start.options.timeoutMs,
                            paramViews,
                            excludeViews,
                            start.options.attestation,
                            WebauthnAuthenticatorSelectionView(start.options.residentKey, start.options.userVerification)
                        )
                    )
                    reply<WebauthnRegisterOptionsDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<WebauthnRegisterOptionsDataView>(200, "ok", Some(view)))
                } catch (e: Exception) {
                    reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, e.message, None))
                }
            case None =>
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "unable to determine rp origin", None))
        }
    }

    public static func registerVerify(ctx: Ctx, userId: Int64): Unit {
        let req = try {
            JsonCodec.decode<WebauthnRegisterVerifyReq>(ctx.bodyString())
        } catch (_: Exception) {
            WebauthnRegisterVerifyReq()
        }
        if (req.challengeId.size == 0) {
            reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "challengeId is required", None))
            return
        }
        let stored = loadRegistrationState(req.challengeId)
        match (stored) {
            case Some(state) =>
                if (state.userId != userId) {
                    reply<String>(ctx, HttpStatusCode.STATUS_FORBIDDEN, ApiResponse<String>(403, "registration state does not belong to current user", None))
                    return
                }
                let webauthn = Webauthn(
                    state.rpId,
                    state.rpId,
                    state.origins,
                    state.timeoutMs,
                    ["ES256"],
                    false,
                    false
                )
                let packageReq = RegistrationCredentialRequest()
                packageReq.id = req.credential.id
                packageReq.rawId = req.credential.rawId
                packageReq.clientDataJson = req.credential.clientDataJson
                packageReq.attestationObject = req.credential.attestationObject
                packageReq.transports = req.credential.transports
                let packageState = PasskeyRegistration(
                    state.challenge,
                    state.rpId,
                    state.origins,
                    state.createdAtSeconds,
                    state.timeoutMs,
                    state.userHandle,
                    state.userName,
                    state.userDisplayName,
                    excludeCredentialIds: state.excludeCredentialIds
                )

                try {
                    let passkey = webauthn.finishPasskeyRegistration(packageReq, packageState, nowSeconds: nowSeconds())
                    let existing = UserWebauthnCredentialDao.findActiveByCredentialId(passkey.credentialId)
                    if (existing.id > 0) {
                        reply<String>(ctx, HttpStatusCode.STATUS_CONFLICT, ApiResponse<String>(409, "credential already exists", None))
                        return
                    }
                    let name = if (req.name.trimAscii().size > 0) { req.name.trimAscii() } else { state.credentialName }
                    match (UserWebauthnCredentialDao.create(userId, name, passkey)) {
                        case Some(_) =>
                            let _ = PersistentCacheService.delete(registerNamespace, req.challengeId)
                            reply<String>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<String>(200, "registered", None))
                        case None =>
                            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to persist credential", None))
                    }
                } catch (e: WebauthnException) {
                    let _ = PersistentCacheService.delete(registerNamespace, req.challengeId)
                    reply<String>(ctx, mapWebauthnHttpStatus(e.code), ApiResponse<String>(Int32(mapWebauthnHttpStatus(e.code)), e.message, None))
                } catch (e: Exception) {
                    let _ = PersistentCacheService.delete(registerNamespace, req.challengeId)
                    reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, e.message, None))
                }
            case None =>
                reply<String>(ctx, UInt16(410), ApiResponse<String>(410, "registration state expired", None))
        }
    }

    public static func authenticateOptions(ctx: Ctx): Unit {
        let builderOpt = buildWebauthn(ctx)
        match (builderOpt) {
            case Some(webauthn) =>
                try {
                    let start = webauthn.startPasskeyAuthentication(Array<Passkey>(), nowSeconds: nowSeconds())
                    let challengeId = AuthUtils.generateTokenHex(bytesLen: 16)
                    let stored = StoredAuthenticationState()
                    stored.userId = 0
                    stored.challenge = start.state.challenge
                    stored.rpId = start.state.rpId
                    stored.origins = start.state.origins
                    stored.createdAtSeconds = start.state.createdAtSeconds
                    stored.timeoutMs = start.state.timeoutMs
                    if (!PersistentCacheService.set(authenticationNamespace, challengeId, JsonCodec.encode<StoredAuthenticationState>(stored), stateTtlSeconds)) {
                        reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to persist authentication state", None))
                        return
                    }
                    let allowViews = Array<WebauthnCredentialDescriptorView>(start.options.allowCredentials.size, { i =>
                        WebauthnCredentialDescriptorView(start.options.allowCredentials[i].id)
                    })
                    let view = WebauthnAuthenticateOptionsDataView(
                        challengeId,
                        WebauthnAuthenticationPublicKeyView(
                            start.options.challenge,
                            start.options.timeoutMs,
                            start.options.rpId,
                            allowViews,
                            start.options.userVerification
                        )
                    )
                    reply<WebauthnAuthenticateOptionsDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<WebauthnAuthenticateOptionsDataView>(200, "ok", Some(view)))
                } catch (e: Exception) {
                    reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, e.message, None))
                }
            case None =>
                reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "unable to determine rp origin", None))
        }
    }

    public static func authenticateVerify(ctx: Ctx): Unit {
        let req = try {
            JsonCodec.decode<WebauthnAuthenticateVerifyReq>(ctx.bodyString())
        } catch (_: Exception) {
            WebauthnAuthenticateVerifyReq()
        }
        if (req.challengeId.size == 0) {
            reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "challengeId is required", None))
            return
        }
        let stored = loadAuthenticationState(req.challengeId)
        match (stored) {
            case Some(state) =>
                let webauthn = Webauthn(
                    state.rpId,
                    state.rpId,
                    state.origins,
                    state.timeoutMs,
                    ["ES256"],
                    false,
                    false
                )
                let credentialLookupId = if (req.credential.rawId.trimAscii().size > 0) {
                    req.credential.rawId.trimAscii()
                } else {
                    req.credential.id.trimAscii()
                }
                let matchedCredential = UserWebauthnCredentialDao.findActiveByCredentialId(credentialLookupId)
                if (matchedCredential.id <= 0) {
                    let _ = PersistentCacheService.delete(authenticationNamespace, req.challengeId)
                    reply<String>(ctx, HttpStatusCode.STATUS_NOT_FOUND, ApiResponse<String>(404, "credential not found", None))
                    return
                }
                let resolvedUserId = matchedCredential.userId
                let credentials = [matchedCredential.toPasskey()]
                let packageState = PasskeyAuthentication(
                    state.challenge,
                    state.rpId,
                    state.origins,
                    state.createdAtSeconds,
                    state.timeoutMs,
                    credentials
                )
                let packageReq = AuthenticationCredentialRequest()
                packageReq.id = req.credential.id
                packageReq.rawId = req.credential.rawId
                packageReq.clientDataJson = req.credential.clientDataJson
                packageReq.authenticatorData = req.credential.authenticatorData
                packageReq.signature = req.credential.signature
                packageReq.userHandle = req.credential.userHandle

                try {
                    let result = webauthn.finishPasskeyAuthentication(packageReq, packageState, nowSeconds: nowSeconds())
                    if (!UserWebauthnCredentialDao.touchAndUpdateCredential(
                        resolvedUserId,
                        result.credentialId,
                        result.counter,
                        result.backupEligible,
                        result.backupState
                    )) {
                        reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to update passkey usage", None))
                        return
                    }
                    match (UserTokenDao.createToken(resolvedUserId, "webauthn", "session", AuthConfig.tokenPepper)) {
                        case Some(tokenRes) =>
                            let userRow = UserDao.getById(resolvedUserId)
                            let userView = UserView(userRow.id, userRow.username, None, Some(userRow.avatarAssetId), None)
                            let tokenView = TokenView(tokenRes.tokenId, "webauthn", tokenRes.prefix, Some(tokenRes.token), None, None, None)
                            let _ = PersistentCacheService.delete(authenticationNamespace, req.challengeId)
                            reply<UserTokenPairView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<UserTokenPairView>(200, "ok", Some(UserTokenPairView(userView, tokenView))))
                        case None =>
                            reply<String>(ctx, HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR, ApiResponse<String>(500, "failed to create session token", None))
                    }
                } catch (e: WebauthnException) {
                    let _ = PersistentCacheService.delete(authenticationNamespace, req.challengeId)
                    reply<String>(ctx, mapWebauthnHttpStatus(e.code), ApiResponse<String>(Int32(mapWebauthnHttpStatus(e.code)), e.message, None))
                } catch (e: Exception) {
                    let _ = PersistentCacheService.delete(authenticationNamespace, req.challengeId)
                    reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, e.message, None))
                }
            case None =>
                reply<String>(ctx, UInt16(410), ApiResponse<String>(410, "authentication state expired", None))
        }
    }

    public static func listCredentials(ctx: Ctx, userId: Int64): Unit {
        let rows = UserWebauthnCredentialDao.listActiveByUser(userId)
        let views = Array<WebauthnCredentialSummaryView>(rows.size, { i => WebauthnCredentialSummaryView(rows[i]) })
        reply<WebauthnCredentialListDataView>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<WebauthnCredentialListDataView>(200, "ok", Some(WebauthnCredentialListDataView(views))))
    }

    public static func revokeCredential(ctx: Ctx, userId: Int64): Unit {
        let idStr = ctx.paramsOpt("id") ?? ""
        let credentialId = try { Int64.parse(idStr) } catch (_: Exception) { 0 }
        if (credentialId <= 0) {
            reply<String>(ctx, HttpStatusCode.STATUS_BAD_REQUEST, ApiResponse<String>(400, "invalid credential id", None))
            return
        }
        if (UserWebauthnCredentialDao.revoke(userId, credentialId)) {
            reply<String>(ctx, HttpStatusCode.STATUS_OK, ApiResponse<String>(200, "revoked", None))
        } else {
            reply<String>(ctx, HttpStatusCode.STATUS_NOT_FOUND, ApiResponse<String>(404, "credential not found", None))
        }
    }
}

private func parseTransports(payload: String): Array<String> {
    let trimmed = payload.trimAscii()
    if (trimmed.size == 0) {
        return Array<String>()
    }
    try {
        let reader = JsonReader(ByteBuffer(trimmed.toArray()))
        return readStringArray(reader)
    } catch (_: Exception) {
        return Array<String>()
    }
}

private func writeStringArray(w: JsonWriter, values: Array<String>): Unit {
    w.startArray()
    for (value in values) {
        w.writeValue(value)
    }
    w.endArray()
}

private func readStringArray(r: JsonReader): Array<String> {
    if (r.peek() != Some(BeginArray)) {
        r.skip()
        return Array<String>()
    }
    let values = ArrayList<String>()
    r.startArray()
    while (r.peek() != EndArray) {
        values.add(r.readValue<String>())
    }
    r.endArray()
    return values.toArray()
}

private func loadRegistrationState(challengeId: String): Option<StoredRegistrationState> {
    match (PersistentCacheService.get("webauthn:registration", challengeId.trimAscii())) {
        case Some(raw) =>
            try { return Some(JsonCodec.decode<StoredRegistrationState>(raw)) } catch (_: Exception) { return None }
        case None => return None
    }
}

private func loadAuthenticationState(challengeId: String): Option<StoredAuthenticationState> {
    match (PersistentCacheService.get("webauthn:authentication", challengeId.trimAscii())) {
        case Some(raw) =>
            try { return Some(JsonCodec.decode<StoredAuthenticationState>(raw)) } catch (_: Exception) { return None }
        case None => return None
    }
}

private func buildWebauthn(ctx: Ctx): Option<Webauthn> {
    let originOpt = extractEffectiveOrigin(ctx)
    match (originOpt) {
        case Some(origin) =>
            let rpId = extractRpId(origin)
            if (rpId.size == 0) {
                return None
            }
            let builder = WebauthnBuilder(rpId, origin)
            builder.rpName("Lanlu")
            return Some(builder.build())
        case None => return None
    }
}

private func extractEffectiveOrigin(ctx: Ctx): Option<String> {
    let origin = (ctx.header("Origin") ?? "").trimAscii()
    if (origin.size > 0) {
        return Some(trimTrailingSlash(origin))
    }
    let host = (ctx.header("X-Forwarded-Host") ?? ctx.header("Host") ?? "").trimAscii()
    if (host.size == 0) {
        return None
    }
    let proto = (ctx.header("X-Forwarded-Proto") ?? "http").trimAscii().toAsciiLower()
    return Some(trimTrailingSlash("${proto}://${host}"))
}

private func trimTrailingSlash(input: String): String {
    var out = input
    while (out.size > 1 && out.endsWith("/")) {
        out = out[0..(out.size - 1)]
    }
    return out
}

private func extractRpId(origin: String): String {
    let trimmed = trimTrailingSlash(origin)
    let schemeIndexOpt = trimmed.indexOf("://")
    match (schemeIndexOpt) {
        case Some(idx) =>
            let authority = trimmed[(idx + 3)..trimmed.size]
            let slashIndexOpt = authority.indexOf("/")
            let hostPort = match (slashIndexOpt) {
                case Some(slashIdx) => authority[0..slashIdx]
                case None => authority
            }
            let colonIndexOpt = hostPort.lastIndexOf(":")
            match (colonIndexOpt) {
                case Some(colonIdx) => return hostPort[0..colonIdx]
                case None => return hostPort
            }
        case None => return ""
    }
}

private func deriveUserHandle(userId: Int64): String {
    let sha = SHA256()
    sha.write("lanlu-webauthn-user:${userId}:${AuthConfig.tokenPepper}".toArray())
    return base64UrlEncode(sha.finish())
}

private func nowSeconds(): Int64 {
    return DateTime.now().toUnixTimeStamp().toSeconds()
}

private func mapWebauthnHttpStatus(code: WebauthnFailureCode): UInt16 {
    match (code) {
        case WebauthnFailureCode.CredentialNotFound => return UInt16(404)
        case WebauthnFailureCode.CounterRollback => return UInt16(409)
        case WebauthnFailureCode.StateExpired => return UInt16(410)
        case _ => return UInt16(400)
    }
}
