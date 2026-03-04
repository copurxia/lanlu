package lanlu.contexts.archive.infrastructure.persistence

import std.collection.*
import std.database.sql.*
import lanlu.shared.config.*
import lanlu.shared.utils.*

/**
 * 页面元数据结构
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
    public var created_at: String = ""
    public var updated_at: String = ""
}

/**
 * 页面元数据数据访问对象 (DAO)
 */
public class ArchivePageMetadataDao {
    private static let logger = getLogger("archive_page_metadata_dao")

    private static func normalizeEntryPath(entryPath: String, pageNumber: Int32): String {
        let trimmed = entryPath.trimAscii()
        if (trimmed.size > 0) {
            return trimmed
        }
        if (pageNumber > 0) {
            return "__page_${pageNumber}"
        }
        return "__page_0"
    }

    private static func mapRow(rs: QueryResult): PageMetadataData {
        let data = PageMetadataData()
        data.id = rs.getOrNull<Int64>(0) ?? 0
        data.archive_id = rs.getOrNull<Int64>(1) ?? 0
        data.page_number = rs.getOrNull<Int32>(2) ?? 0
        data.entry_path = rs.getOrNull<String>(3) ?? ""
        data.title = rs.getOrNull<String>(4) ?? ""
        data.description = rs.getOrNull<String>(5) ?? ""
        data.sort_index = rs.getOrNull<Int32>(6) ?? 0
        data.hidden_in_files = rs.getOrNull<Bool>(7) ?? false
        data.thumb_asset_id = rs.getOrNull<Int64>(8) ?? 0
        data.thumbhash = rs.getOrNull<String>(9) ?? ""
        data.extra_data = rs.getOrNull<String>(10) ?? "{}"
        data.created_at = rs.getOrNull<String>(11) ?? ""
        data.updated_at = rs.getOrNull<String>(12) ?? ""
        return data
    }

    public static func insertOrUpdate(
        archiveId: Int64,
        pageNumber: Int32,
        entryPath: String,
        title: String,
        description: String,
        thumbAssetId!: Int64 = 0,
        thumbHash!: String = "",
        extraData!: String = "{}",
        sortIndex!: Int32 = 0,
        hiddenInFiles!: Bool = false
    ): Bool {
        let safeEntryPath = normalizeEntryPath(entryPath, pageNumber)

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let sql = """
                        INSERT INTO archive_page_metadata
                        (archive_id, page_number, entry_path, title, description, sort_index, hidden_in_files, thumb_asset_id, thumbhash, extra_data, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                        ON CONFLICT (archive_id, entry_path) DO UPDATE SET
                            page_number = EXCLUDED.page_number,
                            title = EXCLUDED.title,
                            description = EXCLUDED.description,
                            sort_index = EXCLUDED.sort_index,
                            hidden_in_files = EXCLUDED.hidden_in_files,
                            thumb_asset_id = EXCLUDED.thumb_asset_id,
                            thumbhash = EXCLUDED.thumbhash,
                            extra_data = EXCLUDED.extra_data,
                            updated_at = CURRENT_TIMESTAMP
                    """
                    let stmt = conn.prepareStatement(sql)
                    try {
                        stmt.set(0, archiveId)
                        stmt.set(1, pageNumber)
                        stmt.set(2, safeEntryPath)
                        stmt.set(3, title)
                        stmt.set(4, description)
                        stmt.set(5, sortIndex)
                        stmt.set(6, hiddenInFiles)
                        stmt.set(7, thumbAssetId)
                        stmt.set(8, thumbHash)
                        stmt.set(9, extraData)
                        let _ = stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("Failed to insert or update page metadata", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("Cannot get database connection")
                return false
        }
    }

    public static func insertOrUpdateBatch(items: Array<PageMetadataData>): Bool {
        if (items.size == 0) {
            return true
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let sql = """
                        INSERT INTO archive_page_metadata
                        (archive_id, page_number, entry_path, title, description, sort_index, hidden_in_files, thumb_asset_id, thumbhash, extra_data, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                        ON CONFLICT (archive_id, entry_path) DO UPDATE SET
                            page_number = EXCLUDED.page_number,
                            title = EXCLUDED.title,
                            description = EXCLUDED.description,
                            sort_index = EXCLUDED.sort_index,
                            hidden_in_files = EXCLUDED.hidden_in_files,
                            thumb_asset_id = EXCLUDED.thumb_asset_id,
                            thumbhash = EXCLUDED.thumbhash,
                            extra_data = EXCLUDED.extra_data,
                            updated_at = CURRENT_TIMESTAMP
                    """
                    let stmt = conn.prepareStatement(sql)
                    try {
                        for (item in items) {
                            stmt.set(0, item.archive_id)
                            stmt.set(1, item.page_number)
                            stmt.set(2, normalizeEntryPath(item.entry_path, item.page_number))
                            stmt.set(3, item.title)
                            stmt.set(4, item.description)
                            stmt.set(5, item.sort_index)
                            stmt.set(6, item.hidden_in_files)
                            stmt.set(7, item.thumb_asset_id)
                            stmt.set(8, item.thumbhash)
                            stmt.set(9, item.extra_data)
                            let _ = stmt.update()
                        }
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("Failed to batch insert page metadata", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("Cannot get database connection")
                return false
        }
    }

    public static func getByArchiveId(archiveId: Int64): Array<PageMetadataData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, archive_id, page_number, COALESCE(entry_path, ''), COALESCE(title, ''), COALESCE(description, ''), COALESCE(sort_index, 0), COALESCE(hidden_in_files, false), COALESCE(thumb_asset_id, 0), COALESCE(thumbhash, ''), COALESCE(CAST(extra_data AS TEXT), '{}'), created_at, updated_at FROM archive_page_metadata WHERE archive_id = ? ORDER BY page_number, id"
                    )
                    try {
                        stmt.set(0, archiveId)
                        let rs = stmt.query()
                        try {
                            var results = ArrayList<PageMetadataData>()
                            while (rs.next()) {
                                results.add(mapRow(rs))
                            }
                            return results.toArray()
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("Failed to get page metadata by archive id", ("error", e.message))
                    return Array<PageMetadataData>()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("Cannot get database connection")
                return Array<PageMetadataData>()
        }
    }

    public static func getByArchiveAndPath(archiveId: Int64, entryPath: String): Option<PageMetadataData> {
        let safeEntryPath = normalizeEntryPath(entryPath, 0)
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, archive_id, page_number, COALESCE(entry_path, ''), COALESCE(title, ''), COALESCE(description, ''), COALESCE(sort_index, 0), COALESCE(hidden_in_files, false), COALESCE(thumb_asset_id, 0), COALESCE(thumbhash, ''), COALESCE(CAST(extra_data AS TEXT), '{}'), created_at, updated_at FROM archive_page_metadata WHERE archive_id = ? AND entry_path = ? LIMIT 1"
                    )
                    try {
                        stmt.set(0, archiveId)
                        stmt.set(1, safeEntryPath)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return Option<PageMetadataData>.Some(mapRow(rs))
                            }
                            return Option<PageMetadataData>.None
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("Failed to get page metadata by path", ("error", e.message))
                    return Option<PageMetadataData>.None
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("Cannot get database connection")
                return Option<PageMetadataData>.None
        }
    }

    public static func getByArchiveAndPage(archiveId: Int64, pageNumber: Int32): Option<PageMetadataData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, archive_id, page_number, COALESCE(entry_path, ''), COALESCE(title, ''), COALESCE(description, ''), COALESCE(sort_index, 0), COALESCE(hidden_in_files, false), COALESCE(thumb_asset_id, 0), COALESCE(thumbhash, ''), COALESCE(CAST(extra_data AS TEXT), '{}'), created_at, updated_at FROM archive_page_metadata WHERE archive_id = ? AND page_number = ? ORDER BY hidden_in_files ASC, id ASC LIMIT 1"
                    )
                    try {
                        stmt.set(0, archiveId)
                        stmt.set(1, pageNumber)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return Option<PageMetadataData>.Some(mapRow(rs))
                            }
                            return Option<PageMetadataData>.None
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("Failed to get page metadata by page number", ("error", e.message))
                    return Option<PageMetadataData>.None
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("Cannot get database connection")
                return Option<PageMetadataData>.None
        }
    }

    public static func deleteByArchiveId(archiveId: Int64): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("DELETE FROM archive_page_metadata WHERE archive_id = ?")
                    try {
                        stmt.set(0, archiveId)
                        let _ = stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("Failed to delete page metadata", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("Cannot get database connection")
                return false
        }
    }

    public static func getPageThumbAssetId(archiveId: Int64, pageNumber: Int32): Int64 {
        match (getByArchiveAndPage(archiveId, pageNumber)) {
            case Some(data) => return data.thumb_asset_id
            case None => return 0
        }
    }

    public static func getPageThumbAssetIdsByArchiveId(archiveId: Int64): Array<Int64> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT DISTINCT thumb_asset_id FROM archive_page_metadata WHERE archive_id = ? AND thumb_asset_id > 0"
                    )
                    try {
                        stmt.set(0, archiveId)
                        let rs = stmt.query()
                        try {
                            var ids = ArrayList<Int64>()
                            while (rs.next()) {
                                let v = rs.getOrNull<Int64>(0) ?? 0
                                if (v > 0) {
                                    ids.add(v)
                                }
                            }
                            return ids.toArray()
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("Failed to get page thumb asset ids", ("error", e.message))
                    return Array<Int64>()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("Cannot get database connection")
                return Array<Int64>()
        }
    }

    public static func updatePageThumbAssetId(archiveId: Int64, pageNumber: Int32, thumbAssetId: Int64, thumbHash: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement(
                        "UPDATE archive_page_metadata SET thumb_asset_id = ?, thumbhash = ?, updated_at = CURRENT_TIMESTAMP WHERE archive_id = ? AND page_number = ?"
                    )
                    try {
                        stmt.set(0, thumbAssetId)
                        stmt.set(1, thumbHash)
                        stmt.set(2, archiveId)
                        stmt.set(3, pageNumber)
                        let _ = stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("Failed to update page thumb asset", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("Cannot get database connection")
                return false
        }
    }

    public static func updatePageThumbAssetIdByPath(archiveId: Int64, entryPath: String, thumbAssetId: Int64, thumbHash: String): Bool {
        let safeEntryPath = normalizeEntryPath(entryPath, 0)
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement(
                        "UPDATE archive_page_metadata SET thumb_asset_id = ?, thumbhash = ?, updated_at = CURRENT_TIMESTAMP WHERE archive_id = ? AND entry_path = ?"
                    )
                    try {
                        stmt.set(0, thumbAssetId)
                        stmt.set(1, thumbHash)
                        stmt.set(2, archiveId)
                        stmt.set(3, safeEntryPath)
                        let _ = stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("Failed to update page thumb asset by path", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                logger.error("Cannot get database connection")
                return false
        }
    }
}
