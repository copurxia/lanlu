package lanlu.views

import cjoy.*
import lanlu.utils.{JsonCodec, JsonRaw}
import stdx.encoding.json.stream.*

/**
 * 响应视图类
 */
public class ResponseView {
    /**
     * 返回成功响应
     */
    public static func success(ctx: JoyContext, message: String) {
        ctx.string(message)
    }

    /**
     * 返回错误响应
     */
    public static func error(ctx: JoyContext, message: String) {
        ctx.string(message)
    }

    /**
     * 返回 JSON 响应
     */
    public static func json(ctx: JoyContext, data: String) {
        ctx.header("Content-Type", "application/json").string(data)
    }

    /**
     * 返回 JsonSerializable 对象为 JSON 响应（项目统一入口）。
     */
    public static func json<T>(ctx: JoyContext, data: T) where T <: JsonSerializable {
        json(ctx, JsonCodec.encode<T>(data))
    }

    /**
     * 返回 JSON 格式的成功响应
     */
    public static func successJson(ctx: JoyContext, data: String) {
        // data is treated as a raw JSON value.
        json(ctx, ApiResponse<JsonRaw>(200, "操作成功", Some(JsonRaw(data))))
    }

    public static func successJson(ctx: JoyContext, data: String, message: String) {
        // message is encoded as JSON string by JsonWriter; no manual escaping needed.
        // data is treated as a raw JSON value.
        json(ctx, ApiResponse<JsonRaw>(200, message, Some(JsonRaw(data))))
    }

    /**
     * 返回 JSON 格式的错误响应
     */
    public static func errorJson(ctx: JoyContext, message: String) {
        json(ctx, ApiResponse<String>(400, message, None))
    }

    public static func errorJson(ctx: JoyContext, message: String, code: Int64) {
        // ApiResponse uses Int32 code; keep compatibility by truncating to Int32 range.
        json(ctx, ApiResponse<String>(Int32(code), message, None))
    }
}
