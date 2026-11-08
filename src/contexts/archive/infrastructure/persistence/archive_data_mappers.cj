package lanlu.contexts.archive.infrastructure.persistence

import csorm.*

/**
 * Centralized mappers for DAO Row -> data objects.
 *
 * Keep these small and index-based (matching SELECT column order) so query code stays readable
 * and column-order changes are done in one place.
 */
public class ArchiveDataMappers {
    /**
     * Map a row shaped like:
     *   arcid, filename, title, summary, thumbhash, cover_asset_id,
     *   created_at, updated_at, release_at, relative_path, file_size, pagecount,
     *   last_read_time, progress, tags
     */
    public static func fromArchivesWithTagsRow(row: Row): ArchiveData {
        return fromArchivesWithTagsRow(row, 0i64)
    }

    public static func fromArchivesWithTagsRow(row: Row, offset: Int64): ArchiveData {
        let archive = ArchiveData()
        archive.id = row.getOrNullText(offset + 0) ?? ""
        archive.filename = row.getOrNullText(offset + 1) ?? ""
        archive.title = row.getOrNullText(offset + 2) ?? ""
        archive.summary = row.getOrNullText(offset + 3) ?? ""
        archive.thumbhash = row.getOrNullText(offset + 4) ?? ""
        archive.cover_asset_id = row.getOrNullInt64(offset + 5) ?? 0
        archive.created_at = row.getOrNullText(offset + 6) ?? ""
        archive.updated_at = row.getOrNullText(offset + 7) ?? ""
        archive.release_at = row.getOrNullText(offset + 8) ?? ""
        archive.relative_path = row.getOrNullText(offset + 9) ?? ""
        archive.file_size = row.getOrNullInt64(offset + 10) ?? 0
        archive.pagecount = row.getOrNullInt32(offset + 11) ?? 0
        archive.last_read_time = row.getOrNullInt64(offset + 12) ?? 0
        archive.progress = row.getOrNullInt32(offset + 13) ?? 0
        archive.tags = row.getOrNullText(offset + 14) ?? ""
        return archive
    }
}