package lanlu.contexts.user.application

import ignite.security.*
import std.collection.*
import stdx.crypto.digest.*
import stdx.encoding.hex.*
import lanlu.shared.config.*
import lanlu.shared.utils.*

public class TotpConstants {
    public static let loginChallengeNamespace = "totp:login"
    public static let enrollmentNamespace = "totp:enroll"
    public static let challengeTtlSeconds: Int64 = 300
    public static let defaultDigits: Int64 = 6
    public static let defaultPeriodSeconds: Int64 = 30
    public static let defaultWindow: Int64 = 1
    public static let defaultIssuer: String = "Lanlu"
    public static let recoveryCodeCount: Int64 = 10
}

public class TotpUtils {
    public static func isConfigured(): Bool {
        return AuthConfig.totpSecretKey.trimAscii().size >= 16
    }

    public static func secretEncryptionConfig(): SecurityConfig {
        let keyMaterial = deriveKeyMaterial(AuthConfig.totpSecretKey)
        let keyRing = HashMap<String, Array<UInt8>>()
        keyRing["k1"] = keyMaterial
        return SecurityConfig(
            providerKind: SecurityProviderKind.StdxFallback,
            activeKid: "k1",
            keyRing: keyRing,
            aeadAlgorithm: "AES-256-GCM"
        )
    }

    public static func encryptSecret(secret: String, userId: Int64): String {
        ensureConfigured()
        return encryptEnvelopeV1Text(secretEncryptionConfig(), secret, aadText: "totp-secret:${userId}")
    }

    public static func decryptSecret(encryptedSecret: String, userId: Int64): String {
        ensureConfigured()
        return decryptEnvelopeV1ToText(secretEncryptionConfig(), encryptedSecret, aadText: "totp-secret:${userId}")
    }

    public static func hashSecret(secret: String): String {
        var sha = SHA256()
        sha.write("${normalizeText(secret)}:${AuthConfig.totpSecretKey}".toArray())
        return toHexString(sha.finish())
    }

    public static func hashRecoveryCode(code: String): String {
        var sha = SHA256()
        sha.write("${normalizeText(code)}:${AuthConfig.tokenPepper}:${AuthConfig.totpSecretKey}".toArray())
        return toHexString(sha.finish())
    }

    public static func normalizeCode(code: String): String {
        var out = ""
        for (r in code.toRuneArray()) {
            if (r >= r'0' && r <= r'9') {
                out += r.toString()
            }
        }
        return out
    }

    public static func normalizeRecoveryCode(code: String): String {
        var out = ""
        for (r in code.toRuneArray()) {
            if ((r >= r'0' && r <= r'9') || (r >= r'a' && r <= r'z') || (r >= r'A' && r <= r'Z')) {
                out += r.toString().toAsciiUpper()
            }
        }
        return out
    }

    public static func generateRecoveryCodes(count!: Int64 = TotpConstants.recoveryCodeCount): Array<String> {
        let normalizedCount = if (count > 0) { count } else { TotpConstants.recoveryCodeCount }
        return Array<String>(normalizedCount, { _ =>
            let raw = AuthUtils.generateTokenHex(bytesLen: 5).toAsciiUpper()
            "${raw[0..4]}-${raw[4..8]}-${raw[8..10]}"
        })
    }

    public static func safeIssuer(): String {
        return TotpConstants.defaultIssuer
    }

    private static func deriveKeyMaterial(secretKey: String): Array<UInt8> {
        var sha = SHA256()
        sha.write(secretKey.trimAscii().toArray())
        return sha.finish()
    }

    private static func normalizeText(input: String): String {
        return input.trimAscii().toAsciiUpper()
    }

    private static func ensureConfigured(): Unit {
        if (!isConfigured()) {
            throw Exception("TOTP requires JWT_SECRET or AUTH_TOTP_SECRET_KEY")
        }
    }
}
