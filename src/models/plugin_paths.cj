package lanlu.models

import std.fs.*
import lanlu.utils.*

/**
 * 插件路径工具：集中管理 PLUGIN_PATH / CACHE_PATH 派生路径
 * 放在 models 中以避免 services <-> task_runners 循环依赖，以及 utils -> models 循环依赖。
 */
public class PluginPaths {
    public static func getPluginStorageRoot(): String {
        SystemSettingsService.getPath("PLUGIN_PATH")
    }

    public static func getCacheRoot(): String {
        SystemSettingsService.getPath("CACHE_PATH")
    }

    public static func getPluginRuntimeRoot(): String {
        FileUtils.joinPath(getCacheRoot(), "plugins")
    }

    public static func getPluginTempRoot(): String {
        FileUtils.joinPath(getCacheRoot(), "plugin_temp")
    }

    public static func getPluginInfoTempRoot(): String {
        FileUtils.joinPath(getCacheRoot(), "plugin_info_temp")
    }

    public static func buildPluginFilePath(pluginType: String, entry: String): String {
        // 所有插件统一存放在 PLUGIN_PATH 根目录
        // entry 可以是：
        // - 文件名：plugin.ts
        // - 相对路径：subfolder/plugin.ts
        FileUtils.joinPath(getPluginStorageRoot(), entry)
    }

    public static func ensurePluginDirs(): Unit {
        FileUtils.ensureDirectoryExists(Path(getPluginStorageRoot()))
        FileUtils.ensureDirectoryExists(Path(getCacheRoot()))
        FileUtils.ensureDirectoryExists(Path(getPluginRuntimeRoot()))
        FileUtils.ensureDirectoryExists(Path(getPluginTempRoot()))
        FileUtils.ensureDirectoryExists(Path(getPluginInfoTempRoot()))
    }
}

