package lrr4cj.controllers

import cjoy.*
import std.collection.*
import stdx.log.*
import lrr4cj.services.*
import lrr4cj.dao.*
import lrr4cj.utils.*

/**
 * 系统设置控制器
 */
public class SystemSettingsController {

    /**
     * 获取所有设置
     * GET /api/system/settings
     */
    public static func getAllSettings(ctx: JoyContext) {
        let logger = getLogger("system_settings_controller")
        try {
            let settings = SystemSettingsService.getAllSettings()
            let json = settingsToJson(settings)
            ctx.json("{\"success\":true,\"data\":${json}}")
        } catch (e: Exception) {
            logger.error("获取系统设置失败", ("error", e.message))
            ctx.status(500)
            ctx.json("{\"success\":false,\"message\":\"获取系统设置失败: ${e.message}\"}")
        }
    }

    /**
     * 按分类获取设置
     * GET /api/system/settings/category/{category}
     */
    public static func getSettingsByCategory(ctx: JoyContext) {
        let category = ctx.getParam("category") ?? ""
        if (category.size == 0) {
            ctx.status(400)
            ctx.json("{\"success\":false,\"message\":\"分类参数不能为空\"}")
            return
        }

        let logger = getLogger("system_settings_controller")
        try {
            let settings = SystemSettingsService.getSettingsByCategory(category)
            let json = settingsToJson(settings)
            ctx.json("{\"success\":true,\"data\":${json}}")
        } catch (e: Exception) {
            logger.error("获取系统设置失败", ("category", category), ("error", e.message))
            ctx.status(500)
            ctx.json("{\"success\":false,\"message\":\"获取系统设置失败: ${e.message}\"}")
        }
    }

    /**
     * 更新单个设置
     * PUT /api/system/settings
     */
    public static func updateSetting(ctx: JoyContext) {
        let logger = getLogger("system_settings_controller")
        try {
            let body = ctx.readString()
            if (body.size == 0) {
                ctx.status(400)
                ctx.json("{\"success\":false,\"message\":\"请求体不能为空\"}")
                return
            }

            // 解析JSON（简化实现）
            let key = extractJsonValue(body, "key")
            let value = extractJsonValue(body, "value")

            if (key.size == 0) {
                ctx.status(400)
                ctx.json("{\"success\":false,\"message\":\"设置键不能为空\"}")
                return
            }

            let success = SystemSettingsService.updateSetting(key, value)
            if (success) {
                // 如果更新的是最大并发任务数，重新加载TaskPool配置
                if (key == "MAX_CONCURRENT_JOBS") {
                    TaskPoolService.getInstance().reloadMaxWorkersConfig()
                }
                ctx.json("{\"success\":true,\"message\":\"更新系统设置成功\"}")
            } else {
                ctx.status(500)
                ctx.json("{\"success\":false,\"message\":\"更新系统设置失败\"}")
            }
        } catch (e: Exception) {
            logger.error("更新系统设置失败", ("error", e.message))
            ctx.status(500)
            ctx.json("{\"success\":false,\"message\":\"更新系统设置失败: ${e.message}\"}")
        }
    }

    /**
     * 批量更新设置
     * PUT /api/system/settings/batch
     */
    public static func updateSettings(ctx: JoyContext) {
        let logger = getLogger("system_settings_controller")
        try {
            let body = ctx.readString()
            if (body.size == 0) {
                ctx.status(400)
                ctx.json("{\"success\":false,\"message\":\"请求体不能为空\"}")
                return
            }

            // 解析JSON（简化实现）
            let settingsJson = extractJsonValue(body, "settings")
            if (settingsJson.size == 0) {
                ctx.status(400)
                ctx.json("{\"success\":false,\"message\":\"设置数据不能为空\"}")
                return
            }

            // 解析设置键值对
            var settingsMap = HashMap<String, String>()
            // TODO: 解析JSON字符串，这里需要更完整的JSON解析
            // 简化实现：假设格式为 {"settings": {"key1": "value1", "key2": "value2"}}

            let success = SystemSettingsService.updateSettings(settingsMap)
            if (success) {
                ctx.json("{\"success\":true,\"message\":\"批量更新系统设置成功\"}")
            } else {
                ctx.status(500)
                ctx.json("{\"success\":false,\"message\":\"批量更新系统设置失败\"}")
            }
        } catch (e: Exception) {
            logger.error("批量更新系统设置失败", ("error", e.message))
            ctx.status(500)
            ctx.json("{\"success\":false,\"message\":\"批量更新系统设置失败: ${e.message}\"}")
        }
    }

    /**
     * 获取设置分类
     * GET /api/system/settings/categories
     */
    public static func getCategories(ctx: JoyContext) {
        let logger = getLogger("system_settings_controller")
        try {
            let categories = SystemSettingsService.getCategories()
            var json = "["
            for (i in 0..categories.size) {
                if (i > 0) {
                    json += ","
                }
                json += "\"${escapeJson(categories[i])}\""
            }
            json += "]"
            ctx.json("{\"success\":true,\"data\":${json}}")
        } catch (e: Exception) {
            logger.error("获取设置分类失败", ("error", e.message))
            ctx.status(500)
            ctx.json("{\"success\":false,\"message\":\"获取设置分类失败: ${e.message}\"}")
        }
    }

    /**
     * 重新加载设置缓存
     * POST /api/system/settings/reload
     */
    public static func reloadCache(ctx: JoyContext) {
        let logger = getLogger("system_settings_controller")
        try {
            SystemSettingsService.reloadCache()
            ctx.json("{\"success\":true,\"message\":\"重新加载设置缓存成功\"}")
        } catch (e: Exception) {
            logger.error("重新加载设置缓存失败", ("error", e.message))
            ctx.status(500)
            ctx.json("{\"success\":false,\"message\":\"重新加载设置缓存失败: ${e.message}\"}")
        }
    }

    /**
     * 辅助方法：设置列表转JSON
     */
    private static func settingsToJson(settings: Array<SystemSettingData>): String {
        var jsonParts = ArrayList<String>()
        for (setting in settings) {
            // description 已经是 JSONB 格式，直接使用
            let part = """
                {
                    "id":${setting.id},
                    "key":"${escapeJson(setting.key)}",
                    "value":"${escapeJson(setting.value)}",
                    "valueType":"${escapeJson(setting.valueType)}",
                    "category":"${escapeJson(setting.category)}",
                    "description":${setting.description},
                    "isEncrypted":${setting.isEncrypted}
                }
            """
            jsonParts.add(part)
        }
        var result = "["
        for (i in 0..jsonParts.size) {
            if (i > 0) {
                result += ",\n"
            }
            result += jsonParts[i]
        }
        result += "\n]"
        return result
    }

    /**
     * 辅助方法：转义JSON字符串
     */
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
     * 辅助方法：从JSON字符串提取值（简化实现）
     */
    private static func extractJsonValue(json: String, key: String): String {
        // 这是一个简化实现，实际应该使用完整的JSON解析器
        // 例如：{"key": "value"} 中提取 key 的值
        let pattern = "\"${key}\"\\s*:\\s*\"([^\"]+)\""
        // TODO: 使用正则表达式或JSON解析器
        return ""
    }
}
