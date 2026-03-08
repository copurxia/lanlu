package lanlu.contexts.archive.interfaces.http

import stdx.net.http.HttpStatusCode
import ignite.*
import lanlu.contexts.archive.domain.*
import lanlu.contexts.tankoubon.domain.*
import lanlu.contexts.plugin.domain.*
import lanlu.contexts.plugin.application.*
import lanlu.contexts.system.application.*
import lanlu.shared.utils.*
import lanlu.shared.views.*
import lanlu.contexts.archive.infrastructure.persistence.*
import lanlu.contexts.user.infrastructure.persistence.*
import lanlu.contexts.asset.infrastructure.persistence.*
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

public class ArchivePagePatchInput {
    public var path: String = ""
    public var title: String = ""
    public var description: String = ""
    public var thumb: String = ""
    public var sort: Int32 = 0
    public var sortProvided: Bool = false
    public var hiddenInFiles: Bool = false
    public var hiddenInFilesProvided: Bool = false

    public init() {}
}

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

    private static func parsePagePatchesFromUpdateRequestBody(requestBody: String): Array<ArchivePagePatchInput> {
        let body = requestBody.trimAscii()
        if (body.size == 0) {
            return Array<ArchivePagePatchInput>()
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(body.rawData()) }
            let r = JsonReader(buf)

            func readBoolFlexible(): Bool {
                let v = r.readValue<String>().trimAscii().toAsciiLower()
                return v == "true" || v == "1"
            }

            func readStringFlexible(): String {
                match (r.peek()) {
                    case Some(BeginObject) =>
                        let bytes = r.readValueBytes()
                        return String.fromUtf8(bytes)
                    case Some(BeginArray) =>
                        let bytes = r.readValueBytes()
                        return String.fromUtf8(bytes)
                    case Some(_) => return r.readValue<String>()
                    case None => return ""
                }
            }

            func readInt32Flexible(): Int32 {
                let s = readStringFlexible().trimAscii()
                try { return Int32.parse(s) } catch (_: Exception) { return 0 }
            }

            func parsePagePatchObject(): ArchivePagePatchInput {
                let patch = ArchivePagePatchInput()
                if (r.peek() != Some(BeginObject)) {
                    return patch
                }

                r.startObject()
                while (r.peek() != EndObject) {
                    let pk = r.readName()
                    match (pk) {
                        case "path" => patch.path = readStringFlexible().trimAscii()
                        case "entry" => patch.path = readStringFlexible().trimAscii()
                        case "entry_path" => patch.path = readStringFlexible().trimAscii()
                        case "entryPath" => patch.path = readStringFlexible().trimAscii()
                        case "title" => patch.title = readStringFlexible()
                        case "description" => patch.description = readStringFlexible()
                        case "thumb" => patch.thumb = readStringFlexible().trimAscii()
                        case "sort" =>
                            patch.sort = readInt32Flexible()
                            patch.sortProvided = true
                        case "hidden_in_files" =>
                            patch.hiddenInFiles = readBoolFlexible()
                            patch.hiddenInFilesProvided = true
                        case "hiddenInFiles" =>
                            patch.hiddenInFiles = readBoolFlexible()
                            patch.hiddenInFilesProvided = true
                        case "metadata" =>
                            if (r.peek() == Some(BeginObject)) {
                                r.startObject()
                                while (r.peek() != EndObject) {
                                    let mk = r.readName()
                                    match (mk) {
                                        case "thumb" =>
                                            let nestedThumb = readStringFlexible().trimAscii()
                                            if (patch.thumb.trimAscii().size == 0 && nestedThumb.size > 0) {
                                                patch.thumb = nestedThumb
                                            }
                                        case _ => r.skip()
                                    }
                                }
                                r.endObject()
                            } else {
                                r.skip()
                            }
                        case _ => r.skip()
                    }
                }
                r.endObject()
                return patch
            }

            if (r.peek() != Some(BeginObject)) {
                return Array<ArchivePagePatchInput>()
            }

            var pages = ArrayList<ArchivePagePatchInput>()
            r.startObject()
            while (r.peek() != EndObject) {
                let key = r.readName()
                match (key) {
                    case "pages" =>
                        if (r.peek() == Some(BeginArray)) {
                            r.startArray()
                            while (r.peek() != EndArray) {
                                let patch = parsePagePatchObject()
                                if (patch.path.trimAscii().size > 0) {
                                    pages.add(patch)
                                }
                            }
                            r.endArray()
                        } else {
                            r.skip()
                        }
                    case _ => r.skip()
                }
            }
            r.endObject()
            return pages.toArray()
        } catch (e: Exception) {
            getLogger("archive_controller").warn("Failed to parse update metadata pages", ("error", e.message))
            return Array<ArchivePagePatchInput>()
        }
    }

    private static func persistPagePatchesForArchive(arcid: String, pluginNamespace: String, pagePatches: Array<ArchivePagePatchInput>): Bool {
        if (pagePatches.size == 0) {
            return true
        }

        let archiveInternalId = ArchiveModel.getArchiveIdByArcid(arcid)
        if (archiveInternalId <= 0) {
            return false
        }

        var saveIndex: Int64 = 0
        for (patch in pagePatches) {
            let entryPath = patch.path.trimAscii()
            if (entryPath.size == 0) {
                continue
            }
            saveIndex += 1

            let existingMeta = ArchivePageMetadataDao.getByArchiveAndPath(archiveInternalId, entryPath)
            var titleToSave = patch.title
            var descriptionToSave = patch.description
            var thumbAssetId: Int64 = 0
            var thumbHash = ""
            var sortIndex: Int32 = 0
            var hiddenInFiles = false

            match (existingMeta) {
                case Some(existing) =>
                    if (titleToSave.trimAscii().size == 0) {
                        titleToSave = existing.title
                    }
                    if (descriptionToSave.trimAscii().size == 0) {
                        descriptionToSave = existing.description
                    }
                    thumbAssetId = existing.thumb_asset_id
                    thumbHash = existing.thumbhash
                    sortIndex = existing.sort_index
                    hiddenInFiles = existing.hidden_in_files
                case None => ()
            }

            if (patch.sortProvided) {
                sortIndex = patch.sort
            }
            if (patch.hiddenInFilesProvided) {
                hiddenInFiles = patch.hiddenInFiles
            }

            let patchThumb = patch.thumb.trimAscii()
            if (patchThumb.size > 0) {
                var directAssetId: Int64 = 0
                try { directAssetId = Int64.parse(patchThumb) } catch (_: Exception) { directAssetId = 0 }
                if (directAssetId > 0) {
                    thumbAssetId = directAssetId
                    thumbHash = ""
                } else if (pluginNamespace.trimAscii().size > 0) {
                    let oldThumbAssetId = thumbAssetId
                    let (okThumb, newThumbAssetId, newThumbHash, thumbErr) = PluginCoverUtils.installCoverAssetFromPluginPath(
                        patchThumb,
                        pluginNamespace,
                        "page_thumb",
                        "${arcid}_${saveIndex.toString()}.avif"
                    )
                    if (okThumb && newThumbAssetId > 0) {
                        thumbAssetId = newThumbAssetId
                        thumbHash = newThumbHash
                        if (oldThumbAssetId > 0 && oldThumbAssetId != newThumbAssetId) {
                            PluginCoverUtils.deleteAsset(oldThumbAssetId)
                        }
                    } else {
                        getLogger("archive_controller").warn(
                            "Failed to install page thumb while updating archive metadata",
                            ("arcid", arcid),
                            ("path", entryPath),
                            ("error", thumbErr)
                        )
                    }
                }
            }

            let ok = ArchivePageMetadataDao.insertOrUpdate(
                archiveInternalId,
                0i32,
                entryPath,
                titleToSave,
                descriptionToSave,
                thumbAssetId: thumbAssetId,
                thumbHash: thumbHash,
                extraData: "{}",
                sortIndex: sortIndex,
                hiddenInFiles: hiddenInFiles
            )
            if (!ok) {
                return false
            }
        }

        return true
    }
    
    // GET /api/archives/{id}/metadata
    public static func getMetadata(ctx: Ctx): Unit {
        let id = ctx.paramsOpt("id").getOrThrow()
        let includePagesRaw = (ctx.query("include_pages") ?? "").trimAscii().toAsciiLower()
        let includePages = includePagesRaw == "1" || includePagesRaw == "true"

        // 检查ID是否为空
        if (id.size == 0) {
            let errorResponse = "{\"error\":\"No archive ID specified.\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, errorResponse)
            return
        }

        let archive = ArchiveDao.getArchiveMetadataById(id)
        if (archive.id.size == 0) {
            let errorResponse = "{\"error\":\"Archive not found\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
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
            lastReadTime: lastReadTime
        )
        if (!okMetadata) {
            let err = if (metadataErr.trimAscii().size > 0) { metadataErr } else { "Failed to build archive metadata" }
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
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
        let lang = ctx.query("lang") ?? ""
        let requestBody = ctx.bodyString().trimAscii()
        let pagePatches = parsePagePatchesFromUpdateRequestBody(requestBody)

        // 检查ID是否为空
        if (id.size == 0) {
            let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"No archive ID specified.\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, errorResponse)
            return
        }

        // 获取查询参数
        let titleParam = ctx.query("title")
        let tagsParam = ctx.query("tags")
        let summaryParam = ctx.query("summary")
        let coverParam = ctx.query("cover")
        let backdropParam = ctx.query("backdrop")
        let clearlogoParam = ctx.query("clearlogo")
        let assetsParam = ctx.query("assets")
        var pluginNamespace = (ctx.query("metadata_namespace") ?? "").trimAscii()
        if (pluginNamespace.size == 0) {
            pluginNamespace = (ctx.query("plugin_namespace") ?? "").trimAscii()
        }
        if (pluginNamespace.size == 0) {
            pluginNamespace = (ctx.query("namespace") ?? "").trimAscii()
        }
        
        // 检查归档是否存在
        let archive = ArchiveModel.getArchiveById(id)
        if (archive.id.size == 0) {
            let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"Archive not found\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ResponseView.json(ctx, errorResponse)
            return
        }

        if (requestBody.size > 0) {
            let parsed = MetadataPatchService.parseMetadataObject(requestBody)
            if (parsed.success && (
                parsed.titleProvided ||
                parsed.summaryProvided ||
                parsed.tagsProvided ||
                parsed.coverProvided ||
                parsed.backdropProvided ||
                parsed.clearlogoProvided ||
                parsed.pages.size > 0
            )) {
                let pluginNamespaceFromBody = MetadataPatchService.extractMetadataNamespace(requestBody)
                let topPatch = MetadataPatchService.buildArchivePatchFromParsed(parsed)
                let ok = MetadataPatchService.applyArchiveMetadataPatch(0, id, topPatch, pluginNamespaceFromBody)
                if (!ok) {
                    let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"Failed to update archive metadata\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ResponseView.json(ctx, errorResponse)
                    return
                }
                ResponseView.json(ctx, "{\"operation\":\"update_metadata\",\"success\":1}")
                return
            }
        }
        
        // 获取现有档案数据
        var existingArchive = ArchiveDao.getArchiveById(id)
        if (existingArchive.id.size == 0) {
            let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"Archive not found in database\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ResponseView.json(ctx, errorResponse)
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

        // Default: do NOT bump updated_at when only metadata changes.
        // In this project, archives.updated_at is treated as the "release time" unless a plugin explicitly sets it.
        var nextUpdatedAt = existingArchive.updated_at

        // If tags contain `updated_at:*`, prefer it as archive updated_at and strip it from tag storage.
        var cleanedTagsOpt: Option<String> = None
        match (tagsParam) {
            case Some(tags) =>
                let originalTags = if (lang.size > 0) {
                    TagDao.reverseTranslateTagsString(tags, lang)
                } else {
                    tags
                }
                let (pluginUpdatedAt, cleanedTags) = extractUpdatedAtFromTags(originalTags)
                if (pluginUpdatedAt.size > 0) {
                    nextUpdatedAt = pluginUpdatedAt
                }
                cleanedTagsOpt = Some(cleanedTags)
            case None => ()
        }

        existingArchive.updated_at = nextUpdatedAt
        
        // 执行数据库更新
        let updateSuccess = ArchiveDao.update(existingArchive)
        
        if (updateSuccess) {
            // 如果有标签参数，更新标签
            match (cleanedTagsOpt) {
                case Some(originalTags) =>
                    // 使用TagDao更新标签（updated_at:* 已剥离，不会作为普通标签写入）
                    let tagUpdateSuccess = TagDao.updateArchiveTags(id, originalTags)
                    if (!tagUpdateSuccess) {
                        // 记录错误日志到日志文件，而不是控制台
                        getLogger("archive_controller").error("Failed to update tags for archive ${id}")
                        // 返回错误响应给前端
                        let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"Failed to update tags\",\"success\":0}"
                        ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                        ResponseView.json(ctx, errorResponse)
                        return
                    }
                case None => () // 不更新标签
            }

            match (assetsParam) {
                case Some(rawAssets) =>
                    let assetsUpdated = ArchiveDao.updateArchiveAssetsRaw(id, rawAssets)
                    if (!assetsUpdated) {
                        let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"Failed to update archive assets\",\"success\":0}"
                        ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                        ResponseView.json(ctx, errorResponse)
                        return
                    }
                case None => ()
            }
            
            match (coverParam) {
                case Some(coverPath) =>
                    let coverTrimmed = coverPath.trimAscii()
                    if (coverTrimmed.size > 0) {
                        let oldCoverAssetId = ArchiveDao.getCoverAssetId(id)
                        let (okCover, coverAssetId, coverThumbHash, coverErr) = PluginCoverUtils.installCoverAssetFromPluginPath(
                            coverTrimmed,
                            pluginNamespace,
                            "archive_cover",
                            "${id}.avif"
                        )
                        if (okCover && coverAssetId > 0) {
                            let coverUpdated = ArchiveDao.updateCoverAssetId(id, coverAssetId)
                            if (coverUpdated) {
                                if (coverThumbHash.trimAscii().size > 0) {
                                    let _ = ArchiveDao.updateThumbHash(id, coverThumbHash)
                                }
                                if (oldCoverAssetId > 0 && oldCoverAssetId != coverAssetId) {
                                    PluginCoverUtils.deleteAsset(oldCoverAssetId)
                                }
                            } else {
                                PluginCoverUtils.deleteAsset(coverAssetId)
                                getLogger("archive_controller").warn("Failed to update archive cover asset id", ("arcid", id))
                            }
                        } else {
                            getLogger("archive_controller").warn("Failed to install archive cover from plugin path", ("arcid", id), ("error", coverErr))
                        }
                    }
                case None => ()
            }

            match (backdropParam) {
                case Some(backdropPath) =>
                    let backdropTrimmed = backdropPath.trimAscii()
                    if (backdropTrimmed.size == 0) {
                        let _ = ArchiveDao.updateArchiveAssetIdByKey(id, "backdrop", 0)
                    } else {
                        let (okBackdrop, backdropAssetId, _, backdropErr) = PluginCoverUtils.installCoverAssetFromPluginPath(
                            backdropTrimmed,
                            pluginNamespace,
                            "archive_backdrop",
                            "${id}_backdrop.avif"
                        )
                        if (okBackdrop && backdropAssetId > 0) {
                            let backdropUpdated = ArchiveDao.updateArchiveAssetIdByKey(id, "backdrop", backdropAssetId)
                            if (!backdropUpdated) {
                                PluginCoverUtils.deleteAsset(backdropAssetId)
                                getLogger("archive_controller").warn("Failed to update archive backdrop asset id", ("arcid", id))
                            }
                        } else {
                            getLogger("archive_controller").warn("Failed to install archive backdrop from plugin path", ("arcid", id), ("error", backdropErr))
                        }
                    }
                case None => ()
            }

            match (clearlogoParam) {
                case Some(clearlogoPath) =>
                    let clearlogoTrimmed = clearlogoPath.trimAscii()
                    if (clearlogoTrimmed.size == 0) {
                        let _ = ArchiveDao.updateArchiveAssetIdByKey(id, "clearlogo", 0)
                    } else {
                        let (okClearlogo, clearlogoAssetId, _, clearlogoErr) = PluginCoverUtils.installCoverAssetFromPluginPath(
                            clearlogoTrimmed,
                            pluginNamespace,
                            "archive_clearlogo",
                            "${id}_clearlogo.avif"
                        )
                        if (okClearlogo && clearlogoAssetId > 0) {
                            let clearlogoUpdated = ArchiveDao.updateArchiveAssetIdByKey(id, "clearlogo", clearlogoAssetId)
                            if (!clearlogoUpdated) {
                                PluginCoverUtils.deleteAsset(clearlogoAssetId)
                                getLogger("archive_controller").warn("Failed to update archive clearlogo asset id", ("arcid", id))
                            }
                        } else {
                            getLogger("archive_controller").warn("Failed to install archive clearlogo from plugin path", ("arcid", id), ("error", clearlogoErr))
                        }
                    }
                case None => ()
            }

            if (pagePatches.size > 0) {
                let pagePatchesUpdated = persistPagePatchesForArchive(id, pluginNamespace, pagePatches)
                if (!pagePatchesUpdated) {
                    let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"Failed to update page metadata\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ResponseView.json(ctx, errorResponse)
                    return
                }
            }

            let result = "{\"operation\":\"update_metadata\",\"success\":1}"
            ResponseView.json(ctx, result)
        } else {
            let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"Failed to update archive metadata\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ResponseView.json(ctx, errorResponse)
        }
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
        let imagesOnly = match (imagesOnlyParam) {
            case Some(i) => i == "true" || i == "1"
            case None => true  // 默认只返回图片文件
        }

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
        let pageMetadata = ArchiveDao.getPageMetadata(id)
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
                    item.thumbAssetId = meta.thumb_asset_id
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

        // 如果不需要只返回图片文件，获取所有文件
        if (!imagesOnly) {
            // 这里可以添加获取所有文件的逻辑
            // 目前保持只返回媒体文件
        }

        // 获取用户的阅读进度（如果用户已登录）
        var progress: Int32 = 0i32
        match (AuthMiddleware.optionalUser(ctx)) {
            case Some(userId) =>
                let archiveIdInt = ArchiveModel.getArchiveIdByArcid(id)
                if (archiveIdInt > 0) {
                    let userProgress = UserArchiveStatusDao.getProgress(userId, archiveIdInt)
                    progress = userProgress
                }
            case None => ()  // 用户未登录，使用默认进度
        }

        // 构建响应JSON（JsonWriter）
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("pages")
        w.startArray()
        for (item in pageFiles) {
            let href = item.href
            let title = item.title
            let metadataTitle = item.title
            let metadataDescription = item.description
            let metadataThumbAssetId = item.thumbAssetId
            let fileType = if (archive.archive_type == ArchiveTypes.EPUB) {
                "html"
            } else if (ArchiveUtils.isVideoFile(href)) {
                "video"
            } else {
                "image"
            }

            w.startObject()
            w.writeName("path").writeValue(href)
            w.writeName("type").writeValue(fileType)
            w.writeName("title").writeValue(title)
            w.writeName("metadata")
            w.startObject()
            w.writeName("title").writeValue(metadataTitle)
            w.writeName("description").writeValue(metadataDescription)
            w.writeName("thumb_asset_id").writeValue(metadataThumbAssetId)
            w.endObject()
            w.endObject()
        }
        w.endArray()
        w.writeName("progress").writeValue(progress)
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
                let coverAssetId = ArchiveDao.getCoverAssetId(id)
                let pageThumbAssetIds = ArchiveDao.getPageThumbAssetIds(id)
                let archivePath = getArchiveBasePath(archive.id)

                // 4. 删除档案记录
                let deleteSuccess = ArchiveDao.delete(id)

                // 5. 删除相关文件（缩略图和原始档案）
                if (deleteSuccess) {
                    // 删除页面元数据及其缩略图资源
                    let _ = ArchiveDao.deletePageMetadata(id)
                    // 删除封面资源文件（assets）
                    try {
                        if (coverAssetId > 0) {
                            let assetRoot = SystemSettingsService.getPath("ASSET_PATH")
                            let assetPath = FileUtils.joinPath(assetRoot, "${coverAssetId}.avif")
                            try { remove(Path(assetPath)) } catch (_: Exception) {}
                            let _ = AssetDao.deleteById(coverAssetId)
                            getLogger("archive_controller").info("Deleted cover asset", ("asset_id", coverAssetId.toString()), ("arcid", id))
                        }
                    } catch (_: Exception) {}

                    // 删除页面级缩略图资源文件（assets）
                    try {
                        let assetRoot = SystemSettingsService.getPath("ASSET_PATH")
                        for (assetId in pageThumbAssetIds) {
                            if (assetId <= 0 || assetId == coverAssetId) {
                                continue
                            }
                            let assetPath = FileUtils.joinPath(assetRoot, "${assetId}.avif")
                            try { remove(Path(assetPath)) } catch (_: Exception) {}
                            let _ = AssetDao.deleteById(assetId)
                        }
                    } catch (_: Exception) {}

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

            // 使用 Handler 获取流式读取器
            let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archive.archive_type)
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
                    w.writeName("summary").writeValue(archive.summary)
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
                    w.writeName("summary").writeValue(archive.summary)
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
    public var thumbAssetId: Int64 = 0
    public var sortIndex: Int32 = 0
    public var originalIndex: Int32 = 0
    public var hidden: Bool = false
    public var hasSort: Bool = false
}
