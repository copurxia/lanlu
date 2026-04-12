package lanlu.shared.utils

public class ArchiveEntryPathUtils {
    private static func isAsciiAlphaByte(ch: UInt8): Bool {
        return (ch >= 97u8 && ch <= 122u8) || (ch >= 65u8 && ch <= 90u8)
    }

    public static func normalizeRelativeEntryPath(path: String): Option<String> {
        let trimmed = path.trimAscii()
        if (trimmed.size == 0) {
            return None
        }

        if (trimmed.contains("\\")) {
            return None
        }
        if (trimmed.startsWith("/")) {
            return None
        }
        if (trimmed.startsWith("//")) {
            return None
        }

        let bytes = trimmed.toArray()
        if (bytes.size >= 2 && isAsciiAlphaByte(bytes[0]) && bytes[1] == 58u8) {
            return None
        }

        if (trimmed.contains("//")) {
            return None
        }

        let segments = trimmed.split("/")
        if (segments.size == 0) {
            return None
        }

        for (segment in segments) {
            let token = segment.trimAscii()
            if (token.size == 0) {
                return None
            }
            if (token == "." || token == "..") {
                return None
            }
        }

        return Some(trimmed)
    }

    public static func isSafeRelativeEntryPath(path: String): Bool {
        return normalizeRelativeEntryPath(path).isSome()
    }
}
