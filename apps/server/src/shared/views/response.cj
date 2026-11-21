package lanlu.shared.views

import ignite.*
import lanlu.shared.utils.{JsonCodec, JsonRaw}
import stdx.encoding.json.stream.*

/**
 * 响应视图类
 */
public class ResponseView {
    /**
     * 返回成功响应
     */
    public static func success(ctx: Ctx, message: String) {
        ctx.sendString(message)
    }

    /**
     * 返回错误响应
     */
    public static func error(ctx: Ctx, message: String) {
        ctx.sendString(message)
    }

    /**
     * 返回 JSON 响应
     */
    public static func json(ctx: Ctx, data: String) {
        ctx.json(data)
    }

    /**
     * 返回 JsonSerializable 对象为 JSON 响应（项目统一入口）。
     */
    public static func json<T>(ctx: Ctx, data: T) where T <: JsonSerializable {
        json(ctx, JsonCodec.encode<T>(data))
    }

    /**
     * 返回 JSON 格式的成功响应
     */
    public static func successJson(ctx: Ctx, data: String) {
        // data is treated as a raw JSON value.
        json(ctx, ApiResponse<JsonRaw>(200, "操作成功", Some(JsonRaw(data))))
    }

    public static func successJson(ctx: Ctx, data: String, message: String) {
        // message is encoded as JSON string by JsonWriter; no manual escaping needed.
        // data is treated as a raw JSON value.
        json(ctx, ApiResponse<JsonRaw>(200, message, Some(JsonRaw(data))))
    }

    /**
     * 返回 JSON 格式的错误响应
     */
    public static func errorJson(ctx: Ctx, message: String) {
        json(ctx, ApiResponse<String>(400, message, None))
    }

    public static func errorJson(ctx: Ctx, message: String, code: Int64) {
        // ApiResponse uses Int32 code; keep compatibility by truncating to Int32 range.
        json(ctx, ApiResponse<String>(Int32(code), message, None))
    }
}
