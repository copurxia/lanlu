package lrr4cj.utils

import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*

/**
 * Project-wide JSON codec based on stdx.encoding.json.stream.
 *
 * Goals:
 * - One place to convert between String and JsonReader/JsonWriter.
 * - Avoid ad-hoc escaping and manual string concatenation.
 */
public class JsonCodec {
    public static func decode<T>(s: String): T where T <: JsonDeserializable<T> {
        var buf = ByteBuffer()
        unsafe { buf.write(s.rawData()) }
        let r = JsonReader(buf)
        return T.fromJson(r)
    }

    public static func encode<T>(v: T): String where T <: JsonSerializable {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.writeValue(v)
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }
}

/**
 * Wrap a pre-serialized JSON value (object/array/string/number/bool/null).
 *
 * This is useful for places where the project stores "JSON inside String"
 * and we want to embed it as raw JSON without double-encoding.
 */
public class JsonRaw <: JsonSerializable {
    public let raw: String

    public init(raw: String) {
        this.raw = raw
    }

    public func toJson(w: JsonWriter): Unit {
        // jsonValue() does not escape and does not add quotes; raw must be a valid JSON value.
        w.jsonValue(raw)
    }
}

