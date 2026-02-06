package lanlu.models

/**
 * 元数据解析结果
 * 用于 metadata_plugin 和 metadata_plugin_callback 任务
 */
public class ParsedMetadataResult {
    public var success: Bool = false
    public var error: String = ""
    public var title: String = ""
    public var summary: String = ""
    public var tags: String = ""
    public var archives: Array<ArchiveMetadataPatch> = Array<ArchiveMetadataPatch>()

    public init(success: Bool, error: String, title: String, summary: String, tags: String) {
        this.success = success
        this.error = error
        this.title = title
        this.summary = summary
        this.tags = tags
        this.archives = Array<ArchiveMetadataPatch>()
    }

    public init(success: Bool, error: String, title: String, summary: String, tags: String, archives: Array<ArchiveMetadataPatch>) {
        this.success = success
        this.error = error
        this.title = title
        this.summary = summary
        this.tags = tags
        this.archives = archives
    }
}

/**
 * 插件返回的子归档补丁（用于合集元数据批量写回）
 */
public class ArchiveMetadataPatch {
    public var archiveId: String = ""
    public var volumeNo: Int32 = 0
    public var title: String = ""
    public var summary: String = ""
    public var tags: String = ""
    public var updatedAt: String = ""

    public init() {}
}
