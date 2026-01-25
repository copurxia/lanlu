package lanlu.controllers

import cjoy.*
import std.collection.*
import std.convert.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.views.*
import lanlu.dao.*
import lanlu.services.*
import lanlu.utils.*

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
        let out = ByteBuffer()
        let w = JsonWriter(out)

        w.startObject()
        w.writeName("id").writeValue(plugin.id)
        w.writeName("name").writeValue(plugin.name)
        w.writeName("namespace").writeValue(plugin.namespace)
        w.writeName("version").writeValue(plugin.version)
        w.writeName("description").writeValue(plugin.description)
        w.writeName("author").writeValue(plugin.author)
        w.writeName("entry").writeValue(plugin.entry)
        w.writeName("plugin_type").writeValue(plugin.plugin_type)
        w.writeName("tags").writeValue(plugin.tags)

        w.writeName("permissions")
        w.startArray()
        let permissionArray = plugin.permissions.split(",")
        for (permission in permissionArray) {
            let trimmed = permission.trimAscii()
            if (trimmed.size == 0) { continue }
            w.writeValue(trimmed)
        }
        w.endArray()

        w.writeName("icon").writeValue(plugin.icon)
        w.writeName("enabled").writeValue(plugin.enabled)
        w.writeName("installed").writeValue(plugin.installed)
        w.writeName("update_url").writeValue(plugin.update_url)

        w.writeName("has_schema").writeValue(plugin.has_schema)
        // Stored as raw JSON string (schema array/object)
        let params = plugin.parameters.trimAscii()
        w.writeName("parameters").jsonValue(if (params.size > 0) { params } else { "[]" })

        w.writeName("created_at").writeValue(plugin.created_at)
        w.writeName("updated_at").writeValue(plugin.updated_at)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
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

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(true)
        w.writeName("message").writeValue(r.message)
        w.writeName("filename").writeValue(r.filename)
        w.writeName("plugin_type").writeValue(r.plugin_type)
        w.writeName("namespace").writeValue(r.namespace)
        w.writeName("old_version").writeValue(r.old_version)
        w.writeName("new_version").writeValue(r.new_version)
        w.writeName("clear_parameters").writeValue(r.clear_parameters)
        w.writeName("reason").writeValue(r.reason)
        w.writeName("scan_task_id").writeValue(r.scan_task_id)
        w.endObject()
        w.flush()
        ctx.json(String.fromUtf8(readToEnd(out)))
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

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(true)
        w.writeName("message").writeValue(r.message)
        w.writeName("namespace").writeValue(r.namespace)
        w.writeName("old_version").writeValue(r.old_version)
        w.writeName("new_version").writeValue(r.new_version)
        w.writeName("clear_parameters").writeValue(r.clear_parameters)
        w.writeName("reason").writeValue(r.reason)
        w.writeName("scan_task_id").writeValue(r.scan_task_id)
        w.endObject()
        w.flush()
        ctx.json(String.fromUtf8(readToEnd(out)))
    }
}
