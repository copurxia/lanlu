package lrr4cj.task_runners

import std.regex.*
import std.fs.*
import std.time.*
import std.convert.*
import std.collection.*
import stdx.encoding.json.*
import stdx.log.*
import lrr4cj.dao.*
import lrr4cj.models.*
import lrr4cj.utils.*

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
        var categoryPath = ""
        match (categoryOpt) {
            case Some(cat) =>
                categoryPath = cat.scanPath
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
            let denoParams = "{\"pluginNamespace\":\"${escapeJson(plugin.namespace)}\",\"pluginType\":\"Download\",\"action\":\"run\",\"groupId\":\"${escapeJson(groupId)}\",\"parentTaskId\":${taskId},\"url\":\"${escapeJson(url)}\"}"

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
        var paramsObj = JsonObject()
        let fields = paramsObj.getFields()
        fields["downloadTaskId"] = JsonInt(downloadTaskId)
        fields["denoTaskId"] = JsonInt(denoTaskId)
        fields["categoryId"] = JsonInt(categoryId)
        fields["pluginNamespace"] = JsonString(pluginNamespace)
        return paramsObj.toString()
    }

    private static func fail(taskId: Int64, message: String): Unit {
        let msg = if (message.size == 0) { "Unknown error" } else { message }
        TaskIO.appendLog(taskId, "FAILED: ${msg}")
        TaskModel.failTask(taskId, msg)
        TaskIO.writeOutput(taskId, "{\"success\":0,\"error\":\"${escapeJson(msg)}\"}")
    }

    private static func parseUrl(parameters: String): String {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ""
        }
        try {
            let bodyJson = JsonValue.fromStr(trimmed)
            match (bodyJson) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    if (fields.contains("url")) {
                        return fields["url"].toString().trimAscii()
                    }
                case _ => ()
            }
        } catch (_: Exception) {}
        return ""
    }

    private static func parseCategoryId(parameters: String): Int64 {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return 0
        }
        try {
            let bodyJson = JsonValue.fromStr(trimmed)
            match (bodyJson) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    if (fields.contains("category_id")) {
                        let raw = fields["category_id"].toString().trimAscii()
                        // 兼容两种格式：
                        // - 直接传内部ID（Int）
                        // - 传 catid（如 CAT_...），需要再查一次内部ID
                        try {
                            return Int64.parse(raw)
                        } catch (_: Exception) {
                            return CategoryDao.getInternalId(raw)
                        }
                    }
                case _ => ()
            }
        } catch (_: Exception) {}
        return 0
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

    private static func parseDownloadedRelativePath(output: String): ArrayList<String> {
        var paths = ArrayList<String>()
        if (output.size == 0) {
            return paths
        }
        try {
            let jsonVal = JsonValue.fromStr(output)
            match (jsonVal) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    if (fields.contains("success")) {
                        let successVal = fields["success"].toString()
                        if (successVal == "true" || successVal == "1") {
                            if (fields.contains("data")) {
                                let dataVal = fields["data"]
                                match (dataVal) {
                                    case dataArray: JsonArray =>
                                        // 数组格式：提取每个档案的relative_path
                                        for (i in 0..dataArray.size()) {
                                            match (dataArray.get(i)) {
                                                case Some(item: JsonObject) =>
                                                    let itemFields = item.getFields()
                                                    if (itemFields.contains("relative_path")) {
                                                        let rpVal = itemFields["relative_path"]
                                                        match (rpVal) {
                                                            case rpStr: JsonString => paths.add(rpStr.getValue().trimAscii())
                                                            case _ => paths.add(rpVal.toString().trimAscii())
                                                        }
                                                    }
                                                case _ => ()
                                            }
                                        }
                                    case _ => ()
                                }
                            }
                        }
                    }
                case _ => ()
            }
        } catch (_: Exception) {
            return paths
        }
        return paths
    }

    private static func parseDownloadedSource(output: String): String {
        if (output.size == 0) {
            return ""
        }
        try {
            let jsonVal = JsonValue.fromStr(output)
            match (jsonVal) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    if (fields.contains("success")) {
                        let successVal = fields["success"].toString()
                        if (successVal == "true" || successVal == "1") {
                            if (fields.contains("data")) {
                                let dataVal = fields["data"]
                                match (dataVal) {
                                    case dataArray: JsonArray =>
                                        // 数组格式：提取第一个档案的source
                                        if (dataArray.size() > 0) {
                                            match (dataArray.get(0)) {
                                                case Some(item: JsonObject) =>
                                                    let itemFields = item.getFields()
                                                    if (itemFields.contains("source")) {
                                                        let sourceVal = itemFields["source"]
                                                        match (sourceVal) {
                                                            case sourceStr: JsonString => return sourceStr.getValue().trimAscii()
                                                            case _ => return sourceVal.toString().trimAscii()
                                                        }
                                                    }
                                                case _ => ()
                                            }
                                        }
                                    case _ => ()
                                }
                            }
                        }
                    }
                case _ => ()
            }
        } catch (_: Exception) {
            return ""
        }
        return ""
    }

    private static func parseArchiveTypeFromPlugin(output: String): String {
        if (output.size == 0) {
            return "archive"  // 默认压缩包
        }
        try {
            let jsonVal = JsonValue.fromStr(output)
            match (jsonVal) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    if (fields.contains("success")) {
                        let successVal = fields["success"].toString()
                        if (successVal == "true" || successVal == "1") {
                            if (fields.contains("data")) {
                                let dataVal = fields["data"]
                                match (dataVal) {
                                    case dataObj: JsonObject =>
                                        let dataFields = dataObj.getFields()
                                        if (dataFields.contains("archive_type")) {
                                            let typeVal = dataFields["archive_type"]
                                            match (typeVal) {
                                                case typeStr: JsonString =>
                                                    let typeName = typeStr.getValue().trimAscii()
                                                    // 验证类型是否有效
                                                    if (typeName == "archive" || typeName == "folder" || typeName == "pdf") {
                                                        return typeName
                                                    }
                                                case _ => ()
                                            }
                                        }
                                    case _ => ()
                                }
                            }
                        }
                    }
                case _ => ()
            }
        } catch (_: Exception) {}
        return "archive"  // 默认压缩包（向后兼容）
    }
}
