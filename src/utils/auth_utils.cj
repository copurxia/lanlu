package lrr4cj.utils

import std.crypto.digest.*
import stdx.crypto.digest.*
import stdx.crypto.crypto.*
import stdx.encoding.hex.*
import stdx.encoding.base64.*
import std.convert.*

public class AuthUtils {
    public static func sha256Hex(input: String): String {
        var sha = SHA256()
        sha.write(input.toArray())
        let out = sha.finish()
        return toHexString(out)
    }

    public static func generateTokenHex(bytesLen!: Int32 = 32): String {
        // 32 bytes => 64 hex chars
        let r = SecureRandom()
        let bytes: Array<Byte> = r.nextBytes(bytesLen)
        return toHexString(bytes)
    }

    public static func tryDecodeBase64ToUtf8(input: String): Option<String> {
        let trimmed = input.trimAscii()
        if (trimmed.size == 0) {
            return None
        }
        match (fromBase64String(trimmed)) {
            case Some(bytes) =>
                try {
                    return Some(String.fromUtf8(bytes))
                } catch (_: Exception) {
                    return None
                }
            case None => return None
        }
    }
}
