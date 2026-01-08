package lrr4cj.controllers

import cjoy.*
import stdx.encoding.json.*
import stdx.log.*
import std.time.DateTime
import std.collection.*
import std.convert.*
import std.fs.*
import lrr4cj.services.*
import lrr4cj.dao.*
import lrr4cj.utils.*
import lrr4cj.views.*

/**
 * 标签控制器
 * - 普通接口：获取标签翻译映射（用于前端展示）
 * - 管理接口：管理员维护、导入导出
 */
public class TagController {
    private static let CACHE_DIR = "./data/cache"
    private static let IMPORT_CHUNK_SIZE: Int64 = 1536 * 1024 // 1.5MB

    private static func escapeJsonString(str: String): String {
        var escaped = str
        escaped = escaped.replace("\\", "\\\\")
        escaped = escaped.replace("\"", "\\\"")
        escaped = escaped.replace("\b", "\\b")
        escaped = escaped.replace("\f", "\\f")
        escaped = escaped.replace("\n", "\\n")
        escaped = escaped.replace("\r", "\\r")
        escaped = escaped.replace("\t", "\\t")
        return escaped
    }

    private static func langFromQuery(ctx: JoyContext): String {
        let lang = (ctx.getQuery("lang") ?? "").trimAscii()
        if (lang.size == 0) { return "zh" }
        return lang
    }

    private static func getJsonString(obj: JsonObject, key: String): String {
        let fields = obj.getFields()
        if (!fields.contains(key)) { return "" }
        match (fields[key]) {
            case s: JsonString => return s.getValue().trimAscii()
            case _ => return fields[key].toString().trimAscii()
        }
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
                ResponseView.successJson(ctx, "{\"lang\":\"${escapeJsonString(lang)}\",\"map\":{}}", "获取标签翻译成功")
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
                    ResponseView.successJson(ctx, "{\"lang\":\"${escapeJsonString(lang)}\",\"map\":{}}", "获取标签翻译成功")
                    return
            }
        }

        var mapJson = "{"
        var first = true
        for ((tag, text) in translationsMap) {
            if (!first) { mapJson = mapJson + "," } else { first = false }
            mapJson = mapJson + "\"" + escapeJsonString(tag) + "\":\"" + escapeJsonString(text) + "\""
        }
        mapJson = mapJson + "}"

        let data = "{\"lang\":\"${escapeJsonString(lang)}\",\"map\":${mapJson}}"
        ResponseView.successJson(ctx, data, "获取标签翻译成功")
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

        var itemsJson = "["
        var first = true
        for (row in rows) {
            if (!first) { itemsJson = itemsJson + "," } else { first = false }
            itemsJson = itemsJson + "{"
            itemsJson = itemsJson + "\"id\":${row.id.toString()},"
            itemsJson = itemsJson + "\"namespace\":\"${escapeJsonString(row.namespace)}\","
            itemsJson = itemsJson + "\"name\":\"${escapeJsonString(row.name)}\","

            // 序列化 translations
            var translationsJson = "{"
            var tFirst = true
            for ((lang, t) in row.translations) {
                if (!tFirst) { translationsJson = translationsJson + "," } else { tFirst = false }
                translationsJson = translationsJson + "\"${escapeJsonString(lang)}\":{\"text\":\"${escapeJsonString(t.text)}\",\"intro\":\"${escapeJsonString(t.intro)}\"}"
            }
            translationsJson = translationsJson + "}"

            itemsJson = itemsJson + "\"translations\":${translationsJson},"
            itemsJson = itemsJson + "\"links\":\"${escapeJsonString(row.links)}\","
            itemsJson = itemsJson + "\"created_at\":\"${escapeJsonString(row.created_at)}\","
            itemsJson = itemsJson + "\"updated_at\":\"${escapeJsonString(row.updated_at)}\""
            itemsJson = itemsJson + "}"
        }
        itemsJson = itemsJson + "]"

        let data = "{\"items\":${itemsJson},\"total\":${total.toString()},\"limit\":${limit.toString()},\"offset\":${offset.toString()}}"
        ResponseView.successJson(ctx, data, "获取标签列表成功")
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
                var translationsJson = "{"
                var tFirst = true
                for ((lang, t) in tag.translations) {
                    if (!tFirst) { translationsJson = translationsJson + "," } else { tFirst = false }
                    translationsJson = translationsJson + "\"${escapeJsonString(lang)}\":{\"text\":\"${escapeJsonString(t.text)}\",\"intro\":\"${escapeJsonString(t.intro)}\"}"
                }
                translationsJson = translationsJson + "}"

                var data = "{"
                data = data + "\"id\":${tag.id.toString()},"
                data = data + "\"namespace\":\"${escapeJsonString(tag.namespace)}\","
                data = data + "\"name\":\"${escapeJsonString(tag.name)}\","
                data = data + "\"translations\":${translationsJson},"
                data = data + "\"links\":\"${escapeJsonString(tag.links)}\","
                data = data + "\"created_at\":\"${escapeJsonString(tag.created_at)}\","
                data = data + "\"updated_at\":\"${escapeJsonString(tag.updated_at)}\""
                data = data + "}"
                ResponseView.successJson(ctx, data, "获取标签成功")
            case None =>
                ctx.status(404)
                ResponseView.errorJson(ctx, "tag not found", 404)
        }
    }

    /**
     * GET /api/tags/namespaces
     * 返回所有命名空间
     */
    public static func listNamespaces(ctx: JoyContext): Unit {
        let namespaces = TagDao.listNamespaces()
        var json = "["
        var first = true
        for (ns in namespaces) {
            if (!first) { json = json + "," } else { first = false }
            json = json + "\"" + escapeJsonString(ns) + "\""
        }
        json = json + "]"
        ResponseView.successJson(ctx, "{\"namespaces\":${json}}", "获取命名空间列表成功")
    }

    /**
     * GET /api/tags/autocomplete?q=...&lang=zh|en&limit=10
     * 返回自动补全建议列表
     */
    public static func autocomplete(ctx: JoyContext): Unit {
        let query = (ctx.getQuery("q") ?? "").trimAscii()
        let lang = langFromQuery(ctx)
        let limitStr = (ctx.getQuery("limit") ?? "10").trimAscii()

        var limit: Int64 = 10
        try { limit = Int64.parse(limitStr) } catch (_: Exception) {}
        if (limit <= 0) { limit = 10 }
        if (limit > 50) { limit = 50 }

        if (query.size == 0) {
            ResponseView.successJson(ctx, "{\"suggestions\":[]}", "获取自动补全建议成功")
            return
        }

        let results = TagDao.autocompleteSearch(query, lang, limit)

        var suggestionsJson = "["
        var first = true
        for ((fullName, translatedText) in results) {
            if (!first) { suggestionsJson = suggestionsJson + "," } else { first = false }
            // 返回格式：{ value: "namespace:name", label: "翻译文本", display: "namespace:翻译文本" }
            let (namespace, _) = TagDao.parseTagName(fullName)
            let display = if (namespace.size > 0) {
                "${namespace}:${translatedText}"
            } else {
                translatedText
            }
            suggestionsJson = suggestionsJson + "{"
            suggestionsJson = suggestionsJson + "\"value\":\"${escapeJsonString(fullName)}\","
            suggestionsJson = suggestionsJson + "\"label\":\"${escapeJsonString(translatedText)}\","
            suggestionsJson = suggestionsJson + "\"display\":\"${escapeJsonString(display)}\""
            suggestionsJson = suggestionsJson + "}"
        }
        suggestionsJson = suggestionsJson + "]"

        ResponseView.successJson(ctx, "{\"suggestions\":${suggestionsJson}}", "获取自动补全建议成功")
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

        var itemsJson = "["
        var first = true
        for ((tag, display, count) in rows) {
            if (!first) { itemsJson = itemsJson + "," } else { first = false }
            itemsJson = itemsJson + "{"
            itemsJson = itemsJson + "\"tag\":\"${escapeJsonString(tag)}\","
            itemsJson = itemsJson + "\"display\":\"${escapeJsonString(display)}\","
            itemsJson = itemsJson + "\"count\":${count.toString()}"
            itemsJson = itemsJson + "}"
        }
        itemsJson = itemsJson + "]"

        let data = "{\"items\":${itemsJson},\"total\":${rows.size.toString()}}"
        ResponseView.successJson(ctx, data, "获取标签词云成功")
    }

    /**
     * GET /api/admin/tags/names
     * 返回所有标签名（用于自动补全）
     */
    public static func adminListTagNames(ctx: JoyContext): Unit {
        let tags = TagDao.listAllTagNames()
        var tagsJson = "["
        var first = true
        for (tag in tags) {
            if (!first) { tagsJson = tagsJson + "," } else { first = false }
            tagsJson = tagsJson + "\"" + escapeJsonString(tag) + "\""
        }
        tagsJson = tagsJson + "]"
        ResponseView.successJson(ctx, "{\"tags\":${tagsJson}}", "获取标签名列表成功")
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

            let json = JsonValue.fromStr(body)
            var namespace = ""
            var name = ""
            var links = ""
            var translations = HashMap<String, TagTranslation>()

            match (json) {
                case obj: JsonObject =>
                    namespace = getJsonString(obj, "namespace")
                    name = getJsonString(obj, "name")
                    links = getJsonString(obj, "links")

                    let fields = obj.getFields()
                    if (fields.contains("translations")) {
                        match (fields["translations"]) {
                            case tObj: JsonObject =>
                                translations = parseTranslationsFromJson(tObj)
                            case _ => ()
                        }
                    }
                case _ => ()
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

            let json = JsonValue.fromStr(body)
            var links = ""
            var translations = HashMap<String, TagTranslation>()

            match (json) {
                case obj: JsonObject =>
                    links = getJsonString(obj, "links")

                    let fields = obj.getFields()
                    if (fields.contains("translations")) {
                        match (fields["translations"]) {
                            case tObj: JsonObject =>
                                translations = parseTranslationsFromJson(tObj)
                            case _ => ()
                        }
                    }
                case _ => ()
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
        var itemsJson = "["
        var first = true
        for (row in rows) {
            if (!first) { itemsJson = itemsJson + "," } else { first = false }
            itemsJson = itemsJson + "{"
            itemsJson = itemsJson + "\"namespace\":\"${escapeJsonString(row.namespace)}\","
            itemsJson = itemsJson + "\"name\":\"${escapeJsonString(row.name)}\","

            var translationsJson = "{"
            var tFirst = true
            for ((lang, t) in row.translations) {
                if (!tFirst) { translationsJson = translationsJson + "," } else { tFirst = false }
                translationsJson = translationsJson + "\"${escapeJsonString(lang)}\":{\"text\":\"${escapeJsonString(t.text)}\",\"intro\":\"${escapeJsonString(t.intro)}\"}"
            }
            translationsJson = translationsJson + "}"

            itemsJson = itemsJson + "\"translations\":${translationsJson},"
            itemsJson = itemsJson + "\"links\":\"${escapeJsonString(row.links)}\""
            itemsJson = itemsJson + "}"
        }
        itemsJson = itemsJson + "]"

        let now = DateTime.nowUTC().toString()
        let data = "{\"generated_at\":\"${escapeJsonString(now)}\",\"tags\":${itemsJson}}"
        ResponseView.successJson(ctx, data, "导出成功")
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

    private static func parseTranslationsFromJson(obj: JsonObject): HashMap<String, TagTranslation> {
        var result = HashMap<String, TagTranslation>()
        let fields = obj.getFields()
        for ((lang, value) in fields) {
            let t = TagTranslation()
            match (value) {
                case innerObj: JsonObject =>
                    let innerFields = innerObj.getFields()
                    if (innerFields.contains("text")) {
                        match (innerFields["text"]) {
                            case s: JsonString => t.text = s.getValue()
                            case _ => ()
                        }
                    }
                    if (innerFields.contains("intro")) {
                        match (innerFields["intro"]) {
                            case s: JsonString => t.intro = s.getValue()
                            case _ => ()
                        }
                    }
                case _ => ()
            }
            result[lang] = t
        }
        return result
    }
}
