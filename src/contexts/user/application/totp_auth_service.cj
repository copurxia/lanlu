package lanlu.contexts.user.application

import std.time.*
import stdx.encoding.json.stream.*
import lanlu.contexts.user.infrastructure.persistence.*
import lanlu.infrastructure.kv.*
import lanlu.shared.utils.*
import totp_cj.*

public class TotpLoginChallengeState <: JsonSerializable & JsonDeserializable<TotpLoginChallengeState> {
    public var userId: Int64 = 0
    public var username: String = ""
    public var tokenName: String = "login"
    public var createdAtSeconds: Int64 = 0

    public init() {}

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("userId").writeValue(userId)
        w.writeName("username").writeValue(username)
        w.writeName("tokenName").writeValue(tokenName)
        w.writeName("createdAtSeconds").writeValue(createdAtSeconds)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): TotpLoginChallengeState {
        let out = TotpLoginChallengeState()
        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            match (name) {
                case "userId" => out.userId = r.readValue<Int64>()
                case "username" => out.username = r.readValue<String>()
                case "tokenName" => out.tokenName = r.readValue<String>()
                case "createdAtSeconds" => out.createdAtSeconds = r.readValue<Int64>()
                case _ => r.skip()
            }
        }
        r.endObject()
        return out
    }
}

public class TotpEnrollmentState <: JsonSerializable & JsonDeserializable<TotpEnrollmentState> {
    public var userId: Int64 = 0
    public var username: String = ""
    public var name: String = ""
    public var secret: String = ""
    public var digits: Int64 = TotpConstants.defaultDigits
    public var periodSeconds: Int64 = TotpConstants.defaultPeriodSeconds
    public var algorithm: String = DEFAULT_ALGORITHM
    public var issuer: String = TotpConstants.defaultIssuer
    public var createdAtSeconds: Int64 = 0

    public init() {}

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("userId").writeValue(userId)
        w.writeName("username").writeValue(username)
        w.writeName("name").writeValue(name)
        w.writeName("secret").writeValue(secret)
        w.writeName("digits").writeValue(digits)
        w.writeName("periodSeconds").writeValue(periodSeconds)
        w.writeName("algorithm").writeValue(algorithm)
        w.writeName("issuer").writeValue(issuer)
        w.writeName("createdAtSeconds").writeValue(createdAtSeconds)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): TotpEnrollmentState {
        let out = TotpEnrollmentState()
        r.startObject()
        while (r.peek() != EndObject) {
            let name = r.readName()
            match (name) {
                case "userId" => out.userId = r.readValue<Int64>()
                case "username" => out.username = r.readValue<String>()
                case "name" => out.name = r.readValue<String>()
                case "secret" => out.secret = r.readValue<String>()
                case "digits" => out.digits = r.readValue<Int64>()
                case "periodSeconds" => out.periodSeconds = r.readValue<Int64>()
                case "algorithm" => out.algorithm = r.readValue<String>()
                case "issuer" => out.issuer = r.readValue<String>()
                case "createdAtSeconds" => out.createdAtSeconds = r.readValue<Int64>()
                case _ => r.skip()
            }
        }
        r.endObject()
        return out
    }
}

public class TotpEnrollmentStartResult {
    public let challengeId: String
    public let state: TotpEnrollmentState

    public init(challengeId: String, state: TotpEnrollmentState) {
        this.challengeId = challengeId
        this.state = state
    }
}

public class TotpChallengeCreateResult {
    public let challengeId: String
    public let state: TotpLoginChallengeState

    public init(challengeId: String, state: TotpLoginChallengeState) {
        this.challengeId = challengeId
        this.state = state
    }
}

public class TotpCredentialValidationResult {
    public let ok: Bool
    public let matchedStep: Int64
    public let reason: String

    public init(ok: Bool, matchedStep!: Int64 = -1, reason!: String = "") {
        this.ok = ok
        this.matchedStep = matchedStep
        this.reason = reason
    }
}

public class TotpAuthService {
    public static func createLoginChallenge(userId: Int64, username: String, tokenName: String): Option<TotpChallengeCreateResult> {
        let state = TotpLoginChallengeState()
        state.userId = userId
        state.username = username.trimAscii()
        state.tokenName = if (tokenName.trimAscii().size > 0) { tokenName.trimAscii() } else { "login" }
        state.createdAtSeconds = nowSeconds()

        let challengeId = AuthUtils.generateTokenHex(bytesLen: 16)
        let encoded = JsonCodec.encode<TotpLoginChallengeState>(state)
        if (!PersistentCacheService.set(TotpConstants.loginChallengeNamespace, challengeId, encoded, TotpConstants.challengeTtlSeconds)) {
            return None
        }
        return Some(TotpChallengeCreateResult(challengeId, state))
    }

    public static func loadLoginChallenge(challengeId: String): Option<TotpLoginChallengeState> {
        match (PersistentCacheService.get(TotpConstants.loginChallengeNamespace, challengeId.trimAscii())) {
            case Some(raw) =>
                try { return Some(JsonCodec.decode<TotpLoginChallengeState>(raw)) } catch (_: Exception) { return None }
            case None => return None
        }
    }

    public static func deleteLoginChallenge(challengeId: String): Bool {
        return PersistentCacheService.delete(TotpConstants.loginChallengeNamespace, challengeId.trimAscii())
    }

    public static func startEnrollment(userId: Int64, username: String, name: String): Option<TotpEnrollmentStartResult> {
        if (!TotpUtils.isConfigured()) {
            return None
        }
        let state = TotpEnrollmentState()
        state.userId = userId
        state.username = username.trimAscii()
        state.name = if (name.trimAscii().size > 0) { name.trimAscii() } else { "Authenticator App" }
        state.secret = generateSecret()
        state.digits = TotpConstants.defaultDigits
        state.periodSeconds = TotpConstants.defaultPeriodSeconds
        state.algorithm = DEFAULT_ALGORITHM
        state.issuer = TotpUtils.safeIssuer()
        state.createdAtSeconds = nowSeconds()

        let challengeId = AuthUtils.generateTokenHex(bytesLen: 16)
        if (!PersistentCacheService.set(
            TotpConstants.enrollmentNamespace,
            challengeId,
            JsonCodec.encode<TotpEnrollmentState>(state),
            TotpConstants.challengeTtlSeconds
        )) {
            return None
        }
        return Some(TotpEnrollmentStartResult(challengeId, state))
    }

    public static func loadEnrollment(challengeId: String): Option<TotpEnrollmentState> {
        match (PersistentCacheService.get(TotpConstants.enrollmentNamespace, challengeId.trimAscii())) {
            case Some(raw) =>
                try { return Some(JsonCodec.decode<TotpEnrollmentState>(raw)) } catch (_: Exception) { return None }
            case None => return None
        }
    }

    public static func deleteEnrollment(challengeId: String): Bool {
        return PersistentCacheService.delete(TotpConstants.enrollmentNamespace, challengeId.trimAscii())
    }

    public static func validateCredential(credential: UserTotpCredentialRow, code: String): TotpCredentialValidationResult {
        if (!TotpUtils.isConfigured()) {
            return TotpCredentialValidationResult(false, reason: "totp is unavailable: JWT_SECRET or AUTH_TOTP_SECRET_KEY is missing")
        }
        if (credential.id <= 0 || credential.userId <= 0) {
            return TotpCredentialValidationResult(false, reason: "totp credential not found")
        }
        let normalizedCode = TotpUtils.normalizeCode(code)
        if (normalizedCode.size != credential.digits) {
            return TotpCredentialValidationResult(false, reason: "invalid totp code")
        }

        let secret = try {
            TotpUtils.decryptSecret(credential.encryptedSecret, credential.userId)
        } catch (_: Exception) {
            return TotpCredentialValidationResult(false, reason: "failed to decrypt totp secret")
        }

        let result = try {
            verifyCodeDetailed(
                secret,
                normalizedCode,
                nowSeconds(),
                window: TotpConstants.defaultWindow,
                stepSeconds: credential.periodSeconds,
                digits: credential.digits,
                algorithm: credential.algorithm
            )
        } catch (_: Exception) {
            return TotpCredentialValidationResult(false, reason: "invalid totp code")
        }

        if (!result.valid) {
            return TotpCredentialValidationResult(false, reason: "invalid totp code")
        }
        if (result.matchedStep <= credential.lastUsedStep) {
            return TotpCredentialValidationResult(false, reason: "totp code already used")
        }
        return TotpCredentialValidationResult(true, matchedStep: result.matchedStep)
    }

    public static func verifyEnrollmentCode(state: TotpEnrollmentState, code: String): TotpCredentialValidationResult {
        let normalizedCode = TotpUtils.normalizeCode(code)
        if (normalizedCode.size != state.digits) {
            return TotpCredentialValidationResult(false, reason: "invalid totp code")
        }
        let result = try {
            verifyCodeDetailed(
                state.secret,
                normalizedCode,
                nowSeconds(),
                window: TotpConstants.defaultWindow,
                stepSeconds: state.periodSeconds,
                digits: state.digits,
                algorithm: state.algorithm
            )
        } catch (_: Exception) {
            return TotpCredentialValidationResult(false, reason: "invalid totp code")
        }
        return TotpCredentialValidationResult(result.valid, matchedStep: result.matchedStep, reason: if (result.valid) { "" } else { "invalid totp code" })
    }

    public static func createRecoveryCodes(): Array<String> {
        return TotpUtils.generateRecoveryCodes()
    }

    public static func recoveryCodeHashes(codes: Array<String>): Array<String> {
        return Array<String>(codes.size, { i => TotpUtils.hashRecoveryCode(codes[i]) })
    }

    public static func useRecoveryCode(credential: UserTotpCredentialRow, recoveryCode: String): Bool {
        let normalized = TotpUtils.normalizeRecoveryCode(recoveryCode)
        if (normalized.size == 0) {
            return false
        }
        return UserTotpCredentialDao.consumeRecoveryCode(credential.id, TotpUtils.hashRecoveryCode(normalized))
    }

    public static func accountName(username: String): String {
        return username.trimAscii()
    }

    private static func nowSeconds(): Int64 {
        return DateTime.now().toUnixTimeStamp().toSeconds()
    }
}
