package lanlu.task_runners

import std.fs.*
import stdx.encoding.json.stream.*
import stdx.log.*
import std.io.{ByteBuffer, readToEnd}
import lanlu.config.*
import lanlu.models.*
import lanlu.utils.*

/**
 * tag_i18n_import 任务执行器（运行在TaskPool中）
 * parameters: 导入请求的原始 JSON
 *
 * 支持新格式：
 * {"tags": [{"namespace": "...", "name": "...", "translations": {"zh": {...}, "en": {...}}}]}
 */
public class TagI18nImportTaskRunner {
    private static func fail(taskId: Int64, message: String): Unit {
        TaskIO.appendLog(taskId, "failed: ${message}")
        TaskModel.failTask(taskId, message)
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(0)
        w.writeName("error").writeValue(message)
        w.endObject()
        w.flush()
        TaskIO.writeOutput(taskId, String.fromUtf8(readToEnd(out)))
    }

    public static func run(taskId: Int64, parameters: String, _: TaskRunnerContext): Unit {
        let logger = getLogger("tag_i18n_import_task")
        TaskIO.appendLog(taskId, "tag_i18n_import task started")
        TaskModel.updateTaskProgress(taskId, 1, "导入任务开始")

        TaskModel.updateTaskProgress(taskId, 5, "准备写入数据库")

        let connOpt = DatabaseConfig.createConnection()
        match (connOpt) {
            case None =>
                fail(taskId, "无法连接到数据库")
                return
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement(
                        "INSERT INTO tags (namespace, name, translations, links) VALUES (?, ?, ?::jsonb, ?) ON CONFLICT (namespace, name) DO UPDATE SET translations = EXCLUDED.translations, links = EXCLUDED.links, updated_at = CURRENT_TIMESTAMP")

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

                    func addTag(namespace: String, name: String, translations: String, links: String): Unit {
                        let ns = namespace.trimAscii()
                        let nm = name.trimAscii()
                        if (ns.size == 0 || nm.size == 0) { return }
                        received += 1
                        stmt.set(0, ns)
                        stmt.set(1, nm)
                        stmt.set(2, translations)
                        stmt.set(3, links)
                        stmt.update()
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
                                    // Read translations as JSON string
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
                                    // Direct array of tags
                                    parseTagsArray(reader)
                                    parsedAny = true
                                    break
                                case BeginObject =>
                                    // Root object: expect {"tags": [...]} format
                                    reader.startObject()
                                    if (reader.peek() == EndObject) {
                                        reader.endObject()
                                        break
                                    }

                                    while (reader.peek() != EndObject && !parsedAny) {
                                        let name = reader.readName()
                                        match (name) {
                                            case "tags" =>
                                                // New simplified format: {"tags": [...]}
                                                match (reader.peek()) {
                                                    case Some(BeginArray) =>
                                                        parseTagsArray(reader)
                                                        parsedAny = true
                                                    case Some(_) =>
                                                        reader.skip()
                                                    case None => ()
                                                }
                                            case _ =>
                                                // Skip other metadata fields
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

                    let path = parameters.trimAscii()
                    if (path.size == 0) {
                        try { stmt.close() } catch (_: Exception) {}
                        try { conn.close() } catch (_: Exception) {}
                        fail(taskId, "导入参数缺少文件路径")
                        return
                    }

                    let filePath = Path(path)
                    if (!exists(filePath)) {
                        try { stmt.close() } catch (_: Exception) {}
                        try { conn.close() } catch (_: Exception) {}
                        fail(taskId, "导入文件不存在: ${path}")
                        return
                    }

                    TaskIO.appendLog(taskId, "source=file ${path}")
                    try (file = File(filePath, Read)) {
                        let reader = JsonReader(file)
                        parseRoot(reader)
                    }

                    try { stmt.close() } catch (_: Exception) {}
                    try { conn.close() } catch (_: Exception) {}

                    let result = "{\"success\":1,\"imported\":${imported.toString()},\"received\":${received.toString()}}"
                    TaskIO.writeOutput(taskId, result)
                    TaskModel.completeTask(taskId, result)
                    TaskIO.appendLog(taskId, "completed imported=${imported.toString()} received=${received.toString()}")
                    logger.debug("tag_i18n_import completed", ("task_id", taskId.toString()), ("imported", imported.toString()))
                } catch (e: Exception) {
                    try { conn.close() } catch (_: Exception) {}
                    fail(taskId, "写入数据库失败: ${e.message}")
                    return
                }
        }
    }
}
