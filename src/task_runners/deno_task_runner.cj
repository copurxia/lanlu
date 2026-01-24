package lrr4cj.task_runners

import std.process.*
import std.collection.*
import std.fs.*
import std.io.*
import std.convert.*
import std.sync.*
import std.time.*
import stdx.encoding.json.*
import stdx.log.*
import lrr4cj.dao.*
import lrr4cj.kv.*
import lrr4cj.models.*
import lrr4cj.utils.*

/**
 * Deno 任务执行结果
 */
public class DenoExecutionResult {
    public var success: Bool = false
    public var error: String = ""
    public var output: String = ""
    public var cookiesJson: String = ""
    public var exitCode: Int32 = 0

    public init(success: Bool, error: String, output: String) {
        this.success = success
        this.error = error
        this.output = output
    }

    public init(success: Bool, error: String, output: String, cookiesJson: String, exitCode: Int32) {
        this.success = success
        this.error = error
        this.output = output
        this.cookiesJson = cookiesJson
        this.exitCode = exitCode
    }
}

/**
 * Deno 任务执行器
 * 统一处理所有 Deno 插件执行
 */
public class DenoTaskRunner {

    /**
     * 任务入口
     */
    public static func run(taskId: Int64, parameters: String): Unit {
        TaskIO.appendLog(taskId, "deno_task started")
        TaskModel.updateTaskProgress(taskId, 1, "Deno任务开始")

        // 解析参数
        let (pluginNamespace, pluginType, _, groupId, archiveId, oneshotParam, extraParams, url, parentTaskIdRaw) = parseParameters(parameters)
        let parentTaskId = parseInt64OrZero(parentTaskIdRaw)

        if (pluginNamespace.size == 0 || pluginType.size == 0) {
            fail(taskId, "pluginNamespace and pluginType are required")
            return
        }

        // 获取 KV store 引用
        let kvStore = TaskGroupKVStore.getInstance()
        if (groupId.size > 0) {
            kvStore.acquireGroup(groupId)
        }

        try {
            // 获取插件
            let plugin = PluginDao.getPluginByNamespace(pluginNamespace)
            if (plugin.namespace.size == 0) {
                fail(taskId, "Plugin not found: ${pluginNamespace}")
                return
            }

            TaskDao.updateTaskPluginNamespace(taskId, plugin.namespace)
            TaskModel.updateTaskProgress(taskId, 10, "准备插件脚本")

            // 准备插件脚本
            if (!ensurePluginScriptReady(plugin, pluginType)) {
                fail(taskId, "Failed to prepare plugin script")
                return
            }

            // 处理登录依赖
            var loginCookiesJson = ""
            let effectiveLoginFrom = plugin.login_from.trimAscii()
            if (effectiveLoginFrom.size > 0) {
                TaskModel.updateTaskProgress(taskId, 20, "处理登录依赖")
                let loginResult = handleLoginDependency(taskId, effectiveLoginFrom, groupId, kvStore)
                if (!loginResult.success) {
                    fail(taskId, "Login plugin failed: ${loginResult.error}")
                    return
                }
                loginCookiesJson = loginResult.cookiesJson
            }

            TaskModel.updateTaskProgress(taskId, 40, "执行插件")

            // 根据类型执行插件
            let result = match (pluginType) {
                case "Metadata" => executeMetadataPlugin(taskId, plugin, archiveId, oneshotParam, extraParams, loginCookiesJson)
                case "Download" => executeDownloadPlugin(taskId, plugin, url, loginCookiesJson, parentTaskId)
                case "Login" => executeLoginPluginDirect(taskId, plugin)
                case "Script" => executeScriptPlugin(taskId, plugin, oneshotParam, extraParams, loginCookiesJson)
                case _ =>
                    fail(taskId, "Unknown plugin type: ${pluginType}")
                    return
            }

            if (!result.success) {
                fail(taskId, result.error)
                return
            }

            TaskModel.updateTaskProgress(taskId, 100, "Deno任务完成")
            TaskModel.completeTask(taskId, "deno_task completed")
            TaskIO.writeOutput(taskId, result.output)

        } catch (e: Exception) {
            fail(taskId, e.message)
        } finally {
            // 释放 KV store 引用
            if (groupId.size > 0) {
                kvStore.releaseGroup(groupId)
            }
        }
    }

    private static func fail(taskId: Int64, message: String): Unit {
        let msg = if (message.size == 0) { "Unknown error" } else { message }
        TaskIO.appendLog(taskId, "FAILED: ${msg}")
        TaskModel.failTask(taskId, msg)
        TaskIO.writeOutput(taskId, "{\"success\":0,\"error\":\"${escapeJson(msg)}\"}")
    }

    private static func parseParameters(parameters: String): (String, String, String, String, String, String, String, String, String) {
        var pluginNamespace = ""
        var pluginType = ""
        var action = "run"
        var groupId = ""
        var archiveId = ""
        var oneshotParam = ""
        var extraParams = ""
        var url = ""
        var parentTaskId = ""

        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return (pluginNamespace, pluginType, action, groupId, archiveId, oneshotParam, extraParams, url, parentTaskId)
        }

        try {
            let jsonVal = JsonValue.fromStr(trimmed)
            match (jsonVal) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    pluginNamespace = getJsonStringValue(fields, "pluginNamespace")
                    pluginType = getJsonStringValue(fields, "pluginType")
                    action = getJsonStringValue(fields, "action")
                    if (action.size == 0) { action = "run" }
                    groupId = getJsonStringValue(fields, "groupId")
                    archiveId = getJsonStringValue(fields, "archiveId")
                    oneshotParam = getJsonStringValue(fields, "oneshotParam")
                    extraParams = getJsonStringValue(fields, "extraParams")
                    url = getJsonStringValue(fields, "url")
                    parentTaskId = getJsonStringValue(fields, "parentTaskId")
                case _ => ()
            }
        } catch (_: Exception) {}

        return (pluginNamespace, pluginType, action, groupId, archiveId, oneshotParam, extraParams, url, parentTaskId)
    }

    private static func parseInt64OrZero(s: String): Int64 {
        let trimmed = s.trimAscii()
        if (trimmed.size == 0) { return 0 }
        try {
            return Int64.parse(trimmed)
        } catch (_: Exception) {
            return 0
        }
    }

    private static func getJsonStringValue(fields: HashMap<String, JsonValue>, key: String): String {
        match (fields.get(key)) {
            case Some(v) =>
                match (v) {
                    case s: JsonString => return s.getValue().trimAscii()
                    case _ => return v.toString().trimAscii()
                }
            case None => return ""
        }
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

    /**
     * 准备插件脚本
     */
    private static func ensurePluginScriptReady(plugin: PluginData, scriptName: String): Bool {
        try {
            let pluginsRoot = Path(PluginPaths.getPluginRuntimeRoot())
            FileUtils.ensureDirectoryExists(pluginsRoot)

            // 确保根目录有 base_plugin.ts（从 plugins 目录复制到缓存目录）
            let basePluginSource = Path("./plugins/base_plugin.ts")
            let basePluginTarget = Path("${pluginsRoot.toString()}/base_plugin.ts")
            if (!exists(basePluginSource)) {
                getLogger("deno_task").error("缺少基础插件文件", ("path", basePluginSource.toString()))
                return false
            }
            if (!exists(basePluginTarget)) {
                copy(basePluginSource, to: basePluginTarget, overwrite: false)
            }

            // 创建插件运行时目录（按命名空间）
            let pluginDir = Path("${pluginsRoot.toString()}/${plugin.namespace}")
            FileUtils.ensureDirectoryExists(pluginDir)

            // 复制插件文件到运行时目录
            let targetFile = Path("${pluginDir.toString()}/${scriptName}.ts")
            // 直接使用 entry 构建源路径（支持子目录）
            let sourcePath = Path(PluginPaths.buildPluginFilePath(plugin.plugin_type, plugin.entry))
            if (!exists(sourcePath)) {
                getLogger("deno_task").error("源插件文件不存在", ("path", sourcePath.toString()))
                return false
            }

            copy(sourcePath, to: targetFile, overwrite: true)
            return true
        } catch (e: Exception) {
            getLogger("deno_task").error("准备插件文件失败", ("error", e.message))
            return false
        }
    }

    /**
     * 处理登录依赖
     */
    private static func handleLoginDependency(
        taskId: Int64,
        loginNamespace: String,
        groupId: String,
        kvStore: TaskKVStore
    ): DenoExecutionResult {
        let logger = getLogger("deno_task")

        // 先检查 KV store 中是否有缓存的 cookies
        if (groupId.size > 0) {
            match (kvStore.get(groupId, "login_cookies_${loginNamespace}")) {
                case Some(cached) =>
                    TaskIO.appendLog(taskId, "Using cached login cookies from KV store")
                    return DenoExecutionResult(true, "", "", cached, 0)
                case None => ()
            }
        }

        // 获取登录插件
        let loginPlugin = PluginDao.getPluginByNamespace(loginNamespace)
        if (loginPlugin.namespace.size == 0) {
            return DenoExecutionResult(false, "Login plugin not found: ${loginNamespace}", "", "", 1)
        }

        // 准备登录插件脚本
        if (!ensurePluginScriptReady(loginPlugin, "Login")) {
            return DenoExecutionResult(false, "Failed to prepare login plugin script", "", "", 1)
        }

        // 执行登录插件
        let loginResult = executeLoginPluginDirect(taskId, loginPlugin)
        if (!loginResult.success) {
            return loginResult
        }

        // 提取 cookies
        let cookiesJson = extractLoginCookiesJson(loginResult.output)
        if (cookiesJson.size == 0) {
            logger.warn("Login plugin did not return cookies", ("namespace", loginNamespace))
        }

        // 缓存到 KV store
        if (groupId.size > 0 && cookiesJson.size > 0) {
            kvStore.set(groupId, "login_cookies_${loginNamespace}", cookiesJson, 3600)
        }

        return DenoExecutionResult(true, "", loginResult.output, cookiesJson, 0)
    }

    /**
     * 从登录插件输出提取 cookies JSON
     */
    private static func extractLoginCookiesJson(output: String): String {
        if (output.trimAscii().size == 0) {
            return ""
        }

        try {
            let jsonVal = JsonValue.fromStr(output)
            match (jsonVal) {
                case jsonObj: JsonObject =>
                    let fields = jsonObj.getFields()
                    if (!getJsonBool(fields, "success")) {
                        return ""
                    }
                    if (fields.contains("data")) {
                        match (fields["data"]) {
                            case dataObj: JsonObject =>
                                let dataFields = dataObj.getFields()
                                if (dataFields.contains("cookies")) {
                                    match (dataFields["cookies"]) {
                                        case cookiesArr: JsonArray =>
                                            return cookiesArr.toString()
                                        case _ => ()
                                    }
                                }
                            case _ => ()
                        }
                    }
                case _ => ()
            }
        } catch (_: Exception) {}

        return ""
    }

    private static func getJsonBool(fields: HashMap<String, JsonValue>, key: String): Bool {
        match (fields.get(key)) {
            case Some(v) =>
                match (v) {
                    case b: JsonBool => return b.getValue()
                    case s: JsonString =>
                        let val = s.getValue()
                        return val == "true" || val == "1"
                    case _ =>
                        let val = v.toString()
                        return val == "true" || val == "1"
                }
            case None => return false
        }
    }

    /**
     * 构建 Deno 权限参数
     */
    private static func buildDenoPermissions(plugin: PluginData, _: String): ArrayList<String> {
        var denoArgs = ArrayList<String>()
        denoArgs.add("run")
        // Avoid ANSI color codes in captured logs/messages; they can contain raw ESC
        // control characters which break JSON if not escaped.
        denoArgs.add("--no-color")

        // 默认给予插件目录的读写权限
        let pluginDir = "${PluginPaths.getPluginRuntimeRoot()}/${plugin.namespace}"
        denoArgs.add("--allow-read=${pluginDir}")
        denoArgs.add("--allow-write=${pluginDir}")
        denoArgs.add("--allow-read=${PluginPaths.getPluginRuntimeRoot()}")

        // 解析插件声明的权限（逗号分隔的键值对格式：net=e-hentai.org,read=./data/thumb）
        let permissionsStr = plugin.permissions.trimAscii()
        if (permissionsStr.size > 0) {
            var netHosts = ArrayList<String>()
            var allowNetAll = false

            let parts = permissionsStr.split(",")
            for (perm in parts) {
                let trimmed = perm.trimAscii()
                if (trimmed.size > 0) {
                    allowNetAll = processPermission(trimmed, denoArgs, netHosts, allowNetAll)
                }
            }

            // 汇总网络权限
            if (allowNetAll) {
                denoArgs.add("--allow-net")
            } else if (netHosts.size > 0) {
                let joinedHosts = String.join(netHosts.toArray(), delimiter: ",")
                denoArgs.add("--allow-net=${joinedHosts}")
            }
        }

        return denoArgs
    }

    private static func normalizePermission(permission: String): String {
        var perm = permission.trimAscii()
        if (perm.startsWith("\"") && perm.endsWith("\"") && perm.size >= 2) {
            perm = perm[1..perm.size - 1]
        }
        return perm
    }

    private static func processPermission(
        perm: String,
        denoArgs: ArrayList<String>,
        netHosts: ArrayList<String>,
        allowNetAll: Bool
    ): Bool {
        var netAll = allowNetAll
        if (perm.contains("=")) {
            let parts = perm.split("=", 2)
            if (parts.size == 2) {
                let permType = normalizePermission(parts[0])
                let permValue = normalizePermission(parts[1])
                if (permType == "net" && permValue.size > 0) {
                    netHosts.add(permValue)
                } else if (permType == "read") {
                    denoArgs.add("--allow-read=${permValue}")
                } else if (permType == "write") {
                    denoArgs.add("--allow-write=${permValue}")
                } else if (permType == "env") {
                    denoArgs.add("--allow-env=${permValue}")
                } else if (permType == "run") {
                    denoArgs.add("--allow-run=${permValue}")
                }
            }
        } else {
            if (perm == "net") { netAll = true }
            else if (perm == "read") { denoArgs.add("--allow-read") }
            else if (perm == "write") { denoArgs.add("--allow-write") }
            else if (perm == "env") { denoArgs.add("--allow-env") }
            else if (perm == "run") { denoArgs.add("--allow-run") }
            else if (perm == "ffi") { denoArgs.add("--allow-ffi") }
            else if (perm == "hrtime") { denoArgs.add("--allow-hrtime") }
        }
        return netAll
    }

    private static func escapeShellArg(arg: String): String {
        if (arg.size == 0) { return "''" }
        let safe = arg.replace("'", "'\"'\"'")
        return "'${safe}'"
    }

    /**
     * 构建 stdin JSON 输入
     */
    private static func buildStdinJson(
        action: String,
        pluginType: String,
        pluginDir: String,
        archiveId: String,
        archiveTitle: String,
        existingTags: String,
        thumbnailHash: String,
        oneshotParam: String,
        params: String,
        loginCookies: String,
        url: String
    ): String {
        var json = JsonObject()
        let fields = json.getFields()
        fields["action"] = JsonString(action)
        fields["pluginType"] = JsonString(pluginType)
        fields["pluginDir"] = JsonString(pluginDir)
        fields["archiveId"] = JsonString(archiveId)
        fields["archiveTitle"] = JsonString(archiveTitle)
        fields["existingTags"] = JsonString(existingTags)
        fields["thumbnailHash"] = JsonString(thumbnailHash)
        fields["oneshotParam"] = JsonString(oneshotParam)
        fields["url"] = JsonString(url)

        // params 是 JSON 字符串，需要解析后嵌入
        if (params.trimAscii().size > 0) {
            try {
                let paramsVal = JsonValue.fromStr(params)
                fields["params"] = paramsVal
            } catch (_: Exception) {
                fields["params"] = JsonObject()
            }
        } else {
            fields["params"] = JsonObject()
        }

        // loginCookies 是 JSON 数组字符串
        if (loginCookies.trimAscii().size > 0) {
            try {
                let cookiesVal = JsonValue.fromStr(loginCookies)
                fields["loginCookies"] = cookiesVal
            } catch (_: Exception) {
                fields["loginCookies"] = JsonArray()
            }
        } else {
            fields["loginCookies"] = JsonArray()
        }

        return json.toString()
    }

    /**
     * 解析插件输出的 NDJSON 消息
     * 返回: (type, progress, message, success, data/error)
     */
    private static func parsePluginMessage(line: String): (String, Int32, String, Bool, String) {
        let trimmed = line.trimAscii()
        if (trimmed.size == 0) {
            return ("", 0, "", false, "")
        }

        try {
            let jsonVal = JsonValue.fromStr(trimmed)
            match (jsonVal) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    let msgType = getJsonStringValue(fields, "type")

                    match (msgType) {
                        case "progress" =>
                            let progress = getJsonIntValue(fields, "progress")
                            let message = getJsonStringValue(fields, "message")
                            return ("progress", progress, message, false, "")
                        case "log" =>
                            let level = getJsonStringValue(fields, "level")
                            let message = getJsonStringValue(fields, "message")
                            return ("log", 0, "[${level}] ${message}", false, "")
                        case "data" =>
                            let key = getJsonStringValue(fields, "key")
                            let value = match (fields.get("value")) {
                                case Some(v) => v.toString()
                                case None => ""
                            }
                            return ("data", 0, key, false, value)
                        case "result" =>
                            let success = getJsonBool(fields, "success")
                            let data = match (fields.get("data")) {
                                case Some(v) => v.toString()
                                case None => ""
                            }
                            let error = getJsonStringValue(fields, "error")
                            return ("result", 0, "", success, if (success) { data } else { error })
                        case _ =>
                            return ("unknown", 0, trimmed, false, "")
                    }
                case _ =>
                    return ("raw", 0, trimmed, false, "")
            }
        } catch (_: Exception) {
            return ("raw", 0, trimmed, false, "")
        }
    }

    private static func getJsonIntValue(fields: HashMap<String, JsonValue>, key: String): Int32 {
        match (fields.get(key)) {
            case Some(v) =>
                match (v) {
                    case n: JsonInt => return Int32(n.getValue())
                    case n: JsonFloat => return Int32(n.getValue())
                    case s: JsonString =>
                        try {
                            return Int32.parse(s.getValue())
                        } catch (_: Exception) {
                            return 0
                        }
                    case _ => return 0
                }
            case None => return 0
        }
    }

    /**
     * 通过 stdio 执行 Deno 插件
     * 支持实时进度回报和流式数据输出
     */
    private static func executeWithStdio(
        taskId: Int64,
        command: String,
        args: ArrayList<String>,
        inputJson: String,
        parentTaskId: Int64
    ): DenoExecutionResult {
        let logger = getLogger("deno_task")

        try {
            // Launch directly (avoid sh -c), and drain stderr concurrently to prevent pipe deadlocks.
            let process = launch(command, args.toArray(),
                stdIn: ProcessRedirect.Pipe,
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe)

            let stderrDone: AtomicInt32 = AtomicInt32(0)
            let stderrFile = Path("${PluginPaths.getPluginTempRoot()}/deno_stderr_${taskId.toString()}_${DateTime.now().toUnixTimeStamp().toSeconds().toString()}.log")
            spawn {
                try {
                    let stderrReader = StringReader<InputStream>(process.stdErrPipe)
                    let content = stderrReader.readToEnd()
                    try {
                        FileUtils.ensureDirectoryExists(stderrFile.parent)
                        let f = File(stderrFile, Write)
                        f.write(content.toArray())
                        f.close()
                    } catch (_: Exception) {}
                } catch (_: Exception) {
                    // Best-effort.
                }
                stderrDone.store(1)
            }

            // 写入 JSON 到 stdin 并刷新
            let inputBytes = inputJson.toArray()
            process.stdInPipe.write(inputBytes)
            process.stdInPipe.write("\n".toArray())  // 添加换行符表示输入结束
            process.stdInPipe.flush()

            // 逐行读取 stdout 并解析 NDJSON
            let reader = StringReader<InputStream>(process.stdOutPipe)
            var finalSuccess = false
            var finalData = ""
            var finalError = ""
            var dataCollector = ArrayList<String>()

            for (line in reader.lines()) {
                let trimmed = line.trimAscii()
                if (trimmed.size == 0) {
                    continue
                }

                let (msgType, progress, message, success, data) = parsePluginMessage(trimmed)

                match (msgType) {
                    case "progress" =>
                        TaskModel.updateTaskProgress(taskId, progress, message)
                        TaskIO.appendLog(taskId, "[PROGRESS] ${progress}% - ${message}")
                        mirrorParentProgress(parentTaskId, taskId, progress, message)
                    case "log" =>
                        TaskIO.appendLog(taskId, message)
                        mirrorParentLog(parentTaskId, taskId, message)
                    case "data" =>
                        // message 是 key，data 是 value
                        TaskIO.appendLog(taskId, "[DATA] ${message}")
                        mirrorParentLog(parentTaskId, taskId, "[DATA] ${message}")
                        dataCollector.add(data)
                    case "result" =>
                        finalSuccess = success
                        if (success) {
                            finalData = data
                        } else {
                            finalError = data
                        }
                    case _ =>
                        // 未知格式，作为原始日志记录
                        TaskIO.appendLog(taskId, "[RAW] ${trimmed}")
                }
            }

            // 等待进程完成
            let exitCode = process.wait()

            // Wait for stderr drain to finish.
            while (stderrDone.load() == 0) {
                sleep(Duration.millisecond * 10)
            }
            var capturedStderr = ""
            try {
                if (exists(stderrFile)) {
                    let f = File(stderrFile, Read)
                    let r = StringReader<InputStream>(f)
                    capturedStderr = r.readToEnd()
                    f.close()
                    try { remove(stderrFile) } catch (_: Exception) {}
                }
            } catch (_: Exception) {}

            if (capturedStderr.trimAscii().size > 0) {
                TaskIO.appendLog(taskId, "[STDERR] ${capturedStderr}")
                if (!finalSuccess && finalError.size == 0) {
                    finalError = capturedStderr
                }
            }

            // 构建最终输出 JSON
            var outputJson = if (finalSuccess) {
                if (finalData.size > 0) {
                    "{\"success\":true,\"data\":${finalData}}"
                } else {
                    "{\"success\":true}"
                }
            } else {
                "{\"success\":false,\"error\":\"${escapeJson(finalError)}\"}"
            }

            return DenoExecutionResult(finalSuccess, finalError, outputJson, "", Int32(exitCode))

        } catch (e: Exception) {
            logger.error("executeWithStdio failed", ("error", e.message))
            return DenoExecutionResult(false, e.message, "", "", 1)
        }
    }

    /**
     * 执行登录插件
     */
    private static func executeLoginPluginDirect(taskId: Int64, plugin: PluginData): DenoExecutionResult {
        let pluginDir = "${PluginPaths.getPluginRuntimeRoot()}/${plugin.namespace}"
        let pluginFile = "${pluginDir}/Login.ts"

        if (!exists(pluginFile)) {
            return DenoExecutionResult(false, "Plugin file not found", "", "", 1)
        }

        let denoArgs = buildDenoPermissions(plugin, pluginFile)
        denoArgs.add(pluginFile)

        // 构建 stdin JSON
        let paramsJson = buildPluginParametersJson(plugin)
        let inputJson = buildStdinJson(
            "run",
            "Login",
            pluginDir,
            "",
            "",
            "",
            "",
            "",
            paramsJson,
            "",
            ""
        )

        return executeWithStdio(taskId, "deno", denoArgs, inputJson, 0)
    }

    /**
     * 执行脚本插件（手动触发/cron）
     */
    private static func executeScriptPlugin(
        taskId: Int64,
        plugin: PluginData,
        oneshotParam: String,
        extraParams: String,
        loginCookiesJson: String
    ): DenoExecutionResult {
        let pluginDir = "${PluginPaths.getPluginRuntimeRoot()}/${plugin.namespace}"
        let pluginFile = "${pluginDir}/Script.ts"

        if (!exists(pluginFile)) {
            return DenoExecutionResult(false, "Plugin file not found", "", loginCookiesJson, 1)
        }

        let denoArgs = buildDenoPermissions(plugin, pluginFile)
        denoArgs.add(pluginFile)

        // 合并参数（插件配置参数 + 任务额外参数）
        let baseParams = buildPluginParametersJson(plugin)
        let mergedParams = mergeParamsJson(baseParams, extraParams)

        // 构建 stdin JSON
        let inputJson = buildStdinJson(
            "run",
            "Script",
            pluginDir,
            "",
            "",
            "",
            "",
            oneshotParam,
            mergedParams,
            loginCookiesJson,
            ""
        )

        let result = executeWithStdio(taskId, "deno", denoArgs, inputJson, 0)
        return DenoExecutionResult(result.success, result.error, result.output, loginCookiesJson, result.exitCode)
    }

    /**
     * 构建插件参数 JSON
     */
    private static func buildPluginParametersJson(plugin: PluginData): String {
        if (plugin.parameters.trimAscii().size == 0) {
            return ""
        }

        try {
            let jsonVal = JsonValue.fromStr(plugin.parameters)
            match (jsonVal) {
                case array: JsonArray =>
                    var mergedParams = JsonObject()
                    let fields = mergedParams.getFields()
                    let size = array.size()
                    for (i in 0..size) {
                        match (array.get(i)) {
                            case Some(paramVal) =>
                                match (paramVal) {
                                    case paramObj: JsonObject =>
                                        let paramFields = paramObj.getFields()
                                        let name = getParamName(paramFields)
                                        let key = if (name.size > 0) { name } else { "param${i}" }
                                        match (getParamValue(paramFields)) {
                                            case Some(value) => fields[key] = value
                                            case None => ()
                                        }
                                    case _ => ()
                                }
                            case None => ()
                        }
                    }
                    if (fields.size > 0) {
                        return mergedParams.toString()
                    }
                case obj: JsonObject =>
                    if (obj.getFields().size > 0) {
                        return obj.toString()
                    }
                case _ => ()
            }
        } catch (_: Exception) {}

        return ""
    }

    private static func getParamName(fields: HashMap<String, JsonValue>): String {
        match (fields.get("name")) {
            case Some(v) =>
                match (v) {
                    case s: JsonString => return s.getValue()
                    case _ => return ""
                }
            case None => return ""
        }
    }

    private static func getParamValue(fields: HashMap<String, JsonValue>): Option<JsonValue> {
        if (fields.contains("value")) {
            return Option<JsonValue>.Some(fields["value"])
        }
        if (fields.contains("default_value")) {
            return Option<JsonValue>.Some(fields["default_value"])
        }
        return Option.None
    }

    /**
     * 执行元数据插件
     */
    private static func executeMetadataPlugin(
        taskId: Int64,
        plugin: PluginData,
        archiveId: String,
        oneshotParam: String,
        extraParams: String,
        loginCookiesJson: String
    ): DenoExecutionResult {
        let pluginDir = "${PluginPaths.getPluginRuntimeRoot()}/${plugin.namespace}"
        let pluginFile = "${pluginDir}/Metadata.ts"

        if (!exists(pluginFile)) {
            return DenoExecutionResult(false, "Plugin file not found", "")
        }

        // 获取归档信息
        let archive = ArchiveDao.getArchiveById(archiveId)
        if (archive.id.size == 0) {
            return DenoExecutionResult(false, "Archive not found", "")
        }
        let tagsString = TagDao.getArchiveTags(archiveId)

        let denoArgs = buildDenoPermissions(plugin, pluginFile)
        denoArgs.add("--allow-read=./data/thumb")
        denoArgs.add(pluginFile)

        // 合并参数
        let baseParams = buildPluginParametersJson(plugin)
        let mergedParams = mergeParamsJson(baseParams, extraParams)

        // 构建 stdin JSON
        let inputJson = buildStdinJson(
            "run",
            "Metadata",
            pluginDir,
            archiveId,
            archive.title,
            tagsString,
            archive.thumbhash,
            oneshotParam,
            mergedParams,
            loginCookiesJson,
            ""
        )

        let result = executeWithStdio(taskId, "deno", denoArgs, inputJson, 0)
        // 保留 loginCookiesJson 用于后续处理
        return DenoExecutionResult(result.success, result.error, result.output, loginCookiesJson, result.exitCode)
    }

    /**
     * 合并参数 JSON
     */
    private static func mergeParamsJson(baseParams: String, extraParams: String): String {
        let extraTrimmed = extraParams.trimAscii()
        if (extraTrimmed.size == 0) {
            return baseParams
        }

        let baseTrimmed = baseParams.trimAscii()
        if (baseTrimmed.size == 0) {
            return extraTrimmed
        }

        try {
            let baseVal = JsonValue.fromStr(baseTrimmed)
            let extraVal = JsonValue.fromStr(extraTrimmed)

            match (baseVal) {
                case baseObj: JsonObject =>
                    match (extraVal) {
                        case extraObj: JsonObject =>
                            let merged = JsonObject()
                            let fields = merged.getFields()
                            for ((k, v) in baseObj.getFields()) {
                                fields[k] = v
                            }
                            for ((k, v) in extraObj.getFields()) {
                                fields[k] = v
                            }
                            return merged.toString()
                        case _ => return extraTrimmed
                    }
                case _ => return extraTrimmed
            }
        } catch (_: Exception) {
            return extraTrimmed
        }
    }

    /**
     * 执行下载插件
     */
    private static func executeDownloadPlugin(
        taskId: Int64,
        plugin: PluginData,
        url: String,
        loginCookiesJson: String,
        parentTaskId: Int64
    ): DenoExecutionResult {
        let pluginDir = "${PluginPaths.getPluginRuntimeRoot()}/${plugin.namespace}"
        let pluginFile = "${pluginDir}/Download.ts"

        if (!exists(pluginFile)) {
            return DenoExecutionResult(false, "Plugin file not found", "")
        }

        let denoArgs = buildDenoPermissions(plugin, pluginFile)
        denoArgs.add(pluginFile)

        // 构建 stdin JSON
        let paramsJson = buildPluginParametersJson(plugin)
        let inputJson = buildStdinJson(
            "run",
            "Download",
            pluginDir,
            "",
            "",
            "",
            "",
            "",
            paramsJson,
            loginCookiesJson,
            url
        )

        let result = executeWithStdio(taskId, "deno", denoArgs, inputJson, parentTaskId)
        return DenoExecutionResult(result.success, result.error, result.output, loginCookiesJson, result.exitCode)
    }

    private static func mirrorParentLog(parentTaskId: Int64, denoTaskId: Int64, message: String): Unit {
        if (parentTaskId <= 0) {
            return
        }
        TaskIO.appendLog(parentTaskId, "[deno_task ${denoTaskId}] ${message}")
    }

    private static func mirrorParentProgress(parentTaskId: Int64, denoTaskId: Int64, progress: Int32, message: String): Unit {
        if (parentTaskId <= 0) {
            return
        }

        // Map plugin progress (0-100) onto a conservative window for the parent task.
        // This keeps room for any callback steps that happen after the plugin finishes.
        var mapped = 20i32 + Int32((Int64(progress) * 75i64) / 100i64) // 20..95
        if (mapped < 20i32) { mapped = 20i32 }
        if (mapped > 95i32) { mapped = 95i32 }

        let parent = TaskDao.getTaskDataById(parentTaskId)
        if (parent.id == 0) {
            return
        }

        // Keep parent status unchanged (e.g., "waiting") but ensure progress is monotonic.
        if (mapped > parent.progress) {
            TaskDao.updateTaskStatus(parentTaskId, parent.status, message, mapped)
        }

        TaskIO.appendLog(parentTaskId, "[deno_task ${denoTaskId}] [PROGRESS] ${progress}% - ${message}")
    }
}
