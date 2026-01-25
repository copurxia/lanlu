package lrr4cj.utils

/**
 * Escape a string for embedding into a JSON string literal (without surrounding quotes).
 *
 * Prefer JsonWriter for whole-object/array serialization; use this only when the code
 * still manually concatenates JSON strings.
 */
public func escapeJsonString(s: String): String {
    if (s.size == 0) {
        return ""
    }

    func hexDigit(n: UInt32): Rune {
        // 0..15 -> '0'..'9','a'..'f'
        return if (n < 10u32) {
            Rune(UInt32(r'0') + n)
        } else {
            Rune(UInt32(r'a') + (n - 10u32))
        }
    }

    func hex4(code: UInt32): String {
        var out = ""
        out += hexDigit((code >> 12) & 0xFu32).toString()
        out += hexDigit((code >> 8) & 0xFu32).toString()
        out += hexDigit((code >> 4) & 0xFu32).toString()
        out += hexDigit(code & 0xFu32).toString()
        return out
    }

    var escaped = ""
    for (r in s.toRuneArray()) {
        match (r) {
            case r'"' => escaped += "\\\""
            case r'\\' => escaped += "\\\\"
            case r'\b' => escaped += "\\b"
            case r'\f' => escaped += "\\f"
            case r'\n' => escaped += "\\n"
            case r'\r' => escaped += "\\r"
            case r'\t' => escaped += "\\t"
            case _ =>
                let code = UInt32(r)
                // Escape other ASCII control characters and line separators.
                if (code < 0x20u32 || code == 0x2028u32 || code == 0x2029u32) {
                    escaped += "\\u" + hex4(code)
                } else {
                    escaped += r.toString()
                }
        }
    }

    return escaped
}

/**
 * Backward-compatible alias used across the project (same behavior as escapeJsonString()).
 */
public func escapeJson(s: String): String {
    return escapeJsonString(s)
}

