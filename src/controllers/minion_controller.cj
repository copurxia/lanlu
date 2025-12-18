package lrr4cj.controllers

import cjoy.*
import std.collection.*
import std.convert.*
import lrr4cj.models.*
import lrr4cj.views.*
import lrr4cj.dao.*
import lrr4cj.services.*
import lrr4cj.utils.*

/**
 * Minion控制器
 * 注意：任务相关的端点已迁移到 TaskPoolController
 * 此控制器现在仅负责插件管理功能
 */
public class MinionController {
    /**
     * 构建JSON响应字符串
     */
    private static func buildJsonResponse(data: HashMap<String, String>): String {
        var result = "{"
        var first = true
        for ((key, value) in data) {
            if (!first) {
                result += ","
            }
            result += "\"${key}\":\"${value}\""
            first = false
        }
        result += "}"
        return result
    }

    /**
     * 获取所有插件详情
     * GET /api/plugins
     */
    public static func getAllPlugins(ctx: JoyContext) {
        let logger = getLogger("minion_controller")

        try {
            let plugins = PluginDao.getAllPlugins()
            var result = "["
            for (i in 0..plugins.size) {
                if (i > 0) { result += "," }
                result += pluginToJson(plugins[i])
            }
            result += "]"

            logger.info("获取插件列表", [("count", plugins.size.toString())])
            ctx.json(result)
        } catch (e: Exception) {
            logger.error("获取插件列表失败")
            ResponseView.errorJson(ctx, "Failed to get plugins: ${e.message}")
        }
    }

    /**
     * 根据类型获取插件
     * GET /api/plugins/:type
     */
    public static func getPluginsByType(ctx: JoyContext) {
        let logger = getLogger("minion_controller")
        let pluginType = ctx.getParam("type") ?? ""

        if (pluginType.size == 0) {
            ResponseView.errorJson(ctx, "Plugin type is required")
            return
        }

        try {
            let plugins = PluginDao.getPluginsByType(pluginType)
            var result = "["
            for (i in 0..plugins.size) {
                if (i > 0) { result += "," }
                result += pluginToJson(plugins[i])
            }
            result += "]"

            logger.info("按类型获取插件", [("type", pluginType), ("count", plugins.size.toString())])
            ctx.json(result)
        } catch (e: Exception) {
            logger.error("按类型获取插件失败")
            ResponseView.errorJson(ctx, "Failed to get plugins by type: ${e.message}")
        }
    }

    /**
     * 根据namespace获取插件详情
     * GET /api/plugins/:namespace/details
     */
    public static func getPluginDetails(ctx: JoyContext) {
        let logger = getLogger("minion_controller")
        let namespace = ctx.getParam("namespace") ?? ""

        if (namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin namespace is required")
            return
        }

        let plugin = PluginDao.getPluginByNamespace(namespace)
        if (plugin.namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin not found")
            return
        }

        logger.info("获取插件详情", [("namespace", namespace)])
        ctx.json(pluginToJson(plugin))
    }

    
    /**
     * 获取插件配置
     * GET /api/plugins/:namespace/config
     */
    public static func getPluginConfig(ctx: JoyContext) {
        let logger = getLogger("minion_controller")
        let namespace = ctx.getParam("namespace") ?? ""

        if (namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin namespace is required")
            return
        }

        let plugin = PluginDao.getPluginByNamespace(namespace)
        if (plugin.namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin not found")
            return
        }

        // 返回插件的parameters数组，直接构建正确的JSON响应
        var response = "{\"success\": true, \"data\": {\"has_schema\": ${plugin.has_schema.toString()}, \"parameters\": ${plugin.parameters}}}"

        logger.info("获取插件配置", [("namespace", namespace), ("has_schema", plugin.has_schema.toString())])
        ctx.json(response)
    }

    /**
     * 更新插件配置
     * PUT /api/plugins/:namespace/config
     */
    public static func updatePluginConfig(ctx: JoyContext) {
        let logger = getLogger("minion_controller")
        let namespace = ctx.getParam("namespace") ?? ""

        if (namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin namespace is required")
            return
        }

        let plugin = PluginDao.getPluginByNamespace(namespace)
        if (plugin.namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin not found")
            return
        }

        // 直接接收parameters字段
        try {
            let requestObj = ctx.readJson<HashMap<String, String>>()
            match (requestObj) {
                case Some(requestData) =>
                    // 如果请求中包含parameters字段，直接使用
                    if (requestData.contains("parameters")) {
                        plugin.parameters = requestData["parameters"]
                    } else {
                        ResponseView.errorJson(ctx, "parameters field is required")
                        return
                    }
                case None =>
                    ResponseView.errorJson(ctx, "Invalid JSON in request body")
                    return
            }
        } catch (e: Exception) {
            logger.error("更新配置失败", ("error", e.message))
            ResponseView.errorJson(ctx, "Failed to parse configuration")
            return
        }
        let success = PluginDao.update(plugin)

        if (success) {
            logger.info("更新插件配置成功", ("namespace", namespace))
            var response = HashMap<String, String>()
            response["success"] = "true"
            response["message"] = "Plugin configuration updated successfully"
            ctx.json(buildJsonResponse(response))
        } else {
            ResponseView.errorJson(ctx, "Failed to update plugin configuration")
        }
    }

    /**
     * 启用或禁用插件
     * PUT /api/plugins/:namespace/enabled
     */
    public static func setPluginEnabled(ctx: JoyContext) {
        let logger = getLogger("minion_controller")
        let namespace = ctx.getParam("namespace") ?? ""

        if (namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin namespace is required")
            return
        }

        // 解析请求体
        var enabled: Bool = false

        try {
            let requestMap = ctx.readJson<HashMap<String, String>>()
            if (requestMap.isSome()) {
                let enabledStr = requestMap.getOrThrow().get("enabled") ?? "false"
                enabled = enabledStr == "true"
            }
        } catch (e: Exception) {
            logger.error("解析启用状态失败")
            ResponseView.errorJson(ctx, "Invalid JSON in request body")
            return
        }

        let success = PluginDao.setEnabled(namespace, enabled)

        if (success) {
            logger.info("设置插件状态成功", [("namespace", namespace), ("enabled", enabled.toString())])
            ResponseView.successJson(ctx, "Plugin enabled status updated successfully")
        } else {
            logger.error("设置插件状态失败")
            ResponseView.errorJson(ctx, "Failed to update plugin enabled status")
        }
    }

    /**
     * 发现并注册插件
     * POST /api/plugins/discover
     */
    public static func discoverPlugins(ctx: JoyContext) {
        let logger = getLogger("minion_controller")

        let pluginService = PluginService.getInstance()
        let discoveredPlugins = pluginService.discoverPlugins()
        var registeredCount = 0

        logger.info("插件发现完成", ("discovered", discoveredPlugins.size.toString()))

        for (plugin in discoveredPlugins) {
            logger.info("检查插件", ("namespace", plugin.namespace), ("name", plugin.name))

            let exists = PluginDao.exists(plugin.namespace)
            logger.info("插件存在性检查", ("namespace", plugin.namespace), ("exists", exists.toString()))

            if (!exists) {
                logger.info("尝试创建新插件", ("namespace", plugin.namespace))
                let created = PluginDao.create(plugin)
                logger.info("插件创建结果", [("namespace", plugin.namespace), ("created", created.toString())])

                if (created) {
                    registeredCount++
                    logger.info("注册新插件", [("namespace", plugin.namespace), ("name", plugin.name), ("has_schema", plugin.has_schema.toString())])
                } else {
                    logger.error("插件创建失败", ("namespace", plugin.namespace))
                }
            } else {
                // 插件已存在，检查是否需要更新Schema字段
                logger.info("插件已存在，检查是否需要更新Schema", ("namespace", plugin.namespace))
                let existingPlugin = PluginDao.getPluginByNamespace(plugin.namespace)

                if (existingPlugin.namespace.size > 0) {
                    // 更新现有插件的元数据与参数字段（保留用户设置的 enabled 等状态）
                    existingPlugin.name = plugin.name
                    existingPlugin.version = plugin.version
                    existingPlugin.description = plugin.description
                    existingPlugin.author = plugin.author
                    existingPlugin.entry = plugin.entry
                    existingPlugin.plugin_type = plugin.plugin_type
                    existingPlugin.url_regex = plugin.url_regex
                    existingPlugin.login_from = plugin.login_from
                    existingPlugin.permissions = plugin.permissions
                    existingPlugin.icon = plugin.icon

                    existingPlugin.parameters = mergePluginParameters(existingPlugin.parameters, plugin.parameters)
                    existingPlugin.has_schema = plugin.has_schema

                    let updated = PluginDao.update(existingPlugin)
                    logger.info("更新现有插件Schema", [("namespace", plugin.namespace), ("updated", updated.toString()), ("has_schema", plugin.has_schema.toString())])

                    if (updated) {
                        registeredCount++
                    }
                } else {
                    logger.warn("无法获取现有插件信息", ("namespace", plugin.namespace))
                }
            }
        }

        // 注册发现的插件到数据库

        var response = HashMap<String, String>()
        response["discovered"] = discoveredPlugins.size.toString()
        response["registered"] = registeredCount.toString()

        logger.info("插件发现完成", [("discovered", discoveredPlugins.size.toString()), ("registered", registeredCount.toString())])
        ctx.json(buildJsonResponse(response))
    }

    /**
     * 将插件数据转换为JSON字符串
     */
    private static func pluginToJson(plugin: PluginData): String {
        var json = "{"
        json += "\"id\":${plugin.id},"
        json += "\"name\":\"${escapeJsonString(plugin.name)}\","
        json += "\"namespace\":\"${escapeJsonString(plugin.namespace)}\","
        json += "\"version\":\"${escapeJsonString(plugin.version)}\","
        json += "\"description\":\"${escapeJsonString(plugin.description)}\","
        json += "\"author\":\"${escapeJsonString(plugin.author)}\","
        json += "\"entry\":\"${escapeJsonString(plugin.entry)}\","
        json += "\"plugin_type\":\"${escapeJsonString(plugin.plugin_type)}\","
        json += "\"tags\":\"${escapeJsonString(plugin.tags)}\","

        // 处理权限字段 - 如果为空则返回空字符串，否则将逗号分隔的字符串转换为JSON数组
        let permissionArray = plugin.permissions.split(",")
        json += "\"permissions\":["
        var firstPermission = true
        for (permission in permissionArray) {
            let trimmed = permission.trimAscii()
            if (trimmed.size == 0) {
                continue
            }
            if (!firstPermission) { json += "," }
            json += "\"${escapeJsonString(trimmed)}\""
            firstPermission = false
        }
        json += "],"

        json += "\"icon\":\"${escapeJsonString(plugin.icon)}\","
        json += "\"enabled\":${plugin.enabled},"
        json += "\"installed\":${plugin.installed},"

        // 添加has_schema字段（指示是否有配置参数）
        json += "\"has_schema\":${plugin.has_schema},"

        json += "\"created_at\":\"${escapeJsonString(plugin.created_at)}\","
        json += "\"updated_at\":\"${escapeJsonString(plugin.updated_at)}\""
        json += "}"
        return json
    }

    private static func escapeJsonString(input: String): String {
        var escaped = input
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
     * 执行插件 (旧版兼容)
     */
    public static func executePluginOld(ctx: JoyContext) {
        let plugin = ctx.getQuery("plugin") ?? ""
        let url = ctx.getQuery("url") ?? ""

        if (plugin.size == 0 || url.size == 0) {
            ResponseView.errorJson(ctx, "Plugin and URL are required")
            return
        }

        // 创建一个下载任务作为替代
        let task = MinionModel.createTask("插件执行: ${plugin}", "download")
        ctx.json(task.toJson())
    }

    // ========== 新增Schema相关API ==========

    /**
     * 获取插件配置Schema
     * GET /api/plugins/:namespace/schema
     */
    public static func getPluginSchema(ctx: JoyContext) {
        let namespace = ctx.getParam("namespace") ?? ""

        if (namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin namespace is required")
            return
        }

        let plugin = PluginDao.getPluginByNamespace(namespace)
        if (plugin.namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin not found")
            return
        }

        if (!plugin.has_schema) {
            // 插件没有Schema，返回空Schema
            var emptySchema = HashMap<String, String>()
            emptySchema["has_schema"] = "false"
            emptySchema["message"] = "Plugin does not have a configuration schema"
            ctx.json(buildJsonResponse(emptySchema))
            return
        }

        // 构建正确的JSON响应 - 返回plugininfo的原始parameters
        // 使用可变字符串来构建JSON
        var jsonResponse = "{"
        jsonResponse += "\"has_schema\": true,"
        jsonResponse += "\"parameters\": ${plugin.parameters}"
        jsonResponse += "}"
        ctx.header("Content-Type", "application/json; charset=utf-8").string(jsonResponse)
    }

    /**
     * 验证插件配置
     * POST /api/plugins/:namespace/validate
     */
    /*
    public static func validatePluginConfig(ctx: JoyContext) {
        let logger = getLogger("minion_controller")
        let namespace = ctx.getParam("namespace") ?? ""

        if (namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin namespace is required")
            return
        }

        let plugin = PluginDao.getPluginByNamespace(namespace)
        if (plugin.namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin not found")
            return
        }

        // 解析请求体中的配置
        var requestBody = ctx.getRequestBody()
        if (requestBody.size == 0) {
            ResponseView.errorJson(ctx, "Request body is required")
            return
        }

        try {
            let jsonValue = JsonValue.fromStr(requestBody)
            match (jsonValue) {
                case configObj: JsonObject =>
                    // 转换为HashMap<String, String>
                    var configMap = HashMap<String, String>()
                    for ((key, value) in configObj.getFields()) {
                        match (value) {
                            case jsonStr: JsonString => configMap[key] = jsonStr.getValue()
                            case _ => configMap[key] = value.toString()
                        }
                    }

                    // 如果插件有Schema，进行验证
                    if (plugin.has_schema) {
                        try {
                            let schemaJson = JsonValue.fromStr(plugin.parameters_schema)
                            match (schemaJson) {
                                case schemaObj: JsonObject =>
                                    // 暂时禁用schema验证
                                    let isValid = true
                                    let errorMessage = ""

                                    var response = HashMap<String, String>()
                                    response["valid"] = if (isValid) { "true" } else { "false" }
                                    if (!isValid) {
                                        response["error"] = errorMessage
                                    }

                                    ctx.json(buildJsonResponse(response))
                                case _ =>
                                    ResponseView.errorJson(ctx, "Invalid schema format")
                            }
                        } catch (e: Exception) {
                            logger.error("Schema解析失败", ("error", e.message))
                            ResponseView.errorJson(ctx, "Failed to parse schema")
                        }
                    } else {
                        // 没有Schema的配置总是有效
                        var response = HashMap<String, String>()
                        response["valid"] = "true"
                        response["message"] = "Plugin does not have a schema, configuration is always valid"
                        ctx.json(buildJsonResponse(response))
                    }
                case _ =>
                    ResponseView.errorJson(ctx, "Invalid JSON format in request body")
            }
        } catch (e: Exception) {
            logger.error("配置验证失败", ("error", e.message))
            ResponseView.errorJson(ctx, "Failed to parse configuration")
        }
    }
    */

    /**
     * 获取插件默认配置
     * GET /api/plugins/:namespace/defaults
     */
    /*
    public static func getPluginDefaults(ctx: JoyContext) {
        let logger = getLogger("minion_controller")
        let namespace = ctx.getParam("namespace") ?? ""

        if (namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin namespace is required")
            return
        }

        let plugin = PluginDao.getPluginByNamespace(namespace)
        if (plugin.namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin not found")
            return
        }

        var defaultConfig = HashMap<String, String>()

        // 如果插件有Schema，生成默认配置
        // 暂时禁用schema处理
        if (false) { // plugin.has_schema
            try {
                let schemaJson = JsonValue.fromStr(plugin.parameters_schema)
                match (schemaJson) {
                    case schemaObj: JsonObject =>
                        // 暂时禁用schema服务，保持空配置
                        defaultConfig = HashMap<String, String>()
                    case _ =>
                        logger.error("插件Schema格式错误")
                }
            } catch (e: Exception) {
                logger.error("解析插件Schema失败", ("error", e.message))
            }
        }

        // 构建响应
        var response = HashMap<String, String>()
        response["has_schema"] = if (plugin.has_schema) { "true" } else { "false" }

        // 将默认配置转换为JSON字符串
        if (defaultConfig.size > 0) {
            var configJson = "{"
            var first = true
            for ((key, value) in defaultConfig) {
                if (!first) { configJson += "," }
                configJson += "\"${key}\":\"${value}\""
                first = false
            }
            configJson += "}"
            response["defaults"] = configJson
        } else {
            response["defaults"] = "{}"
        }

        ctx.json(buildJsonResponse(response))
    }
    */

    /**
     * 更新插件配置（带验证）
     * PUT /api/plugins/:namespace/config
     */
    /*
    public static func updatePluginConfigWithValidation(ctx: JoyContext) {
        let logger = getLogger("minion_controller")
        let namespace = ctx.getParam("namespace") ?? ""

        if (namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin namespace is required")
            return
        }

        let plugin = PluginDao.getPluginByNamespace(namespace)
        if (plugin.namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin not found")
            return
        }

        // 解析请求体中的配置
        var requestBody = ctx.getRequestBody()
        if (requestBody.size == 0) {
            ResponseView.errorJson(ctx, "Request body is required")
            return
        }

        try {
            let jsonValue = JsonValue.fromStr(requestBody)
            match (jsonValue) {
                case configObj: JsonObject =>
                    // 转换为HashMap<String, String>
                    var configMap = HashMap<String, String>()
                    for ((key, value) in configObj.getFields()) {
                        match (value) {
                            case jsonStr: JsonString => configMap[key] = jsonStr.getValue()
                            case _ => configMap[key] = value.toString()
                        }
                    }

                    // 如果插件有Schema，先进行验证
                    if (plugin.has_schema) {
                        try {
                            let schemaJson = JsonValue.fromStr(plugin.parameters_schema)
                            match (schemaJson) {
                                case schemaObj: JsonObject =>
                                    // 暂时禁用schema验证
                                    let isValid = true
                                    let errorMessage = ""

                                    if (!isValid) {
                                        ResponseView.errorJson(ctx, "Configuration validation failed: ${errorMessage}")
                                        return
                                    }
                                case _ =>
                                    ResponseView.errorJson(ctx, "Invalid schema format")
                                    return
                            }
                        } catch (e: Exception) {
                            logger.error("Schema解析失败", ("error", e.message))
                            ResponseView.errorJson(ctx, "Failed to parse schema")
                            return
                        }
                    }

                    // 验证通过，更新配置
                    plugin.setConfigFromMap(configMap)
                    let updated = PluginDao.updateWithSchema(plugin)

                    if (updated) {
                        var response = HashMap<String, String>()
                        response["success"] = "true"
                        response["message"] = "Plugin configuration updated successfully"
                        ctx.json(buildJsonResponse(response))
                    } else {
                        ResponseView.errorJson(ctx, "Failed to update plugin configuration")
                    }
                case _ =>
                    ResponseView.errorJson(ctx, "Invalid JSON format in request body")
            }
        } catch (e: Exception) {
            logger.error("更新配置失败", ("error", e.message))
            ResponseView.errorJson(ctx, "Failed to parse configuration")
        }
    }
    */

    }
