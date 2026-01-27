package lanlu.task_runners

import std.fs.*
import std.time.*
import std.convert.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import std.collection.*
import stdx.encoding.json.stream.*
import lanlu.models.*
import lanlu.utils.*
import lanlu.dao.*
import semver.*

/**
 * 插件扫描任务：扫描并注册TypeScript/Deno插件文件（Metadata、Login、Download 插件）
 */
public class ScanPluginsTaskRunner {

    public static func run(taskId: Int64, _: String, context: TaskRunnerContext): Unit {
        let pluginPath = context.paths.pluginPath
        FileUtils.ensureDirectoryExists(Path(pluginPath))

        TaskIO.appendLog(taskId, "scan_plugins task started")

        TaskModel.updateTaskProgress(taskId, 10, "Starting plugin scan")

        let result = scanPlugins(taskId, pluginPath)

        if (result.errorCount > 0) {
            let errorJson = "{\"success\":1,\"processed_count\":${result.processedCount},\"total_found\":${result.totalFound},\"error_count\":${result.errorCount}}"
            TaskModel.updateTaskProgress(taskId, 100, "Plugin scan completed with ${result.errorCount} errors")
            TaskModel.completeTask(taskId, errorJson)
            TaskIO.writeOutput(taskId, errorJson)
            TaskIO.appendLog(taskId, "scan_plugins completed with errors: processed=${result.processedCount}, errors=${result.errorCount}")
        } else {
            let successJson = "{\"success\":1,\"processed_count\":${result.processedCount},\"total_found\":${result.totalFound},\"error_count\":0}"
            TaskModel.updateTaskProgress(taskId, 100, "Plugin scan completed")
            TaskModel.completeTask(taskId, successJson)
            TaskIO.writeOutput(taskId, successJson)
            TaskIO.appendLog(taskId, "scan_plugins completed: processed=${result.processedCount}, total=${result.totalFound}")
        }
    }

    /**
     * 扫描插件文件
     */
    private static func scanPlugins(taskId: Int64, pluginPath: String): ScanResultData {
        let startTime = getCurrentTimeMillis()
        var processedCount: Int64 = 0
        var errorCount: Int64 = 0
        var errors: Array<String> = Array<String>()

        TaskIO.appendLog(taskId, "Starting plugin scan")
        TaskIO.appendLog(taskId, "Plugin path: ${pluginPath}")

        // 检查目录是否存在
        if (!directoryExists(pluginPath)) {
            // 尝试创建目录（避免因为目录缺失导致任务直接失败）
            try {
                Directory.create(Path(pluginPath), recursive: true)
            } catch (_: Exception) {}

            if (!directoryExists(pluginPath)) {
                let error = "Plugin directory does not exist: ${pluginPath}"
                TaskIO.appendLog(taskId, "ERROR: ${error}")
                return ScanResultData(0, 0, 1, [error])
            }
        }

        // 扫描插件文件
        let pluginFiles = findPluginFiles(taskId, pluginPath)
        TaskIO.appendLog(taskId, "Found ${pluginFiles.size} plugin files to process")

        // 清理已删除的插件
        let removedCount = cleanupRemovedPlugins(taskId, pluginPath, pluginFiles)
        if (removedCount > 0) {
            TaskIO.appendLog(taskId, "Removed ${removedCount} plugins that no longer exist on filesystem")
        }

        // 处理每个插件文件
        for (pluginFile in pluginFiles) {
            try {
                TaskIO.appendLog(taskId, "Processing plugin: ${pluginFile}")

                let result = processPluginFile(taskId, pluginPath, pluginFile)

                if (result.success) {
                    processedCount++
                    TaskIO.appendLog(taskId, "Successfully processed plugin: ${pluginFile} (namespace: ${result.archiveId})")
                } else {
                    errorCount++
                    let errorMsg = "Failed to process plugin ${pluginFile}: ${result.error}"
                    errors = addError(errors, errorMsg)
                    TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                }
            } catch (e: Exception) {
                errorCount++
                let errorMsg = "Exception while processing plugin ${pluginFile}: ${e.message}"
                errors = addError(errors, errorMsg)
                TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
            }
        }

        let endTime = getCurrentTimeMillis()
        let duration = endTime - startTime

        TaskIO.appendLog(taskId, "Plugin scan completed: processed=${processedCount}, errors=${errorCount}, duration=${duration}ms")

        return ScanResultData(processedCount, pluginFiles.size, errorCount, errors)
    }

    /**
     * 查找插件文件 - 扫描目录下所有 .ts 文件（包括子目录）
     */
    private static func findPluginFiles(taskId: Int64, dirPath: String): ArrayList<String> {
        var result: ArrayList<String> = ArrayList<String>()

        try {
            if (!directoryExists(dirPath)) {
                return result
            }

            let entries = listDirectory(dirPath)
            TaskIO.appendLog(taskId, "Scanning plugin directory: ${dirPath} (${entries.size} entries)")

            for (entry in entries) {
                let fullPath = joinPath(dirPath, entry)

                if (fileExists(fullPath) && entry.endsWith(".ts")) {
                    // 直接在根目录的 .ts 文件
                    result.add(fullPath)
                    TaskIO.appendLog(taskId, "Found TypeScript plugin: ${fullPath}")
                } else if (directoryExists(fullPath)) {
                    // 递归扫描子目录
                    let subFiles = findPluginFilesInDir(taskId, fullPath)
                    result.add(all: subFiles)
                }
            }
        } catch (e: Exception) {
            TaskIO.appendLog(taskId, "ERROR: Error scanning plugin directory ${dirPath}: ${e.message}")
        }

        return result
    }

    /**
     * 递归扫描目录中的插件文件
     */
    private static func findPluginFilesInDir(taskId: Int64, dirPath: String): ArrayList<String> {
        var result: ArrayList<String> = ArrayList<String>()

        try {
            let entries = listDirectory(dirPath)

            for (entry in entries) {
                let fullPath = joinPath(dirPath, entry)

                if (fileExists(fullPath) && entry.endsWith(".ts")) {
                    result.add(fullPath)
                    TaskIO.appendLog(taskId, "Found TypeScript plugin: ${fullPath}")
                } else if (directoryExists(fullPath)) {
                    // 递归扫描子目录
                    let subFiles = findPluginFilesInDir(taskId, fullPath)
                    result.add(all: subFiles)
                }
            }
        } catch (e: Exception) {
            TaskIO.appendLog(taskId, "ERROR: Error scanning directory ${dirPath}: ${e.message}")
        }

        return result
    }

    /**
     * 处理插件文件
     */
    private static func processPluginFile(taskId: Int64, pluginRoot: String, filePath: String): ProcessResultData {
        try {
            let pathParts = filePath.split("/")
            let fileName = pathParts[pathParts.size - 1]

            TaskIO.appendLog(taskId, "Processing plugin file: ${fileName}")

            // 计算相对于本次扫描根目录的路径，直接作为 entry 存储：
            // - pluginRoot: /path/to/plugins
            // - filePath:   /path/to/plugins/subfolder/plugin.ts
            // - entryPath:  subfolder/plugin.ts
            let entryPath = computeEntryPath(pluginRoot, filePath)

            TaskIO.appendLog(taskId, "Plugin entry path: ${entryPath}")

            // 使用Deno解析插件元数据，类型从元数据获取
            let pluginMetadata = parsePluginMetadataWithDeno(taskId, filePath)

            if (pluginMetadata.name.size == 0) {
                return ProcessResultData(false, "", "Failed to parse plugin metadata")
            }

            // 从元数据获取插件类型，转换为首字母大写格式
            let pluginType = capitalizeFirst(pluginMetadata.plugin_type)
            if (pluginType.size == 0) {
                return ProcessResultData(false, "", "Plugin type not found in metadata")
            }

            TaskIO.appendLog(taskId, "Plugin type from metadata: ${pluginType}")

            // 检查插件是否已存在（通过namespace检查）
            if (PluginDao.exists(pluginMetadata.namespace)) {
                let existingPlugin = PluginDao.getPluginByNamespace(pluginMetadata.namespace)
                let compareResult = compare(existingPlugin.version, pluginMetadata.version)

                match (compareResult) {
                    case Equal =>
                        TaskIO.appendLog(taskId, "Plugin version unchanged: ${pluginMetadata.namespace} (${existingPlugin.version})")
                        syncScriptScheduledTask(taskId, pluginMetadata, pluginType)
                        return ProcessResultData(true, pluginMetadata.namespace, "")
                    case MajorUpgrade =>
                        TaskIO.appendLog(taskId, "Major upgrade detected for ${pluginMetadata.namespace}: ${existingPlugin.version} -> ${pluginMetadata.version}, clearing parameters")
                        return updateExistingPlugin(taskId, existingPlugin, pluginMetadata, fileName, entryPath, pluginType, true)
                    case MinorUpgrade | PatchUpgrade =>
                        TaskIO.appendLog(taskId, "Upgrade detected for ${pluginMetadata.namespace}: ${existingPlugin.version} -> ${pluginMetadata.version}, preserving parameters")
                        return updateExistingPlugin(taskId, existingPlugin, pluginMetadata, fileName, entryPath, pluginType, false)
                    case Downgrade =>
                        // Keep DB consistent with filesystem: apply the downgrade metadata but preserve parameters.
                        TaskIO.appendLog(taskId, "Version downgrade detected for ${pluginMetadata.namespace}: ${existingPlugin.version} -> ${pluginMetadata.version}, applying (preserve parameters)")
                        return updateExistingPlugin(taskId, existingPlugin, pluginMetadata, fileName, entryPath, pluginType, false)
                    case Invalid =>
                        // Keep DB consistent with filesystem even if semver is invalid.
                        TaskIO.appendLog(taskId, "Invalid version format for ${pluginMetadata.namespace}, applying metadata (preserve parameters)")
                        return updateExistingPlugin(taskId, existingPlugin, pluginMetadata, fileName, entryPath, pluginType, false)
                }
            }

            // 创建新插件数据记录
            var pluginData = PluginData()
            pluginData.name = pluginMetadata.name
            pluginData.namespace = pluginMetadata.namespace
            pluginData.version = pluginMetadata.version
            pluginData.description = pluginMetadata.description
            pluginData.author = pluginMetadata.author
            // entry 存储完整的相对路径，支持子目录
            pluginData.entry = entryPath
            pluginData.plugin_type = pluginType
            pluginData.tags = pluginMetadata.tags
            pluginData.permissions = pluginMetadata.permissions
            pluginData.update_url = pluginMetadata.update_url
            pluginData.parameters = pluginMetadata.parameters
            pluginData.has_schema = pluginMetadata.has_schema
            pluginData.url_regex = pluginMetadata.url_regex
            pluginData.login_from = pluginMetadata.login_from
            pluginData.icon = pluginMetadata.icon
            pluginData.enabled = true
            pluginData.installed = true
            pluginData.created_at = DateTime.now().toUnixTimeStamp().toSeconds().toString()
            pluginData.updated_at = pluginData.created_at

            // 保存到数据库
            if (PluginDao.create(pluginData)) {
                TaskIO.appendLog(taskId, "Successfully registered plugin: ${pluginData.namespace} (${pluginData.name})")
                syncScriptScheduledTask(taskId, pluginMetadata, pluginType)
                return ProcessResultData(true, pluginData.namespace, "")
            } else {
                TaskIO.appendLog(taskId, "ERROR: Failed to save plugin to database")
                return ProcessResultData(false, "", "Failed to save plugin to database")
            }
        } catch (e: Exception) {
            return ProcessResultData(false, "", "Error processing plugin file: ${e.message}")
        }
    }

    /**
     * 使用Deno解析TypeScript插件元数据
     */
    private static func parsePluginMetadataWithDeno(taskId: Int64, filePath: String): PluginMetadata {
        var metadata = PluginMetadata()

        try {
            TaskIO.appendLog(taskId, "Parsing plugin metadata: ${filePath}")

            // Use the shared runner so allow-read is scoped to the sandbox temp root.
            let (exitCode, stdoutStr, stderrStr) = DenoPluginInfoRunner.runPluginInfo(filePath, taskId.toString())

            if (exitCode == 0 && stdoutStr.trimAscii().size > 0) {
                let jsonStr = stdoutStr.trimAscii()
                TaskIO.appendLog(taskId, "Plugin metadata raw output: ${jsonStr}")

                // 解析 NDJSON 格式的输出，查找 result 类型的消息
                let pluginInfo = DenoPluginInfoRunner.extractPluginInfoDataFromNdjson(jsonStr)
                if (pluginInfo.size > 0) {
                    try {
                        var buf = ByteBuffer()
                        unsafe { buf.write(pluginInfo.rawData()) }
                        let r = JsonReader(buf)

                        func readBoolFlexible(): Bool {
                            let v = r.readValue<String>().trimAscii().toAsciiLower()
                            return v == "true" || v == "1"
                        }
                        func readInt32Flexible(defaultValue: Int32): Int32 {
                            let s = r.readValue<String>().trimAscii()
                            try { return Int32.parse(s) } catch (_: Exception) { return defaultValue }
                        }
                        func readCommaSeparated(): String {
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
                                    return out
                                case Some(_) =>
                                    return r.readValue<String>().trimAscii()
                                case None => return ""
                            }
                        }

                        if (r.peek() == Some(BeginObject)) {
                            r.startObject()
                            while (r.peek() != EndObject) {
                                let k = r.readName()
                                match (k) {
                                    case "name" => metadata.name = r.readValue<String>().trimAscii()
                                    case "namespace" => metadata.namespace = r.readValue<String>().trimAscii()
                                    case "version" => metadata.version = r.readValue<String>().trimAscii()
                                    case "description" => metadata.description = r.readValue<String>()
                                    case "author" => metadata.author = r.readValue<String>()
                                    case "tags" => metadata.tags = r.readValue<String>()
                                    case "permissions" => metadata.permissions = readCommaSeparated()
                                    case "update_url" => metadata.update_url = r.readValue<String>().trimAscii()
                                    case "parameters" =>
                                        match (r.peek()) {
                                            case Some(BeginArray) =>
                                                let bytes = r.readValueBytes()
                                                let raw = String.fromUtf8(bytes)
                                                metadata.parameters = raw
                                                let t = raw.trimAscii()
                                                metadata.has_schema = t.size > 2 && t != "[]"
                                            case Some(_) =>
                                                r.skip()
                                                metadata.parameters = "[]"
                                                metadata.has_schema = false
                                            case None => ()
                                        }
                                    case "url_regex" => metadata.url_regex = r.readValue<String>()
                                    case "login_from" => metadata.login_from = r.readValue<String>()
                                    case "icon" => metadata.icon = r.readValue<String>()
                                    case "type" => metadata.plugin_type = r.readValue<String>().trimAscii()
                                    case "cron_expression" => metadata.cron_expression = r.readValue<String>()
                                    case "cron_enabled" => metadata.cron_enabled = readBoolFlexible()
                                    case "cron_priority" => metadata.cron_priority = readInt32Flexible(50)
                                    case "cron_timeout_seconds" => metadata.cron_timeout_seconds = readInt32Flexible(3600)
                                    case _ => r.skip()
                                }
                            }
                            r.endObject()

                            if (metadata.name.size == 0) {
                                metadata.name = Path(filePath).fileName.toString()
                            }

                            TaskIO.appendLog(taskId, "Successfully parsed plugin metadata: name=${metadata.name}, namespace=${metadata.namespace}, version=${metadata.version}, type=${metadata.plugin_type}")
                        } else {
                            TaskIO.appendLog(taskId, "WARN: Failed to parse plugin metadata JSON for ${filePath}")
                        }
                    } catch (_: Exception) {
                        TaskIO.appendLog(taskId, "WARN: Failed to parse plugin metadata JSON for ${filePath}")
                    }
                } else {
                    TaskIO.appendLog(taskId, "WARN: No result message found in plugin output for ${filePath}")
                }
            } else {
                // 执行失败
                if (stderrStr.size > 0) {
                    TaskIO.appendLog(taskId, "ERROR: Failed to execute plugin metadata parsing: exitCode=${exitCode}, stderr=${stderrStr}")
                } else if (stdoutStr.size > 0) {
                    // 某些情况下 Deno 的错误/提示会混在 stdout，保留以便排查
                    TaskIO.appendLog(taskId, "ERROR: Failed to execute plugin metadata parsing: exitCode=${exitCode}, stdout=${stdoutStr}")
                } else {
                    TaskIO.appendLog(taskId, "ERROR: Failed to execute plugin metadata parsing: exitCode=${exitCode}, no output")
                }
            }
        } catch (e: Exception) {
            TaskIO.appendLog(taskId, "ERROR: Error parsing plugin metadata for ${filePath}: ${e.message}")
        }

        return metadata
    }

    /**
     * 添加错误信息到数组
     */
    private static func addError(errors: Array<String>, error: String): Array<String> {
        let result = Array<String>(errors.size + 1, { i =>
            if (i < errors.size) {
                errors[i]
            } else {
                error
            }
        })
        return result
    }

    private static func buildScriptScheduledTaskName(namespace: String): String {
        // Stable, namespaced identifier to avoid colliding with user-created scheduled tasks.
        return "plugin_script:${namespace}"
    }

    private static func buildScriptDenoTaskParameters(namespace: String): String {
        // deno_task parameters is a JSON string parsed by DenoTaskRunner.parseParameters().
        // extraParams is expected to be a JSON *string* (merged into plugin params at runtime).
        let groupId = "cron:script:${namespace}"
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("pluginNamespace").writeValue(namespace)
        w.writeName("pluginType").writeValue("Script")
        w.writeName("action").writeValue("run")
        w.writeName("groupId").writeValue(groupId)
        w.writeName("oneshotParam").writeValue("")
        w.writeName("extraParams").writeValue("{}")
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func syncScriptScheduledTask(taskId: Int64, metadata: PluginMetadata, pluginType: String): Unit {
        if (pluginType != "Script") { return }
        let ns = metadata.namespace.trimAscii()
        if (ns.size == 0) { return }

        let name = buildScriptScheduledTaskName(ns)
        let denoParams = buildScriptDenoTaskParameters(ns)

        match (ScheduledTaskModel.getByName(name)) {
            case Some(existing) =>
                // Preserve user edits (cronExpression/enabled/priority/timeout); only keep wiring correct.
                var updated = existing
                updated.taskType = "deno_task"
                updated.taskParameters = denoParams
                if (ScheduledTaskModel.update(updated)) {
                    TaskIO.appendLog(taskId, "Updated cron task for script plugin: ${name}")
                } else {
                    TaskIO.appendLog(taskId, "WARN: Failed to update cron task for script plugin: ${name}")
                }
            case None =>
                // Script plugins should "show up" in cron even without a provided expression.
                // Use a safe default expression and default to disabled so it won't run until user enables it.
                let cronExpr = if (metadata.cron_expression.trimAscii().size > 0) { metadata.cron_expression } else { "0 0 * * *" }
                let enabled = metadata.cron_enabled
                let priority = metadata.cron_priority
                let timeout = metadata.cron_timeout_seconds

                let task = ScheduledTask(
                    name: name,
                    cronExpression: cronExpr,
                    taskType: "deno_task",
                    taskParameters: denoParams,
                    enabled: enabled,
                    priority: priority,
                    timeoutSeconds: timeout
                )
                match (ScheduledTaskModel.create(task)) {
                    case Some(created) =>
                        TaskIO.appendLog(taskId, "Created cron task for script plugin: ${name} (id=${created.id.toString()})")
                    case None =>
                        TaskIO.appendLog(taskId, "WARN: Failed to create cron task for script plugin: ${name}")
                }
        }
    }

    /**
     * 检查目录是否存在（支持软链接）
     */
    private static func directoryExists(path: String): Bool {
        return DirectoryScanner.directoryExists(path)
    }

    /**
     * 检查文件是否存在（支持软链接）
     */
    private static func fileExists(path: String): Bool {
        return DirectoryScanner.fileExists(path)
    }

    /**
     * 列出目录内容（支持软链接）
     */
    private static func listDirectory(path: String): Array<String> {
        return DirectoryScanner.listDirectory(path)
    }

    /**
     * 拼接路径
     */
    private static func joinPath(base: String, part: String): String {
        return DirectoryScanner.joinPath(base, part)
    }

    /**
     * 获取当前时间戳（毫秒）
     */
    private static func getCurrentTimeMillis(): Int64 {
        return DateTime.now().toUnixTimeStamp().toSeconds() * 1000
    }

    /**
     * 将插件类型转换为首字母大写格式
     */
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

    /**
     * 更新已存在的插件
     * @param clearParameters 是否清除参数（破坏性更新时为 true）
     */
    private static func updateExistingPlugin(
        taskId: Int64,
        existingPlugin: PluginData,
        newMetadata: PluginMetadata,
        fileName: String,
        entryPath: String,
        pluginType: String,
        clearParameters: Bool
    ): ProcessResultData {
        var pluginData = PluginData()
        pluginData.id = existingPlugin.id
        pluginData.name = newMetadata.name
        pluginData.namespace = newMetadata.namespace
        pluginData.version = newMetadata.version
        pluginData.description = newMetadata.description
        pluginData.author = newMetadata.author
        // entry 存储完整的相对路径，支持子目录
        pluginData.entry = entryPath
        pluginData.plugin_type = pluginType
        pluginData.tags = newMetadata.tags
        pluginData.permissions = newMetadata.permissions
        pluginData.url_regex = newMetadata.url_regex
        pluginData.login_from = newMetadata.login_from
        pluginData.icon = newMetadata.icon
        pluginData.update_url = if (newMetadata.update_url.trimAscii().size > 0) { newMetadata.update_url } else { existingPlugin.update_url }
        pluginData.enabled = existingPlugin.enabled
        pluginData.installed = true
        pluginData.has_schema = newMetadata.has_schema

        // 根据是否破坏性更新决定是否清除参数
        if (clearParameters) {
            pluginData.parameters = newMetadata.parameters
        } else {
            pluginData.parameters = existingPlugin.parameters
        }

        if (PluginDao.update(pluginData)) {
            let action = if (clearParameters) { "updated (parameters cleared)" } else { "updated" }
            TaskIO.appendLog(taskId, "Plugin ${action}: ${pluginData.namespace} (${pluginData.name})")
            syncScriptScheduledTask(taskId, newMetadata, pluginType)
            if (existingPlugin.plugin_type == "Script" && pluginType != "Script") {
                let cronName = buildScriptScheduledTaskName(existingPlugin.namespace)
                if (ScheduledTaskModel.deleteByName(cronName)) {
                    TaskIO.appendLog(taskId, "Removed cron task (type changed) for plugin: ${cronName}")
                }
            }
            return ProcessResultData(true, pluginData.namespace, "")
        } else {
            TaskIO.appendLog(taskId, "ERROR: Failed to update plugin in database")
            return ProcessResultData(false, "", "Failed to update plugin in database")
        }
    }

    /**
     * 清理已删除的插件文件
     * 检查数据库中的插件，如果对应的文件不存在则从数据库中删除
     */
    private static func cleanupRemovedPlugins(
        taskId: Int64,
        pluginPath: String,
        existingFiles: ArrayList<String>
    ): Int64 {
        var removedCount: Int64 = 0

        // Fast membership test for "what exists on disk right now".
        // Use entryPath (relative to pluginPath) as the stable key.
        let normalizedRoot = normalizeRootPath(pluginPath)
        var existingEntries = HashSet<String>()
        for (filePath in existingFiles) {
            existingEntries.add(computeEntryPath(normalizedRoot, filePath))
        }

        let allPlugins = PluginDao.getAllPlugins()
        TaskIO.appendLog(taskId, "Checking ${allPlugins.size} plugins in database for removed files")

        for (plugin in allPlugins) {
            let entryTrimmed = plugin.entry.trimAscii()
            if (entryTrimmed.size == 0) {
                TaskIO.appendLog(taskId, "WARN: Plugin entry is empty, skipping cleanup: ${plugin.namespace}")
                continue
            }

            // Support older records where entry may be an absolute path.
            let (entryKey, expectedPath) = resolveEntryAndPath(normalizedRoot, entryTrimmed)

            if (!existingEntries.contains(entryKey) && !fileExists(expectedPath)) {
                TaskIO.appendLog(taskId, "Plugin file not found, removing: ${plugin.namespace} (${expectedPath})")
                if (PluginDao.delete(plugin.namespace)) {
                    removedCount++
                    TaskIO.appendLog(taskId, "Removed plugin: ${plugin.namespace}")
                    if (plugin.plugin_type == "Script") {
                        let cronName = buildScriptScheduledTaskName(plugin.namespace)
                        if (ScheduledTaskModel.deleteByName(cronName)) {
                            TaskIO.appendLog(taskId, "Removed cron task for script plugin: ${cronName}")
                        }
                    }
                } else {
                    TaskIO.appendLog(taskId, "ERROR: Failed to remove plugin: ${plugin.namespace}")
                }
            }
        }

        if (removedCount > 0) {
            TaskIO.appendLog(taskId, "Cleaned up ${removedCount} removed plugins")
        }

        return removedCount
    }

    /**
     * Normalize root path so prefix checks are stable (trailing slashes removed).
     */
    private static func normalizeRootPath(root: String): String {
        var out = root.trimAscii()
        while (out.size > 1 && out.endsWith("/")) {
            out = out[0..(out.size - 1)]
        }
        return out
    }

    /**
     * Compute entry path (relative to pluginRoot) for a file on disk.
     */
    private static func computeEntryPath(pluginRoot: String, filePath: String): String {
        let normalizedRoot = normalizeRootPath(pluginRoot)
        let normalizedPrefix = "${normalizedRoot}/"

        // Prefer stable relative entry for records and comparisons.
        if (filePath.startsWith(normalizedPrefix)) {
            return filePath[normalizedPrefix.size..]
        }

        // Fallback: keep just the filename if outside root.
        let parts = filePath.split("/")
        return parts[parts.size - 1]
    }

    /**
     * Resolve a plugin entry to:
     * - a stable key used for set comparison (relative when possible)
     * - an absolute path used for file existence check
     */
    private static func resolveEntryAndPath(pluginRoot: String, entry: String): (String, String) {
        let normalizedRoot = normalizeRootPath(pluginRoot)
        let normalizedPrefix = "${normalizedRoot}/"

        // Absolute path recorded in DB.
        if (entry.startsWith("/")) {
            let key = if (entry.startsWith(normalizedPrefix)) { entry[normalizedPrefix.size..] } else { entry }
            return (key, entry)
        }

        return (entry, joinPath(normalizedRoot, entry))
    }

    // NOTE: plugin_info execution + NDJSON parsing are now centralized in DenoPluginInfoRunner.
}
