package cli

import stdx.encoding.json.*
import stdx.encoding.hex.*
import std.collection.HashMap
import std.core.StringBuilder

/**
 * 从 JsonObject 中安全读取字符串字段
 */
public func getString(obj: JsonObject, key: String): ?String {
    match (obj.get(key)) {
        case Some(v) =>
            match (v.kind()) {
                case JsString => return Some(v.asString().getValue())
                case _ => ()
            }
        case None => ()
    }
    return None
}

/**
 * 从 JsonObject 中安全读取整数字段
 */
public func getInt(obj: JsonObject, key: String): ?Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            match (v.kind()) {
                case JsInt => return Some(v.asInt().getValue())
                case _ => ()
            }
        case None => ()
    }
    return None
}

/**
 * 从 JsonObject 中安全读取布尔字段
 */
public func getBool(obj: JsonObject, key: String): ?Bool {
    match (obj.get(key)) {
        case Some(v) =>
            match (v.kind()) {
                case JsBool => return Some(v.asBool().getValue())
                case _ => ()
            }
        case None => ()
    }
    return None
}

/**
 * 从 JsonObject 中安全读取子对象
 */
public func getObject(obj: JsonObject, key: String): ?JsonObject {
    match (obj.get(key)) {
        case Some(v) =>
            match (v.kind()) {
                case JsObject => return Some(v.asObject())
                case _ => ()
            }
        case None => ()
    }
    return None
}

/**
 * 从 JsonObject 中安全读取数组
 */
public func getArray(obj: JsonObject, key: String): ?JsonArray {
    match (obj.get(key)) {
        case Some(v) =>
            match (v.kind()) {
                case JsArray => return Some(v.asArray())
                case _ => ()
            }
        case None => ()
    }
    return None
}

/**
 * 读取必需字符串字段，不存在则抛出异常
 */
public func requireString(obj: JsonObject, key: String): String {
    match (getString(obj, key)) {
        case Some(v) => return v
        case None => throw IllegalArgumentException("missing field: ${key}")
    }
}

/**
 * URL 百分号编码（UTF-8）
 */
public func urlEncode(value: String): String {
    let bytes = value.toArray()
    let sb = StringBuilder()
    for (b in bytes) {
        let c = Int64(b)
        let isUnreserved = (c >= 65 && c <= 90) ||
                           (c >= 97 && c <= 122) ||
                           (c >= 48 && c <= 57) ||
                           c == 45 || c == 46 || c == 95 || c == 126
        if (isUnreserved) {
            sb.append(String.fromUtf8(Array<UInt8>(1, repeat: b)))
        } else {
            sb.append("%")
            sb.append(toHexString(Array<UInt8>(1, repeat: b)))
        }
    }
    return sb.toString()
}

/**
 * 将键值对构建为 URL 查询字符串
 */
public func buildQuery(params: HashMap<String, String>): String {
    let sb = StringBuilder()
    var first = true
    for ((k, v) in params) {
        if (v.size == 0) {
            continue
        }
        if (!first) {
            sb.append("&")
        }
        sb.append(urlEncode(k))
        sb.append("=")
        sb.append(urlEncode(v))
        first = false
    }
    return sb.toString()
}

/**
 * 解析 JSON 字符串为 JsonValue，失败时抛出异常并携带上下文
 */
public func parseJson(body: String, context: String): JsonValue {
    try {
        return JsonValue.fromStr(body)
    } catch (e: Exception) {
        throw IllegalArgumentException("failed to parse ${context}: ${e.message}")
    }
}
