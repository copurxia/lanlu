package lrr4cj.task_runners

import std.collection.*
import std.convert.*
import stdx.encoding.json.*
import std.time.*
import lrr4cj.dao.*
import lrr4cj.models.*
import lrr4cj.utils.*

/**
 * metadata_plugin_callback 回调任务执行器
 * 在 deno_task 完成后被触发，负责读取插件输出并写回元数据
 */
public class MetadataPluginCallbackRunner {
    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        TaskIO.appendLog(taskId, "metadata_plugin_callback task started")
        TaskModel.updateTaskProgress(taskId, 10, "开始处理元数据回调")

        // 解析参数
        let (archiveId, namespace, denoTaskId) = parseParameters(parameters)
        if (archiveId.size == 0 || denoTaskId <= 0) {
            fail(taskId, "Invalid callback parameters: missing archiveId or denoTaskId")
            return
        }

        TaskIO.appendLog(taskId, "callback params: archiveId=${archiveId}, namespace=${namespace}, denoTaskId=${denoTaskId}")

        // 读取 deno_task 输出
        TaskModel.updateTaskProgress(taskId, 30, "读取插件输出")
        let output = TaskIO.readOutput(denoTaskId)
        if (output.size == 0) {
            fail(taskId, "Deno task output is empty")
            return
        }
        TaskIO.appendLog(taskId, "plugin output: ${output}")

        // 解析元数据输出
        TaskModel.updateTaskProgress(taskId, 50, "解析元数据")
        let parsed = parseMetadataOutput(output)
        if (!parsed.success) {
            fail(taskId, parsed.error)
            return
        }

        let newTitle = parsed.title
        let newTags = parsed.tags
        let newSummary = parsed.summary

        // 写回 archives 表
        TaskModel.updateTaskProgress(taskId, 70, "写回元数据")
        var archiveToUpdate = ArchiveDao.getArchiveById(archiveId)
        if (archiveToUpdate.id.size == 0) {
            fail(taskId, "Archive not found when updating")
            return
        }

        var changed = false
        if (newTitle.size > 0) {
            archiveToUpdate.title = newTitle
            changed = true
        }
        if (newSummary.size > 0) {
            archiveToUpdate.summary = newSummary
            changed = true
        }
        if (changed) {
            archiveToUpdate.updated_at = DateTime.now().toString()
            let ok = ArchiveDao.update(archiveToUpdate)
            if (!ok) {
                fail(taskId, "Failed to update archive metadata")
                return
            }
        }

        // 写回 tags
        if (newTags.size > 0) {
            let tagOk = TagDao.updateArchiveTags(archiveId, newTags)
            if (!tagOk) {
                TaskIO.appendLog(taskId, "WARN: failed to update tags")
            }
        }

        // 完成任务
        TaskModel.updateTaskProgress(taskId, 100, "元数据回调完成")
        let resultJson = buildResultJson(archiveId, namespace, newTitle, newSummary, newTags, output)
        TaskModel.completeTask(taskId, "metadata_plugin_callback completed")
        TaskIO.writeOutput(taskId, resultJson)
    }

    private static func parseParameters(parameters: String): (String, String, Int64) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ("", "", 0)
        }

        var archiveId = ""
        var namespace = ""
        var denoTaskId: Int64 = 0

        try {
            let jsonVal = JsonValue.fromStr(trimmed)
            match (jsonVal) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    if (fields.contains("archiveId")) {
                        archiveId = jsonValueToString(fields["archiveId"]).trimAscii()
                    }
                    if (fields.contains("namespace")) {
                        namespace = jsonValueToString(fields["namespace"]).trimAscii()
                    }
                    if (fields.contains("denoTaskId")) {
                        denoTaskId = jsonValueToInt64(fields["denoTaskId"])
                    }
                case _ => ()
            }
        } catch (_: Exception) {}

        return (archiveId, namespace, denoTaskId)
    }

    private static func jsonValueToString(value: JsonValue): String {
        match (value) {
            case s: JsonString => return s.getValue()
            case _ => return value.toString()
        }
    }

    private static func jsonValueToInt64(value: JsonValue): Int64 {
        match (value) {
            case n: JsonInt => return n.getValue()
            case s: JsonString =>
                try {
                    return Int64.parse(s.getValue())
                } catch (_: Exception) {
                    return 0
                }
            case _ => return 0
        }
    }

    private static func parseMetadataOutput(output: String): ParsedMetadataResult {
        if (output.trimAscii().size == 0) {
            return ParsedMetadataResult(false, "Plugin returned empty output", "", "", "")
        }

        try {
            let jsonVal = JsonValue.fromStr(output)
            match (jsonVal) {
                case obj: JsonObject =>
                    if (!getJsonBool(obj, "success")) {
                        let err = getJsonString(obj, "error")
                        return ParsedMetadataResult(false, if (err.size > 0) { err } else { "Plugin returned success=false" }, "", "", "")
                    }
                    var title = ""
                    var summary = ""
                    var tags = ""
                    let fields = obj.getFields()
                    if (fields.contains("data")) {
                        match (fields["data"]) {
                            case dataObj: JsonObject =>
                                title = getJsonString(dataObj, "title")
                                summary = getJsonString(dataObj, "summary")
                                tags = getJsonString(dataObj, "tags")
                            case _ => ()
                        }
                    }
                    return ParsedMetadataResult(true, "", title, summary, tags)
                case _ =>
                    return ParsedMetadataResult(false, "Plugin output is not a JSON object", "", "", "")
            }
        } catch (e: Exception) {
            return ParsedMetadataResult(false, "Failed to parse plugin output: ${e.message}", "", "", "")
        }
    }

    private static func getJsonBool(jsonObj: JsonObject, key: String): Bool {
        let fields = jsonObj.getFields()
        if (!fields.contains(key)) { return false }
        match (fields[key]) {
            case b: JsonBool => return b.getValue()
            case s: JsonString =>
                let v = s.getValue()
                return v == "true" || v == "True" || v == "TRUE" || v == "1"
            case _ =>
                let v = fields[key].toString()
                return v == "true" || v == "True" || v == "TRUE" || v == "1"
        }
    }

    private static func getJsonString(jsonObj: JsonObject, key: String): String {
        let fields = jsonObj.getFields()
        if (!fields.contains(key)) { return "" }
        match (fields[key]) {
            case s: JsonString => return s.getValue()
            case _ => return fields[key].toString()
        }
    }

    private static func fail(taskId: Int64, message: String): Unit {
        let msg = if (message.size == 0) { "Unknown error" } else { message }
        TaskIO.appendLog(taskId, "FAILED: ${msg}")
        TaskModel.failTask(taskId, msg)
        TaskIO.writeOutput(taskId, "{\"success\":0,\"error\":\"${escapeJson(msg)}\"}")
    }

    private static func buildResultJson(archiveId: String, namespace: String, title: String, summary: String, tags: String, output: String): String {
        "{" +
        "\"success\":1," +
        "\"archive_id\":\"${escapeJson(archiveId)}\"," +
        "\"namespace\":\"${escapeJson(namespace)}\"," +
        "\"title\":\"${escapeJson(title)}\"," +
        "\"summary\":\"${escapeJson(summary)}\"," +
        "\"tags\":\"${escapeJson(tags)}\"," +
        "\"plugin_output\":\"${escapeJson(output)}\"" +
        "}"
    }

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
}
