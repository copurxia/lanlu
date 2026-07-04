package lanlu.contexts.archive.infrastructure.persistence

import ace_orm.*

/**
 * Centralized mappers for DAO Row -> data objects.
 *
 * Keep these small and name-based (matching SELECT column names) so query code stays readable
 * and column-order changes are done in one place.
 */
public class ArchiveDataMappers {
    /**
     * ACE-ORM 版本：从 ace_orm.Row 按列名读取，对应 SQL 形如：
     *   arcid, filename, title, summary, thumbhash, cover_asset_id,
     *   created_at, updated_at, release_at, relative_path, file_size, pagecount,
     *   last_read_time, progress, tags
     */
    public static func fromArchivesWithTagsRow(r: Row): ArchiveData {
        let archive = ArchiveData()
        archive.id = r.getText("arcid")
        archive.filename = r.getText("filename")
        archive.title = r.getText("title")
        archive.summary = r.getText("summary")
        archive.thumbhash = r.getText("thumbhash")
        archive.cover_asset_id = r.getInt("cover_asset_id")
        archive.created_at = r.getText("created_at")
        archive.updated_at = r.getText("updated_at")
        archive.release_at = r.getText("release_at")
        archive.relative_path = r.getText("relative_path")
        archive.file_size = r.getInt("file_size")
        archive.pagecount = Int32(r.getInt("pagecount"))
        archive.last_read_time = r.getText("last_read_time")
        archive.progress = Int32(r.getInt("progress"))
        archive.tags = r.getText("tags")
        return archive
    }
}
