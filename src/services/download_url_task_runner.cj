package lrr4cj.services

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
import dotenv.Dotenv

/**
 * download_url 任务执行器（运行在TaskPool中）
 */
public class DownloadUrlTaskRunner {
    // 配置 - 使用静态变量存储配置
    private static var archivePath: Path
    private static var cachePath: Path
    private static var thumbnailPath: Path
    private static var bsdtarPath: String

    // 静态初始化器
    static init() {
        let config = Dotenv.createConfig()

        // 读取配置
        let archivePathStr = config.read("ARCHIVE_PATH", "./data/archive")
        let cachePathStr = config.read("CACHE_PATH", "./data/cache")
        let thumbnailPathStr = config.read("THUMBNAIL_PATH", "./data/thumb")
        bsdtarPath = config.read("BSDTAR_PATH", "bsdtar")

        // 转换为 Path 类型并规范化
        archivePath = canonicalize(archivePathStr)
        cachePath = canonicalize(cachePathStr)
        thumbnailPath = canonicalize(thumbnailPathStr)

        // 确保必要的目录存在
        FileUtils.ensureDirectoryExists(archivePath)
        FileUtils.ensureDirectoryExists(cachePath)
        FileUtils.ensureDirectoryExists(thumbnailPath)
    }

    public static func run(taskId: Int64, parameters: String): Unit {
        let _ = getLogger("download_url_task")
        TaskIO.appendLog(taskId, "download_url task started")
        MinionModel.updateTaskProgress(taskId, 1, "下载任务开始")

        let url = parseUrl(parameters)
        if (url.size == 0) {
            fail(taskId, "url is required")
            return
        }

        try {
            TaskIO.appendLog(taskId, "url=${url}")
            MinionModel.updateTaskProgress(taskId, 5, "匹配下载插件")

            let pluginOpt = findMatchingDownloadPlugin(url)
            if (pluginOpt.isNone()) {
                fail(taskId, "No download plugin matches provided url")
                return
            }
            let plugin = pluginOpt.getOrThrow()
            MinionTaskDao.updateTaskPluginNamespace(taskId, plugin.namespace)
            TaskIO.appendLog(taskId, "matched plugin=${plugin.namespace}")

            MinionModel.updateTaskProgress(taskId, 10, "准备插件脚本")
            let pluginReady = ensurePluginScriptReady(plugin, "Download")
            if (!pluginReady) {
                fail(taskId, "Failed to prepare download plugin file")
                return
            }

            // 兼容旧记录：若数据库缺少 login_from，则从插件脚本 plugin_info 中解析并回填
            let pluginService = PluginService.getInstance()
            pluginService.hydrateDownloadPluginRuntimeInfo(plugin)
            let effectiveLoginFrom = plugin.login_from.trimAscii()
            if (effectiveLoginFrom.size > 0) {
                plugin.login_from = effectiveLoginFrom
                let loginPlugin = PluginDao.getPluginByNamespace(effectiveLoginFrom)
                if (loginPlugin.namespace.size == 0) {
                    fail(taskId, "Login plugin ${plugin.login_from} not found")
                    return
                }
                let loginReady = ensurePluginScriptReady(loginPlugin, "Login")
                if (!loginReady) {
                    fail(taskId, "Failed to prepare login plugin file")
                    return
                }
            }

            MinionModel.updateTaskProgress(taskId, 20, "执行下载插件")
            let execResult = pluginService.executeDownloadPlugin(plugin, url)
            if (!execResult.success) {
                fail(taskId, "Plugin execution failed: ${execResult.error}")
                return
            }

            let output = match (execResult.data.get("output")) {
                case Some(v) => v
                case None => ""
            }
            let loginCookiesJson = match (execResult.data.get("login_cookies")) {
                case Some(v) => v
                case None => ""
            }
            TaskIO.appendLog(taskId, "plugin output: ${output}")

            // 插件自行下载并回传 relative_path（相对于 ./data）
            let downloadedRelativePath = parseDownloadedRelativePath(output)
            let usePluginDownloadedFile = downloadedRelativePath.size > 0
            var downloadUrl = ""
            if (!usePluginDownloadedFile) {
                downloadUrl = parseDownloadUrl(output)
                if (downloadUrl.size == 0) {
                    fail(taskId, "Plugin did not return download_url or relative_path")
                    return
                }
            }

            MinionModel.updateTaskProgress(taskId, 35, "下载文件")

            var fileName = ""
            var pluginTarget = Path("")
            var pluginRelativePath = ""

            if (usePluginDownloadedFile) {
                if (downloadedRelativePath.contains("..") || downloadedRelativePath.startsWith("/") ||
                    !downloadedRelativePath.startsWith("plugins/${plugin.namespace}/")) {
                    fail(taskId, "Plugin returned invalid relative_path")
                    return
                }

                pluginRelativePath = downloadedRelativePath
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
                pluginRelativePath = "plugins/${plugin.namespace}/${fileName}"
            }

            MinionModel.updateTaskProgress(taskId, 60, "移动到archive")

            let archiveDir = Path("./data/archive")
            FileUtils.ensureDirectoryExists(archiveDir)

            let finalArchivePath = Path("${archiveDir.toString()}/${fileName}")
            let finalArchivePathStr = finalArchivePath.toString()
            let relativePath = "archive/${fileName}"

            try {
                rename(pluginTarget, to: finalArchivePath)
            } catch (e: Exception) {
                fail(taskId, "Failed to move file to archive: ${e.message}")
                return
            }

            MinionModel.updateTaskProgress(taskId, 80, "创建扫描任务")

            // 获取配置
            let archiveBasePath = archivePath.toString()
            let cachePathStr = cachePath.toString()
            let thumbnailPathStr = thumbnailPath.toString()

            // 创建 scan_archive 任务
            let params = "{\"archive_path\":\"${escapeJson(finalArchivePathStr)}\",\"archive_base_path\":\"${escapeJson(archiveBasePath)}\",\"cache_path\":\"${escapeJson(cachePathStr)}\",\"thumbnail_path\":\"${escapeJson(thumbnailPathStr)}\",\"bsdtar_path\":\"${escapeJson(bsdtarPath)}\"}"
            let task = MinionModel.createTaskWithOptions("扫描档案", "scan_archive", params, 50, "download_url:${taskId}", "upload")
            if (task.id <= 0) {
                let errorJson = "{\"success\":0,\"relative_path\":\"${relativePath}\",\"error\":\"Failed to create scan_archive task\"}"
                MinionModel.failTask(taskId, "Failed to create scan_archive task")
                TaskIO.writeOutput(taskId, errorJson)
                return
            }

            let resultJson = "{\"success\":1,\"relative_path\":\"${relativePath}\",\"plugin_relative_path\":\"${pluginRelativePath}\",\"task_id\":\"${task.id}\",\"filename\":\"${escapeJson(fileName)}\"}"

            MinionModel.updateTaskProgress(taskId, 100, "下载完成")
            MinionModel.completeTask(taskId, "download_url completed")
            TaskIO.writeOutput(taskId, resultJson)
            TaskIO.appendLog(taskId, "download_url task completed: scan_task_id=${task.id}")
        } catch (e: Exception) {
            fail(taskId, e.message)
        }
    }

    private static func fail(taskId: Int64, message: String): Unit {
        let msg = if (message.size == 0) { "Unknown error" } else { message }
        TaskIO.appendLog(taskId, "FAILED: ${msg}")
        MinionModel.failTask(taskId, msg)
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

    private static func ensurePluginScriptReady(plugin: PluginData, scriptName: String): Bool {
        try {
            let pluginsRoot = Path("./data/plugins")
            FileUtils.ensureDirectoryExists(pluginsRoot)

            let sharedBase = Path("${pluginsRoot.toString()}/base_plugin.ts")
            let sharedSource = Path("./plugins/base_plugin.ts")
            if (!exists(sharedSource)) {
                getLogger("download_url_task").error("缺少共享基础插件文件", ("path", sharedSource.toString()))
                return false
            }
            copy(sharedSource, to: sharedBase, overwrite: true)

            let pluginDir = Path("${pluginsRoot.toString()}/${plugin.namespace}")
            FileUtils.ensureDirectoryExists(pluginDir)

            let targetFile = Path("${pluginDir.toString()}/${scriptName}.ts")
            let sourcePath = Path("./plugins/${plugin.plugin_type}/${plugin.entry}")
            if (!exists(sourcePath)) {
                getLogger("download_url_task").error("源插件文件不存在", ("path", sourcePath.toString()))
                return false
            }

            copy(sourcePath, to: targetFile, overwrite: true)
            return true
        } catch (e: Exception) {
            getLogger("download_url_task").error("准备插件文件失败", ("error", e.message))
            return false
        }
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

    private static func parseDownloadedRelativePath(output: String): String {
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
                                        if (dataFields.contains("relative_path")) {
                                            let rpVal = dataFields["relative_path"]
                                            match (rpVal) {
                                                case rpStr: JsonString => return rpStr.getValue().trimAscii()
                                                case _ => return rpVal.toString().trimAscii()
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
}

