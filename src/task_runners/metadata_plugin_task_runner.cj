package lrr4cj.task_runners

import std.collection.*
import std.time.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
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
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("pluginNamespace").writeValue(plugin.namespace)
        w.writeName("pluginType").writeValue("Metadata")
        w.writeName("action").writeValue("run")
        w.writeName("groupId").writeValue(groupId)
        w.writeName("archiveId").writeValue(archiveId)
        match (oneshotOpt) {
            case Some(v) => w.writeName("oneshotParam").writeValue(v)
            case None => ()
        }
        match (extraParamsOpt) {
            case Some(v) => w.writeName("extraParams").writeValue(v)
            case None => ()
        }
        w.endObject()
        w.flush()
        let denoParams = String.fromUtf8(readToEnd(out))

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

        TaskIO.appendLog(taskId, "deno_task created: ${denoTask.id}")

        // 创建回调任务（等待 deno_task 完成后自动触发）
        TaskModel.updateTaskProgress(taskId, 20, "创建回调任务")
        let callbackParams = buildCallbackParams(archiveId, plugin.namespace, denoTask.id)
        let callbackTask = TaskModel.createWaitingTask(
            "元数据写回",
            "metadata_plugin_callback",
            callbackParams,
            denoTask.id,
            groupId,
            "metadata_plugin:${taskId}"
        )

        if (callbackTask.id <= 0) {
            fail(taskId, "Failed to create callback task")
            return
        }

        TaskIO.appendLog(taskId, "callback_task created: ${callbackTask.id}, waiting for deno_task: ${denoTask.id}")

        // 通知 TaskPool 有新任务可用
        context.notifyTaskAvailable()

        // 立即完成原任务（不再等待）
        TaskModel.updateTaskProgress(taskId, 100, "任务已提交")
        let resultJson = "{\"success\":1,\"deno_task_id\":${denoTask.id},\"callback_task_id\":${callbackTask.id}}"
        TaskModel.completeTask(taskId, "metadata_plugin task submitted")
        TaskIO.writeOutput(taskId, resultJson)
    }

    /**
     * 构建回调任务参数
     */
    private static func buildCallbackParams(archiveId: String, namespace: String, denoTaskId: Int64): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("archiveId").writeValue(archiveId)
        w.writeName("namespace").writeValue(namespace)
        w.writeName("denoTaskId").writeValue(denoTaskId)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
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
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            func readRawJson(): String {
                match (r.peek()) {
                    case Some(BeginObject) =>
                        let bytes = r.readValueBytes()
                        return String.fromUtf8(bytes)
                    case Some(BeginArray) =>
                        let bytes = r.readValueBytes()
                        return String.fromUtf8(bytes)
                    case Some(_) =>
                        return r.readValue<String>()
                    case None => return ""
                }
            }

            if (r.peek() == Some(BeginObject)) {
                r.startObject()
                while (r.peek() != EndObject) {
                    let k = r.readName()
                    match (k) {
                        case "archive_id" => archiveId = r.readValue<String>().trimAscii()
                        case "id" =>
                            if (archiveId.size == 0) { archiveId = r.readValue<String>().trimAscii() } else { r.skip() }
                        case "arcid" =>
                            if (archiveId.size == 0) { archiveId = r.readValue<String>().trimAscii() } else { r.skip() }
                        case "archiveId" =>
                            if (archiveId.size == 0) { archiveId = r.readValue<String>().trimAscii() } else { r.skip() }
                        case "namespace" => namespace = r.readValue<String>().trimAscii()
                        case "param" => param = readRawJson()
                        case _ => r.skip()
                    }
                }
                r.endObject()
            }
        } catch (_: Exception) {}

        return (archiveId, namespace, param.trimAscii())
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
                var buf = ByteBuffer()
                unsafe { buf.write(trimmed.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() == Some(BeginObject)) {
                    return (Option.None, Option<String>.Some(trimmed))
                }
            } catch (_: Exception) {}
        }

        return (Option<String>.Some(trimmed), Option.None)
    }

    private static func fail(taskId: Int64, message: String): Unit {
        let msg = if (message.size == 0) { "Unknown error" } else { message }
        TaskIO.appendLog(taskId, "FAILED: ${msg}")
        TaskModel.failTask(taskId, msg)
        TaskIO.writeOutput(taskId, "{\"success\":0,\"error\":\"${escapeJson(msg)}\"}")
    }

}
