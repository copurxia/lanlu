package lanlu.task_runners

import std.process.*
import std.collection.*
import std.fs.*
import std.io.*
import std.convert.*
import std.sync.*
import std.time.*
import std.io.{ByteBuffer, readToEnd}
import stdx.crypto.digest.*
import stdx.encoding.hex.*
import stdx.encoding.json.stream.*
import stdx.log.*
import lanlu.dao.*
import lanlu.archivehandler.*
import lanlu.kv.*
import lanlu.models.*
import lanlu.utils.*

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

class RpcSelectOption {
    var index: Int32 = 0
    var label: String = ""
    var description: String = ""
    var cover: String = ""

    public init() {}

    public init(index: Int32, label: String, description: String, cover: String) {
        this.index = index
        this.label = label
        this.description = description
        this.cover = cover
    }
}

class RpcSelectRequest {
    var taskId: Int64 = 0
    var requestId: String = ""
    var title: String = "请选择候选项"
    var message: String = ""
    var defaultIndex: Int32 = 0
    var timeoutSeconds: Int32 = 90
    var options: Array<RpcSelectOption> = Array<RpcSelectOption>()
    var createdAtSeconds: Int64 = 0
    var responded: Bool = false
    var selectedIndex: Int32 = -1

    public init() {}
}

class DenoTaskParametersReq <: JsonDeserializable<DenoTaskParametersReq> {
    var pluginNamespace: String = ""
    var pluginType: String = ""
    var action: String = "run"
    var groupId: String = ""
    // Backward compatible: archiveId is still accepted. New fields: targetType/targetId.
    var archiveId: String = ""
    var targetType: String = ""
    var targetId: String = ""
    var oneshotParam: String = ""
    var extraParams: String = ""
    var url: String = ""
    var parentTaskId: String = ""

    public static func fromJson(r: JsonReader): DenoTaskParametersReq {
        let res = DenoTaskParametersReq()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "pluginNamespace" => res.pluginNamespace = r.readValue<String>().trimAscii()
                            case "pluginType" => res.pluginType = r.readValue<String>().trimAscii()
                            case "action" => res.action = r.readValue<String>().trimAscii()
                            case "groupId" => res.groupId = r.readValue<String>().trimAscii()
                            case "archiveId" => res.archiveId = r.readValue<String>().trimAscii()
                            case "targetType" => res.targetType = r.readValue<String>().trimAscii()
                            case "targetId" => res.targetId = r.readValue<String>().trimAscii()
                            case "oneshotParam" => res.oneshotParam = r.readValue<String>()
                            case "extraParams" => res.extraParams = r.readValue<String>()
                            case "url" => res.url = r.readValue<String>().trimAscii()
                            case "parentTaskId" => res.parentTaskId = r.readValue<String>().trimAscii()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }
        if (res.action.size == 0) { res.action = "run" }
        return res
    }
}

/**
 * Deno 任务执行器
 * 统一处理所有 Deno 插件执行
 */
public class DenoTaskRunner {
    private static let rpcSelectMutex: Mutex = Mutex()
    private static var rpcSelectPending: HashMap<String, RpcSelectRequest> = HashMap<String, RpcSelectRequest>()

    private static func buildRpcSelectKey(taskId: Int64, requestId: String): String {
        return "${taskId}:${requestId.trimAscii()}"
    }

    private static func buildRpcSelectMessage(request: RpcSelectRequest): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("type").writeValue("rpc_select")
        w.writeName("request_id").writeValue(request.requestId)
        w.writeName("title").writeValue(request.title)
        w.writeName("message").writeValue(request.message)
        w.writeName("default_index").writeValue(request.defaultIndex)
        w.writeName("timeout_seconds").writeValue(request.timeoutSeconds)
        w.writeName("options")
        w.startArray()
        for (opt in request.options) {
            w.startObject()
            w.writeName("index").writeValue(opt.index)
            w.writeName("label").writeValue(opt.label)
            w.writeName("description").writeValue(opt.description)
            w.writeName("cover").writeValue(opt.cover)
            w.endObject()
        }
        w.endArray()
        w.endObject()
        w.flush()
        return "[RPC_SELECT]" + String.fromUtf8(readToEnd(out))
    }

    public static func resolveRpcSelect(taskId: Int64, requestId: String, selectedIndex: Int32): (Bool, String) {
        let rid = requestId.trimAscii()
        if (taskId <= 0 || rid.size == 0) {
            return (false, "invalid task_id/request_id")
        }

        let key = buildRpcSelectKey(taskId, rid)
        rpcSelectMutex.lock()
        match (rpcSelectPending.get(key)) {
            case Some(req) =>
                if (req.responded) {
                    rpcSelectMutex.unlock()
                    return (false, "request already resolved")
                }
                if (selectedIndex < 0 || Int64(selectedIndex) >= req.options.size) {
                    rpcSelectMutex.unlock()
                    return (false, "selected_index out of range")
                }
                req.responded = true
                req.selectedIndex = selectedIndex
                rpcSelectPending[key] = req
                rpcSelectMutex.unlock()
                return (true, "ok")
            case None =>
                rpcSelectMutex.unlock()
                return (false, "request not found or expired")
        }
    }

    public static func abortRpcSelect(taskId: Int64, requestId: String): (Bool, String) {
        let rid = requestId.trimAscii()
        if (taskId <= 0 || rid.size == 0) {
            return (false, "invalid task_id/request_id")
        }

        let key = buildRpcSelectKey(taskId, rid)
        rpcSelectMutex.lock()
        match (rpcSelectPending.get(key)) {
            case Some(req) =>
                if (req.responded) {
                    rpcSelectMutex.unlock()
                    return (false, "request already resolved")
                }
                req.responded = true
                req.selectedIndex = -1
                rpcSelectPending[key] = req
                rpcSelectMutex.unlock()
                return (true, "ok")
            case None =>
                rpcSelectMutex.unlock()
                return (false, "request not found or expired")
        }
    }

    /**
     * 任务入口
     */
    public static func run(taskId: Int64, parameters: String): Unit {
        TaskIO.appendLog(taskId, "deno_task started")
        TaskModel.updateTaskProgress(taskId, 1, "Deno任务开始")

        // 解析参数
        let (pluginNamespace, pluginType, _, groupId, targetType, targetId, oneshotParam, extraParams, url, parentTaskIdRaw) = parseParameters(parameters)
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

        let taskData = TaskDao.getTaskDataById(taskId)
        let interactiveSelectEnabled = taskData.triggerSource.trimAscii() == "metadata_plugin_preview"

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
                case "Metadata" => executeMetadataPlugin(taskId, plugin, targetType, targetId, oneshotParam, extraParams, loginCookiesJson, interactiveSelectEnabled)
                case "Download" => executeDownloadPlugin(taskId, plugin, url, loginCookiesJson, parentTaskId, interactiveSelectEnabled)
                case "Login" => executeLoginPluginDirect(taskId, plugin, interactiveSelectEnabled)
                case "Script" => executeScriptPlugin(taskId, plugin, oneshotParam, extraParams, loginCookiesJson, interactiveSelectEnabled)
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
        TaskRunnerOutput.fail(taskId, message)
    }

    private static func parseParameters(parameters: String): (String, String, String, String, String, String, String, String, String, String) {
        var pluginNamespace = ""
        var pluginType = ""
        var action = "run"
        var groupId = ""
        var archiveId = ""
        var targetType = ""
        var targetId = ""
        var oneshotParam = ""
        var extraParams = ""
        var url = ""
        var parentTaskId = ""

        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return (pluginNamespace, pluginType, action, groupId, targetType, targetId, oneshotParam, extraParams, url, parentTaskId)
        }

        try {
            let req = JsonCodec.decode<DenoTaskParametersReq>(trimmed)
            pluginNamespace = req.pluginNamespace
            pluginType = req.pluginType
            action = req.action
            groupId = req.groupId
            archiveId = req.archiveId
            targetType = req.targetType
            targetId = req.targetId
            oneshotParam = req.oneshotParam
            extraParams = req.extraParams
            url = req.url
            parentTaskId = req.parentTaskId
        } catch (_: Exception) {}

        if (targetType.size == 0) { targetType = "archive" }
        if (targetId.size == 0) { targetId = archiveId }
        return (pluginNamespace, pluginType, action, groupId, targetType, targetId, oneshotParam, extraParams, url, parentTaskId)
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
            // Always refresh base_plugin.ts so runtime cache doesn't get stale across upgrades.
            copy(basePluginSource, to: basePluginTarget, overwrite: true)

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
        let loginResult = executeLoginPluginDirect(taskId, loginPlugin, false)
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
            var buf = ByteBuffer()
            unsafe { buf.write(output.rawData()) }
            let r = JsonReader(buf)

            if (r.peek() != Some(BeginObject)) {
                return ""
            }

            var success = false
            var cookiesRaw = ""

            r.startObject()
            while (r.peek() != EndObject) {
                let n = r.readName()
                match (n) {
                    case "success" =>
                        let v = r.readValue<String>().trimAscii()
                        success = (v == "true" || v == "1")
                    case "data" =>
                        if (r.peek() == Some(BeginObject)) {
                            r.startObject()
                            while (r.peek() != EndObject) {
                                let dn = r.readName()
                                match (dn) {
                                    case "cookies" =>
                                        if (r.peek() == Some(BeginArray)) {
                                            cookiesRaw = String.fromUtf8(r.readValueBytes())
                                        } else {
                                            r.skip()
                                        }
                                    case _ => r.skip()
                                }
                            }
                            r.endObject()
                        } else {
                            r.skip()
                        }
                    case _ => r.skip()
                }
            }
            r.endObject()

            if (!success) { return "" }
            return cookiesRaw
        } catch (_: Exception) {}

        return ""
    }

    /**
     * 构建 Deno 权限参数
     */
    private static func buildDenoPermissions(plugin: PluginData, _: String): ArrayList<String> {
        var denoArgs = ArrayList<String>()
        denoArgs.add("run")

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
        let out = ByteBuffer()
        let w = JsonWriter(out)

        w.startObject()
        w.writeName("action").writeValue(action)
        w.writeName("pluginType").writeValue(pluginType)
        w.writeName("pluginDir").writeValue(pluginDir)
        w.writeName("archiveId").writeValue(archiveId)
        w.writeName("archiveTitle").writeValue(archiveTitle)
        w.writeName("existingTags").writeValue(existingTags)
        w.writeName("thumbnailHash").writeValue(thumbnailHash)
        w.writeName("oneshotParam").writeValue(oneshotParam)
        w.writeName("url").writeValue(url)

        // params/loginCookies are stored as JSON inside String; embed as raw JSON values.
        let paramsTrimmed = params.trimAscii()
        if (paramsTrimmed.size > 0) {
            w.writeName("params").jsonValue(paramsTrimmed)
        } else {
            w.writeName("params")
            w.startObject()
            w.endObject()
        }

        let cookiesTrimmed = loginCookies.trimAscii()
        if (cookiesTrimmed.size > 0) {
            w.writeName("loginCookies").jsonValue(cookiesTrimmed)
        } else {
            w.writeName("loginCookies")
            w.startArray()
            w.endArray()
        }

        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    /**
     * Parse a single NDJSON line from plugin stdout.
     *
     * Supports both:
     * - Plugin messages: progress/log/data/result
     * - Host RPC requests: call
     *
     * Returns:
     * - kind:
     *   - "call": a=id, b=method, payload=paramsRawJson
     *   - "progress": progress, payload=message
     *   - "log": a=level, payload=message
     *   - "data": a=key, payload=valueRawJson
     *   - "result": success, payload=dataRawJson (if success) OR error string (if !success)
     *   - "raw"/"unknown": payload=original line
     */
    private static func parseNdjsonLine(line: String): (String, String, String, Int32, Bool, String) {
        let trimmed = line.trimAscii()
        if (trimmed.size == 0) {
            return ("", "", "", 0, false, "")
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            if (r.peek() != Some(BeginObject)) {
                return ("raw", "", "", 0, false, trimmed)
            }

            var msgType = ""
            var id = ""
            var method = ""
            var paramsRaw = "{}"
            var progress = 0i32
            var message = ""
            var level = ""
            var key = ""
            var valueRaw = ""
            var success = false
            var dataRaw = ""
            var error = ""

            r.startObject()
            while (r.peek() != EndObject) {
                let n = r.readName()
                match (n) {
                    case "type" => msgType = r.readValue<String>().trimAscii()
                    case "id" => id = r.readValue<String>().trimAscii()
                    case "method" => method = r.readValue<String>().trimAscii()
                    case "params" => paramsRaw = String.fromUtf8(r.readValueBytes())
                    case "progress" =>
                        let p = r.readValue<String>().trimAscii()
                        try { progress = Int32.parse(p) } catch (_: Exception) { progress = 0i32 }
                    case "message" => message = r.readValue<String>()
                    case "level" => level = r.readValue<String>().trimAscii()
                    case "key" => key = r.readValue<String>().trimAscii()
                    case "value" => valueRaw = String.fromUtf8(r.readValueBytes())
                    case "success" =>
                        let v = r.readValue<String>().trimAscii()
                        success = (v == "true" || v == "1")
                    case "data" => dataRaw = String.fromUtf8(r.readValueBytes())
                    case "error" => error = r.readValue<String>()
                    case _ => r.skip()
                }
            }
            r.endObject()

            match (msgType) {
                case "call" =>
                    if (id.size == 0 || method.size == 0) { return ("unknown", "", "", 0, false, trimmed) }
                    return ("call", id, method, 0, false, paramsRaw)
                case "progress" => return ("progress", "", "", progress, false, message)
                case "log" => return ("log", level, "", 0, false, message)
                case "data" => return ("data", key, "", 0, false, valueRaw)
                case "result" => return ("result", "", "", 0, success, if (success) { dataRaw } else { error })
                case _ => return ("unknown", "", "", 0, false, trimmed)
            }
        } catch (_: Exception) {
            return ("raw", "", "", 0, false, trimmed)
        }
    }

    private static func buildHostCallResultLine(id: String, success: Bool, dataJson: String, error: String): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("type").writeValue("call_result")
        w.writeName("id").writeValue(id)
        w.writeName("success").writeValue(success)
        if (success) {
            w.writeName("data").jsonValue(dataJson)
        } else {
            w.writeName("error").writeValue(error)
        }
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func parseBoolLoose(s: String): Bool {
        let v = s.trimAscii().toAsciiLower()
        return (v == "true" || v == "1" || v == "yes" || v == "y" || v == "on")
    }

    private static func parseInt64Loose(s: String, defaultValue: Int64): Int64 {
        let v = s.trimAscii()
        if (v.size == 0) { return defaultValue }
        try { return Int64.parse(v) } catch (_: Exception) { return defaultValue }
    }

    private static func handleHostRpcCall(taskId: Int64, method: String, paramsRaw: String, pluginNamespace: String, interactiveSelectEnabled: Bool): (Bool, String, String) {
        // returns: (success, dataJson, error)
        let m = method.trimAscii()
        let paramsTrimmed = paramsRaw.trimAscii()
        let effectiveParams = if (paramsTrimmed.size > 0) { paramsTrimmed } else { "{}" }

        if (m == "ui.select") {
            var title = "请选择候选项"
            var message = ""
            var defaultIndex = 0i32
            var timeoutSeconds = 90i32
            var options = ArrayList<RpcSelectOption>()

            try {
                var buf = ByteBuffer()
                unsafe { buf.write(effectiveParams.rawData()) }
                let r = JsonReader(buf)

                if (r.peek() == Some(BeginObject)) {
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "title" => title = r.readValue<String>()
                            case "message" => message = r.readValue<String>()
                            case "defaultIndex" => defaultIndex = Int32(parseInt64Loose(r.readValue<String>(), 0i64))
                            case "timeoutSeconds" => timeoutSeconds = Int32(parseInt64Loose(r.readValue<String>(), 90i64))
                            case "options" =>
                                if (r.peek() == Some(BeginArray)) {
                                    var idx = 0i32
                                    r.startArray()
                                    while (r.peek() != EndArray) {
                                        var label = ""
                                        var desc = ""
                                        var cover = ""
                                        match (r.peek()) {
                                            case Some(BeginObject) =>
                                                r.startObject()
                                                while (r.peek() != EndObject) {
                                                    let k = r.readName()
                                                    match (k) {
                                                        case "label" => label = r.readValue<String>()
                                                        case "description" => desc = r.readValue<String>()
                                                        case "cover" => cover = r.readValue<String>()
                                                        case _ => r.skip()
                                                    }
                                                }
                                                r.endObject()
                                            case Some(_) =>
                                                label = r.readValue<String>()
                                            case None => ()
                                        }
                                        
                                        let fallbackLabel = if (label.trimAscii().size > 0) { label } else { "选项 ${idx + 1}" }
                                        options.add(RpcSelectOption(idx, fallbackLabel, desc, cover))
                                        idx += 1
                                    }
                                    r.endArray()
                                } else {
                                    r.skip()
                                }
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                }
            } catch (_: Exception) {}

            if (options.size <= 0) {
                return (false, "{}", "ui.select requires non-empty options")
            }
            if (defaultIndex < 0 || Int64(defaultIndex) >= options.size) {
                defaultIndex = 0
            }
            if (timeoutSeconds < 10) { timeoutSeconds = 10 }
            if (timeoutSeconds > 900) { timeoutSeconds = 900 }

            if (!interactiveSelectEnabled) {
                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("index").writeValue(defaultIndex)
                w.endObject()
                w.flush()
                return (true, String.fromUtf8(readToEnd(out)), "")
            }

            let request = RpcSelectRequest()
            request.taskId = taskId
            request.requestId = "${DateTime.now().toUnixTimeStamp().toMilliseconds()}_${taskId}"
            request.title = if (title.trimAscii().size > 0) { title } else { "请选择候选项" }
            request.message = message
            request.defaultIndex = defaultIndex
            request.timeoutSeconds = timeoutSeconds
            request.options = options.toArray()
            request.createdAtSeconds = DateTime.now().toUnixTimeStamp().toSeconds()

            let key = buildRpcSelectKey(taskId, request.requestId)
            rpcSelectMutex.lock()
            rpcSelectPending[key] = request
            rpcSelectMutex.unlock()

            let currentProgress = TaskDao.getTaskDataById(taskId).progress
            TaskModel.updateTaskProgress(taskId, currentProgress, buildRpcSelectMessage(request))

            let deadline = DateTime.now().toUnixTimeStamp().toSeconds() + Int64(timeoutSeconds)
            while (true) {
                var selected = -1i32
                var done = false
                rpcSelectMutex.lock()
                match (rpcSelectPending.get(key)) {
                    case Some(req) =>
                        if (req.responded) {
                            selected = req.selectedIndex
                            done = true
                            rpcSelectPending.remove(key)
                        }
                    case None =>
                        done = true
                }
                rpcSelectMutex.unlock()

                if (done) {
                    if (selected >= 0) {
                        let out = ByteBuffer()
                        let w = JsonWriter(out)
                        w.startObject()
                        w.writeName("index").writeValue(selected)
                        w.endObject()
                        w.flush()
                        TaskModel.updateTaskProgress(taskId, currentProgress, "已接收人工选择结果")
                        return (true, String.fromUtf8(readToEnd(out)), "")
                    }
                    if (selected == -1) {
                        return (false, "{}", "ui.select cancelled by user")
                    }
                }

                if (DateTime.now().toUnixTimeStamp().toSeconds() >= deadline) {
                    rpcSelectMutex.lock()
                    rpcSelectPending.remove(key)
                    rpcSelectMutex.unlock()
                    return (false, "{}", "ui.select timeout: no response")
                }

                sleep(Duration.second)
            }
        }

        // Resolve archiveId -> (archiveType, actualPath).
        func resolveArchiveActualPath(archiveId: String): Option<(String, String)> {
            let arcid = archiveId.trimAscii()
            if (arcid.size == 0) { return None }

            let archive = ArchiveDao.getArchiveById(arcid)
            if (archive.id.size == 0) { return None }

            let categoryId = archive.category_id
            if (categoryId <= 0) { return None }
            let basePath = match (CategoryDao.getCategoryByInternalId(categoryId)) {
                case Some(cat) => cat.scanPath
                case None => ""
            }
            if (basePath.trimAscii().size == 0) { return None }

            let fullArchivePath = if (archive.relative_path.size > 0) {
                "${basePath}/${archive.relative_path}/${archive.filename}"
            } else {
                "${basePath}/${archive.filename}"
            }
            let actualPath = FileUtils.resolvePath(fullArchivePath)
            if (actualPath.trimAscii().size == 0) { return None }
            return Some((archive.archive_type, actualPath))
        }

        func normalizeSafeRelPath(input: String): String {
            // Convert to a safe relative path: drop leading '/', remove '.', '..' segments.
            var s = input.trimAscii().replace("\\", "/")
            while (s.startsWith("/")) { s = s[1..s.size] }
            let parts = s.split("/")
            var outParts = ArrayList<String>()
            for (p in parts) {
                let t = p.trimAscii()
                if (t.size == 0 || t == ".") { continue }
                if (t == "..") { continue }
                // Avoid path separators.
                if (t.contains("/") || t.contains("\\")) { continue }
                outParts.add(t)
            }
            return String.join(outParts.toArray(), delimiter: "/")
        }

        func ensureUnderRuntimeRoot(pluginDir: String): Bool {
            let root = PluginPaths.getPluginRuntimeRoot().trimAscii()
            var p = pluginDir.trimAscii()
            if (root.size == 0 || p.size == 0) { return false }
            // Avoid false positives like "/cache/plugins_evil" matching "/cache/plugins".
            var cleanRoot = root
            while (cleanRoot.size > 1 && cleanRoot.endsWith("/")) { cleanRoot = cleanRoot[0..(cleanRoot.size - 1)] }
            while (p.size > 1 && p.endsWith("/")) { p = p[0..(p.size - 1)] }
            return p == cleanRoot || p.startsWith("${cleanRoot}/")
        }

        func sha1HexFromFile(filePath: String): String {
            let p = Path(filePath)
            if (!exists(p)) { return "" }
            var sha1 = SHA1()
            try {
                let f = File(p, Read)
                let bufSize: Int64 = 1024 * 1024
                var buf = Array<Byte>(bufSize, repeat: 0)
                while (true) {
                    let n = f.read(buf)
                    if (n <= 0) { break }
                    sha1.write(buf[0..n])
                }
                f.close()
                return toHexString(sha1.finish())
            } catch (_: Exception) {
                return ""
            }
        }

        func runFfmpegToJpeg(inputPath: String, outputPath: String, maxSide: Int64, jpegQuality: Int64): (Int64, String) {
            // Best-effort conversion to a JPEG suitable for EH image lookup.
            let scale = if (maxSide > 0) { maxSide } else { 1280i64 }
            // ffmpeg's JPEG "quality" uses qscale (lower is better). Map 1..100 -> 31..2.
            let q = if (jpegQuality > 0) { jpegQuality } else { 85i64 }
            var qv = 31i64 - (q * 29i64 / 100i64)
            if (qv < 2i64) { qv = 2i64 }
            if (qv > 31i64) { qv = 31i64 }
            let vf = "scale=${scale}:${scale}:force_original_aspect_ratio=decrease"
            let args = [
                "-hide_banner",
                "-loglevel", "error",
                "-y",
                "-i", inputPath,
                "-frames:v", "1",
                "-vf", vf,
                "-q:v", qv.toString(),
                "-map_metadata", "-1",
                outputPath
            ]
            try {
                let proc = launch("ffmpeg", args, stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                let (exitCode, _, stderr) = proc.waitOutput()
                let stderrStr = try { String.fromUtf8(stderr) } catch (_: Exception) { "" }
                return (exitCode, stderrStr)
            } catch (e: Exception) {
                return (1, e.message)
            }
        }

        func runImageMagickToJpeg(inputPath: String, outputPath: String, maxSide: Int64, jpegQuality: Int64): (Int64, String) {
            let scale = if (maxSide > 0) { maxSide } else { 1280i64 }
            let q = if (jpegQuality > 0) { jpegQuality } else { 85i64 }
            let firstFrameInput = "${inputPath}[0]"
            let args = [
                firstFrameInput,
                "-strip",
                "-resize", "${scale}x${scale}>",
                "-quality", q.toString(),
                outputPath
            ]
            try {
                let proc = launch("convert", args, stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                let (exitCode, _, stderr) = proc.waitOutput()
                let stderrStr = try { String.fromUtf8(stderr) } catch (_: Exception) { "" }
                return (exitCode, stderrStr)
            } catch (e: Exception) {
                return (1, e.message)
            }
        }

        if (m == "tags.list") {
            var namespaceStr = ""
            var q = ""
            var lang = "zh"
            var limit: Int64 = 1000i64
            var offset: Int64 = 0i64
            var includeTranslations = false

            try {
                var buf = ByteBuffer()
                unsafe { buf.write(effectiveParams.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() == Some(BeginObject)) {
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "namespace" => namespaceStr = r.readValue<String>()
                            case "q" => q = r.readValue<String>()
                            case "lang" => lang = r.readValue<String>()
                            case "limit" => limit = parseInt64Loose(r.readValue<String>(), 1000i64)
                            case "offset" => offset = parseInt64Loose(r.readValue<String>(), 0i64)
                            case "includeTranslations" => includeTranslations = parseBoolLoose(r.readValue<String>())
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                }
            } catch (_: Exception) {}

            if (limit <= 0) { limit = 1000i64 }
            if (limit > 2000) { limit = 2000i64 }
            if (offset < 0) { offset = 0i64 }
            let nsOpt: ?String = if (namespaceStr.trimAscii().size > 0) { Some(namespaceStr.trimAscii()) } else { None }
            let qOpt: ?String = if (q.trimAscii().size > 0) { Some(q.trimAscii()) } else { None }
            let effectiveLang = if (lang.trimAscii().size > 0) { lang.trimAscii() } else { "zh" }

            let total = TagDao.count(nsOpt, qOpt)
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("total").writeValue(total)
            w.writeName("limit").writeValue(limit)
            w.writeName("offset").writeValue(offset)
            w.writeName("items")
            w.startArray()

            if (includeTranslations) {
                let rows = TagDao.list(nsOpt, qOpt, limit, offset)
                for (row in rows) {
                    w.startObject()
                    w.writeName("id").writeValue(row.id)
                    w.writeName("namespace").writeValue(row.namespace)
                    w.writeName("name").writeValue(row.name)
                    w.writeName("translation_text").writeValue(row.getTranslatedText(effectiveLang))
                    w.writeName("translations")
                    w.startObject()
                    for ((l, t) in row.translations) {
                        w.writeName(l)
                        w.startObject()
                        w.writeName("text").writeValue(t.text)
                        w.writeName("intro").writeValue(t.intro)
                        w.endObject()
                    }
                    w.endObject()
                    w.endObject()
                }
            } else {
                let rows = TagDao.listLite(nsOpt, qOpt, effectiveLang, limit, offset)
                for (row in rows) {
                    w.startObject()
                    w.writeName("id").writeValue(row.id)
                    w.writeName("namespace").writeValue(row.namespace)
                    w.writeName("name").writeValue(row.name)
                    w.writeName("translation_text").writeValue(row.translationText)
                    w.endObject()
                }
            }

            w.endArray()
            w.endObject()
            w.flush()
            return (true, String.fromUtf8(readToEnd(out)), "")
        }

        if (m == "tags.merge") {
            var sourceId: Int64 = 0i64
            var targetId: Int64 = 0i64
            var deleteSource = true

            try {
                var buf = ByteBuffer()
                unsafe { buf.write(effectiveParams.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() == Some(BeginObject)) {
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "sourceId" => sourceId = parseInt64Loose(r.readValue<String>(), 0i64)
                            case "targetId" => targetId = parseInt64Loose(r.readValue<String>(), 0i64)
                            case "deleteSource" => deleteSource = parseBoolLoose(r.readValue<String>())
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                }
            } catch (_: Exception) {}

            if (sourceId <= 0 || targetId <= 0 || sourceId == targetId) {
                return (false, "{}", "invalid sourceId/targetId")
            }

            let ok = TagDao.mergeById(sourceId, targetId, deleteSource)
            if (!ok) {
                return (false, "{}", "merge failed")
            }
            return (true, "{\"merged\":true}", "")
        }

        if (m == "archive.listFiles") {
            var archiveId = ""
            try {
                var buf = ByteBuffer()
                unsafe { buf.write(effectiveParams.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() == Some(BeginObject)) {
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "archiveId" => archiveId = r.readValue<String>().trimAscii()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                }
            } catch (_: Exception) {}

            let resolved = resolveArchiveActualPath(archiveId)
            match (resolved) {
                case None => return (false, "{}", "archive not found or path unresolved")
                case Some((archiveType, actualPath)) =>
                    let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archiveType)
                    let entries = handler.listEntries(actualPath)
                    let out = ByteBuffer()
                    let w = JsonWriter(out)
                    w.startObject()
                    w.writeName("archiveId").writeValue(archiveId)
                    w.writeName("count").writeValue(Int64(entries.size))
                    w.writeName("files")
                    w.startArray()
                    for (e in entries) { w.writeValue(e) }
                    w.endArray()
                    w.endObject()
                    w.flush()
                    return (true, String.fromUtf8(readToEnd(out)), "")
            }
        }

        if (m == "archive.getMetadata") {
            var archiveId = ""

            try {
                var buf = ByteBuffer()
                unsafe { buf.write(effectiveParams.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() == Some(BeginObject)) {
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "archiveId" => archiveId = r.readValue<String>().trimAscii()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                }
            } catch (_: Exception) {}

            if (archiveId.size == 0) {
                return (false, "{}", "missing archiveId")
            }

            let archive = ArchiveDao.getArchiveById(archiveId)
            if (archive.id.size == 0) {
                return (false, "{}", "archive not found")
            }

            let tags = TagDao.getArchiveTags(archiveId)
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("archiveId").writeValue(archiveId)
            w.writeName("title").writeValue(archive.title)
            w.writeName("existingTags").writeValue(tags)
            w.writeName("thumbnailHash").writeValue(archive.thumbhash)
            w.endObject()
            w.flush()
            return (true, String.fromUtf8(readToEnd(out)), "")
        }

        if (m == "tankoubon.listArchives") {
            var tankoubonId = ""

            try {
                var buf = ByteBuffer()
                unsafe { buf.write(effectiveParams.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() == Some(BeginObject)) {
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "tankoubonId" => tankoubonId = r.readValue<String>().trimAscii()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                }
            } catch (_: Exception) {}

            if (tankoubonId.size == 0) {
                return (false, "{}", "missing tankoubonId")
            }

            let archiveIds = TankoubonDao.getArchivesInTankoubon(tankoubonId)
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("tankoubonId").writeValue(tankoubonId)
            w.writeName("archiveIds")
            w.startArray()
            for (arcid in archiveIds) {
                let id = arcid.trimAscii()
                if (id.size > 0) {
                    w.writeValue(id)
                }
            }
            w.endArray()
            w.endObject()
            w.flush()
            return (true, String.fromUtf8(readToEnd(out)), "")
        }

        // List files adjacent to an archive on disk.
        // - For file archives (cbz/pdf/epub/...): list files in the parent directory.
        // - For folder archives: list files directly inside that folder.
        if (m == "archive.listAdjacentFiles") {
            var archiveId = ""
            try {
                var buf = ByteBuffer()
                unsafe { buf.write(effectiveParams.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() == Some(BeginObject)) {
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "archiveId" => archiveId = r.readValue<String>().trimAscii()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                }
            } catch (_: Exception) {}

            if (archiveId.size == 0) {
                return (false, "{}", "missing archiveId")
            }

            let resolved = resolveArchiveActualPath(archiveId)
            match (resolved) {
                case None => return (false, "{}", "archive not found or path unresolved")
                case Some((archiveType, actualPath)) =>
                    var baseDir = ""
                    if (archiveType == ArchiveTypes.FOLDER) {
                        baseDir = actualPath
                    } else {
                        let p = Path(actualPath)
                        baseDir = p.parent.toString().trimAscii()
                    }

                    if (baseDir.size == 0 || !DirectoryScanner.directoryExists(baseDir)) {
                        return (false, "{}", "adjacent directory not found")
                    }

                    let entries = DirectoryScanner.listDirectory(baseDir)
                    let out = ByteBuffer()
                    let w = JsonWriter(out)
                    w.startObject()
                    w.writeName("archiveId").writeValue(archiveId)
                    w.writeName("baseDir").writeValue(baseDir)
                    w.writeName("files")
                    w.startArray()
                    var count: Int64 = 0
                    for (e in entries) {
                        let fullPath = FileUtils.joinPath(baseDir, e)
                        if (DirectoryScanner.fileExists(fullPath)) {
                            w.writeValue(e)
                            count += 1
                        }
                    }
                    w.endArray()
                    w.writeName("count").writeValue(count)
                    w.endObject()
                    w.flush()
                    return (true, String.fromUtf8(readToEnd(out)), "")
            }
        }

        // Copy a sidecar file located next to an archive into plugin cache.
        if (m == "archive.extractAdjacentFileToCache") {
            var archiveId = ""
            var fileName = ""
            var pluginDir = ""
            var cacheSubdir = "cache"
            var overwrite = true

            try {
                var buf = ByteBuffer()
                unsafe { buf.write(effectiveParams.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() == Some(BeginObject)) {
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "archiveId" => archiveId = r.readValue<String>().trimAscii()
                            case "fileName" => fileName = r.readValue<String>()
                            case "pluginDir" => pluginDir = r.readValue<String>().trimAscii()
                            case "cacheSubdir" => cacheSubdir = r.readValue<String>().trimAscii()
                            case "overwrite" => overwrite = parseBoolLoose(r.readValue<String>())
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                }
            } catch (_: Exception) {}

            if (archiveId.size == 0 || fileName.trimAscii().size == 0) {
                return (false, "{}", "missing archiveId/fileName")
            }

            // Never trust plugin-provided pluginDir; derive it from the caller namespace.
            let expectedPluginDir = "${PluginPaths.getPluginRuntimeRoot()}/${pluginNamespace.trimAscii()}"
            if (pluginNamespace.trimAscii().size == 0) {
                return (false, "{}", "missing pluginNamespace context")
            }
            if (pluginDir.size > 0) {
                if (pluginDir.trimAscii() != expectedPluginDir) {
                    return (false, "{}", "invalid pluginDir (must match expected plugin runtime dir)")
                }
            }
            pluginDir = expectedPluginDir
            if (!ensureUnderRuntimeRoot(pluginDir)) {
                return (false, "{}", "invalid pluginDir (not under runtime root)")
            }

            let safeFileName = normalizeSafeRelPath(fileName)
            if (safeFileName.size == 0 || safeFileName.contains("/")) {
                return (false, "{}", "invalid fileName")
            }

            var sub = cacheSubdir.trimAscii()
            if (sub.size == 0) { sub = "cache" }
            sub = normalizeSafeRelPath(sub)
            if (sub.size == 0) { sub = "cache" }

            let safeArchiveId = normalizeSafeRelPath(archiveId)
            if (safeArchiveId.size == 0 || safeArchiveId != archiveId.trimAscii()) {
                return (false, "{}", "invalid archiveId")
            }

            let resolved = resolveArchiveActualPath(archiveId)
            match (resolved) {
                case None => return (false, "{}", "archive not found or path unresolved")
                case Some((archiveType, actualPath)) =>
                    var baseDir = ""
                    if (archiveType == ArchiveTypes.FOLDER) {
                        baseDir = actualPath
                    } else {
                        let p = Path(actualPath)
                        baseDir = p.parent.toString().trimAscii()
                    }

                    if (baseDir.size == 0 || !DirectoryScanner.directoryExists(baseDir)) {
                        return (false, "{}", "adjacent directory not found")
                    }

                    let sourcePath = FileUtils.joinPath(baseDir, safeFileName)
                    if (!DirectoryScanner.fileExists(sourcePath)) {
                        return (false, "{}", "adjacent file not found")
                    }

                    let outPath = "${pluginDir}/${sub}/${archiveId}/${safeFileName}"
                    let outFile = Path(outPath)
                    try {
                        if (!overwrite && exists(outFile)) {
                            // Keep existing.
                        } else {
                            FileUtils.ensureDirectoryExists(outFile.parent)
                            copy(Path(sourcePath), to: outFile, overwrite: true)
                        }
                    } catch (e: Exception) {
                        return (false, "{}", "copy failed: ${e.message}")
                    }

                    let size = try {
                        FileInfo(Path(sourcePath)).size
                    } catch (_: Exception) { 0i64 }
                    let rel = "${sub}/${archiveId}/${safeFileName}"

                    let out = ByteBuffer()
                    let w = JsonWriter(out)
                    w.startObject()
                    w.writeName("archiveId").writeValue(archiveId)
                    w.writeName("fileName").writeValue(safeFileName)
                    w.writeName("outputPath").writeValue(outPath)
                    w.writeName("relativePath").writeValue(rel)
                    w.writeName("size").writeValue(size)
                    w.endObject()
                    w.flush()
                    return (true, String.fromUtf8(readToEnd(out)), "")
            }
        }

        // Export the first image ("cover") from an archive into the plugin runtime directory,
        // compute its SHA-1 (LANraragi-style thumbnail_hash), and optionally generate a JPEG for upload.
        if (m == "archive.exportCoverForSearch") {
            var archiveId = ""
            var pluginDir = ""
            var cacheSubdir = "cache"
            var overwrite = true
            var exportJpeg = true
            var maxSide: Int64 = 1280i64
            var jpegQuality: Int64 = 85i64

            try {
                var buf = ByteBuffer()
                unsafe { buf.write(effectiveParams.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() == Some(BeginObject)) {
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "archiveId" => archiveId = r.readValue<String>().trimAscii()
                            case "pluginDir" => pluginDir = r.readValue<String>().trimAscii()
                            case "cacheSubdir" => cacheSubdir = r.readValue<String>().trimAscii()
                            case "overwrite" => overwrite = parseBoolLoose(r.readValue<String>())
                            case "exportJpeg" => exportJpeg = parseBoolLoose(r.readValue<String>())
                            case "maxSide" => maxSide = parseInt64Loose(r.readValue<String>(), 1280i64)
                            case "jpegQuality" => jpegQuality = parseInt64Loose(r.readValue<String>(), 85i64)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                }
            } catch (_: Exception) {}

            if (archiveId.size == 0) {
                return (false, "{}", "missing archiveId")
            }
            if (pluginNamespace.trimAscii().size == 0) {
                return (false, "{}", "missing pluginNamespace context")
            }

            // Never trust plugin-provided pluginDir; derive it from the caller namespace.
            let expectedPluginDir = "${PluginPaths.getPluginRuntimeRoot()}/${pluginNamespace.trimAscii()}"
            if (pluginDir.size > 0) {
                if (pluginDir.trimAscii() != expectedPluginDir) {
                    return (false, "{}", "invalid pluginDir (must match expected plugin runtime dir)")
                }
            }
            pluginDir = expectedPluginDir
            if (!ensureUnderRuntimeRoot(pluginDir)) {
                return (false, "{}", "invalid pluginDir (not under runtime root)")
            }

            // Prevent traversal via archiveId. Require it to be a safe relative path segment.
            let safeArchiveId = normalizeSafeRelPath(archiveId)
            if (safeArchiveId.size == 0 || safeArchiveId != archiveId.trimAscii()) {
                return (false, "{}", "invalid archiveId")
            }

            var sub = cacheSubdir.trimAscii()
            if (sub.size == 0) { sub = "cache" }
            sub = normalizeSafeRelPath(sub)
            if (sub.size == 0) { sub = "cache" }

            let resolved = resolveArchiveActualPath(archiveId)
            match (resolved) {
                case None => return (false, "{}", "archive not found or path unresolved")
                case Some((archiveType, actualPath)) =>
                    let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archiveType)
                    let (entryName, _) = handler.getFirstImage(actualPath)
                    if (entryName.trimAscii().size == 0) {
                        return (false, "{}", "no image found in archive")
                    }

                    // Infer ext from entryName.
                    var inferredExt = ""
                    let parts = entryName.split(".")
                    if (parts.size > 1) { inferredExt = parts[parts.size - 1].trimAscii().toAsciiLower() }
                    if (inferredExt.size == 0) { inferredExt = "bin" }

                    let baseDir = "${pluginDir}/${sub}/${archiveId}"
                    let originalPath = "${baseDir}/cover_original.${inferredExt}"
                    let uploadPath = "${baseDir}/cover_upload.jpg"
                    try { FileUtils.ensureDirectoryExists(Path(baseDir)) } catch (_: Exception) {}

                    // Extract original cover.
                    if (overwrite || !exists(Path(originalPath))) {
                        let ok = handler.extractEntryToFile(actualPath, entryName, originalPath)
                        if (!ok) {
                            return (false, "{}", "extract failed")
                        }
                    }
                    let originalSha1 = sha1HexFromFile(originalPath)

                    // Prepare a JPEG for upload (EH upload/lookup expects common formats).
                    var uploadSha1 = ""
                    if (exportJpeg) {
                        if (overwrite || !exists(Path(uploadPath))) {
                            if (inferredExt == "jpg" || inferredExt == "jpeg") {
                                try {
                                    FileUtils.safeReplaceFile(Path(uploadPath), Path(originalPath))
                                } catch (e: Exception) {
                                    return (false, "{}", "failed to copy jpeg: ${e.message}")
                                }
                            } else {
                                let (exitCode, err1) = runFfmpegToJpeg(originalPath, uploadPath, maxSide, jpegQuality)
                                if (exitCode != 0 || !exists(Path(uploadPath))) {
                                    let (exit2, err2) = runImageMagickToJpeg(originalPath, uploadPath, maxSide, jpegQuality)
                                    if (exit2 != 0 || !exists(Path(uploadPath))) {
                                        return (false, "{}", "jpeg convert failed: ffmpeg=${err1}; convert=${err2}")
                                    }
                                }
                            }
                        }
                        uploadSha1 = sha1HexFromFile(uploadPath)
                    }

                    let out = ByteBuffer()
                    let w = JsonWriter(out)
                    w.startObject()
                    w.writeName("archiveId").writeValue(archiveId)
                    w.writeName("entryName").writeValue(entryName)
                    w.writeName("originalPath").writeValue(originalPath)
                    w.writeName("originalSha1").writeValue(originalSha1)
                    w.writeName("uploadPath").writeValue(if (exportJpeg) { uploadPath } else { "" })
                    w.writeName("uploadSha1").writeValue(if (exportJpeg) { uploadSha1 } else { "" })
                    w.endObject()
                    w.flush()
                    return (true, String.fromUtf8(readToEnd(out)), "")
            }
        }

        if (m == "archive.extractFileToCache") {
            var archiveId = ""
            var entryName = ""
            var pluginDir = ""
            var cacheSubdir = "cache"
            var overwrite = true

            try {
                var buf = ByteBuffer()
                unsafe { buf.write(effectiveParams.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() == Some(BeginObject)) {
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "archiveId" => archiveId = r.readValue<String>().trimAscii()
                            case "entryName" => entryName = r.readValue<String>()
                            case "pluginDir" => pluginDir = r.readValue<String>().trimAscii()
                            case "cacheSubdir" => cacheSubdir = r.readValue<String>().trimAscii()
                            case "overwrite" => overwrite = parseBoolLoose(r.readValue<String>())
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                }
            } catch (_: Exception) {}

            if (archiveId.size == 0 || entryName.trimAscii().size == 0) {
                return (false, "{}", "missing archiveId/entryName")
            }

            // Never trust plugin-provided pluginDir; derive it from the caller namespace.
            let expectedPluginDir = "${PluginPaths.getPluginRuntimeRoot()}/${pluginNamespace.trimAscii()}"
            if (pluginNamespace.trimAscii().size == 0) {
                return (false, "{}", "missing pluginNamespace context")
            }
            if (pluginDir.size > 0) {
                // Backward-compatible: accept provided pluginDir only if it matches the expected one.
                if (pluginDir.trimAscii() != expectedPluginDir) {
                    return (false, "{}", "invalid pluginDir (must match expected plugin runtime dir)")
                }
            }
            pluginDir = expectedPluginDir
            if (!ensureUnderRuntimeRoot(pluginDir)) {
                return (false, "{}", "invalid pluginDir (not under runtime root)")
            }

            let resolved = resolveArchiveActualPath(archiveId)
            match (resolved) {
                case None => return (false, "{}", "archive not found or path unresolved")
                case Some((archiveType, actualPath)) =>
                    let safeEntryRel = normalizeSafeRelPath(entryName)
                    if (safeEntryRel.size == 0) { return (false, "{}", "invalid entryName") }

                    var sub = cacheSubdir.trimAscii()
                    if (sub.size == 0) { sub = "cache" }
                    sub = normalizeSafeRelPath(sub)
                    if (sub.size == 0) { sub = "cache" }

                    // Prevent traversal via archiveId. Require it to be a safe relative path segment.
                    let safeArchiveId = normalizeSafeRelPath(archiveId)
                    if (safeArchiveId.size == 0 || safeArchiveId != archiveId.trimAscii()) {
                        return (false, "{}", "invalid archiveId")
                    }

                    let outPath = "${pluginDir}/${sub}/${safeArchiveId}/${safeEntryRel}"
                    let outFile = Path(outPath)
                    try {
                        if (!overwrite && exists(outFile)) {
                            // Keep existing.
                        } else {
                            FileUtils.ensureDirectoryExists(outFile.parent)
                            let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archiveType)
                            let ok = handler.extractEntryToFile(actualPath, entryName, outPath)
                            if (!ok) { return (false, "{}", "extract failed") }
                        }
                    } catch (e: Exception) {
                        return (false, "{}", "extract exception: ${e.message}")
                    }

                    let rel = "${sub}/${archiveId}/${safeEntryRel}"
                    let out = ByteBuffer()
                    let w = JsonWriter(out)
                    w.startObject()
                    w.writeName("archiveId").writeValue(archiveId)
                    w.writeName("entryName").writeValue(entryName)
                    w.writeName("outputPath").writeValue(outPath)
                    w.writeName("relativePath").writeValue(rel)
                    w.endObject()
                    w.flush()
                    return (true, String.fromUtf8(readToEnd(out)), "")
            }
        }

        return (false, "{}", "unknown method: ${m}")
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
        parentTaskId: Int64,
        pluginNamespace: String,
        interactiveSelectEnabled: Bool
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

            for (line in reader.lines()) {
                let trimmed = line.trimAscii()
                if (trimmed.size == 0) {
                    continue
                }

                let (kind, a, b, progress, success, payload) = parseNdjsonLine(trimmed)

                match (kind) {
                    case "call" =>
                        let id = a
                        let method = b
                        let paramsRaw = payload
                        let (ok, dataJson, err) = handleHostRpcCall(taskId, method, paramsRaw, pluginNamespace, interactiveSelectEnabled)
                        let respLine = buildHostCallResultLine(id, ok, dataJson, err)
                        process.stdInPipe.write(respLine.toArray())
                        process.stdInPipe.write("\n".toArray())
                        process.stdInPipe.flush()
                        continue
                    case "progress" =>
                        TaskModel.updateTaskProgress(taskId, progress, payload)
                        TaskIO.appendLog(taskId, "[PROGRESS] ${progress}% - ${payload}")
                        mirrorParentProgress(parentTaskId, taskId, progress, payload)
                    case "log" =>
                        let level = a.trimAscii()
                        let msg = if (level.size > 0) { "[${level}] ${payload}" } else { payload }
                        TaskIO.appendLog(taskId, msg)
                        mirrorParentLog(parentTaskId, taskId, msg)
                    case "data" =>
                        let key = a
                        TaskIO.appendLog(taskId, "[DATA] ${key}")
                        mirrorParentLog(parentTaskId, taskId, "[DATA] ${key}")
                    case "result" =>
                        finalSuccess = success
                        if (success) {
                            finalData = payload
                        } else {
                            finalError = payload
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
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("success").writeValue(finalSuccess)
            if (finalSuccess) {
                if (finalData.size > 0) {
                    w.writeName("data").jsonValue(finalData)
                }
            } else {
                w.writeName("error").writeValue(finalError)
            }
            w.endObject()
            w.flush()
            let outputJson = String.fromUtf8(readToEnd(out))

            return DenoExecutionResult(finalSuccess, finalError, outputJson, "", Int32(exitCode))

        } catch (e: Exception) {
            logger.error("executeWithStdio failed", ("error", e.message))
            return DenoExecutionResult(false, e.message, "", "", 1)
        }
    }

    /**
     * 执行登录插件
     */
    private static func executeLoginPluginDirect(taskId: Int64, plugin: PluginData, interactiveSelectEnabled: Bool): DenoExecutionResult {
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

        return executeWithStdio(taskId, "deno", denoArgs, inputJson, 0, plugin.namespace, interactiveSelectEnabled)
    }

    /**
     * 执行脚本插件（手动触发/cron）
     */
    private static func executeScriptPlugin(
        taskId: Int64,
        plugin: PluginData,
        oneshotParam: String,
        extraParams: String,
        loginCookiesJson: String,
        interactiveSelectEnabled: Bool
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

        let result = executeWithStdio(taskId, "deno", denoArgs, inputJson, 0, plugin.namespace, interactiveSelectEnabled)
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
            let trimmed = plugin.parameters.trimAscii()
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            match (r.peek()) {
                case Some(BeginArray) =>
                    // schema array -> {name: value/default_value}
                    var paramMap = HashMap<String, String>()
                    r.startArray()
                    var idx: Int64 = 0
                    while (r.peek() != EndArray) {
                        if (r.peek() != Some(BeginObject)) {
                            r.skip()
                            idx += 1
                            continue
                        }
                        var name = ""
                        var valueRaw: Option<String> = None

                        r.startObject()
                        while (r.peek() != EndObject) {
                            let n = r.readName()
                            match (n) {
                                case "name" => name = r.readValue<String>().trimAscii()
                                case "value" =>
                                    let bytes = r.readValueBytes()
                                    valueRaw = Some(String.fromUtf8(bytes))
                                case "default_value" =>
                                    // only keep default_value if value is not provided
                                    if (valueRaw.isNone()) {
                                        let bytes = r.readValueBytes()
                                        valueRaw = Some(String.fromUtf8(bytes))
                                    } else {
                                        r.skip()
                                    }
                                case _ => r.skip()
                            }
                        }
                        r.endObject()

                        let key = if (name.size > 0) { name } else { "param${idx.toString()}" }
                        match (valueRaw) {
                            case Some(v) => paramMap[key] = v
                            case None => ()
                        }

                        idx += 1
                    }
                    r.endArray()

                    if (paramMap.size == 0) {
                        return ""
                    }
                    let out = ByteBuffer()
                    let w = JsonWriter(out)
                    w.startObject()
                    for ((k, v) in paramMap) {
                        w.writeName(k).jsonValue(v)
                    }
                    w.endObject()
                    w.flush()
                    return String.fromUtf8(readToEnd(out))
                case Some(BeginObject) =>
                    // Already an object; keep as-is unless it's empty.
                    var hasField = false
                    r.startObject()
                    while (r.peek() != EndObject) {
                        hasField = true
                        r.readName()
                        r.skip()
                    }
                    r.endObject()
                    return if (hasField) { trimmed } else { "" }
                case _ => ()
            }
        } catch (_: Exception) {}

        return ""
    }

    /**
     * 执行元数据插件
     */
    private static func executeMetadataPlugin(
        taskId: Int64,
        plugin: PluginData,
        targetType: String,
        targetId: String,
        oneshotParam: String,
        extraParams: String,
        loginCookiesJson: String,
        interactiveSelectEnabled: Bool
    ): DenoExecutionResult {
        let pluginDir = "${PluginPaths.getPluginRuntimeRoot()}/${plugin.namespace}"
        let pluginFile = "${pluginDir}/Metadata.ts"

        if (!exists(pluginFile)) {
            return DenoExecutionResult(false, "Plugin file not found", "")
        }

        // Resolve target into plugin input fields.
        let effectiveType = targetType.trimAscii().toAsciiLower()
        let effectiveId = targetId.trimAscii()
        if (effectiveId.size == 0) {
            return DenoExecutionResult(false, "Missing targetId", "")
        }

        var title = ""
        var tagsString = ""
        var thumbhash = ""

        if (effectiveType == "tankoubon" || effectiveType == "tank") {
            let tankOpt = TankoubonDao.getTankoubonById(effectiveId)
            match (tankOpt) {
                case Some(t) =>
                    title = t.name
                    tagsString = TankoubonDao.getMergedTagsForTankoubon(effectiveId)
                    let coverAssetId = TankoubonDao.getTankoubonCoverAssetId(effectiveId)
                    if (coverAssetId > 0) {
                        let asset = AssetDao.getById(coverAssetId)
                        thumbhash = asset.thumbhash
                    }
                case None => return DenoExecutionResult(false, "Tankoubon not found", "")
            }
        } else {
            // Default: archive
            let archive = ArchiveDao.getArchiveById(effectiveId)
            if (archive.id.size == 0) {
                return DenoExecutionResult(false, "Archive not found", "")
            }
            title = archive.title
            tagsString = TagDao.getArchiveTags(effectiveId)
            thumbhash = archive.thumbhash
        }

        let denoArgs = buildDenoPermissions(plugin, pluginFile)
        // Allow reading the plugin runtime dir so plugins can consume files exported via host RPC
        // (e.g. archive.exportCoverForSearch).
        denoArgs.add("--allow-read=${pluginDir}")
        denoArgs.add("--allow-read=./data/thumb")
        denoArgs.add(pluginFile)

        // 合并参数
        let baseParams = buildPluginParametersJson(plugin)
        let mergedParams = mergeParamsJson(baseParams, extraParams)
        let contextParams = "{\"__target_type\":\"${effectiveType}\",\"__target_id\":\"${effectiveId}\"}"
        let finalParams = mergeParamsJson(mergedParams, contextParams)

        // 构建 stdin JSON
        let inputJson = buildStdinJson(
            "run",
            "Metadata",
            pluginDir,
            effectiveId,
            title,
            tagsString,
            thumbhash,
            oneshotParam,
            finalParams,
            loginCookiesJson,
            ""
        )

        let result = executeWithStdio(taskId, "deno", denoArgs, inputJson, 0, plugin.namespace, interactiveSelectEnabled)
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
            func parseObjectToRawMap(json: String): Option<HashMap<String, String>> {
                var buf = ByteBuffer()
                unsafe { buf.write(json.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() != Some(BeginObject)) {
                    return None
                }
                var m = HashMap<String, String>()
                r.startObject()
                while (r.peek() != EndObject) {
                    let name = r.readName()
                    let bytes = r.readValueBytes()
                    m[name] = String.fromUtf8(bytes)
                }
                r.endObject()
                return Some(m)
            }

            match (parseObjectToRawMap(baseTrimmed)) {
                case Some(baseMap) =>
                    match (parseObjectToRawMap(extraTrimmed)) {
                        case Some(extraMap) =>
                            for ((k, v) in extraMap) {
                                baseMap[k] = v
                            }
                            let out = ByteBuffer()
                            let w = JsonWriter(out)
                            w.startObject()
                            for ((k, v) in baseMap) {
                                w.writeName(k).jsonValue(v)
                            }
                            w.endObject()
                            w.flush()
                            return String.fromUtf8(readToEnd(out))
                        case None => return extraTrimmed
                    }
                case None => return extraTrimmed
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
        parentTaskId: Int64,
        interactiveSelectEnabled: Bool
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

        let result = executeWithStdio(taskId, "deno", denoArgs, inputJson, parentTaskId, plugin.namespace, interactiveSelectEnabled)
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
