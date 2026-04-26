package lanlu.contexts.metadata.domain

public enum MetadataEntityType {
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
}
