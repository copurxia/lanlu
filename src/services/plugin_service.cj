package lrr4cj.services

import std.process.*
import std.time.*
import std.convert.*
import std.collection.*
import std.fs.*
import stdx.encoding.json.*
import lrr4cj.dao.*
import lrr4cj.utils.*
import stdx.log.*
import std.sync.*

/**
 * 插件执行结果
 */
public class PluginExecutionResult {
    public var success: Bool = false
    public var error: String = ""
    public var data: HashMap<String, String> = HashMap<String, String>()
    public var executionTime: Int64 = 0
    public var exitCode: Int32 = 0

    public init(success: Bool, error: String, data: HashMap<String, String>, executionTime: Int64, exitCode: Int32) {
        this.success = success
        this.error = error
        this.data = data
        this.executionTime = executionTime
        this.exitCode = exitCode
    }
}

/**
 * 插件服务类
 * 负责通过std.process调用Deno插件，处理参数转换和结果解析
 */
public class PluginService {
    private static var instance: Option<PluginService> = Option.None
    private var pluginPath: String = "./plugins"
    private var defaultTimeout: Int64 = 30000 // 30秒超时
    private var initialized: Bool = false
    private let initMutex: Mutex = Mutex()

    private init() {
        // 延迟初始化，在第一次使用时从数据库读取配置
    }

    // 私有初始化方法（懒加载）
    private func ensureInitialized(): Unit {
        initMutex.lock()
        if (!initialized) {
            pluginPath = SystemSettingsService.getPath("PLUGIN_PATH")

            getLogger("plugin_service").info("插件服务初始化", ("plugin_path", pluginPath))
            initialized = true
        }
        initMutex.unlock()
    }

    /**
     * 获取单例实例
     */
    public static func getInstance(): PluginService {
        match (instance) {
            case Some(service) =>
                service.ensureInitialized()
                return service
            case None =>
                let service = PluginService()
                service.ensureInitialized()
                instance = Some(service)
                return service
        }
    }

    /**
     * 根据插件权限构建Deno参数
     */
    private static func buildDenoPermissions(plugin: PluginData, _: String): ArrayList<String> {
        var denoArgs = ArrayList<String>()

        // 基本参数
        denoArgs.add("run")

        // 默认给予插件目录的读写权限
        let pluginDir = "./data/plugins/${plugin.namespace}"
        denoArgs.add("--allow-read=${pluginDir}")
        denoArgs.add("--allow-write=${pluginDir}")
        // 允许读取共享插件基类，支持 '../base_plugin.ts' 相对引用
        denoArgs.add("--allow-read=./data/plugins")

        // 解析插件声明的权限（JSON数组格式）
        var permissionsList = ArrayList<String>()
        let permissionsStr = plugin.permissions.trimAscii()

        if (permissionsStr.size > 0 && permissionsStr.startsWith("[") && permissionsStr.endsWith("]")) {
            // JSON数组格式
            try {
                let jsonVal = JsonValue.fromStr(permissionsStr)
                match (jsonVal) {
                    case arr: JsonArray =>
                        for (i in 0..arr.size()) {
                            match (arr[i]) {
                                case s: JsonString => permissionsList.add(s.getValue())
                                case _ => permissionsList.add(arr[i].toString())
                            }
                        }
                    case _ => ()
                }
            } catch (_: Exception) {
                // 解析失败，忽略权限
            }
        }

        var allowNetAll = false
        var netHosts = ArrayList<String>()

        for (permission in permissionsList) {
            let perm = normalizePermission(permission)
            if (perm.size == 0) {
                continue
            }

            // 处理带参数的权限，如 net=domain.com
            if (perm.contains("=")) {
                let parts = perm.split("=", 2)
                if (parts.size == 2) {
                    let permType = normalizePermission(parts[0])
                    let permValue = normalizePermission(parts[1])

                    if (permType == "net") {
                        if (permValue.size > 0) {
                            netHosts.add(permValue)
                        }
                    } else if (permType == "read") {
                        denoArgs.add("--allow-read=${permValue}")
                    } else if (permType == "write") {
                        denoArgs.add("--allow-write=${permValue}")
                    } else if (permType == "env") {
                        denoArgs.add("--allow-env=${permValue}")
                    } else if (permType == "run") {
                        if (permValue.size > 0) {
                            denoArgs.add("--allow-run=${permValue}")
                        } else {
                            denoArgs.add("--allow-run")
                        }
                    }
                }
                continue
            }

            // 处理简单权限
            if (perm == "net") {
                    allowNetAll = true
                } else if (perm == "read") {
                    denoArgs.add("--allow-read")
                } else if (perm == "write") {
                    denoArgs.add("--allow-write")
                } else if (perm == "env") {
                    denoArgs.add("--allow-env")
                } else if (perm == "run") {
                    denoArgs.add("--allow-run")
                } else if (perm == "ffi") {
                    denoArgs.add("--allow-ffi")
                } else if (perm == "hrtime") {
                    denoArgs.add("--allow-hrtime")
                }
        }

        // 汇总网络权限，避免重复 --allow-net
        if (allowNetAll) {
            denoArgs.add("--allow-net")
        } else if (netHosts.size > 0) {
            let joinedHosts = String.join(netHosts.toArray(), delimiter: ",")
            denoArgs.add("--allow-net=${joinedHosts}")
        }

        return denoArgs
    }

    /**
     * 规范化权限字符串，去除引号和空白
     */
    private static func normalizePermission(permission: String): String {
        var perm = permission.trimAscii()
        if (perm.startsWith("\"") && perm.endsWith("\"") && perm.size >= 2) {
            perm = perm[1..perm.size - 1]
        }
        return perm
    }

    /**
     * 执行命令并获取输出
     */
    private static func executeWithOutput(command: String, args: Array<String>): (Int32, Array<UInt8>, Array<UInt8>) {
        try {
            // 对于2个参数的情况，使用 launch 函数执行命令
            if (args.size == 2) {
                let process = launch(command, args[0], args[1], stdOut: ProcessRedirect.Pipe,
                    stdErr: ProcessRedirect.Pipe)
                let (exitCode, stdout, stderr) = process.waitOutput()
                return (Int32(exitCode), stdout, stderr)
            } else {
                // 对于其他情况，使用 shell 执行
                var fullCmd = command
                for (arg in args) {
                    fullCmd += " " + escapeShellArg(arg)
                }

                let process = launch("sh", "-c", fullCmd, stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                let (exitCode, stdout, stderr) = process.waitOutput()
                return (Int32(exitCode), stdout, stderr)
            }
        } catch (_: Exception) {
            return (1, Array<UInt8>(), Array<UInt8>())
        }
    }

    private static func escapeShellArg(arg: String): String {
        if (arg.size == 0) {
            return "''"
        }
        let safe = arg.replace("'", "'\"'\"'")
        return "'${safe}'"
    }

    /**
     * 扫描并发现插件 - 从TypeScript/Deno插件文件获取信息
     */
    public func discoverPlugins(): Array<PluginData> {
        var discoveredPlugins: Array<PluginData> = []
        let logger = getLogger("plugin_service")

        logger.info("开始动态插件发现扫描")

        try {
            let pluginDir = pluginPath
            if (!existsDirectory(pluginDir)) {
                logger.error("插件目录不存在")
                return discoveredPlugins
            }

            // 动态扫描插件目录，类似shinobu的逻辑
            let pluginPathObj = Path(pluginDir)
            if (!exists(pluginPathObj)) {
                logger.error("插件目录不存在")
                return discoveredPlugins
            }

            let pluginTypes = ["Metadata", "Login", "Download"]

            for (pluginType in pluginTypes) {
                let typePath = pathJoin(pluginPath, pluginType)
                let typeDir = Path(typePath)

                logger.info("扫描插件类型目录", ("type", pluginType), ("path", typePath))

                if (exists(typeDir)) {
                    let entries = DirectoryScanner.listDirectory(typePath)

                    for (entry in entries) {
                        // 只支持.ts (TypeScript/Deno) 插件文件
                        if (entry.endsWith(".ts")) {
                            let pluginFile = pathJoin(typePath, entry)

                            logger.info("发现TypeScript插件文件: ${entry}, full_path: ${pluginFile}")

                            let pluginData = createDenoPluginFromFile(pluginFile, pluginType)
                            if (pluginData.namespace.size > 0) {
                                discoveredPlugins = addPluginToArray(discoveredPlugins, pluginData)
                                logger.info(
                                    "成功解析TypeScript插件: ${pluginData.name}, namespace: ${pluginData.namespace}, type: ${pluginType}")
                            } else {
                                logger.warn("解析TypeScript插件失败: ${entry}")
                            }
                        }
                    }
                }
            }

            logger.info("插件扫描完成: total_found: ${discoveredPlugins.size.toString()}")
        } catch (e: Exception) {
            logger.error("插件扫描过程中发生异常")
        }

        return discoveredPlugins
    }

    /**
     * 从Deno/TypeScript插件文件执行并获取元数据
     */
    private func createDenoPluginFromFile(pluginFile: String, pluginType: String): PluginData {
        var pluginData = PluginData()
        let logger = getLogger("plugin_service")

        try {
            // 从文件路径提取文件名
            let pathObj = Path(pluginFile)
            let fileName = pathObj.fileName

            // 构建Deno命令来获取插件信息
            let denoPath = "deno"

            // 为插件信息获取构建最小权限参数
            var denoArgs = ArrayList<String>()
            denoArgs.add("run")
            // 获取插件信息只需要读取权限
            denoArgs.add("--allow-read=${pluginFile}")
            denoArgs.add(pluginFile)
            denoArgs.add("--action=plugin_info")

            // 执行Deno插件获取插件信息
            let startTime = DateTime.now().toUnixTimeStamp().toSeconds()
            let (exitCode, stdout, stderr) = executeWithOutput(denoPath, denoArgs.toArray())
            let executionTime = DateTime.now().toUnixTimeStamp().toSeconds() - startTime

            if (exitCode == 0) {
                let output = String.fromUtf8(stdout)

                // 解析JSON输出
                if (!output.contains("\"error\"")) {
                    // 从JSON解析插件信息
                    pluginData = parsePluginInfoFromJson(output, fileName, pluginType)
                    logger.info("成功解析Deno插件元数据: ${fileName}, execution_time: ${executionTime}")
                } else {
                    logger.error("Deno插件返回错误: ${fileName}, error: ${output}")
                }
            } else {
                let stderrStr = String.fromUtf8(stderr)
                logger.error("执行Deno插件失败: ${fileName}, exit_code: ${exitCode.toString()}, stderr: ${stderrStr}")
            }
        } catch (e: Exception) {
            logger.error("解析Deno插件文件时发生异常: ${e.message}")
        }

        return pluginData
    }



    /**
     * 从JSON解析插件信息
     */
    private func parsePluginInfoFromJson(jsonStr: String, fileName: String, pluginType: String): PluginData {
        var pluginData = PluginData()
        let logger = getLogger("plugin_service")

        try {
            // 检查JSON是否包含错误
            if (jsonStr.contains("\"error\"")) {
                throw Exception("Plugin returned error: ${jsonStr}")
            }

            // 使用JsonValue解析JSON
            let jsonValue = JsonValue.fromStr(jsonStr)

            // 设置基本信息
            pluginData.entry = fileName
            pluginData.plugin_type = pluginType
            pluginData.installed = true

            // 使用match expression解析JSON
            match (jsonValue) {
                case jsonObj: JsonObject =>
                    // 解析必需字段
                    pluginData.name = getJsonString(jsonObj, "name")
                    pluginData.namespace = getJsonString(jsonObj, "namespace")
                    pluginData.version = getJsonString(jsonObj, "version")
                    pluginData.description = getJsonString(jsonObj, "description")
                    pluginData.author = getJsonString(jsonObj, "author")
                    pluginData.icon = getJsonString(jsonObj, "icon")
                    pluginData.url_regex = getJsonString(jsonObj, "url_regex")
                    pluginData.login_from = getJsonString(jsonObj, "login_from")
                    // 默认启用动态发现到的插件，便于直接匹配URL
                    pluginData.enabled = true

                    // 获取所有字段
                    let fields = jsonObj.getFields()

                    // 解析权限字段
                    if (fields.contains("permissions")) {
                        let perms = fields["permissions"]
                        logger.info("开始解析插件权限", [("plugin", pluginData.name), ("permissions_raw", perms.toString())])
                        match (perms) {
                            case array: JsonArray =>
                                var permissionList = ArrayList<String>()
                                let size = array.size()
                                logger.info("权限数组大小", [("plugin", pluginData.name), ("array_size", size.toString())])
                                for (i in 0..size) {
                                    let itemOpt = array.get(i)
                                    match (itemOpt) {
                                        case Some(item) =>
                                            match (item) {
                                                case permStr: JsonString =>
                                                    let permission = normalizePermission(permStr.getValue())
                                                    permissionList.add(permission)
                                                    logger.info("添加权限", [("plugin", pluginData.name), ("permission", permission)])
                                                case _ =>
                                                    let permission = normalizePermission(item.toString())
                                                    permissionList.add(permission)
                                                    logger.info("添加权限(非JsonString)", [("plugin", pluginData.name), ("permission", permission)])
                                            }
                                        case None =>
                                            logger.info("数组元素为空", [("plugin", pluginData.name), ("index", i.toString())])
                                    }
                                }
                                if (permissionList.size > 0) {
                                    pluginData.permissions = String.join(permissionList.toArray(), delimiter: ",")
                                    logger.info("权限解析完成", [("plugin", pluginData.name), ("permissions", pluginData.permissions)])
                                } else {
                                    pluginData.permissions = ""
                                    logger.info("权限列表为空", [("plugin", pluginData.name)])
                                }
                            case str: JsonString =>
                                pluginData.permissions = normalizePermission(str.getValue())
                                logger.info("权限字符串解析", [("plugin", pluginData.name), ("permissions", pluginData.permissions)])
                            case _ =>
                                pluginData.permissions = normalizePermission(perms.toString())
                                logger.info("权限其他格式", [("plugin", pluginData.name), ("permissions", pluginData.permissions)])
                        }
                    } else {
                        logger.info("插件没有权限字段", [("plugin", pluginData.name)])
                    }

                    // 解析参数信息
                    if (fields.contains("parameters")) {
                        let params = fields["parameters"]
                        pluginData.parameters = params.toString()
                        pluginData.has_schema = true
                        logger.info("成功解析插件参数", ("plugin", pluginData.name),
                            ("parameters_count", getParameterCount(params)))
                    } else {
                        pluginData.has_schema = false
                        pluginData.parameters = "[]"
                    }
                case _ => throw Exception("Invalid JSON format: expected object")
            }
        } catch (e: Exception) {
            logger.error("解析插件JSON时发生异常", ("plugin", fileName), ("error", e.message))
            throw e
        }

        return pluginData
    }



    /**
     * 从JsonObject获取字符串值
     */
    private func getJsonString(jsonObj: JsonObject, key: String): String {
        let fields = jsonObj.getFields()
        if (fields.contains(key)) {
            let value = fields[key]
            match (value) {
                case jsonStr: JsonString => return jsonStr.getValue()
                case _ => throw Exception("${key} must be a string")
            }
        }
        return ""
    }

    private func appendParamsArg(args: ArrayList<String>, paramsJson: Option<String>) {
        match (paramsJson) {
            case Some(json) =>
                let trimmed = json.trimAscii()
                if (trimmed.size > 0) {
                    args.add("--params=${trimmed}")
                }
            case None => ()
        }
    }

    private func buildPluginParametersJson(plugin: PluginData): Option<String> {
        if (plugin.parameters.trimAscii().size == 0) {
            return Option.None
        }

        try {
            let jsonVal = JsonValue.fromStr(plugin.parameters)
            match (jsonVal) {
                case array: JsonArray =>
                    var mergedParams = JsonObject()
                    let size = array.size()
                    for (i in 0..size) {
                        match (array.get(i)) {
                            case Some(paramVal) =>
                                match (paramVal) {
                                    case paramObj: JsonObject =>
                                        let name = getJsonString(paramObj, "name")
                                        let key = if (name.size > 0) { name } else { "param${i}" }

                                        // 优先使用value字段，如果没有则使用default_value
                                        match (getParamValueOrDefault(paramObj)) {
                                            case Some(value) =>
                                                let paramFields = mergedParams.getFields()
                                                paramFields[key] = value
                                            case None => ()
                                        }
                                    case _ => ()
                                }
                            case None => ()
                        }
                    }
                    if (mergedParams.getFields().size > 0) {
                        return Option<String>.Some(mergedParams.toString())
                    }
                case obj: JsonObject =>
                    if (obj.getFields().size > 0) {
                        return Option<String>.Some(obj.toString())
                    }
                case _ => ()
            }
        } catch (e: Exception) {
            let logger = getLogger("plugin_service")
            logger.warn("解析插件参数失败", ("plugin", plugin.namespace), ("error", e.message), ("parameters", plugin.parameters))
        }

        return Option.None
    }

    private func getParamValueOrDefault(paramObj: JsonObject): Option<JsonValue> {
        let fields = paramObj.getFields()
        if (fields.contains("value")) {
            return Option<JsonValue>.Some(fields["value"])
        }
        if (fields.contains("default_value")) {
            return Option<JsonValue>.Some(fields["default_value"])
        }
        return Option.None
    }

    private func extractLoginCookiesJson(output: String): Option<String> {
        if (output.trimAscii().size == 0) {
            return Option.None
        }

        try {
            let jsonVal = JsonValue.fromStr(output)
            match (jsonVal) {
                case jsonObj: JsonObject =>
                    if (!getJsonBool(jsonObj, "success")) {
                        return Option.None
                    }

                    let fields = jsonObj.getFields()
                    if (fields.contains("data")) {
                        match (fields["data"]) {
                            case dataObj: JsonObject =>
                                let dataFields = dataObj.getFields()
                                if (dataFields.contains("cookies")) {
                                    match (dataFields["cookies"]) {
                                        case cookiesArr: JsonArray =>
                                            return Option<String>.Some(cookiesArr.toString())
                                        case _ => ()
                                    }
                                }
                            case _ => ()
                        }
                    }
                case _ => ()
            }
        } catch (_: Exception) {
            return Option.None
        }

        return Option.None
    }

    private func getJsonBool(jsonObj: JsonObject, key: String): Bool {
        let fields = jsonObj.getFields()
        if (fields.contains(key)) {
            let value = fields[key]
            match (value) {
                case jsonBool: JsonBool => return jsonBool.getValue()
                case jsonStr: JsonString =>
                    return matchesTrueString(jsonStr.getValue())
                case _ =>
                    return matchesTrueString(value.toString())
            }
        }
        return false
    }

    private func matchesTrueString(value: String): Bool {
        return value == "true" || value == "True" || value == "TRUE" || value == "1"
    }

    /**
     * 获取参数数量
     */
    private func getParameterCount(params: JsonValue): String {
        match (params) {
            case jsonArray: JsonArray =>
                let size = jsonArray.size()
                return "${size}"
            case _ => return "0"
        }
    }

    /**
     * 执行元数据插件
     */
    public func executeMetadataPlugin(
        plugin: PluginData,
        archiveId: String,
        oneshotParam: Option<String>,
        extraParamsJson: Option<String>
    ): PluginExecutionResult {
        let logger = getLogger("plugin_service")
        let startTime = DateTime.now().toUnixTimeStamp().toSeconds()

        logger.info("开始执行元数据插件: ${plugin.namespace}")

        let archive = ArchiveDao.getArchiveById(archiveId)
        if (archive.id.size == 0) {
            return PluginExecutionResult(false, "Archive not found", HashMap<String, String>(), 0, 1)
        }
        let tagsString = TagDao.getArchiveTags(archiveId)

        // 获取插件文件路径
        let pluginFile = "./data/plugins/${plugin.namespace}/Metadata.ts"
        if (!exists(pluginFile)) {
            logger.error("插件文件不存在: ${pluginFile}")
            return PluginExecutionResult(false, "Plugin file not found", HashMap<String, String>(), 0, 1)
        }

        // 构建Deno权限参数
        let denoPath = "deno"
        let denoArgs = buildDenoPermissions(plugin, pluginFile)

        // 常用共享数据目录（用于以图搜图/封面读取等）
        denoArgs.add("--allow-read=./data/thumb")

        // 元数据插件常用环境变量（限制读取范围）
        denoArgs.add("--allow-env=ARCHIVE_TITLE,EXISTING_TAGS,THUMBNAIL_HASH,ARCHIVE_ID")

        // 添加插件执行参数
        denoArgs.add(pluginFile)
        denoArgs.add("--action=run")
        denoArgs.add("--archive_id=${archiveId}")
        denoArgs.add("--archive_title=${archive.title}")

        match (oneshotParam) {
            case Some(v) =>
                let trimmed = v.trimAscii()
                if (trimmed.size > 0) {
                    denoArgs.add("--oneshot=${trimmed}")
                }
            case None => ()
        }

        // 合并插件配置参数 + 自定义 params JSON（自定义覆盖配置）
        let baseParamsJson = buildPluginParametersJson(plugin)
        let mergedParamsJson = mergeParamsJson(baseParamsJson, extraParamsJson)
        appendParamsArg(denoArgs, mergedParamsJson)

        // 若声明了 login_from，则先执行登录插件并将 cookies 传入
        var cookiesJsonOpt: Option<String> = Option.None
        let effectiveLoginFrom = plugin.login_from.trimAscii()
        if (effectiveLoginFrom.size > 0) {
            let loginPlugin = PluginDao.getPluginByNamespace(effectiveLoginFrom)
            if (loginPlugin.namespace.size == 0) {
                let failure = "Login plugin not found: ${effectiveLoginFrom}"
                let elapsed = DateTime.now().toUnixTimeStamp().toSeconds() - startTime
                logger.error(failure)
                return PluginExecutionResult(false, failure, HashMap<String, String>(), elapsed, 1)
            }

            let loginPluginFile = "./data/plugins/${loginPlugin.namespace}/Login.ts"
            if (!exists(loginPluginFile)) {
                let failure = "Login plugin file missing: ${loginPluginFile}"
                let elapsed = DateTime.now().toUnixTimeStamp().toSeconds() - startTime
                logger.error(failure)
                return PluginExecutionResult(false, failure, HashMap<String, String>(), elapsed, 1)
            }

            let loginParamsJson = buildPluginParametersJson(loginPlugin)
            let loginResult = executeLoginPlugin(loginPlugin, loginParamsJson)
            if (!loginResult.success) {
                let failure = "Login plugin execution failed: ${loginResult.error}"
                var resultData = HashMap<String, String>()
                resultData["error"] = loginResult.error
                let elapsed = DateTime.now().toUnixTimeStamp().toSeconds() - startTime
                logger.error(failure)
                return PluginExecutionResult(false, failure, resultData, elapsed, loginResult.exitCode)
            }

            let loginOutput = match (loginResult.data.get("output")) {
                case Some(value) => value
                case None => ""
            }
            cookiesJsonOpt = extractLoginCookiesJson(loginOutput)
            if (cookiesJsonOpt.isSome()) {
                denoArgs.add("--login_cookies=${cookiesJsonOpt.getOrThrow()}")
            } else {
                logger.warn("Login plugin ${loginPlugin.namespace} did not return cookies")
            }
        }

        // 执行插件：通过 env 注入 archive 信息
        var envArgs = ArrayList<String>()
        envArgs.add("ARCHIVE_TITLE=${archive.title}")
        envArgs.add("EXISTING_TAGS=${tagsString}")
        envArgs.add("THUMBNAIL_HASH=${archive.thumbhash}")
        envArgs.add("ARCHIVE_ID=${archiveId}")
        envArgs.add(denoPath)
        for (arg in denoArgs.toArray()) {
            envArgs.add(arg)
        }

        let (exitCode, stdout, stderr) = executeWithOutput("env", envArgs.toArray())
        let executionTime = DateTime.now().toUnixTimeStamp().toSeconds() - startTime

        if (exitCode == 0) {
            let output = String.fromUtf8(stdout)
            logger.info("插件执行成功: ${plugin.namespace}, execution_time: ${executionTime}")

            // 解析输出结果
            var resultData = HashMap<String, String>()
            resultData["output"] = output
            if (cookiesJsonOpt.isSome()) {
                resultData["login_cookies"] = cookiesJsonOpt.getOrThrow()
            }

            return PluginExecutionResult(true, output, resultData, executionTime, exitCode)
        } else {
            let errorOutput = String.fromUtf8(stderr)
            logger.error("插件执行失败: ${plugin.namespace}, exit_code: ${exitCode}, error: ${errorOutput}")

            var resultData = HashMap<String, String>()
            resultData["error"] = errorOutput

            return PluginExecutionResult(false, errorOutput, resultData, executionTime, exitCode)
        }
    }

    private func mergeParamsJson(baseParamsJson: Option<String>, extraParamsJson: Option<String>): Option<String> {
        // 没有额外参数：直接返回基础参数
        if (extraParamsJson.isNone()) {
            return baseParamsJson
        }

        let extraStr = extraParamsJson.getOrThrow()
        let extraTrimmed = extraStr.trimAscii()
        if (extraTrimmed.size == 0) {
            return baseParamsJson
        }

        // 没有基础参数：直接返回 extra
        if (baseParamsJson.isNone()) {
            return Option<String>.Some(extraTrimmed)
        }

        let baseStr = baseParamsJson.getOrThrow()
        let baseTrimmed = baseStr.trimAscii()
        if (baseTrimmed.size == 0) {
            return Option<String>.Some(extraTrimmed)
        }

        // 两者都是 JSON 对象时做合并，否则优先 extra
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
                            return Option<String>.Some(merged.toString())
                        case _ =>
                            return Option<String>.Some(extraTrimmed)
                    }
                case _ =>
                    return Option<String>.Some(extraTrimmed)
            }
        } catch (_: Exception) {
            return Option<String>.Some(extraTrimmed)
        }
    }

    /**
     * 执行登录插件
     */
    public func executeLoginPlugin(plugin: PluginData, paramsJson: Option<String>): PluginExecutionResult {
        let logger = getLogger("plugin_service")
        let startTime = DateTime.now().toUnixTimeStamp().toSeconds()

        logger.info("开始执行登录插件: ${plugin.namespace}")

        // 获取插件文件路径
        let pluginFile = "./data/plugins/${plugin.namespace}/Login.ts"
        if (!exists(pluginFile)) {
            logger.error("插件文件不存在: ${pluginFile}")
            return PluginExecutionResult(false, "Plugin file not found", HashMap<String, String>(), 0, 1)
        }

        // 构建Deno权限参数
        let denoPath = "deno"
        let denoArgs = buildDenoPermissions(plugin, pluginFile)

        // 添加插件执行参数
        denoArgs.add(pluginFile)
        denoArgs.add("--action=run")

        appendParamsArg(denoArgs, paramsJson)

        // 执行插件
        let (exitCode, stdout, stderr) = executeWithOutput(denoPath, denoArgs.toArray())
        let executionTime = DateTime.now().toUnixTimeStamp().toSeconds() - startTime

        if (exitCode == 0) {
            let output = String.fromUtf8(stdout)
            logger.info("插件执行成功: ${plugin.namespace}, execution_time: ${executionTime}")

            // 解析输出结果
            var resultData = HashMap<String, String>()
            resultData["output"] = output

            return PluginExecutionResult(true, output, resultData, executionTime, exitCode)
        } else {
            let errorOutput = String.fromUtf8(stderr)
            logger.error("插件执行失败: ${plugin.namespace}, exit_code: ${exitCode}, error: ${errorOutput}")

            var resultData = HashMap<String, String>()
            resultData["error"] = errorOutput

            return PluginExecutionResult(false, errorOutput, resultData, executionTime, exitCode)
        }
    }

    /**
     * 执行下载插件
     */
    public func executeDownloadPlugin(plugin: PluginData, url: String): PluginExecutionResult {
        let logger = getLogger("plugin_service")
        let startTime = DateTime.now().toUnixTimeStamp().toSeconds()

        logger.info("开始执行下载插件: ${plugin.namespace}")

        // 获取插件文件路径
        let pluginFile = "./data/plugins/${plugin.namespace}/Download.ts"
        if (!exists(pluginFile)) {
            logger.error("插件文件不存在: ${pluginFile}")
            return PluginExecutionResult(false, "Plugin file not found", HashMap<String, String>(), 0, 1)
        }

        // 构建Deno权限参数
        let denoPath = "deno"
        let denoArgs = buildDenoPermissions(plugin, pluginFile)

        // 添加插件执行参数
        denoArgs.add(pluginFile)
        denoArgs.add("--action=run")
        denoArgs.add("--url=${url}")

        let paramsJson = buildPluginParametersJson(plugin)
        appendParamsArg(denoArgs, paramsJson)

        var cookiesJsonOpt: Option<String> = Option.None

        let effectiveLoginFrom = plugin.login_from.trimAscii()
        if (effectiveLoginFrom.size > 0) {
            let loginPlugin = PluginDao.getPluginByNamespace(effectiveLoginFrom)
            if (loginPlugin.namespace.size == 0) {
                let failure = "Login plugin not found: ${effectiveLoginFrom}"
                let elapsed = DateTime.now().toUnixTimeStamp().toSeconds() - startTime
                logger.error(failure)
                return PluginExecutionResult(false, failure, HashMap<String, String>(), elapsed, 1)
            }

            let loginPluginFile = "./data/plugins/${loginPlugin.namespace}/Login.ts"
            if (!exists(loginPluginFile)) {
                let failure = "Login plugin file missing: ${loginPluginFile}"
                let elapsed = DateTime.now().toUnixTimeStamp().toSeconds() - startTime
                logger.error(failure)
                return PluginExecutionResult(false, failure, HashMap<String, String>(), elapsed, 1)
            }

            let loginParamsJson = buildPluginParametersJson(loginPlugin)
            let loginResult = executeLoginPlugin(loginPlugin, loginParamsJson)
            if (!loginResult.success) {
                let failure = "Login plugin execution failed: ${loginResult.error}"
                var resultData = HashMap<String, String>()
                resultData["error"] = loginResult.error
                let elapsed = DateTime.now().toUnixTimeStamp().toSeconds() - startTime
                logger.error(failure)
                return PluginExecutionResult(false, failure, resultData, elapsed, loginResult.exitCode)
            }

            let loginOutput = match (loginResult.data.get("output")) {
                case Some(value) => value
                case None => ""
            }
            cookiesJsonOpt = extractLoginCookiesJson(loginOutput)
            if (cookiesJsonOpt.isSome()) {
                denoArgs.add("--login_cookies=${cookiesJsonOpt.getOrThrow()}")
            } else {
                logger.warn("Login plugin ${loginPlugin.namespace} did not return cookies")
            }
        }

        let (exitCode, stdout, stderr) = executeWithOutput(denoPath, denoArgs.toArray())
        let executionTime = DateTime.now().toUnixTimeStamp().toSeconds() - startTime

        if (exitCode == 0) {
            let output = String.fromUtf8(stdout)
            logger.info("插件执行成功: ${plugin.namespace}, execution_time: ${executionTime}")

            // 解析输出结果
            var resultData = HashMap<String, String>()
            resultData["output"] = output
            if (cookiesJsonOpt.isSome()) {
                resultData["login_cookies"] = cookiesJsonOpt.getOrThrow()
            }

            return PluginExecutionResult(true, output, resultData, executionTime, exitCode)
        } else {
            let errorOutput = String.fromUtf8(stderr)
            logger.error("插件执行失败: ${plugin.namespace}, exit_code: ${exitCode}, error: ${errorOutput}")

            var resultData = HashMap<String, String>()
            resultData["error"] = errorOutput
            if (cookiesJsonOpt.isSome()) {
                resultData["login_cookies"] = cookiesJsonOpt.getOrThrow()
            }

            return PluginExecutionResult(false, errorOutput, resultData, executionTime, exitCode)
        }
    }

    /**
     * 获取插件配置 - 直接返回空Map，现在配置由前端处理
     */
    public func getPluginConfig(_: String): HashMap<String, String> {
        return HashMap<String, String>()
    }

    /**
     * 更新插件配置
     */
    public func updatePluginConfig(_: String, _: HashMap<String, String>): Bool {
        // 这个方法已弃用，现在配置通过控制器直接处理
        return false
    }

    /**
     * 检查插件是否可用
     */
    public func isPluginAvailable(plugin: PluginData): Bool {
        let typePath = pathJoin(pluginPath, plugin.plugin_type)
        let pluginFilePath = pathJoin(typePath, plugin.entry)
        let path = Path(pluginFilePath)
        let fileExists = exists(path)
        let logger = getLogger("plugin_service")
        logger.info("检查插件文件", ("plugin", plugin.namespace), ("path", pluginFilePath),
            ("exists", fileExists.toString()))
        return fileExists
    }

    /**
     * 添加插件到数组
     */
    private func addPluginToArray(pluginArray: Array<PluginData>, plugin: PluginData): Array<PluginData> {
        let result = Array<PluginData>(pluginArray.size + 1, {
            i => if (i < pluginArray.size) {
                pluginArray[i]
            } else {
                plugin
            }
        })
        return result
    }

    /**
     * 检查目录是否存在
     */
    private func existsDirectory(path: String): Bool {
        try {
            let dirPath = Path(path)
            if (exists(dirPath)) {
                let fileInfo = FileInfo(dirPath)

                // 如果是软链接，获取其目标并检查目标目录
                if (fileInfo.isSymbolicLink()) {
                    try {
                        let targetPath = SymbolicLink.readFrom(path, recursive: false)
                        if (exists(targetPath)) {
                            let targetFileInfo = FileInfo(targetPath)
                            return targetFileInfo.isDirectory()
                        } else {
                            return false
                        }
                    } catch (_: Exception) {
                        return false
                    }
                } else {
                    return fileInfo.isDirectory()
                }
            } else {
                return false
            }
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * 连接路径
     */
    private func pathJoin(base: String, part: String): String {
        let cleanBase = if (base.endsWith("/")) {
            base[0..base.size - 1]
        } else {
            base
        }
        let cleanPart = if (part.startsWith("/")) {
            part[1..]
        } else {
            part
        }
        return "${cleanBase}/${cleanPart}"
    }
}
