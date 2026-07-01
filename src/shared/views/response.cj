package lanlu.shared.views

import ace_web.*
import lanlu.shared.utils.{JsonCodec, JsonRaw}
import stdx.encoding.json.stream.*

/**
 * 响应视图类（ACE Context 版）
 */
public class ResponseView {
    public static func success(ctx: Context, message: String) {
        ctx.contentType = "text/plain; charset=utf-8"
        ctx.body = message
    }

    public static func error(ctx: Context, message: String) {
        ctx.contentType = "text/plain; charset=utf-8"
        ctx.body = message
    }

    public static func json(ctx: Context, data: String) {
        ctx.json(data)
    }

    public static func json<T>(ctx: Context, data: T) where T <: JsonSerializable {
        json(ctx, JsonCodec.encode<T>(data))
    }

    public static func successJson(ctx: Context, data: String) {
        json(ctx, ApiResponse<JsonRaw>(200, "操作成功", Some(JsonRaw(data))))
    }

    public static func successJson(ctx: Context, data: String, message: String) {
        json(ctx, ApiResponse<JsonRaw>(200, message, Some(JsonRaw(data))))
    }

    public static func errorJson(ctx: Context, message: String) {
        json(ctx, ApiResponse<String>(400, message, None))
    }

    public static func errorJson(ctx: Context, message: String, code: Int64) {
        json(ctx, ApiResponse<String>(Int32(code), message, None))
    }
}
