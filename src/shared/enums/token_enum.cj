package lanlu.shared.enums

import csorm.*

/**
 * 用户令牌类型枚举（对标 user_tokens.token_type 列）。
 * session=登录设备令牌, api=手动创建的 API token。
 */
public enum TokenType <: ActiveEnum {
    | Session
    | Api

    public func enumName(): String { "token_type" }

    public func toValue(): String {
        match (this) {
            case Session => "session"
            case Api => "api"
        }
    }

    public func fromValue(raw: String): Bool {
        this.toValue() == raw
    }

    /** 从 DB 原始字符串解析为枚举，非法值回退 Session（与原 DAO 逻辑一致）。 */
    public static func parse(raw: String): TokenType {
        match (raw) {
            case "session" => Session
            case "api" => Api
            case _ => Session
        }
    }
}