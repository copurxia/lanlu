package lrr4cj.controllers

import stdx.net.http.HttpStatusCode
import cjoy.*
import cjoy.json.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*
import lrr4cj.config.*
import lrr4cj.middleware.*
import lrr4cj.archivehandler.*
import std.time.*
import std.fs.*
import std.convert.*
import std.collection.*
import std.database.sql.*
import stdx.encoding.url.Form

public class ArchiveController {

    /**
     * JSON字符串转义函数
     */
    private static func escapeJson(s: String): String {
        var escaped = s
        escaped = escaped.replace("\\", "\\\\")
        escaped = escaped.replace("\"", "\\\"")
        escaped = escaped.replace("\b", "\\b")
        escaped = escaped.replace("\f", "\\f")
        escaped = escaped.replace("\n", "\\n")
        escaped = escaped.replace("\r", "\\r")
        escaped = escaped.replace("\t", "\\t")
        return escaped
    }

    /**
     * 获取档案的基础路径（从分类获取）
     */
    private static func getArchiveBasePath(arcid: String): String {
        let categoryId = ArchiveDao.getArchiveCategoryId(arcid)
        if (categoryId > 0) {
            match (CategoryDao.getCategoryByInternalId(categoryId)) {
                case Some(cat) => return cat.scanPath
                case None => ()
            }
        }
        return ""
    }

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
            archivesJson += "\"isnew\":${archive.isNew},"  // 返回布尔值
            archivesJson += "\"pagecount\":${archive.pagecount}"
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

        // 获取归档的内部数据库ID用于查询用户状态
        let archiveIdInt = getArchiveInternalId(id)

        // 查询用户级别的 isNew 状态和收藏状态
        var isNew = true  // 默认为新
        var isFavorite = false  // 默认未收藏
        match (AuthMiddleware.optionalUser(ctx)) {
            case Some(userId) =>
                if (archiveIdInt > 0) {
                    isNew = UserArchiveStatusDao.isNew(userId, archiveIdInt)
                    isFavorite = UserFavoriteDao.isFavorite(userId, archiveIdInt)
                }
            case None =>
                // 未登录用户，默认为新且未收藏
                isNew = true
                isFavorite = false
        }

        // 手动构建JSON对象
        var archiveJson = "{"
        archiveJson += "\"arcid\":\"${archive.id}\","
        archiveJson += "\"title\":\"${escapeJson(archive.title)}\","
        archiveJson += "\"filename\":\"${escapeJson(archive.filename)}\","
        archiveJson += "\"summary\":\"${escapeJson(archive.summary)}\","
        archiveJson += "\"thumbhash\":\"${archive.thumbhash}\","
        archiveJson += "\"created_at\":\"${archive.created_at}\","
        archiveJson += "\"updated_at\":\"${archive.updated_at}\","
        archiveJson += "\"relative_path\":\"${escapeJson(archive.relative_path)}\","
        archiveJson += "\"file_size\":${archive.file_size},"
        archiveJson += "\"isnew\":${isNew},"
        archiveJson += "\"isfavorite\":${isFavorite},"
        archiveJson += "\"pagecount\":${archive.pagecount}"
        archiveJson += "}"

        let result = "{\"operation\":\"get_archive\",\"data\":" + archiveJson + ",\"success\":1}"
        ctx.json(result)
    }
    
    // GET /api/archives/{id}/metadata
    public static func getMetadata(ctx: JoyContext): Unit {
        let id = ctx.getParam("id").getOrThrow()
        let lang = ctx.getQuery("lang") ?? ""

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

        // 获取归档的内部数据库ID用于查询用户状态
        let archiveIdInt = getArchiveInternalId(id)

        // 查询用户级别的 isNew 状态、收藏状态和阅读进度
        var isNew = true  // 默认为新
        var isFavorite = false  // 默认未收藏
        var userProgress: Int32 = 0  // 用户特定阅读进度，默认为0
        var lastreadtime: Int64 = 0  // 最后阅读时间，默认为0
        match (AuthMiddleware.optionalUser(ctx)) {
            case Some(userId) =>
                if (archiveIdInt > 0) {
                    isNew = UserArchiveStatusDao.isNew(userId, archiveIdInt)
                    isFavorite = UserFavoriteDao.isFavorite(userId, archiveIdInt)
                    userProgress = UserArchiveStatusDao.getProgress(userId, archiveIdInt)
                    // 获取最后阅读时间
                    lastreadtime = UserArchiveStatusDao.getLastReadTime(userId, archiveIdInt)
                }
            case None =>
                // 未登录用户，默认为新且未收藏，进度为0
                isNew = true
                isFavorite = false
                userProgress = 0
                lastreadtime = 0
        }

        // 手动构建JSON响应，符合API文档规范
        var metadataJson = "{"
        metadataJson += "\"arcid\":\"${archive.id}\","
        metadataJson += "\"title\":\"${archive.title}\","
        metadataJson += "\"filename\":\"${archive.filename}\","
        metadataJson += "\"summary\":\"${archive.summary}\","
        // 从标签关联表获取实际标签数据，并根据lang参数翻译
        let tagsString = TagDao.getArchiveTags(archive.id)
        let translatedTags = if (lang.size > 0) {
            TagDao.translateTagsString(tagsString, lang)
        } else {
            tagsString
        }
        metadataJson += "\"tags\":\"${translatedTags}\","
        metadataJson += "\"isnew\":${isNew},"  // 查询用户级别的 isNew 状态
        metadataJson += "\"isfavorite\":${isFavorite},"  // 查询用户级别的收藏状态
        metadataJson += "\"pagecount\":${archive.pagecount},"
        metadataJson += "\"progress\":${userProgress},"  // 使用用户特定进度而非全局进度
        metadataJson += "\"lastreadtime\":${lastreadtime},"
        metadataJson += "\"file_size\":${archive.file_size},"
        metadataJson += "\"size\":${archive.file_size},"
        metadataJson += "\"archivetype\":\"${archive.archive_type}\","
        metadataJson += "\"created_at\":\"${archive.created_at}\","
        metadataJson += "\"updated_at\":\"${archive.updated_at}\","
        metadataJson += "\"relative_path\":\"${archive.relative_path}\""
        metadataJson += "}"
        
        ctx.json(metadataJson)
    }

    // GET /api/archives/{id}/tankoubons
    public static func getTankoubonsForArchive(ctx: JoyContext): Unit {
        let arcid = ctx.getParam("id").getOrThrow()
        if (arcid.size == 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ctx.json("{\"error\":\"No archive ID specified.\",\"operation\":\"get_archive_tankoubons\",\"success\":0}")
            return
        }

        let userIdOpt = AuthMiddleware.optionalUser(ctx)
        let tankoubons = match (userIdOpt) {
            case Some(userId) => TankoubonModel.getTankoubonsForArchiveWithUser(arcid, userId)
            case None => TankoubonModel.getTankoubonsForArchive(arcid)
        }

        // 查询收藏状态（登录用户）
        match (userIdOpt) {
            case Some(userId) =>
                for (i in 0..tankoubons.size) {
                    tankoubons[i].isfavorite = UserTankoubonFavoriteDao.isFavorite(userId, tankoubons[i].id)
                }
            case None => ()
        }

        var result = "{\"filtered\":${tankoubons.size},\"result\":["
        for (i in 0..tankoubons.size) {
            if (i > 0) { result += "," }
            result += tankoubons[i].toJson()
        }
        result += "],\"total\":${tankoubons.size}}"
        ctx.json(result)
    }
    
    // PUT /api/archives/{id}/metadata
    public static func updateMetadata(ctx: JoyContext): Unit {
        let id = ctx.getParam("id").getOrThrow()
        let lang = ctx.getQuery("lang") ?? ""

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
        existingArchive.updated_at = DateTime.now().toString()
        
        // 执行数据库更新
        let updateSuccess = ArchiveDao.update(existingArchive)
        
        if (updateSuccess) {
            // 如果有标签参数，更新标签
            match (tagsParam) {
                case Some(tags) =>
                    // 如果提供了lang参数，需要将翻译后的标签还原为原始标签
                    let originalTags = if (lang.size > 0) {
                        TagDao.reverseTranslateTagsString(tags, lang)
                    } else {
                        tags
                    }
                    // 使用TagDao更新标签
                    let tagUpdateSuccess = TagDao.updateArchiveTags(id, originalTags)
                    if (!tagUpdateSuccess) {
                        // 记录错误日志到日志文件，而不是控制台
                        getLogger("archive_controller").error("Failed to update tags for archive ${id}")
                        // 返回错误响应给前端
                        let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"Failed to update tags\",\"success\":0}"
                        ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                        ctx.json(errorResponse)
                        return
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
                // 生成 ETag（优先使用 thumbhash，否则基于 id+page 生成）
                let etag = if (archive.thumbhash.size > 0) {
                    "\"${archive.thumbhash}\""
                } else {
                    CacheUtils.generateETag("${id}-${page}")
                }

                // 检查条件请求 - If-None-Match
                if (CacheUtils.checkIfNoneMatch(ctx, etag)) {
                    CacheUtils.sendNotModified(ctx, etag)
                    return
                }

                let imageData = File.readFrom(Path(thumbnailPath))

                // 设置缓存头
                CacheUtils.setStaticCacheHeaders(ctx, etag)
                ctx.header("Content-Type", "image/avif")
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
            let jobId = DateTime.now().toUnixTimeStamp().toSeconds() * 1000
            let response = "{\"job\":${jobId},\"operation\":\"serve_thumbnail\",\"success\":1}"
            ctx.status(HttpStatusCode.STATUS_ACCEPTED)
            ctx.json(response)
        } else {
            // 使用fallback，返回占位符图像（不缓存临时内容）
            let placeholderImage = getPlaceholderThumbnail()
            CacheUtils.setNoCacheHeaders(ctx)
            ctx.header("Content-Type", "image/avif")
            ctx.status(HttpStatusCode.STATUS_OK)
            // 直接返回二进制数据
            ctx.data(placeholderImage)
        }
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
        let imagesOnlyParam = ctx.getQuery("images_only")
        let imagesOnly = match (imagesOnlyParam) {
            case Some(i) => i == "true" || i == "1"
            case None => true  // 默认只返回图片文件
        }

        // 检查归档是否存在
        let archive = ArchiveDao.getArchiveById(id)
        if (archive.id.size == 0) {
            let errorResponse = "{\"operation\":\"get_file_list\",\"error\":\"Archive not found\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ctx.json(errorResponse)
            return
        }

        // 构建归档文件完整路径（从分类获取基础路径）
        let archivePath = getArchiveBasePath(archive.id)
        if (archivePath.size == 0) {
            ctx.status(500)
            ctx.json("{\"success\":0,\"error\":\"Category not found for archive\"}")
            return
        }
        let fullArchivePath = if (archive.relative_path.size > 0) {
            "${archivePath}/${archive.relative_path}/${archive.filename}"
        } else {
            "${archivePath}/${archive.filename}"
        }

        // 对于文件访问，需要解析软链接到实际路径
        let actualPath = FileUtils.resolvePath(fullArchivePath)

        // 使用 Handler 获取文件列表（带标题）
        let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archive.archive_type)
        let entriesWithTitle = handler.listEntriesWithTitle(actualPath)

        // handler 已经进行了适当的过滤：EPUB返回HTML文件，其他返回媒体文件
        var pageFiles = ArrayList<(String, String)>()
        var totalEntries = 0
        var mediaEntries = 0
        for (entry in entriesWithTitle) {
            let (href, title) = entry
            totalEntries += 1
            mediaEntries += 1
            pageFiles.add((href, title))
        }

        // 如果不需要只返回图片文件，获取所有文件
        if (!imagesOnly) {
            // 这里可以添加获取所有文件的逻辑
            // 目前保持只返回媒体文件
        }

        // 构建页面URL列表（包含类型和标题信息）
        var pagesJson = "["
        for (i in 0..pageFiles.size) {
            if (i > 0) {
                pagesJson = pagesJson + ","
            }
            let (href, title) = pageFiles[i]
            // 使用查询参数格式，对 path 参数进行 URL 编码
            let form = Form()
            form.set("path", href)
            let pageUrl = "/api/archives/${id}/page?${form.toEncodeString()}"
            // 判断文件类型 - handler已经过滤过了，EPUB返回HTML，其他返回媒体文件
            let fileType = if (archive.archive_type == ArchiveTypes.EPUB) {
                "html"
            } else if (ArchiveUtils.isVideoFile(href)) {
                "video"
            } else {
                "image"
            }
            // 转义标题中的特殊字符
            let escapedTitle = escapeJson(title)
            pagesJson = pagesJson + "{\"url\":\"${pageUrl}\",\"type\":\"${fileType}\",\"title\":\"${escapedTitle}\"}"
        }
        pagesJson = pagesJson + "]"

        // 获取用户的阅读进度（如果用户已登录）
        var progressJson = "0"  // 默认进度为0
        match (AuthMiddleware.optionalUser(ctx)) {
            case Some(userId) =>
                let archiveIdInt = ArchiveModel.getArchiveIdByArcid(id)
                if (archiveIdInt > 0) {
                    let userProgress = UserArchiveStatusDao.getProgress(userId, archiveIdInt)
                    progressJson = userProgress.toString()
                }
            case None => ()  // 用户未登录，使用默认进度
        }

        // 构建响应JSON
        var responseJson = "{"
        responseJson = responseJson + "\"pages\":${pagesJson},"
        responseJson = responseJson + "\"progress\":${progressJson}"
        responseJson = responseJson + "}"

        ctx.json(responseJson)
    }

    // DELETE /api/archives/{id}
    public static func deleteArchive(ctx: JoyContext): Unit {
        // 检查管理员权限
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(userId) =>
                let id = ctx.getParam("id").getOrThrow()

                // 检查ID是否为空
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"delete_archive\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
                }

                // 检查归档是否存在
                let archive = ArchiveModel.getArchiveById(id)
                if (archive.id.size == 0) {
                    let errorResponse = "{\"operation\":\"delete_archive\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ctx.json(errorResponse)
                    return
                }

                // 获取归档的数据库内部ID
                let archiveIdInt = getArchiveInternalId(id)
                if (archiveIdInt <= 0) {
                    let errorResponse = "{\"operation\":\"delete_archive\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ctx.json(errorResponse)
                    return
                }

                // 删除相关数据
                // 1. 删除用户收藏
                UserFavoriteDao.deleteByArchiveId(archiveIdInt)

                // 2. 删除用户阅读状态
                UserArchiveStatusDao.deleteByArchiveId(archiveIdInt)

                // 3. 删除标签关联（通过更新空标签实现）
                TagDao.updateArchiveTags(id, "")

                // 4. 删除档案记录
                let deleteSuccess = ArchiveDao.delete(id)

                // 5. 删除相关文件（缩略图和原始档案）
                // 删除缩略图文件
                if (archive.thumbhash.size > 0) {
                    let thumbnailDir = DatabaseConfig.getThumbnailPath()
                    let exts = ["avif", "jpg", "jpeg", "png", "webp"]
                    for (ext in exts) {
                        let thumbPath = "${thumbnailDir}/${archive.thumbhash}.${ext}"
                        try {
                            remove(Path(thumbPath))
                            getLogger("archive_controller").info("Deleted thumbnail file", ("path", thumbPath), ("arcid", id))
                        } catch (_: Exception) {
                            // 忽略删除失败（文件可能不存在）
                            getLogger("archive_controller").debug("Thumbnail file not found or delete failed", ("path", thumbPath), ("arcid", id))
                        }
                    }
                }

                // 删除原始档案文件
                try {
                    let archivePath = getArchiveBasePath(archive.id)
                    if (archivePath.size > 0) {
                        let fullArchivePath = if (archive.relative_path.size > 0) {
                            "${archivePath}/${archive.relative_path}/${archive.filename}"
                        } else {
                            "${archivePath}/${archive.filename}"
                        }
                        remove(Path(fullArchivePath))
                        getLogger("archive_controller").info("Deleted archive file", ("path", fullArchivePath), ("arcid", id))
                    }
                } catch (e: Exception) {
                    getLogger("archive_controller").warn("Failed to delete archive file", ("arcid", id), ("error", e.message))
                }

                if (deleteSuccess) {
                    let result = "{\"operation\":\"delete_archive\",\"success\":1}"
                    ctx.json(result)
                } else {
                    let errorResponse = "{\"operation\":\"delete_archive\",\"error\":\"Failed to delete archive\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ctx.json(errorResponse)
                }
            case None => return  // requireAdmin 已经设置了错误响应
        }
    }

    // GET /api/archives/{id}/download
    // 大文件阈值：5MB
    private static let CHUNKED_THRESHOLD: Int64 = 5 * 1024 * 1024
    // 分块大小：1MB
    private static let CHUNK_SIZE: Int64 = 1024 * 1024

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

        // 构建归档文件完整路径（从分类获取基础路径）
        let archivePath = getArchiveBasePath(archive.id)
        if (archivePath.size == 0) {
            ctx.status(500)
            ctx.json("{\"success\":0,\"error\":\"Category not found for archive\"}")
            return
        }
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

            // 根据文件大小选择传输方式
            if (fileSize > CHUNKED_THRESHOLD) {
                // 大文件：使用 chunked 分块传输
                downloadArchiveChunked(ctx, file, fileSize, archive.filename)
            } else {
                // 小文件：一次性读取返回
                downloadArchiveSmall(ctx, file, fileSize, archive.filename)
            }
        } catch (e: Exception) {
            let errorResponse = "{\"operation\":\"download_archive\",\"error\":\"Failed to read archive file: ${e.message}\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ctx.json(errorResponse)
        }
    }

    /**
     * 小文件下载：一次性读取到内存返回
     */
    private static func downloadArchiveSmall(ctx: JoyContext, file: File, fileSize: Int64, filename: String): Unit {
        let buffer = Array<Byte>(fileSize, {_ => 0})
        file.read(buffer)
        file.close()

        // 设置响应头
        ctx.header("Content-Type", "application/octet-stream")
        ctx.header("Content-Disposition", "attachment; filename=\"${filename}\"")
        ctx.header("Content-Length", "${fileSize}")
        ctx.status(HttpStatusCode.STATUS_OK)

        // 返回文件内容
        ctx.data(buffer)
    }

    /**
     * 大文件下载：使用 chunked 分块传输，流式读取不占用大量内存
     */
    private static func downloadArchiveChunked(ctx: JoyContext, file: File, fileSize: Int64, filename: String): Unit {
        // 获取 chunked writer
        let writer = ctx.chunkedWriter()

        // 设置响应头（在第一次 write 之前设置）
        writer.header("Content-Type", "application/octet-stream")
        writer.header("Content-Disposition", "attachment; filename=\"${filename}\"")
        // 注意：chunked 传输不设置 Content-Length，由 Transfer-Encoding: chunked 处理

        // 分块读取并发送
        var remaining = fileSize
        let chunkBuffer = Array<Byte>(CHUNK_SIZE, {_ => 0})

        while (remaining > 0) {
            let toRead = if (remaining > CHUNK_SIZE) { CHUNK_SIZE } else { remaining }

            // 读取一块数据
            if (toRead == CHUNK_SIZE) {
                // 完整块，直接使用预分配的 buffer
                let bytesRead = file.read(chunkBuffer)
                if (bytesRead > 0) {
                    writer.write(chunkBuffer)
                    remaining -= bytesRead
                } else {
                    break
                }
            } else {
                // 最后一块，可能不足 CHUNK_SIZE
                let lastBuffer = Array<Byte>(toRead, {_ => 0})
                let bytesRead = file.read(lastBuffer)
                if (bytesRead > 0) {
                    writer.write(lastBuffer)
                    remaining -= bytesRead
                } else {
                    break
                }
            }
        }

        // 关闭文件和结束 chunked 传输
        file.close()
        writer.end()
    }

    // GET /api/archives/{id}/page?path=...
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

                // 检查归档是否存在（使用ArchiveDao以获取archive_type）
                let archive = ArchiveDao.getArchiveById(id)
                if (archive.id.size == 0) {
                    let errorResponse = "{\"operation\":\"serve_page\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ctx.json(errorResponse)
                    return
                }

                // 构建归档文件完整路径（从分类获取基础路径）
                let archivePath = getArchiveBasePath(archive.id)
                if (archivePath.size == 0) {
                    ctx.status(500)
                    ctx.json("{\"success\":0,\"error\":\"Category not found for archive\"}")
                    return
                }
                let fullArchivePath = if (archive.relative_path.size > 0) {
                    "${archivePath}/${archive.relative_path}/${archive.filename}"
                } else {
                    "${archivePath}/${archive.filename}"
                }

                try {
                    // 对于文件访问，需要解析软链接到实际路径
                    let actualPath = FileUtils.resolvePath(fullArchivePath)

                    // 使用 Handler 提取文件内容
                    let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archive.archive_type)
                    let (exitCode, data, error) = handler.extractEntryToStream(actualPath, path)

                    if (exitCode == 0) {
                        let contentSize = data.size
                        let etag = CacheUtils.generateETag("${id}-${path}-${contentSize}")

                        if (CacheUtils.checkIfNoneMatch(ctx, etag)) {
                            CacheUtils.sendNotModifiedDynamic(ctx, etag)
                            return
                        }

                        CacheUtils.setDynamicCacheHeaders(ctx, etag)
                        let contentType = getContentTypeFromPath(path)
                        ctx.header("Content-Type", contentType)
                        ctx.status(HttpStatusCode.STATUS_OK)
                        let byteData = Array<Byte>(contentSize, { i => data[i] })
                        ctx.data(byteData)
                    } else {
                        var errorStr = ""
                        try {
                            errorStr = String.fromUtf8(error)
                        } catch (_: Exception) {
                            errorStr = "Failed to extract file"
                        }
                        let errorResponse = "{\"operation\":\"serve_page\",\"error\":\"${errorStr}\",\"success\":0}"
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
        let lowerPath = filePath.toAsciiLower()
        // HTML/XHTML 类型
        if (lowerPath.endsWith(".xhtml")) {
            return "application/xhtml+xml; charset=utf-8"
        } else if (lowerPath.endsWith(".html")) {
            return "text/html; charset=utf-8"
        } else if (lowerPath.endsWith(".htm")) {
            return "text/html; charset=utf-8"
        // CSS 类型
        } else if (lowerPath.endsWith(".css")) {
            return "text/css; charset=utf-8"
        // 图片类型
        } else if (lowerPath.endsWith(".jpg") || lowerPath.endsWith(".jpeg")) {
            return "image/jpeg"
        } else if (lowerPath.endsWith(".png")) {
            return "image/png"
        } else if (lowerPath.endsWith(".gif")) {
            return "image/gif"
        } else if (lowerPath.endsWith(".bmp")) {
            return "image/bmp"
        } else if (lowerPath.endsWith(".webp")) {
            return "image/webp"
        } else if (lowerPath.endsWith(".avif")) {
            return "image/avif"
        // 视频类型
        } else if (lowerPath.endsWith(".mp4") || lowerPath.endsWith(".m4v")) {
            return "video/mp4"
        } else if (lowerPath.endsWith(".webm")) {
            return "video/webm"
        } else if (lowerPath.endsWith(".mkv")) {
            return "video/x-matroska"
        } else if (lowerPath.endsWith(".avi")) {
            return "video/x-msvideo"
        } else if (lowerPath.endsWith(".mov")) {
            return "video/quicktime"
        } else {
            return "application/octet-stream"
        }
    }

    /**
     * 根据 arcid 获取归档的数据库内部ID
     */
    private static func getArchiveInternalId(arcid: String): Int64 {
        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("SELECT id FROM archives WHERE arcid = ?")
                    try {
                        stmt.set(0, arcid)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<Int64>(0) ?? 0
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (_: Exception) {
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return 0
        }
        return 0
    }

    /**
     * 设置归档的isNew标记（PUT /api/archives/{id}/isnew）
     * 现在使用用户级别的已读状态
     */
    public static func setIsNew(ctx: JoyContext): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.getParam("id").getOrThrow()

                // 检查ID是否为空
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"set_isnew\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
                }

                // 检查归档是否存在
                let archive = ArchiveModel.getArchiveById(id)
                if (archive.id.size == 0) {
                    let errorResponse = "{\"operation\":\"set_isnew\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ctx.json(errorResponse)
                    return
                }

                // 获取归档的数据库内部ID
                let archiveIdInt = getArchiveInternalId(id)
                if (archiveIdInt <= 0) {
                    let errorResponse = "{\"operation\":\"set_isnew\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ctx.json(errorResponse)
                    return
                }

                // 更新用户级别的isNew标记为true
                let updateSuccess = UserArchiveStatusDao.setIsNew(userId, archiveIdInt)

                if (updateSuccess) {
                    let result = "{\"operation\":\"set_isnew\",\"success\":1}"
                    ctx.json(result)
                } else {
                    let errorResponse = "{\"operation\":\"set_isnew\",\"error\":\"Failed to set isNew flag\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ctx.json(errorResponse)
                }
            case None => return  // requireUser 已经设置了错误响应
        }
    }

    /**
     * 清除归档的isNew标记（DELETE /api/archives/{id}/isnew）
     * 现在使用用户级别的已读状态
     */
    public static func clearIsNew(ctx: JoyContext): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.getParam("id").getOrThrow()

                // 检查ID是否为空
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"clear_isnew\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
                }

                // 检查归档是否存在
                let archive = ArchiveModel.getArchiveById(id)
                if (archive.id.size == 0) {
                    let errorResponse = "{\"operation\":\"clear_isnew\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ctx.json(errorResponse)
                    return
                }

                // 获取归档的数据库内部ID
                let archiveIdInt = getArchiveInternalId(id)
                if (archiveIdInt <= 0) {
                    let errorResponse = "{\"operation\":\"clear_isnew\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ctx.json(errorResponse)
                    return
                }

                // 更新用户级别的isNew标记为false
                let updateSuccess = UserArchiveStatusDao.clearIsNew(userId, archiveIdInt)

                if (updateSuccess) {
                    let result = "{\"operation\":\"clear_isnew\",\"success\":1}"
                    ctx.json(result)
                } else {
                    let errorResponse = "{\"operation\":\"clear_isnew\",\"error\":\"Failed to clear isNew flag\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ctx.json(errorResponse)
                }
            case None => return  // requireUser 已经设置了错误响应
        }
    }

    /**
     * 更新用户阅读进度并自动标记为已读（PUT /api/archives/{id}/progress/{page}）
     */
    public static func updateProgress(ctx: JoyContext): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.getParam("id").getOrThrow()
                let pageParam = ctx.getParam("page").getOrThrow()

                // 检查ID和页数参数
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"update_progress\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
                }

                if (pageParam.size == 0) {
                    let errorResponse = "{\"operation\":\"update_progress\",\"error\":\"No page specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
                }

                // 解析页数为整数
                var progress = try {
                    Int32.parse(pageParam)
                } catch (e: Exception) {
                    let errorResponse = "{\"operation\":\"update_progress\",\"error\":\"Invalid page number\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
                }

                // 检查归档是否存在
                let archive = ArchiveModel.getArchiveById(id)
                if (archive.id.size == 0) {
                    let errorResponse = "{\"operation\":\"update_progress\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ctx.json(errorResponse)
                    return
                }

                // 获取归档的数据库内部ID
                let archiveIdInt = getArchiveInternalId(id)
                if (archiveIdInt <= 0) {
                    let errorResponse = "{\"operation\":\"update_progress\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ctx.json(errorResponse)
                    return
                }

                // 验证进度值合理性（不超过总页数）
                if (progress < 0) {
                    progress = 0
                }
                if (progress > archive.pagecount && archive.pagecount > 0) {
                    progress = archive.pagecount
                }

                // 更新进度并自动标记为已读
                let updateSuccess = UserArchiveStatusDao.updateProgress(userId, archiveIdInt, progress)

                if (updateSuccess) {
                    let result = "{\"operation\":\"update_progress\",\"progress\":${progress},\"success\":1}"
                    ctx.json(result)
                } else {
                    let errorResponse = "{\"operation\":\"update_progress\",\"error\":\"Failed to update progress\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ctx.json(errorResponse)
                }
            case None => return  // requireUser 已经设置了错误响应
        }
    }

    /**
     * 添加收藏（PUT /api/archives/{id}/favorite）
     */
    public static func addFavorite(ctx: JoyContext): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.getParam("id").getOrThrow()

                // 检查ID是否为空
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"add_favorite\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
                }

                // 检查归档是否存在
                let archive = ArchiveModel.getArchiveById(id)
                if (archive.id.size == 0) {
                    let errorResponse = "{\"operation\":\"add_favorite\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ctx.json(errorResponse)
                    return
                }

                // 获取归档的数据库内部ID
                let archiveIdInt = getArchiveInternalId(id)
                if (archiveIdInt <= 0) {
                    let errorResponse = "{\"operation\":\"add_favorite\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ctx.json(errorResponse)
                    return
                }

                // 添加收藏
                let addSuccess = UserFavoriteDao.addFavorite(userId, archiveIdInt)

                if (addSuccess) {
                    let result = "{\"operation\":\"add_favorite\",\"success\":1}"
                    ctx.json(result)
                } else {
                    let errorResponse = "{\"operation\":\"add_favorite\",\"error\":\"Failed to add favorite\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ctx.json(errorResponse)
                }
            case None => return  // requireUser 已经设置了错误响应
        }
    }

    /**
     * 取消收藏（DELETE /api/archives/{id}/favorite）
     */
    public static func removeFavorite(ctx: JoyContext): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.getParam("id").getOrThrow()

                // 检查ID是否为空
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"remove_favorite\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
                }

                // 获取归档的数据库内部ID
                let archiveIdInt = getArchiveInternalId(id)
                if (archiveIdInt <= 0) {
                    let errorResponse = "{\"operation\":\"remove_favorite\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ctx.json(errorResponse)
                    return
                }

                // 取消收藏
                let removeSuccess = UserFavoriteDao.removeFavorite(userId, archiveIdInt)

                if (removeSuccess) {
                    let result = "{\"operation\":\"remove_favorite\",\"success\":1}"
                    ctx.json(result)
                } else {
                    let errorResponse = "{\"operation\":\"remove_favorite\",\"error\":\"Failed to remove favorite\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ctx.json(errorResponse)
                }
            case None => return  // requireUser 已经设置了错误响应
        }
    }

    /**
     * 获取用户的所有收藏（GET /api/favorites）
     * 返回收藏的 arcid 列表（兼容旧接口）
     */
    public static func getFavorites(ctx: JoyContext): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                // 获取用户收藏的 arcid 列表
                let arcids = UserFavoriteDao.getUserFavoriteArcids(userId)

                // 构建JSON数组
                var arcidsJson = "["
                for (i in 0..arcids.size) {
                    if (i > 0) {
                        arcidsJson += ","
                    }
                    arcidsJson += "\"${arcids[i]}\""
                }
                arcidsJson += "]"

                let result = "{\"operation\":\"get_favorites\",\"favorites\":${arcidsJson},\"success\":1}"
                ctx.json(result)
            case None => return  // requireUser 已经设置了错误响应
        }
    }

    /**
     * 获取用户收藏的档案详情列表（GET /api/favorites/archives）
     * 支持分页，返回完整的档案信息
     */
    public static func getFavoriteArchives(ctx: JoyContext): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                // 获取分页参数
                let startParam = ctx.getQuery("start")
                let countParam = ctx.getQuery("count")

                let start = match (startParam) {
                    case Some(s) => try { Int32.parse(s) } catch (_: Exception) { 0i32 }
                    case None => 0i32
                }

                let count = match (countParam) {
                    case Some(c) => try { Int32.parse(c) } catch (_: Exception) { 100i32 }
                    case None => 100i32
                }

                // 获取收藏的档案详情
                let (archives, totalCount) = UserFavoriteDao.getUserFavoriteArchives(userId, start, count)

                // 构建JSON响应
                var archivesJson = "["
                for (i in 0..archives.size) {
                    if (i >= archives.size) {
                        break
                    }
                    if (i > 0) {
                        archivesJson += ","
                    }
                    let archive = archives[i]

                    // 查询用户级别的 isNew 状态
                    let archiveIdInt = getArchiveInternalId(archive.id)
                    let isNew = if (archiveIdInt > 0) {
                        UserArchiveStatusDao.isNew(userId, archiveIdInt)
                    } else {
                        true
                    }

                    archivesJson += "{"
                    archivesJson += "\"arcid\":\"${escapeJson(archive.id)}\","
                    archivesJson += "\"title\":\"${escapeJson(archive.title)}\","
                    archivesJson += "\"filename\":\"${escapeJson(archive.filename)}\","
                    archivesJson += "\"summary\":\"${escapeJson(archive.summary)}\","
                    archivesJson += "\"thumbhash\":\"${escapeJson(archive.thumbhash)}\","
                    archivesJson += "\"tags\":\"${escapeJson(archive.tags)}\","
                    archivesJson += "\"isnew\":${isNew},"
                    archivesJson += "\"isfavorite\":true,"
                    archivesJson += "\"pagecount\":${archive.pagecount},"
                    archivesJson += "\"progress\":${archive.progress},"
                    archivesJson += "\"file_size\":${archive.file_size},"
                    archivesJson += "\"created_at\":\"${escapeJson(archive.created_at)}\","
                    archivesJson += "\"updated_at\":\"${escapeJson(archive.updated_at)}\","
                    archivesJson += "\"last_read_time\":\"${escapeJson(archive.last_read_time)}\""
                    archivesJson += "}"
                }
                archivesJson += "]"

                let result = "{\"operation\":\"get_favorite_archives\",\"data\":${archivesJson},\"recordsTotal\":${totalCount},\"recordsFiltered\":${totalCount},\"success\":1}"
                ctx.json(result)
            case None => return  // requireUser 已经设置了错误响应
        }
    }

    /**
     * 获取用户已读的档案列表（GET /api/read_archives）
     * 支持分页，返回完整的档案信息
     */
    public static func getReadArchives(ctx: JoyContext): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                // 获取分页参数
                let startParam = ctx.getQuery("start")
                let countParam = ctx.getQuery("count")

                let start = match (startParam) {
                    case Some(s) => try { Int32.parse(s) } catch (_: Exception) { 0i32 }
                    case None => 0i32
                }

                let count = match (countParam) {
                    case Some(c) => try { Int32.parse(c) } catch (_: Exception) { 100i32 }
                    case None => 100i32
                }

                // 获取已读的档案详情
                let (archives, totalCount) = UserArchiveStatusDao.getUserReadArchives(userId, start, count)

                // 构建JSON响应
                var archivesJson = "["
                for (i in 0..archives.size) {
                    if (i >= archives.size) {
                        break
                    }
                    if (i > 0) {
                        archivesJson += ","
                    }
                    let archive = archives[i]

                    // 查询收藏状态
                    let archiveIdInt = getArchiveInternalId(archive.id)
                    let isFavorite = if (archiveIdInt > 0) {
                        UserFavoriteDao.isFavorite(userId, archiveIdInt)
                    } else {
                        false
                    }

                    archivesJson += "{"
                    archivesJson += "\"arcid\":\"${escapeJson(archive.id)}\","
                    archivesJson += "\"title\":\"${escapeJson(archive.title)}\","
                    archivesJson += "\"filename\":\"${escapeJson(archive.filename)}\","
                    archivesJson += "\"summary\":\"${escapeJson(archive.summary)}\","
                    archivesJson += "\"thumbhash\":\"${escapeJson(archive.thumbhash)}\","
                    archivesJson += "\"tags\":\"${escapeJson(archive.tags)}\","
                    archivesJson += "\"isnew\":false,"
                    archivesJson += "\"isfavorite\":${isFavorite},"
                    archivesJson += "\"pagecount\":${archive.pagecount},"
                    archivesJson += "\"progress\":${archive.progress},"
                    archivesJson += "\"file_size\":${archive.file_size},"
                    archivesJson += "\"created_at\":\"${escapeJson(archive.created_at)}\","
                    archivesJson += "\"updated_at\":\"${escapeJson(archive.updated_at)}\","
                    archivesJson += "\"last_read_time\":\"${escapeJson(archive.last_read_time)}\""
                    archivesJson += "}"
                }
                archivesJson += "]"

                let result = "{\"operation\":\"get_read_archives\",\"data\":${archivesJson},\"recordsTotal\":${totalCount},\"recordsFiltered\":${totalCount},\"success\":1}"
                ctx.json(result)
            case None => return  // requireUser 已经设置了错误响应
        }
    }
}
