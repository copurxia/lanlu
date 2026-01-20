package lrr4cj.task_runners

import std.collection.*
import std.convert.*
import std.fs.*
import std.time.*
import stdx.encoding.json.*
import stdx.log.*
import lrr4cj.dao.*
import lrr4cj.models.*
import lrr4cj.utils.*

/**
 * download_url_callback 回调任务执行器
 * 在 deno_task 结束后触发：读取下载插件输出、搬运文件、创建 scan_archive，并将结果写回到 download_url 任务
 */
public class DownloadUrlCallbackRunner {
    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("download_url_callback")
        TaskIO.appendLog(taskId, "download_url_callback task started")
        TaskModel.updateTaskProgress(taskId, 10, "开始处理下载回调")

        let (downloadTaskId, denoTaskId, categoryId, pluginNamespace) = parseParameters(parameters)
        if (downloadTaskId <= 0 || denoTaskId <= 0 || categoryId <= 0 || pluginNamespace.size == 0) {
            fail(taskId, "Invalid callback parameters")
            return
        }

        TaskIO.appendLog(
            taskId,
            "callback params: downloadTaskId=${downloadTaskId}, denoTaskId=${denoTaskId}, categoryId=${categoryId}, pluginNamespace=${pluginNamespace}"
        )

        // 读取 deno_task 状态/输出（失败时依旧会写 output JSON，但 status=failed）
        let denoTask = TaskDao.getTaskDataById(denoTaskId)
        let pluginOutput = TaskIO.readOutput(denoTaskId)

        if (denoTask.status != "completed") {
            let errMsg =
                if (denoTask.message.trimAscii().size > 0) { denoTask.message } else { "Deno task failed" }
            // 将失败写回父任务，避免前端卡在 waiting
            TaskModel.failTask(downloadTaskId, errMsg)
            TaskIO.writeOutput(downloadTaskId, "{\"success\":0,\"error\":\"${escapeJson(errMsg)}\"}")
            fail(taskId, "Dependency deno_task not completed: ${denoTask.status} - ${errMsg}")
            return
        }

        if (pluginOutput.trimAscii().size == 0) {
            let errMsg = "Deno task output is empty"
            TaskModel.failTask(downloadTaskId, errMsg)
            TaskIO.writeOutput(downloadTaskId, "{\"success\":0,\"error\":\"${escapeJson(errMsg)}\"}")
            fail(taskId, errMsg)
            return
        }

        // 插件自行下载并回传 relative_path（相对于缓存目录）
        TaskModel.updateTaskProgress(taskId, 30, "解析插件输出")
        let downloadedRelativePaths = parseDownloadedRelativePath(pluginOutput)
        let downloadedSource = parseDownloadedSource(pluginOutput)

        if (downloadedRelativePaths.size == 0) {
            let pluginErr = parsePluginError(pluginOutput)
            let errMsg = if (pluginErr.size > 0) { pluginErr } else { "Plugin did not return relative_path" }
            TaskModel.failTask(downloadTaskId, errMsg)
            TaskIO.writeOutput(downloadTaskId, "{\"success\":0,\"error\":\"${escapeJson(errMsg)}\"}")
            fail(taskId, errMsg)
            return
        }
        if (downloadedRelativePaths.size > 1) {
            let errMsg = "Multiple archives not yet supported in this version"
            TaskModel.failTask(downloadTaskId, errMsg)
            TaskIO.writeOutput(downloadTaskId, "{\"success\":0,\"error\":\"${escapeJson(errMsg)}\"}")
            fail(taskId, errMsg)
            return
        }

        let downloadedRelativePath = downloadedRelativePaths.get(0).getOrThrow()
        if (downloadedRelativePath.contains("..") || downloadedRelativePath.startsWith("/") ||
            !downloadedRelativePath.startsWith("plugins/${pluginNamespace}/")) {
            let errMsg = "Plugin returned invalid relative_path"
            TaskModel.failTask(downloadTaskId, errMsg)
            TaskIO.writeOutput(downloadTaskId, "{\"success\":0,\"error\":\"${escapeJson(errMsg)}\"}")
            fail(taskId, errMsg)
            return
        }

        // 获取分类信息
        let categoryOpt = CategoryDao.getCategoryByInternalId(categoryId)
        var categoryPath = ""
        match (categoryOpt) {
            case Some(cat) =>
                categoryPath = cat.scanPath
            case None =>
                let errMsg = "Category not found"
                TaskModel.failTask(downloadTaskId, errMsg)
                TaskIO.writeOutput(downloadTaskId, "{\"success\":0,\"error\":\"${escapeJson(errMsg)}\"}")
                fail(taskId, errMsg)
                return
        }

        // 搬运文件到归档目录
        TaskModel.updateTaskProgress(taskId, 60, "搬运下载文件")
        let cachePath = context.paths.cachePath
        let pluginTarget = Path("${cachePath}/${downloadedRelativePath}")
        if (!exists(pluginTarget)) {
            let errMsg = "Plugin downloaded file not found"
            TaskModel.failTask(downloadTaskId, errMsg)
            TaskIO.writeOutput(downloadTaskId, "{\"success\":0,\"error\":\"${escapeJson(errMsg)}\"}")
            fail(taskId, errMsg)
            return
        }
        let fileName = pluginTarget.fileName

        let archiveDir = Path(categoryPath)
        FileUtils.ensureDirectoryExists(archiveDir)

        let finalArchivePath = Path("${categoryPath}/${fileName}")
        let finalArchivePathStr = finalArchivePath.toString()

        try {
            // 移动文件到归档目录（支持跨设备：rename 失败时 fallback 到 copy+remove）
            try {
                rename(pluginTarget, to: finalArchivePath)
            } catch (e: Exception) {
                if (e.message.contains("cross-device") || e.message.contains("Invalid cross-device link")) {
                    copy(pluginTarget, to: finalArchivePath, overwrite: false)
                    // copy 成功后尽力删除源文件（避免缓存目录堆积）
                    try { remove(pluginTarget) } catch (_: Exception) {}
                } else {
                    throw e
                }
            }

            // 验证移动结果
            if (!exists(finalArchivePath)) {
                throw Exception("文件移动失败：目标文件不存在")
            }
        } catch (e: Exception) {
            let errMsg = "Failed to move file to archive: ${e.message}"
            TaskModel.failTask(downloadTaskId, errMsg)
            TaskIO.writeOutput(downloadTaskId, "{\"success\":0,\"error\":\"${escapeJson(errMsg)}\"}")
            fail(taskId, errMsg)
            return
        }

        // 创建 scan_archive 任务
        TaskModel.updateTaskProgress(taskId, 80, "创建扫描任务")

        let cachePathStr = cachePath.toString()

        // 解析插件返回的 archive_type
        let archiveType = parseArchiveTypeFromPlugin(pluginOutput)

        // 构建包含source的tags
        var tags = ""
        if (downloadedSource.size > 0) {
            tags = "source:${downloadedSource}"
        }

        let scanParams = """
            {
                "archive_path":"${escapeJson(finalArchivePathStr)}",
                "category_id":${categoryId},
                "cache_path":"${escapeJson(cachePathStr)}",
                "archive_type":"${archiveType}",
                "tags":"${escapeJson(tags)}"
            }
        """
        let scanTask = TaskModel.createTaskWithOptions(
            "扫描档案",
            "scan_archive",
            scanParams,
            50,
            "download_url:${downloadTaskId}",
            "upload"
        )
        if (scanTask.id <= 0) {
            let errMsg = "Failed to create scan_archive task"
            TaskModel.failTask(downloadTaskId, errMsg)
            TaskIO.writeOutput(downloadTaskId, "{\"success\":0,\"error\":\"${escapeJson(errMsg)}\"}")
            fail(taskId, errMsg)
            return
        }

        // 通知 TaskPool 有新任务可用（scan_archive）
        context.notifyTaskAvailable()

        // 将结果写回父任务（download_url）
        let resultJson = "{\"success\":1,\"archives\":[{\"filename\":\"${escapeJson(fileName)}\"}],\"task_id\":\"${scanTask.id}\"}"
        TaskModel.updateTaskProgress(downloadTaskId, 100, "下载完成")
        TaskModel.completeTask(downloadTaskId, "download_url completed")
        TaskIO.writeOutput(downloadTaskId, resultJson)
        TaskIO.appendLog(downloadTaskId, "download_url task completed: scan_task_id=${scanTask.id}")

        // 完成回调任务自身
        TaskModel.updateTaskProgress(taskId, 100, "下载回调完成")
        TaskModel.completeTask(taskId, "download_url_callback completed")
        TaskIO.writeOutput(taskId, "{\"success\":1,\"download_task_id\":${downloadTaskId},\"scan_task_id\":${scanTask.id}}")

        logger.debug("download_url_callback completed", ("download_task_id", downloadTaskId.toString()), ("scan_task_id", scanTask.id.toString()))
    }

    private static func parseParameters(parameters: String): (Int64, Int64, Int64, String) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return (0, 0, 0, "")
        }

        var downloadTaskId: Int64 = 0
        var denoTaskId: Int64 = 0
        var categoryId: Int64 = 0
        var pluginNamespace = ""

        try {
            let jsonVal = JsonValue.fromStr(trimmed)
            match (jsonVal) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    if (fields.contains("downloadTaskId")) {
                        downloadTaskId = jsonValueToInt64(fields["downloadTaskId"])
                    }
                    if (fields.contains("denoTaskId")) {
                        denoTaskId = jsonValueToInt64(fields["denoTaskId"])
                    }
                    if (fields.contains("categoryId")) {
                        categoryId = jsonValueToInt64(fields["categoryId"])
                    }
                    if (fields.contains("pluginNamespace")) {
                        pluginNamespace = jsonValueToString(fields["pluginNamespace"]).trimAscii()
                    }
                case _ => ()
            }
        } catch (_: Exception) {}

        return (downloadTaskId, denoTaskId, categoryId, pluginNamespace)
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
            case _ =>
                try {
                    return Int64.parse(value.toString())
                } catch (_: Exception) {
                    return 0
                }
        }
    }

    private static func parsePluginError(output: String): String {
        if (output.trimAscii().size == 0) {
            return ""
        }
        try {
            let jsonVal = JsonValue.fromStr(output)
            match (jsonVal) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    if (fields.contains("success")) {
                        let successVal = fields["success"].toString()
                        if (successVal == "false" || successVal == "0") {
                            if (fields.contains("error")) {
                                return jsonValueToString(fields["error"]).trimAscii()
                            }
                        }
                    }
                case _ => ()
            }
        } catch (_: Exception) {}
        return ""
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
        } catch (_: Exception) {}
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
        } catch (_: Exception) {}
        return ""
    }

    private static func parseArchiveTypeFromPlugin(output: String): String {
        if (output.size == 0) {
            return "archive"
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
        return "archive"
    }

    private static func fail(taskId: Int64, message: String): Unit {
        let msg = if (message.size == 0) { "Unknown error" } else { message }
        TaskIO.appendLog(taskId, "FAILED: ${msg}")
        TaskModel.failTask(taskId, msg)
        TaskIO.writeOutput(taskId, "{\"success\":0,\"error\":\"${escapeJson(msg)}\"}")
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
