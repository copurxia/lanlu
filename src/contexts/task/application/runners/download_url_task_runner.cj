package lanlu.contexts.task.application.runners

import std.regex.*
import std.fs.*
import std.time.*
import std.convert.*
import stdx.log.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.contexts.plugin.application.PluginTaskService
import lanlu.contexts.plugin.application.PluginTaskData
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.category.infrastructure.persistence.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*

/**
 * download_url 任务执行器（运行在TaskPool中）
 */
public class DownloadUrlTaskRunner {

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let cachePath = context.paths.cachePath

        // 确保目录存在
        FileUtils.ensureDirectoryExists(Path(cachePath))

        let _ = getLogger("download_url_task")
        TaskIO.appendLog(taskId, "download_url task started")
        TaskModel.updateTaskProgress(taskId, 1, "下载任务开始")

        let url = parseUrl(parameters)
        if (url.size == 0) {
            fail(taskId, "url is required")
            return
        }

        let categoryId = parseCategoryId(parameters)
        if (categoryId <= 0) {
            fail(taskId, "category_id is required")
            return
        }

        // 获取分类信息
        let categoryOpt = CategoryDao.getCategoryByInternalId(categoryId)
        match (categoryOpt) {
            case Some(_) =>
                ()
            case None =>
                fail(taskId, "Category not found")
                return
        }

        try {
            TaskIO.appendLog(taskId, "url=${url}")
            TaskModel.updateTaskProgress(taskId, 5, "匹配下载插件")

            let pluginOpt = findMatchingDownloadPlugin(url)
            if (pluginOpt.isNone()) {
                fail(taskId, "No download plugin matches provided url")
                return
            }
            let plugin = pluginOpt.getOrThrow()
            TaskDao.updateTaskPluginNamespace(taskId, plugin.namespace)
            TaskIO.appendLog(taskId, "matched plugin=${plugin.namespace}")

            // 生成 groupId 用于 KV store
            let groupId = "download_${taskId}_${DateTime.now().toUnixTimeStamp().toSeconds()}"

            let runnerTaskType = PluginTaskService.getRunnerTaskType(plugin)
            let runnerLabel = "WASM"
            TaskModel.updateTaskProgress(taskId, 10, "创建 ${runnerLabel} 任务")

            // 创建 runner 参数
            // parentTaskId allows plugin task to mirror logs/progress back to this download_url task.
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("pluginNamespace").writeValue(plugin.namespace)
            w.writeName("pluginType").writeValue("Download")
            w.writeName("action").writeValue("run")
            w.writeName("groupId").writeValue(groupId)
            w.writeName("parentTaskId").writeValue(taskId)
            w.writeName("url").writeValue(url)
            w.endObject()
            w.flush()
            let runnerParams = String.fromUtf8(readToEnd(out))

            // 创建并提交插件任务（wasm_task）
            let pluginTask = TaskModel.createTaskWithOptions(
                "执行下载插件",
                runnerTaskType,
                runnerParams,
                50,
                "download_url:${taskId}",
                "download_url:${taskId}"
            )

            if (pluginTask.id <= 0) {
                fail(taskId, "Failed to create plugin task")
                return
            }

            // 通知 TaskPool
            context.notifyTaskAvailable()

            // 创建回调任务（等待插件任务完成后自动触发）
            //
            // 这里不再同步等待插件任务，避免 worker 被占满导致依赖任务无法被调度的死锁风险。
            TaskModel.updateTaskProgress(taskId, 15, "创建回调任务")
            let callbackParams = buildCallbackParams(taskId, pluginTask.id, categoryId, plugin.namespace)
            let callbackTask = TaskModel.createWaitingTask(
                "下载后处理",
                "download_url_callback",
                callbackParams,
                pluginTask.id,
                "download_url:${taskId}",
                "download_url:${taskId}"
            )

            if (callbackTask.id <= 0) {
                fail(taskId, "Failed to create callback task")
                return
            }

            TaskIO.appendLog(taskId, "callback_task created: ${callbackTask.id}, waiting for plugin task: ${pluginTask.id} (${runnerTaskType})")

            // 将当前任务置为 waiting：后续由 callback 负责将本任务标记为 completed/failed 并写回输出
            TaskDao.updateTaskStatus(taskId, "waiting", "等待下载插件执行", 20)
            let submittedJson = "{\"success\":1,\"plugin_task_id\":${pluginTask.id},\"task_type\":\"${runnerTaskType}\",\"callback_task_id\":${callbackTask.id}}"
            TaskIO.writeOutput(taskId, submittedJson)
        } catch (e: Exception) {
            fail(taskId, e.message)
        }
    }

    /**
     * 构建回调任务参数
     */
    private static func buildCallbackParams(downloadTaskId: Int64, pluginTaskId: Int64, categoryId: Int64, pluginNamespace: String): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("downloadTaskId").writeValue(downloadTaskId)
        w.writeName("pluginTaskId").writeValue(pluginTaskId)
        w.writeName("categoryId").writeValue(categoryId)
        w.writeName("pluginNamespace").writeValue(pluginNamespace)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }

    private static func parseUrl(parameters: String): String {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ""
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) { return "" }
            var url = ""
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "url" => url = r.readValue<String>().trimAscii()
                    case _ => r.skip()
                }
            }
            r.endObject()
            return url
        } catch (_: Exception) {}
        return ""
    }

    private static func parseCategoryId(parameters: String): Int64 {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return 0
        }
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

    private static func findMatchingDownloadPlugin(url: String): Option<PluginTaskData> {
        let logger = getLogger("download_url_task")
        let plugins = PluginTaskService.getPluginsByType("Download")
        var disabledMatch: Option<PluginTaskData> = Option.None

        for (plugin in plugins) {
            if (plugin.url_regex.size == 0) {
                continue
            }
            try {
                let regex = Regex(plugin.url_regex)
                match (regex.find(url)) {
                    case Some(_) =>
                        if (plugin.enabled) {
                            return Option<PluginTaskData>.Some(plugin)
                        } else if (disabledMatch.isNone()) {
                            disabledMatch = Option<PluginTaskData>.Some(plugin)
                        }
                    case None => ()
                }
            } catch (_: Exception) {
                logger.warn("跳过无效的下载插件正则", ("namespace", plugin.namespace), ("regex", plugin.url_regex))
            }
        }

        if (disabledMatch.isSome()) {
            let plugin = disabledMatch.getOrThrow()
            logger.warn("匹配到禁用的下载插件，自动启用", ("namespace", plugin.namespace))
            plugin.enabled = true
            let enabled = PluginTaskService.setEnabled(plugin.namespace, true)
            if (!enabled) {
                logger.warn("自动启用下载插件失败", ("namespace", plugin.namespace))
            }
            return Option<PluginTaskData>.Some(plugin)
        }

        return Option<PluginTaskData>.None
    }
}
