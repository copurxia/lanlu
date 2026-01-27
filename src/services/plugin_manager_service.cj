package lanlu.services

import std.convert.*
import std.fs.*
import std.io.*
import std.process.*
import std.time.*
import std.collection.*
import stdx.log.*
import stdx.encoding.json.stream.*
import semver.*
import lanlu.dao.*
import lanlu.models.*
import lanlu.utils.*

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

public class PluginCheckUpdateResult {
    public var success: Bool = false
    public var message: String = ""
    public var namespace: String = ""
    public var update_url: String = ""
    public var old_version: String = ""
    public var new_version: String = ""
    public var has_update: Bool = false
    public var clear_parameters: Bool = false
    public var reason: String = ""
    public var old_etag: String = ""
    public var new_etag: String = ""

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

    /**
     * 下载 URL 到指定文件。
     * 统一使用 deno+fetch（避免容器/发行版环境下 HTTP 客户端行为不一致导致的 HTTP 0）。
     */
    private static func downloadUrlToFile(url: String, outFile: Path, ifNoneMatch!: String = ""): (Bool, String, String, Bool) {
        let (ok, err, etag, notModified) = downloadUrlToFileWithDeno(url, outFile, ifNoneMatch)
        if (ok) { return (true, "", etag, notModified) }
        return (false, "Failed to download plugin: ${err}", etag, notModified)
    }

    private static func truncateForLog(s: String, maxLen: Int64): String {
        let trimmed = s.trimAscii()
        if (maxLen <= 0 || trimmed.size == 0) { return "" }
        if (trimmed.size <= maxLen) { return trimmed }
        return trimmed[0..maxLen] + "...(truncated,len=${trimmed.size.toString()})"
    }

    private static func downloadUrlToFileWithDeno(url: String, outFile: Path, ifNoneMatch: String): (Bool, String, String, Bool) {
        // 使用仓库内置脚本，避免运行时创建临时脚本文件。
        let scriptPath = Path("./plugins/deno_fetch.ts")
        if (!exists(scriptPath)) {
            return (false, "missing ./plugins/deno_fetch.ts", "", false)
        }

        let tempDir = Path(getPluginTempRoot())
        FileUtils.ensureDirectoryExists(tempDir)

        try {
            var args = ArrayList<String>()
            args.add("run")
            args.add("--allow-net")
            args.add("--allow-write=${tempDir.toString()}")
            args.add(scriptPath.toString())
            args.add(url)
            args.add(outFile.toString())
            let etagTrimmed = ifNoneMatch.trimAscii()
            if (etagTrimmed.size > 0) {
                args.add(etagTrimmed)
            }

            let process = launch("deno", args.toArray(),
                stdIn: ProcessRedirect.Pipe,
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe)

            let (exitCode, stdoutBytes, stderrBytes) = process.waitOutput()

            let stderrStr = if (stderrBytes.size > 0) { String.fromUtf8(stderrBytes).trimAscii() } else { "" }
            let stdoutStr = if (stdoutBytes.size > 0) { String.fromUtf8(stdoutBytes).trimAscii() } else { "" }

            // Parse stdout JSON: { not_modified: bool, etag: string }
            var notModified = false
            var etag = ""
            if (stdoutStr.trimAscii().size > 0) {
                try {
                    var buf = ByteBuffer()
                    unsafe { buf.write(stdoutStr.trimAscii().rawData()) }
                    let r = JsonReader(buf)
                    func readBoolFlexible(): Bool {
                        let v = r.readValue<String>().trimAscii().toAsciiLower()
                        return v == "true" || v == "1"
                    }
                    if (r.peek() == Some(BeginObject)) {
                        r.startObject()
                        while (r.peek() != EndObject) {
                            let k = r.readName()
                            match (k) {
                                case "not_modified" => notModified = readBoolFlexible()
                                case "etag" => etag = r.readValue<String>().trimAscii()
                                case _ => r.skip()
                            }
                        }
                        r.endObject()
                    }
                } catch (_: Exception) {}
            }

            if (exitCode == 0 && exists(outFile)) {
                return (true, "", etag, false)
            }
            if (exitCode == 0 && notModified) {
                return (true, "", etag, true)
            }
            // deno_fetch.ts 会把可诊断信息写到 stderr
            if (stderrStr.size > 0) {
                logger.error("deno fetch failed", ("url", url), ("stderr", truncateForLog(stderrStr, 1024)))
                return (false, stderrStr, etag, false)
            }
            if (stdoutStr.size > 0) {
                logger.error("deno fetch failed (stdout)", ("url", url), ("stdout", truncateForLog(stdoutStr, 1024)))
                return (false, stdoutStr, etag, false)
            }
            return (false, "deno fetch failed (exitCode=${exitCode.toString()})", etag, false)
        } catch (e: Exception) {
            return (false, e.message, "", false)
        }
    }

    private static func sanitizeEntryName(s: String): String {
        // Avoid directory traversal and keep storage entry stable.
        var out = s.trimAscii()
        out = out.replace("/", "_").replace("\\", "_").replace("..", "_")
        return out
    }

    private static func getEtagSidecarPathForEntry(entry: String): Path {
        let filePath = Path(buildPluginFilePath("", entry))
        return Path(filePath.toString() + ".etag")
    }

    private static func readStoredEtag(entry: String): String {
        let p = getEtagSidecarPathForEntry(entry)
        try {
            if (!exists(p)) { return "" }
            let f = File(p, Read)
            let r = StringReader<InputStream>(f)
            let raw = r.readToEnd()
            f.close()
            return raw.trimAscii()
        } catch (_: Exception) {
            return ""
        }
    }

    private static func writeStoredEtag(entry: String, etag: String): Unit {
        let trimmed = etag.trimAscii()
        let p = getEtagSidecarPathForEntry(entry)
        try {
            if (trimmed.size == 0) {
                if (exists(p)) { try { remove(p) } catch (_: Exception) {} }
                return
            }
            FileUtils.ensureDirectoryExists(p.parent)
            let f = File(p, Write)
            f.write(trimmed.toArray())
            f.flush()
            f.close()
        } catch (_: Exception) {}
    }

    private static func deleteStoredEtag(entry: String): Unit {
        let p = getEtagSidecarPathForEntry(entry)
        try { if (exists(p)) { remove(p) } } catch (_: Exception) {}
    }

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

        let (downloadOk, downloadErr, newEtag, _) = downloadUrlToFile(trimmedUrl, tempFile, ifNoneMatch: "")
        if (!downloadOk) {
            result.message = downloadErr
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
        // Use namespace as the stable entry name to avoid collisions between different URLs sharing the same filename.
        let storedEntry = sanitizeEntryName("${info.namespace}.ts")
        result.filename = storedEntry

        let targetFile = Path(buildPluginFilePath(info.pluginType, storedEntry))

        // Backup existing file to avoid destructive rollback if upsert fails.
        var backupPath = Path("")
        if (exists(targetFile)) {
            backupPath = Path("${getPluginTempRoot()}/backup_install_${DateTime.now().toUnixTimeStamp().toSeconds().toString()}_${storedEntry}")
            try { copy(targetFile, to: backupPath, overwrite: true) } catch (_: Exception) {}
        }

        let writeOk = atomicReplaceFile(targetFile, tempFile)
        if (!writeOk) {
            result.message = "Failed to write plugin file"
            return result
        }

        let upsert = upsertPluginInDatabase(info, storedEntry)
        if (upsert.error.size > 0) {
            // Rollback: restore backup if present; otherwise remove the newly written file.
            if (backupPath.toString().trimAscii().size > 0 && exists(backupPath)) {
                try {
                    if (exists(targetFile)) { try { remove(targetFile) } catch (_: Exception) {} }
                    rename(backupPath, to: targetFile)
                } catch (_: Exception) {}
            } else {
                try { remove(targetFile) } catch (_: Exception) {}
            }
            result.message = upsert.error
            return result
        }

        // Best-effort: persist ETag for conditional checks/updates (if present).
        if (newEtag.trimAscii().size > 0) {
            writeStoredEtag(storedEntry, newEtag)
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

    public static func updateFromDatabase(namespace: String, force!: Bool = false): PluginInstallResult {
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

        // 下载到临时文件（支持 ETag 条件请求；force 时跳过条件）
        let tempDir = Path(getPluginTempRoot())
        FileUtils.ensureDirectoryExists(tempDir)
        let tempFile = Path("${tempDir.toString()}/${DateTime.now().toUnixTimeStamp().toSeconds().toString()}_${existing.entry}")

        let storedEtag = if (!force) { readStoredEtag(existing.entry) } else { "" }
        let (downloadOk, downloadErr, newEtag, notModified) = downloadUrlToFile(updateUrl, tempFile, ifNoneMatch: storedEtag)
        if (!downloadOk) {
            result.message = downloadErr
            return result
        }
        if (!force && notModified) {
            result.success = true
            result.message = "Plugin already up to date (etag not modified)."
            result.namespace = existing.namespace
            result.plugin_type = existing.plugin_type
            result.filename = existing.entry
            result.old_version = existing.version
            result.new_version = existing.version
            result.clear_parameters = false
            result.reason = "etag_not_modified"
            // Update stored etag if server provided a fresh value.
            if (newEtag.trimAscii().size > 0) {
                writeStoredEtag(existing.entry, newEtag)
            }
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

        // Guard against downgrade/invalid unless force is explicitly requested.
        let compareResult = compare(existing.version, info.version)
        if (!force) {
            match (compareResult) {
                case Downgrade =>
                    try { remove(tempFile) } catch (_: Exception) {}
                    result.message = "Refusing plugin downgrade without force"
                    return result
                case Invalid =>
                    try { remove(tempFile) } catch (_: Exception) {}
                    result.message = "Refusing plugin update with invalid version without force"
                    return result
                case _ => ()
            }
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

        // Persist ETag for future conditional checks/updates (best-effort).
        if (newEtag.trimAscii().size > 0) {
            writeStoredEtag(existing.entry, newEtag)
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

    public static func checkUpdateFromDatabase(namespace: String, force!: Bool = false): PluginCheckUpdateResult {
        ensurePluginDirs()
        var out = PluginCheckUpdateResult()

        let ns = namespace.trimAscii()
        if (ns.size == 0) {
            out.message = "Plugin namespace is required"
            return out
        }

        let existing = PluginDao.getPluginByNamespace(ns)
        if (existing.namespace.size == 0) {
            out.message = "Plugin not found"
            return out
        }

        let updateUrl = existing.update_url.trimAscii()
        if (updateUrl.size == 0) {
            out.message = "Plugin does not have an update URL"
            return out
        }

        out.namespace = existing.namespace
        out.update_url = updateUrl
        out.old_version = existing.version
        out.old_etag = readStoredEtag(existing.entry)

        // If we have an ETag and not forcing, try conditional download first.
        let tempDir = Path(getPluginTempRoot())
        FileUtils.ensureDirectoryExists(tempDir)
        let tempFile = Path("${tempDir.toString()}/check_${DateTime.now().toUnixTimeStamp().toSeconds().toString()}_${existing.entry}")

        let ifNoneMatch = if (!force) { out.old_etag } else { "" }
        let (downloadOk, downloadErr, newEtag, notModified) = downloadUrlToFile(updateUrl, tempFile, ifNoneMatch: ifNoneMatch)
        if (!downloadOk) {
            out.message = downloadErr
            return out
        }

        out.new_etag = newEtag

        if (!force && notModified) {
            out.success = true
            out.has_update = false
            out.new_version = existing.version
            out.clear_parameters = false
            out.reason = "etag_not_modified"
            out.message = "No update (etag not modified)."
            if (newEtag.trimAscii().size > 0) {
                writeStoredEtag(existing.entry, newEtag)
            }
            return out
        }

        // Parse plugin_info from downloaded file to compute semver/clear_parameters.
        let info = parsePluginInfoFromFile(tempFile.toString(), updateUrl, "Temp")
        try { remove(tempFile) } catch (_: Exception) {}

        if (info.namespace.size == 0 || info.pluginType.size == 0) {
            out.message = "Failed to get plugin info from updated file"
            return out
        }
        if (info.namespace != existing.namespace) {
            out.message = "Plugin namespace mismatch after update"
            return out
        }
        if (info.pluginType != existing.plugin_type) {
            out.message = "Plugin type mismatch after update"
            return out
        }

        out.new_version = info.version

        let compareResult = compare(existing.version, info.version)
        match (compareResult) {
            case MajorUpgrade =>
                out.has_update = true
                out.clear_parameters = true
                out.reason = "major_upgrade"
            case MinorUpgrade | PatchUpgrade =>
                out.has_update = true
                out.clear_parameters = false
                out.reason = "upgrade_preserve_parameters"
            case Equal =>
                // Treat as update if ETag changed (content changed without version bump).
                let oldE = out.old_etag.trimAscii()
                let newE = out.new_etag.trimAscii()
                if (!force && oldE.size > 0 && newE.size > 0 && oldE != newE) {
                    out.has_update = true
                    out.clear_parameters = false
                    out.reason = "etag_changed_version_unchanged"
                } else {
                    out.has_update = false
                    out.clear_parameters = false
                    out.reason = "version_unchanged"
                }
            case Downgrade =>
                out.has_update = false
                out.clear_parameters = false
                out.reason = "downgrade"
            case Invalid =>
                out.has_update = false
                out.clear_parameters = false
                out.reason = "invalid_version"
        }

        out.success = true
        out.message = if (out.has_update) { "Update available." } else { "No update available." }
        return out
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

        // Remove stored etag sidecar (best-effort).
        deleteStoredEtag(plugin.entry)

        // 删除运行时缓存目录（可选）
        let runtimeDir = Path(FileUtils.joinPath(getPluginRuntimeRoot(), plugin.namespace))
        try {
            if (exists(runtimeDir)) {
                remove(runtimeDir, recursive: true)
            }
        } catch (_: Exception) {}

        // Delete cron task for script plugins (best-effort).
        if (plugin.plugin_type == "Script") {
            let cronName = "plugin_script:${plugin.namespace}"
            try { let _ = ScheduledTaskModel.deleteByName(cronName) } catch (_: Exception) {}
        }

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
            // Delegate to FileUtils to keep file replacement semantics consistent across the codebase.
            FileUtils.safeReplaceFile(target, tempFile)
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
            let fileName = Path(filePath).fileName.toString()
            let safeFileName = fileName.replace(".", "_")
            let uniqueId = "plugin_manager_${typeDir}_${safeFileName}_${DateTime.now().toUnixTimeStamp().toSeconds().toString()}"

            let (exitCode, stdoutStr, stderrStr) = DenoPluginInfoRunner.runPluginInfo(filePath, uniqueId)
            if (exitCode != 0) {
                if (stderrStr.trimAscii().size > 0) {
                    logger.warn("plugin_info failed", ("file", filePath), ("stderr", truncateForLog(stderrStr, 1024)))
                }
                return result
            }

            // Prefer parsing NDJSON result->data; fall back to raw stdout if it looks like a single JSON object.
            var infoJson = DenoPluginInfoRunner.extractPluginInfoDataFromNdjson(stdoutStr)
            if (infoJson.trimAscii().size == 0) {
                infoJson = stdoutStr
            }
            result = parsePluginInfoOutput(infoJson, sourceUrl)
        } catch (_: Exception) {}

        return result
    }

    private static func parsePluginInfoOutput(output: String, sourceUrl: String): ParsedPluginInfo {
        var result = ParsedPluginInfo()

        try {
            let trimmed = output.trimAscii()
            if (trimmed.size == 0) { return result }

            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            func applyField(key: String): Unit {
                match (key) {
                    case "type" =>
                        let t = r.readValue<String>().trimAscii()
                        result.pluginType = capitalizeFirst(t)
                    case "update_url" =>
                        result.updateUrl = r.readValue<String>().trimAscii()
                    case "namespace" => result.namespace = r.readValue<String>().trimAscii()
                    case "name" => result.name = r.readValue<String>().trimAscii()
                    case "version" => result.version = r.readValue<String>().trimAscii()
                    case "description" => result.description = r.readValue<String>()
                    case "author" => result.author = r.readValue<String>()
                    case "tags" => result.tags = r.readValue<String>()
                    case "url_regex" => result.url_regex = r.readValue<String>()
                    case "login_from" => result.login_from = r.readValue<String>()
                    case "icon" => result.icon = r.readValue<String>()
                    case "permissions" =>
                        match (r.peek()) {
                            case Some(BeginArray) =>
                                var out = ""
                                var first = true
                                r.startArray()
                                while (r.peek() != EndArray) {
                                    let s = r.readValue<String>().trimAscii()
                                    if (s.size == 0) { continue }
                                    if (!first) { out += "," } else { first = false }
                                    out += s
                                }
                                r.endArray()
                                result.permissions = out
                            case Some(_) =>
                                result.permissions = r.readValue<String>().trimAscii()
                            case None => ()
                        }
                    case "parameters" =>
                        match (r.peek()) {
                            case Some(BeginArray) =>
                                let bytes = r.readValueBytes()
                                let raw = String.fromUtf8(bytes)
                                result.parameters = raw
                                let t = raw.trimAscii()
                                result.has_schema = t.size > 2 && t != "[]"
                            case Some(_) =>
                                // Unexpected format; keep defaults.
                                r.skip()
                            case None => ()
                        }
                    case _ =>
                        r.skip()
                }
            }

            func parsePayloadObject(): Unit {
                r.startObject()
                while (r.peek() != EndObject) {
                    let k = r.readName()
                    applyField(k)
                }
                r.endObject()
            }

            if (r.peek() != Some(BeginObject)) { return result }

            // Wrapper-aware parsing: if there's a "data" object, prefer it.
            r.startObject()
            var parsedData = false
            while (r.peek() != EndObject) {
                let k = r.readName()
                if (k == "data" && r.peek() == Some(BeginObject)) {
                    parsedData = true
                    parsePayloadObject()
                } else if (!parsedData) {
                    applyField(k)
                } else {
                    r.skip()
                }
            }
            r.endObject()

            if (result.updateUrl.size == 0) {
                result.updateUrl = sourceUrl
            }
        } catch (_: Exception) {}

        return result
    }

    private static func capitalizeFirst(s: String): String {
        if (s.size == 0) { return s }
        let lower = s.toAsciiLower()
        match (lower) {
            case "metadata" => return "Metadata"
            case "login" => return "Login"
            case "download" => return "Download"
            case "script" => return "Script"
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
