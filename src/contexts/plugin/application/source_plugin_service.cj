package lanlu.contexts.plugin.application

import std.fs.*
import std.io.{ByteBuffer, readToEnd}
import std.time.*
import stdx.encoding.json.stream.*
import lanlu.contexts.plugin.infrastructure.persistence.*
import lanlu.contexts.task.domain.*

public class SourcePluginService {

    public static func listSourcePlugins(): Array<PluginData> {
        return PluginDao.getPluginsByType("Source")
    }

    public static func getEnabledSourcePlugin(namespace: String): Option<PluginData> {
        let plugin = PluginDao.getPluginByNamespace(namespace)
        if (plugin.namespace.size == 0 || plugin.plugin_type.trimAscii() != "Source" || !plugin.enabled) {
            return None
        }
        return Some(plugin)
    }

    public static func executeBrowseAction(
        namespace: String,
        action: String,
        requestParams: String
    ): Int64 {

        match (getEnabledSourcePlugin(namespace)) {
            case Some(plugin) =>
                let wasmPath = PluginTaskService.buildPluginFilePath(plugin.plugin_type, plugin.entry)
                if (!exists(Path(wasmPath))) {
                    return 0
                }

                let effectiveAction = action.trimAscii()
                if (effectiveAction.size == 0) {
                    return 0
                }

                let groupId = buildGroupId(namespace, effectiveAction)
                let taskParams = buildBrowseTaskParamsJson(namespace, effectiveAction, groupId, requestParams)
                let task = TaskModel.createTaskWithOptions(
                    "在线源浏览",
                    "wasm_task",
                    taskParams,
                    50,
                    groupId,
                    "source_browse:${namespace}:${effectiveAction}"
                )

                if (task.id <= 0) {
                    return 0
                }

                return task.id
            case None => return 0
        }
    }

    private static func buildBrowseTaskParamsJson(
        namespace: String,
        action: String,
        groupId: String,
        requestParams: String
    ): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("pluginNamespace").writeValue(namespace.trimAscii())
        w.writeName("pluginType").writeValue("Source")
        w.writeName("action").writeValue(action.trimAscii())
        w.writeName("targetType").writeValue("source")
        w.writeName("targetId").writeValue(namespace.trimAscii())
        w.writeName("groupId").writeValue(groupId.trimAscii())
        if (requestParams.trimAscii().size > 0) {
            w.writeName("extraParams").writeValue(requestParams.trimAscii())
        }
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func buildGroupId(namespace: String, action: String): String {
        let safeNamespace = namespace.trimAscii().replace("/", "_").replace("\\", "_").replace(" ", "_")
        let safeAction = action.trimAscii().replace("/", "_").replace("\\", "_").replace(" ", "_")
        return "source_browse:${safeNamespace}:${safeAction}:${DateTime.now().toUnixTimeStamp().toSeconds()}"
    }
}
