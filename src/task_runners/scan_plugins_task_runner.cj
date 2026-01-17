package lrr4cj.task_runners

import std.fs.*
import std.process.*
import std.time.*
import std.convert.*
import std.io.*
import stdx.encoding.json.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*
import cjoy.json.*
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

        // 处理每个插件文件
        for (pluginFile in pluginFiles) {
            try {
                TaskIO.appendLog(taskId, "Processing plugin: ${pluginFile}")

                let result = processPluginFile(taskId, pluginFile)

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

        return ScanResultData(processedCount, pluginFiles.size, 0, errors)
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
    private static func processPluginFile(taskId: Int64, filePath: String): ProcessResultData {
        try {
            let pathParts = filePath.split("/")
            let fileName = pathParts[pathParts.size - 1]

            TaskIO.appendLog(taskId, "Processing plugin file: ${fileName}")

            // 计算相对于插件根目录的路径，直接作为 entry 存储
            // filePath 格式: /path/to/data/plugins/subfolder/plugin.ts
            // pluginPath 格式: /path/to/data/plugins
            // entryPath 应该是: subfolder/plugin.ts 或 plugin.ts
            let pluginPath = PluginPaths.getPluginStorageRoot()
            let entryPath = if (filePath.startsWith(pluginPath)) {
                filePath[(pluginPath.size + 1)..]  // +1 to skip the leading '/'
            } else {
                // 如果不在标准路径下，使用文件名
                fileName
            }

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
                        return ProcessResultData(true, pluginMetadata.namespace, "")
                    case MajorUpgrade =>
                        TaskIO.appendLog(taskId, "Major upgrade detected for ${pluginMetadata.namespace}: ${existingPlugin.version} -> ${pluginMetadata.version}, clearing parameters")
                        return updateExistingPlugin(taskId, existingPlugin, pluginMetadata, fileName, entryPath, pluginType, true)
                    case MinorUpgrade | PatchUpgrade =>
                        TaskIO.appendLog(taskId, "Upgrade detected for ${pluginMetadata.namespace}: ${existingPlugin.version} -> ${pluginMetadata.version}, preserving parameters")
                        return updateExistingPlugin(taskId, existingPlugin, pluginMetadata, fileName, entryPath, pluginType, false)
                    case Downgrade =>
                        TaskIO.appendLog(taskId, "Version downgrade detected for ${pluginMetadata.namespace}: ${existingPlugin.version} -> ${pluginMetadata.version}, skipping")
                        return ProcessResultData(true, pluginMetadata.namespace, "")
                    case Invalid =>
                        TaskIO.appendLog(taskId, "Invalid version format for ${pluginMetadata.namespace}, skipping")
                        return ProcessResultData(true, pluginMetadata.namespace, "")
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

            // 使用 stdio 方式运行插件获取信息
            let (exitCode, stdout, stderr) = executePluginInfoWithStdio(taskId, filePath)

            if (exitCode == 0 && stdout.size > 0) {
                let jsonStr = String.fromUtf8(stdout).trimAscii()
                TaskIO.appendLog(taskId, "Plugin metadata raw output: ${jsonStr}")

                // 解析 NDJSON 格式的输出，查找 result 类型的消息
                let pluginInfo = parsePluginInfoFromNdjson(jsonStr)
                if (pluginInfo.size > 0) {
                    let json = JsonValue.fromStr(pluginInfo)
                    match (json) {
                        case jsonObj: JsonObject =>
                            let nameValue = getJsonString(jsonObj, "name")
                            metadata.name = if (nameValue.size > 0) { nameValue } else { Path(filePath).fileName.toString() }
                            metadata.namespace = getJsonString(jsonObj, "namespace")
                            metadata.version = getJsonString(jsonObj, "version")
                            metadata.description = getJsonString(jsonObj, "description")
                            metadata.author = getJsonString(jsonObj, "author")
                            metadata.tags = getJsonString(jsonObj, "tags")
                            metadata.permissions = getJsonCommaSeparated(jsonObj, "permissions")
                            metadata.update_url = getJsonString(jsonObj, "update_url")

                            // 解析parameters字段
                            if (jsonObj.getFields().contains("parameters")) {
                                let paramsValue = jsonObj.getFields()["parameters"]
                                match (paramsValue) {
                                    case paramsArray: JsonArray =>
                                        metadata.parameters = paramsArray.toString()
                                        metadata.has_schema = paramsArray.size() > 0
                                    case _ =>
                                        metadata.parameters = "[]"
                                        metadata.has_schema = false
                                }
                            }

                            // 解析其他可选字段
                            metadata.url_regex = getJsonString(jsonObj, "url_regex")
                            metadata.login_from = getJsonString(jsonObj, "login_from")
                            metadata.icon = getJsonString(jsonObj, "icon")
                            metadata.plugin_type = getJsonString(jsonObj, "type")

                            TaskIO.appendLog(taskId, "Successfully parsed plugin metadata: name=${metadata.name}, namespace=${metadata.namespace}, version=${metadata.version}, type=${metadata.plugin_type}")
                        case _ =>
                            TaskIO.appendLog(taskId, "WARN: Failed to parse plugin metadata JSON for ${filePath}")
                    }
                } else {
                    TaskIO.appendLog(taskId, "WARN: No result message found in plugin output for ${filePath}")
                }
            } else {
                // 执行失败
                let stderrStr = String.fromUtf8(stderr).trimAscii()
                let stdoutStr = if (stdout.size > 0) { String.fromUtf8(stdout).trimAscii() } else { "" }
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

    /**
     * 从JsonObject获取字符串值的辅助函数
     */
    private static func getJsonString(jsonObj: JsonObject, key: String): String {
        let fields = jsonObj.getFields()
        if (fields.contains(key)) {
            let value = fields[key]
            match (value) {
                case jsonStr: JsonString =>
                    return jsonStr.getValue()
                case _ =>
                    return value.toString()
            }
        }
        return ""
    }

    private static func getJsonCommaSeparated(jsonObj: JsonObject, key: String): String {
        let fields = jsonObj.getFields()
        if (!fields.contains(key)) {
            return ""
        }

        let value = fields[key]
        match (value) {
            case arr: JsonArray =>
                var out = ""
                var first = true
                let size = arr.size()
                for (i in 0..size) {
                    match (arr.get(i)) {
                        case Some(v) =>
                            let s = match (v) {
                                case js: JsonString => js.getValue()
                                case _ => v.toString()
                            }.trimAscii()
                            if (s.size == 0) { continue }
                            if (!first) { out += "," }
                            out += s
                            first = false
                        case None => ()
                    }
                }
                return out
            case jsonStr: JsonString =>
                return jsonStr.getValue()
            case _ =>
                return value.toString()
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

        let allPlugins = PluginDao.getAllPlugins()
        TaskIO.appendLog(taskId, "Checking ${allPlugins.size} plugins in database for removed files")

        for (plugin in allPlugins) {
            // 直接使用 entry 构建完整路径（支持子目录）
            let expectedPath = buildPluginPath(pluginPath, plugin.plugin_type, plugin.entry)

            if (!existingFiles.contains(expectedPath) && !fileExists(expectedPath)) {
                TaskIO.appendLog(taskId, "Plugin file not found, removing: ${plugin.namespace} (${expectedPath})")
                if (PluginDao.delete(plugin.namespace)) {
                    removedCount++
                    TaskIO.appendLog(taskId, "Removed plugin: ${plugin.namespace}")
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
     * 构建插件文件路径
     * 所有插件统一存放在 basePath 根目录，不再按类型分子目录
     */
    private static func buildPluginPath(basePath: String, pluginType: String, entry: String): String {
        joinPath(basePath, entry)
    }

    /**
     * 从 NDJSON 输出中解析 plugin info
     * 查找 type=result 且 success=true 的消息，返回其 data 字段
     */
    private static func parsePluginInfoFromNdjson(ndjsonOutput: String): String {
        let lines = ndjsonOutput.split("\n")
        for (line in lines) {
            let trimmed = line.trimAscii()
            if (trimmed.size == 0) {
                continue
            }

            try {
                let jsonVal = JsonValue.fromStr(trimmed)
                match (jsonVal) {
                    case obj: JsonObject =>
                        let fields = obj.getFields()
                        // 检查是否是 result 类型
                        match (fields.get("type")) {
                            case Some(typeVal) =>
                                match (typeVal) {
                                    case typeStr: JsonString =>
                                        if (typeStr.getValue() == "result") {
                                            // 检查 success 字段
                                            match (fields.get("success")) {
                                                case Some(successVal) =>
                                                    match (successVal) {
                                                        case successBool: JsonBool =>
                                                            if (successBool.getValue()) {
                                                                // 返回 data 字段
                                                                match (fields.get("data")) {
                                                                    case Some(dataVal) =>
                                                                        return dataVal.toString()
                                                                    case None => ()
                                                                }
                                                            }
                                                        case _ => ()
                                                    }
                                                case None => ()
                                            }
                                        }
                                    case _ => ()
                                }
                            case None => ()
                        }
                    case _ => ()
                }
            } catch (_: Exception) {
                // 解析失败，跳过这一行
            }
        }
        return ""
    }

    /**
     * 使用 stdio 方式执行插件获取 plugin_info
     */
    private static func executePluginInfoWithStdio(taskId: Int64, filePath: String): (Int32, Array<UInt8>, Array<UInt8>) {
        try {
            // 构建一个临时目录，模拟 ./plugins/<Type>/X.ts 与 ./plugins/base_plugin.ts 的相对结构，
            // 以兼容插件里常见的 `../base_plugin.ts` 引用。
            let pathParts = filePath.split("/")
            let fileName = Path(filePath).fileName.toString()
            let pluginTypeDir = if (pathParts.size >= 2) { pathParts[pathParts.size - 2] } else { "Temp" }

            // 注意：getCurrentTimeMillis() 的分辨率只有秒级（末尾通常为 000），
            // 若多次调用落在同一秒内会产生相同路径，导致临时目录互相覆盖/清理。
            // 这里加入 taskId + pluginTypeDir + fileName 以保证稳定唯一性。
            let safeFileName = fileName.replace(".", "_")
            let tempRoot = Path("${PluginPaths.getPluginInfoTempRoot()}/${taskId.toString()}/${getCurrentTimeMillis().toString()}_${pluginTypeDir}_${safeFileName}")
            let pluginsRoot = Path("${tempRoot.toString()}/plugins")
            let tempTypeDir = Path("${pluginsRoot.toString()}/${pluginTypeDir}")
            Directory.create(tempTypeDir, recursive: true)

            // 复制 base_plugin.ts
            let baseSource = Path("./plugins/base_plugin.ts")
            let baseTarget = Path("${pluginsRoot.toString()}/base_plugin.ts")
            if (exists(baseSource)) {
                copy(baseSource, to: baseTarget, overwrite: true)
            }

            // 复制插件文件
            let tempPluginFile = Path("${tempTypeDir.toString()}/${fileName}")
            copy(Path(filePath), to: tempPluginFile, overwrite: true)

            // 启动 Deno 进程（避免通过 shell 运行，减少引号/路径问题）
            TaskIO.appendLog(taskId, "Executing: deno run --allow-read ${tempPluginFile.toString()}")
            let process = launch("deno", ["run", "--allow-read", tempPluginFile.toString()],
                stdIn: ProcessRedirect.Pipe,
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe)

            // 写入 plugin_info 请求到 stdin
            let inputJson = "{\"action\":\"plugin_info\",\"pluginType\":\"\"}\n"
            process.stdInPipe.write(inputJson.toArray())
            process.stdInPipe.flush()

            // 使用 waitOutput 可靠地获取 stdout/stderr，避免在 wait() 后丢失管道内容
            let (exitCode, stdoutBytes, stderrBytes) = process.waitOutput()

            // 清理临时目录
            try {
                remove(tempRoot, recursive: true)
            } catch (_: Exception) {}

            return (Int32(exitCode), stdoutBytes, stderrBytes)
        } catch (e: Exception) {
            TaskIO.appendLog(taskId, "ERROR: executePluginInfoWithStdio failed: ${e.message}")
            return (1, Array<UInt8>(), Array<UInt8>())
        }
    }
}
