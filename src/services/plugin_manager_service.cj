package lrr4cj.services

import std.collection.*
import std.convert.*
import std.fs.*
import std.io.*
import std.process.*
import std.time.*
import stdx.encoding.json.*
import stdx.log.*
import linderHttp.*
import linderHttp.commons.*
import semver.*
import lrr4cj.dao.*
import lrr4cj.models.*
import lrr4cj.utils.*

public class PluginInstallResult {
    public var success: Bool = false
    public var message: String = ""
    public var namespace: String = ""
    public var plugin_type: String = ""
    public var filename: String = ""
    public var old_version: String = ""
    public var new_version: String = ""
    public var clear_parameters: Bool = false
    public var reason: String = ""
    public var scan_task_id: Int64 = 0

    public init() {}
}

class ParsedPluginInfo {
    public var pluginType: String = ""
    public var updateUrl: String = ""
    public var namespace: String = ""
    public var name: String = ""
    public var version: String = ""
    public var description: String = ""
    public var author: String = ""
    public var tags: String = ""
    public var permissions: String = ""
    public var url_regex: String = ""
    public var login_from: String = ""
    public var icon: String = ""
    public var parameters: String = "[]"
    public var has_schema: Bool = false
}

class UpsertOutcome {
    public var error: String = ""
    public var oldVersion: String = ""
    public var newVersion: String = ""
    public var clearParameters: Bool = false
    public var reason: String = ""
}

/**
 * 插件管理服务：统一安装/更新/落盘/写库/触发扫描
 */
public class PluginManagerService {
    private static let logger = getLogger("plugin_manager")

    public static func getPluginStorageRoot(): String { PluginPaths.getPluginStorageRoot() }
    public static func getCacheRoot(): String { PluginPaths.getCacheRoot() }
    public static func getPluginRuntimeRoot(): String { PluginPaths.getPluginRuntimeRoot() }
    public static func getPluginTempRoot(): String { PluginPaths.getPluginTempRoot() }
    public static func getPluginInfoTempRoot(): String { PluginPaths.getPluginInfoTempRoot() }
    public static func ensurePluginDirs(): Unit { PluginPaths.ensurePluginDirs() }
    public static func buildPluginFilePath(pluginType: String, entry: String): String { PluginPaths.buildPluginFilePath(pluginType, entry) }

    public static func installFromUrl(url: String): PluginInstallResult {
        ensurePluginDirs()
        var result = PluginInstallResult()

        let trimmedUrl = url.trimAscii()
        if (trimmedUrl.size == 0) {
            result.message = "URL is required"
            return result
        }
        if (!trimmedUrl.endsWith(".ts")) {
            result.message = "URL must point to a .ts file"
            return result
        }

        // 文件名
        let urlParts = trimmedUrl.split("/")
        let filename = urlParts[urlParts.size - 1]
        result.filename = filename

        // 下载到临时文件
        let tempDir = Path(getPluginTempRoot())
        FileUtils.ensureDirectoryExists(tempDir)
        let tempFile = Path("${tempDir.toString()}/${DateTime.now().toUnixTimeStamp().toSeconds().toString()}_${filename}")

        try {
            var http = LinderHttp(url: RequestUrl.from(trimmedUrl))
            let response = http.send()
            if (response.status != 200) {
                result.message = "Failed to download plugin: HTTP ${response.status.toString()}"
                return result
            }

            let content = response.getBodyString()
            let file = File(tempFile, OpenMode.Write)
            file.write(content.toArray())
            file.close()
        } catch (e: Exception) {
            result.message = "Failed to download plugin: ${e.message}"
            return result
        }

        // 解析 plugin_info
        let info = parsePluginInfoFromFile(tempFile.toString(), trimmedUrl, "Temp")
        if (info.pluginType.size == 0 || info.namespace.size == 0) {
            try { remove(tempFile) } catch (_: Exception) {}
            result.message = "Failed to get plugin info"
            return result
        }

        // 写入到存储目录
        result.plugin_type = info.pluginType
        result.namespace = info.namespace
        // 所有插件统一存放在 PLUGIN_PATH 根目录，不再按类型分子目录
        let targetFile = Path("${getPluginStorageRoot()}/${filename}")

        let writeOk = atomicReplaceFile(targetFile, tempFile)
        if (!writeOk) {
            result.message = "Failed to write plugin file"
            return result
        }

        let upsert = upsertPluginInDatabase(info, filename)
        if (upsert.error.size > 0) {
            // 回滚：删除落盘的文件
            try { remove(targetFile) } catch (_: Exception) {}
            result.message = upsert.error
            return result
        }

        // 触发扫描任务（统一入口）
        let scanTask = enqueueScanPluginsTask("plugin_install")
        result.scan_task_id = scanTask

        result.success = true
        result.message = "Plugin installed successfully."
        result.old_version = upsert.oldVersion
        result.new_version = upsert.newVersion
        result.clear_parameters = upsert.clearParameters
        result.reason = upsert.reason
        return result
    }

    public static func updateFromDatabase(namespace: String): PluginInstallResult {
        ensurePluginDirs()
        var result = PluginInstallResult()

        let ns = namespace.trimAscii()
        if (ns.size == 0) {
            result.message = "Plugin namespace is required"
            return result
        }

        let existing = PluginDao.getPluginByNamespace(ns)
        if (existing.namespace.size == 0) {
            result.message = "Plugin not found"
            return result
        }

        let updateUrl = existing.update_url.trimAscii()
        if (updateUrl.size == 0) {
            result.message = "Plugin does not have an update URL"
            return result
        }

        result.namespace = existing.namespace
        result.plugin_type = existing.plugin_type
        result.filename = existing.entry

        // 下载到临时文件
        let tempDir = Path(getPluginTempRoot())
        FileUtils.ensureDirectoryExists(tempDir)
        let tempFile = Path("${tempDir.toString()}/${DateTime.now().toUnixTimeStamp().toSeconds().toString()}_${existing.entry}")

        try {
            var http = LinderHttp(url: RequestUrl.from(updateUrl))
            let response = http.send()
            if (response.status != 200) {
                result.message = "Failed to download plugin: HTTP ${response.status.toString()}"
                return result
            }

            let content = response.getBodyString()
            let file = File(tempFile, OpenMode.Write)
            file.write(content.toArray())
            file.close()
        } catch (e: Exception) {
            result.message = "Failed to download plugin: ${e.message}"
            return result
        }

        // 解析 plugin_info
        let info = parsePluginInfoFromFile(tempFile.toString(), updateUrl, "Temp")
        if (info.namespace.size == 0 || info.pluginType.size == 0) {
            try { remove(tempFile) } catch (_: Exception) {}
            result.message = "Failed to get plugin info from updated file"
            return result
        }
        if (info.namespace != existing.namespace) {
            try { remove(tempFile) } catch (_: Exception) {}
            result.message = "Plugin namespace mismatch after update"
            return result
        }
        if (info.pluginType != existing.plugin_type) {
            try { remove(tempFile) } catch (_: Exception) {}
            result.message = "Plugin type mismatch after update"
            return result
        }

        let targetPath = Path(buildPluginFilePath(existing.plugin_type, existing.entry))

        // 备份旧文件，以便失败回滚
        var backupPath = Path("")
        if (exists(targetPath)) {
            backupPath = Path("${getPluginTempRoot()}/backup_${DateTime.now().toUnixTimeStamp().toSeconds().toString()}_${existing.entry}")
            try {
                copy(targetPath, to: backupPath, overwrite: true)
            } catch (_: Exception) {}
        }

        let writeOk = atomicReplaceFile(targetPath, tempFile)
        if (!writeOk) {
            result.message = "Failed to write plugin file"
            return result
        }

        let upsert = upsertPluginInDatabase(info, existing.entry)
        if (upsert.error.size > 0) {
            // 回滚：恢复旧文件
            if (backupPath.toString().trimAscii().size > 0 && exists(backupPath)) {
                try {
                    if (exists(targetPath)) {
                        try { remove(targetPath) } catch (_: Exception) {}
                    }
                    rename(backupPath, to: targetPath)
                } catch (_: Exception) {}
            }
            result.message = upsert.error
            return result
        }

        // 成功后清理备份
        if (backupPath.toString().trimAscii().size > 0) {
            try { remove(backupPath) } catch (_: Exception) {}
        }

        let scanTask = enqueueScanPluginsTask("plugin_update")
        result.scan_task_id = scanTask

        result.success = true
        result.message = "Plugin updated successfully."
        result.old_version = upsert.oldVersion
        result.new_version = upsert.newVersion
        result.clear_parameters = upsert.clearParameters
        result.reason = upsert.reason
        return result
    }

    public static func deletePlugin(namespace: String): String {
        ensurePluginDirs()
        let ns = namespace.trimAscii()
        if (ns.size == 0) {
            return "Plugin namespace is required"
        }

        let plugin = PluginDao.getPluginByNamespace(ns)
        if (plugin.namespace.size == 0) {
            return "Plugin not found"
        }

        let filePath = Path(buildPluginFilePath(plugin.plugin_type, plugin.entry))
        try {
            if (exists(filePath)) {
                remove(filePath)
            }
        } catch (e: Exception) {
            return "Failed to delete plugin file: ${e.message}"
        }

        // 删除运行时缓存目录（可选）
        let runtimeDir = Path(FileUtils.joinPath(getPluginRuntimeRoot(), plugin.namespace))
        try {
            if (exists(runtimeDir)) {
                remove(runtimeDir, recursive: true)
            }
        } catch (_: Exception) {}

        if (!PluginDao.delete(ns)) {
            return "Failed to delete plugin from database"
        }
        return ""
    }

    private static func enqueueScanPluginsTask(source: String): Int64 {
        let t = TaskModel.createTaskWithOptions("插件扫描", "scan_plugins", "", 50, "", source)
        t.id
    }

    private static func atomicReplaceFile(target: Path, tempFile: Path): Bool {
        try {
            // 尽量使用 rename 完成替换；若目标存在则先删除
            if (exists(target)) {
                try { remove(target) } catch (_: Exception) {}
            }
            rename(tempFile, to: target)
            return true
        } catch (e: Exception) {
            logger.error("atomicReplaceFile failed", ("target", target.toString()), ("error", e.message))
            try { remove(tempFile) } catch (_: Exception) {}
            return false
        }
    }

    private static func parsePluginInfoFromFile(filePath: String, sourceUrl: String, typeDir: String): ParsedPluginInfo {
        var result = ParsedPluginInfo()

        try {
            let tempRoot = Path("${getPluginInfoTempRoot()}/${DateTime.now().toUnixTimeStamp().toSeconds().toString()}")
            let pluginsRoot = Path("${tempRoot.toString()}/plugins")
            let tempTypeDir = Path("${pluginsRoot.toString()}/${typeDir}")
            Directory.create(tempTypeDir, recursive: true)

            let baseSource = Path("./plugins/base_plugin.ts")
            let baseTarget = Path("${pluginsRoot.toString()}/base_plugin.ts")
            if (exists(baseSource)) {
                copy(baseSource, to: baseTarget, overwrite: true)
            }

            let fileName = Path(filePath).fileName.toString()
            let tempPluginFile = Path("${tempTypeDir.toString()}/${fileName}")
            copy(Path(filePath), to: tempPluginFile, overwrite: true)

            let inputJson = "{\"action\":\"plugin_info\",\"pluginType\":\"\"}"
            let cmd = "echo '${inputJson}' | deno run --allow-read '${tempPluginFile.toString()}'"
            let process = launch("sh", "-c", cmd,
                stdIn: ProcessRedirect.Pipe,
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe)

            let reader = StringReader<InputStream>(process.stdOutPipe)
            var output = ""
            for (line in reader.lines()) {
                output += line
            }

            let _ = process.wait()

            result = parsePluginInfoOutput(output, sourceUrl)

            try {
                remove(tempRoot, recursive: true)
            } catch (_: Exception) {}
        } catch (_: Exception) {}

        return result
    }

    private static func parsePluginInfoOutput(output: String, sourceUrl: String): ParsedPluginInfo {
        var result = ParsedPluginInfo()

        try {
            let jsonVal = JsonValue.fromStr(output.trimAscii())
            match (jsonVal) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    if (!getJsonBoolValue(fields, "success")) {
                        return result
                    }
                    match (fields.get("data")) {
                        case Some(dataVal) =>
                            match (dataVal) {
                                case dataObj: JsonObject =>
                                    let dataFields = dataObj.getFields()
                                    let pluginType = getJsonStrValue(dataFields, "type")
                                    result.pluginType = capitalizeFirst(pluginType)
                                    result.updateUrl = getJsonStrValue(dataFields, "update_url")
                                    if (result.updateUrl.size == 0) {
                                        result.updateUrl = sourceUrl
                                    }
                                    result.namespace = getJsonStrValue(dataFields, "namespace")
                                    result.name = getJsonStrValue(dataFields, "name")
                                    result.version = getJsonStrValue(dataFields, "version")
                                    result.description = getJsonStrValue(dataFields, "description")
                                    result.author = getJsonStrValue(dataFields, "author")
                                    result.tags = getJsonStrValue(dataFields, "tags")
                                    result.permissions = getJsonCommaSeparatedValue(dataFields, "permissions")
                                    result.url_regex = getJsonStrValue(dataFields, "url_regex")
                                    result.login_from = getJsonStrValue(dataFields, "login_from")
                                    result.icon = getJsonStrValue(dataFields, "icon")

                                    let (paramsJson, hasSchema) = getJsonArrayStringValue(dataFields, "parameters")
                                    result.parameters = paramsJson
                                    result.has_schema = hasSchema
                                case _ => ()
                            }
                        case None => ()
                    }
                case _ => ()
            }
        } catch (_: Exception) {}

        return result
    }

    private static func getJsonStrValue(fields: HashMap<String, JsonValue>, key: String): String {
        match (fields.get(key)) {
            case Some(v) =>
                match (v) {
                    case s: JsonString => return s.getValue()
                    case _ => return ""
                }
            case None => return ""
        }
    }

    private static func getJsonBoolValue(fields: HashMap<String, JsonValue>, key: String): Bool {
        match (fields.get(key)) {
            case Some(v) =>
                match (v) {
                    case b: JsonBool => return b.getValue()
                    case _ => return false
                }
            case None => return false
        }
    }

    private static func getJsonCommaSeparatedValue(fields: HashMap<String, JsonValue>, key: String): String {
        match (fields.get(key)) {
            case Some(v) =>
                match (v) {
                    case arr: JsonArray =>
                        var out = ""
                        var first = true
                        let size = arr.size()
                        for (i in 0..size) {
                            match (arr.get(i)) {
                                case Some(item) =>
                                    let s = match (item) {
                                        case js: JsonString => js.getValue()
                                        case _ => item.toString()
                                    }.trimAscii()
                                    if (s.size == 0) { continue }
                                    if (!first) { out += "," }
                                    out += s
                                    first = false
                                case None => ()
                            }
                        }
                        return out
                    case s: JsonString =>
                        return s.getValue()
                    case _ =>
                        return v.toString()
                }
            case None => return ""
        }
    }

    private static func getJsonArrayStringValue(fields: HashMap<String, JsonValue>, key: String): (String, Bool) {
        match (fields.get(key)) {
            case Some(v) =>
                match (v) {
                    case arr: JsonArray =>
                        return (arr.toString(), arr.size() > 0)
                    case _ =>
                        return ("[]", false)
                }
            case None => return ("[]", false)
        }
    }

    private static func capitalizeFirst(s: String): String {
        if (s.size == 0) { return s }
        let lower = s.toAsciiLower()
        match (lower) {
            case "metadata" => return "Metadata"
            case "login" => return "Login"
            case "download" => return "Download"
            case _ => return s
        }
    }

    private static func upsertPluginInDatabase(info: ParsedPluginInfo, fileName: String): UpsertOutcome {
        var out = UpsertOutcome()
        if (info.namespace.trimAscii().size == 0) {
            out.error = "Plugin namespace is required"
            return out
        }
        if (info.pluginType.trimAscii().size == 0) {
            out.error = "Plugin type is required"
            return out
        }

        var pluginData = PluginData()
        pluginData.name = if (info.name.trimAscii().size > 0) { info.name } else { fileName }
        pluginData.namespace = info.namespace
        pluginData.version = if (info.version.trimAscii().size > 0) { info.version } else { "1.0" }
        pluginData.description = info.description
        pluginData.author = info.author
        // 下载的插件文件直接放在根目录，所以 entry 就是文件名
        pluginData.entry = fileName
        pluginData.plugin_type = info.pluginType
        pluginData.tags = info.tags
        pluginData.permissions = info.permissions
        pluginData.url_regex = info.url_regex
        pluginData.login_from = info.login_from
        pluginData.icon = info.icon
        pluginData.update_url = info.updateUrl
        pluginData.installed = true
        pluginData.has_schema = info.has_schema

        if (PluginDao.exists(info.namespace)) {
            let existing = PluginDao.getPluginByNamespace(info.namespace)
            out.oldVersion = existing.version
            out.newVersion = pluginData.version

            let compareResult = compare(existing.version, pluginData.version)
            pluginData.enabled = existing.enabled

            match (compareResult) {
                case MajorUpgrade =>
                    pluginData.parameters = info.parameters
                    out.clearParameters = true
                    out.reason = "major_upgrade"
                case MinorUpgrade | PatchUpgrade =>
                    pluginData.parameters = existing.parameters
                    out.reason = "upgrade_preserve_parameters"
                case Equal =>
                    pluginData.parameters = existing.parameters
                    out.reason = "version_unchanged"
                case Downgrade =>
                    pluginData.parameters = existing.parameters
                    out.reason = "downgrade"
                case Invalid =>
                    pluginData.parameters = existing.parameters
                    out.reason = "invalid_version"
            }

            if (!PluginDao.update(pluginData)) {
                out.error = "Failed to update plugin in database"
            }
            return out
        }

        out.oldVersion = ""
        out.newVersion = pluginData.version
        out.reason = "new_install"
        pluginData.enabled = true
        pluginData.parameters = info.parameters

        if (!PluginDao.create(pluginData)) {
            out.error = "Failed to create plugin in database"
        }
        return out
    }
}
