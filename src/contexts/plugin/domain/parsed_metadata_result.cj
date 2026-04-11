package lanlu.contexts.plugin.domain

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
    public var cover: String = ""
    public var backdrop: String = ""
    public var clearlogo: String = ""
    public var releaseAt: String = ""
    public var createdAt: String = ""
    public var updatedAt: String = ""
    public var titleProvided: Bool = false
    public var summaryProvided: Bool = false
    public var tagsProvided: Bool = false
    public var coverProvided: Bool = false
    public var backdropProvided: Bool = false
    public var clearlogoProvided: Bool = false
    public var releaseAtProvided: Bool = false
    public var createdAtProvided: Bool = false
    public var updatedAtProvided: Bool = false
    public var archives: Array<ArchiveMetadataPatch> = Array<ArchiveMetadataPatch>()
    public var archivesProvided: Bool = false
    public var pages: Array<PageMetadataPatch> = Array<PageMetadataPatch>()

    public init() {}

    public init(success: Bool, error: String, title: String, summary: String, tags: String) {
        this.success = success
        this.error = error
        this.title = title
        this.summary = summary
        this.tags = tags
        this.cover = ""
        this.backdrop = ""
        this.clearlogo = ""
        this.releaseAt = ""
        this.createdAt = ""
        this.updatedAt = ""
        this.titleProvided = false
        this.summaryProvided = false
        this.tagsProvided = false
        this.coverProvided = false
        this.backdropProvided = false
        this.clearlogoProvided = false
        this.releaseAtProvided = false
        this.createdAtProvided = false
        this.updatedAtProvided = false
        this.archives = Array<ArchiveMetadataPatch>()
        this.archivesProvided = false
        this.pages = Array<PageMetadataPatch>()
    }

    public init(success: Bool, error: String, title: String, summary: String, tags: String, cover: String, archives: Array<ArchiveMetadataPatch>) {
        this.success = success
        this.error = error
        this.title = title
        this.summary = summary
        this.tags = tags
        this.cover = cover
        this.backdrop = ""
        this.clearlogo = ""
        this.releaseAt = ""
        this.createdAt = ""
        this.updatedAt = ""
        this.titleProvided = false
        this.summaryProvided = false
        this.tagsProvided = false
        this.coverProvided = false
        this.backdropProvided = false
        this.clearlogoProvided = false
        this.releaseAtProvided = false
        this.createdAtProvided = false
        this.updatedAtProvided = false
        this.archives = archives
        this.archivesProvided = false
        this.pages = Array<PageMetadataPatch>()
    }

    public init(success: Bool, error: String, title: String, summary: String, tags: String, cover: String, archives: Array<ArchiveMetadataPatch>, archivesProvided: Bool) {
        this.success = success
        this.error = error
        this.title = title
        this.summary = summary
        this.tags = tags
        this.cover = cover
        this.backdrop = ""
        this.clearlogo = ""
        this.releaseAt = ""
        this.createdAt = ""
        this.updatedAt = ""
        this.titleProvided = false
        this.summaryProvided = false
        this.tagsProvided = false
        this.coverProvided = false
        this.backdropProvided = false
        this.clearlogoProvided = false
        this.releaseAtProvided = false
        this.createdAtProvided = false
        this.updatedAtProvided = false
        this.archives = archives
        this.archivesProvided = archivesProvided
        this.pages = Array<PageMetadataPatch>()
    }

    public init(success: Bool, error: String, title: String, summary: String, tags: String, cover: String, archives: Array<ArchiveMetadataPatch>, archivesProvided: Bool, pages: Array<PageMetadataPatch>) {
        this.success = success
        this.error = error
        this.title = title
        this.summary = summary
        this.tags = tags
        this.cover = cover
        this.backdrop = ""
        this.clearlogo = ""
        this.releaseAt = ""
        this.createdAt = ""
        this.updatedAt = ""
        this.titleProvided = false
        this.summaryProvided = false
        this.tagsProvided = false
        this.coverProvided = false
        this.backdropProvided = false
        this.clearlogoProvided = false
        this.releaseAtProvided = false
        this.createdAtProvided = false
        this.updatedAtProvided = false
        this.archives = archives
        this.archivesProvided = archivesProvided
        this.pages = pages
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
    public var releaseAt: String = ""
    public var createdAt: String = ""
    public var updatedAt: String = ""
    public var cover: String = ""
    public var backdrop: String = ""
    public var clearlogo: String = ""
    public var titleProvided: Bool = false
    public var summaryProvided: Bool = false
    public var tagsProvided: Bool = false
    public var releaseAtProvided: Bool = false
    public var createdAtProvided: Bool = false
    public var updatedAtProvided: Bool = false
    public var coverProvided: Bool = false
    public var backdropProvided: Bool = false
    public var clearlogoProvided: Bool = false
    public var pages: Array<PageMetadataPatch> = Array<PageMetadataPatch>()

    public init() {}
}

/**
 * 插件返回的页面元数据补丁
 */
public class PageMetadataPatch {
    public var page: Int32 = 0
    public var path: String = ""
    public var title: String = ""
    public var description: String = ""
    public var thumb: String = ""
    public var releaseAt: String = ""
    public var createdAt: String = ""
    public var updatedAt: String = ""
    public var sort: Int32 = 0
    public var releaseAtProvided: Bool = false
    public var createdAtProvided: Bool = false
    public var updatedAtProvided: Bool = false
    public var sortProvided: Bool = false
    public var hiddenInFiles: Bool = false
    public var hiddenInFilesProvided: Bool = false
    public var attachments: Array<PageAttachmentPatch> = Array<PageAttachmentPatch>()
    public var attachmentsProvided: Bool = false

    public init() {}
}

public class PageAttachmentPatch {
    public var slot: String = ""
    public var assetId: Int64 = 0
    public var path: String = ""
    public var name: String = ""
    public var mimeType: String = ""
    public var kind: String = ""
    public var language: String = ""
    public var orderIndex: Int32 = 0

    public init() {}
}
