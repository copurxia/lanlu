package lrr4cj.services

import stdx.log.*
import std.fs.*
import std.process.*
import std.time.*
import std.convert.*
import stdx.encoding.json.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*
import cjoy.json.*
import dotenv.Dotenv

/**
 * 插件扫描任务：扫描并注册插件文件（Metadata、Login、Download 插件）
 */
public class ScanPluginsTaskRunner {
    // 插件路径配置
    private static var pluginPath: Path

    // 静态初始化器
    static init() {
        let config = Dotenv.createConfig()
        let pluginPathStr = config.read("PLUGIN_PATH", "./plugins")
        pluginPath = canonicalize(pluginPathStr)
        FileUtils.ensureDirectoryExists(pluginPath)
    }

    public static func run(taskId: Int64, _: String): Unit {
        let logger = getLogger("scan_plugins_task")
        TaskIO.appendLog(taskId, "scan_plugins task started")

        MinionModel.updateTaskProgress(taskId, 10, "Starting plugin scan")

        let result = scanPlugins()

        if (result.errorCount > 0) {
            logger.warn("scan_plugins completed with errors", ("error_count", result.errorCount.toString()))
            let errorJson = "{\"success\":1,\"processed_count\":${result.processedCount},\"total_found\":${result.totalFound},\"error_count\":${result.errorCount}}"
            MinionModel.updateTaskProgress(taskId, 100, "Plugin scan completed with ${result.errorCount} errors")
            MinionModel.completeTask(taskId, errorJson)
            TaskIO.writeOutput(taskId, errorJson)
            TaskIO.appendLog(taskId, "scan_plugins completed with errors: processed=${result.processedCount}, errors=${result.errorCount}")
        } else {
            let successJson = "{\"success\":1,\"processed_count\":${result.processedCount},\"total_found\":${result.totalFound},\"error_count\":0}"
            MinionModel.updateTaskProgress(taskId, 100, "Plugin scan completed")
            MinionModel.completeTask(taskId, successJson)
            TaskIO.writeOutput(taskId, successJson)
            TaskIO.appendLog(taskId, "scan_plugins completed: processed=${result.processedCount}, total=${result.totalFound}")
        }
    }

    /**
     * 扫描插件文件
     */
    private static func scanPlugins(): ScanResultData {
        let startTime = getCurrentTimeMillis()
        var processedCount: Int64 = 0
        var errorCount: Int64 = 0
        var errors: Array<String> = Array<String>()

        let logger = getLogger("scan_plugins")
        logger.debug("Starting plugin scan")
        logger.debug("Plugin path", ("path", pluginPath.toString()))

        // 检查目录是否存在
        if (!directoryExists(pluginPath.toString())) {
            logger.error("Plugin directory does not exist", ("path", pluginPath.toString()))
            return ScanResultData(0, 0, 1, ["Plugin directory does not exist: ${pluginPath.toString()}"])
        }

        // 扫描插件文件
        let pluginFiles = findPluginFiles(pluginPath.toString())
        logger.info("Found plugin files to process", ("count", pluginFiles.size.toString()))

        // 处理每个插件文件
        for (pluginFile in pluginFiles) {
            try {
                logger.debug("Processing plugin", ("file", pluginFile))
                let result = processPluginFile(pluginFile)

                if (result.success) {
                    processedCount++
                    logger.debug("Successfully processed plugin", ("file", pluginFile), ("archive_id", result.archiveId))
                } else {
                    errorCount++
                    let errorMsg = "Failed to process plugin ${pluginFile}: ${result.error}"
                    errors = addError(errors, errorMsg)
                    logger.error(errorMsg)
                }
            } catch (e: Exception) {
                errorCount++
                let errorMsg = "Error processing plugin ${pluginFile}: ${e.message}"
                errors = addError(errors, errorMsg)
                logger.error(errorMsg)
            }
        }

        let endTime = getCurrentTimeMillis()
        let duration = endTime - startTime

        logger.info("Plugin scan completed",
            ("processed", processedCount.toString()),
            ("errors", errorCount.toString()),
            ("duration_ms", duration.toString()))

        return ScanResultData(processedCount, pluginFiles.size, 0, errors)
    }

    /**
     * 查找插件文件
     */
    private static func findPluginFiles(dirPath: String): Array<String> {
        var result: Array<String> = Array<String>()

        try {
            if (!directoryExists(dirPath)) {
                return result
            }

            let entries = listDirectory(dirPath)
            let logger = getLogger("scan_plugins")
            logger.debug("Scanning plugin directory", ("directory", dirPath), ("entries", entries.size.toString()))

            // 扫描EHentai相关的插件类型目录
            let pluginTypes = ["Metadata", "Login", "Download"]

            for (entry in entries) {
                let fullPath = joinPath(dirPath, entry)

                if (directoryExists(fullPath)) {
                    // 检查是否是插件类型目录
                    for (pluginType in pluginTypes) {
                        if (entry == pluginType) {
                            let pluginFiles = findPluginFilesInType(fullPath)
                            result = combineArrays(result, pluginFiles)
                            break
                        }
                    }
                }
            }
        } catch (e: Exception) {
            let logger = getLogger("scan_plugins")
            logger.error("Error scanning plugin directory", ("directory", dirPath), ("error", e.message))
        }

        return result
    }

    /**
     * 在指定类型目录中查找插件文件
     */
    private static func findPluginFilesInType(typeDirPath: String): Array<String> {
        var result: Array<String> = Array<String>()

        try {
            let entries = listDirectory(typeDirPath)

            for (entry in entries) {
                let fullPath = joinPath(typeDirPath, entry)

                if (fileExists(fullPath) && entry.endsWith(".pm") && entry.contains("EHentai")) {
                    result = addFile(result, fullPath)
                    let logger = getLogger("scan_plugins")
                    logger.debug("Found EHentai plugin", ("file", fullPath))
                }
            }
        } catch (e: Exception) {
            let logger = getLogger("scan_plugins")
            logger.error("Error scanning plugin type directory", ("directory", typeDirPath), ("error", e.message))
        }

        return result
    }

    /**
     * 处理插件文件
     */
    private static func processPluginFile(filePath: String): ProcessResultData {
        try {
            // 解析插件路径获取类型和文件名
            let pathParts = filePath.split("/")
            let fileName = pathParts[pathParts.size - 1]
            let pluginType = if (pathParts.size >= 2) { pathParts[pathParts.size - 2] } else { "Unknown" }

            let logger = getLogger("scan_plugins")
            logger.debug("Processing plugin file", ("file", fileName), ("type", pluginType), ("path", filePath))

            // 使用Perl解析插件元数据
            let pluginMetadata = parsePluginMetadataWithPerl(filePath, pluginType)

            // 检查插件是否已存在（通过namespace检查）
            if (PluginDao.exists(pluginMetadata.namespace)) {
                logger.debug("Plugin already exists", ("namespace", pluginMetadata.namespace))
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
            pluginData.enabled = true
            pluginData.installed = true
            // config字段已移除，现在配置存储在parameters中
            pluginData.created_at = DateTime.now().toUnixTimeStamp().toSeconds().toString()
            pluginData.updated_at = pluginData.created_at

            // 保存到数据库
            if (PluginDao.create(pluginData)) {
                logger.info("Successfully registered plugin: ${pluginData.namespace} (${pluginData.name})")
                return ProcessResultData(true, pluginData.namespace, "")
            } else {
                return ProcessResultData(false, "", "Failed to save plugin to database")
            }
        } catch (e: Exception) {
            return ProcessResultData(false, "", "Error processing plugin file: ${e.message}")
        }
    }

    /**
     * 使用Perl解析插件元数据
     */
    private static func parsePluginMetadataWithPerl(filePath: String, pluginType: String): PluginMetadata {
        var metadata = PluginMetadata()

        try {
            let perlScript = """
            use strict;
            use warnings;
            use JSON;

            my \$plugin_file = '${escapeJson(filePath)}';
            my \$plugin_class = '';

            # 从文件路径推断类名
            \$plugin_file =~ s.*/([^/]+)\\.pm.\\$1.;
            my \$full_class = "LANraragi::Plugin::${escapeJson(pluginType)}::\$plugin_file";

            eval {
                require \$plugin_file;
                import \$full_class;
                if (\$full_class->can('plugin_info')) {
                    my %info = \$full_class->plugin_info();
                    print encode_json(\\%info);
                } else {
                    # 如果没有plugin_info方法，使用文件名作为默认信息
                    print '{"name":"' . \$plugin_file . '","namespace":"lanraragi.ehentai.' . lc(\$plugin_file) . '","version":"1.0","description":"EHentai plugin","author":"Unknown","tags":"","permissions":""}';
                }
            };

            if (\$@) {
                print STDERR "Error loading plugin: \$@";
                # 即使出错也返回基本信息
                print '{"name":"' . \$plugin_file . '","namespace":"lanraragi.ehentai.' . lc(\$plugin_file) . '","version":"1.0","description":"EHentai plugin","author":"Unknown","tags":"","permissions":""}';
            }
            """

            let (exitCode, stdout, stderr) = executeWithOutput("perl", ["-e", perlScript])

            if (exitCode == 0 && stdout.size > 0) {
                let jsonStr = String.fromUtf8(stdout)
                let json = JsonValue.fromStr(jsonStr)
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
                    case _ =>
                        // 解析失败，使用文件名作为默认信息
                        let fileName = Path(filePath).fileName.toString()
                        metadata.name = fileName
                        metadata.namespace = "lanraragi.ehentai." + fileName
                        metadata.version = "1.0"
                        metadata.description = "EHentai plugin"
                        metadata.author = "Unknown"
                }
            } else {
                // 执行失败，使用文件名作为默认信息
                let fileName = Path(filePath).fileName.toString()
                metadata.name = fileName
                metadata.namespace = "lanraragi.ehentai." + fileName
                metadata.version = "1.0"
                metadata.description = "EHentai plugin"
                metadata.author = "Unknown"
                let logger = getLogger("scan_plugins")
                logger.warn("Failed to execute plugin metadata parsing", ("file", filePath), ("stderr", String.fromUtf8(stderr)))
            }
        } catch (e: Exception) {
            let logger = getLogger("scan_plugins")
            logger.error("Error parsing plugin metadata", ("file", filePath), ("error", e.message))
            // 异常情况下，使用文件名作为默认信息
            let fileName = Path(filePath).fileName.toString()
            metadata.name = fileName
            metadata.namespace = "lanraragi.ehentai." + fileName
            metadata.version = "1.0"
            metadata.description = "EHentai plugin"
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

    private static func escapeJson(value: String): String {
        var escaped = value
        escaped = escaped.replace("\\", "\\\\")
        escaped = escaped.replace("\"", "\\\"")
        escaped = escaped.replace("\b", "\\b")
        escaped = escaped.replace("\f", "\\f")
        escaped = escaped.replace("\n", "\\n")
        escaped = escaped.replace("\r", "\\r")
        escaped = escaped.replace("\t", "\\t")
        return escaped
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
    private static func executeWithOutput(command: String, args: Array<String>): (Int32, Array<UInt8>, Array<UInt8>) {
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
            let logger = getLogger("scan_plugins")
            logger.info("Executing command with args: ${fullCmd}")

            if (args.size == 0) {
                // 没有参数的情况
                let process = launch(command, stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            } else if (args.size == 1) {
                // 一个参数的情况
                let process = launch(command, args[0], stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            } else if (args.size == 2) {
                // 两个参数的情况
                let process = launch(command, args[0], args[1], stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            } else if (args.size == 3) {
                // 三个参数的情况
                let process = launch(command, args[0], args[1], args[2], stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            } else if (args.size == 4) {
                // 四个参数的情况
                let process = launch(command, args[0], args[1], args[2], args[3], stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            } else {
                // 更多参数的情况，暂时返回错误
                let logger = getLogger("scan_plugins")
                logger.error("Too many arguments for command: ${fullCmd}")
                return (1, Array<UInt8>(), Array<UInt8>())
            }
        } catch (e: Exception) {
            let logger = getLogger("scan_plugins")
            logger.error("Error executing command '${command}': ${e.message}")
            return (1, Array<UInt8>(), Array<UInt8>())
        }
    }

    private static func combineArrays(arr1: Array<String>, arr2: Array<String>): Array<String> {
        return DirectoryScanner.combineArrays(arr1, arr2)
    }

    private static func addFile(arr: Array<String>, file: String): Array<String> {
        return DirectoryScanner.addFileToArray(arr, file)
    }

    /**
     * 获取当前时间戳（毫秒）
     */
    private static func getCurrentTimeMillis(): Int64 {
        return DateTime.now().toUnixTimeStamp().toSeconds() * 1000
    }
}
