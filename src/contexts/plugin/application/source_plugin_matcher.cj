package lanlu.contexts.plugin.application

import std.collection.*
import std.regex.*
import stdx.log.*
import lanlu.shared.utils.*

/**
 * Source 插件匹配服务。
 *
 * 根据 sourceId（格式 "source:{namespace}:{remote_id}"）匹配
 * Metadata 和 Download 插件。
 *
 * 匹配规则：
 * - Metadata 插件：plugin_type = "Metadata" 且 source_id_regex 匹配 sourceId
 * - Download 插件：plugin_type = "Download" 且 source_id_regex 匹配 sourceId
 * - 如果多个插件匹配，优先返回 enabled 的插件
 */
public class SourcePluginMatcher {

    /**
     * 从复合 sourceId 提取 namespace。
     * "source:ehentaisource:123/token" → "ehentaisource"
     */
    private static func extractNamespace(sourceId: String): String {
        let normalized = sourceId
            .replace("%3A", ":")
            .replace("%3a", ":")
        if (!normalized.startsWith("source:")) {
            return ""
        }
        let parts = normalized.split(":")
        if (parts.size < 3) {
            return ""
        }
        return parts[1].trimAscii()
    }

    /**
     * 根据 sourceId 找到匹配的 Metadata 插件。
     * 返回第一个匹配的 enabled 插件；如果没有 enabled 匹配，返回 None。
     */
    public static func findMetadataPlugin(sourceId: String): Option<PluginTaskData> {
        let plugins = PluginTaskService.getPluginsByType("Metadata")
        return findFirstMatching(sourceId, plugins)
    }

    /**
     * 根据 sourceId 找到匹配的 Download 插件。
     * 返回第一个匹配的 enabled 插件；如果没有 enabled 匹配，返回 None。
     */
    public static func findDownloadPlugin(sourceId: String): Option<PluginTaskData> {
        let plugins = PluginTaskService.getPluginsByType("Download")
        return findFirstMatching(sourceId, plugins)
    }

    /**
     * 获取 source 的能力列表。
     * - "metadata"：有 Metadata 插件匹配
     * - "read"：有 Metadata 和 Download 插件同时匹配（Metadata 提供 children，Download 提供资源）
     * - "download"：有 Download 插件匹配
     */
    public static func getCapabilities(sourceId: String): Array<String> {
        let caps = ArrayList<String>()

        let hasMetadata = findMetadataPlugin(sourceId).isSome()
        if (hasMetadata) {
            caps.add("metadata")
        }

        if (findDownloadPlugin(sourceId).isSome()) {
            if (hasMetadata) {
                caps.add("read")
            }
            caps.add("download")
        }

        return caps.toArray()
    }

    /**
     * 核心匹配逻辑：遍历插件列表，匹配 source_id_regex 与 sourceId。
     *
     * 匹配规则：
     * 1. 只匹配 enabled 插件，返回第一个匹配的。
     * 2. 如果没有 enabled 匹配，返回 None。
     * 注意：disabled 插件不会被返回，避免 source 运行路径执行被禁用的插件。
     */
    private static func findFirstMatching(
        sourceId: String,
        plugins: Array<PluginTaskData>
    ): Option<PluginTaskData> {
        let logger = getLogger("source_plugin_matcher")

        for (plugin in plugins) {
            if (!plugin.enabled) {
                continue
            }
            let regexStr = plugin.source_id_regex.trimAscii()
            if (regexStr.size == 0) {
                continue
            }
            try {
                let regex = Regex(regexStr)
                match (regex.find(sourceId)) {
                    case Some(_) =>
                        return Option<PluginTaskData>.Some(plugin)
                    case None => ()
                }
            } catch (e: Exception) {
                logger.warn("跳过无效的 source_id_regex",
                    ("namespace", plugin.namespace),
                    ("regex", regexStr),
                    ("error", e.message))
            }
        }

        return Option.None
    }

    /**
     * 直接通过 PluginTaskData 检查 source_id_regex 是否匹配 sourceId。
     * 用于性能敏感场景，调用方已持有 PluginTaskData 引用。
     */
    public static func matchesSourceId(plugin: PluginTaskData, sourceId: String): Bool {
        let regexStr = plugin.source_id_regex.trimAscii()
        if (regexStr.size == 0) {
            return false
        }
        try {
            let regex = Regex(regexStr)
            match (regex.find(sourceId)) {
                case Some(_) => return true
                case None => return false
            }
        } catch (_: Exception) {
            return false
        }
    }
}
