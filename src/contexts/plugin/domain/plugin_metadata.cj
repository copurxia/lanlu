package lanlu.contexts.plugin.domain

public enum PluginType {
    | Script
    | Metadata
    | Download
    | Unknown(String)

    public static func fromDb(value: String): PluginType {
        match (value.trimAscii().toAsciiLower()) {
            case "script" => return Script
            case "metadata" => return Metadata
            case "download" => return Download
            case _ => return Unknown(value.trimAscii())
        }
    }

    public static func isValidDbValue(value: String): Bool {
        return PluginType.fromDb(value).isKnown()
    }

    public func toDb(): String {
        match (this) {
            case Script => return "Script"
            case Metadata => return "Metadata"
            case Download => return "Download"
            case Unknown(value) => return value
        }
    }

    public func isKnown(): Bool {
        match (this) {
            case Unknown(_) => return false
            case _ => return true
        }
    }

    public func requiresRuntime(): Bool {
        match (this) {
            case Script => return true
            case Metadata => return true
            case Download => return true
            case Unknown(_) => return false
        }
    }
}

/**
 * 插件元数据
 */
public class PluginMetadata {
    public var name: String = ""
    public var namespace: String = ""
    public var version: String = ""
    public var description: String = ""
    public var author: String = ""
    public var tags: String = ""
    public var permissions: String = ""
    public var parameters: String = "[]"
    public var update_url: String = ""
    public var url_regex: String = ""
    public var pre_hooks: String = "[]"
    public var after_hooks: String = "[]"
    public var icon: String = ""
    public var has_schema: Bool = false
    public var plugin_type: String = ""  // 从元数据获取的插件类型
    public var metadata_error: String = ""
    // Script plugin cron registration hints (optional).
    public var cron_expression: String = ""
    public var cron_enabled: Bool = false
    public var cron_priority: Int32 = 50
    public var cron_timeout_seconds: Int32 = 3600

    public mut prop pluginType: PluginType {
        get() {
            PluginType.fromDb(plugin_type)
        }
        set(value) {
            plugin_type = value.toDb()
        }
    }

    public init() {}
}
