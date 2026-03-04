package lanlu.contexts.plugin.application

import std.collection.*
import lanlu.contexts.plugin.infrastructure.persistence.*
import lanlu.contexts.task.domain.*
import lanlu.contexts.plugin.domain.*
import lanlu.contexts.plugin.application.runners.ScanPluginsTaskRunner

public class PluginTaskData {
    public var namespace: String = ""
    public var plugin_type: String = ""
    public var entry: String = ""
    public var url_regex: String = ""
    public var login_from: String = ""
    public var permissions: String = ""
    public var parameters: String = "[]"
    public var enabled: Bool = false

    public init() {}
}

/**
 * Task-facing plugin application API.
 *
 * Keep task context away from plugin DAO implementation details.
 */
public class PluginTaskService {
    private static func toTaskData(plugin: PluginData): PluginTaskData {
        let mapped = PluginTaskData()
        mapped.namespace = plugin.namespace
        mapped.plugin_type = plugin.plugin_type
        mapped.entry = plugin.entry
        mapped.url_regex = plugin.url_regex
        mapped.login_from = plugin.login_from
        mapped.permissions = plugin.permissions
        mapped.parameters = plugin.parameters
        mapped.enabled = plugin.enabled
        return mapped
    }

    public static func getPluginByNamespace(namespace: String): PluginTaskData {
        return toTaskData(PluginDao.getPluginByNamespace(namespace))
    }

    public static func getPluginsByType(pluginType: String): Array<PluginTaskData> {
        let plugins = PluginDao.getPluginsByType(pluginType)
        var out = ArrayList<PluginTaskData>()
        for (plugin in plugins) {
            out.add(toTaskData(plugin))
        }
        return out.toArray()
    }

    public static func setEnabled(namespace: String, enabled: Bool): Bool {
        return PluginDao.setEnabled(namespace, enabled)
    }

    public static func runScanPluginsTask(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        ScanPluginsTaskRunner.run(taskId, parameters, context)
    }

    public static func getPluginRuntimeRoot(): String {
        return PluginPaths.getPluginRuntimeRoot()
    }

    public static func getPluginTempRoot(): String {
        return PluginPaths.getPluginTempRoot()
    }

    public static func buildPluginFilePath(pluginType: String, entry: String): String {
        return PluginPaths.buildPluginFilePath(pluginType, entry)
    }

    public static func installCoverAssetFromPluginPath(coverPath: String, pluginNamespace: String, assetKind: String, originalName: String): (Bool, Int64, String, String) {
        return PluginCoverUtils.installCoverAssetFromPluginPath(coverPath, pluginNamespace, assetKind, originalName)
    }

    public static func deleteCoverAsset(assetId: Int64): Unit {
        PluginCoverUtils.deleteAsset(assetId)
    }
}
