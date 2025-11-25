package lrr4cj.controllers

import stdx.net.http.HttpStatusCode
import cjoy.*
import cjoy.json.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*
import lrr4cj.services.*
import std.time.*
import std.fs.*
import std.convert.*

public class ArchiveController {
    // GET /api/archives
    public static func getArchives(ctx: JoyContext): Unit {
        // 从数据库获取档案列表
        let archives = ArchiveModel.getAllArchives()
        
        // 手动构建JSON数组
        var archivesJson = "["
        var isFirst = true
        for (archive in archives) {
            if (!isFirst) {
                archivesJson += ","
            }
            isFirst = false
            
            archivesJson += "{"
            archivesJson += "\"arcid\":\"${archive.id}\","
            archivesJson += "\"title\":\"${archive.title}\","
            archivesJson += "\"filename\":\"${archive.filename}\","
            archivesJson += "\"summary\":\"${archive.summary}\","
            archivesJson += "\"thumbhash\":\"${archive.thumbhash}\","
            archivesJson += "\"created_at\":\"${archive.created_at}\","
            archivesJson += "\"updated_at\":\"${archive.updated_at}\","
            archivesJson += "\"relative_path\":\"${archive.relative_path}\","
            archivesJson += "\"file_size\":${archive.file_size},"
            archivesJson += "\"isnew\":${archive.isNew},"
            archivesJson += "\"pagecount\":${archive.pagecount},"
            archivesJson += "\"last_read_time\":\"${archive.last_read_time}\","
            archivesJson += "\"progress\":${archive.progress}"
            archivesJson += "}"
        }
        
        archivesJson += "]"
        
        let result = "{\"operation\":\"get_archives\",\"data\":" + archivesJson + ",\"success\":1}"
        
        ctx.json(result)
    }
    
    // GET /api/archives/{id}
    public static func getArchive(ctx: JoyContext): Unit {
        let id = ctx.getParam("id").getOrThrow()
        let archive = ArchiveModel.getArchiveById(id)

        if (archive.id.size == 0) {
            let errorResponse = "{\"operation\":\"get_archive\",\"error\":\"Archive not found\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ctx.json(errorResponse)
            return
        }

        // 手动构建JSON对象
        var archiveJson = "{"
        archiveJson += "\"arcid\":\"${archive.id}\","
        archiveJson += "\"title\":\"${archive.title}\","
        archiveJson += "\"filename\":\"${archive.filename}\","
        archiveJson += "\"summary\":\"${archive.summary}\","
        archiveJson += "\"thumbhash\":\"${archive.thumbhash}\","
        archiveJson += "\"created_at\":\"${archive.created_at}\","
        archiveJson += "\"updated_at\":\"${archive.updated_at}\","
        archiveJson += "\"relative_path\":\"${archive.relative_path}\","
        archiveJson += "\"file_size\":${archive.file_size},"
        archiveJson += "\"isnew\":${archive.isNew},"
        archiveJson += "\"pagecount\":${archive.pagecount},"
        archiveJson += "\"last_read_time\":\"${archive.last_read_time}\","
        archiveJson += "\"progress\":${archive.progress}"
        archiveJson += "}"
        
        let result = "{\"operation\":\"get_archive\",\"data\":" + archiveJson + ",\"success\":1}"
        ctx.json(result)
    }
    
    // GET /api/archives/{id}/metadata
    public static func getMetadata(ctx: JoyContext): Unit {
        let id = ctx.getParam("id").getOrThrow()
        
        // 检查ID是否为空
        if (id.size == 0) {
            let errorResponse = "{\"error\":\"No archive ID specified.\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json(errorResponse)
            return
        }
        
        // 获取档案元数据（包含标签）
        let archive = ArchiveDao.getArchiveMetadataById(id)
        if (archive.id.size == 0) {
            let errorResponse = "{\"error\":\"Archive not found\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ctx.json(errorResponse)
            return
        }
        
        // 转换 last_read_time 为时间戳
        let lastreadtime = try {
            // 如果 last_read_time 不为空，尝试解析为时间戳
            if (archive.last_read_time.size > 0) {
                // 简化处理，直接返回当前时间戳
                // 实际应该解析时间字符串并转换为时间戳
                Int64.parse(archive.last_read_time)
            } else {
                Int64(0)
            }
        } catch (e: Exception) {
            Int64(0)
        }
        
        // 手动构建JSON响应，符合API文档规范
        var metadataJson = "{"
        metadataJson += "\"arcid\":\"${archive.id}\","
        metadataJson += "\"title\":\"${archive.title}\","
        metadataJson += "\"filename\":\"${archive.filename}\","
        metadataJson += "\"summary\":\"${archive.summary}\","
        // 从标签关联表获取实际标签数据
        let tagsString = TagDao.getArchiveTags(archive.id)
        metadataJson += "\"tags\":\"${tagsString}\","
        metadataJson += "\"isnew\":\"${archive.isNew}\","
        metadataJson += "\"pagecount\":${archive.pagecount},"
        metadataJson += "\"progress\":${archive.progress},"
        metadataJson += "\"lastreadtime\":${lastreadtime},"
        metadataJson += "\"file_size\":${archive.file_size},"
        metadataJson += "\"size\":${archive.file_size},"
        metadataJson += "\"extension\":\"${archive.getExtension()}\","
        metadataJson += "\"created_at\":\"${archive.created_at}\","
        metadataJson += "\"updated_at\":\"${archive.updated_at}\","
        metadataJson += "\"relative_path\":\"${archive.relative_path}\""
        metadataJson += "}"
        
        ctx.json(metadataJson)
    }
    
    // PUT /api/archives/{id}/metadata
    public static func updateMetadata(ctx: JoyContext): Unit {
        let id = ctx.getParam("id").getOrThrow()
        
        // 检查ID是否为空
        if (id.size == 0) {
            let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"No archive ID specified.\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json(errorResponse)
            return
        }
        
        // 获取查询参数
        let titleParam = ctx.getQuery("title")
        let tagsParam = ctx.getQuery("tags")
        let summaryParam = ctx.getQuery("summary")
        
        // 检查归档是否存在
        let archive = ArchiveModel.getArchiveById(id)
        if (archive.id.size == 0) {
            let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"Archive not found\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ctx.json(errorResponse)
            return
        }
        
        // 获取现有档案数据
        var existingArchive = ArchiveDao.getArchiveById(id)
        if (existingArchive.id.size == 0) {
            let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"Archive not found in database\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ctx.json(errorResponse)
            return
        }
        
        // 更新字段（只有提供了参数才更新）
        match (titleParam) {
            case Some(title) => existingArchive.title = title
            case None => () // 保持原值
        }
        
        match (summaryParam) {
            case Some(summary) => existingArchive.summary = summary
            case None => () // 保持原值
        }
        
        // 更新时间戳
        let currentTime = Int64(getCurrentTimeMillis()).toString()
        existingArchive.updated_at = currentTime
        
        // 执行数据库更新
        let updateSuccess = ArchiveDao.update(existingArchive)
        
        if (updateSuccess) {
            // 如果有标签参数，更新标签
            match (tagsParam) {
                case Some(tags) =>
                    // 使用TagDao更新标签
                    let tagUpdateSuccess = TagDao.updateArchiveTags(id, tags)
                    if (!tagUpdateSuccess) {
                        println("Failed to update tags for archive ${id}")
                    }
                case None => () // 不更新标签
            }
            
            let result = "{\"operation\":\"update_metadata\",\"success\":1}"
            ctx.json(result)
        } else {
            let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"Failed to update archive metadata\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ctx.json(errorResponse)
        }
    }
    
    // GET /api/archives/{id}/thumbnail
    public static func getThumbnail(ctx: JoyContext): Unit {
        let id = ctx.getParam("id").getOrThrow()
        
        // 检查ID是否为空
        if (id.size == 0) {
            let errorResponse = "{\"operation\":\"serve_thumbnail\",\"error\":\"No archive ID specified.\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json(errorResponse)
            return
        }
        
        // 获取查询参数
        let pageParam = ctx.getQuery("page")
        let noFallbackParam = ctx.getQuery("no_fallback")
        
        let page = match (pageParam) {
            case Some(p) => try {
                Int32.parse(p)
            } catch (e: Exception) {
                1i32  // 默认为第1页
            }
            case None => 1i32
        }
        
        let noFallback = match (noFallbackParam) {
            case Some(p) => p == "true" || p == "1"
            case None => false
        }
        
        // 检查归档是否存在
        println("Looking for archive with ID: ${id}")
        let archive = ArchiveModel.getArchiveById(id)
        println("Found archive: ${archive.id}, title: ${archive.title}")
        if (archive.id.size == 0) {
            let errorResponse = "{\"operation\":\"serve_thumbnail\",\"error\":\"Archive not found\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ctx.json(errorResponse)
            return
        }
        
        println("About to check if thumbnail exists for archive: ${id}, page: ${page}")
        // 检查缩略图是否存在
        if (ArchiveModel.thumbnailExists(id, page)) {
            // 缩略图存在，直接返回图片
            let thumbnailPath = ArchiveModel.getThumbnailFilePath(id, page)
            println("Thumbnail exists, reading from: ${thumbnailPath}")
            try {
                let imageData = File.readFrom(Path(thumbnailPath))
                ctx.header("Content-Type", "image/jpeg")
                ctx.status(HttpStatusCode.STATUS_OK)
                // 直接返回二进制数据
                ctx.data(imageData)
                return
            } catch (e: Exception) {
                // 读取文件失败，继续使用fallback逻辑
                println("Failed to read thumbnail file: ${e}")
            }
        }
        
        // 缩略图不存在
        if (noFallback) {
            // 不使用fallback，返回任务ID
            let jobId = generateJobId()
            let response = "{\"job\":${jobId},\"operation\":\"serve_thumbnail\",\"success\":1}"
            ctx.status(HttpStatusCode.STATUS_ACCEPTED)
            ctx.json(response)
        } else {
            // 使用fallback，返回占位符图像
            let placeholderImage = getPlaceholderThumbnail()
            ctx.header("Content-Type", "image/jpeg")
            ctx.status(HttpStatusCode.STATUS_OK)
            // 直接返回二进制数据
            ctx.data(placeholderImage)
        }
    }
    
    /**
     * 生成任务ID
     */
    private static func generateJobId(): Int64 {
        return getCurrentTimeMillis()
    }
    
    /**
     * 获取当前时间的毫秒数
     */
    private static func getCurrentTimeMillis(): Int64 {
        // 简单实现，实际应该使用系统API
        return 1234567890
    }
    
    /**
     * 获取占位符缩略图
     */
    private static func getPlaceholderThumbnail(): Array<Byte> {
        // 简化实现，返回一个最小的JPEG图像
        // 这是一个1x1像素的黑色JPEG图像
        let bytes: Array<Byte> = [
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
            0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
            0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
            0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
            0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
            0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
            0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
            0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x01,
            0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
            0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0xFF, 0xC4,
            0x00, 0x14, 0x10, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xDA, 0x00, 0x0C,
            0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00, 0x80, 0xFF, 0xD9
        ]
        
        return bytes
    }

    // GET /api/archives/{id}/files
    public static func getFiles(ctx: JoyContext): Unit {
        let id = ctx.getParam("id").getOrThrow()
        
        // 检查ID是否为空
        if (id.size == 0) {
            let errorResponse = "{\"operation\":\"get_file_list\",\"error\":\"No archive ID specified.\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json(errorResponse)
            return
        }
        
        // 获取查询参数
        let forceParam = ctx.getQuery("force")
        let force = match (forceParam) {
            case Some(f) => f == "true" || f == "1"
            case None => false
        }
        
        let imagesOnlyParam = ctx.getQuery("images_only")
        let imagesOnly = match (imagesOnlyParam) {
            case Some(i) => i == "true" || i == "1"
            case None => true  // 默认只返回图片文件
        }
        
        // 检查归档是否存在
        let archive = ArchiveModel.getArchiveById(id)
        if (archive.id.size == 0) {
            let errorResponse = "{\"operation\":\"get_file_list\",\"error\":\"Archive not found\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ctx.json(errorResponse)
            return
        }
        
        // 获取ShinobuService实例
        let shinobu = ShinobuService.getInstance()
        
        
        // 获取归档中的文件列表
        let pageFiles = shinobu.getArchiveFileList(id)
        
        // 如果不需要只返回图片文件，获取所有文件
        if (!imagesOnly) {
            // 这里可以添加获取所有文件的逻辑
            // 目前保持只返回图片文件
        }
        
        // 构建页面URL列表
        var pagesJson = "["
        for (i in 0..pageFiles.size) {
            if (i > 0) {
                pagesJson = pagesJson + ","
            }
            // 修正URL格式，使用 ? 而不是 &
            let pageUrl = "/api/archives/${id}/page?path=${pageFiles[i]}"
            pagesJson = pagesJson + "\"${pageUrl}\""
        }
        pagesJson = pagesJson + "]"
        
        // 构建响应JSON
        var responseJson = "{"
        responseJson = responseJson + "\"pages\":${pagesJson}"
        responseJson = responseJson + "}"
        
        ctx.json(responseJson)
    }

    // GET /api/archives/{id}/files/{fileIndex}
    public static func getFile(ctx: JoyContext): Unit {
        let id = ctx.getParam("id").getOrThrow()
        let fileIndex = ctx.getParam("fileIndex").getOrThrow()
        let filePath = ArchiveModel.getArchiveFile(id)

        let result = "{\"file\":\"${filePath}\",\"index\":\"${fileIndex}\"}"
        ctx.json(result)
    }

    // POST /api/archives/{id}/extract
    public static func extractArchive(ctx: JoyContext): Unit {
        let id = ctx.getParam("id").getOrThrow()
        // 简化实现，返回一个任务ID
        let taskId = "task_${id}_${Int64(1234567890)}"
        let result = "{\"operation\":\"extract_archive\",\"data\":{\"task_id\":\"${taskId}\"},\"success\":1}"
        ctx.json(result)
    }

    // DELETE /api/archives/{id}
    public static func deleteArchive(ctx: JoyContext): Unit {
        let id = ctx.getParam("id").getOrThrow()
        // 简化实现，总是返回成功
        let result = "{\"operation\":\"delete_archive\",\"success\":1}"
        ctx.json(result)
    }

    // GET /api/archives/{id}/download
    public static func downloadArchive(ctx: JoyContext): Unit {
        let id = ctx.getParam("id").getOrThrow()
        
        // 检查ID是否为空
        if (id.size == 0) {
            let errorResponse = "{\"operation\":\"download_archive\",\"error\":\"No archive ID specified.\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json(errorResponse)
            return
        }
        
        // 检查归档是否存在
        let archive = ArchiveModel.getArchiveById(id)
        if (archive.id.size == 0) {
            let errorResponse = "{\"operation\":\"download_archive\",\"error\":\"Archive not found\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ctx.json(errorResponse)
            return
        }
        
        // 获取ShinobuService实例
        let shinobu = ShinobuService.getInstance()
        
        // 构建归档文件完整路径
        let archivePath = ShinobuService.getArchivePath().toString()
        let fullArchivePath = if (archive.relative_path.size > 0) {
            "${archivePath}/${archive.relative_path}/${archive.filename}"
        } else {
            "${archivePath}/${archive.filename}"
        }
        
        // 检查文件是否存在并读取文件内容
        try {
            // 对于文件访问，需要解析软链接到实际路径
            let actualPath = FileUtils.resolvePath(fullArchivePath)
            let filePath = Path(actualPath)
            let file = File(filePath, Read)
            let fileInfo = file.info
            let fileSize = fileInfo.size
            let buffer = Array<Byte>(fileSize, {_ => 0})
            let bytesRead = file.read(buffer)
            file.close()
            
            // 设置响应头
            ctx.header("Content-Type", "application/octet-stream")
            ctx.header("Content-Disposition", "attachment; filename=\"${archive.filename}\"")
            ctx.header("Content-Length", "${fileSize}")
            ctx.status(HttpStatusCode.STATUS_OK)
            
            // 返回文件内容
            ctx.data(buffer)
        } catch (e: Exception) {
            let errorResponse = "{\"operation\":\"download_archive\",\"error\":\"Failed to read archive file: ${e.message}\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ctx.json(errorResponse)
        }
    }

    // GET /api/archives/{id}/page
    public static func getPage(ctx: JoyContext): Unit {
        let id = ctx.getParam("id").getOrThrow()
        
        // 检查ID是否为空
        if (id.size == 0) {
            let errorResponse = "{\"operation\":\"serve_page\",\"error\":\"No archive ID specified.\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json(errorResponse)
            return
        }
        
        // 获取查询参数
        let pathParam = ctx.getQuery("path")
        match (pathParam) {
            case Some(path) =>
                if (path.size == 0) {
                    let errorResponse = "{\"operation\":\"serve_page\",\"error\":\"No path specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
                }
                
                // 检查归档是否存在
                let archive = ArchiveModel.getArchiveById(id)
                if (archive.id.size == 0) {
                    let errorResponse = "{\"operation\":\"serve_page\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ctx.json(errorResponse)
                    return
                }
                
                // 获取ShinobuService实例
                let shinobu = ShinobuService.getInstance()
                
                // 构建归档文件完整路径
                let archivePath = ShinobuService.getArchivePath().toString()
                let fullArchivePath = if (archive.relative_path.size > 0) {
                    "${archivePath}/${archive.relative_path}/${archive.filename}"
                } else {
                    "${archivePath}/${archive.filename}"
                }
                
                // 使用bsdtar直接提取文件到内存，不写入文件
                try {
                    // 对于文件访问，需要解析软链接到实际路径
                    let actualPath = FileUtils.resolvePath(fullArchivePath)
                    // 使用 bsdtar 的 -xO 选项直接输出到标准输出
                    let (exitCode, stdout, stderr) = shinobu.extractArchiveEntryToStream(actualPath, path)
                    
                    if (exitCode == 0) {
                        // 根据文件扩展名设置Content-Type
                        let contentType = getContentTypeFromPath(path)
                        ctx.header("Content-Type", contentType)
                        ctx.status(HttpStatusCode.STATUS_OK)
                        // 直接返回二进制数据
                        ctx.data(stdout)
                    } else {
                        let error = String.fromUtf8(stderr)
                        let errorResponse = "{\"operation\":\"serve_page\",\"error\":\"Failed to extract file: ${error}\",\"success\":0}"
                        ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                        ctx.json(errorResponse)
                    }
                } catch (e: Exception) {
                    let errorResponse = "{\"operation\":\"serve_page\",\"error\":\"Exception extracting file: ${e.message}\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ctx.json(errorResponse)
                }
            case None =>
                let errorResponse = "{\"operation\":\"serve_page\",\"error\":\"No path specified.\",\"success\":0}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ctx.json(errorResponse)
        }
    }
    
    /**
     * 根据文件路径获取Content-Type
     */
    private static func getContentTypeFromPath(filePath: String): String {
        if (filePath.endsWith(".jpg") || filePath.endsWith(".jpeg")) {
            return "image/jpeg"
        } else if (filePath.endsWith(".png")) {
            return "image/png"
        } else if (filePath.endsWith(".gif")) {
            return "image/gif"
        } else if (filePath.endsWith(".bmp")) {
            return "image/bmp"
        } else if (filePath.endsWith(".webp")) {
            return "image/webp"
        } else {
            return "application/octet-stream"
        }
    }
}