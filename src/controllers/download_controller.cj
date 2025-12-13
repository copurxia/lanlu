package lrr4cj.controllers

import std.regex.*
import std.fs.*
import std.process.*
import std.time.*
import std.convert.*
import std.collection.*
import stdx.encoding.json.*
import stdx.log.*
import cjoy.*
import lrr4cj.dao.*
import lrr4cj.services.*
import lrr4cj.utils.*

/**
 * 处理下载URL的控制器
 * 负责匹配下载插件、调用插件并拉取文件到归档目录
 */
public class DownloadController {

    /**
     * POST /api/download_url
     * 请求体: { "url": "https://example.com/file.zip" }
     */
    public static func downloadFromUrl(ctx: JoyContext): Unit {
        let logger = getLogger("download_controller")

        try {
            let requestBody = ctx.readString()
            var url = ""

            if (requestBody.size > 0) {
                try {
                    let bodyJson = JsonValue.fromStr(requestBody)
                    match (bodyJson) {
                        case obj: JsonObject =>
                            let fields = obj.getFields()
                            if (fields.contains("url")) {
                                let urlVal = fields["url"]
                                url = urlVal.toString().trimAscii()
                            }
                        case _ => ()
                    }
                } catch (e: Exception) {
                    logger.warn("解析下载请求JSON失败", ("error", e.message))
                }
            }

            if (url.size == 0) {
                url = ctx.getQuery("url") ?? ""
            }

            if (url.size == 0) {
                ctx.status(400)
                ctx.json("{\"success\":0,\"error\":\"url is required\"}")
                return
            }

            // 查找匹配的下载插件
            let pluginOpt = findMatchingDownloadPlugin(url)
            if (pluginOpt.isNone()) {
                ctx.status(400)
                ctx.json("{\"success\":0,\"error\":\"No download plugin matches provided url\"}")
                return
            }
            let plugin = pluginOpt.getOrThrow()
            logger.info("匹配到下载插件", ("namespace", plugin.namespace), ("url_regex", plugin.url_regex), ("login_from", plugin.login_from))

            // 确保插件文件复制到 data/plugins 下
            let pluginReady = ensureDownloadPluginReady(plugin)
            if (!pluginReady) {
                ctx.status(500)
                ctx.json("{\"success\":0,\"error\":\"Failed to prepare download plugin file\"}")
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
                    logger.error("所需登录插件不存在", ("namespace", plugin.login_from))
                    ctx.status(500)
                    ctx.json("{\"success\":0,\"error\":\"Login plugin ${plugin.login_from} not found\"}")
                    return
                }
                let loginReady = ensurePluginScriptReady(loginPlugin, "Login")
                if (!loginReady) {
                    ctx.status(500)
                    ctx.json("{\"success\":0,\"error\":\"Failed to prepare login plugin file\"}")
                    return
                }
            }

            // 调用插件生成下载链接
            let execResult = pluginService.executeDownloadPlugin(plugin, url)
            if (!execResult.success) {
                let err = execResult.error
                ctx.status(500)
                ctx.json("{\"success\":0,\"error\":\"Plugin execution failed: ${err}\"}")
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
            logger.info("下载插件输出", ("namespace", plugin.namespace), ("output", output))

            // 优先支持插件自行下载并回传 data.relative_path（相对于 ./data）
            let downloadedRelativePath = parseDownloadedRelativePath(output)
            let usePluginDownloadedFile = downloadedRelativePath.size > 0
            var downloadUrl = ""
            if (!usePluginDownloadedFile) {
                downloadUrl = parseDownloadUrl(output)
                if (downloadUrl.size == 0) {
                    logger.error("插件未返回 download_url 或 relative_path", ("namespace", plugin.namespace), ("output", output))
                    ctx.status(500)
                    ctx.json("{\"success\":0,\"error\":\"Plugin did not return download_url or relative_path\"}")
                    return
                }
            }

            // 生成目标文件名
            var fileName = ""
            var pluginTarget = Path("")
            var pluginRelativePath = ""

            if (usePluginDownloadedFile) {
                // 安全校验：必须是 ./data 下的 plugins/{namespace}/... 相对路径
                if (downloadedRelativePath.contains("..") || downloadedRelativePath.startsWith("/") ||
                    !downloadedRelativePath.startsWith("plugins/${plugin.namespace}/")) {
                    logger.error("插件返回的 relative_path 非法", ("namespace", plugin.namespace), ("relative_path", downloadedRelativePath))
                    ctx.status(500)
                    ctx.json("{\"success\":0,\"error\":\"Plugin returned invalid relative_path\"}")
                    return
                }

                pluginRelativePath = downloadedRelativePath
                pluginTarget = Path("./data/${downloadedRelativePath}")
                if (!exists(pluginTarget)) {
                    logger.error("插件返回的文件不存在", ("namespace", plugin.namespace), ("path", pluginTarget.toString()))
                    ctx.status(500)
                    ctx.json("{\"success\":0,\"error\":\"Plugin downloaded file not found\"}")
                    return
                }
                fileName = pluginTarget.fileName
            } else {
                fileName = deriveFileName(downloadUrl)
                if (fileName.size == 0) {
                    fileName = "download_${DateTime.now().toUnixTimeStamp().toSeconds().toString()}.bin"
                }

                // 下载到插件数据目录
                let pluginDataDir = "./data/plugins/${plugin.namespace}"
                pluginTarget = Path("${pluginDataDir}/${fileName}")
                FileUtils.ensureDirectoryExists(Path(pluginDataDir))

                let downloadOk = downloadToPath(downloadUrl, pluginTarget.toString(), loginCookiesJson)
                if (!downloadOk) {
                    ctx.status(500)
                    ctx.json("{\"success\":0,\"error\":\"Failed to download file from plugin url\"}")
                    return
                }
                pluginRelativePath = "plugins/${plugin.namespace}/${fileName}"
            }

            // 移动到归档目录
            let archiveDir = Path("./data/archive")
            FileUtils.ensureDirectoryExists(archiveDir)

            let finalArchivePath = Path("${archiveDir.toString()}/${fileName}")
            let finalArchivePathStr = finalArchivePath.toString()
            let relativePath = "archive/${fileName}"

            try {
                rename(pluginTarget, to: finalArchivePath)
            } catch (e: Exception) {
                logger.error("移动文件到archive失败", ("error", e.message))
                ctx.status(500)
                ctx.json("{\"success\":0,\"error\":\"Failed to move file to archive: ${e.message}\"}")
                return
            }

            // 交给Shinobu处理归档
            let shinobu = ShinobuService.getInstance()
            let processResult = shinobu.processUploadedArchiveFile(finalArchivePathStr)

            if (!processResult.success) {
                ctx.status(500)
                ctx.json("{\"success\":0,\"relative_path\":\"${relativePath}\",\"error\":\"${processResult.error}\"}")
                return
            }

            let response = "{\"success\":1,\"relative_path\":\"${relativePath}\",\"plugin_relative_path\":\"${pluginRelativePath}\",\"id\":\"${processResult.archiveId}\",\"filename\":\"${fileName}\"}"
            ctx.json(response)
        } catch (e: Exception) {
            getLogger("download_controller").error("下载处理异常", ("error", e.message))
            ctx.status(500)
            ctx.json("{\"success\":0,\"error\":\"${e.message}\"}")
        }
    }

    /**
     * 根据URL匹配可用的下载插件
     */
    private static func findMatchingDownloadPlugin(url: String): Option<PluginData> {
        let logger = getLogger("download_controller")
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

        // 如果只匹配到禁用的插件，尝试自动启用并返回
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

    /**
     * 确保下载插件被复制到 data/plugins/{namespace}/Download.ts
     */
    private static func ensureDownloadPluginReady(plugin: PluginData): Bool {
        return ensurePluginScriptReady(plugin, "Download")
    }

    /**
     * 通用helper，确保插件脚本文件存在
     */
    private static func ensurePluginScriptReady(plugin: PluginData, scriptName: String): Bool {
        try {
            let pluginsRoot = Path("./data/plugins")
            FileUtils.ensureDirectoryExists(pluginsRoot)

            let sharedBase = Path("${pluginsRoot.toString()}/base_plugin.ts")
            let sharedSource = Path("./plugins/base_plugin.ts")
            if (!exists(sharedSource)) {
                getLogger("download_controller").error("缺少共享基础插件文件", ("path", sharedSource.toString()))
                return false
            }
            // 始终覆盖，确保更新的基类生效
            copy(sharedSource, to: sharedBase, overwrite: true)

            let pluginDir = Path("${pluginsRoot.toString()}/${plugin.namespace}")
            FileUtils.ensureDirectoryExists(pluginDir)

            let targetFile = Path("${pluginDir.toString()}/${scriptName}.ts")
            let sourcePath = Path("./plugins/${plugin.plugin_type}/${plugin.entry}")
            if (!exists(sourcePath)) {
                getLogger("download_controller").error("源插件文件不存在", ("path", sourcePath.toString()))
                return false
            }

            // 始终覆盖，确保更新的插件脚本生效
            copy(sourcePath, to: targetFile, overwrite: true)
            return true
        } catch (e: Exception) {
            getLogger("download_controller").error("准备插件文件失败", ("error", e.message))
            return false
        }
    }

    /**
     * 解析插件输出中的下载链接
     */
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

    /**
     * 解析插件输出中的相对路径（相对于 ./data）
     */
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
                                                case rpStr: JsonString => return rpStr.getValue()
                                                case _ => return rpVal.toString()
                                            }
                                        }
                                        // 兼容 LANraragi 风格：data.file_path（可能是 ./data/... 或 data/...）
                                        if (dataFields.contains("file_path")) {
                                            let fpVal = dataFields["file_path"]
                                            let fpStr = match (fpVal) {
                                                case fpJson: JsonString => fpJson.getValue()
                                                case _ => fpVal.toString()
                                            }
                                            let trimmed = fpStr.trimAscii()
                                            if (trimmed.startsWith("./data/")) {
                                                return trimmed[7..trimmed.size]
                                            }
                                            if (trimmed.startsWith("data/")) {
                                                return trimmed[5..trimmed.size]
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

    /**
     * 从URL提取文件名
     */
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

    /**
     * 使用 curl 将文件下载到指定路径
     */
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
