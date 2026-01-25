package lanlu.task_runners

import std.regex.*
import std.fs.*
import std.time.*
import std.convert.*
import stdx.log.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.dao.*
import lanlu.models.*
import lanlu.utils.*

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

            TaskModel.updateTaskProgress(taskId, 10, "创建 Deno 任务")

            // 创建 deno_task 参数
            // parentTaskId allows deno_task to mirror plugin logs/progress back to this download_url task.
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
            let denoParams = String.fromUtf8(readToEnd(out))

            // 创建并提交 deno_task
            let denoTask = TaskModel.createTaskWithOptions(
                "执行下载插件",
                "deno_task",
                denoParams,
                50,
                "download_url:${taskId}",
                "download_url:${taskId}"
            )

            if (denoTask.id <= 0) {
                fail(taskId, "Failed to create deno_task")
                return
            }

            // 通知 TaskPool
            context.notifyTaskAvailable()

            // 创建回调任务（等待 deno_task 完成后自动触发）
            //
            // 这里不再同步等待 deno_task，避免 worker 被占满导致 deno_task 无法被调度的死锁风险。
            TaskModel.updateTaskProgress(taskId, 15, "创建回调任务")
            let callbackParams = buildCallbackParams(taskId, denoTask.id, categoryId, plugin.namespace)
            let callbackTask = TaskModel.createWaitingTask(
                "下载后处理",
                "download_url_callback",
                callbackParams,
                denoTask.id,
                "download_url:${taskId}",
                "download_url:${taskId}"
            )

            if (callbackTask.id <= 0) {
                fail(taskId, "Failed to create callback task")
                return
            }

            TaskIO.appendLog(taskId, "callback_task created: ${callbackTask.id}, waiting for deno_task: ${denoTask.id}")

            // 将当前任务置为 waiting：后续由 callback 负责将本任务标记为 completed/failed 并写回输出
            TaskDao.updateTaskStatus(taskId, "waiting", "等待下载插件执行", 20)
            let submittedJson = "{\"success\":1,\"deno_task_id\":${denoTask.id},\"callback_task_id\":${callbackTask.id}}"
            TaskIO.writeOutput(taskId, submittedJson)
        } catch (e: Exception) {
            fail(taskId, e.message)
        }
    }

    /**
     * 构建回调任务参数
     */
    private static func buildCallbackParams(downloadTaskId: Int64, denoTaskId: Int64, categoryId: Int64, pluginNamespace: String): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("downloadTaskId").writeValue(downloadTaskId)
        w.writeName("denoTaskId").writeValue(denoTaskId)
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

    private static func findMatchingDownloadPlugin(url: String): Option<PluginData> {
        let logger = getLogger("download_url_task")
        let plugins = PluginDao.getPluginsByType("Download")
        var disabledMatch: Option<PluginData> = Option.None

        for (plugin in plugins) {
            if (plugin.url_regex.size == 0) {
                continue
            }
            try {
                let regex = Regex(plugin.url_regex)
                match (regex.find(url)) {
                    case Some(_) =>
                        if (plugin.enabled) {
                            return Option<PluginData>.Some(plugin)
                        } else if (disabledMatch.isNone()) {
                            disabledMatch = Option<PluginData>.Some(plugin)
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
            let enabled = PluginDao.setEnabled(plugin.namespace, true)
            if (!enabled) {
                logger.warn("自动启用下载插件失败", ("namespace", plugin.namespace))
            }
            return Option<PluginData>.Some(plugin)
        }

        return Option<PluginData>.None
    }
}
