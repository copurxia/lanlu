package totp_cj

import std.collection.*
import stdx.crypto.crypto.*
import stdx.crypto.digest.*

public const DEFAULT_STEP_SECONDS: Int64 = 30
public const DEFAULT_DIGITS: Int64 = 6
public const DEFAULT_WINDOW: Int64 = 1
public const DEFAULT_ALGORITHM: String = "SHA1"
public const DEFAULT_SECRET_BYTES: Int64 = 20

public enum TotpFailureCode {
    | InvalidSecret
    | InvalidCode
    | InvalidBase32
    | UnsupportedAlgorithm
}

public class TotpException <: Exception {
    public let code: TotpFailureCode

    public init(code: TotpFailureCode, message: String) {
        super(message)
        this.code = code
    }
}

public class TotpVerificationResult {
    public let valid: Bool
    public let matchedStep: Int64

    public init(valid: Bool, matchedStep!: Int64 = -1) {
        this.valid = valid
        this.matchedStep = matchedStep
    }
}

public func generateSecret(bytesLen!: Int64 = DEFAULT_SECRET_BYTES): String {
    let normalized = if (bytesLen > 0) { bytesLen } else { DEFAULT_SECRET_BYTES }
    let random = SecureRandom()
    return base32Encode(random.nextBytes(Int32(normalized)))
}

public func generateCode(secret: String, unixTimeSeconds: Int64): String {
    return generateCodeCustom(secret, unixTimeSeconds, DEFAULT_STEP_SECONDS, DEFAULT_DIGITS, DEFAULT_ALGORITHM)
}

public func generateCodeCustom(
    secret: String,
    unixTimeSeconds: Int64,
    stepSeconds: Int64,
    digits: Int64,
    algorithm: String
): String {
    let secretBytes = decodeSecret(secret)
    let normalizedStep = normalizeStep(stepSeconds)
    let normalizedDigits = normalizeDigits(digits)
    let counter = if (unixTimeSeconds <= 0) { 0 } else { unixTimeSeconds / normalizedStep }
    let digest = signCounter(secretBytes, counter, algorithm)
    return truncateDigits(digest, normalizedDigits)
}

public func verifyCode(
    secret: String,
    code: String,
    unixTimeSeconds: Int64,
    window!: Int64 = DEFAULT_WINDOW
): Bool {
    return verifyCodeDetailed(secret, code, unixTimeSeconds, window: window).valid
}

public func verifyCodeDetailed(
    secret: String,
    code: String,
    unixTimeSeconds: Int64,
    window!: Int64 = DEFAULT_WINDOW,
    stepSeconds!: Int64 = DEFAULT_STEP_SECONDS,
    digits!: Int64 = DEFAULT_DIGITS,
    algorithm!: String = DEFAULT_ALGORITHM
): TotpVerificationResult {
    let normalizedCode = normalizeCode(code)
    let normalizedWindow = if (window < 0) { 0 } else { window }
    let normalizedStep = normalizeStep(stepSeconds)
    let currentStep = if (unixTimeSeconds <= 0) { 0 } else { unixTimeSeconds / normalizedStep }

    for (offset in (-normalizedWindow)..(normalizedWindow + 1)) {
        let candidateStep = currentStep + offset
        if (candidateStep < 0) {
            continue
        }
        let candidate = generateCodeAtStep(secret, candidateStep, normalizedStep, digits, algorithm)
        if (candidate == normalizedCode) {
            return TotpVerificationResult(true, matchedStep: candidateStep)
        }
    }
    return TotpVerificationResult(false)
}

public func buildOtpAuthUri(
    issuer: String,
    accountName: String,
    secret: String,
    algorithm!: String = DEFAULT_ALGORITHM,
    digits!: Int64 = DEFAULT_DIGITS,
    periodSeconds!: Int64 = DEFAULT_STEP_SECONDS
): String {
    let normalizedIssuer = issuer.trimAscii()
    let normalizedAccount = accountName.trimAscii()
    if (normalizedIssuer.size == 0 || normalizedAccount.size == 0) {
        throw TotpException(TotpFailureCode.InvalidSecret, "issuer and accountName are required")
    }
    let normalizedSecret = normalizeSecret(secret)
    let normalizedAlgorithm = normalizeAlgorithm(algorithm)
    let label = urlEncode("${normalizedIssuer}:${normalizedAccount}")
    let encodedIssuer = urlEncode(normalizedIssuer)
    return "otpauth://totp/${label}?secret=${normalizedSecret}&issuer=${encodedIssuer}&algorithm=${normalizedAlgorithm}&digits=${normalizeDigits(digits)}&period=${normalizeStep(periodSeconds)}"
}

public func base32Encode(input: Array<UInt8>): String {
    if (input.size == 0) {
        return ""
    }
    let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".toRuneArray()
    var out = ""
    var buffer: Int64 = 0
    var bitsLeft: Int64 = 0
    for (byte in input) {
        buffer = (buffer << 8) | Int64(byte)
        bitsLeft += 8
        while (bitsLeft >= 5) {
            let index = (buffer >> (bitsLeft - 5)) & 31
            out += alphabet[index].toString()
            bitsLeft -= 5
        }
    }
    if (bitsLeft > 0) {
        let index = (buffer << (5 - bitsLeft)) & 31
        out += alphabet[index].toString()
    }
    return out
}

public func base32Decode(input: String): Array<UInt8> {
    let normalized = normalizeSecret(input)
    if (normalized.size == 0) {
        throw TotpException(TotpFailureCode.InvalidBase32, "secret cannot be empty")
    }

    let out = ArrayList<UInt8>()
    var buffer: Int64 = 0
    var bitsLeft: Int64 = 0
    for (r in normalized.toRuneArray()) {
        let value = base32Value(r)
        if (value < 0) {
            throw TotpException(TotpFailureCode.InvalidBase32, "invalid base32 character")
        }
        buffer = (buffer << 5) | value
        bitsLeft += 5
        if (bitsLeft >= 8) {
            let byteValue = UInt8((buffer >> (bitsLeft - 8)) & 255)
            out.add(byteValue)
            bitsLeft -= 8
        }
    }
    return out.toArray()
}

private func generateCodeAtStep(
    secret: String,
    step: Int64,
    _: Int64,
    digits: Int64,
    algorithm: String
): String {
    let secretBytes = decodeSecret(secret)
    let digest = signCounter(secretBytes, step, algorithm)
    return truncateDigits(digest, normalizeDigits(digits))
}

private func decodeSecret(secret: String): Array<UInt8> {
    let decoded = base32Decode(secret)
    if (decoded.size == 0) {
        throw TotpException(TotpFailureCode.InvalidSecret, "decoded secret cannot be empty")
    }
    return decoded
}

private func signCounter(secret: Array<UInt8>, counter: Int64, algorithm: String): Array<UInt8> {
    let bytes = counterToBytes(counter)
    let normalized = normalizeAlgorithm(algorithm)
    let hashType = match (normalized) {
        case "SHA1" => HashType.SHA1
        case "SHA256" => HashType.SHA256
        case "SHA512" => HashType.SHA512
        case _ => throw TotpException(TotpFailureCode.UnsupportedAlgorithm, "unsupported algorithm: ${algorithm}")
    }
    let signer = HMAC(secret, hashType)
    signer.write(bytes)
    return signer.finish()
}

private func truncateDigits(digest: Array<UInt8>, digits: Int64): String {
    if (digest.size < 20) {
        throw TotpException(TotpFailureCode.InvalidCode, "digest too short")
    }
    let offset = Int64(digest[digest.size - 1] & 0x0Fu8)
    if (offset + 3 >= digest.size) {
        throw TotpException(TotpFailureCode.InvalidCode, "invalid dynamic truncation offset")
    }
    let binary = (
        (Int64(digest[offset] & 0x7Fu8) << 24) |
        (Int64(digest[offset + 1]) << 16) |
        (Int64(digest[offset + 2]) << 8) |
        Int64(digest[offset + 3])
    )
    let modulus = pow10(digits)
    let otp = binary % modulus
    return leftPad(otp.toString(), digits)
}

private func counterToBytes(counter: Int64): Array<UInt8> {
    let out = Array<UInt8>(8, repeat: 0)
    var value = if (counter < 0) { 0 } else { counter }
    var i = 7
    while (i >= 0) {
        out[i] = UInt8(value & 255)
        value >>= 8
        i -= 1
    }
    return out
}

private func normalizeSecret(input: String): String {
    var out = ""
    for (r in input.toRuneArray()) {
        if (r == r' ' || r == r'\n' || r == r'\r' || r == r'\t' || r == r'-' || r == r'=') {
            continue
        }
        out += r.toString().toAsciiUpper()
    }
    return out.trimAscii()
}

private func normalizeCode(input: String): String {
    var out = ""
    for (r in input.toRuneArray()) {
        if (r >= r'0' && r <= r'9') {
            out += r.toString()
        }
    }
    return out
}

private func normalizeStep(stepSeconds: Int64): Int64 {
    return if (stepSeconds > 0) { stepSeconds } else { DEFAULT_STEP_SECONDS }
}

private func normalizeDigits(digits: Int64): Int64 {
    if (digits < 6) {
        return 6
    }
    if (digits > 10) {
        return 10
    }
    return digits
}

private func normalizeAlgorithm(input: String): String {
    let normalized = input.trimAscii().toAsciiUpper()
    return if (normalized.size > 0) { normalized } else { DEFAULT_ALGORITHM }
}

private func base32Value(r: Rune): Int64 {
    let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    match (alphabet.indexOf(r.toString())) {
        case Some(idx) => return idx
        case None => return -1
    }
}

private func leftPad(value: String, width: Int64): String {
    if (value.size >= width) {
        return value
    }
    var out = ""
    var i = value.size
    while (i < width) {
        out += "0"
        i += 1
    }
    return out + value
}

private func urlEncode(input: String): String {
    let unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"
    var out = ""
    for (byte in input.toArray()) {
        let ch = Rune(byte)
        if (unreserved.contains(ch.toString())) {
            out += ch.toString()
        } else {
            out += "%" + byteToHex(byte)
        }
    }
    return out
}

private func pow10(exp: Int64): Int64 {
    var out: Int64 = 1
    var i: Int64 = 0
    while (i < exp) {
        out *= 10
        i += 1
    }
    return out
}

private func byteToHex(value: UInt8): String {
    let table = "0123456789ABCDEF".toRuneArray()
    let high = table[Int64((value >> 4) & 0x0Fu8)].toString()
    let low = table[Int64(value & 0x0Fu8)].toString()
    return high + low
}
