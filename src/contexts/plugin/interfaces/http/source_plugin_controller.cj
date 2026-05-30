package lanlu.contexts.plugin.interfaces.http

import ignite.*
import std.collection.*
import std.convert.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import stdx.log.*
import lanlu.shared.views.*
import lanlu.contexts.plugin.infrastructure.persistence.*
import lanlu.contexts.plugin.application.*
import lanlu.contexts.task.application.TaskPoolService
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*

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

    public static func sourceAction(ctx: Ctx) {
        enqueueBrowse(ctx, ctx.paramsOpt("action") ?? "")
    }

    private static func enqueueBrowse(ctx: Ctx, action: String) {
        let namespace = ctx.paramsOpt("namespace") ?? ""
        if (namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin namespace is required")
            return
        }
        let effectiveAction = action.trimAscii()
        if (effectiveAction.size == 0) {
            ResponseView.errorJson(ctx, "Source action is required")
            return
        }

        let requestParams = ctx.bodyString()
        let taskId = SourcePluginService.executeBrowseAction(namespace, effectiveAction, requestParams)
        if (taskId <= 0) {
            ResponseView.errorJson(ctx, "Failed to create browse task")
            return
        }

        TaskPoolService.getInstance().notifyTaskAvailable()
        ctx.setHeader("Content-Type", "application/json")
        ctx.sendString(browseTaskJson(taskId))
    }

    public static func sourceDownload(ctx: Ctx) {
        let logger = getLogger("source_plugin_controller")
        let namespace = ctx.paramsOpt("namespace") ?? ""
        if (namespace.size == 0) {
            ResponseView.errorJson(ctx, "Plugin namespace is required")
            return
        }

        match (SourcePluginService.getEnabledSourcePlugin(namespace)) {
            case Some(_) => ()
            case None =>
                ResponseView.errorJson(ctx, "Source plugin not found or disabled: ${namespace}")
                return
        }

        var remoteId = ""
        var archiveId = ""
        var categoryId: Int64 = 0

        try {
            let body = ctx.bodyString()
            if (body.size > 0) {
                let requestMap = JsonCodec.decode<HashMap<String, String>>(body)
                remoteId = requestMap.get("remote_id") ?? ""
                archiveId = requestMap.get("archive_id") ?? ""
                let catStr = requestMap.get("category_id") ?? "0"
                try {
                    categoryId = Int64.parse(catStr)
                } catch (_: Exception) {
                    categoryId = 0
                }
            }
        } catch (e: Exception) {
            logger.error("解析下载请求失败", [("error", e.message)])
            ResponseView.errorJson(ctx, "Invalid request body")
            return
        }

        if (remoteId.size == 0) {
            ResponseView.errorJson(ctx, "remote_id is required")
            return
        }
        if (categoryId <= 0) {
            ResponseView.errorJson(ctx, "category_id is required")
            return
        }

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("namespace").writeValue(namespace)
        w.writeName("remote_id").writeValue(remoteId)
        w.writeName("archive_id").writeValue(archiveId)
        w.writeName("category_id").writeValue(categoryId)
        w.endObject()
        w.flush()
        let taskParams = String.fromUtf8(readToEnd(out))

        let task = TaskModel.createTaskWithOptions(
            "在线源下载",
            "source_download",
            taskParams,
            50,
            "source_download:${namespace}",
            "source"
        )

        if (task.id <= 0) {
            ResponseView.errorJson(ctx, "Failed to create download task")
            return
        }

        let responseOut = ByteBuffer()
        let responseW = JsonWriter(responseOut)
        responseW.startObject()
        responseW.writeName("success").writeValue(true)
        responseW.writeName("task_id").writeValue(task.id)
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

    private static func browseTaskJson(taskId: Int64): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(1)
        w.writeName("job").writeValue(taskId)
        w.writeName("task_id").writeValue(taskId)
        w.writeName("task_type").writeValue("wasm_task")
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }
}
