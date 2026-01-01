package lrr4cj.task_runners

import std.collection.*
import stdx.encoding.json.*
import std.time.*
import lrr4cj.dao.*
import lrr4cj.models.*
import lrr4cj.utils.*

/**
 * metadata_plugin 任务执行器（运行在TaskPool中）
 * 运行 metadata 插件并将返回的 title/tags/summary 写回归档
 */
public class MetadataPluginTaskRunner {
    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        TaskIO.appendLog(taskId, "metadata_plugin task started")
        TaskModel.updateTaskProgress(taskId, 1, "元数据插件任务开始")
        TaskIO.appendLog(taskId, "metadata_plugin: about to parse parameters")

        let (archiveId, namespace, param) = parseParameters(parameters)
        TaskIO.appendLog(taskId, "metadata_plugin: parameters parsed")
        if (archiveId.size == 0 || namespace.size == 0) {
            fail(taskId, "archive_id and namespace are required")
            return
        }

        TaskIO.appendLog(taskId, "metadata_plugin: about to get archive")
        // 获取归档并验证存在
        let archive = ArchiveDao.getArchiveById(archiveId)
        TaskIO.appendLog(taskId, "metadata_plugin: archive retrieved")
        if (archive.id.size == 0) {
            fail(taskId, "Archive not found")
            return
        }

        TaskIO.appendLog(taskId, "metadata_plugin: about to get plugin")
        // 获取插件并验证类型
        var plugin = PluginDao.getPluginByNamespace(namespace)
        TaskIO.appendLog(taskId, "metadata_plugin: plugin retrieved")
        TaskIO.appendLog(taskId, "metadata_plugin: namespace=${plugin.namespace}, type=${plugin.plugin_type}, enabled=${plugin.enabled}")
        if (plugin.namespace.size == 0) {
            fail(taskId, "Plugin not found")
            return
        }
        TaskIO.appendLog(taskId, "metadata_plugin: namespace check passed")
        if (plugin.plugin_type != "Metadata") {
            fail(taskId, "Plugin is not a Metadata plugin")
            return
        }
        TaskIO.appendLog(taskId, "metadata_plugin: type check passed")
        if (!plugin.enabled) {
            // 与 download_url 保持一致：若匹配到禁用插件，自动启用一次
            plugin.enabled = true
            PluginDao.setEnabled(plugin.namespace, true)
        }
        TaskIO.appendLog(taskId, "metadata_plugin: enabled check passed")
        TaskIO.appendLog(taskId, "metadata_plugin: about to update task plugin namespace")

        let updateResult = TaskDao.updateTaskPluginNamespace(taskId, plugin.namespace)
        TaskIO.appendLog(taskId, "metadata_plugin: update result=${updateResult}")
        TaskIO.appendLog(taskId, "metadata_plugin: task plugin namespace updated")
        TaskIO.appendLog(taskId, "plugin=${plugin.namespace}")

        // 生成 groupId 用于 KV store
        let groupId = "metadata_${taskId}_${DateTime.now().toUnixTimeStamp().toSeconds()}"

        TaskModel.updateTaskProgress(taskId, 10, "创建 Deno 任务")

        let (oneshotOpt, extraParamsOpt) = splitParam(param)

        // 创建 deno_task 参数
        var paramsObj = JsonObject()
        let paramsFields = paramsObj.getFields()
        paramsFields["pluginNamespace"] = JsonString(plugin.namespace)
        paramsFields["pluginType"] = JsonString("Metadata")
        paramsFields["action"] = JsonString("run")
        paramsFields["groupId"] = JsonString(groupId)
        paramsFields["archiveId"] = JsonString(archiveId)
        match (oneshotOpt) {
            case Some(v) => paramsFields["oneshotParam"] = JsonString(v)
            case None => ()
        }
        match (extraParamsOpt) {
            case Some(v) => paramsFields["extraParams"] = JsonString(v)
            case None => ()
        }
        let denoParams = paramsObj.toString()

        // 创建并提交 deno_task
        let denoTask = TaskModel.createTaskWithOptions(
            "执行元数据插件",
            "deno_task",
            denoParams,
            50,
            groupId,
            "metadata_plugin:${taskId}"
        )

        if (denoTask.id <= 0) {
            fail(taskId, "Failed to create deno_task")
            return
        }

        // 通知 TaskPool
        context.notifyTaskAvailable()

        TaskModel.updateTaskProgress(taskId, 30, "等待插件执行")

        // 等待 deno_task 完成
        let denoResult = waitForTaskCompletion(denoTask.id, 300)
        if (!denoResult.success) {
            fail(taskId, "Deno task failed: ${denoResult.error}")
            return
        }

        let output = denoResult.output
        TaskIO.appendLog(taskId, "plugin output: ${output}")

        TaskModel.updateTaskProgress(taskId, 70, "解析并写回元数据")
        let parsed = parseMetadataOutput(output)
        if (!parsed.success) {
            fail(taskId, parsed.error)
            return
        }

        let newTitle = parsed.title
        let newTags = parsed.tags
        let newSummary = parsed.summary

        // 写回 archives 表
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

        TaskModel.updateTaskProgress(taskId, 100, "元数据插件执行完成")
        let resultJson =
            "{" +
            "\"success\":1," +
            "\"archive_id\":\"${escapeJson(archiveId)}\"," +
            "\"namespace\":\"${escapeJson(plugin.namespace)}\"," +
            "\"title\":\"${escapeJson(newTitle)}\"," +
            "\"summary\":\"${escapeJson(newSummary)}\"," +
            "\"tags\":\"${escapeJson(newTags)}\"," +
            "\"plugin_output\":\"${escapeJson(output)}\"" +
            "}"
        TaskModel.completeTask(taskId, "metadata_plugin completed")
        TaskIO.writeOutput(taskId, resultJson)
    }

    private static func parseParameters(parameters: String): (String, String, String) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ("", "", "")
        }

        var archiveId = ""
        var namespace = ""
        var param = ""

        try {
            let jsonVal = JsonValue.fromStr(trimmed)
            match (jsonVal) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    if (fields.contains("archive_id")) {
                        archiveId = jsonValueToString(fields["archive_id"]).trimAscii()
                    } else if (fields.contains("id")) {
                        archiveId = jsonValueToString(fields["id"]).trimAscii()
                    } else if (fields.contains("arcid")) {
                        archiveId = jsonValueToString(fields["arcid"]).trimAscii()
                    } else if (fields.contains("archiveId")) {
                        archiveId = jsonValueToString(fields["archiveId"]).trimAscii()
                    }
                    if (fields.contains("namespace")) {
                        namespace = jsonValueToString(fields["namespace"]).trimAscii()
                    }
                    if (fields.contains("param")) {
                        // param 允许 string / object
                        let pv = fields["param"]
                        match (pv) {
                            case s: JsonString => param = s.getValue()
                            case o: JsonObject => param = o.toString()
                            case _ => param = pv.toString()
                        }
                    }
                case _ => ()
            }
        } catch (_: Exception) {}

        return (archiveId, namespace, param.trimAscii())
    }

    private static func jsonValueToString(value: JsonValue): String {
        match (value) {
            case s: JsonString => return s.getValue()
            case _ => return value.toString()
        }
    }

    /**
     * param 若是 JSON 对象字符串，则作为 extra --params；否则作为 oneshot 参数
     */
    private static func splitParam(param: String): (Option<String>, Option<String>) {
        let trimmed = param.trimAscii()
        if (trimmed.size == 0) {
            return (Option.None, Option.None)
        }

        if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
            try {
                let jsonVal = JsonValue.fromStr(trimmed)
                match (jsonVal) {
                    case _: JsonObject =>
                        return (Option.None, Option<String>.Some(trimmed))
                    case _ => ()
                }
            } catch (_: Exception) {}
        }

        return (Option<String>.Some(trimmed), Option.None)
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

    /**
     * 等待任务完成（轮询 + 指数退避）
     */
    private static func waitForTaskCompletion(taskId: Int64, timeoutSeconds: Int32): TaskWaitResult {
        let startTime = DateTime.now().toUnixTimeStamp().toSeconds()
        var sleepMs: Int64 = 100

        while (true) {
            let task = TaskDao.getTaskDataById(taskId)
            if (task.status == "completed") {
                let output = TaskIO.readOutput(taskId)
                return TaskWaitResult(true, "", output)
            }
            if (task.status == "failed" || task.status == "stopped") {
                return TaskWaitResult(false, task.message, "")
            }

            let elapsed = DateTime.now().toUnixTimeStamp().toSeconds() - startTime
            if (elapsed > Int64(timeoutSeconds)) {
                return TaskWaitResult(false, "Timeout waiting for task", "")
            }

            sleep(Duration.millisecond * sleepMs)
            sleepMs = if (sleepMs * 2 > 2000) { 2000 } else { sleepMs * 2 }
        }
        // This line should never be reached but satisfies the compiler
        return TaskWaitResult(false, "Unexpected error", "")
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

public class ParsedMetadataResult {
    public var success: Bool = false
    public var error: String = ""
    public var title: String = ""
    public var summary: String = ""
    public var tags: String = ""

    public init(success: Bool, error: String, title: String, summary: String, tags: String) {
        this.success = success
        this.error = error
        this.title = title
        this.summary = summary
        this.tags = tags
    }
}
