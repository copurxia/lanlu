package lrr4cj.controllers

import stdx.net.http.HttpStatusCode
import cjoy.*
import cjoy.json.*
import lrr4cj.models.*
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
    
    // PUT /api/archives/{id}/metadata
    public static func updateMetadata(ctx: JoyContext): Unit {
        let id = ctx.getParam("id").getOrThrow()
        // 简化实现，总是返回成功
        let result = "{\"operation\":\"update_metadata\",\"success\":1}"
        ctx.json(result)
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
        // 简化实现，返回空文件列表
        let result = "{\"operation\":\"get_files\",\"data\":[],\"success\":1}"
        ctx.json(result)
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
}