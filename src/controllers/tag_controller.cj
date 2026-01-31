package lanlu.controllers

import cjoy.*
import stdx.log.*
import std.time.DateTime
import std.collection.*
import std.convert.*
import std.fs.*
import std.io.*
import stdx.encoding.json.stream.*
import lanlu.services.*
import lanlu.dao.*
import lanlu.models.*
import lanlu.utils.*
import lanlu.views.*

/**
 * 标签控制器
 * - 普通接口：获取标签翻译映射（用于前端展示）
 * - 管理接口：管理员维护、导入导出
 */
public class TagController {
    private static let CACHE_DIR = "./data/cache"
    private static let IMPORT_CHUNK_SIZE: Int64 = 1536 * 1024 // 1.5MB

    private static func langFromQuery(ctx: JoyContext): String {
        let lang = (ctx.getQuery("lang") ?? "").trimAscii()
        if (lang.size == 0) { return "zh" }
        return lang
    }

    private static func readStringFlexible(r: JsonReader): String {
        return r.readValue<String>().trimAscii()
    }

    private static func parseTranslationsFromReader(r: JsonReader): HashMap<String, TagTranslation> {
        var result = HashMap<String, TagTranslation>()
        match (r.peek()) {
            case Some(BeginObject) =>
                r.startObject()
                while (r.peek() != EndObject) {
                    let lang = r.readName()
                    let t = TagTranslation()
                    match (r.peek()) {
                        case Some(BeginObject) =>
                            r.startObject()
                            while (r.peek() != EndObject) {
                                let k = r.readName()
                                match (k) {
                                    case "text" => t.text = r.readValue<String>()
                                    case "intro" => t.intro = r.readValue<String>()
                                    case _ => r.skip()
                                }
                            }
                            r.endObject()
                            result[lang] = t
                        case Some(_) =>
                            r.skip()
                        case None => break
                    }
                }
                r.endObject()
            case _ => ()
        }
        return result
    }

    /**
     * GET /api/tags/translations?lang=zh|en[&arcid=...][&tankoubon_id=...]
     * 返回: { lang, map: { "<namespace:name>": "<text>" } }
     * 如果提供 arcid，则只返回该档案相关的 tag 翻译
     * 如果提供 tankoubon_id，则返回该合集相关的所有 tag 翻译（合集自身标签 + 所有归档标签）
     */
    public static func getTranslations(ctx: JoyContext): Unit {
        let lang = langFromQuery(ctx)
        let arcid = (ctx.getQuery("arcid") ?? "").trimAscii()
        let tankoubonId = (ctx.getQuery("tankoubon_id") ?? "").trimAscii()

        var translationsMap = TagDao.getTranslationsMap(lang)

        // 如果指定了 arcid，则只返回该档案相关的 tag 翻译
        if (arcid.size > 0) {
            let archive = ArchiveDao.getArchiveMetadataById(arcid)
            if (archive.id.size == 0) {
                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("lang").writeValue(lang)
                w.writeName("map")
                w.startObject()
                w.endObject()
                w.endObject()
                w.flush()
                ResponseView.successJson(ctx, String.fromUtf8(readToEnd(out)), "获取标签翻译成功")
                return
            }

            // 解析档案的 tags 字符串，构建 tag 集合
            let tagSet = HashSet<String>()
            let tagsStr = archive.tags.trimAscii()
            if (tagsStr.size > 0) {
                let tagParts = tagsStr.split(",")
                for (part in tagParts) {
                    let t = part.trimAscii()
                    if (t.size > 0) {
                        tagSet.add(t)
                    }
                }
            }

            // 过滤：只保留档案拥有的 tag
            var filteredMap = HashMap<String, String>()
            for ((tag, text) in translationsMap) {
                if (tagSet.contains(tag)) {
                    filteredMap[tag] = text
                }
            }
            translationsMap = filteredMap
        }
        // 如果指定了 tankoubon_id，则返回该合集相关的所有 tag 翻译
        else if (tankoubonId.size > 0) {
            match (TankoubonDao.getTankoubonById(tankoubonId)) {
                case Some(tankoubon) =>
                    // 构建 tag 集合：所有归档标签（tankoubon 自身标签现在也通过关联表获取，但这里只需要归档标签）
                    let tagSet = HashSet<String>()

                    // 添加所有归档的标签
                    for (archiveArcid in tankoubon.archives) {
                        let archiveTags = TagDao.getArchiveTags(archiveArcid)
                        if (archiveTags.size > 0) {
                            for (part in archiveTags.split(",")) {
                                let t = part.trimAscii()
                                if (t.size > 0 && !TagDao.isSourceTag(t)) {
                                    tagSet.add(t)
                                }
                            }
                        }
                    }

                    // 过滤：只保留合集相关的 tag
                    var filteredMap = HashMap<String, String>()
                    for ((tag, text) in translationsMap) {
                        if (tagSet.contains(tag)) {
                            filteredMap[tag] = text
                        }
                    }
                    translationsMap = filteredMap
                case None =>
                    // tankoubon 不存在，返回空映射
                    let out = ByteBuffer()
                    let w = JsonWriter(out)
                    w.startObject()
                    w.writeName("lang").writeValue(lang)
                    w.writeName("map")
                    w.startObject()
                    w.endObject()
                    w.endObject()
                    w.flush()
                    ResponseView.successJson(ctx, String.fromUtf8(readToEnd(out)), "获取标签翻译成功")
                    return
            }
        }

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("lang").writeValue(lang)
        w.writeName("map")
        w.startObject()
        for ((tag, text) in translationsMap) {
            w.writeName(tag).writeValue(text)
        }
        w.endObject()
        w.endObject()
        w.flush()
        ResponseView.successJson(ctx, String.fromUtf8(readToEnd(out)), "获取标签翻译成功")
    }

    /**
     * GET /api/tags?namespace=...&q=...&limit=...&offset=...
     * 返回: { items: [...], total, limit, offset }
     */
    public static func list(ctx: JoyContext): Unit {
        let namespaceStr = (ctx.getQuery("namespace") ?? "").trimAscii()
        let q = (ctx.getQuery("q") ?? "").trimAscii()
        let limitStr = (ctx.getQuery("limit") ?? "100").trimAscii()
        let offsetStr = (ctx.getQuery("offset") ?? "0").trimAscii()

        var limit: Int64 = 100
        var offset: Int64 = 0
        try { limit = Int64.parse(limitStr) } catch (_: Exception) {}
        try { offset = Int64.parse(offsetStr) } catch (_: Exception) {}

        if (limit <= 0) { limit = 100 }
        if (limit > 2000) { limit = 2000 }
        if (offset < 0) { offset = 0 }

        let namespace: ?String = if (namespaceStr.size > 0) { Some(namespaceStr) } else { None }
        let query: ?String = if (q.size > 0) { Some(q) } else { None }

        let total = TagDao.count(namespace, query)
        let rows = TagDao.list(namespace, query, limit, offset)

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("items")
        w.startArray()
        for (row in rows) {
            w.startObject()
            w.writeName("id").writeValue(row.id)
            w.writeName("namespace").writeValue(row.namespace)
            w.writeName("name").writeValue(row.name)
            w.writeName("translations")
            w.startObject()
            for ((lang, t) in row.translations) {
                w.writeName(lang)
                w.startObject()
                w.writeName("text").writeValue(t.text)
                w.writeName("intro").writeValue(t.intro)
                w.endObject()
            }
            w.endObject()
            w.writeName("links").writeValue(row.links)
            w.writeName("iconAssetId").writeValue(row.iconAssetId)
            w.writeName("backgroundAssetId").writeValue(row.backgroundAssetId)
            w.writeName("created_at").writeValue(row.created_at)
            w.writeName("updated_at").writeValue(row.updated_at)
            w.endObject()
        }
        w.endArray()
        w.writeName("total").writeValue(total)
        w.writeName("limit").writeValue(limit)
        w.writeName("offset").writeValue(offset)
        w.endObject()
        w.flush()
        ResponseView.successJson(ctx, String.fromUtf8(readToEnd(out)), "获取标签列表成功")
    }

    /**
     * GET /api/tags/{id}
     */
    public static func getById(ctx: JoyContext): Unit {
        let idStr = (ctx.getParam("id") ?? "").trimAscii()
        if (idStr.size == 0) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "id is required", 400)
            return
        }

        var id: Int64 = 0
        try { id = Int64.parse(idStr) } catch (_: Exception) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "invalid id", 400)
            return
        }

        match (TagDao.getById(id)) {
            case Some(tag) =>
                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("id").writeValue(tag.id)
                w.writeName("namespace").writeValue(tag.namespace)
                w.writeName("name").writeValue(tag.name)
                w.writeName("translations")
                w.startObject()
                for ((lang, t) in tag.translations) {
                    w.writeName(lang)
                    w.startObject()
                    w.writeName("text").writeValue(t.text)
                    w.writeName("intro").writeValue(t.intro)
                    w.endObject()
                }
                w.endObject()
                w.writeName("links").writeValue(tag.links)
                w.writeName("iconAssetId").writeValue(tag.iconAssetId)
                w.writeName("backgroundAssetId").writeValue(tag.backgroundAssetId)
                w.writeName("created_at").writeValue(tag.created_at)
                w.writeName("updated_at").writeValue(tag.updated_at)
                w.endObject()
                w.flush()
                ResponseView.successJson(ctx, String.fromUtf8(readToEnd(out)), "获取标签成功")
            case None =>
                ctx.status(404)
                ResponseView.errorJson(ctx, "tag not found", 404)
        }
    }

    /**
     * GET /api/tags/by-name?tag=namespace:name
     * 也支持: ?namespace=...&name=...
     */
    public static func getByName(ctx: JoyContext): Unit {
        let tagStr = (ctx.getQuery("tag") ?? "").trimAscii()
        let namespaceQ = (ctx.getQuery("namespace") ?? "").trimAscii()
        let nameQ = (ctx.getQuery("name") ?? "").trimAscii()

        var namespace = namespaceQ
        var name = nameQ
        if (tagStr.size > 0) {
            let (ns, nm) = TagDao.parseTagName(tagStr)
            namespace = ns
            name = nm
        }

        if (name.trimAscii().size == 0) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "tag/name is required", 400)
            return
        }

        match (TagDao.getByNamespaceName(namespace, name)) {
            case Some(tag) =>
                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("id").writeValue(tag.id)
                w.writeName("namespace").writeValue(tag.namespace)
                w.writeName("name").writeValue(tag.name)
                w.writeName("translations")
                w.startObject()
                for ((lang, t) in tag.translations) {
                    w.writeName(lang)
                    w.startObject()
                    w.writeName("text").writeValue(t.text)
                    w.writeName("intro").writeValue(t.intro)
                    w.endObject()
                }
                w.endObject()
                w.writeName("links").writeValue(tag.links)
                w.writeName("iconAssetId").writeValue(tag.iconAssetId)
                w.writeName("backgroundAssetId").writeValue(tag.backgroundAssetId)
                w.writeName("created_at").writeValue(tag.created_at)
                w.writeName("updated_at").writeValue(tag.updated_at)
                w.endObject()
                w.flush()
                ResponseView.successJson(ctx, String.fromUtf8(readToEnd(out)), "获取标签成功")
            case None =>
                ctx.status(404)
                ResponseView.errorJson(ctx, "tag not found", 404)
        }
    }

    /**
     * PUT /api/admin/tags/{id}/icon
     * Body: raw image bytes
     */
    public static func adminUploadIcon(ctx: JoyContext, adminUserId: Int64): Unit {
        let idStr = (ctx.getParam("id") ?? "").trimAscii()
        var id: Int64 = 0
        try { id = Int64.parse(idStr) } catch (_: Exception) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "invalid id", 400)
            return
        }

        let raw = ctx.readRawData()
        if (raw.size <= 0) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "empty body", 400)
            return
        }

        // Validate tag exists
        let tagOpt = TagDao.getById(id)
        if (tagOpt.isNone()) {
            ctx.status(404)
            ResponseView.errorJson(ctx, "tag not found", 404)
            return
        }
        let tag = tagOpt.getOrThrow()

        let cacheRoot = SystemSettingsService.getPath("CACHE_PATH")
        let assetRoot = SystemSettingsService.getPath("ASSET_PATH")
        FileUtils.ensureDirectoryExists(Path(cacheRoot))
        FileUtils.ensureDirectoryExists(Path(assetRoot))

        let filename = (ctx.getHeader("X-Filename") ?? "tag_icon").trimAscii()
        let inferredExt = ArchiveUtils.getFileExtension(filename)

        let ts = DateTime.now().toUnixTimeStamp().toSeconds()
        let tempDir = FileUtils.joinPath(cacheRoot, "tag_icon/${id.toString()}_${ts.toString()}")
        FileUtils.ensureDirectoryExists(Path(tempDir))
        let inputPath = FileUtils.joinPath(tempDir, "input.${inferredExt}")
        let outputAvifPath = FileUtils.joinPath(tempDir, "icon.avif")

        try {
            let f = File(Path(inputPath), Write)
            f.write(raw)
            f.close()
        } catch (e: Exception) {
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            ctx.status(500)
            ResponseView.errorJson(ctx, "failed to write temp file", 500)
            return
        }

        // Reuse avatar policy: center-crop square 256x256 then server stores AVIF.
        let (convertRes, thumbHashFromConvert) = ArchiveUtils.convertAvatarToAvifWithThumbHash(inputPath, outputAvifPath, tempDir)
        if (!convertRes.success) {
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            ctx.status(422)
            ResponseView.errorJson(ctx, "icon conversion failed", 422)
            return
        }

        let thumbHash = if (thumbHashFromConvert.size > 0) { thumbHashFromConvert }
            else { try { ThumbHashUtils.calculateAvifThumbHashFromFile(outputAvifPath) } catch (_: Exception) { "" } }
        let byteSize = try { Int64(FileInfo(Path(outputAvifPath)).size) } catch (_: Exception) { 0 }

        // Delete previous icon asset (best-effort)
        if (tag.iconAssetId > 0) {
            try {
                let oldPath = FileUtils.joinPath(assetRoot, "${tag.iconAssetId}.avif")
                try { remove(Path(oldPath)) } catch (_: Exception) {}
                let _ = AssetDao.deleteById(tag.iconAssetId)
            } catch (_: Exception) {}
        }

        match (AssetDao.create(Some(adminUserId), "tag_icon", filename, "image/avif", "avif", byteSize, thumbHash)) {
            case Some(assetId) =>
                let finalPath = FileUtils.joinPath(assetRoot, "${assetId}.avif")
                try {
                    FileUtils.safeReplaceFile(Path(finalPath), Path(outputAvifPath))
                } catch (e: Exception) {
                    let _ = FileUtils.removeFileOrDirectory(tempDir)
                    ctx.status(500)
                    ResponseView.errorJson(ctx, "failed to store icon", 500)
                    return
                }

                if (!TagDao.updateIconAssetId(id, assetId)) {
                    let _ = FileUtils.removeFileOrDirectory(tempDir)
                    ctx.status(500)
                    ResponseView.errorJson(ctx, "failed to update tag icon", 500)
                    return
                }

                let _ = FileUtils.removeFileOrDirectory(tempDir)
                ResponseView.successJson(ctx, "{\"success\":1,\"iconAssetId\":${assetId.toString()}}", "更新成功")
            case None =>
                let _ = FileUtils.removeFileOrDirectory(tempDir)
                ctx.status(500)
                ResponseView.errorJson(ctx, "failed to create asset record", 500)
        }
    }

    /**
     * PUT /api/admin/tags/{id}/background
     * Body: raw image bytes
     */
    public static func adminUploadBackground(ctx: JoyContext, adminUserId: Int64): Unit {
        let idStr = (ctx.getParam("id") ?? "").trimAscii()
        var id: Int64 = 0
        try { id = Int64.parse(idStr) } catch (_: Exception) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "invalid id", 400)
            return
        }

        let raw = ctx.readRawData()
        if (raw.size <= 0) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "empty body", 400)
            return
        }

        // Validate tag exists
        let tagOpt = TagDao.getById(id)
        if (tagOpt.isNone()) {
            ctx.status(404)
            ResponseView.errorJson(ctx, "tag not found", 404)
            return
        }
        let tag = tagOpt.getOrThrow()

        let cacheRoot = SystemSettingsService.getPath("CACHE_PATH")
        let assetRoot = SystemSettingsService.getPath("ASSET_PATH")
        FileUtils.ensureDirectoryExists(Path(cacheRoot))
        FileUtils.ensureDirectoryExists(Path(assetRoot))

        let filename = (ctx.getHeader("X-Filename") ?? "tag_background").trimAscii()
        let inferredExt = ArchiveUtils.getFileExtension(filename)

        let ts = DateTime.now().toUnixTimeStamp().toSeconds()
        let tempDir = FileUtils.joinPath(cacheRoot, "tag_background/${id.toString()}_${ts.toString()}")
        FileUtils.ensureDirectoryExists(Path(tempDir))
        let inputPath = FileUtils.joinPath(tempDir, "input.${inferredExt}")
        let outputAvifPath = FileUtils.joinPath(tempDir, "background.avif")

        try {
            let f = File(Path(inputPath), Write)
            f.write(raw)
            f.close()
        } catch (_: Exception) {
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            ctx.status(500)
            ResponseView.errorJson(ctx, "failed to write temp file", 500)
            return
        }

        let (convertRes, thumbHashFromConvert2) = ArchiveUtils.convertTagBackgroundToAvifWithThumbHash(inputPath, outputAvifPath, tempDir)
        if (!convertRes.success) {
            let _ = FileUtils.removeFileOrDirectory(tempDir)
            ctx.status(422)
            ResponseView.errorJson(ctx, "background conversion failed", 422)
            return
        }

        let thumbHash = if (thumbHashFromConvert2.size > 0) { thumbHashFromConvert2 }
            else { try { ThumbHashUtils.calculateAvifThumbHashFromFile(outputAvifPath) } catch (_: Exception) { "" } }
        let byteSize = try { Int64(FileInfo(Path(outputAvifPath)).size) } catch (_: Exception) { 0 }

        // Delete previous background asset (best-effort)
        if (tag.backgroundAssetId > 0) {
            try {
                let oldPath = FileUtils.joinPath(assetRoot, "${tag.backgroundAssetId}.avif")
                try { remove(Path(oldPath)) } catch (_: Exception) {}
                let _ = AssetDao.deleteById(tag.backgroundAssetId)
            } catch (_: Exception) {}
        }

        match (AssetDao.create(Some(adminUserId), "tag_background", filename, "image/avif", "avif", byteSize, thumbHash)) {
            case Some(assetId) =>
                let finalPath = FileUtils.joinPath(assetRoot, "${assetId}.avif")
                try {
                    FileUtils.safeReplaceFile(Path(finalPath), Path(outputAvifPath))
                } catch (_: Exception) {
                    let _ = FileUtils.removeFileOrDirectory(tempDir)
                    ctx.status(500)
                    ResponseView.errorJson(ctx, "failed to store background", 500)
                    return
                }

                if (!TagDao.updateBackgroundAssetId(id, assetId)) {
                    let _ = FileUtils.removeFileOrDirectory(tempDir)
                    ctx.status(500)
                    ResponseView.errorJson(ctx, "failed to update tag background", 500)
                    return
                }

                let _ = FileUtils.removeFileOrDirectory(tempDir)
                ResponseView.successJson(ctx, "{\"success\":1,\"backgroundAssetId\":${assetId.toString()}}", "更新成功")
            case None =>
                let _ = FileUtils.removeFileOrDirectory(tempDir)
                ctx.status(500)
                ResponseView.errorJson(ctx, "failed to create asset record", 500)
        }
    }

    /**
     * GET /api/tags/namespaces
     * 返回所有命名空间
     */
    public static func listNamespaces(ctx: JoyContext): Unit {
        let namespaces = TagDao.listNamespaces()
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("namespaces")
        w.startArray()
        for (ns in namespaces) {
            w.writeValue(ns)
        }
        w.endArray()
        w.endObject()
        w.flush()
        ResponseView.successJson(ctx, String.fromUtf8(readToEnd(out)), "获取命名空间列表成功")
    }

    /**
     * GET /api/tags/autocomplete?q=...&lang=zh|en&limit=10[&require_bound=0|1]
     * 返回自动补全建议列表
     */
    public static func autocomplete(ctx: JoyContext): Unit {
        let query = (ctx.getQuery("q") ?? "").trimAscii()
        let lang = langFromQuery(ctx)
        let limitStr = (ctx.getQuery("limit") ?? "10").trimAscii()
        let requireBoundStr = (ctx.getQuery("require_bound") ?? "1").trimAscii()

        var limit: Int64 = 10
        try { limit = Int64.parse(limitStr) } catch (_: Exception) {}
        if (limit <= 0) { limit = 10 }
        if (limit > 50) { limit = 50 }

        if (query.size == 0) {
            ResponseView.successJson(ctx, "{\"suggestions\":[]}", "获取自动补全建议成功")
            return
        }

        // Default behavior keeps search suggestions "in use" (bound to archives).
        // Some UIs (e.g. archive tag editor) need to suggest all tags, including unbound ones.
        let requireBound: Bool = !(requireBoundStr == "0" || requireBoundStr == "false")
        let results = TagDao.autocompleteSearch(query, lang, limit, requireBound)

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("suggestions")
        w.startArray()
        for ((fullName, translatedText) in results) {
            // 返回格式：{ value: "namespace:name", label: "翻译文本", display: "namespace:翻译文本" }
            let (namespace, _) = TagDao.parseTagName(fullName)
            let display = if (namespace.size > 0) {
                "${namespace}:${translatedText}"
            } else {
                translatedText
            }
            w.startObject()
            w.writeName("value").writeValue(fullName)
            w.writeName("label").writeValue(translatedText)
            w.writeName("display").writeValue(display)
            w.endObject()
        }
        w.endArray()
        w.endObject()
        w.flush()
        ResponseView.successJson(ctx, String.fromUtf8(readToEnd(out)), "获取自动补全建议成功")
    }

    /**
     * GET /api/tags/cloud?lang=...&limit=...
     * 返回: { items: [{ tag, display, count }], total }
     */
    public static func cloud(ctx: JoyContext): Unit {
        let lang = (ctx.getQuery("lang") ?? "zh").trimAscii()
        let limitStr = (ctx.getQuery("limit") ?? "200").trimAscii()
        var limit: Int64 = 200
        try { limit = Int64.parse(limitStr) } catch (_: Exception) {}
        if (limit <= 0) { limit = 200 }
        if (limit > 1000) { limit = 1000 }

        let rows = TagDao.getTagCloud(lang, limit)

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("items")
        w.startArray()
        for ((tag, display, count) in rows) {
            w.startObject()
            w.writeName("tag").writeValue(tag)
            w.writeName("display").writeValue(display)
            w.writeName("count").writeValue(count)
            w.endObject()
        }
        w.endArray()
        w.writeName("total").writeValue(rows.size)
        w.endObject()
        w.flush()
        ResponseView.successJson(ctx, String.fromUtf8(readToEnd(out)), "获取标签词云成功")
    }

    /**
     * GET /api/admin/tags/names
     * 返回所有标签名（用于自动补全）
     */
    public static func adminListTagNames(ctx: JoyContext): Unit {
        let tags = TagDao.listAllTagNames()
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("tags")
        w.startArray()
        for (tag in tags) {
            w.writeValue(tag)
        }
        w.endArray()
        w.endObject()
        w.flush()
        ResponseView.successJson(ctx, String.fromUtf8(readToEnd(out)), "获取标签名列表成功")
    }

    /**
     * POST /api/admin/tags
     * body: { namespace, name, translations: { zh: {text, intro}, en: {...} }, links }
     */
    public static func adminCreate(ctx: JoyContext): Unit {
        let logger = getLogger("tag_controller")
        try {
            let body = ctx.readString()
            if (body.trimAscii().size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "Empty body", 400)
                return
            }

            var namespace = ""
            var name = ""
            var links = ""
            var translations = HashMap<String, TagTranslation>()
            try {
                var buf = ByteBuffer()
                unsafe { buf.write(body.rawData()) }
                let r = JsonReader(buf)
                match (r.peek()) {
                    case Some(BeginObject) =>
                        r.startObject()
                        while (r.peek() != EndObject) {
                            let k = r.readName()
                            match (k) {
                                case "namespace" => namespace = readStringFlexible(r)
                                case "name" => name = readStringFlexible(r)
                                case "links" => links = readStringFlexible(r)
                                case "translations" => translations = parseTranslationsFromReader(r)
                                case _ => r.skip()
                            }
                        }
                        r.endObject()
                    case _ => ()
                }
            } catch (_: Exception) {
                ()
            }

            if (name.size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "name is required", 400)
                return
            }

            let id = TagDao.create(namespace, name, translations, links)
            if (id == 0) {
                ctx.status(500)
                ResponseView.errorJson(ctx, "Create failed", 500)
                return
            }
            ResponseView.successJson(ctx, "{\"success\":1,\"id\":${id.toString()}}", "创建成功")
        } catch (e: Exception) {
            logger.error("adminCreate异常", ("error", e.message))
            ctx.status(500)
            ResponseView.errorJson(ctx, "Internal error", 500)
        }
    }

    /**
     * PUT /api/admin/tags/{id}
     * body: { translations: {...}, links }
     */
    public static func adminUpdate(ctx: JoyContext): Unit {
        let logger = getLogger("tag_controller")
        try {
            let idStr = (ctx.getParam("id") ?? "").trimAscii()
            if (idStr.size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "id is required", 400)
                return
            }

            var id: Int64 = 0
            try { id = Int64.parse(idStr) } catch (_: Exception) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "invalid id", 400)
                return
            }

            let body = ctx.readString()
            if (body.trimAscii().size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "Empty body", 400)
                return
            }

            var links = ""
            var translations = HashMap<String, TagTranslation>()
            try {
                var buf = ByteBuffer()
                unsafe { buf.write(body.rawData()) }
                let r = JsonReader(buf)
                match (r.peek()) {
                    case Some(BeginObject) =>
                        r.startObject()
                        while (r.peek() != EndObject) {
                            let k = r.readName()
                            match (k) {
                                case "links" => links = readStringFlexible(r)
                                case "translations" => translations = parseTranslationsFromReader(r)
                                case _ => r.skip()
                            }
                        }
                        r.endObject()
                    case _ => ()
                }
            } catch (_: Exception) {
                ()
            }

            let ok = TagDao.update(id, translations, links)
            if (!ok) {
                ctx.status(500)
                ResponseView.errorJson(ctx, "Update failed", 500)
                return
            }
            ResponseView.successJson(ctx, "{\"success\":1}", "更新成功")
        } catch (e: Exception) {
            logger.error("adminUpdate异常", ("error", e.message))
            ctx.status(500)
            ResponseView.errorJson(ctx, "Internal error", 500)
        }
    }

    /**
     * DELETE /api/admin/tags/{id}
     */
    public static func adminDelete(ctx: JoyContext): Unit {
        let idStr = (ctx.getParam("id") ?? "").trimAscii()
        if (idStr.size == 0) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "id is required", 400)
            return
        }

        var id: Int64 = 0
        try { id = Int64.parse(idStr) } catch (_: Exception) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "invalid id", 400)
            return
        }

        let ok = TagDao.delete(id)
        if (!ok) {
            ctx.status(500)
            ResponseView.errorJson(ctx, "Delete failed", 500)
            return
        }
        ResponseView.successJson(ctx, "{\"success\":1}", "删除成功")
    }

    /**
     * GET /api/admin/tags/export
     * 返回: { tags: [...], generated_at }
     */
    public static func adminExport(ctx: JoyContext): Unit {
        let rows = TagDao.list(None, None, 200000, 0)
        let now = DateTime.nowUTC().toString()
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("generated_at").writeValue(now)
        w.writeName("tags")
        w.startArray()
        for (row in rows) {
            w.startObject()
            w.writeName("namespace").writeValue(row.namespace)
            w.writeName("name").writeValue(row.name)
            w.writeName("translations")
            w.startObject()
            for ((lang, t) in row.translations) {
                w.writeName(lang)
                w.startObject()
                w.writeName("text").writeValue(t.text)
                w.writeName("intro").writeValue(t.intro)
                w.endObject()
            }
            w.endObject()
            w.writeName("links").writeValue(row.links)
            w.endObject()
        }
        w.endArray()
        w.endObject()
        w.flush()
        ResponseView.successJson(ctx, String.fromUtf8(readToEnd(out)), "导出成功")
    }

    /**
     * POST /api/admin/tags/import
     * 支持 EhTagTranslation 格式和简化格式
     */
    public static func adminImport(ctx: JoyContext): Unit {
        let logger = getLogger("tag_controller")
        try {
            let taskData = TaskData()
            taskData.name = "标签导入"
            taskData.taskType = "tag_import"
            taskData.status = "waiting_upload"
            taskData.progress = 0
            taskData.message = "等待上传导入文件"
            taskData.parameters = ""
            let created = TaskDao.createTaskData(taskData)
            if (!created || taskData.id == 0) {
                ctx.status(500)
                ResponseView.errorJson(ctx, "Create task failed", 500)
                return
            }
            let taskId = taskData.id

            let taskDir = Path("${CACHE_DIR}/task/${taskId.toString()}")
            if (!exists(taskDir)) {
                Directory.create(taskDir, recursive: true)
            }
            let jsonFile = Path("${taskDir}/tag_import.json")
            let fileData = ctx.readRawData()
            try (file = File(jsonFile, Write)) {
                file.write(fileData)
            }

            let size = FileInfo(jsonFile).size
            if (size <= 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "Empty body", 400)
                return
            }

            TaskDao.updateTaskParameters(taskId, jsonFile.toString())
            TaskDao.updateTaskStatus(taskId, "pending", "文件已上传，等待导入", 0)
            TaskIO.appendLog(taskId, "enqueued tag_import")
            TaskPoolService.getInstance().notifyTaskAvailable()

            let data = "{\"success\":1,\"job\":${taskId.toString()},\"operation\":\"tag_import\"}"
            ResponseView.successJson(ctx, data, "已入队导入任务")
        } catch (e: Exception) {
            logger.error("adminImport异常", ("error", e.message))
            ctx.status(500)
            ResponseView.errorJson(ctx, "Internal error", 500)
        }
    }

    /**
     * POST /api/admin/tags/import/init
     */
    public static func adminImportInit(ctx: JoyContext): Unit {
        let logger = getLogger("tag_controller")
        try {
            let taskData = TaskData()
            taskData.name = "标签导入"
            taskData.taskType = "tag_import"
            taskData.status = "waiting_upload"
            taskData.progress = 0
            taskData.message = "等待上传导入文件"
            taskData.parameters = ""
            let created = TaskDao.createTaskData(taskData)
            if (!created || taskData.id == 0) {
                ctx.status(500)
                ResponseView.errorJson(ctx, "Create task failed", 500)
                return
            }

            let taskId = taskData.id
            let taskDir = Path("${CACHE_DIR}/task/${taskId.toString()}")
            if (!exists(taskDir)) {
                Directory.create(taskDir, recursive: true)
            }
            let jsonFile = Path("${taskDir}/tag_import.json")

            TaskDao.updateTaskParameters(taskId, jsonFile.toString())
            TaskIO.appendLog(taskId, "created, waiting_upload")

            let data = "{\"success\":1,\"job\":${taskId.toString()},\"operation\":\"tag_import\",\"chunk_size\":${IMPORT_CHUNK_SIZE.toString()}}"
            ResponseView.successJson(ctx, data, "已创建导入任务")
        } catch (e: Exception) {
            logger.error("adminImportInit异常", ("error", e.message))
            ctx.status(500)
            ResponseView.errorJson(ctx, "Internal error", 500)
        }
    }

    /**
     * PUT /api/admin/tags/import/chunk?job=...&chunkIndex=...&totalChunks=...
     */
    public static func adminImportUploadChunk(ctx: JoyContext): Unit {
        let logger = getLogger("tag_controller")
        try {
            let jobStr = (ctx.getQuery("job") ?? "").trimAscii()
            let chunkIndexStr = (ctx.getQuery("chunkIndex") ?? "").trimAscii()
            let totalChunksStr = (ctx.getQuery("totalChunks") ?? "").trimAscii()
            if (jobStr.size == 0 || chunkIndexStr.size == 0 || totalChunksStr.size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "job, chunkIndex and totalChunks are required", 400)
                return
            }

            let jobId = try {
                Int64.parse(jobStr)
            } catch (_: Exception) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "invalid job", 400)
                return
            }

            let chunkIndex = try {
                Int64.parse(chunkIndexStr)
            } catch (_: Exception) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "invalid chunkIndex", 400)
                return
            }

            let totalChunks = try {
                Int64.parse(totalChunksStr)
            } catch (_: Exception) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "invalid totalChunks", 400)
                return
            }

            if (chunkIndex < 0 || totalChunks <= 0 || chunkIndex >= totalChunks) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "invalid chunk range", 400)
                return
            }

            let taskData = TaskDao.getTaskDataById(jobId)
            if (taskData.id == 0 || taskData.taskType != "tag_import") {
                ctx.status(404)
                ResponseView.errorJson(ctx, "job not found", 404)
                return
            }

            if (taskData.status != "waiting_upload") {
                ctx.status(409)
                ResponseView.errorJson(ctx, "job is not ready for upload", 409)
                return
            }

            let jsonPathStr = taskData.parameters.trimAscii()
            if (jsonPathStr.size == 0) {
                ctx.status(500)
                ResponseView.errorJson(ctx, "job has no upload path", 500)
                return
            }

            let jsonFile = Path(jsonPathStr)
            let parent = jsonFile.parent
            if (parent.toString().trimAscii().size > 0 && !exists(parent)) {
                Directory.create(parent, recursive: true)
            }

            let chunkFile = Path("${parent.toString()}/chunk_${chunkIndex.toString()}.bin")
            let fileData = ctx.readRawData()
            try (file = File(chunkFile, Write)) {
                file.write(fileData)
            }

            let size = FileInfo(chunkFile).size
            if (size <= 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "Empty body", 400)
                return
            }

            TaskIO.appendLog(jobId, "uploaded chunk=${chunkIndex.toString()}/${totalChunks.toString()} size=${size.toString()}")

            let data = "{\"success\":1,\"job\":${jobId.toString()},\"operation\":\"tag_import\"}"
            ResponseView.successJson(ctx, data, "已上传分片")
        } catch (e: Exception) {
            logger.error("adminImportUploadChunk异常", ("error", e.message))
            ctx.status(500)
            ResponseView.errorJson(ctx, "Internal error", 500)
        }
    }

    private static func mergeChunks(chunkDir: Path, outputFile: Path): Unit {
        if (!exists(chunkDir)) {
            throw Exception("Chunk directory does not exist: ${chunkDir.toString()}")
        }

        var chunkFiles = ArrayList<Path>()
        for (entry in Directory.readFrom(chunkDir)) {
            if (!entry.isDirectory()) {
                let fileName = entry.path.fileName.toString()
                if (fileName.startsWith("chunk_") && fileName.endsWith(".bin")) {
                    chunkFiles.add(entry.path)
                }
            }
        }

        if (chunkFiles.size == 0) {
            throw Exception("No chunk files found")
        }

        var chunkArray = Array<Path>(chunkFiles.size, { _ => Path("") })
        for (i in 0..chunkFiles.size) {
            chunkArray[i] = chunkFiles[i]
        }
        for (i in 0..chunkArray.size - 1) {
            for (j in 0..chunkArray.size - i - 1) {
                let aName = chunkArray[j].fileName.toString()
                let bName = chunkArray[j + 1].fileName.toString()
                let aIndex = Int64.parse(aName.removePrefix("chunk_").removeSuffix(".bin"))
                let bIndex = Int64.parse(bName.removePrefix("chunk_").removeSuffix(".bin"))
                if (aIndex > bIndex) {
                    let temp = chunkArray[j]
                    chunkArray[j] = chunkArray[j + 1]
                    chunkArray[j + 1] = temp
                }
            }
        }

        try (output = File(outputFile, Write)) {
            let bufferSize = 1024 * 1024
            let buffer = Array<Byte>(bufferSize, { _ => 0 })
            for (chunkFile in chunkArray) {
                try (chunk = File(chunkFile, Read)) {
                    var bytesRead = chunk.read(buffer)
                    while (bytesRead > 0) {
                        output.write(buffer[0..bytesRead])
                        bytesRead = chunk.read(buffer)
                    }
                }
            }
        }
    }

    /**
     * POST /api/admin/tags/import/complete?job=...&totalChunks=...
     */
    public static func adminImportUploadComplete(ctx: JoyContext): Unit {
        let logger = getLogger("tag_controller")
        try {
            let jobStr = (ctx.getQuery("job") ?? "").trimAscii()
            let totalChunksStr = (ctx.getQuery("totalChunks") ?? "").trimAscii()
            if (jobStr.size == 0 || totalChunksStr.size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "job and totalChunks are required", 400)
                return
            }

            let jobId = try {
                Int64.parse(jobStr)
            } catch (_: Exception) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "invalid job", 400)
                return
            }

            let totalChunks = try {
                Int64.parse(totalChunksStr)
            } catch (_: Exception) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "invalid totalChunks", 400)
                return
            }
            if (totalChunks <= 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "invalid totalChunks", 400)
                return
            }

            let taskData = TaskDao.getTaskDataById(jobId)
            if (taskData.id == 0 || taskData.taskType != "tag_import") {
                ctx.status(404)
                ResponseView.errorJson(ctx, "job not found", 404)
                return
            }
            if (taskData.status != "waiting_upload") {
                ctx.status(409)
                ResponseView.errorJson(ctx, "job is not ready for complete", 409)
                return
            }

            let jsonPathStr = taskData.parameters.trimAscii()
            if (jsonPathStr.size == 0) {
                ctx.status(500)
                ResponseView.errorJson(ctx, "job has no upload path", 500)
                return
            }

            let jsonFile = Path(jsonPathStr)
            let chunkDir = jsonFile.parent

            for (i in 0..totalChunks) {
                let chunkFile = Path("${chunkDir.toString()}/chunk_${Int64(i).toString()}.bin")
                if (!exists(chunkFile)) {
                    ctx.status(400)
                    ResponseView.errorJson(ctx, "missing chunk ${i.toString()}", 400)
                    return
                }
            }

            mergeChunks(chunkDir, jsonFile)

            let size = FileInfo(jsonFile).size
            if (size <= 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "Empty file", 400)
                return
            }

            for (i in 0..totalChunks) {
                let chunkFile = Path("${chunkDir.toString()}/chunk_${Int64(i).toString()}.bin")
                try { remove(chunkFile) } catch (_: Exception) {}
            }

            TaskIO.appendLog(jobId, "completed upload file=${jsonFile.toString()} size=${size.toString()}")
            TaskDao.updateTaskStatus(jobId, "pending", "文件已上传，等待导入", 0)
            TaskPoolService.getInstance().notifyTaskAvailable()

            let data = "{\"success\":1,\"job\":${jobId.toString()},\"operation\":\"tag_import\"}"
            ResponseView.successJson(ctx, data, "已合并分片并入队导入")
        } catch (e: Exception) {
            logger.error("adminImportUploadComplete异常", ("error", e.message))
            ctx.status(500)
            ResponseView.errorJson(ctx, "Internal error", 500)
        }
    }

    // ============ 辅助方法 ============

    // parseTranslationsFromReader() is used instead (json.stream-based).
}
