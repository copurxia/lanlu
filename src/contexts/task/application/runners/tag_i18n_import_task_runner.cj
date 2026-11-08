package lanlu.contexts.task.application.runners

import std.fs.*
import stdx.encoding.json.stream.*
import stdx.log.*
import lanlu.shared.config.*
import lanlu.contexts.tag.infrastructure.persistence.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*
import csorm.*

/**
 * tag_i18n_import 任务执行器（运行在TaskPool中）
 * parameters: 导入请求的原始 JSON
 *
 * 支持新格式：
 * {"tags": [{"namespace": "...", "name": "...", "translations": {"zh": {...}, "en": {...}}}]}
 */
public class TagI18nImportTaskRunner {
    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }

    public static func run(taskId: Int64, parameters: String, _: TaskRunnerContext): Unit {
        let logger = getLogger("tag_i18n_import_task")
        TaskIO.appendLog(taskId, "tag_i18n_import task started")
        TaskModel.updateTaskProgress(taskId, 1, "导入任务开始")

        TaskModel.updateTaskProgress(taskId, 5, "准备写入数据库")

        match (DatabaseConfig.getDatabase()) {
            case None =>
                fail(taskId, "无法连接到数据库")
                return
            case Some(db) =>
                var received: Int64 = 0
                var imported: Int64 = 0

                func tickProgress(): Unit {
                    if (received > 0 && received % 1000 == 0) {
                        let p: Int32 = if (received < 5000) { 20 }
                            else if (received < 20000) { 40 }
                            else if (received < 80000) { 60 }
                            else if (received < 200000) { 75 }
                            else { 90 }
                        TaskModel.updateTaskProgress(taskId, p, "已写入 ${received.toString()} 条")
                        TaskIO.appendLog(taskId, "progress received=${received.toString()} imported=${imported.toString()}")
                    }
                }

                let updateSql = "UPDATE tags SET translations = $1::jsonb, links = $2, updated_at = CURRENT_TIMESTAMP WHERE namespace = $3 AND name = $4"
                let insertSql = "INSERT INTO tags (namespace, name, translations, links) SELECT $1, $2, $3::jsonb, $4 WHERE NOT EXISTS (SELECT 1 FROM tags WHERE namespace = $5 AND name = $6)"

                func addTag(namespace: String, name: String, translations: String, links: String): Unit {
                    let ns = namespace.trimAscii()
                    let nm = name.trimAscii()
                    if (ns.size == 0 || nm.size == 0) { return }
                    received += 1
                    let aff = db.execRaw(updateSql, [vjson(translations), vtext(links), vtext(ns), vtext(nm)])
                    if (aff <= 0) {
                        db.execRaw(insertSql, [vtext(ns), vtext(nm), vjson(translations), vtext(links), vtext(ns), vtext(nm)])
                    }
                    imported += 1
                    tickProgress()
                }

                func readValueAsString(r: JsonReader): String {
                    match (r.peek()) {
                        case Some(BeginObject) =>
                            let bytes = r.readValueBytes()
                            return String.fromUtf8(bytes)
                        case Some(BeginArray) =>
                            let bytes = r.readValueBytes()
                            return String.fromUtf8(bytes)
                        case Some(_) =>
                            return r.readValue<String>()
                        case None =>
                            return ""
                    }
                }

                func parseEntryObject(r: JsonReader): Unit {
                    var namespace = ""
                    var name = ""
                    var translationsJson = "{}"
                    var links = ""

                    r.startObject()
                    while (r.peek() != EndObject) {
                        let fieldName = r.readName()
                        match (fieldName) {
                            case "namespace" => namespace = readValueAsString(r).trimAscii()
                            case "name" => name = readValueAsString(r).trimAscii()
                            case "translations" =>
                                translationsJson = readValueAsString(r)
                            case "links" => links = readValueAsString(r)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()

                    addTag(namespace, name, translationsJson, links)
                }

                func parseTagsArray(r: JsonReader): Unit {
                    r.startArray()
                    while (r.peek() != EndArray) {
                        match (r.peek()) {
                            case Some(BeginObject) => parseEntryObject(r)
                            case Some(_) => r.skip()
                            case None => break
                        }
                    }
                    r.endArray()
                }

                func parseRoot(reader: JsonReader): Unit {
                    var parsedAny = false
                    while (let Some(tok) <- reader.peek()) {
                        match (tok) {
                            case BeginArray =>
                                parseTagsArray(reader)
                                parsedAny = true
                                break
                            case BeginObject =>
                                reader.startObject()
                                if (reader.peek() == EndObject) {
                                    reader.endObject()
                                    break
                                }

                                while (reader.peek() != EndObject && !parsedAny) {
                                    let name = reader.readName()
                                    match (name) {
                                        case "tags" =>
                                            match (reader.peek()) {
                                                case Some(BeginArray) =>
                                                    parseTagsArray(reader)
                                                    parsedAny = true
                                                case Some(_) =>
                                                    reader.skip()
                                                case None => ()
                                            }
                                        case _ =>
                                            reader.skip()
                                    }
                                }
                                reader.endObject()
                                break
                            case _ =>
                                reader.skip()
                        }
                    }
                    if (!parsedAny || received == 0) {
                        throw Exception("没有可导入的数据")
                    }
                }

                try {
                    let path = parameters.trimAscii()
                    if (path.size == 0) {
                        fail(taskId, "导入参数缺少文件路径")
                        return
                    }

                    let filePath = Path(path)
                    if (!exists(filePath)) {
                        fail(taskId, "导入文件不存在: ${path}")
                        return
                    }

                    TaskIO.appendLog(taskId, "source=file ${path}")
                    try (file = File(filePath, Read)) {
                        let reader = JsonReader(file)
                        parseRoot(reader)
                    }

                    let cacheVersion = TagDao.bumpTranslationSearchCacheVersion()
                    TaskIO.appendLog(taskId, "tag translation search cache version=${cacheVersion.toString()}")

                    let result = "{\"success\":1,\"imported\":${imported.toString()},\"received\":${received.toString()}}"
                    TaskIO.writeOutput(taskId, result)
                    TaskModel.completeTask(taskId, result)
                    TaskIO.appendLog(taskId, "completed imported=${imported.toString()} received=${received.toString()}")
                    logger.debug("tag_i18n_import completed", ("task_id", taskId.toString()), ("imported", imported.toString()))
                } catch (e: Exception) {
                    fail(taskId, "写入数据库失败: ${e.message}")
                    return
                }
        }
    }
}