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
}
