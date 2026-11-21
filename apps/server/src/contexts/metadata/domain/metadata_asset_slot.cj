package lanlu.contexts.metadata.domain

import csorm.*

/**
 * 元数据资产槽位枚举（对标 metadata_assets.slot 列）。
 * cover=封面, backdrop=背景图, clearlogo=透明 Logo, thumb=缩略图。
 * 实现 csorm.ActiveEnum 接口，DB 侧仍走 VARCHAR 文本协议。
 */
public enum MetadataAssetSlot <: ActiveEnum {
    | Cover
    | Backdrop
    | Clearlogo
    | Thumb
    | Other(String)

    public static func fromDb(value: String): MetadataAssetSlot {
        match (value.trimAscii().toAsciiLower()) {
            case "cover" => return Cover
            case "backdrop" => return Backdrop
            case "clearlogo" => return Clearlogo
            case "thumb" => return Thumb
            case _ => return Other(value.trimAscii().toAsciiLower())
        }
    }

    public func toDb(): String {
        match (this) {
            case Cover => return "cover"
            case Backdrop => return "backdrop"
            case Clearlogo => return "clearlogo"
            case Thumb => return "thumb"
            case Other(value) => return value
        }
    }

    public func isKnown(): Bool {
        match (this) {
            case Other(_) => return false
            case _ => return true
        }
    }

    // ===== ActiveEnum 接口实现 =====

    public func enumName(): String { "asset_slot" }

    public func toValue(): String { this.toDb() }

    public func fromValue(raw: String): Bool { this.toDb() == raw }
}