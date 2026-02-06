package lanlu.models

import std.database.sql.*
import lanlu.config.*
import std.collection.*
import std.fs.*
import lanlu.dao.*
import lanlu.utils.*

/**
 * 归档数据模型
 * 注意：isNew 字段已移除，现在使用用户级别的已读状态（user_archive_status 表）
 */
public class Archive {
    public var id: String = ""  // arcid
    public var internalId: Int64 = 0  // 数据库内部ID，用于关联查询
    public var title: String = ""
    public var filename: String = ""
    public var summary: String = ""
    public var thumbhash: String = ""
    public var cover_asset_id: Int64 = 0
    public var created_at: String = ""
    public var updated_at: String = ""
    public var relative_path: String = ""
    public var file_size: Int64 = 0
    public var pagecount: Int32 = 0
    public var archive_type: String = "archive"  // 归档类型：archive=压缩包，folder=文件夹，pdf=PDF
    public var tags: String = ""
    // isNew 字段已移除 - 现在使用 UserArchiveStatusDao 来管理用户级别的已读状态
    public var isNew: Bool = false  // 保留用于向后兼容，但不再从数据库读取
    // last_read_time 和 progress 不再存储在 archives 表中，而是从 user_archive_status 表获取
    // 这些字段仅用于 API 响应，由 UserArchiveStatusDao 填充
    public var last_read_time: String = ""
    public var progress: Int32 = 0

    /**
     * 获取文件扩展名
     */
    public func getExtension(): String {
        if (filename.size > 0) {
            let parts = filename.split(".")
            if (parts.size > 1) {
                return parts[parts.size - 1]
            }
        }
        return ""
    }

    /**
     * 获取文件扩展名（别名，与API文档一致）
     */
    public func extension(): String {
        return getExtension()
    }

    /**
     * 获取文件大小
     */
    public func size(): Int64 {
        return file_size
    }
}

/**
 * 归档数据访问层
 */
public class ArchiveModel {
    /**
     * 获取所有归档
     */
    public static func getAllArchives(): Array<Archive> {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                var archives: ArrayList<Archive> = ArrayList<Archive>()
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT arcid, title, filename, summary, thumbhash, cover_asset_id, created_at, updated_at, relative_path, file_size, pagecount, archive_type FROM archives ORDER BY id")
                    try {
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let archive = Archive()
                                archive.id = rs.getOrNull<String>(0) ?? ""
                                archive.title = rs.getOrNull<String>(1) ?? ""
                                archive.filename = rs.getOrNull<String>(2) ?? ""
                                archive.summary = rs.getOrNull<String>(3) ?? ""
                                archive.thumbhash = rs.getOrNull<String>(4) ?? ""
                                archive.cover_asset_id = rs.getOrNull<Int64>(5) ?? 0
                                archive.created_at = rs.getOrNull<String>(6) ?? ""
                                archive.updated_at = rs.getOrNull<String>(7) ?? ""
                                archive.relative_path = rs.getOrNull<String>(8) ?? ""
                                archive.file_size = rs.getOrNull<Int64>(9) ?? 0
                                archive.pagecount = rs.getOrNull<Int32>(10) ?? 0
                                archive.archive_type = rs.getOrNull<String>(11) ?? "archive"
                                archives.add(archive)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return archives.toArray()
                } catch (e: Exception) {
                    println("查询归档失败: ${e}")
                    return Array<Archive>()
                } finally {
                    try { conn.close() } catch (closeException: Exception) {}
                }
            case None =>
                println("无法连接到数据库")
                return Array<Archive>()
        }
    }

    /**
     * 根据 ID 获取归档
     */
    public static func getArchiveById(id: String): Archive {
        let archiveData = ArchiveDao.getArchiveById(id)
        let archive = Archive()
        archive.id = archiveData.id
        archive.title = archiveData.title
        archive.filename = archiveData.filename
        archive.summary = archiveData.summary
        archive.thumbhash = archiveData.thumbhash
        archive.cover_asset_id = archiveData.cover_asset_id
        archive.created_at = archiveData.created_at
        archive.updated_at = archiveData.updated_at
        archive.relative_path = archiveData.relative_path
        archive.file_size = archiveData.file_size
        archive.pagecount = archiveData.pagecount
        archive.archive_type = archiveData.archive_type
        archive.tags = archiveData.tags
        return archive
    }

    /**
     * 根据 arcid 获取 archives 表的内部 ID
     */
    public static func getArchiveIdByArcid(arcid: String): Int64 {
        return ArchiveDao.getArchiveInternalId(arcid)
    }

    /**
     * 搜索归档
     */
    public static func searchArchives(filter: String, category: String, start: Int32, count: Int32, sortby: String, order: String): (Array<Archive>, Int64) {
        println("开始搜索归档，参数: filter='${filter}', category='${category}', start=${start}, count=${count}, sortby='${sortby}', order='${order}'")
        
        // 使用DAO层获取数据
        let (archiveDataArray, totalCount) = ArchiveDao.searchArchives(filter, category, start, count, sortby, order)
        
        var archives: ArrayList<Archive> = ArrayList<Archive>()
        for (data in archiveDataArray) {
            let archive = Archive()
            archive.id = data.id
            archive.title = data.title
            archive.filename = data.filename
            archive.summary = data.summary
            archive.thumbhash = data.thumbhash
            archive.cover_asset_id = data.cover_asset_id
            archive.created_at = data.created_at
            archive.updated_at = data.updated_at
            archive.relative_path = data.relative_path
            archive.file_size = data.file_size
            archive.pagecount = data.pagecount
            archive.archive_type = data.archive_type
            archive.tags = data.tags
            archives.add(archive)
        }

        println("返回${archives.size}条记录，总记录数: ${totalCount}")
        return (archives.toArray(), totalCount)
    }

    /**
     * 搜索归档（带过滤条件）
     */
    public static func searchArchives(filter: String, category: String, start: Int32, count: Int32, sortby: String, order: String, newOnly: Bool, untaggedOnly: Bool): (Array<Archive>, Int64) {
        // 调用带 userId 的版本，userId=0 表示不进行用户级别的 newOnly 过滤
        return searchArchives(filter, category, start, count, sortby, order, newOnly, untaggedOnly, false, "", "", 0)
    }

    /**
     * 搜索归档（带过滤条件和用户ID，支持用户级别的 newOnly 过滤）
     */
    public static func searchArchives(filter: String, category: String, start: Int32, count: Int32, sortby: String, order: String, newOnly: Bool, untaggedOnly: Bool, userId: Int64): (Array<Archive>, Int64) {
        return searchArchives(filter, category, start, count, sortby, order, newOnly, untaggedOnly, false, "", "", userId)
    }

    /**
     * 搜索归档（完整参数版本，支持收藏筛选和日期范围筛选）
     */
    public static func searchArchives(filter: String, category: String, start: Int32, count: Int32, sortby: String, order: String, newOnly: Bool, untaggedOnly: Bool, favoriteOnly: Bool, dateFrom: String, dateTo: String, userId: Int64): (Array<Archive>, Int64) {
        return searchArchives(filter, category, start, count, sortby, order, newOnly, untaggedOnly, favoriteOnly, dateFrom, dateTo, userId, "")
    }

    /**
     * 搜索归档（完整参数版本，支持收藏筛选、日期范围筛选和 tankoubon_id 过滤）
     */
    public static func searchArchives(filter: String, category: String, start: Int32, count: Int32, sortby: String, order: String, newOnly: Bool, untaggedOnly: Bool, favoriteOnly: Bool, dateFrom: String, dateTo: String, userId: Int64, tankoubonId: String): (Array<Archive>, Int64) {
        println("开始搜索归档，参数: filter='${filter}', category='${category}', start=${start}, count=${count}, sortby='${sortby}', order='${order}', newOnly=${newOnly}, untaggedOnly=${untaggedOnly}, favoriteOnly=${favoriteOnly}, dateFrom='${dateFrom}', dateTo='${dateTo}', userId=${userId}, tankoubonId='${tankoubonId}'")

        // 使用DAO层获取数据
        let (archiveDataArray, totalCount) = ArchiveDao.searchArchives(filter, category, start, count, sortby, order, newOnly, untaggedOnly, favoriteOnly, dateFrom, dateTo, userId, tankoubonId)

        var archives: ArrayList<Archive> = ArrayList<Archive>()
        for (data in archiveDataArray) {
            let archive = Archive()
            archive.id = data.id
            archive.internalId = data.internalId
            archive.title = data.title
            archive.filename = data.filename
            archive.summary = data.summary
            archive.thumbhash = data.thumbhash
            archive.cover_asset_id = data.cover_asset_id
            archive.created_at = data.created_at
            archive.updated_at = data.updated_at
            archive.relative_path = data.relative_path
            archive.file_size = data.file_size
            archive.pagecount = data.pagecount
            archive.archive_type = data.archive_type
            archive.tags = data.tags
            archives.add(archive)
        }

        println("返回${archives.size}条记录，总记录数: ${totalCount}")
        return (archives.toArray(), totalCount)
    }

    /**
     * 获取归档元数据
     */
    public static func getArchiveMetadata(id: String): Archive {
        return getArchiveById(id)
    }

    /**
     * 获取归档缩略图
     */
    public static func getArchiveThumbnail(id: String): String {
        let coverAssetId = ArchiveDao.getCoverAssetId(id)
        if (coverAssetId <= 0) { return "" }
        return "/api/assets/${coverAssetId}"
    }

    /**
     * 获取归档缩略图的文件系统路径
     * 缩略图文件存储在 assets：{ASSET_PATH}/{assetId}.avif
     */
    public static func getThumbnailFilePath(id: String): String {
        let coverAssetId = ArchiveDao.getCoverAssetId(id)
        if (coverAssetId <= 0) { return "" }
        let assetDir = SystemSettingsService.getPath("ASSET_PATH")
        let thumbPath = FileUtils.joinPath(assetDir, "${coverAssetId}.avif")
        try {
            let filePath = Path(thumbPath)
            if (exists(filePath)) {
                let fileInfo = FileInfo(filePath)
                if (fileInfo.isRegular()) {
                    return thumbPath
                }
            }
        } catch (_: Exception) {}

        println("Thumbnail not found for archive: ${id}")
        return ""
    }

    /**
     * 检查缩略图文件是否存在
     * 缩略图文件存储在 assets：{ASSET_PATH}/{assetId}.avif
     */
    public static func thumbnailExists(id: String): Bool {
        let coverAssetId = ArchiveDao.getCoverAssetId(id)
        if (coverAssetId <= 0) { return false }
        let assetDir = SystemSettingsService.getPath("ASSET_PATH")
        let thumbPath = FileUtils.joinPath(assetDir, "${coverAssetId}.avif")

        try {
            let filePath = Path(thumbPath)
            if (exists(filePath)) {
                let fileInfo = FileInfo(filePath)
                return fileInfo.isRegular()
            }
        } catch (_: Exception) {}

        return false
    }

    /**
     * 删除归档缩略图文件（不影响数据库）
     */
    public static func deleteThumbnailFile(id: String): Bool {
        let coverAssetId = ArchiveDao.getCoverAssetId(id)
        if (coverAssetId <= 0) { return true }
        let assetDir = SystemSettingsService.getPath("ASSET_PATH")
        let thumbPath = FileUtils.joinPath(assetDir, "${coverAssetId}.avif")
        try {
            let filePath = Path(thumbPath)
            if (!exists(filePath)) { return true }
            let fileInfo = FileInfo(filePath)
            if (!fileInfo.isRegular()) { return true }
            remove(filePath)
            return true
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * 获取归档文件
     */
    public static func getArchiveFile(id: String): String {
        return "/api/archives/${id}/file"
    }
    
}
