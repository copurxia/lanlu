package lanlu.contexts.system.interfaces.http

import ignite.*
import std.collection.*
import stdx.log.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.contexts.task.application.TaskPoolService
import lanlu.contexts.system.infrastructure.persistence.*
import lanlu.contexts.system.application.*
import lanlu.shared.utils.*

class SystemSettingUpdateReq <: JsonDeserializable<SystemSettingUpdateReq> {
    var key: String = ""
    var value: String = ""

    private static func readValueAsString(r: JsonReader): String {
        match (r.peek()) {
            case Some(BeginObject) =>
                let bytes = r.readValueBytes()
                return String.fromUtf8(bytes)
            case Some(BeginArray) =>
                let bytes = r.readValueBytes()
                return String.fromUtf8(bytes)
            case Some(_) =>
                return r.readValue<String>()
            case None =>
                return ""
        }
    }

    public static func fromJson(r: JsonReader): SystemSettingUpdateReq {
        let req = SystemSettingUpdateReq()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "key" => req.key = r.readValue<String>().trimAscii()
                            case "value" => req.value = readValueAsString(r)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }
        return req
    }
}

class SystemSettingsBatchUpdateReq <: JsonDeserializable<SystemSettingsBatchUpdateReq> {
    var settings: HashMap<String, String> = HashMap<String, String>()

    private static func readValueAsString(r: JsonReader): String {
        match (r.peek()) {
            case Some(BeginObject) =>
                let bytes = r.readValueBytes()
                return String.fromUtf8(bytes)
            case Some(BeginArray) =>
                let bytes = r.readValueBytes()
                return String.fromUtf8(bytes)
            case Some(_) =>
                return r.readValue<String>()
            case None =>
                return ""
        }
    }

    private static func readSettingsObject(r: JsonReader): HashMap<String, String> {
        var settingsMap = HashMap<String, String>()
        match (r.peek()) {
            case Some(BeginObject) =>
                r.startObject()
                while (r.peek() != EndObject) {
                    let k = r.readName()
                    settingsMap[k] = readValueAsString(r)
                }
                r.endObject()
            case _ =>
                r.skip()
        }
        return settingsMap
    }

    public static func fromJson(r: JsonReader): SystemSettingsBatchUpdateReq {
        let req = SystemSettingsBatchUpdateReq()
        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "settings" => req.settings = readSettingsObject(r)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }
        return req
    }
}

/**
 * 系统设置控制器
 */
public class SystemSettingsController {

    /**
     * 获取所有设置
     * GET /api/system/settings
     */
    public static func getAllSettings(ctx: Ctx) {
        let logger = getLogger("system_settings_controller")
        try {
            let settings = SystemSettingsService.filterVisibleSettings(SystemSettingsDao.getAllSettings())
            let json = settingsToJson(settings)
            ctx.json("{\"success\":true,\"data\":${json}}")
        } catch (e: Exception) {
            logger.error("获取系统设置失败", ("error", e.message))
            ctx.status(500)
            ctx.json("{\"success\":false,\"message\":\"获取系统设置失败: ${e.message}\"}")
        }
    }

    /**
     * 更新单个设置
     * PUT /api/system/settings
     */
    public static func updateSetting(ctx: Ctx) {
        let logger = getLogger("system_settings_controller")
        try {
            let body = ctx.bodyString()
            if (body.size == 0) {
                ctx.status(400)
                ctx.json("{\"success\":false,\"message\":\"请求体不能为空\"}")
                return
            }

            let req = JsonCodec.decode<SystemSettingUpdateReq>(body)
            let key = req.key
            let value = req.value

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
    public static func updateSettings(ctx: Ctx) {
        let logger = getLogger("system_settings_controller")
        try {
            let body = ctx.bodyString()
            if (body.size == 0) {
                ctx.status(400)
                ctx.json("{\"success\":false,\"message\":\"请求体不能为空\"}")
                return
            }

            let req = JsonCodec.decode<SystemSettingsBatchUpdateReq>(body)
            let settingsMap = req.settings
            if (settingsMap.size == 0) {
                ctx.status(400)
                ctx.json("{\"success\":false,\"message\":\"设置数据格式不正确\"}")
                return
            }

            let success = SystemSettingsService.updateSettings(settingsMap)
            if (success) {
                if (settingsMap.contains("MAX_CONCURRENT_JOBS")) {
                    TaskPoolService.getInstance().reloadMaxWorkersConfig()
                }
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
    public static func getCategories(ctx: Ctx) {
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
    public static func reloadCache(ctx: Ctx) {
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

}
