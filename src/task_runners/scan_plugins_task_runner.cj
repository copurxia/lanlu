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
            let error = "Plugin directory does not exist: ${pluginPath}"
            TaskIO.appendLog(taskId, "ERROR: ${error}")
            return ScanResultData(0, 0, 1, [error])
        }

        // 扫描插件文件
        let pluginFiles = findPluginFiles(taskId, pluginPath)
        TaskIO.appendLog(taskId, "Found ${pluginFiles.size} plugin files to process")

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
     * 查找插件文件
     */
    private static func findPluginFiles(taskId: Int64, dirPath: String): ArrayList<String> {
        var result: ArrayList<String> = ArrayList<String>()

        try {
            if (!directoryExists(dirPath)) {
                return result
            }

            let entries = listDirectory(dirPath)
            TaskIO.appendLog(taskId, "Scanning plugin directory: ${dirPath} (${entries.size} entries)")

            // 扫描EHentai相关的插件类型目录
            let pluginTypes = ["Metadata", "Login", "Download"]

            for (entry in entries) {
                let fullPath = joinPath(dirPath, entry)

                if (directoryExists(fullPath)) {
                    // 检查是否是插件类型目录
                    for (pluginType in pluginTypes) {
                        if (entry == pluginType) {
                            let pluginFiles = findPluginFilesInType(taskId, fullPath)
                            result.add(all: pluginFiles)
                            break
                        }
                    }
                }
            }
        } catch (e: Exception) {
            TaskIO.appendLog(taskId, "ERROR: Error scanning plugin directory ${dirPath}: ${e.message}")
        }

        return result
    }

    /**
     * 在指定类型目录中查找插件文件
     */
    private static func findPluginFilesInType(taskId: Int64, typeDirPath: String): ArrayList<String> {
        var result: ArrayList<String> = ArrayList<String>()

        try {
            let entries = listDirectory(typeDirPath)

            for (entry in entries) {
                let fullPath = joinPath(typeDirPath, entry)

                // 只扫描 TypeScript 插件文件
                if (fileExists(fullPath) && entry.endsWith(".ts")) {
                    result.add(fullPath)
                    TaskIO.appendLog(taskId, "Found TypeScript plugin: ${fullPath}")
                }
            }
        } catch (e: Exception) {
            TaskIO.appendLog(taskId, "ERROR: Error scanning plugin type directory ${typeDirPath}: ${e.message}")
        }

        return result
    }

    /**
     * 处理插件文件
     */
    private static func processPluginFile(taskId: Int64, filePath: String): ProcessResultData {
        try {
            // 解析插件路径获取类型和文件名
            let pathParts = filePath.split("/")
            let fileName = pathParts[pathParts.size - 1]
            let pluginType = if (pathParts.size >= 2) { pathParts[pathParts.size - 2] } else { "Unknown" }

            TaskIO.appendLog(taskId, "Processing plugin file: ${fileName} (type: ${pluginType})")

            // 使用Deno解析插件元数据
            let pluginMetadata = parsePluginMetadataWithDeno(taskId, filePath, pluginType)

            // 检查插件是否已存在（通过namespace检查）
            if (PluginDao.exists(pluginMetadata.namespace)) {
                TaskIO.appendLog(taskId, "Plugin already exists: ${pluginMetadata.namespace}")
                return ProcessResultData(true, pluginMetadata.namespace, "")
            }

            if (pluginMetadata.name.size == 0) {
                return ProcessResultData(false, "", "Failed to parse plugin metadata")
            }

            // 创建插件数据记录
            var pluginData = PluginData()
            // id会由数据库自动生成
            pluginData.name = pluginMetadata.name
            pluginData.namespace = pluginMetadata.namespace
            pluginData.version = pluginMetadata.version
            pluginData.description = pluginMetadata.description
            pluginData.author = pluginMetadata.author
            pluginData.entry = fileName
            pluginData.plugin_type = pluginType
            pluginData.tags = pluginMetadata.tags
            pluginData.permissions = pluginMetadata.permissions
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
    private static func parsePluginMetadataWithDeno(taskId: Int64, filePath: String, pluginType: String): PluginMetadata {
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
                            metadata.permissions = getJsonString(jsonObj, "permissions")

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

                            TaskIO.appendLog(taskId, "Successfully parsed plugin metadata: name=${metadata.name}, namespace=${metadata.namespace}, version=${metadata.version}, has_schema=${metadata.has_schema}")
                        case _ =>
                            setDefaultMetadata(metadata, filePath, pluginType)
                            TaskIO.appendLog(taskId, "WARN: Failed to parse plugin metadata JSON, using defaults for ${filePath}")
                    }
                } else {
                    setDefaultMetadata(metadata, filePath, pluginType)
                    TaskIO.appendLog(taskId, "WARN: No result message found in plugin output, using defaults for ${filePath}")
                }
            } else {
                // 执行失败，使用文件名作为默认信息
                let stderrStr = String.fromUtf8(stderr)
                let fileNameOnly = Path(filePath).fileName.toString()
                metadata.name = fileNameOnly
                metadata.namespace = "plugin." + pluginType.toAsciiLower() + "." + fileNameOnly.replace(".ts", "")
                metadata.version = "1.0"
                metadata.description = "${pluginType} plugin"
                metadata.author = "Unknown"

                TaskIO.appendLog(taskId, "ERROR: Failed to execute plugin metadata parsing: exitCode=${exitCode}, stderr=${stderrStr}")
            }
        } catch (e: Exception) {
            TaskIO.appendLog(taskId, "ERROR: Error parsing plugin metadata for ${filePath}: ${e.message}")
            // 异常情况下，使用文件名作为默认信息
            let fileNameOnly = Path(filePath).fileName.toString()
            metadata.name = fileNameOnly
            metadata.namespace = "plugin." + pluginType.toAsciiLower() + "." + fileNameOnly.replace(".ts", "")
            metadata.version = "1.0"
            metadata.description = "${pluginType} plugin"
            metadata.author = "Unknown"
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
     * 执行命令
     */
    private static func executeWithOutput(taskId: Int64, command: String, args: Array<String>): (Int32, Array<UInt8>, Array<UInt8>) {
        try {
            // 构建完整的命令字符串用于日志，对包含空格的参数加引号
            var fullCmd = command
            for (arg in args) {
                if (arg.contains(" ") || arg.contains("\t") || arg.contains("\"") || arg.contains("'")) {
                    fullCmd += " \"" + arg.replace("\"", "\\\"") + "\""
                } else {
                    fullCmd += " " + arg
                }
            }
            TaskIO.appendLog(taskId, "Executing command: ${fullCmd}")

            if (args.size == 0) {
                // 没有参数的情况
                let process = launch(command, stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                let (exitCode, stdout, stderr) = process.waitOutput()
                return (Int32(exitCode), stdout, stderr)
            } else if (args.size == 1) {
                // 一个参数的情况
                let process = launch(command, args[0], stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                let (exitCode, stdout, stderr) = process.waitOutput()
                return (Int32(exitCode), stdout, stderr)
            } else if (args.size == 2) {
                // 两个参数的情况
                let process = launch(command, args[0], args[1], stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                let (exitCode, stdout, stderr) = process.waitOutput()
                return (Int32(exitCode), stdout, stderr)
            } else if (args.size == 3) {
                // 三个参数的情况
                let process = launch(command, args[0], args[1], args[2], stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                let (exitCode, stdout, stderr) = process.waitOutput()
                return (Int32(exitCode), stdout, stderr)
            } else if (args.size == 4) {
                // 四个参数的情况
                let process = launch(command, args[0], args[1], args[2], args[3], stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                let (exitCode, stdout, stderr) = process.waitOutput()
                return (Int32(exitCode), stdout, stderr)
            } else {
                // 更多参数的情况，暂时返回错误
                TaskIO.appendLog(taskId, "ERROR: Too many arguments for command: ${fullCmd}")
                return (1, Array<UInt8>(), Array<UInt8>())
            }
        } catch (e: Exception) {
            TaskIO.appendLog(taskId, "ERROR: Error executing command '${command}': ${e.message}")
            return (1, Array<UInt8>(), Array<UInt8>())
        }
    }

    /**
     * 获取当前时间戳（毫秒）
     */
    private static func getCurrentTimeMillis(): Int64 {
        return DateTime.now().toUnixTimeStamp().toSeconds() * 1000
    }

    /**
     * 设置默认元数据
     */
    private static func setDefaultMetadata(metadata: PluginMetadata, filePath: String, pluginType: String): Unit {
        let fileNameOnly = Path(filePath).fileName.toString()
        metadata.name = fileNameOnly
        metadata.namespace = "plugin." + pluginType.toAsciiLower() + "." + fileNameOnly.replace(".ts", "")
        metadata.version = "1.0"
        metadata.description = "${pluginType} plugin"
        metadata.author = "Unknown"
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
            // 构建 deno 命令
            let cmd = "deno run --allow-read '${filePath}'"
            TaskIO.appendLog(taskId, "Executing: ${cmd}")

            // 启动进程
            let process = launch("sh", "-c", cmd,
                stdIn: ProcessRedirect.Pipe,
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe)

            // 写入 plugin_info 请求到 stdin
            let inputJson = "{\"action\":\"plugin_info\",\"pluginType\":\"\"}\n"
            process.stdInPipe.write(inputJson.toArray())
            process.stdInPipe.flush()

            // 读取 stdout
            let reader = StringReader<InputStream>(process.stdOutPipe)
            var output = ""
            for (line in reader.lines()) {
                output += line + "\n"
            }

            // 等待进程完成
            let exitCode = process.wait()

            // 读取 stderr
            let stderrReader = StringReader<InputStream>(process.stdErrPipe)
            let stderrContent = stderrReader.readToEnd()

            return (Int32(exitCode), output.toArray(), stderrContent.toArray())
        } catch (e: Exception) {
            TaskIO.appendLog(taskId, "ERROR: executePluginInfoWithStdio failed: ${e.message}")
            return (1, Array<UInt8>(), Array<UInt8>())
        }
    }
}
