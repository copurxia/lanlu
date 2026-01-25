package lanlu.controllers

import cjoy.*
import std.collection.*
import stdx.log.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.services.*
import lanlu.models.*
import lanlu.dao.*
import lanlu.utils.*

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
            let settingsJson = extractJsonObject(body, "settings")
            if (settingsJson.size == 0) {
                ctx.status(400)
                ctx.json("{\"success\":false,\"message\":\"设置数据不能为空\"}")
                return
            }

            // 解析设置键值对
            var settingsMap = parseSettingsObject(settingsJson)
            if (settingsMap.size == 0) {
                ctx.status(400)
                ctx.json("{\"success\":false,\"message\":\"设置数据格式不正确\"}")
                return
            }

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
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("success").writeValue(true)
            w.writeName("data")
            w.startArray()
            for (c in categories) {
                w.writeValue(c)
            }
            w.endArray()
            w.endObject()
            w.flush()
            ctx.json(String.fromUtf8(readToEnd(out)))
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
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startArray()
        for (setting in settings) {
            w.startObject()
            w.writeName("id").writeValue(setting.id)
            w.writeName("key").writeValue(setting.key)
            w.writeName("value").writeValue(setting.value)
            w.writeName("valueType").writeValue(setting.valueType)
            w.writeName("category").writeValue(setting.category)
            // description is stored as JSONB; embed as raw JSON value.
            let desc = setting.description.trimAscii()
            w.writeName("description").jsonValue(if (desc.size > 0) { desc } else { "null" })
            w.writeName("isEncrypted").writeValue(setting.isEncrypted)
            w.endObject()
        }
        w.endArray()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    /**
     * 辅助方法：从JSON字符串提取值
     */
    private static func extractJsonValue(json: String, key: String): String {
        if (json.size == 0) {
            return ""
        }
        
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(json.rawData()) }
            let r = JsonReader(buf)

            match (r.peek()) {
                case Some(BeginObject) =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        if (n == key) {
                            return r.readValue<String>()
                        } else {
                            r.skip()
                        }
                    }
                    r.endObject()
                case _ => return ""
            }
        } catch (e: Exception) {
            return ""
        }
        
        return ""
    }
    
    /**
     * 辅助方法：从JSON字符串中提取对象
     */
    private static func extractJsonObject(json: String, key: String): String {
        if (json.size == 0) {
            return ""
        }
        
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(json.rawData()) }
            let r = JsonReader(buf)

            match (r.peek()) {
                case Some(BeginObject) =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        if (n == key) {
                            let bytes = r.readValueBytes()
                            return String.fromUtf8(bytes)
                        } else {
                            r.skip()
                        }
                    }
                    r.endObject()
                case _ => return ""
            }
        } catch (e: Exception) {
            return ""
        }
        
        return ""
    }
    
    /**
     * 辅助方法：解析设置对象为键值对
     */
    private static func parseSettingsObject(settingsJson: String): HashMap<String, String> {
        var settingsMap = HashMap<String, String>()
        
        if (settingsJson.size == 0) {
            return settingsMap
        }
        
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(settingsJson.rawData()) }
            let r = JsonReader(buf)

            match (r.peek()) {
                case Some(BeginObject) =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let k = r.readName()
                        match (r.peek()) {
                            case Some(BeginObject) =>
                                let bytes = r.readValueBytes()
                                settingsMap[k] = String.fromUtf8(bytes)
                            case Some(BeginArray) =>
                                let bytes = r.readValueBytes()
                                settingsMap[k] = String.fromUtf8(bytes)
                            case Some(_) =>
                                settingsMap[k] = r.readValue<String>()
                            case None => break
                        }
                    }
                    r.endObject()
                case _ => return settingsMap
            }
        } catch (_: Exception) {
            return settingsMap
        }
        
        return settingsMap
    }
}
