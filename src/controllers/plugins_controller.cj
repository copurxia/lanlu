package lrr4cj.controllers

import cjoy.*
import std.collection.*
import std.convert.*
import lrr4cj.views.*
import lrr4cj.dao.*
import lrr4cj.services.*
import lrr4cj.utils.*

/**
 * 插件控制器
 * 负责插件的管理功能，包括插件的注册、配置和状态管理
 */
public class PluginsController {
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
        let logger = getLogger("plugins_controller")

        try {
            let plugins = PluginDao.getAllPlugins()
            var result = "["
            for (i in 0..plugins.size) {
                if (i > 0) { result += "," }
                result += pluginToJson(plugins[i])
            }
            result += "]"

            logger.debug("获取插件列表", [("count", plugins.size.toString())])
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
        let logger = getLogger("plugins_controller")
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

            logger.debug("按类型获取插件", [("type", pluginType), ("count", plugins.size.toString())])
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
        let logger = getLogger("plugins_controller")
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

        logger.debug("获取插件详情", [("namespace", namespace)])
        ctx.json(pluginToJson(plugin))
    }

    
    /**
     * 获取插件配置
     * GET /api/plugins/:namespace/config
     */
    public static func getPluginConfig(ctx: JoyContext) {
        let logger = getLogger("plugins_controller")
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

        logger.debug("获取插件配置", [("namespace", namespace), ("has_schema", plugin.has_schema.toString())])
        ctx.json(response)
    }

    /**
     * 更新插件配置
     * PUT /api/plugins/:namespace/config
     */
    public static func updatePluginConfig(ctx: JoyContext) {
        let logger = getLogger("plugins_controller")
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
            logger.debug("更新插件配置成功", ("namespace", namespace))
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
        let logger = getLogger("plugins_controller")
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
            logger.debug("设置插件状态成功", [("namespace", namespace), ("enabled", enabled.toString())])
            ResponseView.successJson(ctx, "Plugin enabled status updated successfully")
        } else {
            logger.error("设置插件状态失败")
            ResponseView.errorJson(ctx, "Failed to update plugin enabled status")
        }
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
        json += "\"update_url\":\"${escapeJsonString(plugin.update_url)}\","

        // 添加has_schema字段（指示是否有配置参数）
        json += "\"has_schema\":${plugin.has_schema},"
        json += "\"parameters\":${plugin.parameters},"

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
     * 删除插件
     * DELETE /api/plugins/:namespace
     */
    public static func deletePlugin(ctx: JoyContext) {
        let logger = getLogger("plugins_controller")
        let namespace = ctx.getParam("namespace") ?? ""

        if (namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin namespace is required")
            return
        }

        let err = PluginManagerService.deletePlugin(namespace)
        if (err.size > 0) {
            logger.error("删除插件失败", [("namespace", namespace), ("error", err)])
            ResponseView.errorJson(ctx, err)
            return
        }
        logger.info("删除插件成功", [("namespace", namespace)])
        ResponseView.successJson(ctx, "Plugin deleted successfully")
    }

    /**
     * 安装插件
     * POST /api/plugins/install
     * 只需要提供 URL，类型从插件元数据中自动获取
     */
    public static func installPlugin(ctx: JoyContext) {
        let logger = getLogger("plugins_controller")

        // 解析请求体
        var url: String = ""

        try {
            let requestMap = ctx.readJson<HashMap<String, String>>()
            match (requestMap) {
                case Some(data) =>
                    url = data.get("url") ?? ""
                case None =>
                    ResponseView.errorJson(ctx, "Invalid JSON in request body")
                    return
            }
        } catch (e: Exception) {
            logger.error("解析请求体失败", [("error", e.message)])
            ResponseView.errorJson(ctx, "Failed to parse request body")
            return
        }

        // 验证参数
        if (url.size == 0) {
            ResponseView.errorJson(ctx, "URL is required")
            return
        }

        // 验证 URL 格式（必须是 .ts 文件）
        if (!url.endsWith(".ts")) {
            ResponseView.errorJson(ctx, "URL must point to a .ts file")
            return
        }

        logger.info("开始下载/安装插件", [("url", url)])
        let r = PluginManagerService.installFromUrl(url)
        if (!r.success) {
            logger.error("安装插件失败", [("url", url), ("error", r.message)])
            ResponseView.errorJson(ctx, r.message)
            return
        }

        var response2 = "{"
        response2 += "\"success\": true,"
        response2 += "\"message\": \"${escapeJsonString(r.message)}\","
        response2 += "\"filename\": \"${escapeJsonString(r.filename)}\","
        response2 += "\"plugin_type\": \"${escapeJsonString(r.plugin_type)}\","
        response2 += "\"namespace\": \"${escapeJsonString(r.namespace)}\","
        response2 += "\"old_version\": \"${escapeJsonString(r.old_version)}\","
        response2 += "\"new_version\": \"${escapeJsonString(r.new_version)}\","
        response2 += "\"clear_parameters\": ${r.clear_parameters},"
        response2 += "\"reason\": \"${escapeJsonString(r.reason)}\","
        response2 += "\"scan_task_id\": ${r.scan_task_id}"
        response2 += "}"
        ctx.json(response2)
    }

    /**
     * 更新插件
     * POST /api/plugins/:namespace/update
     * 使用插件声明的 update_url 更新
     */
    public static func updatePlugin(ctx: JoyContext) {
        let logger = getLogger("plugins_controller")
        let namespace = ctx.getParam("namespace") ?? ""

        if (namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin namespace is required")
            return
        }

        logger.info("开始更新插件", [("namespace", namespace)])
        let r = PluginManagerService.updateFromDatabase(namespace)
        if (!r.success) {
            logger.error("更新插件失败", [("namespace", namespace), ("error", r.message)])
            ResponseView.errorJson(ctx, r.message)
            return
        }

        var response2 = "{"
        response2 += "\"success\": true,"
        response2 += "\"message\": \"${escapeJsonString(r.message)}\","
        response2 += "\"namespace\": \"${escapeJsonString(r.namespace)}\","
        response2 += "\"old_version\": \"${escapeJsonString(r.old_version)}\","
        response2 += "\"new_version\": \"${escapeJsonString(r.new_version)}\","
        response2 += "\"clear_parameters\": ${r.clear_parameters},"
        response2 += "\"reason\": \"${escapeJsonString(r.reason)}\","
        response2 += "\"scan_task_id\": ${r.scan_task_id}"
        response2 += "}"
        ctx.json(response2)
    }
}
