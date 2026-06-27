package lanlu.contexts.archive.interfaces.http

import stdx.net.http.{HttpStatusCode, HttpResponseWriter}
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
import lanlu.contexts.tag.infrastructure.persistence.*
import lanlu.infrastructure.middleware.*
import lanlu.infrastructure.archivehandler.*
import lanlu.infrastructure.kv.*
import std.fs.*
import std.convert.*
import std.collection.*
import std.io.{ByteBuffer, InputStream, readToEnd}
import stdx.encoding.json.stream.*

private class PageEntryBody <: InputStream {
    private let reader: EntryReader
    private var remaining: Int64
    private var skipRemaining: Int64
    private var closed: Bool = false

    public init(reader: EntryReader, remaining!: Int64 = -1, skipBytes!: Int64 = 0) {
        this.reader = reader
        this.remaining = remaining
        this.skipRemaining = if (skipBytes > 0) {
            skipBytes
        } else {
            0
        }
        if (this.skipRemaining > 0) {
            if (reader.seek(this.skipRemaining)) {
                this.skipRemaining = 0
            }
        }
    }

    public func read(buffer: Array<Byte>): Int64 {
        if (closed) {
            return 0
        }
        if (!drainSkip()) {
            return 0
        }
        if (remaining == 0) {
            close()
            return 0
        }

        let toRead = if (remaining > 0 && remaining < Int64(buffer.size)) {
            remaining
        } else {
            Int64(buffer.size)
        }

        let readBuffer = if (toRead < Int64(buffer.size)) {
            Array<Byte>(toRead, {_ => 0})
        } else {
            buffer
        }

        let bytesRead = reader.read(readBuffer)
        if (bytesRead <= 0) {
            close()
            return 0
        }

        let sendLen = if (remaining > 0 && bytesRead > remaining) {
            remaining
        } else {
            bytesRead
        }
        if (readBuffer.size != buffer.size) {
            for (i in 0..sendLen) {
                buffer[i] = readBuffer[i]
            }
        }

        if (remaining > 0) {
            remaining -= sendLen
        }
        if (remaining == 0) {
            close()
        }
        return sendLen
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        try {
            reader.close()
        } catch (_: Exception) {}
    }

    private func drainSkip(): Bool {
        if (skipRemaining <= 0) {
            return true
        }

        let skipBuffer = Array<Byte>(8192, {_ => 0})
        while (skipRemaining > 0) {
            let toRead = if (skipRemaining > Int64(skipBuffer.size)) {
                Int64(skipBuffer.size)
            } else {
                skipRemaining
            }
            let scratch = if (toRead == Int64(skipBuffer.size)) {
                skipBuffer
            } else {
                Array<Byte>(toRead, {_ => 0})
            }
            let bytesRead = reader.read(scratch)
            if (bytesRead <= 0) {
                close()
                return false
            }
            skipRemaining -= bytesRead
        }
        return true
    }
}

private func isHttp2Protocol(protocol: String): Bool {
    let normalized = protocol.trimAscii().toAsciiLower()
    if (normalized.size == 0) {
        return false
    }
    return normalized == "h2" || normalized == "h2c" || normalized.contains("http/2") || normalized.contains("http2")
}

public class ArchiveController {
    private static let logger = getLogger("archive_controller")

    private static func writeArchiveAssetsJson(w: JsonWriter, assetsRaw: String): Unit {
        let raw = assetsRaw.trimAscii()
        let normalized = if (raw.size > 0) {
            raw
        } else {
            "{}"
        }
        w.writeName("assets").jsonValue(normalized)
    }

    private static func buildArchiveBasePathCacheKey(arcid: String): String {
        let cacheVersion = DerivedCacheUtils.getArchiveBasePathVersion()
        return "v${cacheVersion.toString()}:a${arcid.trimAscii()}"
    }

    private static func readArchiveBasePathCache(cacheKey: String): Option<String> {
        let cacheNamespace = DerivedCacheUtils.getArchiveBasePathPayloadNamespace()
        match (PersistentCacheService.get(cacheNamespace, cacheKey)) {
            case Some(value) =>
                let normalized = value.trimAscii()
                if (normalized.size > 0) {
                    return Some(normalized)
                }
                return None
            case None => return None
        }
    }

    private static func writeArchiveBasePathCache(cacheKey: String, scanPath: String): Unit {
        let normalized = scanPath.trimAscii()
        if (normalized.size == 0) {
            return
        }
        let cacheNamespace = DerivedCacheUtils.getArchiveBasePathPayloadNamespace()
        let _ = PersistentCacheService.set(
            cacheNamespace,
            cacheKey,
            normalized,
            0
        )
    }

    /**
     * 获取档案的基础路径（从分类获取）
     */
    private static func getArchiveBasePath(arcid: String): String {
        let normalizedArcid = arcid.trimAscii()
        if (normalizedArcid.size == 0) {
            return ""
        }
        let cacheKey = buildArchiveBasePathCacheKey(normalizedArcid)
        match (readArchiveBasePathCache(cacheKey)) {
            case Some(path) => return path
            case None => ()
        }

        let path = ArchiveDao.getArchiveScanPathByArcid(normalizedArcid)
        if (path.size > 0) {
            writeArchiveBasePathCache(cacheKey, path)
            return path
        }
        logger.warn("failed to resolve archive base path", ("arcid", normalizedArcid))
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
            "-thumb",
            "_thumb",
            ".thumb",
            "-poster",
            "_poster",
            ".poster",
            "-cover",
            "_cover",
            ".cover"
        ]
        for (suffix in suffixes) {
            if (stem.endsWith(suffix) && stem.size > suffix.size) {
                stem = stem[0..(stem.size - suffix.size)]
                break
            }
        }
        return stem.trimAscii()
    }

    private static func parsePositiveIntQuery(ctx: Ctx, name: String): Int32 {
        let raw = (ctx.query(name) ?? "").trimAscii()
        if (raw.size == 0) {
            return 0
        }
        let parsed = try {
            Int32.parse(raw)
        } catch (_: Exception) {
            0i32
        }
        return if (parsed > 0i32) {
            parsed
        } else {
            0i32
        }
    }

    private static func resolveArchiveFileType(archiveType: String, href: String): String {
        if (ArchiveType.fromDb(archiveType).defaultFileType() == "html") {
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

    private static func isAsciiDigit(value: UInt8): Bool {
        return value >= 48 && value <= 57
    }

    private static func trimAsciiLower(value: String): String {
        return value.trimAscii().toAsciiLower()
    }

    private static func zeroPad2(value: Int64): String {
        if (value < 10) {
            return "0${value}"
        }
        return value.toString()
    }

    /**
     * 对字符串进行 URL 组件编码（等价于 JavaScript encodeURIComponent）。
     * 保留 unreserved 字符（字母、数字、-_.~），其余字符进行百分号编码。
     */
    private static func urlEncodeComponent(input: String): String {
        let unreserved = HashSet<UInt8>()
        let hexChars = [
            UInt8(UInt32(r'0')), UInt8(UInt32(r'1')), UInt8(UInt32(r'2')), UInt8(UInt32(r'3')),
            UInt8(UInt32(r'4')), UInt8(UInt32(r'5')), UInt8(UInt32(r'6')), UInt8(UInt32(r'7')),
            UInt8(UInt32(r'8')), UInt8(UInt32(r'9')), UInt8(UInt32(r'A')), UInt8(UInt32(r'B')),
            UInt8(UInt32(r'C')), UInt8(UInt32(r'D')), UInt8(UInt32(r'E')), UInt8(UInt32(r'F'))
        ]
        unsafe {
            for (c in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~".rawData()) {
                unreserved.add(c)
            }
        }
        let bytes = unsafe { input.rawData() }
        var out = ""
        for (b in bytes) {
            if (unreserved.contains(b)) {
                out += String.fromUtf8(Array<UInt8>(1, {_ => b}))
            } else {
                let high = Int64((UInt32(b) >> 4) & 0x0Fu32)
                let low = Int64(UInt32(b) & 0x0Fu32)
                out += "%"
                out += String.fromUtf8(Array<UInt8>(1, {_ => hexChars[high]}))
                out += String.fromUtf8(Array<UInt8>(1, {_ => hexChars[low]}))
            }
        }
        return out
    }

    private static func extractEpisodeToken(text: String): String {
        let lower = trimAsciiLower(text)
        if (lower.size < 6) {
            return ""
        }

        for (i in 0..(lower.size - 5)) {
            let ch = lower[i]
            if (ch != 115) { // 's'
                continue
            }

            var cursor = i + 1
            var seasonDigits = ""
            while (cursor < lower.size && seasonDigits.size < 3 && isAsciiDigit(lower[cursor])) {
                seasonDigits += Rune(UInt32(lower[cursor])).toString()
                cursor++
            }
            if (seasonDigits.size <= 0 || cursor >= lower.size || lower[cursor] != 101) { // 'e'
                continue
            }

            cursor++
            var episodeDigits = ""
            while (cursor < lower.size && episodeDigits.size < 3 && isAsciiDigit(lower[cursor])) {
                episodeDigits += Rune(UInt32(lower[cursor])).toString()
                cursor++
            }
            if (episodeDigits.size <= 0) {
                continue
            }

            let seasonNo = try {
                Int64.parse(seasonDigits)
            } catch (_: Exception) {
                0i64
            }
            let episodeNo = try {
                Int64.parse(episodeDigits)
            } catch (_: Exception) {
                0i64
            }
            if (seasonNo <= 0 || episodeNo <= 0) {
                continue
            }
            return "s${zeroPad2(seasonNo)}e${zeroPad2(episodeNo)}"
        }

        return ""
    }

    private static func extractGroupKey(item: ArchiveFilesPageItem): String {
        let fileType = item.fileType.trimAscii()
        if (fileType != "video" && fileType != "audio") {
            return ""
        }
        if (item.sortIndex > 0) {
            return "${fileType}:sort:${item.sortIndex}"
        }
        let titleToken = extractEpisodeToken(item.title)
        if (titleToken.size > 0) {
            return "${fileType}:episode:${titleToken}"
        }
        let pathToken = extractEpisodeToken(item.href)
        if (pathToken.size > 0) {
            return "${fileType}:episode:${pathToken}"
        }
        return ""
    }

    private static func sourcePreferenceScore(item: ArchiveFilesPageItem): Int64 {
        var score = 0i64
        if (item.thumbAssetId > 0) {
            score += 1000000000i64
        }
        if (item.hasSort && item.sortIndex > 0) {
            score += Int64(100000000 - item.sortIndex)
        } else if (item.sortIndex > 0) {
            score += Int64(100000000 - item.sortIndex)
        }
        score += Int64(1000000 - item.originalIndex)
        return score
    }

    private static func choosePreferredSource(
        current: ArchiveFilesPageItem,
        candidate: ArchiveFilesPageItem
    ): ArchiveFilesPageItem {
        let currentScore = sourcePreferenceScore(current)
        let candidateScore = sourcePreferenceScore(candidate)
        if (candidateScore > currentScore) {
            return candidate
        }
        if (candidateScore < currentScore) {
            return current
        }
        if (candidate.href.trimAscii().toAsciiLower() < current.href.trimAscii().toAsciiLower()) {
            return candidate
        }
        return current
    }

    private static func writeArchiveFilePageMetadata(
        w: JsonWriter,
        item: ArchiveFilesPageItem
    ): Unit {
        func writeAttachments(): Unit {
            w.writeName("attachments")
            w.startArray()
            for (attachment in item.attachments) {
                if (attachment.asset_id <= 0 || attachment.slot.trimAscii().size == 0) {
                    continue
                }
                w.startObject()
                w.writeName("slot").writeValue(attachment.slot)
                w.writeName("asset_id").writeValue(attachment.asset_id)
                w.writeName("name").writeValue(attachment.name)
                w.writeName("mime_type").writeValue(attachment.mime_type)
                w.writeName("kind").writeValue(attachment.kind)
                w.writeName("language").writeValue(attachment.language)
                w.writeName("order_index").writeValue(attachment.order_index)
                w.endObject()
            }
            w.endArray()
        }

        w.startObject()
        w.writeName("title").writeValue(item.title)
        w.writeName("description").writeValue(item.description)
        w.writeName("thumb_asset_id").writeValue(item.thumbAssetId)
        writeAttachments()
        w.writeName("release_at").writeValue(item.releaseAt)
        w.endObject()
    }

    private static func injectCapabilities(json: String, capsArray: String): String {
        let trimmed = json.trimAscii()
        if (trimmed.size < 2) { return json }
        // 找到最后一个 } 的位置，在其前面插入 ,"capabilities":capsArray
        let lastBrace = trimmed.lastIndexOf("}")
        match (lastBrace) {
            case Some(idx) =>
                let before = trimmed[0..idx]
                let after = trimmed[idx..trimmed.size]
                return "${before},\"capabilities\":${capsArray}${after}"
            case None => return json
        }
    }

    // GET /api/archives/{id}/metadata
    public static func getMetadata(ctx: Ctx): Unit {
        let id = ctx.paramsOpt("id") ?? ""

        // Source: 复合 ID 检测/转发 → 构建 ArchiveMetadata
        match (SourceRequestResolver.parseFromCompositeId(id)) {
            case Some(request) =>
                let detail = SourceArchiveReadService.fetchDetail(id)

                // 检查插件返回是否有效，失败时返回明确错误
                if (detail.hasError() || (detail.title.size == 0 && detail.pageCount <= 0)) {
                    let errMsg = if (detail.hasError()) { detail.errorMessage } else { "plugin returned empty result" }
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ResponseView.errorJson(ctx, "Failed to fetch source detail: ${errMsg}")
                    return
                }

                // 合并用户状态（如果登录）
                var progress: Int32 = 0
                var isNew: Bool = true
                var isFavorite: Bool = false
                var lastReadTime: Int64 = 0
                match (AuthMiddleware.optionalUser(ctx)) {
                    case Some(userId) =>
                        progress = UserTargetStatusDao.getProgress(userId, "source_archive", id)
                        isNew = UserTargetStatusDao.isNew(userId, "source_archive", id)
                        isFavorite = UserTargetFavoritesDao.isFavorite(userId, "source_archive", id)
                        lastReadTime = UserTargetStatusDao.getLastReadTime(userId, "source_archive", id)
                    case None => ()
                }

                // 构建 ArchiveMetadata JSON 输出
                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("arcid").writeValue(id)
                w.writeName("title").writeValue(detail.title)
                w.writeName("description").writeValue(detail.description)
                w.writeName("tags")
                w.startArray()
                for (tag in detail.tags) { w.writeValue(tag) }
                w.endArray()
                w.writeName("pagecount").writeValue(detail.pageCount)
                w.writeName("page_count").writeValue(detail.pageCount)
                w.writeName("progress").writeValue(progress)
                w.writeName("isnew").writeValue(isNew)
                w.writeName("isfavorite").writeValue(isFavorite)
                w.writeName("archivetype").writeValue(detail.mediaType)
                w.writeName("lastreadtime").writeValue(lastReadTime)
                w.writeName("size").writeValue(0)
                // assets
                if (detail.coverAssetId > 0) {
                    w.writeName("assets")
                    w.startObject()
                    w.writeName("cover").writeValue(detail.coverAssetId)
                    w.endObject()
                } else {
                    w.writeName("assets")
                    w.startObject()
                    w.endObject()
                }
                w.writeName("filename").writeValue("")
                w.writeName("relative_path").writeValue("")
                w.writeName("thumbnail_hash").writeValue("")
                w.writeName("release_at").writeValue("")
                w.writeName("updated_at").writeValue("")
                w.writeName("created_at").writeValue("")
                // capabilities - 由 SourcePluginMatcher 动态计算
                let caps = SourcePluginMatcher.getCapabilities(id)
                var hasPageChildren = false
                for (child in detail.children) {
                    if (child.entityType == "page") { hasPageChildren = true; break }
                }
                w.writeName("capabilities")
                w.startArray()
                for (cap in caps) {
                    if (cap == "read" && !hasPageChildren) { continue }
                    w.writeValue(cap)
                }
                w.writeValue("progress")
                w.writeValue("favorite")
                w.writeValue("isnew")
                w.endArray()
                // children - 由 Metadata 插件提供，支持 archive 和 page 两种 entity_type
                w.writeName("children")
                w.startArray()
                for (child in detail.children) {
                    let isPage = child.entityType == "page"
                    w.startObject()
                    w.writeName("entity_type").writeValue(child.entityType)
                    if (isPage) {
                        // page children 使用 path 定位资源
                        w.writeName("entity_id").writeValue(child.remoteId)
                        w.writeName("title").writeValue(child.title)
                        w.writeName("path").writeValue(child.path)
                        w.writeName("media_type").writeValue(child.mediaType)
                        if (child.sortOrder > 0) {
                            w.writeName("sort_order").writeValue(child.sortOrder)
                        }
                    } else {
                        // archive children 使用 child.remoteId（已包含完整 source:ns:id）
                        w.writeName("entity_id").writeValue(child.remoteId)
                        w.writeName("title").writeValue(child.title)
                        w.writeName("description").writeValue(child.description)
                        w.writeName("tags")
                        w.startArray()
                        for (ct in child.tags) { w.writeValue(ct) }
                        w.endArray()
                    }
                    w.endObject()
                }
                w.endArray()
                w.endObject()
                w.flush()
                ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
                return
            case None => ()
        }

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
            let err = if (metadataErr.trimAscii().size > 0) {
                metadataErr
            } else {
                "Failed to build archive metadata"
            }
            if (err == "Archive not found") {
                ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            } else {
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            }
            ResponseView.json(ctx, "{\"error\":\"${err}\",\"success\":0}")
            return
        }
        // 向 metadata JSON 注入 capabilities
        let injectedJson = injectCapabilities(metadataJson, "[\"read\",\"download\",\"update_metadata\",\"delete\",\"progress\",\"favorite\",\"isnew\"]")
        ResponseView.json(ctx, injectedJson)
    }

    // GET /api/archives/{id}/tankoubons
    public static func getTankoubonsForArchive(ctx: Ctx): Unit {
        let arcid = ctx.paramsOpt("id") ?? ""
        if (arcid.size == 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx,
                "{\"error\":\"No archive ID specified.\",\"operation\":\"get_archive_tankoubons\",\"success\":0}")
            return
        }

        // Source: 复合 ID — 返回空列表
        match (SourceRequestResolver.parseFromCompositeId(arcid)) {
            case Some(_) =>
                ResponseView.json(ctx, "{\"filtered\":0,\"result\":[],\"total\":0}")
                return
            case None => ()
        }

        let userIdOpt = AuthMiddleware.optionalUser(ctx)
        let tankoubons = match (userIdOpt) {
            case Some(userId) => TankoubonModel.getTankoubonsForArchiveWithUser(arcid, userId)
            case None => TankoubonModel.getTankoubonsForArchive(arcid)
        }

        // 查询收藏状态（登录用户）
        match (userIdOpt) {
            case Some(userId) => for (i in 0..tankoubons.size) {
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
        let id = ctx.paramsOpt("id") ?? ""
        let requestBody = ctx.bodyString().trimAscii()

        if (id.size == 0) {
            let errorResponse = "{\"operation\":\"update_metadata\",\"error\":\"No archive ID specified.\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, errorResponse)
            return
        }

        // Source: 复合 ID — 在线源元数据只读
        match (SourceRequestResolver.parseFromCompositeId(id)) {
            case Some(_) =>
                ctx.status(HttpStatusCode.STATUS_METHOD_NOT_ALLOWED)
                ResponseView.json(ctx, "{\"operation\":\"update_metadata\",\"error\":\"Online source metadata is read-only\",\"success\":0}")
                return
            case None => ()
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
        let id = ctx.paramsOpt("id") ?? ""

        // Source: 复合 ID 检测/转发
        match (SourceRequestResolver.parseFromCompositeId(id)) {
            case Some(request) =>
                let tankoubonId = (ctx.query("tankoubon_id") ?? "").trimAscii()
                var effectiveRequest = request

                // 如果传了 tankoubon_id，解析单行本的第一个子项作为实际阅读目标
                if (tankoubonId.size > 0) {
                    match (SourceRequestResolver.parseFromCompositeId(tankoubonId)) {
                        case Some(tankoubonRequest) =>
                            let detail = SourceArchiveReadService.fetchDetail(tankoubonId)
                            if (detail.children.size > 0 && detail.children[0].remoteId.size > 0) {
                                let out = ByteBuffer()
                                let w = JsonWriter(out)
                                w.startObject()
                                w.writeName("remote_id").writeValue(detail.children[0].remoteId)
                                w.endObject()
                                w.flush()
                                let childRequest = SourceRequest(request.namespace, detail.children[0].remoteId)
                                childRequest.paramsJson = String.fromUtf8(readToEnd(out))
                                effectiveRequest = childRequest
                            }
                        case None => ()
                    }
                }

                // 使用 effectiveRequest 构建实际阅读目标的 compositeId
                let effectiveId: String
                if (effectiveRequest.remoteId != request.remoteId) {
                    effectiveId = "source:${effectiveRequest.namespace}:${effectiveRequest.remoteId}"
                } else {
                    effectiveId = id
                }
                let result = SourceArchiveReadService.fetchPages(effectiveId)

                // 检查插件返回是否有效
                if (result.hasError() || result.pages.size == 0) {
                    let errMsg = if (result.hasError()) { result.errorMessage } else { "plugin returned empty result" }
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ResponseView.errorJson(ctx, "Failed to fetch source pages: ${errMsg}")
                    return
                }

                // 构建前端 PageInfo 输出
                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("pages").startArray()

                for (i in 0..result.pages.size) {
                    let page = result.pages[i]
                    let pagePath = page.path

                    let srcId = "src-${i.toString()}"

                    let pageUrl: String
                    if (page.assetId > 0) {
                        pageUrl = "/api/assets/${page.assetId.toString()}"
                    } else {
                        let encodedId = urlEncodeComponent(effectiveId)
                        let encodedPath = urlEncodeComponent(pagePath)
                        pageUrl = "/api/archives/${encodedId}/page?path=${encodedPath}"
                    }

                    w.startObject()
                    w.writeName("id").writeValue(pagePath)
                    w.writeName("type").writeValue("image")

                    w.writeName("defaultSource").startObject()
                    w.writeName("id").writeValue(srcId)
                    w.writeName("path").writeValue(pagePath)
                    w.writeName("url").writeValue(pageUrl)
                    w.writeName("type").writeValue("image")
                    w.endObject()

                    w.writeName("sources").startArray()
                    w.startObject()
                    w.writeName("id").writeValue(srcId)
                    w.writeName("path").writeValue(pagePath)
                    w.writeName("url").writeValue(pageUrl)
                    w.writeName("type").writeValue("image")
                    w.writeName("metadata")
                    w.startObject()
                    w.endObject()
                    w.endObject()
                    w.endArray()

                    w.writeName("metadata")
                    w.startObject()
                    w.endObject()

                    w.endObject()
                }

                w.endArray()
                w.endObject()
                w.flush()

                ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
                return
            case None => ()
        }

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
        let offsetParsed = try {
            Int32.parse(offsetRaw)
        } catch (_: Exception) {
            0i32
        }
        let offset = if (offsetParsed > 0i32) {
            offsetParsed
        } else {
            0i32
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
        let pageMetadata = MetadataDao.listPageMetadata(id, includeAttachments: includeMetadata)
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
            let fileType = if (ArchiveType.fromDb(archive.archive_type).defaultFileType() == "html") {
                "html"
            } else {
                resolveArchiveFileType(archive.archive_type, href)
            }
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
            item.fileType = fileType
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
                    item.attachments = meta.attachments
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
                    if (!found || item.sortIndex < bestSort || (item.sortIndex == bestSort && item.originalIndex <
                        bestOrder)) {
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
            if (imagesOnlySpecified && imagesOnly && item.fileType != "image") {
                continue
            }
            filteredPageFiles.add(item)
        }

        var groupedPageFiles = ArrayList<ArchiveFilesPageGroup>()
        var groupedIndexByKey = HashMap<String, Int64>()
        let offsetInt = Int64(offset)
        let endExclusive = if (limit > 0i32) {
            Int64(offset + limit)
        } else {
            Int64(filteredPageFiles.size)
        }
        for (i in 0..filteredPageFiles.size) {
            let item = filteredPageFiles[i]
            let groupKey = extractGroupKey(item)
            if (groupKey.size <= 0) {
                let group = ArchiveFilesPageGroup()
                group.groupKey = if (item.fileType == "video" || item.fileType == "audio") {
                    "${item.fileType}:path:${item.href.trimAscii()}"
                } else {
                    ""
                }
                group.fileType = item.fileType
                group.defaultSource = item
                group.sources.add(item)
                groupedPageFiles.add(group)
                continue
            }

            match (groupedIndexByKey.get(groupKey)) {
                case Some(existingIndex) =>
                    let group = groupedPageFiles[existingIndex]
                    group.sources.add(item)
                    group.defaultSource = choosePreferredSource(group.defaultSource, item)
                case None =>
                    let group = ArchiveFilesPageGroup()
                    group.groupKey = groupKey
                    group.fileType = item.fileType
                    group.defaultSource = item
                    group.sources.add(item)
                    groupedIndexByKey[groupKey] = Int64(groupedPageFiles.size)
                    groupedPageFiles.add(group)
            }
        }

        var responsePageFiles = ArrayList<ArchiveFilesPageGroup>()
        for (i in 0..groupedPageFiles.size) {
            let idx = Int64(i)
            if (idx < offsetInt) {
                continue
            }
            if (idx >= endExclusive) {
                break
            }
            responsePageFiles.add(groupedPageFiles[i])
        }

        // 构建响应JSON（JsonWriter）
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("pages")
        w.startArray()
        for (group in responsePageFiles) {
            let item = group.defaultSource
            let title = item.title
            let fileType = item.fileType
            var defaultSourceIndex = 0i32
            for (sourceIndex in 0..group.sources.size) {
                if (group.sources[sourceIndex].href == item.href) {
                    defaultSourceIndex = Int32(sourceIndex)
                    break
                }
            }

            w.startObject()
            w.writeName("id").writeValue(if (group.groupKey.size > 0) {
                group.groupKey
            } else {
                item.href
            })
            w.writeName("type").writeValue(fileType)
            w.writeName("title").writeValue(title)
            if (group.groupKey.size > 0) {
                w.writeName("group_key").writeValue(group.groupKey)
            }
            w.writeName("default_source_index").writeValue(defaultSourceIndex)
            w.writeName("source_count").writeValue(group.sources.size)
            if (includeMetadata) {
                w.writeName("metadata")
                writeArchiveFilePageMetadata(w, item)
            }
            w.writeName("default_source")
            w.startObject()
            w.writeName("id").writeValue(item.href)
            w.writeName("path").writeValue(item.href)
            w.writeName("type").writeValue(item.fileType)
            w.writeName("title").writeValue(item.title)
            if (includeMetadata) {
                w.writeName("metadata")
                writeArchiveFilePageMetadata(w, item)
            }
            w.endObject()
            w.writeName("sources")
            w.startArray()
            for (source in group.sources) {
                w.startObject()
                w.writeName("id").writeValue(source.href)
                w.writeName("path").writeValue(source.href)
                w.writeName("type").writeValue(source.fileType)
                w.writeName("title").writeValue(source.title)
                if (includeMetadata) {
                    w.writeName("metadata")
                    writeArchiveFilePageMetadata(w, source)
                }
                w.endObject()
            }
            w.endArray()
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
                let id = ctx.paramsOpt("id") ?? ""

                // 检查ID是否为空
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"delete_archive\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // Source: 复合 ID — 在线源不允许删除
                match (SourceRequestResolver.parseFromCompositeId(id)) {
                    case Some(_) =>
                        ctx.status(HttpStatusCode.STATUS_METHOD_NOT_ALLOWED)
                        ResponseView.json(ctx, "{\"operation\":\"delete_archive\",\"error\":\"Online source archives cannot be deleted\",\"success\":0}")
                        return
                    case None => ()
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
                let archiveIdInt = ArchiveDao.getArchiveInternalId(id)
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
                    case Some(metadata) => for (asset in metadata.assets) {
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
                let pageAttachmentAssetIds = MetadataDao.getPageAttachmentAssetIds(id)
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
                    for (assetId in pageAttachmentAssetIds) {
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
                            let actualDeletePath = FileUtils.resolvePath(fullArchivePath)
                            var deletedCount: Int64 = 0
                            match (VolumeArchiveUtils.detectVolume(actualDeletePath)) {
                                case Some(volumeInfo) =>
                                    for (part in volumeInfo.parts) {
                                        try {
                                            if (exists(Path(part))) {
                                                remove(Path(part))
                                                deletedCount++
                                            }
                                        } catch (partErr: Exception) {
                                            getLogger("archive_controller").warn("Failed to delete volume part",
                                                ("arcid", id), ("path", part), ("error", partErr.message))
                                        }
                                    }
                                case None =>
                                    remove(Path(actualDeletePath))
                                    deletedCount = 1
                            }
                            getLogger("archive_controller").info("Deleted archive file", ("path", actualDeletePath),
                                ("arcid", id), ("deleted_count", deletedCount.toString()))
                        } else {
                            getLogger("archive_controller").warn("Archive path is empty, skipping file deletion",
                                ("arcid", id), ("filename", archive.filename))
                        }
                    } catch (e: Exception) {
                        getLogger("archive_controller").warn("Failed to delete archive file", ("arcid", id),
                            ("error", e.message))
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
            case None => return // requireAdmin 已经设置了错误响应
        }
    }

    // GET /api/archives/{id}/download
    // 下载分块大小：1MB
    private static let CHUNK_SIZE: Int64 = 1024 * 1024

    public static func downloadArchive(ctx: Ctx): Unit {
        let id = ctx.paramsOpt("id") ?? ""

        // Source: 复合 ID — 档案统一下载端点不负责在线源下载。
        // 在线源下载需要分类等上下文，应走 source-plugins download/action 入口。
        match (SourceRequestResolver.parseFromCompositeId(id)) {
            case Some(_) =>
                ctx.status(HttpStatusCode.STATUS_METHOD_NOT_ALLOWED)
                ResponseView.json(ctx, "{\"operation\":\"download_archive\",\"error\":\"Online source archives cannot be downloaded from this endpoint\",\"success\":0}")
                return
            case None => ()
        }

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
            match (VolumeArchiveUtils.detectVolume(actualPath)) {
                case Some(volumeInfo) =>
                    if (volumeInfo.isEntry && volumeInfo.parts.size > 1) {
                        match (ctx.query("part")) {
                            case Some(partValue) =>
                                let partIndex = try { Int64.parse(partValue.trimAscii()) } catch (_: Exception) { -1 }
                                if (partIndex < 0 || partIndex >= volumeInfo.parts.size) {
                                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                                    ResponseView.json(ctx, "{\"success\":0,\"error\":\"Invalid volume part index\"}")
                                    return
                                }
                                let partPath = FileUtils.resolvePath(volumeInfo.parts[partIndex])
                                let partFile = File(Path(partPath), Read)
                                let partInfo = partFile.info
                                downloadArchiveChunked(ctx, partFile, partInfo.size, ArchiveUtils.getFullFileName(volumeInfo.parts[partIndex]))
                                return
                            case None =>
                                ctx.status(HttpStatusCode.STATUS_CONFLICT)
                                ResponseView.json(ctx, "{\"success\":0,\"error\":\"Archive is split into multiple volume files; use /download/parts first\"}")
                                return
                        }
                    }
                case None => ()
            }
            if (ctx.query("part").isSome()) {
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, "{\"success\":0,\"error\":\"Archive is not a multi-volume archive\"}")
                return
            }
            let filePath = Path(actualPath)
            let fileSize = FileInfo(filePath).size
            let file = File(filePath, Read)

            // 统一使用分块流式传输，避免一次性分配 fileSize 大小的 buffer
            downloadArchiveChunked(ctx, file, fileSize, archive.filename)
        } catch (e: Exception) {
            let errorResponse = "{\"operation\":\"download_archive\",\"error\":\"Failed to read archive file: ${e.message}\",\"success\":0}"
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ResponseView.json(ctx, errorResponse)
        }
    }

    /**
     * 统一流式下载：分块读取文件并写入响应流，避免一次性分配大 buffer。
     * 文件句柄通过 try/finally 确保异常路径也能关闭。
     */
    private static func downloadArchiveChunked(ctx: Ctx, file: File, fileSize: Int64, filename: String): Unit {
        ctx.setHeader("Content-Type", "application/octet-stream")
        ctx.setHeader("Content-Disposition", "attachment; filename=\"${filename}\"")
        ctx.status(HttpStatusCode.STATUS_OK)

        let writer = ctx.writer()

        var remaining = fileSize
        let chunkBuffer = Array<Byte>(CHUNK_SIZE, {_ => 0})

        try {
            while (remaining > 0) {
                let bytesRead = file.read(chunkBuffer)
                if (bytesRead <= 0) {
                    break
                }
                writer.write(chunkBuffer[0..bytesRead])
                remaining -= bytesRead
            }
        } finally {
            file.close()
        }
    }

    public static func getArchiveDownloadParts(ctx: Ctx): Unit {
        let id = ctx.paramsOpt("id") ?? ""

        if (id.size == 0) {
            ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
            ResponseView.json(ctx, "{\"success\":0,\"error\":\"No archive ID specified.\"}")
            return
        }

        let archive = ArchiveModel.getArchiveById(id)
        if (archive.id.size == 0) {
            ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
            ResponseView.json(ctx, "{\"success\":0,\"error\":\"Archive not found\"}")
            return
        }

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
            let actualPath = FileUtils.resolvePath(fullArchivePath)
            let downloadParts = ArrayList<String>()
            match (VolumeArchiveUtils.detectVolume(actualPath)) {
                case Some(volumeInfo) =>
                    if (volumeInfo.isEntry && volumeInfo.parts.size > 1) {
                        for (part in volumeInfo.parts) {
                            downloadParts.add(part)
                        }
                    } else {
                        downloadParts.add(actualPath)
                    }
                case None => downloadParts.add(actualPath)
            }

            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("success").writeValue(1)
            w.writeName("multipart").writeValue(if (downloadParts.size > 1) { 1 } else { 0 })
            w.writeName("parts")
            w.startArray()
            for (i in 0..downloadParts.size) {
                let part = downloadParts[i]
                let info = FileInfo(Path(FileUtils.resolvePath(part)))
                w.startObject()
                w.writeName("index").writeValue(i)
                w.writeName("name").writeValue(ArchiveUtils.getFullFileName(part))
                w.writeName("size").writeValue(info.size)
                let url = if (downloadParts.size > 1) {
                    "/api/archives/${id}/download?part=${i.toString()}"
                } else {
                    "/api/archives/${id}/download"
                }
                w.writeName("url").writeValue(url)
                w.endObject()
            }
            w.endArray()
            w.endObject()
            w.flush()
            ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
        } catch (e: Exception) {
            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
            ResponseView.json(ctx, "{\"success\":0,\"error\":\"Failed to build download parts: ${e.message}\"}")
        }
    }

    // GET /api/archives/{id}/page?path=...
    public static func getPage(ctx: Ctx): Unit {
        let id = ctx.paramsOpt("id") ?? ""

        // Source: 复合 ID 检测/转发到 source_page_asset
        match (SourceRequestResolver.parseFromCompositeId(id)) {
            case Some(request) =>
                let path = (ctx.query("path") ?? "").trimAscii()
                if (path.size > 0) {
                    let result = SourceArchiveReadService.resolvePageAsset(
                        request.namespace, request.remoteId, path
                    )

                    // 新协议：直接返回二进制数据（零磁盘、零 DB）
                    match (result.binaryData) {
                        case Some(binaryData) =>
                            let ct = if (result.contentType.size > 0) { result.contentType } else { "application/octet-stream" }
                            ctx.setHeader("Content-Type", ct)
                            ctx.setHeader("Cache-Control", "private, max-age=3600")
                            ctx.status(HttpStatusCode.STATUS_OK)
                            ctx.send(binaryData)
                            return
                        case None => ()
                    }

                    // 旧协议：302 重定向到 asset
                    if (result.assetId > 0) {
                        ctx.status(302)
                        ctx.setHeader("Location", "/api/assets/${result.assetId.toString()}")
                        ctx.sendString("")
                    } else {
                        let errorDetail = if (result.errorMessage.size > 0) {
                            result.errorMessage
                        } else {
                            "Failed to resolve source page asset"
                        }
                        // 504: plugin execution/dependency failure
                        ctx.status(HttpStatusCode.STATUS_GATEWAY_TIMEOUT)
                        ResponseView.errorJson(ctx, errorDetail, 504)
                    }
                } else {
                    ResponseView.errorJson(ctx, "Missing path parameter for source archive")
                }
                return
            case None => ()
        }

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

    // GET /api/archives/{id}/cover
    public static func getCover(ctx: Ctx): Unit {
        let id = ctx.paramsOpt("id") ?? ""

        // Source: 分配占位 asset + 投递异步任务
        match (SourceRequestResolver.parseFromCompositeId(id)) {
            case Some(request) =>
                let assetId = SourcePluginExecutionService.resolveCover(id)
                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("cover_asset_id").writeValue(assetId)
                w.endObject()
                w.flush()
                ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
                return
            case None => ()
        }

        // Local archive: 查 metadata 已有 cover
        var coverAssetId: Int64 = 0
        match (MetadataDao.getMetadataObject("archive", id)) {
            case Some(meta) =>
                for (asset in meta.assets) {
                    if (asset.slot == "cover" && asset.asset_id > 0) {
                        coverAssetId = asset.asset_id
                        break
                    }
                }
            case None => ()
        }
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("cover_asset_id").writeValue(coverAssetId)
        w.endObject()
        w.flush()
        ResponseView.json(ctx, String.fromUtf8(readToEnd(out)))
    }

    /**
     * getPage 内部实现
     */
    private static func getPageInternal(ctx: Ctx, id: String, path: String): Unit {
        let safePath = match (ArchiveEntryPathUtils.normalizeRelativeEntryPath(path)) {
            case Some(value) => value
            case None =>
                let errorResponse = "{\"operation\":\"serve_page\",\"error\":\"Invalid path\",\"success\":0}"
                ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                ResponseView.json(ctx, errorResponse)
                return
        }

        if (safePath.size == 0) {
            let errorResponse = "{\"operation\":\"serve_page\",\"error\":\"Invalid path\",\"success\":0}"
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
            let (exitCode, readerOpt, errorMsg) = handler.getEntryReader(actualPath, safePath)

            if (exitCode == 0) {
                match (readerOpt) {
                    case Some(reader) => sendPageDataWithReader(ctx, id, safePath, archive.archive_type, reader)
                    case None =>
                        logger.error(
                            "entry reader missing",
                            ("arcid", id),
                            ("entry_path", safePath),
                            ("archive_type", archive.archive_type),
                            ("range", "none"),
                            ("error", "Reader is null")
                        )
                        CacheUtils.setNoCacheHeaders(ctx)
                        ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                        ResponseView.json(ctx,
                            "{\"operation\":\"serve_page\",\"error\":\"Reader is null\",\"success\":0}")
                }
            } else {
                logger.error(
                    "failed to get entry reader",
                    ("arcid", id),
                    ("entry_path", safePath),
                    ("archive_type", archive.archive_type),
                    ("range", "none"),
                    ("error", errorMsg)
                )
                CacheUtils.setNoCacheHeaders(ctx)
                ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                ResponseView.json(ctx, "{\"operation\":\"serve_page\",\"error\":\"${errorMsg}\",\"success\":0}")
            }
        } catch (e: Exception) {
            logger.error(
                "serve page exception",
                ("arcid", id),
                ("entry_path", safePath),
                ("archive_type", archive.archive_type),
                ("range", "none"),
                ("error", e.message)
            )
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
        archiveType: String,
        reader: EntryReader
    ): Unit {
        let fileSize = reader.getSize()
        let contentType = getContentTypeFromPath(path)
        let etag = CacheUtils.generateETag("${id}-${path}-${fileSize}")
        let method = ctx.method.trimAscii().toAsciiUpper()
        let isHeadRequest = method == "HEAD"

        // 检查缓存
        if (CacheUtils.checkIfNoneMatch(ctx, etag)) {
            reader.close()
            CacheUtils.sendNotModifiedDynamic(ctx, etag)
            return
        }

        // 支持 HTTP Range（仅单区间），用于视频拖动/断点播放
        let rangeHeader = (ctx.header("Range") ?? "").trimAscii()
        let ifRangeHeader = (ctx.header("If-Range") ?? "").trimAscii()
        let (rangeState, rangeStart, rangeEnd) = parseRangeHeader(rangeHeader, fileSize)
        let effectiveRangeState = if (rangeState > 0 && ifRangeHeader.size > 0 && ifRangeHeader != etag) {
            0i32
        } else {
            rangeState
        }
        logger.debug(
            "serve page request",
            ("arcid", id),
            ("entry_path", path),
            ("archive_type", archiveType),
            ("content_type", contentType),
            ("file_size", fileSize.toString()),
            ("range_header", rangeHeader),
            ("if_range_header", ifRangeHeader),
            ("has_authorization", if ((ctx.header("Authorization") ?? "").trimAscii().size > 0) {
                    "true"
                } else {
                    "false"
                }),
            ("has_auth_cookie", if ((ctx.header("Cookie") ?? "").contains("auth_token=")) {
                    "true"
                } else {
                    "false"
                }),
            ("user_agent", ctx.header("User-Agent") ?? "")
        )
        if (effectiveRangeState < 0) {
            logger.warn(
                "serve page invalid range",
                ("arcid", id),
                ("entry_path", path),
                ("archive_type", archiveType),
                ("range_header", rangeHeader),
                ("file_size", fileSize.toString())
            )
            reader.close()
            sendRangeNotSatisfiable(ctx, fileSize, sendBody: !isHeadRequest)
            return
        }

        if (isHeadRequest) {
            sendPageHeadResponse(ctx, contentType, etag, fileSize, effectiveRangeState, rangeStart, rangeEnd)
            reader.close()
            return
        }

        if (effectiveRangeState > 0) {
            sendPageRangeResponse(ctx, reader, contentType, etag, fileSize, rangeStart, rangeEnd, id, path, archiveType)
            return
        }

        // 将字节流交给框架写出线程，避免在 handler 线程里手写阻塞循环。
        sendPageStreamResponse(ctx, reader, contentType, etag)
    }

    /**
     * 大文件：使用 chunked 流式传输
     */
    private static func sendPageStreamResponse(
        ctx: Ctx,
        reader: EntryReader,
        contentType: String,
        etag: String
    ): Unit {
        // 设置响应头（在交给 responseBuilder 之前）
        ctx.setHeader("Content-Type", contentType)
        ctx.setHeader("ETag", etag)
        ctx.setHeader("Cache-Control", "private, max-age=3600")
        ctx.setHeader("Accept-Ranges", "bytes")
        if (!isHttp2Protocol(ctx.protocol)) {
            ctx.setHeader("Transfer-Encoding", "chunked")
        }
        ctx.status(HttpStatusCode.STATUS_OK)
        writePageEntryBody(ctx, PageEntryBody(reader))
    }

    /**
     * Range 请求：按指定区间发送数据（206 Partial Content）
     */
    private static func sendPageRangeResponse(
        ctx: Ctx,
        reader: EntryReader,
        contentType: String,
        etag: String,
        fileSize: Int64,
        rangeStart: Int64,
        rangeEnd: Int64,
        arcid: String,
        entryPath: String,
        archiveType: String
    ): Unit {
        let rangeLength = rangeEnd - rangeStart + 1
        ctx.setHeader("Content-Type", contentType)
        ctx.setHeader("ETag", etag)
        ctx.setHeader("Cache-Control", "private, max-age=3600")
        ctx.setHeader("Accept-Ranges", "bytes")
        ctx.setHeader("Content-Range", "bytes ${rangeStart}-${rangeEnd}/${fileSize}")
        ctx.setHeader("Content-Length", "${rangeLength}")
        ctx.status(HttpStatusCode.STATUS_PARTIAL_CONTENT)
        logger.info(
            "serve page response",
            ("arcid", arcid),
            ("entry_path", entryPath),
            ("archive_type", archiveType),
            ("status", "206"),
            ("content_type", contentType),
            ("range", "bytes ${rangeStart}-${rangeEnd}/${fileSize}"),
            ("content_length", "${rangeLength}")
        )
        writePageEntryBody(ctx, PageEntryBody(reader, remaining: rangeLength, skipBytes: rangeStart))
    }

    private static func writePageEntryBody(ctx: Ctx, body: PageEntryBody): Unit {
        let writer = HttpResponseWriter(ctx.httpContext())
        let buffer = Array<Byte>(CHUNK_SIZE, {_ => 0})
        try {
            while (true) {
                let bytesRead = body.read(buffer)
                if (bytesRead <= 0) {
                    break
                }
                writer.write(buffer[0..bytesRead])
            }
        } finally {
            body.close()
        }
    }

    private static func sendPageHeadResponse(
        ctx: Ctx,
        contentType: String,
        etag: String,
        fileSize: Int64,
        rangeState: Int32,
        rangeStart: Int64,
        rangeEnd: Int64
    ): Unit {
        ctx.setHeader("Content-Type", contentType)
        ctx.setHeader("ETag", etag)
        ctx.setHeader("Cache-Control", "private, max-age=3600")
        ctx.setHeader("Accept-Ranges", "bytes")
        if (rangeState > 0) {
            let rangeLength = rangeEnd - rangeStart + 1
            ctx.setHeader("Content-Range", "bytes ${rangeStart}-${rangeEnd}/${fileSize}")
            ctx.setHeader("Content-Length", "${rangeLength}")
            ctx.status(HttpStatusCode.STATUS_PARTIAL_CONTENT)
            logger.info(
                "serve page response",
                ("status", "206"),
                ("content_type", contentType),
                ("range", "bytes ${rangeStart}-${rangeEnd}/${fileSize}"),
                ("content_length", "${rangeLength}")
            )
            return
        }
        ctx.setHeader("Content-Length", "${fileSize}")
        ctx.status(HttpStatusCode.STATUS_OK)
        logger.info(
            "serve page response",
            ("status", "200"),
            ("content_type", contentType),
            ("range", "none"),
            ("content_length", "${fileSize}")
        )
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
                    let start = if (suffixLen >= fileSize) {
                        0i64
                    } else {
                        fileSize - suffixLen
                    }
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
            case None => return (-1i32, 0i64, 0i64)
        }
    }

    /**
     * 返回 416 Range Not Satisfiable
     */
    private static func sendRangeNotSatisfiable(ctx: Ctx, fileSize: Int64, sendBody!: Bool = true): Unit {
        ctx.status(416)
        ctx.setHeader("Accept-Ranges", "bytes")
        if (fileSize >= 0) {
            ctx.setHeader("Content-Range", "bytes */${fileSize}")
        }
        ctx.setHeader("Content-Length", "0")
        logger.warn(
            "serve page response",
            ("status", "416"),
            ("file_size", fileSize.toString())
        )
        if (sendBody) {
            ctx.sendString("")
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
     * 设置归档的 isNew 标记（PUT /api/archives/{id}/isnew）
     * 现在使用用户级别的已读状态
     */
    public static func setIsNew(ctx: Ctx): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.paramsOpt("id") ?? ""

                // 检查ID是否为空
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"set_isnew\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // Source: 复合 ID — 真实持久化
                match (SourceRequestResolver.parseFromCompositeId(id)) {
                    case Some(_) =>
                        let ok = UserTargetStatusDao.setIsNew(userId, "source_archive", id)
                        if (ok) {
                            ResponseView.json(ctx, "{\"operation\":\"set_isnew\",\"success\":1}")
                        } else {
                            let errorResponse = "{\"operation\":\"set_isnew\",\"error\":\"Failed to set isNew flag\",\"success\":0}"
                            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                            ResponseView.json(ctx, errorResponse)
                        }
                        return
                    case None => ()
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
                let archiveIdInt = ArchiveDao.getArchiveInternalId(id)
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
            case None => return // requireUser 已经设置了错误响应
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
                let id = ctx.paramsOpt("id") ?? ""

                // 检查ID是否为空
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"clear_isnew\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // Source: 复合 ID — 真实持久化
                match (SourceRequestResolver.parseFromCompositeId(id)) {
                    case Some(_) =>
                        let ok = UserTargetStatusDao.clearIsNew(userId, "source_archive", id)
                        if (ok) {
                            ResponseView.json(ctx, "{\"operation\":\"clear_isnew\",\"success\":1}")
                        } else {
                            let errorResponse = "{\"operation\":\"clear_isnew\",\"error\":\"Failed to clear isNew flag\",\"success\":0}"
                            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                            ResponseView.json(ctx, errorResponse)
                        }
                        return
                    case None => ()
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
                let archiveIdInt = ArchiveDao.getArchiveInternalId(id)
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
            case None => return // requireUser 已经设置了错误响应
        }
    }

    /**
     * 更新用户阅读进度并自动标记为已读（PUT /api/archives/{id}/progress/{page}）
     */
    public static func updateProgress(ctx: Ctx): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.paramsOpt("id") ?? ""
                let pageParam = ctx.paramsOpt("page") ?? ""

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

                // Source: 复合 ID — 真实持久化
                match (SourceRequestResolver.parseFromCompositeId(id)) {
                    case Some(_) =>
                        let ok = UserTargetStatusDao.updateProgress(userId, "source_archive", id, progress)
                        if (ok) {
                            let result = "{\"operation\":\"update_progress\",\"progress\":${progress},\"success\":1}"
                            ResponseView.json(ctx, result)
                        } else {
                            let errorResponse = "{\"operation\":\"update_progress\",\"error\":\"Failed to update progress\",\"success\":0}"
                            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                            ResponseView.json(ctx, errorResponse)
                        }
                        return
                    case None => ()
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
                let archiveIdInt = ArchiveDao.getArchiveInternalId(id)
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
            case None => return // requireUser 已经设置了错误响应
        }
    }

    /**
     * 添加收藏（PUT /api/archives/{id}/favorite）
     */
    public static func addFavorite(ctx: Ctx): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.paramsOpt("id") ?? ""

                // 检查ID是否为空
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"add_favorite\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // Source: 复合 ID — 真实持久化
                match (SourceRequestResolver.parseFromCompositeId(id)) {
                    case Some(_) =>
                        let ok = UserTargetFavoritesDao.addFavorite(userId, "source_archive", id)
                        if (ok) {
                            ResponseView.json(ctx, "{\"operation\":\"add_favorite\",\"success\":1}")
                        } else {
                            let errorResponse = "{\"operation\":\"add_favorite\",\"error\":\"Failed to add favorite\",\"success\":0}"
                            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                            ResponseView.json(ctx, errorResponse)
                        }
                        return
                    case None => ()
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
                let archiveIdInt = ArchiveDao.getArchiveInternalId(id)
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
            case None => return // requireUser 已经设置了错误响应
        }
    }

    /**
     * 取消收藏（DELETE /api/archives/{id}/favorite）
     */
    public static func removeFavorite(ctx: Ctx): Unit {
        // 获取用户ID
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.paramsOpt("id") ?? ""

                // 检查ID是否为空
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"remove_favorite\",\"error\":\"No archive ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ResponseView.json(ctx, errorResponse)
                    return
                }

                // Source: 复合 ID — 真实持久化
                match (SourceRequestResolver.parseFromCompositeId(id)) {
                    case Some(_) =>
                        let ok = UserTargetFavoritesDao.removeFavorite(userId, "source_archive", id)
                        if (ok) {
                            ResponseView.json(ctx, "{\"operation\":\"remove_favorite\",\"success\":1}")
                        } else {
                            let errorResponse = "{\"operation\":\"remove_favorite\",\"error\":\"Failed to remove favorite\",\"success\":0}"
                            ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                            ResponseView.json(ctx, errorResponse)
                        }
                        return
                    case None => ()
                }

                // 获取归档的数据库内部ID
                let archiveIdInt = ArchiveDao.getArchiveInternalId(id)
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
            case None => return // requireUser 已经设置了错误响应
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
            case None => return // requireUser 已经设置了错误响应
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
                    case Some(s) => try {
                        Int32.parse(s)
                    } catch (_: Exception) {
                        0i32
                    }
                    case None => 0i32
                }

                let count = match (countParam) {
                    case Some(c) => try {
                        Int32.parse(c)
                    } catch (_: Exception) {
                        100i32
                    }
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
                    let archiveIdInt = ArchiveDao.getArchiveInternalId(archive.id)
                    let isNew = if (archiveIdInt > 0) {
                        UserArchiveStatusDao.isNew(userId, archiveIdInt)
                    } else {
                        true
                    }

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
            case None => return // requireUser 已经设置了错误响应
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
                    case Some(s) => try {
                        Int32.parse(s)
                    } catch (_: Exception) {
                        0i32
                    }
                    case None => 0i32
                }

                let count = match (countParam) {
                    case Some(c) => try {
                        Int32.parse(c)
                    } catch (_: Exception) {
                        100i32
                    }
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
                    let archiveIdInt = ArchiveDao.getArchiveInternalId(archive.id)
                    let isFavorite = if (archiveIdInt > 0) {
                        UserFavoriteDao.isFavorite(userId, archiveIdInt)
                    } else {
                        false
                    }

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
            case None => return // requireUser 已经设置了错误响应
        }
    }
}

private class ArchiveFilesPageItem {
    public var href: String = ""
    public var fileType: String = ""
    public var title: String = ""
    public var description: String = ""
    public var releaseAt: String = ""
    public var thumbAssetId: Int64 = 0
    public var attachments: Array<PageAttachmentData> = Array<PageAttachmentData>()
    public var sortIndex: Int32 = 0
    public var originalIndex: Int32 = 0
    public var hidden: Bool = false
    public var hasSort: Bool = false
}

private class ArchiveFilesPageGroup {
    public var groupKey: String = ""
    public var fileType: String = ""
    public var defaultSource: ArchiveFilesPageItem = ArchiveFilesPageItem()
    public var sources: ArrayList<ArchiveFilesPageItem> = ArrayList<ArchiveFilesPageItem>()
}
