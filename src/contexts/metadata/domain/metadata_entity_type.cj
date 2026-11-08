package lanlu.contexts.metadata.domain

import csorm.*

/**
 * 元数据实体类型枚举。
 * 实现 csorm.ActiveEnum 接口，可用 activeEnumToValue() 转为 Value.VEnum，
 * DB 侧仍走 VARCHAR 文本协议。
 */
public enum MetadataEntityType <: ActiveEnum {
    | Archive
    | Tankoubon
    | Page
    | Tag
    | Unknown(String)

    public static func fromDb(value: String): MetadataEntityType {
        match (value.trimAscii().toAsciiLower()) {
            case "archive" => return Archive
            case "tankoubon" => return Tankoubon
            case "page" => return Page
            case "tag" => return Tag
            case _ => return Unknown(value.trimAscii().toAsciiLower())
        }
    }

    public static func isValidDbValue(value: String): Bool {
        return MetadataEntityType.fromDb(value).isKnown()
    }

    public func toDb(): String {
        match (this) {
            case Archive => return "archive"
            case Tankoubon => return "tankoubon"
            case Page => return "page"
            case Tag => return "tag"
            case Unknown(value) => return value
        }
    }

    public func isKnown(): Bool {
        match (this) {
            case Unknown(_) => return false
            case _ => return true
        }
    }

    // ===== ActiveEnum 接口实现（csorm 阶段五落地） =====

    public func enumName(): String { "entity_type" }

    public func toValue(): String { this.toDb() }

    public func fromValue(raw: String): Bool { this.toDb() == raw }
}
