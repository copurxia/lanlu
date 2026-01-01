package lrr4cj.task_runners

import std.regex.*
import std.fs.*
import std.process.*
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
        let thumbnailPath = context.paths.thumbnailPath

        // 确保目录存在
        FileUtils.ensureDirectoryExists(Path(cachePath))
        FileUtils.ensureDirectoryExists(Path(thumbnailPath))

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
            case Some(cat) => categoryPath = cat.scanPath
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
            let denoParams = "{\"pluginNamespace\":\"${escapeJson(plugin.namespace)}\",\"pluginType\":\"Download\",\"action\":\"run\",\"groupId\":\"${escapeJson(groupId)}\",\"url\":\"${escapeJson(url)}\"}"

            // 创建并提交 deno_task
            let denoTask = TaskModel.createTaskWithOptions(
                "执行下载插件",
                "deno_task",
                denoParams,
                50,
                groupId,
                "download_url:${taskId}"
            )

            if (denoTask.id <= 0) {
                fail(taskId, "Failed to create deno_task")
                return
            }

            // 通知 TaskPool
            context.notifyTaskAvailable()

            TaskModel.updateTaskProgress(taskId, 15, "等待插件执行")

            // 等待 deno_task 完成
            let denoResult = waitForTaskCompletion(denoTask.id, 300)
            if (!denoResult.success) {
                fail(taskId, "Deno task failed: ${denoResult.error}")
                return
            }

            let output = denoResult.output
            let loginCookiesJson = denoResult.cookiesJson
            TaskIO.appendLog(taskId, "plugin output: ${output}")

            // 插件自行下载并回传 relative_path（相对于 ./data）
            let downloadedRelativePaths = parseDownloadedRelativePath(output)
            let usePluginDownloadedFile = downloadedRelativePaths.size > 0
            let downloadedSource = parseDownloadedSource(output)
            var downloadUrl = ""
            if (!usePluginDownloadedFile) {
                downloadUrl = parseDownloadUrl(output)
                if (downloadUrl.size == 0) {
                    fail(taskId, "Plugin did not return download_url or relative_path")
                    return
                }
            }

            // 检查是否返回了多个档案
            if (downloadedRelativePaths.size > 1) {
                fail(taskId, "Multiple archives not yet supported in this version")
                return
            }

            if (downloadedRelativePaths.size == 0) {
                fail(taskId, "No archives returned from plugin")
                return
            }

            TaskModel.updateTaskProgress(taskId, 35, "下载文件")

            var fileName = ""
            var pluginTarget = Path("")

            // 处理数组中的第一个（也是唯一的）档案
            let downloadedRelativePath = downloadedRelativePaths.get(0).getOrThrow()

            if (usePluginDownloadedFile) {
                if (downloadedRelativePath.contains("..") || downloadedRelativePath.startsWith("/") ||
                    !downloadedRelativePath.startsWith("plugins/${plugin.namespace}/")) {
                    fail(taskId, "Plugin returned invalid relative_path")
                    return
                }

                pluginTarget = Path("./data/${downloadedRelativePath}")
                if (!exists(pluginTarget)) {
                    fail(taskId, "Plugin downloaded file not found")
                    return
                }
                fileName = pluginTarget.fileName
            } else {
                fileName = deriveFileName(downloadUrl)
                if (fileName.size == 0) {
                    fileName = "download_${DateTime.now().toUnixTimeStamp().toSeconds().toString()}.bin"
                }

                let pluginDataDir = "./data/plugins/${plugin.namespace}"
                pluginTarget = Path("${pluginDataDir}/${fileName}")
                FileUtils.ensureDirectoryExists(Path(pluginDataDir))

                let downloadOk = downloadToPath(downloadUrl, pluginTarget.toString(), loginCookiesJson)
                if (!downloadOk) {
                    fail(taskId, "Failed to download file from plugin url")
                    return
                }
            }

            TaskModel.updateTaskProgress(taskId, 60, "移动到archive")

            let archiveDir = Path(categoryPath)
            FileUtils.ensureDirectoryExists(archiveDir)

            let finalArchivePath = Path("${categoryPath}/${fileName}")
            let finalArchivePathStr = finalArchivePath.toString()

            try {
                rename(pluginTarget, to: finalArchivePath)
            } catch (e: Exception) {
                fail(taskId, "Failed to move file to archive: ${e.message}")
                return
            }

            TaskModel.updateTaskProgress(taskId, 80, "创建扫描任务")

            // 获取配置
            let cachePathStr = cachePath.toString()
            let thumbnailPathStr = thumbnailPath.toString()

            // 解析插件返回的 archive_type
            let archiveType = parseArchiveTypeFromPlugin(output)

            // 构建包含source的tags
            var tags = ""
            if (downloadedSource.size > 0) {
                tags = "source:${downloadedSource}"
            }

            // 创建 scan_archive 任务
            let params = """
                {
                    "archive_path":"${escapeJson(finalArchivePathStr)}",
                    "category_id":${categoryId},
                    "cache_path":"${escapeJson(cachePathStr)}",
                    "thumbnail_path":"${escapeJson(thumbnailPathStr)}",
                    "archive_type":"${archiveType}",
                    "tags":"${escapeJson(tags)}"
                }
            """
            let task = TaskModel.createTaskWithOptions("扫描档案", "scan_archive", params, 50, "download_url:${taskId}", "upload")
            if (task.id <= 0) {
                let errorJson = "{\"success\":0,\"error\":\"Failed to create scan_archive task\"}"
                TaskModel.failTask(taskId, "Failed to create scan_archive task")
                TaskIO.writeOutput(taskId, errorJson)
                return
            }

            let resultJson = "{\"success\":1,\"archives\":[{\"filename\":\"${escapeJson(fileName)}\"}],\"task_id\":\"${task.id}\"}"

            TaskModel.updateTaskProgress(taskId, 100, "下载完成")
            TaskModel.completeTask(taskId, "download_url completed")
            TaskIO.writeOutput(taskId, resultJson)
            TaskIO.appendLog(taskId, "download_url task completed: scan_task_id=${task.id}")
        } catch (e: Exception) {
            fail(taskId, e.message)
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
                        return Int64.parse(fields["category_id"].toString().trimAscii())
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

    private static func parseDownloadUrl(output: String): String {
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
                                    case dataObj: JsonObject =>
                                        let dataFields = dataObj.getFields()
                                        if (dataFields.contains("download_url")) {
                                            let dlVal = dataFields["download_url"]
                                            match (dlVal) {
                                                case dlStr: JsonString => return dlStr.getValue()
                                                case _ => return dlVal.toString()
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

    private static func deriveFileName(downloadUrl: String): String {
        let parts = downloadUrl.split("/")
        if (parts.size == 0) {
            return ""
        }
        var candidate = parts[parts.size - 1]
        if (candidate.contains("?")) {
            candidate = candidate.split("?")[0]
        }
        return candidate
    }

    private static func downloadToPath(url: String, outputPath: String, loginCookiesJson: String): Bool {
        try {
            var args = ArrayList<String>()
            args.add("-L")
            args.add("-A")
            args.add("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")

            let cookieHeader = buildCookieHeaderForUrl(url, loginCookiesJson)
            if (cookieHeader.size > 0) {
                args.add("-H")
                args.add("Cookie: ${cookieHeader}")
            }

            args.add(url)
            args.add("-o")
            args.add(outputPath)

            let process = launch("curl", args.toArray(), stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
            let exitCode = process.wait()
            return exitCode == 0
        } catch (_: Exception) {
            return false
        }
    }

    private static func buildCookieHeaderForUrl(targetUrl: String, cookiesJson: String): String {
        let trimmed = cookiesJson.trimAscii()
        if (trimmed.size == 0) {
            return ""
        }

        let host = extractHostname(targetUrl)
        if (host.size == 0) {
            return ""
        }

        try {
            let jsonVal = JsonValue.fromStr(trimmed)
            match (jsonVal) {
                case arr: JsonArray =>
                    var parts = ArrayList<String>()
                    let size = arr.size()
                    for (i in 0..size) {
                        match (arr.get(i)) {
                            case Some(v) =>
                                match (v) {
                                    case obj: JsonObject =>
                                        let fields = obj.getFields()
                                        let name = match (fields.get("name")) {
                                            case Some(s: JsonString) => s.getValue().trimAscii()
                                            case Some(other) => other.toString().trimAscii()
                                            case None => ""
                                        }
                                        let value = match (fields.get("value")) {
                                            case Some(s: JsonString) => s.getValue().trimAscii()
                                            case Some(other) => other.toString().trimAscii()
                                            case None => ""
                                        }
                                        let domain = match (fields.get("domain")) {
                                            case Some(s: JsonString) => s.getValue().trimAscii()
                                            case Some(other) => other.toString().trimAscii()
                                            case None => ""
                                        }
                                        if (name.size > 0 && value.size > 0 && domainMatches(domain, host)) {
                                            parts.add("${name}=${value}")
                                        }
                                    case _ => ()
                                }
                            case None => ()
                        }
                    }
                    if (parts.size == 0) {
                        return ""
                    }
                    return String.join(parts.toArray(), delimiter: "; ")
                case _ => return ""
            }
        } catch (_: Exception) {
            return ""
        }
    }

    private static func extractHostname(url: String): String {
        try {
            let m = Regex("^https?://([^/]+)").find(url, group: true)
            match (m) {
                case Some(md) => return md.matchString(1).trimAscii()
                case None => ()
            }
        } catch (_: Exception) {
            return ""
        }
        return ""
    }

    private static func domainMatches(cookieDomainRaw: String, targetHostRaw: String): Bool {
        var cookieDomain = cookieDomainRaw.trimAscii()
        var targetHost = targetHostRaw.trimAscii()

        if (cookieDomain.startsWith(".")) {
            let parts = cookieDomain.split(".", 2)
            if (parts.size == 2) {
                cookieDomain = parts[1]
            }
        }
        if (targetHost.startsWith("www.")) {
            let parts = targetHost.split("www.", 2)
            if (parts.size == 2) {
                targetHost = parts[1]
            }
        }

        if (cookieDomain.size == 0 || targetHost.size == 0) {
            return false
        }
        if (targetHost == cookieDomain) {
            return true
        }
        if (targetHost.endsWith(".${cookieDomain}")) {
            return true
        }
        if (cookieDomain.endsWith(".${targetHost}")) {
            return true
        }
        return false
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

