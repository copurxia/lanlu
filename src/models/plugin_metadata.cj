package lanlu.models

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
    public var login_from: String = ""
    public var icon: String = ""
    public var has_schema: Bool = false
    public var plugin_type: String = ""  // 从元数据获取的插件类型
    // Script plugin cron registration hints (optional).
    public var cron_expression: String = ""
    public var cron_enabled: Bool = false
    public var cron_priority: Int32 = 50
    public var cron_timeout_seconds: Int32 = 3600

    public init() {}
}
