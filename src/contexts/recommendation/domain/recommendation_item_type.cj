package lanlu.contexts.recommendation.domain

public enum RecommendationItemType {
    | Archive
    | Tankoubon
    | Unknown(String)

    public static func fromDb(value: String): RecommendationItemType {
        match (value.trimAscii().toAsciiLower()) {
            case "archive" => return Archive
            case "tankoubon" => return Tankoubon
            case _ => return Unknown(value.trimAscii().toAsciiLower())
        }
    }

    public static func isValidDbValue(value: String): Bool {
        return RecommendationItemType.fromDb(value).isKnown()
    }

    public func toDb(): String {
        match (this) {
            case Archive => return "archive"
            case Tankoubon => return "tankoubon"
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
