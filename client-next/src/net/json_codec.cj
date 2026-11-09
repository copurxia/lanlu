package lanlu_client_next.net

import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*

// 全局唯一的 JSON 出入口，与服务端 src/shared/utils/json_codec.cj 同一模式。
public class JsonCodec {
    public static func decode<T>(s: String): T where T <: JsonDeserializable<T> {
        var buf = ByteBuffer()
        unsafe { buf.write(s.rawData()) }
        let r = JsonReader(buf)
        return T.fromJson(r)
    }
}

// 把任意字符串转成带引号的 JSON 字面量（用于拼请求体）。
public func jsonQuote(s: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.writeValue(s)
    w.flush()
    String.fromUtf8(readToEnd(out))
}

// 对 readValueBytes() 取到的原始 JSON 值做容错解码；失败/null 一律回退 fallback。
// 注意 stdx 的 String.fromJson 遇到 JSON null 不抛异常而是返回 "null"，
// 所以 null 必须在解码前显式拦截。
public func decodeRaw<T>(b: Array<UInt8>, fallback: T): T where T <: JsonDeserializable<T> {
    try {
        let s = String.fromUtf8(b)
        if (s == "null") { return fallback }
        JsonCodec.decode<T>(s)
    } catch (_: Exception) {
        fallback
    }
}

// 当字段值本身是对象/数组（data、tags、assets、pages……）时，不能用 decodeRaw<String>
// （那只会接受 JSON 字符串）。用 rawText 取回原始 JSON 文本，再做二次解析。
public func rawText(b: Array<UInt8>): String {
    try {
        String.fromUtf8(b)
    } catch (_: Exception) {
        ""
    }
}
