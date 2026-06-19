package lanlu.contexts.plugin.interfaces.http

import ignite.*
import std.collection.*
import std.convert.*
import stdx.encoding.json.stream.*
import std.io.{ByteBuffer, readToEnd}
import stdx.log.*
import lanlu.shared.views.*
import lanlu.shared.utils.{getLogger, JsonCodec}
import lanlu.contexts.plugin.infrastructure.persistence.*
import lanlu.contexts.plugin.application.*
import lanlu.contexts.task.domain.*

public class SourcePluginController {

    public static func listSourcePlugins(ctx: Ctx) {
        let logger = getLogger("source_plugin_controller")

        try {
            let plugins = SourcePluginService.listSourcePlugins()
            var result = "["
            for (i in 0..plugins.size) {
                if (i > 0) { result += "," }
                result += pluginSummaryToJson(plugins[i])
            }
            result += "]"

            logger.debug("列出Source插件", [("count", plugins.size.toString())])
            ctx.json(result)
        } catch (e: Exception) {
            logger.error("列出Source插件失败")
            ResponseView.errorJson(ctx, "Failed to list source plugins: ${e.message}")
        }
    }

    /**
     * Source action 入口。
     * 浏览类 action（source_home/search/filters/detail/reader/coverAsset/pageAsset）直连执行，
     * 不经过 taskpool/SSE。
     * 其他 action（如 source_download）走原有 taskpool 路径，由 sourceDownload 方法处理。
     */
    public static func sourceAction(ctx: Ctx) {
        let action = ctx.paramsOpt("action") ?? ""

        let effectiveAction = action.trimAscii()
        if (effectiveAction.size == 0) {
            ResponseView.errorJson(ctx, "Source action is required")
            return
        }

        if (SourceDirectActionService.isBrowseAction(effectiveAction)) {
            executeBrowseDirect(ctx, effectiveAction)
        } else {
            ResponseView.errorJson(ctx, "Unknown source action: ${effectiveAction}")
        }
    }

    /**
     * 直连执行浏览类 action，不经过 taskpool。
     */
    private static func executeBrowseDirect(ctx: Ctx, action: String) {
        let logger = getLogger("source_plugin_controller")

        // 解析请求
        match (SourceRequestResolver.parse(ctx)) {
            case Some(request) =>
                // 校验插件
                match (SourceRequestResolver.validatePlugin(request)) {
                    case Some(_) =>
                        // 直连执行
                        let json = SourceDirectActionService.execute(
                            request.namespace,
                            action,
                            request
                        )
                        ctx.setHeader("Content-Type", "application/json")
                        ctx.sendString(json)
                    case None =>
                        ResponseView.errorJson(ctx, "Source plugin not found or disabled: ${request.namespace}")
                }
            case None =>
                logger.error("解析Source请求失败", [
                    ("namespace", ctx.paramsOpt("namespace") ?? ""),
                    ("action", action)
                ])
                ResponseView.errorJson(ctx, "Invalid source request: namespace is required")
        }
    }

    // 改为通过新的 download_archive 协议执行
    public static func sourceDownload(ctx: Ctx) {
        let logger = getLogger("source_plugin_controller")
        let namespace = ctx.paramsOpt("namespace") ?? ""
        if (namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin namespace is required")
            return
        }

        var remoteId = ""
        var categoryId: Int64 = 0
        var kind = "archive"

        try {
            let body = ctx.bodyString()
            if (body.size > 0) {
                let requestMap = JsonCodec.decode<HashMap<String, String>>(body)
                remoteId = requestMap.get("remote_id") ?? ""
                let catStr = requestMap.get("category_id") ?? "0"
                try { categoryId = Int64.parse(catStr) } catch (_: Exception) { categoryId = 0 }
                kind = requestMap.get("kind") ?? "archive"
            }
        } catch (e: Exception) {
            logger.error("解析下载请求失败", [("error", e.message)])
            ResponseView.errorJson(ctx, "Invalid request body")
            return
        }

        if (remoteId.size == 0 || categoryId <= 0) {
            ResponseView.errorJson(ctx, "remote_id and category_id are required")
            return
        }

        let sourceId = "source:${namespace}:${remoteId}"
        let taskId = SourcePluginExecutionService.downloadArchive(sourceId, categoryId, kind)
        if (taskId <= 0) {
            ResponseView.errorJson(ctx, "Failed to create download task")
            return
        }

        let responseOut = ByteBuffer()
        let responseW = JsonWriter(responseOut)
        responseW.startObject()
        responseW.writeName("success").writeValue(true)
        responseW.writeName("task_id").writeValue(taskId)
        responseW.endObject()
        responseW.flush()
        ctx.json(String.fromUtf8(readToEnd(responseOut)))
    }

    private static func pluginSummaryToJson(plugin: PluginData): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("namespace").writeValue(plugin.namespace)
        w.writeName("name").writeValue(plugin.name)
        w.writeName("version").writeValue(plugin.version)
        w.writeName("description").writeValue(plugin.description)
        w.writeName("author").writeValue(plugin.author)
        w.writeName("icon").writeValue(plugin.icon)
        w.writeName("enabled").writeValue(plugin.enabled)
        w.writeName("tags").writeValue(plugin.tags)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }
}