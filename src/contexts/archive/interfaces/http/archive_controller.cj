package lanlu.contexts.archive.interfaces.http

import stdx.net.http.HttpStatusCode
import ignite.*
import lanlu.contexts.archive.domain.*
import lanlu.contexts.tankoubon.domain.*
import lanlu.contexts.plugin.domain.*
import lanlu.contexts.plugin.application.*
import lanlu.shared.utils.*
import lanlu.shared.views.*
import lanlu.contexts.archive.infrastructure.persistence.*
import lanlu.contexts.user.infrastructure.persistence.*
import lanlu.contexts.metadata.infrastructure.persistence.*
import lanlu.contexts.category.infrastructure.persistence.*
import lanlu.contexts.tag.infrastructure.persistence.*
import lanlu.shared.config.*
import lanlu.infrastructure.middleware.*
import lanlu.infrastructure.archivehandler.*
import std.fs.*
import std.convert.*
import std.collection.*
import std.database.sql.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*

public class ArchiveController {
    private static func writeArchiveAssetsJson(w: JsonWriter, assetsRaw: String): Unit {
        let raw = assetsRaw.trimAscii()
        let normalized = if (raw.size > 0) { raw } else { "{}" }
        w.writeName("assets").jsonValue(normalized)
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

    /**
     * Normalize file path to a base key for matching sidecar cover/thumb images.
     * Example:
     *   "Episode S01E01-thumb.jpg" -> "episode s01e01"
     *   "Episode S01E01.mkv"      -> "episode s01e01"
     */
    private static func normalizeSidecarBaseKey(path: String): String {
        var normalized = path.trimAscii().replace("\\", "/")
        match (normalized.lastIndexOf("/")) {
            case Some(idx) =>
                if (idx + 1 < normalized.size) {
                    normalized = normalized[(idx + 1)..normalized.size]
                }
            case None => ()
        }

        match (normalized.lastIndexOf(".")) {
            case Some(idx) =>
                if (idx > 0) {
                    normalized = normalized[0..idx]
                }
            case None => ()
        }

        var stem = normalized.trimAscii().toAsciiLower()
        let suffixes: Array<String> = [
            "-thumb", "_thumb", ".thumb",
            "-poster", "_poster", ".poster",
            "-cover", "_cover", ".cover"
        ]
        for (suffix in suffixes) {
            if (stem.endsWith(suffix) && stem.size > suffix.size) {
                stem = stem[0..(stem.size - suffix.size)]
                break
            }
        }
        return stem.trimAscii()
    }

    private static func readExtraInt64(extraData: String, key: String): Int64 {
        let normalized = extraData.trimAscii()
        if (normalized.size == 0 || normalized == "null") {
            return 0
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(normalized.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return 0
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                if (name == key) {
                    let raw = r.readValue<String>().trimAscii()
                    try {
                        let parsed = Int64.parse(raw)
                        return if (parsed > 0) { parsed } else { 0 }
                    } catch (_: Exception) {
                        return 0
                    }
                }
                r.skip()
            }
            r.endObject()
        } catch (_: Exception) {}
        return 0
    }

    private static func parsePositiveIntQuery(ctx: Ctx, name: String): Int32 {
        let raw = (ctx.query(name) ?? "").trimAscii()
        if (raw.size == 0) {
            return 0
        }
        let parsed = try { Int32.parse(raw) } catch (_: Exception) { 0i32 }
        return if (parsed > 0i32) { parsed } else { 0i32 }
    }

    private static func resolveArchiveFileType(archiveType: String, href: String): String {
        if (archiveType == ArchiveTypes.EPUB) {
            return "html"
        }
        if (ArchiveUtils.isVideoFile(href)) {
            return "video"
        }
        if (ArchiveUtils.isAudioFile(href)) {
            return "audio"
        }
        return "image"
    }

    // GET /api/archives/{id}/metadata
    public static func getMetadata(ctx: Ctx): Unit {
        let id = ctx.paramsOpt("id").getOrThrow()
        let lang = (ctx.query("lang") ?? "").trimAscii()
        let includePagesRaw = (ctx.query("include_pages") ?? "").trimAscii().toAsciiLower()
        let includePages = includePagesRaw == "1" || includePagesRaw == "true"

        // 检查ID是否为空
        if (id.size == 0) {
            let errorResponse = "{\"error\":\"No archive ID specified.\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, errorResponse)
            return
        }


        var progress: Int32 = 0i32
        var isNew = false
        var isFavorite = false
        var lastReadTime: Int64 = 0i64
        match (AuthMiddleware.optionalUser(ctx)) {
            case Some(userId) =>
                let archiveIdInt = ArchiveDao.getArchiveInternalId(id)
                if (archiveIdInt > 0) {
                    progress = UserArchiveStatusDao.getProgress(userId, archiveIdInt)
                    isNew = UserArchiveStatusDao.isNew(userId, archiveIdInt)
                    isFavorite = UserFavoriteDao.isFavorite(userId, archiveIdInt)
                    lastReadTime = UserArchiveStatusDao.getLastReadTime(userId, archiveIdInt)
                }
            case None => ()
        }

        let (okMetadata, metadataJson, metadataErr) = MetadataPatchService.buildArchiveMetadataObjectJson(
            id,
            true,
            0,
            includePages: includePages,
            progress: progress,
            isNew: isNew,
            isFavorite: isFavorite,
            lastReadTime: lastReadTime,
            lang: lang
        )
        if (!okMetadata) {
            let err = if (metadataErr.trimAscii().size > 0) { metadataErr } else { "Failed to build archive metadata" }
            if (err == "Archive not found") {
                ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            } else {
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            }
            ResponseView.json(ctx, "{\"error\":\"${err}\",\"success\":0}")
            return
        }
        ResponseView.json(ctx, metadataJson)
    }

    // GET /api/archives/{id}/tankoubons
    public static func getTankoubonsForArchive(ctx: Ctx): Unit {
        let arcid = ctx.paramsOpt("id").getOrThrow()
        if (arcid.size == 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, "{\"error\":\"No archive ID specified.\",\"operation\":\"get_archive_tankoubons\",\"success\":0}")
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

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("filtered").writeValue(tankoubons.size)
        w.writeName("result")
        w.startArray()
        for (i in 0..tankoubons.size) {
            tankoubons[i].writeJson(w)
        }
        w.endArray()
        w.writeName("total").writeValue(tankoubons.size)
        w.endObject()
        w.flush()
        ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
    }
    
    // PUT /api/archives/{id}/metadata
    public static func updateMetadata(ctx: Ctx): Unit {
        let id = ctx.paramsOpt("id").getOrThrow()
        let requestBody = ctx.bodyString().trimAscii()

        if (id.size == 0) {
            let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"No archive ID specified.\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, errorResponse)
            return
        }
        if (requestBody.size == 0) {
            let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"Request body is required\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, errorResponse)
            return
        }

        let archive = ArchiveModel.getArchiveById(id)
        if (archive.id.size == 0) {
            let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"Archive not found\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ResponseView.json(ctx, errorResponse)
            return
        }

        let parsed = MetadataPatchService.parseMetadataObject(requestBody)
        if (!parsed.success) {
            let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"${parsed.error}\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, errorResponse)
            return
        }

        let pluginNamespace = MetadataPatchService.extractMetadataNamespace(requestBody)
        let topPatch = MetadataPatchService.buildArchivePatchFromParsed(parsed)
        let ok = MetadataPatchService.applyArchiveMetadataPatch(0, id, topPatch, pluginNamespace)
        if (!ok) {
            let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"Failed to update archive metadata\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ResponseView.json(ctx, errorResponse)
            return
        }

        ResponseView.json(ctx, "{\"operation\":\"update_metadata\",\"success\":1}")
    }
    
    // GET /api/archives/{id}/files
    public static func getFiles(ctx: Ctx): Unit {
        let id = ctx.paramsOpt("id").getOrThrow()

        // 检查ID是否为空
        if (id.size == 0) {
            let errorResponse = "{\"operation\":\"get_file_list\",\"error\":\"No archive ID specified.\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, errorResponse)
            return
        }

        // 获取查询参数
        let imagesOnlyParam = ctx.query("images_only")
        let imagesOnlySpecified = match (imagesOnlyParam) {
            case Some(_) => true
            case None => false
        }
        let imagesOnly = match (imagesOnlyParam) {
            case Some(i) => i == "true" || i == "1"
            case None => false
        }
        let includeMetadataRaw = (ctx.query("include_metadata") ?? "").trimAscii().toAsciiLower()
        let includeMetadata = includeMetadataRaw != "false" && includeMetadataRaw != "0"
        let limit = parsePositiveIntQuery(ctx, "limit")
        let offsetRaw = (ctx.query("offset") ?? "").trimAscii()
        let offsetParsed = try { Int32.parse(offsetRaw) } catch (_: Exception) { 0i32 }
        let offset = if (offsetParsed > 0i32) { offsetParsed } else { 0i32 }

        // 检查归档是否存在
        let archive = ArchiveDao.getArchiveById(id)
        if (archive.id.size == 0) {
            let errorResponse = "{\"operation\":\"get_file_list\",\"error\":\"Archive not found\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ResponseView.json(ctx, errorResponse)
            return
        }

        // 构建归档文件完整路径（从分类获取基础路径）
        let archivePath = getArchiveBasePath(archive.id)
        if (archivePath.size == 0) {
            ctx.status(500)
            ResponseView.json(ctx, "{\"success\":0,\"error\":\"Category not found for archive\"}")
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
        let pageMetadata = MetadataDao.listPageMetadata(id)
        var metadataByPath = HashMap<String, PageMetadataData>()
        var metadataByPage = HashMap<Int32, PageMetadataData>()
        var sidecarThumbByBase = HashMap<String, Int64>()
        for (meta in pageMetadata) {
            let pathKey = meta.entry_path.trimAscii()
            if (pathKey.size > 0 && !metadataByPath.contains(pathKey)) {
                metadataByPath[pathKey] = meta
            }
            if (meta.page_number > 0 && !metadataByPage.contains(meta.page_number)) {
                metadataByPage[meta.page_number] = meta
            }
            if (meta.hidden_in_files && meta.thumb_asset_id > 0 && ArchiveUtils.isImageFile(pathKey)) {
                let baseKey = normalizeSidecarBaseKey(pathKey)
                if (baseKey.size > 0 && !sidecarThumbByBase.contains(baseKey)) {
                    sidecarThumbByBase[baseKey] = meta.thumb_asset_id
                }
            }
        }

        var withSort = ArrayList<ArchiveFilesPageItem>()
        var withoutSort = ArrayList<ArchiveFilesPageItem>()
        for (i in 0..entriesWithTitle.size) {
            let entry = entriesWithTitle[i]
            let href = entry[0]
            let rawTitle = entry[1]
            let pageNumber = Int32(i + 1)
            let pathKey = href.trimAscii()

            var metadataOpt: Option<PageMetadataData> = Option<PageMetadataData>.None
            var metadataFound = false
            match (metadataByPath.get(pathKey)) {
                case Some(meta) =>
                    metadataOpt = Option<PageMetadataData>.Some(meta)
                    metadataFound = true
                case None => ()
            }
            if (!metadataFound) {
                match (metadataByPage.get(pageNumber)) {
                    case Some(meta) => metadataOpt = Option<PageMetadataData>.Some(meta)
                    case None => ()
                }
            }

            let item = ArchiveFilesPageItem()
            item.href = href
            item.originalIndex = pageNumber
            item.title = rawTitle

            match (metadataOpt) {
                case Some(meta) =>
                    if (meta.title.trimAscii().size > 0) {
                        item.title = meta.title
                    }
                    item.description = meta.description
                    item.releaseAt = meta.release_at
                    item.thumbAssetId = meta.thumb_asset_id
                    item.lyricsAssetId = readExtraInt64(meta.extra_data, "lyrics_asset_id")
                    item.hidden = meta.hidden_in_files
                    if (meta.sort_index > 0) {
                        item.hasSort = true
                        item.sortIndex = meta.sort_index
                    }
                case None => ()
            }

            // Prefer sidecar image thumb (e.g. *-thumb.jpg) for matching media entries.
            let mediaBaseKey = normalizeSidecarBaseKey(href)
            if (mediaBaseKey.size > 0) {
                match (sidecarThumbByBase.get(mediaBaseKey)) {
                    case Some(sidecarThumbAssetId) =>
                        if (sidecarThumbAssetId > 0) {
                            item.thumbAssetId = sidecarThumbAssetId
                        }
                    case None => ()
                }
            }

            if (item.hidden) {
                continue
            }
            if (item.hasSort) {
                withSort.add(item)
            } else {
                withoutSort.add(item)
            }
        }

        var pageFiles = ArrayList<ArchiveFilesPageItem>()
        if (withSort.size > 0) {
            var used = HashSet<Int64>()
            while (Int64(used.size) < Int64(withSort.size)) {
                var found = false
                var bestIdx: Int64 = -1
                var bestSort: Int32 = 0
                var bestOrder: Int32 = 0
                for (i in 0..withSort.size) {
                    let idx = i
                    if (used.contains(idx)) {
                        continue
                    }
                    let item = withSort[idx]
                    if (!found ||
                        item.sortIndex < bestSort ||
                        (item.sortIndex == bestSort && item.originalIndex < bestOrder)) {
                        found = true
                        bestIdx = idx
                        bestSort = item.sortIndex
                        bestOrder = item.originalIndex
                    }
                }
                if (!found) {
                    break
                }
                pageFiles.add(withSort[bestIdx])
                used.add(bestIdx)
            }
        }
        for (item in withoutSort) {
            pageFiles.add(item)
        }

        var filteredPageFiles = ArrayList<ArchiveFilesPageItem>()
        for (item in pageFiles) {
            let fileType = resolveArchiveFileType(archive.archive_type, item.href)
            if (imagesOnlySpecified && imagesOnly && fileType != "image") {
                continue
            }
            filteredPageFiles.add(item)
        }

        var responsePageFiles = ArrayList<ArchiveFilesPageItem>()
        let offsetInt = Int64(offset)
        let endExclusive = if (limit > 0i32) { Int64(offset + limit) } else { Int64(filteredPageFiles.size) }
        for (i in 0..filteredPageFiles.size) {
            let idx = Int64(i)
            if (idx < offsetInt) {
                continue
            }
            if (idx >= endExclusive) {
                break
            }
            responsePageFiles.add(filteredPageFiles[i])
        }

        // 构建响应JSON（JsonWriter）
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("pages")
        w.startArray()
        for (item in responsePageFiles) {
            let href = item.href
            let title = item.title
            let metadataTitle = item.title
            let metadataDescription = item.description
            let metadataThumbAssetId = item.thumbAssetId
            let fileType = if (archive.archive_type == ArchiveTypes.EPUB) {
                "html"
            } else {
                resolveArchiveFileType(archive.archive_type, href)
            }

            w.startObject()
            w.writeName("path").writeValue(href)
            w.writeName("type").writeValue(fileType)
            w.writeName("title").writeValue(title)
            if (includeMetadata) {
                w.writeName("metadata")
                w.startObject()
                w.writeName("title").writeValue(metadataTitle)
                w.writeName("description").writeValue(metadataDescription)
                w.writeName("thumb_asset_id").writeValue(metadataThumbAssetId)
                w.writeName("lyrics_asset_id").writeValue(item.lyricsAssetId)
                w.writeName("release_at").writeValue(item.releaseAt)
                w.endObject()
            }
            w.endObject()
        }
        w.endArray()
        w.endObject()
        w.flush()
        ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
    }

    // DELETE /api/archives/{id}
    public static func deleteArchive(ctx: Ctx): Unit {
        // 检查管理员权限
        match (AuthMiddleware.requireAdmin(ctx)) {
            case Some(userId) =>
                let id = ctx.paramsOpt("id").getOrThrow()

                // 检查ID是否为空
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"delete_archive\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 检查归档是否存在
                let archive = ArchiveModel.getArchiveById(id)
                if (archive.id.size == 0) {
                    let errorResponse = "{\"operation\":\"delete_archive\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 获取归档的数据库内部ID
                let archiveIdInt = getArchiveInternalId(id)
                if (archiveIdInt <= 0) {
                    let errorResponse = "{\"operation\":\"delete_archive\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 删除相关数据
                // 1. 删除用户收藏
                UserFavoriteDao.deleteByArchiveId(archiveIdInt)

                // 2. 删除用户阅读状态
                UserArchiveStatusDao.deleteByArchiveId(archiveIdInt)

                // 3. 删除标签关联（通过更新空标签实现）
                TagDao.updateArchiveTags(id, "")

                // Keep all necessary data before deleting the archive row.
                // IMPORTANT: Must get archivePath BEFORE deleting from database,
                // because getArchiveBasePath() queries the archives table.
                let rootAssetIds = HashSet<Int64>()
                match (MetadataDao.getMetadataObject("archive", id)) {
                    case Some(metadata) =>
                        for (asset in metadata.assets) {
                            if (asset.asset_id > 0) {
                                rootAssetIds.add(asset.asset_id)
                            }
                        }
                    case None => ()
                }
                let coverAssetId = ArchiveDao.getCoverAssetId(id)
                if (coverAssetId > 0) {
                    rootAssetIds.add(coverAssetId)
                }
                let pageThumbAssetIds = MetadataDao.getPageThumbAssetIds(id)
                let pageLyricsAssetIds = MetadataDao.getPageLyricsAssetIds(id)
                let archivePath = getArchiveBasePath(archive.id)

                // 4. 删除档案记录
                let deleteSuccess = ArchiveDao.delete(id)

                // 5. 删除相关文件（缩略图和原始档案）
                if (deleteSuccess) {
                    let _ = MetadataDao.deletePageMetadata(id)
                    let _ = MetadataDao.deleteEntity("archive", id)
                    for (assetId in pageThumbAssetIds) {
                        if (assetId > 0) {
                            rootAssetIds.add(assetId)
                        }
                    }
                    for (assetId in pageLyricsAssetIds) {
                        if (assetId > 0) {
                            rootAssetIds.add(assetId)
                        }
                    }
                    for (assetId in rootAssetIds) {
                        if (assetId > 0) {
                            PluginTaskService.deleteCoverAsset(assetId)
                        }
                    }

                    // 删除原始档案文件
                    try {
                        if (archivePath.size > 0) {
                            let fullArchivePath = if (archive.relative_path.size > 0) {
                                "${archivePath}/${archive.relative_path}/${archive.filename}"
                            } else {
                                "${archivePath}/${archive.filename}"
                            }
                            remove(Path(fullArchivePath))
                            getLogger("archive_controller").info("Deleted archive file", ("path", fullArchivePath), ("arcid", id))
                        } else {
                            getLogger("archive_controller").warn("Archive path is empty, skipping file deletion", ("arcid", id), ("filename", archive.filename))
                        }
                    } catch (e: Exception) {
                        getLogger("archive_controller").warn("Failed to delete archive file", ("arcid", id), ("error", e.message))
                    }
                }

                if (deleteSuccess) {
                    let result = "{\"operation\":\"delete_archive\",\"success\":1}"
                    ResponseView.json(ctx, result)
                } else {
                    let errorResponse = "{\"operation\":\"delete_archive\",\"error\":\"Failed to delete archive\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ResponseView.json(ctx, errorResponse)
                }
            case None => return  // requireAdmin 已经设置了错误响应
        }
    }

    // GET /api/archives/{id}/download
    // 大文件阈值：5MB
    private static let CHUNKED_THRESHOLD: Int64 = 5 * 1024 * 1024
    // 分块大小：1MB
    private static let CHUNK_SIZE: Int64 = 1024 * 1024

    public static func downloadArchive(ctx: Ctx): Unit {
        let id = ctx.paramsOpt("id").getOrThrow()

        // 检查ID是否为空
        if (id.size == 0) {
            let errorResponse = "{\"operation\":\"download_archive\",\"error\":\"No archive ID specified.\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, errorResponse)
            return
        }

        // 检查归档是否存在
        let archive = ArchiveModel.getArchiveById(id)
        if (archive.id.size == 0) {
            let errorResponse = "{\"operation\":\"download_archive\",\"error\":\"Archive not found\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ResponseView.json(ctx, errorResponse)
            return
        }

        // 构建归档文件完整路径（从分类获取基础路径）
        let archivePath = getArchiveBasePath(archive.id)
        if (archivePath.size == 0) {
            ctx.status(500)
            ResponseView.json(ctx, "{\"success\":0,\"error\":\"Category not found for archive\"}")
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
            ResponseView.json(ctx, errorResponse)
        }
    }

    /**
     * 小文件下载：一次性读取到内存返回
     */
    private static func downloadArchiveSmall(ctx: Ctx, file: File, fileSize: Int64, filename: String): Unit {
        let buffer = Array<Byte>(fileSize, {_ => 0})
        file.read(buffer)
        file.close()

        // 设置响应头
        ctx.setHeader("Content-Type", "application/octet-stream")
        ctx.setHeader("Content-Disposition", "attachment; filename=\"${filename}\"")
        ctx.setHeader("Content-Length", "${fileSize}")
        ctx.status(HttpStatusCode.STATUS_OK)

        // 返回文件内容
        ctx.send(buffer)
    }

    /**
     * 大文件下载：使用 chunked 分块传输，流式读取不占用大量内存
     */
    private static func downloadArchiveChunked(ctx: Ctx, file: File, fileSize: Int64, filename: String): Unit {
        // 设置响应头（在获取 writer 之前设置）
        ctx.setHeader("Content-Type", "application/octet-stream")
        ctx.setHeader("Content-Disposition", "attachment; filename=\"${filename}\"")
        ctx.status(HttpStatusCode.STATUS_OK)

        // 获取 writer
        let writer = ctx.writer()

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

        // 关闭文件
        file.close()
    }

    // GET /api/archives/{id}/page?path=...
    public static func getPage(ctx: Ctx): Unit {
        let id = ctx.paramsOpt("id").getOrThrow()

        // 检查ID是否为空
        if (id.size == 0) {
            let errorResponse = "{\"operation\":\"serve_page\",\"error\":\"No archive ID specified.\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, errorResponse)
            return
        }

        // 获取查询参数
        let pathParam = ctx.query("path")
        match (pathParam) {
            case Some(path) => getPageInternal(ctx, id, path)
            case None =>
                let errorResponse = "{\"operation\":\"serve_page\",\"error\":\"No path specified.\",\"success\":0}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
        }
    }

    /**
     * getPage 内部实现
     */
    private static func getPageInternal(ctx: Ctx, id: String, path: String): Unit {
        if (path.size == 0) {
            let errorResponse = "{\"operation\":\"serve_page\",\"error\":\"No path specified.\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, errorResponse)
            return
        }

        // 检查归档是否存在（使用ArchiveDao以获取archive_type）
        let archive = ArchiveDao.getArchiveById(id)
        if (archive.id.size == 0) {
            let errorResponse = "{\"operation\":\"serve_page\",\"error\":\"Archive not found\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ResponseView.json(ctx, errorResponse)
            return
        }

        // 构建归档文件完整路径
        let archivePath = getArchiveBasePath(archive.id)
        if (archivePath.size == 0) {
            ctx.status(500)
            ResponseView.json(ctx, "{\"success\":0,\"error\":\"Category not found for archive\"}")
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

            let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archive.archive_type)
            // 使用 Handler 获取流式读取器
            let (exitCode, readerOpt, errorMsg) = handler.getEntryReader(actualPath, path)

            if (exitCode == 0) {
                match (readerOpt) {
                    case Some(reader) => sendPageDataWithReader(ctx, id, path, reader)
                    case None =>
                        CacheUtils.setNoCacheHeaders(ctx)
                        ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                        ResponseView.json(ctx, "{\"operation\":\"serve_page\",\"error\":\"Reader is null\",\"success\":0}")
                }
            } else {
                CacheUtils.setNoCacheHeaders(ctx)
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ResponseView.json(ctx, "{\"operation\":\"serve_page\",\"error\":\"${errorMsg}\",\"success\":0}")
            }
        } catch (e: Exception) {
            CacheUtils.setNoCacheHeaders(ctx)
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ResponseView.json(ctx, "{\"operation\":\"serve_page\",\"error\":\"Exception: ${e.message}\",\"success\":0}")
        }
    }

    /**
     * 使用 EntryReader 发送页面数据，支持真正的流式分块传输
     */
    private static func sendPageDataWithReader(
        ctx: Ctx,
        id: String,
        path: String,
        reader: EntryReader
    ): Unit {
        let fileSize = reader.getSize()
        let contentType = getContentTypeFromPath(path)
        let etag = CacheUtils.generateETag("${id}-${path}-${fileSize}")

        // 检查缓存
        if (CacheUtils.checkIfNoneMatch(ctx, etag)) {
            reader.close()
            CacheUtils.sendNotModifiedDynamic(ctx, etag)
            return
        }

        // 支持 HTTP Range（仅单区间），用于视频拖动/断点播放
        let rangeHeader = (ctx.header("Range") ?? "").trimAscii()
        let (rangeState, rangeStart, rangeEnd) = parseRangeHeader(rangeHeader, fileSize)
        if (rangeState < 0) {
            reader.close()
            sendRangeNotSatisfiable(ctx, fileSize)
            return
        }
        if (rangeState > 0) {
            sendWithReaderChunkedRange(ctx, reader, contentType, etag, fileSize, rangeStart, rangeEnd)
            return
        }

        // 统一使用流式传输，避免大缓冲区占用内存
        // 小文件也可以使用流式传输，性能影响可忽略，但能避免内存峰值问题
        sendWithReaderChunked(ctx, reader, contentType, etag)
    }

    /**
     * 大文件：使用 chunked 流式传输
     */
    private static func sendWithReaderChunked(
        ctx: Ctx,
        reader: EntryReader,
        contentType: String,
        etag: String
    ): Unit {
        // 设置响应头（在获取 writer 之前）
        ctx.setHeader("Content-Type", contentType)
        ctx.setHeader("ETag", etag)
        ctx.setHeader("Cache-Control", "private, max-age=3600")
        ctx.setHeader("Accept-Ranges", "bytes")
        ctx.status(HttpStatusCode.STATUS_OK)

        let writer = ctx.writer()

        // 分块读取并发送
        let chunkBuffer = Array<Byte>(CHUNK_SIZE, {_ => 0})

        while (true) {
            let bytesRead = reader.read(chunkBuffer)
            if (bytesRead <= 0) {
                break
            }

            if (bytesRead == CHUNK_SIZE) {
                // 完整块
                writer.write(chunkBuffer)
            } else {
                // 最后一块，可能不足 CHUNK_SIZE
                let lastChunk = Array<Byte>(bytesRead, { i => chunkBuffer[i] })
                writer.write(lastChunk)
            }
        }

        reader.close()
    }

    /**
     * Range 请求：按指定区间发送数据（206 Partial Content）
     */
    private static func sendWithReaderChunkedRange(
        ctx: Ctx,
        reader: EntryReader,
        contentType: String,
        etag: String,
        fileSize: Int64,
        rangeStart: Int64,
        rangeEnd: Int64
    ): Unit {
        // 先跳过前置字节；EntryReader 不一定支持 seek，这里用读取丢弃实现
        if (!skipReaderBytes(reader, rangeStart)) {
            reader.close()
            sendRangeNotSatisfiable(ctx, fileSize)
            return
        }

        // 设置响应头（在获取 writer 之前）
        ctx.setHeader("Content-Type", contentType)
        ctx.setHeader("ETag", etag)
        ctx.setHeader("Cache-Control", "private, max-age=3600")
        ctx.setHeader("Accept-Ranges", "bytes")
        ctx.setHeader("Content-Range", "bytes ${rangeStart}-${rangeEnd}/${fileSize}")
        ctx.status(HttpStatusCode.STATUS_PARTIAL_CONTENT)

        let writer = ctx.writer()

        var remaining = rangeEnd - rangeStart + 1
        let chunkBuffer = Array<Byte>(CHUNK_SIZE, {_ => 0})

        while (remaining > 0) {
            let toRead = if (remaining > CHUNK_SIZE) { CHUNK_SIZE } else { remaining }

            if (toRead == CHUNK_SIZE) {
                let bytesRead = reader.read(chunkBuffer)
                if (bytesRead <= 0) {
                    break
                }
                if (bytesRead <= remaining) {
                    writer.write(chunkBuffer.slice(0, bytesRead))
                    remaining -= bytesRead
                } else {
                    writer.write(chunkBuffer.slice(0, remaining))
                    remaining = 0
                }
            } else {
                let lastChunk = Array<Byte>(toRead, {_ => 0})
                let bytesRead = reader.read(lastChunk)
                if (bytesRead <= 0) {
                    break
                }
                if (bytesRead <= remaining) {
                    writer.write(lastChunk.slice(0, bytesRead))
                    remaining -= bytesRead
                } else {
                    writer.write(lastChunk.slice(0, remaining))
                    remaining = 0
                }
            }
        }

        reader.close()
    }

    /**
     * 跳过指定字节数（通过读取并丢弃）
     */
    private static func skipReaderBytes(reader: EntryReader, skipBytes: Int64): Bool {
        if (skipBytes <= 0) {
            return true
        }
        let skipBuffer = Array<Byte>(CHUNK_SIZE, {_ => 0})
        var remaining = skipBytes
        while (remaining > 0) {
            let toRead = if (remaining > CHUNK_SIZE) { CHUNK_SIZE } else { remaining }
            if (toRead == CHUNK_SIZE) {
                let bytesRead = reader.read(skipBuffer)
                if (bytesRead <= 0) {
                    return false
                }
                remaining -= bytesRead
            } else {
                let tmp = Array<Byte>(toRead, {_ => 0})
                let bytesRead = reader.read(tmp)
                if (bytesRead <= 0) {
                    return false
                }
                remaining -= bytesRead
            }
        }
        return true
    }

    /**
     * 解析 Range 请求头。
     * 返回值：(state, start, end)
     * - state = 1: 有效单区间
     * - state = 0: 无 Range 或不处理
     * - state = -1: Range 无效（应返回 416）
     */
    private static func parseRangeHeader(rangeHeader: String, fileSize: Int64): (Int32, Int64, Int64) {
        if (fileSize <= 0) {
            return (0i32, 0i64, 0i64)
        }

        let header = rangeHeader.trimAscii()
        if (header.size == 0) {
            return (0i32, 0i64, 0i64)
        }
        if (!header.startsWith("bytes=")) {
            return (0i32, 0i64, 0i64)
        }

        let spec = header[6..header.size].trimAscii()
        if (spec.size == 0 || spec.contains(",")) {
            return (-1i32, 0i64, 0i64)
        }

        match (spec.indexOf("-")) {
            case Some(dashIdx) =>
                let startPart = spec[0..dashIdx].trimAscii()
                let endPart = spec[(dashIdx + 1)..spec.size].trimAscii()

                // bytes=-N（后缀长度）
                if (startPart.size == 0) {
                    if (endPart.size == 0) {
                        return (-1i32, 0i64, 0i64)
                    }
                    var suffixLen: Int64 = 0
                    try {
                        suffixLen = Int64.parse(endPart)
                    } catch (_: Exception) {
                        return (-1i32, 0i64, 0i64)
                    }
                    if (suffixLen <= 0) {
                        return (-1i32, 0i64, 0i64)
                    }
                    let start = if (suffixLen >= fileSize) { 0i64 } else { fileSize - suffixLen }
                    return (1i32, start, fileSize - 1)
                }

                // bytes=START- 或 bytes=START-END
                var start: Int64 = 0
                try {
                    start = Int64.parse(startPart)
                } catch (_: Exception) {
                    return (-1i32, 0i64, 0i64)
                }
                if (start < 0 || start >= fileSize) {
                    return (-1i32, 0i64, 0i64)
                }

                var end = fileSize - 1
                if (endPart.size > 0) {
                    try {
                        end = Int64.parse(endPart)
                    } catch (_: Exception) {
                        return (-1i32, 0i64, 0i64)
                    }
                    if (end < start) {
                        return (-1i32, 0i64, 0i64)
                    }
                    if (end >= fileSize) {
                        end = fileSize - 1
                    }
                }
                return (1i32, start, end)
            case None =>
                return (-1i32, 0i64, 0i64)
        }
    }

    /**
     * 返回 416 Range Not Satisfiable
     */
    private static func sendRangeNotSatisfiable(ctx: Ctx, fileSize: Int64): Unit {
        ctx.status(416)
        ctx.setHeader("Accept-Ranges", "bytes")
        if (fileSize >= 0) {
            ctx.setHeader("Content-Range", "bytes */${fileSize}")
        }
        ctx.sendString("")
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
        // 音频类型
        } else if (lowerPath.endsWith(".mp3")) {
            return "audio/mpeg"
        } else if (lowerPath.endsWith(".flac")) {
            return "audio/flac"
        } else if (lowerPath.endsWith(".m4a")) {
            return "audio/mp4"
        } else if (lowerPath.endsWith(".aac")) {
            return "audio/aac"
        } else if (lowerPath.endsWith(".ogg")) {
            return "audio/ogg"
        } else if (lowerPath.endsWith(".opus")) {
            return "audio/opus"
        } else if (lowerPath.endsWith(".wav")) {
            return "audio/wav"
        } else if (lowerPath.endsWith(".wma")) {
            return "audio/x-ms-wma"
        } else if (lowerPath.endsWith(".ape")) {
            return "audio/ape"
        } else if (lowerPath.endsWith(".alac")) {
            return "audio/alac"
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
    public static func setIsNew(ctx: Ctx): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.paramsOpt("id").getOrThrow()

                // 检查ID是否为空
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"set_isnew\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 检查归档是否存在
                let archive = ArchiveModel.getArchiveById(id)
                if (archive.id.size == 0) {
                    let errorResponse = "{\"operation\":\"set_isnew\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 获取归档的数据库内部ID
                let archiveIdInt = getArchiveInternalId(id)
                if (archiveIdInt <= 0) {
                    let errorResponse = "{\"operation\":\"set_isnew\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 更新用户级别的isNew标记为true
                let updateSuccess = UserArchiveStatusDao.setIsNew(userId, archiveIdInt)

                if (updateSuccess) {
                    let result = "{\"operation\":\"set_isnew\",\"success\":1}"
                    ResponseView.json(ctx, result)
                } else {
                    let errorResponse = "{\"operation\":\"set_isnew\",\"error\":\"Failed to set isNew flag\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ResponseView.json(ctx, errorResponse)
                }
            case None => return  // requireUser 已经设置了错误响应
        }
    }

    /**
     * 清除归档的isNew标记（DELETE /api/archives/{id}/isnew）
     * 现在使用用户级别的已读状态
     */
    public static func clearIsNew(ctx: Ctx): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.paramsOpt("id").getOrThrow()

                // 检查ID是否为空
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"clear_isnew\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 检查归档是否存在
                let archive = ArchiveModel.getArchiveById(id)
                if (archive.id.size == 0) {
                    let errorResponse = "{\"operation\":\"clear_isnew\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 获取归档的数据库内部ID
                let archiveIdInt = getArchiveInternalId(id)
                if (archiveIdInt <= 0) {
                    let errorResponse = "{\"operation\":\"clear_isnew\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 更新用户级别的isNew标记为false
                let updateSuccess = UserArchiveStatusDao.clearIsNew(userId, archiveIdInt)

                if (updateSuccess) {
                    let result = "{\"operation\":\"clear_isnew\",\"success\":1}"
                    ResponseView.json(ctx, result)
                } else {
                    let errorResponse = "{\"operation\":\"clear_isnew\",\"error\":\"Failed to clear isNew flag\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ResponseView.json(ctx, errorResponse)
                }
            case None => return  // requireUser 已经设置了错误响应
        }
    }

    /**
     * 更新用户阅读进度并自动标记为已读（PUT /api/archives/{id}/progress/{page}）
     */
    public static func updateProgress(ctx: Ctx): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.paramsOpt("id").getOrThrow()
                let pageParam = ctx.paramsOpt("page").getOrThrow()

                // 检查ID和页数参数
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"update_progress\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                if (pageParam.size == 0) {
                    let errorResponse = "{\"operation\":\"update_progress\",\"error\":\"No page specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 解析页数为整数
                var progress = try {
                    Int32.parse(pageParam)
                } catch (e: Exception) {
                    let errorResponse = "{\"operation\":\"update_progress\",\"error\":\"Invalid page number\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 检查归档是否存在
                let archive = ArchiveModel.getArchiveById(id)
                if (archive.id.size == 0) {
                    let errorResponse = "{\"operation\":\"update_progress\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 获取归档的数据库内部ID
                let archiveIdInt = getArchiveInternalId(id)
                if (archiveIdInt <= 0) {
                    let errorResponse = "{\"operation\":\"update_progress\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ResponseView.json(ctx, errorResponse)
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
                    ResponseView.json(ctx, result)
                } else {
                    let errorResponse = "{\"operation\":\"update_progress\",\"error\":\"Failed to update progress\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ResponseView.json(ctx, errorResponse)
                }
            case None => return  // requireUser 已经设置了错误响应
        }
    }

    /**
     * 添加收藏（PUT /api/archives/{id}/favorite）
     */
    public static func addFavorite(ctx: Ctx): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.paramsOpt("id").getOrThrow()

                // 检查ID是否为空
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"add_favorite\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 检查归档是否存在
                let archive = ArchiveModel.getArchiveById(id)
                if (archive.id.size == 0) {
                    let errorResponse = "{\"operation\":\"add_favorite\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 获取归档的数据库内部ID
                let archiveIdInt = getArchiveInternalId(id)
                if (archiveIdInt <= 0) {
                    let errorResponse = "{\"operation\":\"add_favorite\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 添加收藏
                let addSuccess = UserFavoriteDao.addFavorite(userId, archiveIdInt)

                if (addSuccess) {
                    let result = "{\"operation\":\"add_favorite\",\"success\":1}"
                    ResponseView.json(ctx, result)
                } else {
                    let errorResponse = "{\"operation\":\"add_favorite\",\"error\":\"Failed to add favorite\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ResponseView.json(ctx, errorResponse)
                }
            case None => return  // requireUser 已经设置了错误响应
        }
    }

    /**
     * 取消收藏（DELETE /api/archives/{id}/favorite）
     */
    public static func removeFavorite(ctx: Ctx): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.paramsOpt("id").getOrThrow()

                // 检查ID是否为空
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"remove_favorite\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 获取归档的数据库内部ID
                let archiveIdInt = getArchiveInternalId(id)
                if (archiveIdInt <= 0) {
                    let errorResponse = "{\"operation\":\"remove_favorite\",\"error\":\"Archive not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // 取消收藏
                let removeSuccess = UserFavoriteDao.removeFavorite(userId, archiveIdInt)

                if (removeSuccess) {
                    let result = "{\"operation\":\"remove_favorite\",\"success\":1}"
                    ResponseView.json(ctx, result)
                } else {
                    let errorResponse = "{\"operation\":\"remove_favorite\",\"error\":\"Failed to remove favorite\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ResponseView.json(ctx, errorResponse)
                }
            case None => return  // requireUser 已经设置了错误响应
        }
    }

    /**
     * 获取用户的所有收藏（GET /api/favorites）
     * 返回收藏的 arcid 列表（兼容旧接口）
     */
    public static func getFavorites(ctx: Ctx): Unit {
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
                ResponseView.json(ctx, result)
            case None => return  // requireUser 已经设置了错误响应
        }
    }

    /**
     * 获取用户收藏的档案详情列表（GET /api/favorites/archives）
     * 支持分页，返回完整的档案信息
     */
    public static func getFavoriteArchives(ctx: Ctx): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                // 获取分页参数
                let startParam = ctx.query("start")
                let countParam = ctx.query("count")

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
                let archiveIds = ArrayList<String>()
                for (archive in archives) {
                    if (archive.id.size > 0) {
                        archiveIds.add(archive.id)
                    }
                }
                let assetsMap = ArchiveDao.getBatchArchiveAssetsRaw(archiveIds.toArray())

                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("operation").writeValue("get_favorite_archives")
                w.writeName("data")
                w.startArray()
                for (archive in archives) {
                    let archiveIdInt = getArchiveInternalId(archive.id)
                    let isNew = if (archiveIdInt > 0) { UserArchiveStatusDao.isNew(userId, archiveIdInt) } else { true }

                    w.startObject()
                    w.writeName("arcid").writeValue(archive.id)
                    w.writeName("title").writeValue(archive.title)
                    w.writeName("filename").writeValue(archive.filename)
                    w.writeName("description").writeValue(archive.summary)
                    w.writeName("thumbhash").writeValue(archive.thumbhash)
                    w.writeName("tags").writeValue(archive.tags)
                    w.writeName("isnew").writeValue(isNew)
                    w.writeName("isfavorite").writeValue(true)
                    w.writeName("pagecount").writeValue(archive.pagecount)
                    w.writeName("progress").writeValue(archive.progress)
                    w.writeName("file_size").writeValue(archive.file_size)
                    let assetsRaw = match (assetsMap.get(archive.id)) {
                        case Some(raw) => raw
                        case None => "{}"
                    }
                    writeArchiveAssetsJson(w, assetsRaw)
                    w.writeName("release_at").writeValue(archive.release_at)
                    w.writeName("created_at").writeValue(archive.created_at)
                    w.writeName("updated_at").writeValue(archive.updated_at)
                    w.writeName("last_read_time").writeValue(archive.last_read_time)
                    w.endObject()
                }
                w.endArray()
                w.writeName("recordsTotal").writeValue(totalCount)
                w.writeName("recordsFiltered").writeValue(totalCount)
                w.writeName("success").writeValue(1)
                w.endObject()
                w.flush()
                ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
            case None => return  // requireUser 已经设置了错误响应
        }
    }

    /**
     * 获取用户已读的档案列表（GET /api/read_archives）
     * 支持分页，返回完整的档案信息
     */
    public static func getReadArchives(ctx: Ctx): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                // 获取分页参数
                let startParam = ctx.query("start")
                let countParam = ctx.query("count")

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
                let archiveIds = ArrayList<String>()
                for (archive in archives) {
                    if (archive.id.size > 0) {
                        archiveIds.add(archive.id)
                    }
                }
                let assetsMap = ArchiveDao.getBatchArchiveAssetsRaw(archiveIds.toArray())

                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("operation").writeValue("get_read_archives")
                w.writeName("data")
                w.startArray()
                for (archive in archives) {
                    let archiveIdInt = getArchiveInternalId(archive.id)
                    let isFavorite = if (archiveIdInt > 0) { UserFavoriteDao.isFavorite(userId, archiveIdInt) } else { false }

                    w.startObject()
                    w.writeName("arcid").writeValue(archive.id)
                    w.writeName("title").writeValue(archive.title)
                    w.writeName("filename").writeValue(archive.filename)
                    w.writeName("description").writeValue(archive.summary)
                    w.writeName("thumbhash").writeValue(archive.thumbhash)
                    w.writeName("tags").writeValue(archive.tags)
                    w.writeName("isnew").writeValue(false)
                    w.writeName("isfavorite").writeValue(isFavorite)
                    w.writeName("pagecount").writeValue(archive.pagecount)
                    w.writeName("progress").writeValue(archive.progress)
                    w.writeName("file_size").writeValue(archive.file_size)
                    let assetsRaw = match (assetsMap.get(archive.id)) {
                        case Some(raw) => raw
                        case None => "{}"
                    }
                    writeArchiveAssetsJson(w, assetsRaw)
                    w.writeName("release_at").writeValue(archive.release_at)
                    w.writeName("created_at").writeValue(archive.created_at)
                    w.writeName("updated_at").writeValue(archive.updated_at)
                    w.writeName("last_read_time").writeValue(archive.last_read_time)
                    w.endObject()
                }
                w.endArray()
                w.writeName("recordsTotal").writeValue(totalCount)
                w.writeName("recordsFiltered").writeValue(totalCount)
                w.writeName("success").writeValue(1)
                w.endObject()
                w.flush()
                ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
            case None => return  // requireUser 已经设置了错误响应
        }
    }
}

private class ArchiveFilesPageItem {
    public var href: String = ""
    public var title: String = ""
    public var description: String = ""
    public var releaseAt: String = ""
    public var thumbAssetId: Int64 = 0
    public var lyricsAssetId: Int64 = 0
    public var sortIndex: Int32 = 0
    public var originalIndex: Int32 = 0
    public var hidden: Bool = false
    public var hasSort: Bool = false
}
