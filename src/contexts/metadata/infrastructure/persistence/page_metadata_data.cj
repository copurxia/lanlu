package lanlu.contexts.metadata.infrastructure.persistence

/**
 * Unified page metadata DTO.
 */
public class PageMetadataData {
    public var id: Int64 = 0
    public var archive_id: Int64 = 0
    public var page_number: Int32 = 0
    public var entry_path: String = ""
    public var title: String = ""
    public var description: String = ""
    public var sort_index: Int32 = 0
    public var hidden_in_files: Bool = false
    public var thumb_asset_id: Int64 = 0
    public var thumbhash: String = ""
    public var extra_data: String = "{}"
    public var release_at: String = ""
    public var created_at: String = ""
    public var updated_at: String = ""
    public var attachments: Array<PageAttachmentData> = Array<PageAttachmentData>()
    public var attachments_provided: Bool = false
}

public class PageAttachmentData {
    public var id: Int64 = 0
    public var metadata_id: Int64 = 0
    public var slot: String = ""
    public var asset_id: Int64 = 0
    public var name: String = ""
    public var mime_type: String = ""
    public var kind: String = ""
    public var language: String = ""
    public var order_index: Int32 = 0
    public var created_at: String = ""
    public var updated_at: String = ""
}
