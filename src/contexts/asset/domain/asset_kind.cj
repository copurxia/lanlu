package lanlu.contexts.asset.domain

public enum AssetKind {
    | Cover
    | Icon
    | Avatar
    | Backdrop
    | ClearLogo
    | Attachment
    | Unknown(String)

    public static func fromDb(value: String): AssetKind {
        match (value.trimAscii().toAsciiLower()) {
            case "cover" => return Cover
            case "icon" => return Icon
            case "avatar" => return Avatar
            case "backdrop" => return Backdrop
            case "clearlogo" => return ClearLogo
            case "attachment" => return Attachment
            case _ => return Unknown(value.trimAscii().toAsciiLower())
        }
    }

    public static func isValidDbValue(value: String): Bool {
        return AssetKind.fromDb(value).isKnown()
    }

    public func toDb(): String {
        match (this) {
            case Cover => return "cover"
            case Icon => return "icon"
            case Avatar => return "avatar"
            case Backdrop => return "backdrop"
            case ClearLogo => return "clearlogo"
            case Attachment => return "attachment"
            case Unknown(value) => return value
        }
    }

    public func isKnown(): Bool {
        match (this) {
            case Unknown(_) => return false
            case _ => return true
        }
    }
}
