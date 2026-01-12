package lrr4cj.models

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

    public init() {}
}
