package lanlu.task_runners

import std.process.*
import std.collection.*
import std.fs.*
import std.io.*
import std.convert.*
import std.sync.*
import std.time.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import stdx.log.*
import lanlu.dao.*
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
                case "Metadata" => executeMetadataPlugin(taskId, plugin, targetType, targetId, oneshotParam, extraParams, loginCookiesJson)
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
     * 解析插件输出的 NDJSON 消息
     * 返回: (type, progress, message, success, data/error)
     */
    private static func parsePluginMessage(line: String): (String, Int32, String, Bool, String) {
        let trimmed = line.trimAscii()
        if (trimmed.size == 0) {
            return ("", 0, "", false, "")
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            if (r.peek() != Some(BeginObject)) {
                return ("raw", 0, trimmed, false, "")
            }

            var msgType = ""
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
                case "progress" => return ("progress", progress, message, false, "")
                case "log" => return ("log", 0, "[${level}] ${message}", false, "")
                case "data" => return ("data", 0, key, false, valueRaw)
                case "result" => return ("result", 0, "", success, if (success) { dataRaw } else { error })
                case _ => return ("unknown", 0, trimmed, false, "")
            }
        } catch (_: Exception) {
            return ("raw", 0, trimmed, false, "")
        }
    }

    /**
     * 解析插件发起的 Host RPC 调用请求（NDJSON 单行）
     * 格式：
     *   {"type":"call","id":"...","method":"tags.list","params":{...}}
     */
    private static func parseHostCallRequest(line: String): Option<(String, String, String)> {
        let trimmed = line.trimAscii()
        if (trimmed.size == 0) { return None }
        if (!trimmed.startsWith("{")) { return None }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) { return None }

            var msgType = ""
            var id = ""
            var method = ""
            var paramsRaw = "{}"

            r.startObject()
            while (r.peek() != EndObject) {
                let n = r.readName()
                match (n) {
                    case "type" => msgType = r.readValue<String>().trimAscii()
                    case "id" => id = r.readValue<String>().trimAscii()
                    case "method" => method = r.readValue<String>().trimAscii()
                    case "params" => paramsRaw = String.fromUtf8(r.readValueBytes())
                    case _ => r.skip()
                }
            }
            r.endObject()

            if (msgType != "call") { return None }
            if (id.size == 0 || method.size == 0) { return None }
            return Some((id, method, paramsRaw))
        } catch (_: Exception) {
            return None
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

    private static func handleHostRpcCall(method: String, paramsRaw: String): (Bool, String, String) {
        // returns: (success, dataJson, error)
        let m = method.trimAscii()
        let paramsTrimmed = paramsRaw.trimAscii()
        let effectiveParams = if (paramsTrimmed.size > 0) { paramsTrimmed } else { "{}" }

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

                // Host RPC: plugin can request backend operations via NDJSON "call".
                match (parseHostCallRequest(trimmed)) {
                    case Some((id, method, paramsRaw)) =>
                        let (ok, dataJson, err) = handleHostRpcCall(method, paramsRaw)
                        let respLine = buildHostCallResultLine(id, ok, dataJson, err)
                        process.stdInPipe.write(respLine.toArray())
                        process.stdInPipe.write("\n".toArray())
                        process.stdInPipe.flush()
                        continue
                    case None => ()
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
        loginCookiesJson: String
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
            effectiveId,
            title,
            tagsString,
            thumbhash,
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
