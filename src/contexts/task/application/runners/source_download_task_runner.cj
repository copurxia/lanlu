package lanlu.contexts.task.application.runners

import std.time.*
import std.convert.*
import std.io.{ByteBuffer, readToEnd}
import std.fs.*
import stdx.encoding.json.stream.*
import lanlu.contexts.plugin.application.PluginTaskService
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.category.infrastructure.persistence.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*

public class SourceDownloadTaskRunner {

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let cachePath = context.paths.cachePath
        FileUtils.ensureDirectoryExists(Path(cachePath))

        let _ = getLogger("source_download_task")
        TaskIO.appendLog(taskId, "source_download task started")
        TaskModel.updateTaskProgress(taskId, 1, "在线源下载任务开始")

        let namespace = parseNamespace(parameters)
        let remoteId = parseRemoteId(parameters)
        let archiveId = parseArchiveId(parameters)
        let categoryId = parseCategoryId(parameters)

        if (namespace.size == 0) {
            fail(taskId, "namespace is required")
            return
        }
        if (remoteId.size == 0) {
            fail(taskId, "remote_id is required")
            return
        }
        if (categoryId <= 0) {
            fail(taskId, "category_id is required")
            return
        }

        let categoryOpt = CategoryDao.getCategoryByInternalId(categoryId)
        match (categoryOpt) {
            case Some(_) => ()
            case None =>
                fail(taskId, "Category not found")
                return
        }

        try {
            TaskIO.appendLog(taskId, "namespace=${namespace}, remote_id=${remoteId}, archive_id=${archiveId}, category_id=${categoryId}")
            TaskModel.updateTaskProgress(taskId, 5, "加载Source插件")

            let plugin = PluginTaskService.getPluginByNamespace(namespace)
            if (plugin.namespace.size == 0) {
                fail(taskId, "Plugin not found: ${namespace}")
                return
            }
            if (plugin.plugin_type.trimAscii() != "Source") {
                fail(taskId, "Plugin is not a Source plugin: ${namespace}")
                return
            }
            if (!plugin.enabled) {
                fail(taskId, "Plugin is not enabled: ${namespace}")
                return
            }

            TaskDao.updateTaskPluginNamespace(taskId, plugin.namespace)
            TaskIO.appendLog(taskId, "matched source plugin=${plugin.namespace}")

            let groupId = "source_${taskId}_${DateTime.now().toUnixTimeStamp().toSeconds()}"
            TaskModel.updateTaskProgress(taskId, 10, "创建WASM下载任务")

            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("pluginNamespace").writeValue(plugin.namespace)
            w.writeName("pluginType").writeValue("Source")
            w.writeName("action").writeValue("source_download")
            w.writeName("groupId").writeValue(groupId)
            w.writeName("parentTaskId").writeValue(taskId)
            w.writeName("targetId").writeValue(remoteId)
            if (archiveId.size > 0) {
                w.writeName("oneshotParam").writeValue(archiveId)
            }
            w.endObject()
            w.flush()
            let runnerParams = String.fromUtf8(readToEnd(out))

            let pluginTask = TaskModel.createTaskWithOptions(
                "执行Source下载插件",
                "wasm_task",
                runnerParams,
                50,
                "source_download:${taskId}",
                "source_download:${taskId}"
            )

            if (pluginTask.id <= 0) {
                fail(taskId, "Failed to create plugin task")
                return
            }

            context.notifyTaskAvailable()

            TaskModel.updateTaskProgress(taskId, 15, "创建回调任务")
            let callbackParams = buildCallbackParams(taskId, pluginTask.id, categoryId, plugin.namespace)
            let callbackTask = TaskModel.createWaitingTask(
                "在线源下载后处理",
                "source_download_callback",
                callbackParams,
                pluginTask.id,
                "source_download:${taskId}",
                "source_download:${taskId}"
            )

            if (callbackTask.id <= 0) {
                fail(taskId, "Failed to create callback task")
                return
            }

            TaskIO.appendLog(taskId, "callback_task created: ${callbackTask.id}, waiting for plugin task: ${pluginTask.id}")

            TaskModel.markTaskWaiting(
                taskId,
                "等待Source插件下载完成",
                progress: 20,
                waitingReason: "task_dependency",
                phase: "awaiting_dependency"
            )
            let submittedJson = "{\"success\":1,\"plugin_task_id\":${pluginTask.id},\"task_type\":\"wasm_task\",\"callback_task_id\":${callbackTask.id}}"
            TaskIO.writeOutput(taskId, submittedJson)
        } catch (e: Exception) {
            fail(taskId, e.message)
        }
    }

    private static func buildCallbackParams(sourceTaskId: Int64, pluginTaskId: Int64, categoryId: Int64, pluginNamespace: String): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("downloadTaskId").writeValue(sourceTaskId)
        w.writeName("pluginTaskId").writeValue(pluginTaskId)
        w.writeName("categoryId").writeValue(categoryId)
        w.writeName("pluginNamespace").writeValue(pluginNamespace)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func parseNamespace(parameters: String): String {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) { return "" }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) { return "" }
            var result = ""
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "namespace" => result = r.readValue<String>().trimAscii()
                    case _ => r.skip()
                }
            }
            r.endObject()
            return result
        } catch (_: Exception) {}
        return ""
    }

    private static func parseRemoteId(parameters: String): String {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) { return "" }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) { return "" }
            var result = ""
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "remote_id" => result = r.readValue<String>().trimAscii()
                    case _ => r.skip()
                }
            }
            r.endObject()
            return result
        } catch (_: Exception) {}
        return ""
    }

    private static func parseArchiveId(parameters: String): String {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) { return "" }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) { return "" }
            var result = ""
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "archive_id" => result = r.readValue<String>().trimAscii()
                    case _ => r.skip()
                }
            }
            r.endObject()
            return result
        } catch (_: Exception) {}
        return ""
    }

    private static func parseCategoryId(parameters: String): Int64 {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) { return 0 }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) { return 0 }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "category_id" =>
                        let raw = r.readValue<String>().trimAscii()
                        try { return Int64.parse(raw) } catch (_: Exception) { return CategoryDao.getInternalId(raw) }
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}
        return 0
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }
}
