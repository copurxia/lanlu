package lrr4cj.services

import std.collection.*
import std.sync.*
import stdx.log.*
import std.convert.*
import lrr4cj.dao.*
import lrr4cj.utils.*

/**
 * 系统设置服务
 */
public class SystemSettingsService {
    private static var cache: HashMap<String, SystemSettingData> = HashMap<String, SystemSettingData>()
    private static var cacheMutex: Mutex = Mutex()
    private static var cacheInitialized: Bool = false

    /**
     * 初始化设置（写入默认设置）
     * 每次启动时都会检查并补充缺失的设置项，同时更新description格式
     */
    public static func initializeFromEnv(): Bool {
        let logger = getLogger("system_settings_service")
        logger.info("开始初始化系统设置")

        // 创建设置表
        if (!SystemSettingsDao.createTable()) {
            logger.error("创建设置表失败")
            return false
        }

        // 获取默认设置列表
        let defaultSettings = getDefaultSettingsList()
        let existingSettings = SystemSettingsDao.getAllSettings()

        // 创建现有设置的映射（key -> SettingData）
        var existingSettingsMap = HashMap<String, SystemSettingData>()
        for (setting in existingSettings) {
            existingSettingsMap[setting.key] = setting
        }

        // 检查缺失的设置项和需要更新的设置项
        var missingSettings = ArrayList<SystemSettingData>()
        var updateSettings = ArrayList<SystemSettingData>()
        for (setting in defaultSettings) {
            if (!existingSettingsMap.contains(setting.key)) {
                missingSettings.add(setting)
                logger.info("发现缺失的设置项", ("key", setting.key), ("default_value", setting.value))
            } else {
                // 检查description格式是否正确（是否同时包含en和zh）
                let existingSetting = existingSettingsMap[setting.key]
                let needsUpdate = !isDescriptionFormatValid(existingSetting.description)
                if (needsUpdate) {
                    updateSettings.add(setting)
                    logger.info("发现需要更新description格式的设置项", ("key", setting.key))
                }
            }
        }

        // 如果有缺失的设置项，进行批量插入
        if (missingSettings.size > 0) {
            let missingArray = missingSettings.toArray()
            logger.info("补充 ${missingArray.size.toString()} 个缺失的设置项")
            let success = SystemSettingsDao.upsertSettings(missingArray)
            if (!success) {
                logger.error("补充缺失设置项失败")
                return false
            }
            logger.info("补充缺失设置项成功")
        } else {
            logger.info("所有设置项已存在，无需补充")
        }

        // 如果有需要更新的设置项，进行批量更新
        if (updateSettings.size > 0) {
            let updateArray = updateSettings.toArray()
            logger.info("更新 ${updateArray.size.toString()} 个设置项的description格式")
            let success = SystemSettingsDao.upsertSettings(updateArray)
            if (!success) {
                logger.error("更新description格式失败")
                return false
            }
            logger.info("更新description格式成功")
        } else {
            logger.info("所有设置项的description格式正确，无需更新")
        }

        // 重新加载缓存
        reloadCache()
        return true
    }

    /**
     * 检查description格式是否正确（是否同时包含en和zh）
     */
    private static func isDescriptionFormatValid(description: String): Bool {
        // 尝试解析JSON并检查是否同时包含en和zh
        try {
            // 简化实现：检查是否包含"en"和"zh"
            return description.contains("\"en\"") && description.contains("\"zh\"")
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * 获取默认设置列表（不依赖.env）
     */
    private static func getDefaultSettingsList(): Array<SystemSettingData> {
        let logger = getLogger("system_settings_service")

        var settings = ArrayList<SystemSettingData>()

        // 存储设置 - 默认值
        settings.add(createSetting("ARCHIVE_PATH", "./data/archive", "path", "storage", "归档文件目录路径"))
        settings.add(createSetting("THUMBNAIL_PATH", "./data/thumb", "path", "storage", "缩略图目录路径"))
        settings.add(createSetting("CACHE_PATH", "./data/cache", "path", "storage", "缓存目录路径"))
        settings.add(createSetting("PLUGIN_PATH", "./plugins", "path", "storage", "插件目录路径"))

        // 性能设置 - 默认值
        settings.add(createSetting("MAX_CONCURRENT_JOBS", "8", "integer", "performance", "最大并发任务数"))
        settings.add(createSetting("SCAN_FALLBACK_INTERVAL_MS", "300000", "long", "performance", "扫描回退间隔（毫秒）"))

        // 服务器信息设置 - 默认值
        settings.add(createSetting("SERVER_NAME", "兰鹿", "string", "server", "服务器名称"))
        settings.add(createSetting("SERVER_MOTD", "兰鹿轻盈，自在如风", "string", "server", "服务器欢迎消息"))

        // 定时任务/启动任务设置 - 归类到 cron 分类（不在系统设置页面显示，由定时任务管理页面管理）
        settings.add(createSetting("ENABLE_INITIAL_SCAN", "false", "boolean", "cron", "启用初始扫描"))
        settings.add(createSetting("ENABLE_INITIAL_DB_CHECK", "true", "boolean", "cron", "启用初始数据库检查"))
        settings.add(createSetting("ENABLE_INITIAL_PLUGIN_SCAN", "true", "boolean", "cron", "启用初始插件扫描"))

        // 返回设置数组
        let settingsArray = settings.toArray()
        logger.info("获取到 ${settingsArray.size.toString()} 个默认系统设置")
        return settingsArray
    }

    /**
     * 创建设置数据
     */
    private static func createSetting(key: String, value: String, valueType: String, category: String, description: String): SystemSettingData {
        let data = SystemSettingData()
        data.key = key
        data.value = value
        data.valueType = valueType
        data.category = category

        // 将字符串转换为 JSON 对象格式，同时包含英文和中文
        // 例如: {"en": "Archive Directory Path", "zh": "归档文件目录路径"}
        let descriptionMap = HashMap<String, String>()
        descriptionMap["zh"] = description

        // 根据key添加对应的英文翻译
        let enDescription = getEnglishDescription(key, description)
        descriptionMap["en"] = enDescription

        // 构建JSON字符串
        var jsonStr = "{"
        var first = true
        for ((lang, desc) in descriptionMap) {
            if (!first) {
                jsonStr += ","
            }
            jsonStr += "\"${lang}\": \"" + desc.replace("\"", "\\\"") + "\""
            first = false
        }
        jsonStr += "}"

        data.description = jsonStr
        data.isEncrypted = false
        return data
    }

    /**
     * 获取英文描述翻译
     */
    private static func getEnglishDescription(key: String, zhDescription: String): String {
        // 根据中文描述返回英文翻译
        let translations = HashMap<String, String>()
        translations["归档文件目录路径"] = "Archive Directory Path"
        translations["缩略图目录路径"] = "Thumbnail Directory Path"
        translations["缓存目录路径"] = "Cache Directory Path"
        translations["扫描定时任务表达式"] = "Scan Cron Expression"
        translations["缩略图定时任务表达式"] = "Thumbnail Cron Expression"
        translations["启用自动扫描"] = "Enable Auto Scan"
        translations["启用自动缩略图"] = "Enable Auto Thumbnail"
        translations["启用初始扫描"] = "Enable Initial Scan"
        translations["最大并发任务数"] = "Max Concurrent Jobs"
        translations["扫描回退间隔（毫秒）"] = "Scan Fallback Interval (ms)"
        translations["启用数据库检查"] = "Enable Database Check"
        translations["数据库检查定时任务表达式"] = "Database Check Cron Expression"
        translations["启用初始数据库检查"] = "Enable Initial Database Check"
        translations["启用初始插件扫描"] = "Enable Initial Plugin Scan"
        translations["插件目录路径"] = "Plugin Directory Path"
        translations["服务器名称"] = "Server Name"
        translations["服务器欢迎消息"] = "Server Welcome Message"

        return translations.get(zhDescription) ?? "System Setting"
    }

    /**
     * 重新加载缓存
     */
    public static func reloadCache(): Unit {
        cacheMutex.lock()

        cache.clear()
        let settings = SystemSettingsDao.getAllSettings()
        for (setting in settings) {
            cache[setting.key] = setting
        }
        cacheInitialized = true
        cacheMutex.unlock()
        getLogger("system_settings_service").info("系统设置缓存已更新", ("count", settings.size.toString()))
    }

    /**
     * 获取字符串值（优先从缓存）
     */
    public static func getString(key: String): String {
        // 优先从缓存获取
        cacheMutex.lock()
        if (cache.contains(key)) {
            let value = cache[key].value
            cacheMutex.unlock()
            return value
        }
        cacheMutex.unlock()

        // 缓存未命中，从数据库查询
        let settingOpt = SystemSettingsDao.getSetting(key)
        match (settingOpt) {
            case Option<SystemSettingData>.Some(setting) =>
                cacheMutex.lock()
                cache[key] = setting
                cacheMutex.unlock()
                return setting.value
            case Option<SystemSettingData>.None =>
                // 配置不存在，返回空字符串
                getLogger("system_settings_service").warn("设置未在数据库中找到", ("key", key))
                return ""
        }
    }

    /**
     * 获取布尔值
     */
    public static func getBoolean(key: String): Bool {
        let value = getString(key)
        return value == "true" || value == "1"
    }

    /**
     * 获取整数值
     */
    public static func getInt(key: String): Int32 {
        let value = getString(key)
        try {
            return Int32.parse(value)
        } catch (_) {
            return 0
        }
    }

    /**
     * 获取长整数值
     */
    public static func getLong(key: String): Int64 {
        let value = getString(key)
        try {
            return Int64.parse(value)
        } catch (_) {
            return 0
        }
    }

    /**
     * 获取路径值
     */
    public static func getPath(key: String): String {
        return getString(key)
    }

    /**
     * 更新设置
     */
    public static func updateSetting(key: String, value: String): Bool {
        let settingOpt = SystemSettingsDao.getSetting(key)
        match (settingOpt) {
            case Option<SystemSettingData>.Some(setting) =>
                setting.value = value
                let success = SystemSettingsDao.upsertSetting(setting)
                if (success) {
                    cacheMutex.lock()
                    cache[key] = setting
                    cacheMutex.unlock()
                    getLogger("system_settings_service").info("更新设置成功", ("key", key), ("value", value))
                }
                return success
            case Option<SystemSettingData>.None =>
                getLogger("system_settings_service").warn("设置不存在，将创建新设置", ("key", key))
                let newSetting = SystemSettingData()
                newSetting.key = key
                newSetting.value = value
                newSetting.valueType = "string"
                newSetting.category = "general"
                newSetting.description = ""
                newSetting.isEncrypted = false
                let success = SystemSettingsDao.upsertSetting(newSetting)
                if (success) {
                    cacheMutex.lock()
                    cache[key] = newSetting
                    cacheMutex.unlock()
                }
                return success
        }
    }

    /**
     * 批量更新设置
     */
    public static func updateSettings(settings: HashMap<String, String>): Bool {
        var settingsArray = ArrayList<SystemSettingData>()
        cacheMutex.lock()
        for ((key, value) in settings) {
            if (cache.contains(key)) {
                let setting = cache[key]
                setting.value = value
                settingsArray.add(setting)
            }
        }
        cacheMutex.unlock()

        if (settingsArray.size == 0) {
            getLogger("system_settings_service").warn("无有效设置需要更新")
            return false
        }

        let success = SystemSettingsDao.upsertSettings(settingsArray.toArray())
        if (success) {
            // 更新缓存
            for ((key, value) in settings) {
                if (cache.contains(key)) {
                    let setting = cache[key]
                    setting.value = value
                    cache[key] = setting
                }
            }
        }
        return success
    }

    /**
     * 获取所有设置（按分类）
     */
    public static func getSettingsByCategory(category: String): Array<SystemSettingData> {
        return SystemSettingsDao.getSettingsByCategory(category)
    }

    /**
     * 获取所有设置
     */
    public static func getAllSettings(): Array<SystemSettingData> {
        return SystemSettingsDao.getAllSettings()
    }

    /**
     * 获取所有分类（仅返回系统设置页面显示的分类，不包含 cron）
     */
    public static func getCategories(): Array<String> {
        return ["storage", "performance", "server"]
    }
}
