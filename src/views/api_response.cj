package lanlu.views

import stdx.encoding.json.stream.*

/**
 * Standard API response envelope.
 *
 * Note: keep it minimal and stream-friendly; controllers can embed raw JSON via lrr4cj.utils.JsonRaw.
 */
public class ApiResponse<T> <: JsonSerializable where T <: JsonSerializable {
    public let code: Int32
    public let message: String
    public let data: Option<T>

    public init(code: Int32, message: String, data: Option<T>) {
        this.code = code
        this.message = message
        this.data = data
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("code").writeValue(code)
        w.writeName("message").writeValue(message)
        w.writeName("data").writeValue<Option<T>>(data)
        w.endObject()
    }
}

