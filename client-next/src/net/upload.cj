package lanlu_client_next.net

import std.io.ByteBuffer
import std.convert.Parsable
import stdx.encoding.json.stream.*

public let ARCHIVE_UPLOAD_CHUNK_SIZE: Int64 = 10 * 1024 * 1024

public class UploadTaskSnapshot {
    public var id: Int64 = 0
    public var status: String = ""
    public var progress: Int64 = 0
    public var message: String = ""
    public var result: String = ""
}

public class ArchiveUploadResult {
    public var success: Bool = false
    public var fileExists: Bool = false
    public var error: String = ""
    public var taskId: Int64 = 0
}

/** Parsed result for mutation endpoints that return a raw `{success, error, ...}` object. */
public class ApiMutationResult {
    public var success: Bool = false
    public var error: String = ""
    public var value: String = ""
}

public func isSupportedArchiveUpload(path: String): Bool {
    let name = path.toAsciiLower()
    let extensions = [
        ".zip",
        ".rar",
        ".7z",
        ".tar",
        ".gz",
        ".pdf",
        ".epub",
        ".mobi",
        ".cbz",
        ".cbr",
        ".cb7",
        ".cbt"
    ]
    for (extension in extensions) {
        if (name.endsWith(extension)) {
            return true
        }
    }
    if (name.endsWith(".part1.rar") || name.endsWith(".part01.rar") || name.endsWith(".part.1.rar")) {
        return true
    }
    let dot = name.lastIndexOf(".")
    if (dot.isNone()) {
        return false
    }
    let suffix = name[(dot.getOrThrow() + 1)..name.size]
    let runes = suffix.toRuneArray()
    if (runes.size == 3 && runes[0] >= r'0' && runes[0] <= r'9' && runes[1] >= r'0' && runes[1] <= r'9' && runes[2] >=
        r'0' && runes[2] <= r'9') {
        return true
    }
    if (runes.size == 3 && (runes[0] == r'z' || runes[0] == r'r') && runes[1] >= r'0' && runes[1] <= r'9' && runes[2] >=
        r'0' && runes[2] <= r'9') {
        return true
    }
    false
}

public func parseUploadTaskSnapshot(body: String): UploadTaskSnapshot {
    let task = UploadTaskSnapshot()
    if (body.trimAscii().size == 0) {
        return task
    }
    var buffer = ByteBuffer()
    unsafe { buffer.write(body.rawData()) }
    let reader = JsonReader(buffer)
    try {
        reader.startObject()
        while (reader.peek() != EndObject) {
            match (reader.readName()) {
                case "id" => task.id = decodeRaw<Int64>(reader.readValueBytes(), 0)
                case "status" => task.status = decodeRaw<String>(reader.readValueBytes(), "")
                case "progress" => task.progress = decodeRaw<Int64>(reader.readValueBytes(), 0)
                case "message" => task.message = decodeRaw<String>(reader.readValueBytes(), "")
                case "result" => task.result = decodeRaw<String>(reader.readValueBytes(), "")
                case _ => reader.skip()
            }
        }
        reader.endObject()
    } catch (_: Exception) {}
    task
}

public func uploadResultTaskId(raw: String, field: String): Int64 {
    if (raw.trimAscii().size == 0) {
        return 0
    }
    var buffer = ByteBuffer()
    unsafe { buffer.write(raw.rawData()) }
    let reader = JsonReader(buffer)
    try {
        reader.startObject()
        while (reader.peek() != EndObject) {
            if (reader.readName() == field) {
                let value = reader.readValueBytes()
                let number = decodeRaw<Int64>(value, 0)
                if (number > 0) {
                    return number
                }
                let text = decodeRaw<String>(value, "")
                try {
                    return Int64.parse(text)
                } catch (_: Exception) {
                    return 0
                }
            }
            reader.skip()
        }
        reader.endObject()
    } catch (_: Exception) {}
    0
}

// 与 uploadResultTaskId 同形，但提取字符串字段（如入队失败响应里的 error 文本）。
public func uploadResultText(raw: String, field: String): String {
    if (raw.trimAscii().size == 0) {
        return ""
    }
    var buffer = ByteBuffer()
    unsafe { buffer.write(raw.rawData()) }
    let reader = JsonReader(buffer)
    try {
        reader.startObject()
        while (reader.peek() != EndObject) {
            if (reader.readName() == field) {
                return decodeRaw<String>(reader.readValueBytes(), "")
            }
            reader.skip()
        }
        reader.endObject()
    } catch (_: Exception) {}
    ""
}

/**
 * Parses Lanlu mutation responses in either their real raw-object form or an optional
 * `{data: ...}` envelope. `valueField` extracts an operation-specific identifier such
 * as `tankoubon_id` without making the generic result depend on that endpoint.
 */
public func parseApiMutationResult(raw: String, valueField!: String = ""): ApiMutationResult {
    let result = ApiMutationResult()
    let body = unwrapDataRaw(raw)
    if (body.trimAscii().size == 0) {
        result.error = "服务器返回了空响应"
        return result
    }
    var buffer = ByteBuffer()
    unsafe { buffer.write(body.rawData()) }
    let reader = JsonReader(buffer)
    try {
        reader.startObject()
        while (reader.peek() != EndObject) {
            let name = reader.readName()
            match (name) {
                case "success" =>
                    let value = reader.readValueBytes()
                    result.success = decodeRaw<Int64>(value, 0) == 1 || decodeRaw<Bool>(value, false)
                case "error" => result.error = decodeRaw<String>(reader.readValueBytes(), "")
                case _ =>
                    if (valueField.size > 0 && name == valueField) {
                        result.value = decodeRaw<String>(reader.readValueBytes(), "")
                    } else {
                        reader.skip()
                    }
            }
        }
        reader.endObject()
    } catch (e: Exception) {
        result.success = false
        result.error = "无法解析服务器响应：${e.message}"
    }
    if (!result.success && result.error.trimAscii().size == 0) {
        result.error = "服务器拒绝了本次操作"
    }
    result
}
