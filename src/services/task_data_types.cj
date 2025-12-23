package lrr4cj.services

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
    public var url_regex: String = ""
    public var login_from: String = ""
    public var icon: String = ""
    public var has_schema: Bool = false

    public init() {}
}

/**
 * 扫描结果数据
 */
public class ScanResultData {
    public var processedCount: Int64
    public var totalFound: Int64
    public var errorCount: Int64
    public var errors: Array<String>
    public var taskId: Int64

    public init(processedCount: Int64, totalFound: Int64, errorCount: Int64, errors: Array<String>, taskId!: Int64 = 0) {
        this.processedCount = processedCount
        this.totalFound = totalFound
        this.errorCount = errorCount
        this.errors = errors
        this.taskId = taskId
    }
}

/**
 * 数据库检查结果数据
 */
public class CheckResultData {
    public var success: Bool
    public var deletedCount: Int64
    public var checkedCount: Int64
    public var error: String

    public init(success: Bool, deletedCount: Int64, checkedCount: Int64, error: String) {
        this.success = success
        this.deletedCount = deletedCount
        this.checkedCount = checkedCount
        this.error = error
    }
}
