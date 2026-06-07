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

    /**
     * 执行 Source 插件的 browse 类 action，返回 task id。
     *
     * Source 插件契约说明：
     *
     * ## Browse Actions
     * - source_home: 获取首页内容
     * - source_search: 搜索
     * - source_filters: 获取过滤器列表
     * - source_detail: 获取条目详情（返回 title, description, tags, page_count, cover_asset_id, reader.media_type, children）
     * - source_reader: 获取页面列表
     * - source_cover_asset: 获取封面资源
     * - source_page_asset: 获取页面资源
     *
     * ## source_reader 输出契约
     * 响应 data.pages[] 中每个条目 SHALL 包含以下字段：
     * - path: 必填，页面资源 key（后续翻页时传回插件的标识）。
     *   插件可自行定义 path 的格式（URL、远端 ID、文件 key、页码字符串等），宿主不解释。
     * - asset_id: 可选，如果插件能直接提供资源 ID 可在此返回，必须是 JSON number 类型。
     *
     * ## source_page_asset 输入契约
     * 宿主调用时 SHALL 提供以下参数：
     * - remote_id: 必填
     * - path: 必填，值来自 source_reader 输出的 data.pages[].path
     * - page: 可选，仅作为插件自用 hint（如页码索引）
     *
     * ## source_page_asset 输出契约
     * 响应 data 中 SHALL 包含以下字段：
     * - asset_id: 必填，JSON number 类型。
     */
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
