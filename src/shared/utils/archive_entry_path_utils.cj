package lanlu.shared.utils

import std.collection.ArrayList

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

        // 词法规范化（RFC 3986 §5.2.4 remove_dot_segments）：用栈消除 "." 与 ".." 段。
        // 归档内部条目可能含相对引用（如 EPUB 的 Text/../Images/x.webp），直接拒绝会误伤；
        // 规范化后只要不逃出根（栈为空时遇 ".."）即放行，返回规范化后的路径。
        let stack = ArrayList<String>()
        for (segment in segments) {
            let token = segment.trimAscii()
            if (token.size == 0) {
                return None
            }
            if (token == ".") {
                continue
            }
            if (token == "..") {
                if (stack.isEmpty()) {
                    // 逃出根目录，拒绝。
                    return None
                }
                stack.remove(at: stack.size - 1)
                continue
            }
            stack.add(token)
        }

        if (stack.isEmpty()) {
            return None
        }

        let normalized = String.join(stack.toArray(), delimiter: "/")
        return Some(normalized)
    }

    public static func isSafeRelativeEntryPath(path: String): Bool {
        return normalizeRelativeEntryPath(path).isSome()
    }
}
