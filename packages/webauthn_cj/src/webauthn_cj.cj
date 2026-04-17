package webauthn_cj

import std.collection.*
import std.io.ByteBuffer
import stdx.crypto.crypto.*
import stdx.crypto.digest.*
import stdx.crypto.keys.*
import stdx.encoding.base64.*
import stdx.encoding.json.stream.*

public enum WebauthnFailureCode {
    | ChallengeMismatch
    | OriginMismatch
    | RpIdMismatch
    | CredentialNotFound
    | UnsupportedAlgorithm
    | InvalidAttestation
    | InvalidAssertion
    | CounterRollback
    | StateExpired
    | InvalidState
    | InvalidClientData
    | InvalidAuthenticatorData
}

public class WebauthnException <: Exception {
    public let code: WebauthnFailureCode

    public init(code: WebauthnFailureCode, message: String) {
        super(message)
        this.code = code
    }

    protected override func getClassName(): String {
        return "WebauthnException"
    }
}

public class CredentialDescriptor {
    public var id: String
    public var credentialType: String

    public init(id: String, credentialType!: String = "public-key") {
        this.id = id
        this.credentialType = credentialType
    }
}

public class RelyingParty {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        this.id = id
        this.name = name
    }
}

public class UserEntity {
    public var id: String
    public var name: String
    public var displayName: String

    public init(id: String, name: String, displayName: String) {
        this.id = id
        this.name = name
        this.displayName = displayName
    }
}

public class Passkey {
    public var credentialId: String
    public var algorithm: String
    public var publicKey: String
    public var counter: Int64
    public var transports: Array<String>
    public var userVerified: Bool
    public var backupEligible: Bool
    public var backupState: Bool
    public var aaguid: String
    public var attestationFormat: String

    public init(
        credentialId: String,
        algorithm: String,
        publicKey: String,
        counter: Int64,
        transports!: Array<String> = Array<String>(),
        userVerified!: Bool = false,
        backupEligible!: Bool = false,
        backupState!: Bool = false,
        aaguid!: String = "",
        attestationFormat!: String = "none"
    ) {
        this.credentialId = credentialId
        this.algorithm = algorithm
        this.publicKey = publicKey
        this.counter = counter
        this.transports = transports
        this.userVerified = userVerified
        this.backupEligible = backupEligible
        this.backupState = backupState
        this.aaguid = aaguid
        this.attestationFormat = attestationFormat
    }
}

public class AuthenticationResult {
    public var credentialId: String
    public var counter: Int64
    public var userVerified: Bool
    public var backupEligible: Bool
    public var backupState: Bool
    public var needsUpdate: Bool

    public init(
        credentialId: String,
        counter: Int64,
        userVerified: Bool,
        backupEligible: Bool,
        backupState: Bool,
        needsUpdate: Bool
    ) {
        this.credentialId = credentialId
        this.counter = counter
        this.userVerified = userVerified
        this.backupEligible = backupEligible
        this.backupState = backupState
        this.needsUpdate = needsUpdate
    }
}

public class PasskeyRegistration {
    public var challenge: String
    public var rpId: String
    public var origins: Array<String>
    public var createdAtSeconds: Int64
    public var timeoutMs: Int64
    public var userHandle: String
    public var userName: String
    public var userDisplayName: String
    public var excludeCredentialIds: Array<String>

    public init(
        challenge: String,
        rpId: String,
        origins: Array<String>,
        createdAtSeconds: Int64,
        timeoutMs: Int64,
        userHandle: String,
        userName: String,
        userDisplayName: String,
        excludeCredentialIds!: Array<String> = Array<String>()
    ) {
        this.challenge = challenge
        this.rpId = rpId
        this.origins = origins
        this.createdAtSeconds = createdAtSeconds
        this.timeoutMs = timeoutMs
        this.userHandle = userHandle
        this.userName = userName
        this.userDisplayName = userDisplayName
        this.excludeCredentialIds = excludeCredentialIds
    }
}

public class PasskeyAuthentication {
    public var challenge: String
    public var rpId: String
    public var origins: Array<String>
    public var createdAtSeconds: Int64
    public var timeoutMs: Int64
    public var credentials: Array<Passkey>

    public init(
        challenge: String,
        rpId: String,
        origins: Array<String>,
        createdAtSeconds: Int64,
        timeoutMs: Int64,
        credentials: Array<Passkey>
    ) {
        this.challenge = challenge
        this.rpId = rpId
        this.origins = origins
        this.createdAtSeconds = createdAtSeconds
        this.timeoutMs = timeoutMs
        this.credentials = credentials
    }
}

public class RegistrationOptions {
    public var challenge: String
    public var rp: RelyingParty
    public var user: UserEntity
    public var timeoutMs: Int64
    public var pubKeyCredParams: Array<Int64>
    public var excludeCredentials: Array<CredentialDescriptor>
    public var attestation: String
    public var authenticatorAttachment: String
    public var residentKey: String
    public var userVerification: String

    public init(
        challenge: String,
        rp: RelyingParty,
        user: UserEntity,
        timeoutMs: Int64,
        pubKeyCredParams: Array<Int64>,
        excludeCredentials: Array<CredentialDescriptor>
    ) {
        this.challenge = challenge
        this.rp = rp
        this.user = user
        this.timeoutMs = timeoutMs
        this.pubKeyCredParams = pubKeyCredParams
        this.excludeCredentials = excludeCredentials
        this.attestation = "none"
        this.authenticatorAttachment = ""
        this.residentKey = "required"
        this.userVerification = "required"
    }
}

public class AuthenticationOptions {
    public var challenge: String
    public var timeoutMs: Int64
    public var rpId: String
    public var allowCredentials: Array<CredentialDescriptor>
    public var userVerification: String

    public init(challenge: String, timeoutMs: Int64, rpId: String, allowCredentials: Array<CredentialDescriptor>) {
        this.challenge = challenge
        this.timeoutMs = timeoutMs
        this.rpId = rpId
        this.allowCredentials = allowCredentials
        this.userVerification = "required"
    }
}

public class RegistrationStartResult {
    public var options: RegistrationOptions
    public var state: PasskeyRegistration

    public init(options: RegistrationOptions, state: PasskeyRegistration) {
        this.options = options
        this.state = state
    }
}

public class AuthenticationStartResult {
    public var options: AuthenticationOptions
    public var state: PasskeyAuthentication

    public init(options: AuthenticationOptions, state: PasskeyAuthentication) {
        this.options = options
        this.state = state
    }
}

public class RegistrationCredentialRequest {
    public var id: String = ""
    public var rawId: String = ""
    public var clientDataJson: String = ""
    public var attestationObject: String = ""
    public var transports: Array<String> = Array<String>()

    public init() {}
}

public class AuthenticationCredentialRequest {
    public var id: String = ""
    public var rawId: String = ""
    public var clientDataJson: String = ""
    public var authenticatorData: String = ""
    public var signature: String = ""
    public var userHandle: String = ""

    public init() {}
}

private class ClientData {
    public var clientDataType: String = ""
    public var challenge: String = ""
    public var origin: String = ""
    public var crossOrigin: Bool = false
}

private class ParsedAuthenticatorData {
    public var rpIdHash: Array<Byte> = Array<Byte>()
    public var flags: UInt8 = 0u8
    public var signCount: Int64 = 0
    public var credentialId: String = ""
    public var publicKeyDer: String = ""
    public var aaguid: String = ""
    public var backupEligible: Bool = false
    public var backupState: Bool = false
    public var userPresent: Bool = false
    public var userVerified: Bool = false
}

public class WebauthnBuilder {
    private var rpId: String
    private var allowedOrigins: ArrayList<String> = ArrayList<String>()
    private var rpNameValue: String
    private var timeoutMsValue: Int64 = 300000
    private var algorithms: ArrayList<String> = ArrayList<String>()
    private var allowSubdomainsEnabled: Bool = false
    private var allowAnyPortEnabled: Bool = false

    public init(rpId: String, allowedOrigin: String) {
        this.rpId = rpId.trimAscii()
        this.rpNameValue = this.rpId
        this.allowedOrigins.add(allowedOrigin.trimAscii())
        this.algorithms.add("ES256")
    }

    public func rpName(name: String): WebauthnBuilder {
        this.rpNameValue = name.trimAscii()
        return this
    }

    public func timeoutMs(timeoutMs: Int64): WebauthnBuilder {
        this.timeoutMsValue = timeoutMs
        return this
    }

    public func appendAllowedOrigin(origin: String): WebauthnBuilder {
        let trimmed = origin.trimAscii()
        if (trimmed.size > 0) {
            this.allowedOrigins.add(trimmed)
        }
        return this
    }

    public func allowSubdomains(allow: Bool): WebauthnBuilder {
        this.allowSubdomainsEnabled = allow
        return this
    }

    public func allowAnyPort(allow: Bool): WebauthnBuilder {
        this.allowAnyPortEnabled = allow
        return this
    }

    public func build(): Webauthn {
        return Webauthn(
            rpId,
            rpNameValue,
            allowedOrigins.toArray(),
            timeoutMsValue,
            algorithms.toArray(),
            allowSubdomainsEnabled,
            allowAnyPortEnabled
        )
    }
}

public class Webauthn {
    private let rpId: String
    private let rpName: String
    private let allowedOrigins: Array<String>
    private let timeoutMs: Int64
    private let algorithms: Array<String>
    private let allowSubdomains: Bool
    private let allowAnyPort: Bool

    public init(
        rpId: String,
        rpName: String,
        allowedOrigins: Array<String>,
        timeoutMs: Int64,
        algorithms: Array<String>,
        allowSubdomains: Bool,
        allowAnyPort: Bool
    ) {
        this.rpId = rpId
        this.rpName = rpName
        this.allowedOrigins = allowedOrigins
        this.timeoutMs = timeoutMs
        this.algorithms = algorithms
        this.allowSubdomains = allowSubdomains
        this.allowAnyPort = allowAnyPort
    }

    public func startPasskeyRegistration(
        userHandle: String,
        userName: String,
        userDisplayName: String,
        excludeCredentialIds!: Array<String> = Array<String>(),
        nowSeconds!: Int64 = 0
    ): RegistrationStartResult {
        let challengeBytes = randomBytes(32)
        let challenge = base64UrlEncode(challengeBytes)
        let created = if (nowSeconds > 0) { nowSeconds } else { 0 }
        let state = PasskeyRegistration(
            challenge,
            rpId,
            allowedOrigins,
            created,
            timeoutMs,
            userHandle,
            userName,
            userDisplayName,
            excludeCredentialIds: excludeCredentialIds
        )

        var descriptors = Array<CredentialDescriptor>()
        if (excludeCredentialIds.size > 0) {
            descriptors = Array<CredentialDescriptor>(excludeCredentialIds.size, {
                i => CredentialDescriptor(excludeCredentialIds[i])
            })
        }

        let options = RegistrationOptions(
            challenge,
            RelyingParty(rpId, rpName),
            UserEntity(userHandle, userName, userDisplayName),
            timeoutMs,
            Array<Int64>(1, { _ => -7 }),
            descriptors
        )
        return RegistrationStartResult(options, state)
    }

    public func finishPasskeyRegistration(
        registrationResponse: RegistrationCredentialRequest,
        registrationState: PasskeyRegistration,
        nowSeconds!: Int64 = 0
    ): Passkey {
        assertNotExpired(registrationState.createdAtSeconds, registrationState.timeoutMs, nowSeconds)

        let rawId = nonEmptyOr(registrationResponse.rawId, registrationResponse.id)
        let clientDataBytes = decodeB64OrThrow(registrationResponse.clientDataJson, WebauthnFailureCode.InvalidClientData, "invalid clientDataJSON")
        let clientData = parseClientDataJson(clientDataBytes)
        if (clientData.clientDataType != "webauthn.create") {
            throw WebauthnException(WebauthnFailureCode.InvalidClientData, "unexpected clientData type")
        }
        if (clientData.challenge != registrationState.challenge) {
            throw WebauthnException(WebauthnFailureCode.ChallengeMismatch, "challenge mismatch")
        }
        assertAllowedOrigin(clientData.origin)

        let attestationBytes = decodeB64OrThrow(registrationResponse.attestationObject, WebauthnFailureCode.InvalidAttestation, "invalid attestationObject")
        let attestation = parseAttestationObject(attestationBytes)
        assertRpIdHash(attestation.authData.rpIdHash)
        if (!attestation.authData.userPresent || !attestation.authData.userVerified) {
            throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "user presence and verification are required")
        }

        for (existing in registrationState.excludeCredentialIds) {
            if (existing == attestation.authData.credentialId || existing == rawId) {
                throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "credential already registered")
            }
        }

        let clientHash = sha256Bytes(clientDataBytes)
        let signedData = concatBytes(attestation.rawAuthData, clientHash)
        match (attestation.fmt) {
            case "none" => ()
            case "packed" =>
                if (attestation.signature.size == 0) {
                    throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "packed attestation missing signature")
                }
                if (!verifyEs256(attestation.authData.publicKeyDer, signedData, attestation.signature)) {
                    throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "packed attestation verification failed")
                }
            case _ =>
                throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "unsupported attestation format")
        }

        let credentialId = if (attestation.authData.credentialId.size > 0) {
            attestation.authData.credentialId
        } else {
            rawId
        }
        return Passkey(
            credentialId,
            "ES256",
            attestation.authData.publicKeyDer,
            attestation.authData.signCount,
            transports: registrationResponse.transports,
            userVerified: attestation.authData.userVerified,
            backupEligible: attestation.authData.backupEligible,
            backupState: attestation.authData.backupState,
            aaguid: attestation.authData.aaguid,
            attestationFormat: attestation.fmt
        )
    }

    public func startPasskeyAuthentication(
        creds: Array<Passkey>,
        nowSeconds!: Int64 = 0
    ): AuthenticationStartResult {
        let challengeBytes = randomBytes(32)
        let challenge = base64UrlEncode(challengeBytes)
        let created = if (nowSeconds > 0) { nowSeconds } else { 0 }
        let state = PasskeyAuthentication(challenge, rpId, allowedOrigins, created, timeoutMs, creds)
        let descriptors = if (creds.size > 0) {
            Array<CredentialDescriptor>(creds.size, { i =>
                CredentialDescriptor(creds[i].credentialId)
            })
        } else {
            Array<CredentialDescriptor>()
        }
        let options = AuthenticationOptions(challenge, timeoutMs, rpId, descriptors)
        return AuthenticationStartResult(options, state)
    }

    public func finishPasskeyAuthentication(
        authenticationResponse: AuthenticationCredentialRequest,
        authenticationState: PasskeyAuthentication,
        nowSeconds!: Int64 = 0
    ): AuthenticationResult {
        assertNotExpired(authenticationState.createdAtSeconds, authenticationState.timeoutMs, nowSeconds)

        let rawId = nonEmptyOr(authenticationResponse.rawId, authenticationResponse.id)
        let credOpt = findCredential(authenticationState.credentials, rawId)
        match (credOpt) {
            case Some(cred) =>
                let clientDataBytes = decodeB64OrThrow(authenticationResponse.clientDataJson, WebauthnFailureCode.InvalidClientData, "invalid clientDataJSON")
                let clientData = parseClientDataJson(clientDataBytes)
                if (clientData.clientDataType != "webauthn.get") {
                    throw WebauthnException(WebauthnFailureCode.InvalidClientData, "unexpected clientData type")
                }
                if (clientData.challenge != authenticationState.challenge) {
                    throw WebauthnException(WebauthnFailureCode.ChallengeMismatch, "challenge mismatch")
                }
                assertAllowedOrigin(clientData.origin)

                let authDataBytes = decodeB64OrThrow(authenticationResponse.authenticatorData, WebauthnFailureCode.InvalidAuthenticatorData, "invalid authenticatorData")
                let authData = parseAssertionAuthenticatorData(authDataBytes)
                assertRpIdHash(authData.rpIdHash)
                if (!authData.userPresent || !authData.userVerified) {
                    throw WebauthnException(WebauthnFailureCode.InvalidAssertion, "user presence and verification are required")
                }

                let signature = decodeB64OrThrow(authenticationResponse.signature, WebauthnFailureCode.InvalidAssertion, "invalid signature")
                let signedData = concatBytes(authDataBytes, sha256Bytes(clientDataBytes))
                if (!verifyEs256(cred.publicKey, signedData, signature)) {
                    throw WebauthnException(WebauthnFailureCode.InvalidAssertion, "signature verification failed")
                }

                if (cred.counter > 0 && authData.signCount <= cred.counter) {
                    throw WebauthnException(WebauthnFailureCode.CounterRollback, "credential counter rollback detected")
                }

                let needsUpdate = authData.signCount > cred.counter ||
                    authData.backupEligible != cred.backupEligible ||
                    authData.backupState != cred.backupState
                return AuthenticationResult(
                    cred.credentialId,
                    authData.signCount,
                    authData.userVerified,
                    authData.backupEligible,
                    authData.backupState,
                    needsUpdate
                )
            case None =>
                throw WebauthnException(WebauthnFailureCode.CredentialNotFound, "credential not found")
        }
    }

    private func assertAllowedOrigin(origin: String): Unit {
        for (allowed in allowedOrigins) {
            if (matchesOrigin(origin, allowed)) {
                return
            }
        }
        throw WebauthnException(WebauthnFailureCode.OriginMismatch, "origin mismatch")
    }

    private func matchesOrigin(origin: String, allowed: String): Bool {
        if (origin == allowed) {
            return true
        }

        let originParts = parseOrigin(origin)
        let allowedParts = parseOrigin(allowed)
        if (originParts.size != 3 || allowedParts.size != 3) {
            return false
        }
        if (originParts[0] != allowedParts[0]) {
            return false
        }

        let originHost = originParts[1]
        let allowedHost = allowedParts[1]
        if (originHost == allowedHost) {
            if (allowAnyPort) {
                return true
            }
            return originParts[2] == allowedParts[2]
        }

        if (allowSubdomains && originHost.endsWith(".${allowedHost}")) {
            if (allowAnyPort) {
                return true
            }
            return originParts[2] == allowedParts[2]
        }
        return false
    }

    private func parseOrigin(origin: String): Array<String> {
        let trimmed = origin.trimAscii()
        let schemeSplit = trimmed.split("://")
        if (schemeSplit.size != 2) {
            return Array<String>()
        }
        let scheme = schemeSplit[0]
        let rest = schemeSplit[1]
        let slashIndex = rest.indexOf("/")
        let authority = match (slashIndex) {
            case Some(idx) => rest[0..idx]
            case None => rest
        }
        let colonIndex = authority.lastIndexOf(":")
        match (colonIndex) {
            case Some(idx) =>
                return [scheme, authority[0..idx], authority[(idx + 1)..authority.size]]
            case None =>
                let port = if (scheme == "https") { "443" } else if (scheme == "http") { "80" } else { "" }
                return [scheme, authority, port]
        }
    }

    private func assertRpIdHash(actual: Array<Byte>): Unit {
        let expected = sha256Bytes(rpId.toArray())
        if (!bytesEqual(actual, expected)) {
            throw WebauthnException(WebauthnFailureCode.RpIdMismatch, "rpId hash mismatch")
        }
    }
}

private class ParsedAttestationObject {
    public var fmt: String = "none"
    public var rawAuthData: Array<Byte> = Array<Byte>()
    public var authData: ParsedAuthenticatorData = ParsedAuthenticatorData()
    public var signature: Array<Byte> = Array<Byte>()
}

private func nonEmptyOr(primary: String, fallback: String): String {
    let trimmed = primary.trimAscii()
    if (trimmed.size > 0) {
        return trimmed
    }
    return fallback.trimAscii()
}

private func assertNotExpired(createdAtSeconds: Int64, timeoutMs: Int64, nowSeconds: Int64): Unit {
    if (createdAtSeconds <= 0 || nowSeconds <= 0 || timeoutMs <= 0) {
        return
    }
    let ttlSeconds = timeoutMs / 1000
    if (ttlSeconds > 0 && nowSeconds - createdAtSeconds > ttlSeconds) {
        throw WebauthnException(WebauthnFailureCode.StateExpired, "challenge state expired")
    }
}

private func findCredential(creds: Array<Passkey>, credentialId: String): Option<Passkey> {
    for (cred in creds) {
        if (cred.credentialId == credentialId) {
            return Some(cred)
        }
    }
    return None
}

private func randomBytes(size: Int32): Array<Byte> {
    let r = SecureRandom()
    return r.nextBytes(size)
}

public func base64UrlEncode(bytes: Array<Byte>): String {
    let base = toBase64String(bytes)
    var out = base.replace("+", "-").replace("/", "_")
    while (out.endsWith("=")) {
        out = out[0..(out.size - 1)]
    }
    return out
}

public func base64UrlDecode(input: String): Option<Array<Byte>> {
    let trimmed = input.trimAscii()
    if (trimmed.size == 0) {
        return None
    }
    var normalized = trimmed.replace("-", "+").replace("_", "/")
    let mod4 = normalized.size % 4
    if (mod4 == 2) {
        normalized = "${normalized}=="
    } else if (mod4 == 3) {
        normalized = "${normalized}="
    } else if (mod4 == 1) {
        return None
    }
    return fromBase64String(normalized)
}

private func decodeB64OrThrow(input: String, code: WebauthnFailureCode, message: String): Array<Byte> {
    match (base64UrlDecode(input)) {
        case Some(bytes) => return bytes
        case None => throw WebauthnException(code, message)
    }
}

private func sha256Bytes(input: Array<Byte>): Array<Byte> {
    let sha = SHA256()
    sha.write(input)
    return sha.finish()
}

private func bytesEqual(a: Array<Byte>, b: Array<Byte>): Bool {
    if (a.size != b.size) {
        return false
    }
    for (i in 0..a.size) {
        if (a[i] != b[i]) {
            return false
        }
    }
    return true
}

private func concatBytes(a: Array<Byte>, b: Array<Byte>): Array<Byte> {
    let out = ArrayList<Byte>()
    for (item in a) { out.add(item) }
    for (item in b) { out.add(item) }
    return out.toArray()
}

private func parseClientDataJson(bytes: Array<Byte>): ClientData {
    let text = try { String.fromUtf8(bytes) } catch (_: Exception) {
        throw WebauthnException(WebauthnFailureCode.InvalidClientData, "invalid clientData utf8")
    }
    var buf = ByteBuffer(text.toArray())
    let reader = JsonReader(buf)
    if (reader.peek() != Some(BeginObject)) {
        throw WebauthnException(WebauthnFailureCode.InvalidClientData, "clientDataJSON must be an object")
    }
    let out = ClientData()
    reader.startObject()
    while (reader.peek() != EndObject) {
        let name = reader.readName()
        match (name) {
            case "type" => out.clientDataType = reader.readValue<String>()
            case "challenge" => out.challenge = reader.readValue<String>()
            case "origin" => out.origin = reader.readValue<String>()
            case "crossOrigin" => out.crossOrigin = reader.readValue<Bool>()
            case _ => reader.skip()
        }
    }
    reader.endObject()
    return out
}

private func parseAttestationObject(bytes: Array<Byte>): ParsedAttestationObject {
    let parser = CborParser(bytes)
    let root = parser.readValue()
    let map = root.asMapOrThrow(WebauthnFailureCode.InvalidAttestation, "attestationObject must be a CBOR map")
    let out = ParsedAttestationObject()

    match (map.get("fmt")) {
        case Some(value) => out.fmt = value.asTextOrThrow(WebauthnFailureCode.InvalidAttestation, "invalid attestation fmt")
        case None => throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "missing attestation fmt")
    }
    match (map.get("authData")) {
        case Some(value) =>
            out.rawAuthData = value.asBytesOrThrow(WebauthnFailureCode.InvalidAttestation, "invalid authData")
            out.authData = parseRegistrationAuthenticatorData(out.rawAuthData)
        case None => throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "missing authData")
    }

    if (out.fmt == "packed") {
        match (map.get("attStmt")) {
            case Some(attStmtValue) =>
                let attStmt = attStmtValue.asMapOrThrow(WebauthnFailureCode.InvalidAttestation, "invalid attStmt")
                match (attStmt.get("alg")) {
                    case Some(algValue) =>
                        let alg = algValue.asIntOrThrow(WebauthnFailureCode.InvalidAttestation, "invalid attStmt alg")
                        if (alg != -7) {
                            throw WebauthnException(WebauthnFailureCode.UnsupportedAlgorithm, "only ES256 is supported")
                        }
                    case None => throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "missing attStmt alg")
                }
                match (attStmt.get("sig")) {
                    case Some(sigValue) =>
                        out.signature = sigValue.asBytesOrThrow(WebauthnFailureCode.InvalidAttestation, "invalid attStmt signature")
                    case None => throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "missing attStmt signature")
                }
            case None => throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "missing attStmt")
        }
    }

    return out
}

private func parseRegistrationAuthenticatorData(bytes: Array<Byte>): ParsedAuthenticatorData {
    if (bytes.size < 55) {
        throw WebauthnException(WebauthnFailureCode.InvalidAuthenticatorData, "authenticatorData too short")
    }
    let out = ParsedAuthenticatorData()
    out.rpIdHash = bytes.slice(0, 32).toArray()
    out.flags = bytes[32]
    out.signCount = readUInt32(bytes, 33)
    out.userPresent = (out.flags & 0x01u8) != 0u8
    out.userVerified = (out.flags & 0x04u8) != 0u8
    out.backupEligible = (out.flags & 0x08u8) != 0u8
    out.backupState = (out.flags & 0x10u8) != 0u8

    if ((out.flags & 0x40u8) == 0u8) {
        throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "attested credential data missing")
    }

    out.aaguid = bytesToHex(bytes.slice(37, 16).toArray())
    let credentialIdLength = Int64(Int32(bytes[53]) * 256 + Int32(bytes[54]))
    let credentialIdStart = 55
    let credentialIdEnd = credentialIdStart + credentialIdLength
    if (credentialIdEnd > bytes.size) {
        throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "invalid credential id length")
    }
    let credentialIdBytes = bytes.slice(credentialIdStart, credentialIdLength).toArray()
    out.credentialId = base64UrlEncode(credentialIdBytes)
    let publicKeyBytes = bytes.slice(credentialIdEnd, bytes.size - credentialIdEnd).toArray()
    let coseKey = parseCoseEc2Key(publicKeyBytes)
    out.publicKeyDer = base64UrlEncode(coseKey.publicKeyDer)
    return out
}

private func parseAssertionAuthenticatorData(bytes: Array<Byte>): ParsedAuthenticatorData {
    if (bytes.size < 37) {
        throw WebauthnException(WebauthnFailureCode.InvalidAuthenticatorData, "assertion authenticatorData too short")
    }
    let out = ParsedAuthenticatorData()
    out.rpIdHash = bytes.slice(0, 32).toArray()
    out.flags = bytes[32]
    out.signCount = readUInt32(bytes, 33)
    out.userPresent = (out.flags & 0x01u8) != 0u8
    out.userVerified = (out.flags & 0x04u8) != 0u8
    out.backupEligible = (out.flags & 0x08u8) != 0u8
    out.backupState = (out.flags & 0x10u8) != 0u8
    return out
}

private class ParsedCoseEc2Key {
    public var publicKeyDer: Array<Byte> = Array<Byte>()
}

private func parseCoseEc2Key(bytes: Array<Byte>): ParsedCoseEc2Key {
    let parser = CborParser(bytes)
    let map = parser.readValue().asIntMapOrThrow(WebauthnFailureCode.InvalidAttestation, "COSE key must be a map")

    let kty = getIntMapInt(map, 1, WebauthnFailureCode.InvalidAttestation, "missing COSE kty")
    let alg = getIntMapInt(map, 3, WebauthnFailureCode.InvalidAttestation, "missing COSE alg")
    let curve = getIntMapInt(map, -1, WebauthnFailureCode.InvalidAttestation, "missing COSE curve")
    if (kty != 2 || alg != -7 || curve != 1) {
        throw WebauthnException(WebauthnFailureCode.UnsupportedAlgorithm, "only ES256 / P-256 COSE keys are supported")
    }

    let x = getIntMapBytes(map, -2, WebauthnFailureCode.InvalidAttestation, "missing COSE x")
    let y = getIntMapBytes(map, -3, WebauthnFailureCode.InvalidAttestation, "missing COSE y")
    if (x.size != 32 || y.size != 32) {
        throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "invalid P-256 coordinate length")
    }

    let uncompressed = ArrayList<Byte>()
    uncompressed.add(0x04)
    for (b in x) { uncompressed.add(b) }
    for (b in y) { uncompressed.add(b) }
    let out = ParsedCoseEc2Key()
    out.publicKeyDer = buildEcPublicKeyDer(uncompressed.toArray())
    return out
}

private func verifyEs256(publicKeyDerB64Url: String, signedData: Array<Byte>, signature: Array<Byte>): Bool {
    match (base64UrlDecode(publicKeyDerB64Url)) {
        case Some(derBytes) =>
            try {
                let pubKey = ECDSAPublicKey.decodeFromPem(derBytesToPem(derBytes, "PUBLIC KEY"))
                let digest = sha256Bytes(signedData)
                return pubKey.verify(digest, signature)
            } catch (_: Exception) {
                return false
            }
        case None => return false
    }
}

private func derBytesToPem(derBytes: Array<Byte>, label: String): String {
    let encoded = toBase64String(derBytes)
    let out = StringBuilder()
    out.append("-----BEGIN ${label}-----\n")
    var start = 0
    while (start < encoded.size) {
        let end = min(start + 64, encoded.size)
        out.append(String.fromUtf8(encoded.toArray()[start..end]))
        out.append("\n")
        start = end
    }
    out.append("-----END ${label}-----\n")
    return out.toString()
}

private func buildEcPublicKeyDer(uncompressedPoint: Array<Byte>): Array<Byte> {
    let algorithmSequence = encodeDerSequence(concatBytes(
        encodeDerOid([0x2au8, 0x86u8, 0x48u8, 0xceu8, 0x3du8, 0x02u8, 0x01u8]),
        encodeDerOid([0x2au8, 0x86u8, 0x48u8, 0xceu8, 0x3du8, 0x03u8, 0x01u8, 0x07u8])
    ))
    let bitString = encodeDerBitString(uncompressedPoint)
    return encodeDerSequence(concatBytes(algorithmSequence, bitString))
}

private func encodeDerSequence(content: Array<Byte>): Array<Byte> {
    return concatBytes([0x30], concatBytes(encodeDerLength(content.size), content))
}

private func encodeDerOid(content: Array<Byte>): Array<Byte> {
    return concatBytes([0x06], concatBytes(encodeDerLength(content.size), content))
}

private func encodeDerBitString(content: Array<Byte>): Array<Byte> {
    let prefixed = concatBytes([0x00], content)
    return concatBytes([0x03], concatBytes(encodeDerLength(prefixed.size), prefixed))
}

private func encodeDerLength(length: Int64): Array<Byte> {
    if (length < 128) {
        return [UInt8(length)]
    }
    var remaining = length
    let bytes = ArrayList<Byte>()
    while (remaining > 0) {
        bytes.add(UInt8(remaining % 256))
        remaining /= 256
    }
    let reversed = ArrayList<Byte>()
    reversed.add(UInt8(0x80 + bytes.size))
    var idx = bytes.size - 1
    while (idx >= 0) {
        reversed.add(bytes[idx])
        idx -= 1
    }
    return reversed.toArray()
}

private func readUInt32(bytes: Array<Byte>, start: Int64): Int64 {
    return Int64(bytes[start]) * 16777216 +
        Int64(bytes[start + 1]) * 65536 +
        Int64(bytes[start + 2]) * 256 +
        Int64(bytes[start + 3])
}

private func bytesToHex(bytes: Array<Byte>): String {
    let hexDigits = "0123456789abcdef".toArray()
    let out = ArrayList<Byte>()
    for (b in bytes) {
        let value = Int32(b)
        out.add(hexDigits[Int64((value >> 4) & 15)])
        out.add(hexDigits[Int64(value & 15)])
    }
    return String.fromUtf8(out.toArray())
}

private class CborValue {
    public var intValue: Option<Int64> = None
    public var bytesValue: Option<Array<Byte>> = None
    public var textValue: Option<String> = None
    public var mapValue: Option<HashMap<String, CborValue>> = None
    public var intMapValue: Option<HashMap<Int64, CborValue>> = None

    public init() {}

    public static func fromInt(value: Int64): CborValue {
        let out = CborValue()
        out.intValue = Some(value)
        return out
    }

    public static func fromBytes(value: Array<Byte>): CborValue {
        let out = CborValue()
        out.bytesValue = Some(value)
        return out
    }

    public static func fromText(value: String): CborValue {
        let out = CborValue()
        out.textValue = Some(value)
        return out
    }

    public static func fromStringMap(value: HashMap<String, CborValue>): CborValue {
        let out = CborValue()
        out.mapValue = Some(value)
        return out
    }

    public static func fromIntMap(value: HashMap<Int64, CborValue>): CborValue {
        let out = CborValue()
        out.intMapValue = Some(value)
        return out
    }

    public func asTextOrThrow(code: WebauthnFailureCode, message: String): String {
        match (textValue) {
            case Some(value) => return value
            case None => throw WebauthnException(code, message)
        }
    }

    public func asBytesOrThrow(code: WebauthnFailureCode, message: String): Array<Byte> {
        match (bytesValue) {
            case Some(value) => return value
            case None => throw WebauthnException(code, message)
        }
    }

    public func asIntOrThrow(code: WebauthnFailureCode, message: String): Int64 {
        match (intValue) {
            case Some(value) => return value
            case None => throw WebauthnException(code, message)
        }
    }

    public func asMapOrThrow(code: WebauthnFailureCode, message: String): HashMap<String, CborValue> {
        match (mapValue) {
            case Some(value) => return value
            case None => throw WebauthnException(code, message)
        }
    }

    public func asIntMapOrThrow(code: WebauthnFailureCode, message: String): HashMap<Int64, CborValue> {
        match (intMapValue) {
            case Some(value) => return value
            case None => throw WebauthnException(code, message)
        }
    }
}

private class CborParser {
    private let bytes: Array<Byte>
    private var pos: Int64 = 0

    public init(bytes: Array<Byte>) {
        this.bytes = bytes
    }

    public func readValue(): CborValue {
        if (pos >= bytes.size) {
            throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "unexpected CBOR EOF")
        }
        let initial = bytes[pos]
        pos += 1
        let major = Int64(initial >> 5)
        let additional = Int64(initial & 0x1fu8)

        if (major == 0) {
            return CborValue.fromInt(readLength(additional))
        }
        if (major == 1) {
            return CborValue.fromInt(-1 - readLength(additional))
        }
        if (major == 2) {
            let length = readLength(additional)
            return CborValue.fromBytes(readBytes(length))
        }
        if (major == 3) {
            let length = readLength(additional)
            let data = readBytes(length)
            return CborValue.fromText(String.fromUtf8(data))
        }
        if (major == 5) {
            let length = readLength(additional)
            var allStringKeys = true
            let stringMap = HashMap<String, CborValue>()
            let intMap = HashMap<Int64, CborValue>()
            for (_ in 0..length) {
                let keyValue = readValue()
                let value = readValue()
                match (keyValue.textValue) {
                    case Some(keyText) =>
                        stringMap[keyText] = value
                    case None =>
                        allStringKeys = false
                        let keyInt = keyValue.asIntOrThrow(WebauthnFailureCode.InvalidAttestation, "unsupported CBOR map key")
                        intMap[keyInt] = value
                }
            }
            if (allStringKeys) {
                return CborValue.fromStringMap(stringMap)
            }
            return CborValue.fromIntMap(intMap)
        }
        throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "unsupported CBOR major type")
    }

    private func readLength(additional: Int64): Int64 {
        if (additional < 24) {
            return additional
        }
        if (additional == 24) {
            return Int64(readSingle())
        }
        if (additional == 25) {
            let b1 = Int64(readSingle())
            let b2 = Int64(readSingle())
            return b1 * 256 + b2
        }
        if (additional == 26) {
            let b1 = Int64(readSingle())
            let b2 = Int64(readSingle())
            let b3 = Int64(readSingle())
            let b4 = Int64(readSingle())
            return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
        }
        throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "unsupported CBOR length")
    }

    private func readSingle(): Byte {
        if (pos >= bytes.size) {
            throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "unexpected CBOR EOF")
        }
        let value = bytes[pos]
        pos += 1
        return value
    }

    private func readBytes(length: Int64): Array<Byte> {
        if (pos + length > bytes.size) {
            throw WebauthnException(WebauthnFailureCode.InvalidAttestation, "invalid CBOR bytes length")
        }
        let value = bytes.slice(pos, length).toArray()
        pos += length
        return value
    }
}

private func getIntMapInt(map: HashMap<Int64, CborValue>, key: Int64, code: WebauthnFailureCode, message: String): Int64 {
    match (map.get(key)) {
        case Some(value) => return value.asIntOrThrow(code, message)
        case None => throw WebauthnException(code, message)
    }
}

private func getIntMapBytes(map: HashMap<Int64, CborValue>, key: Int64, code: WebauthnFailureCode, message: String): Array<Byte> {
    match (map.get(key)) {
        case Some(value) => return value.asBytesOrThrow(code, message)
        case None => throw WebauthnException(code, message)
    }
}
