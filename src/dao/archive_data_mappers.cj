package lanlu.dao

import std.database.sql.*

/**
 * Centralized mappers for DAO ResultSet -> data objects.
 *
 * Keep these small and index-based (matching SELECT column order) so query code stays readable
 * and column-order changes are done in one place.
 */
public class ArchiveDataMappers {
    /**
     * Map a row shaped like:
     *   arcid, filename, title, summary, thumbhash, cover_asset_id,
     *   created_at, updated_at, relative_path, file_size, pagecount,
     *   last_read_time, progress, tags
     */
    public static func fromArchivesWithTagsRow(rs: QueryResult): ArchiveData {
        return fromArchivesWithTagsRow(rs, 0i64)
    }

    public static func fromArchivesWithTagsRow(rs: QueryResult, offset: Int64): ArchiveData {
        let archive = ArchiveData()
        archive.id = rs.getOrNull<String>(offset + 0) ?? ""
        archive.filename = rs.getOrNull<String>(offset + 1) ?? ""
        archive.title = rs.getOrNull<String>(offset + 2) ?? ""
        archive.summary = rs.getOrNull<String>(offset + 3) ?? ""
        archive.thumbhash = rs.getOrNull<String>(offset + 4) ?? ""
        archive.cover_asset_id = rs.getOrNull<Int64>(offset + 5) ?? 0
        archive.created_at = rs.getOrNull<String>(offset + 6) ?? ""
        archive.updated_at = rs.getOrNull<String>(offset + 7) ?? ""
        archive.relative_path = rs.getOrNull<String>(offset + 8) ?? ""
        archive.file_size = rs.getOrNull<Int64>(offset + 9) ?? 0
        archive.pagecount = rs.getOrNull<Int32>(offset + 10) ?? 0
        archive.last_read_time = rs.getOrNull<String>(offset + 11) ?? ""
        archive.progress = rs.getOrNull<Int32>(offset + 12) ?? 0
        archive.tags = rs.getOrNull<String>(offset + 13) ?? ""
        return archive
    }
}
