package lrr4cj.models

import cjoy.json.*
import std.database.sql.*
import lrr4cj.config.*
import std.collection.*
import std.fs.*
import lrr4cj.services.*
import lrr4cj.dao.*

/**
 * 归档数据模型
 */
public class Archive {
    public var id: String = ""
    public var title: String = ""
    public var filename: String = ""
    public var summary: String = ""
    public var thumbhash: String = ""
    public var created_at: String = ""
    public var updated_at: String = ""
    public var relative_path: String = ""
    public var file_size: Int64 = 0
    public var isNew: Bool = false
    public var pagecount: Int32 = 0
    public var last_read_time: String = ""
    public var progress: Int32 = 0
    public var tags: String = ""
    
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
    
    /**
     * 将last_read_time转换为时间戳
     */
    public func lastreadtime(): Int64 {
        if (last_read_time.size > 0) {
            // 这里需要根据实际情况转换时间格式
            // 暂时返回0，因为archives_with_tags视图没有这个字段
            return 0
        }
        return 0
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
                        "SELECT arcid, title, filename, summary, thumbhash, created_at, updated_at, relative_path, file_size, isnew, pagecount, last_read_time, progress FROM archives ORDER BY id")
                    let rs = stmt.query()

                    while (rs.next()) {
                        let archive = Archive()
                        archive.id = rs.getOrNull<String>(1) ?? ""
                        archive.title = rs.getOrNull<String>(2) ?? ""
                        archive.filename = rs.getOrNull<String>(3) ?? ""
                        archive.summary = rs.getOrNull<String>(4) ?? ""
                        archive.thumbhash = rs.getOrNull<String>(5) ?? ""
                        archive.created_at = rs.getOrNull<String>(6) ?? ""
                        archive.updated_at = rs.getOrNull<String>(7) ?? ""
                        archive.relative_path = rs.getOrNull<String>(8) ?? ""
                        archive.file_size = rs.getOrNull<Int64>(9) ?? 0
                        archive.isNew = rs.getOrNull<Bool>(10) ?? false
                        archive.pagecount = rs.getOrNull<Int32>(11) ?? 0
                        archive.last_read_time = rs.getOrNull<String>(12) ?? ""
                        archive.progress = rs.getOrNull<Int32>(13) ?? 0
                        archives.add(archive)
                    }

                    conn.close()
                    return archives.toArray()
                } catch (e: Exception) {
                    println("查询归档失败: ${e}")
                    conn.close()
                    return Array<Archive>()
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
        archive.created_at = archiveData.created_at
        archive.updated_at = archiveData.updated_at
        archive.relative_path = archiveData.relative_path
        archive.file_size = archiveData.file_size
        archive.isNew = archiveData.isNew
        archive.pagecount = archiveData.pagecount
        archive.last_read_time = archiveData.last_read_time
        archive.progress = archiveData.progress
        archive.tags = archiveData.tags
        return archive
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
            archive.created_at = data.created_at
            archive.updated_at = data.updated_at
            archive.relative_path = data.relative_path
            archive.file_size = data.file_size
            archive.isNew = data.isNew
            archive.pagecount = data.pagecount
            archive.last_read_time = data.last_read_time
            archive.progress = data.progress
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
        println("开始搜索归档，参数: filter='${filter}', category='${category}', start=${start}, count=${count}, sortby='${sortby}', order='${order}', newOnly=${newOnly}, untaggedOnly=${untaggedOnly}")
        
        // 使用DAO层获取数据
        let (archiveDataArray, totalCount) = ArchiveDao.searchArchives(filter, category, start, count, sortby, order, newOnly, untaggedOnly)
        
        var archives: ArrayList<Archive> = ArrayList<Archive>()
        for (data in archiveDataArray) {
            let archive = Archive()
            archive.id = data.id
            archive.title = data.title
            archive.filename = data.filename
            archive.summary = data.summary
            archive.thumbhash = data.thumbhash
            archive.created_at = data.created_at
            archive.updated_at = data.updated_at
            archive.relative_path = data.relative_path
            archive.file_size = data.file_size
            archive.isNew = data.isNew
            archive.pagecount = data.pagecount
            archive.last_read_time = data.last_read_time
            archive.progress = data.progress
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
        return "/api/archives/${id}/thumbnail"
    }

    /**
     * 获取归档缩略图的文件系统路径
     */
    public static func getThumbnailFilePath(id: String, page: Int32): String {
        let thumbnailDir = ShinobuService.getThumbnailPath().toString()
        let extension = "jpg"
        
        let archiveIdPath = "${thumbnailDir}/${id}.${extension}"
        println("Trying archiveId path: ${archiveIdPath}")
        
        try {
            let filePath = Path(archiveIdPath)
            if (exists(filePath)) {
                let fileInfo = FileInfo(filePath)
                if (fileInfo.isRegular()) {
                    println("Found thumbnail using archiveId: ${archiveIdPath}")
                    return archiveIdPath
                }
            }
        } catch (e: Exception) {
            println("Error checking archiveId file: ${e}")
        }
        
        println("Thumbnail not found for archive: ${id}")
        return ""
    }

    /**
     * 检查缩略图文件是否存在
     */
    public static func thumbnailExists(id: String, page: Int32): Bool {
        // 使用DAO层直接获取thumbhash，避免循环依赖
        let thumbhash = ArchiveDao.getThumbnailHash(id)
        if (thumbhash.size == 0) {
            println("No thumbhash found for archive: ${id}")
            return false
        }
        
        let thumbnailDir = ShinobuService.getThumbnailPath().toString()
        let extension = "jpg"
        let thumbnailPath = "${thumbnailDir}/${id}.${extension}"
        
        println("Checking if thumbnail exists at: ${thumbnailPath}")
        try {
            let filePath = Path(thumbnailPath)
            if (exists(filePath)) {
                let fileInfo = FileInfo(filePath)
                println("Thumbnail file exists and is regular: ${fileInfo.isRegular()}")
                return fileInfo.isRegular()
            }
            println("Thumbnail file does not exist")
            return false
        } catch (e: Exception) {
            println("Error checking thumbnail file: ${e}")
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
