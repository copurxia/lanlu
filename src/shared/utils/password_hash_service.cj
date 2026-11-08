package lanlu.shared.utils

import argon2_ffi.*
import stdx.log.*

public class PasswordHashRecord {
    public var version: String = ""
    public var salt: String = ""
    public var hash: String = ""

    public init() {}

    public init(version: String, salt: String, hash: String) {
        this.version = version
        this.salt = salt
        this.hash = hash
    }
}

public class PasswordVerificationResult {
    public var valid: Bool = false
    public var needsUpgrade: Bool = false

    public init() {}

    public init(valid: Bool, needsUpgrade: Bool) {
        this.valid = valid
        this.needsUpgrade = needsUpgrade
    }
}

public class PasswordHashService {
    private static let logger = getLogger("password_hash_service")
    private static let argon2idVersion = "argon2id_v1"
    private static let sha256Version = "sha256_v1"
    private static let argon2TimeCost: UInt32 = 3
    private static let argon2MemoryCostKiB: UInt32 = 65536
    private static let argon2Parallelism: UInt32 = 1
    private static let argon2HashLen: UIntNative = 32
    private static let argon2EncodedBufferLen: Int64 = 512

    public static func currentVersion(): String {
        return argon2idVersion
    }

    public static func legacyVersion(): String {
        return sha256Version
    }

    public static func hashPassword(password: String, pepper: String): Option<PasswordHashRecord> {
        let salt = AuthUtils.generateTokenHex(bytesLen: 16)
        match (hashArgon2id(password, pepper, salt)) {
            case Some(hash) => return Some(PasswordHashRecord(argon2idVersion, salt, hash))
            case None => return None
        }
    }

    public static func verifyPassword(version: String, salt: String, hash: String, password: String, pepper: String): PasswordVerificationResult {
        let normalizedVersion = normalizeVersion(version, hash)
        if (normalizedVersion == argon2idVersion) {
            return PasswordVerificationResult(verifyArgon2id(hash, password, pepper), false)
        }

        let computed = AuthUtils.sha256Hex("${salt}:${password}:${pepper}")
        if (computed == hash) {
            return PasswordVerificationResult(true, true)
        }
        return PasswordVerificationResult(false, false)
    }

    private static func normalizeVersion(version: String, hash: String): String {
        let trimmed = version.trimAscii().toAsciiLower()
        if (trimmed.size > 0) {
            return trimmed
        }
        if (hash.trimAscii().startsWith("$argon2id$")) {
            return argon2idVersion
        }
        return sha256Version
    }

    private static func hashArgon2id(password: String, pepper: String, salt: String): Option<String> {
        let secret = normalizeSecret(password, pepper)
        let passwordBytes = secret.toArray()
        let saltBytes = salt.toArray()
        let encodedBytes = Array<UInt8>(argon2EncodedBufferLen, { _ => 0u8 })
        let passwordHandle = unsafe { acquireArrayRawData(passwordBytes) }
        let saltHandle = unsafe { acquireArrayRawData(saltBytes) }
        let encodedHandle = unsafe { acquireArrayRawData(encodedBytes) }
        try {
            let rc = unsafe {
                Argon2.hashEncoded(
                    argon2TimeCost,
                    argon2MemoryCostKiB,
                    argon2Parallelism,
                    CString(passwordHandle.pointer),
                    UIntNative(passwordBytes.size),
                    CString(saltHandle.pointer),
                    UIntNative(saltBytes.size),
                    argon2HashLen,
                    CString(encodedHandle.pointer),
                    UIntNative(encodedBytes.size)
                )
            }
            if (rc != ARGON2_OK) {
                logger.error("argon2id hash failed", ("code", rc.toString()), ("message", Argon2.errorMessage(rc)))
                return None
            }
            return Some(unsafe { CString(encodedHandle.pointer).toString() })
        } finally {
            unsafe { releaseArrayRawData(encodedHandle) }
            unsafe { releaseArrayRawData(saltHandle) }
            unsafe { releaseArrayRawData(passwordHandle) }
        }
    }

    private static func verifyArgon2id(encodedHash: String, password: String, pepper: String): Bool {
        let normalizedHash = encodedHash.trimAscii()
        if (normalizedHash.size == 0) {
            return false
        }

        let secret = normalizeSecret(password, pepper)
        let passwordBytes = secret.toArray()
        let passwordHandle = unsafe { acquireArrayRawData(passwordBytes) }
        let hashCString = unsafe { LibC.mallocCString(normalizedHash) }
        try {
            let rc = Argon2.verifyEncoded(
                hashCString,
                CString(passwordHandle.pointer),
                UIntNative(passwordBytes.size)
            )
            return rc == ARGON2_OK
        } finally {
            unsafe { LibC.free(hashCString) }
            unsafe { releaseArrayRawData(passwordHandle) }
        }
    }

    private static func normalizeSecret(password: String, pepper: String): String {
        if (pepper.trimAscii().size == 0) {
            return password
        }
        return "${password}:${pepper}"
    }
}
