package lrr4cj.controllers

import cjoy.*
import stdx.encoding.json.*
import stdx.log.*
import std.time.DateTime
import std.collection.*
import std.convert.*
import std.fs.*
import std.io.*
import lrr4cj.services.*
import lrr4cj.dao.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.views.*

/**
 * Tag i18n 映射控制器
 * - 普通接口：按语言返回 map（用于前端展示）
 * - 管理接口：管理员维护、导入导出
 */
public class TagI18nController {
    private static let CACHE_DIR = "./data/cache"
    private static let IMPORT_CHUNK_SIZE: Int64 = 1536 * 1024 // 1.5MB

    private static func jsonValueToString(value: JsonValue): String {
        match (value) {
            case s: JsonString => return s.getValue()
            case _ => return value.toString()
        }
    }

    private static func getJsonString(obj: JsonObject, key: String): String {
        let fields = obj.getFields()
        if (!fields.contains(key)) { return "" }
        return jsonValueToString(fields[key]).trimAscii()
    }

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

    private static func addEntry(entries: ArrayList<TagI18nEntry>, tag: String, lang: String, text: String): Unit {
        let t = tag.trimAscii()
        let l = lang.trimAscii()
        if (t.size == 0 || l.size == 0) { return }
        let e = TagI18nEntry()
        e.tag = t
        e.lang = l
        e.text = text
        entries.add(e)
    }

    private static func parseEntriesArray(entries: ArrayList<TagI18nEntry>, arr: JsonArray): Unit {
        let size = arr.size()
        for (i in 0..size) {
            match (arr.get(i)) {
                case Some(v) =>
                    match (v) {
                        case obj: JsonObject =>
                            let tag = getJsonString(obj, "tag")
                            let lang = getJsonString(obj, "lang")
                            let text = getJsonString(obj, "text")
                            addEntry(entries, tag, lang, text)
                        case _ => ()
                    }
                case None => ()
            }
        }
    }

    private static func parseTagMap(entries: ArrayList<TagI18nEntry>, obj: JsonObject): Unit {
        let fields = obj.getFields()
        for ((tag, value) in fields) {
            match (value) {
                case langsObj: JsonObject =>
                    let lf = langsObj.getFields()
                    for ((lang, textVal) in lf) {
                        addEntry(entries, tag, lang, jsonValueToString(textVal))
                    }
                case s: JsonString =>
                    // 兜底：如果只有字符串，则默认当作 zh
                    addEntry(entries, tag, "zh", s.getValue())
                case _ => ()
            }
        }
    }

    private static func langFromQuery(ctx: JoyContext): String {
        let lang = (ctx.getQuery("lang") ?? "").trimAscii()
        if (lang.size == 0) { return "zh" }
        return lang
    }

    /**
     * GET /api/tags/i18n?lang=zh|en[&arcid=...]
     * 返回: { lang, map: { "<tag>": "<text>" } }
     * 如果提供 arcid，则只返回该档案相关的 tag 翻译
     */
    public static func getTagI18nMap(ctx: JoyContext): Unit {
        let lang = langFromQuery(ctx)
        let arcid = (ctx.getQuery("arcid") ?? "").trimAscii()

        var rows = TagI18nDao.getByLang(lang)

        // 如果指定了 arcid，则只返回该档案相关的 tag 翻译
        if (arcid.size > 0) {
            let archive = ArchiveDao.getArchiveMetadataById(arcid)
            if (archive.id.size == 0) {
                ResponseView.successJson(ctx, "{\"lang\":\"${escapeJsonString(lang)}\",\"map\":{}}", "获取tag i18n成功")
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
            var filteredRows = ArrayList<TagI18nEntry>()
            for (row in rows) {
                if (tagSet.contains(row.tag)) {
                    filteredRows.add(row)
                }
            }
            rows = filteredRows.toArray()
        }

        var mapJson = "{"
        var first = true
        for (row in rows) {
            if (!first) { mapJson = mapJson + "," } else { first = false }
            mapJson = mapJson + "\"" + escapeJsonString(row.tag) + "\":\"" + escapeJsonString(row.text) + "\""
        }
        mapJson = mapJson + "}"

        let data = "{\"lang\":\"${escapeJsonString(lang)}\",\"map\":${mapJson}}"
        ResponseView.successJson(ctx, data, "获取tag i18n成功")
    }

    /**
     * GET /api/admin/tag_i18n?q=...&limit=...&offset=...
     * 返回: { items: [{tag,lang,text,updated_at}, ...] }
     */
    public static func adminList(ctx: JoyContext): Unit {
        let q = (ctx.getQuery("q") ?? "").trimAscii()
        let limitStr = (ctx.getQuery("limit") ?? "5000").trimAscii()
        let offsetStr = (ctx.getQuery("offset") ?? "0").trimAscii()
        var limit: Int32 = 5000
        var offset: Int32 = 0
        try { limit = Int32.parse(limitStr) } catch (_: Exception) {}
        try { offset = Int32.parse(offsetStr) } catch (_: Exception) {}

        let rows = TagI18nDao.list(q: q, limit: limit, offset: offset)
        var itemsJson = "["
        var first = true
        for (row in rows) {
            if (!first) { itemsJson = itemsJson + "," } else { first = false }
            itemsJson = itemsJson + "{\"tag\":\"${escapeJsonString(row.tag)}\",\"lang\":\"${escapeJsonString(row.lang)}\",\"text\":\"${escapeJsonString(row.text)}\",\"updated_at\":\"${escapeJsonString(row.updated_at)}\"}"
        }
        itemsJson = itemsJson + "]"

        let data = "{\"items\":${itemsJson}}"
        ResponseView.successJson(ctx, data, "获取tag i18n列表成功")
    }

    /**
     * GET /api/admin/tag_i18n/merged?q=...&limit=...&offset=...
     * 返回: { items: [{tag,zh,en}], total, limit, offset }
     */
    public static func adminListMerged(ctx: JoyContext): Unit {
        let q = (ctx.getQuery("q") ?? "").trimAscii()
        let limitStr = (ctx.getQuery("limit") ?? "100").trimAscii()
        let offsetStr = (ctx.getQuery("offset") ?? "0").trimAscii()
        var limit: Int32 = 100
        var offset: Int32 = 0
        try { limit = Int32.parse(limitStr) } catch (_: Exception) {}
        try { offset = Int32.parse(offsetStr) } catch (_: Exception) {}

        if (limit <= 0) { limit = 100 }
        if (limit > 2000) { limit = 2000 }
        if (offset < 0) { offset = 0 }

        let total = TagI18nDao.countMerged(q: q)
        let rows = TagI18nDao.listMerged(q: q, limit: limit, offset: offset)

        var itemsJson = "["
        var first = true
        for (row in rows) {
            if (!first) { itemsJson = itemsJson + "," } else { first = false }
            itemsJson = itemsJson + "{"
            itemsJson = itemsJson + "\"tag\":\"${escapeJsonString(row.tag)}\","
            itemsJson = itemsJson + "\"zh\":\"${escapeJsonString(row.zh)}\","
            itemsJson = itemsJson + "\"en\":\"${escapeJsonString(row.en)}\","
            itemsJson = itemsJson + "\"zh_intro\":\"${escapeJsonString(row.zh_intro)}\","
            itemsJson = itemsJson + "\"en_intro\":\"${escapeJsonString(row.en_intro)}\","
            itemsJson = itemsJson + "\"zh_links\":\"${escapeJsonString(row.zh_links)}\","
            itemsJson = itemsJson + "\"en_links\":\"${escapeJsonString(row.en_links)}\""
            itemsJson = itemsJson + "}"
        }
        itemsJson = itemsJson + "]"

        let data = "{\"items\":${itemsJson},\"total\":${total.toString()},\"limit\":${limit.toString()},\"offset\":${offset.toString()}}"
        ResponseView.successJson(ctx, data, "获取tag i18n分页列表成功")
    }

    /**
     * GET /api/admin/tag_i18n/tags
     * 返回: { tags: ["artist:...", ...] }
     */
    public static func adminListTags(ctx: JoyContext): Unit {
        let tags = TagDao.listAllTagNames()
        var tagsJson = "["
        var first = true
        for (tag in tags) {
            if (!first) { tagsJson = tagsJson + "," } else { first = false }
            tagsJson = tagsJson + "\"" + escapeJsonString(tag) + "\""
        }
        tagsJson = tagsJson + "]"
        ResponseView.successJson(ctx, "{\"tags\":${tagsJson}}", "获取标签列表成功")
    }

    /**
     * PUT /api/admin/tag_i18n
     * body: { tag, lang, text }
     */
    public static func adminUpsert(ctx: JoyContext): Unit {
        let logger = getLogger("tag_i18n_controller")
        try {
            let body = ctx.readString()
            if (body.trimAscii().size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "Empty body", 400)
                return
            }

            let json = JsonValue.fromStr(body)
            var tag = ""
            var lang = ""
            var text = ""
            match (json) {
                case obj: JsonObject =>
                    tag = getJsonString(obj, "tag")
                    lang = getJsonString(obj, "lang")
                    text = getJsonString(obj, "text")
                case _ => ()
            }

            if (tag.size == 0 || lang.size == 0) {
                ctx.status(400)
                ResponseView.errorJson(ctx, "tag and lang are required", 400)
                return
            }

            let ok = TagI18nDao.upsert(tag, lang, text)
            if (!ok) {
                ctx.status(500)
                ResponseView.errorJson(ctx, "Upsert failed", 500)
                return
            }
            ResponseView.successJson(ctx, "{\"success\":1}", "保存成功")
        } catch (e: Exception) {
            logger.error("adminUpsert异常", ("error", e.message))
            ctx.status(500)
            ResponseView.errorJson(ctx, "Internal error", 500)
        }
    }

    /**
     * DELETE /api/admin/tag_i18n?tag=...&lang=...
     */
    public static func adminDelete(ctx: JoyContext): Unit {
        let tag = (ctx.getQuery("tag") ?? "").trimAscii()
        let lang = (ctx.getQuery("lang") ?? "").trimAscii()
        if (tag.size == 0 || lang.size == 0) {
            ctx.status(400)
            ResponseView.errorJson(ctx, "tag and lang are required", 400)
            return
        }
        let ok = TagI18nDao.delete(tag, lang)
        if (!ok) {
            ctx.status(500)
            ResponseView.errorJson(ctx, "Delete failed", 500)
            return
        }
        ResponseView.successJson(ctx, "{\"success\":1}", "删除成功")
    }

    /**
     * GET /api/admin/tag_i18n/export
     * 返回: { entries: [{tag,lang,text}], generated_at }
     */
    public static func adminExport(ctx: JoyContext): Unit {
        let rows = TagI18nDao.list(q: "", limit: 200000, offset: 0)
        var entriesJson = "["
        var first = true
        for (row in rows) {
            if (!first) { entriesJson = entriesJson + "," } else { first = false }
            entriesJson = entriesJson + "{\"tag\":\"${escapeJsonString(row.tag)}\",\"lang\":\"${escapeJsonString(row.lang)}\",\"text\":\"${escapeJsonString(row.text)}\"}"
        }
        entriesJson = entriesJson + "]"

        let now = DateTime.nowUTC().toString()
        let data = "{\"generated_at\":\"${escapeJsonString(now)}\",\"entries\":${entriesJson}}"
        ResponseView.successJson(ctx, data, "导出成功")
    }

    /**
     * POST /api/admin/tag_i18n/import
     *
     * 兼容三种格式：
     * 1) { "entries": [ {tag,lang,text}, ... ] }
     * 2) [ {tag,lang,text}, ... ]
     * 3) { "map": { "<tag>": { "zh": "...", "en": "..." }, ... } }  或直接以该对象作为根
     */
    public static func adminImport(ctx: JoyContext): Unit {
        let logger = getLogger("tag_i18n_controller")
        try {
            // 改为 TaskPool 异步导入：避免大文件导入请求超时
            let taskData = MinionTaskData()
            taskData.name = "Tag i18n 导入"
            taskData.taskType = "tag_i18n_import"
            taskData.status = "waiting_upload"
            taskData.progress = 0
            taskData.message = "等待上传导入文件"
            taskData.parameters = ""
            let created = MinionTaskDao.createTaskData(taskData)
            if (!created || taskData.id == 0) {
                ctx.status(500)
                ResponseView.errorJson(ctx, "Create task failed", 500)
                return
            }
            let taskId = taskData.id

            // 将请求体流式落盘，避免把大 JSON 全量读入内存/写入DB(parameters)
            let taskDir = Path("${CACHE_DIR}/task/${taskId.toString()}")
            Directory.create(taskDir, recursive: true)
            let jsonFile = Path("${taskDir}/tag_i18n_import.json")
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

            MinionTaskDao.updateTaskParameters(taskId, jsonFile.toString())
            MinionTaskDao.updateTaskStatus(taskId, "pending", "文件已上传，等待导入", 0)
            TaskIO.appendLog(taskId, "enqueued tag_i18n_import")
            TaskPoolService.getInstance().notifyTaskAvailable()

            let data = "{\"success\":1,\"job\":${taskId.toString()},\"operation\":\"tag_i18n_import\"}"
            ResponseView.successJson(ctx, data, "已入队导入任务")
        } catch (e: Exception) {
            logger.error("adminImport异常", ("error", e.message))
            ctx.status(500)
            ResponseView.errorJson(ctx, "Internal error", 500)
        }
    }

    /**
     * POST /api/admin/tag_i18n/import/init
     * 创建导入任务并返回 jobId（不做解析，解析在 TaskPool 中执行）
     */
    public static func adminImportInit(ctx: JoyContext): Unit {
        let logger = getLogger("tag_i18n_controller")
        try {
            let taskData = MinionTaskData()
            taskData.name = "Tag i18n 导入"
            taskData.taskType = "tag_i18n_import"
            taskData.status = "waiting_upload"
            taskData.progress = 0
            taskData.message = "等待上传导入文件"
            taskData.parameters = ""
            let created = MinionTaskDao.createTaskData(taskData)
            if (!created || taskData.id == 0) {
                ctx.status(500)
                ResponseView.errorJson(ctx, "Create task failed", 500)
                return
            }

            let taskId = taskData.id
            let taskDir = Path("${CACHE_DIR}/task/${taskId.toString()}")
            Directory.create(taskDir, recursive: true)
            let jsonFile = Path("${taskDir}/tag_i18n_import.json")

            MinionTaskDao.updateTaskParameters(taskId, jsonFile.toString())
            TaskIO.appendLog(taskId, "created, waiting_upload")

            let data = "{\"success\":1,\"job\":${taskId.toString()},\"operation\":\"tag_i18n_import\",\"chunk_size\":${IMPORT_CHUNK_SIZE.toString()}}"
            ResponseView.successJson(ctx, data, "已创建导入任务")
        } catch (e: Exception) {
            logger.error("adminImportInit异常", ("error", e.message))
            ctx.status(500)
            ResponseView.errorJson(ctx, "Internal error", 500)
        }
    }

    /**
     * PUT /api/admin/tag_i18n/import/chunk?job=...&chunkIndex=...&totalChunks=...
     * 上传分片到缓存目录
     */
    public static func adminImportUploadChunk(ctx: JoyContext): Unit {
        let logger = getLogger("tag_i18n_controller")
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

            let taskData = MinionTaskDao.getTaskDataById(jobId)
            if (taskData.id == 0 || taskData.taskType != "tag_i18n_import") {
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

            let data = "{\"success\":1,\"job\":${jobId.toString()},\"operation\":\"tag_i18n_import\"}"
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

        var chunkArray = Array<Path>(chunkFiles.size, { i => Path("") })
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
            let buffer = Array<Byte>(bufferSize, { i => 0 })
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
     * POST /api/admin/tag_i18n/import/complete?job=...&totalChunks=...
     * 合并分片并将任务状态切回 pending 以便 TaskPool 执行
     */
    public static func adminImportUploadComplete(ctx: JoyContext): Unit {
        let logger = getLogger("tag_i18n_controller")
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

            let taskData = MinionTaskDao.getTaskDataById(jobId)
            if (taskData.id == 0 || taskData.taskType != "tag_i18n_import") {
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

            // 预检查分片是否都存在
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

            // 清理分片
            for (i in 0..totalChunks) {
                let chunkFile = Path("${chunkDir.toString()}/chunk_${Int64(i).toString()}.bin")
                try { remove(chunkFile) } catch (_: Exception) {}
            }

            TaskIO.appendLog(jobId, "completed upload file=${jsonFile.toString()} size=${size.toString()}")
            MinionTaskDao.updateTaskStatus(jobId, "pending", "文件已上传，等待导入", 0)
            TaskPoolService.getInstance().notifyTaskAvailable()

            let data = "{\"success\":1,\"job\":${jobId.toString()},\"operation\":\"tag_i18n_import\"}"
            ResponseView.successJson(ctx, data, "已合并分片并入队导入")
        } catch (e: Exception) {
            logger.error("adminImportUploadComplete异常", ("error", e.message))
            ctx.status(500)
            ResponseView.errorJson(ctx, "Internal error", 500)
        }
    }
}
