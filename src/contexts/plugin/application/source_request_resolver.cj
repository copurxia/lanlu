package lanlu.contexts.plugin.application

import std.collection.*
import std.fs.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import ignite.*
import lanlu.shared.utils.JsonCodec

public class SourceRequest {
    public var namespace: String = ""
    public var remoteId: String = ""
    public var parentRemoteId: String = ""
    public var paramsJson: String = "{}"

    public init() {}

    public init(namespace: String, remoteId: String) {
        this.namespace = namespace
        this.remoteId = remoteId
    }
}

public class SourceRequestResolver {

    /**
     * 从请求中解析 SourceRequest。
     * remote_id 是可选的——部分 action（如 source_home、source_search、source_filters）不需要 remote_id。
     * 具体的 action handler 自行校验必需字段。
     */
    public static func parse(ctx: Ctx): Option<SourceRequest> {
        let namespace = ctx.paramsOpt("namespace") ?? ""
        if (namespace.size == 0) {
            return None
        }

        var remoteId = ""
        var parentRemoteId = ""

        try {
            let body = ctx.bodyString()
            if (body.trimAscii().size > 0) {
                let bodyMap = JsonCodec.decode<HashMap<String, String>>(body)
                remoteId = bodyMap.get("remote_id") ?? ""
                parentRemoteId = bodyMap.get("parent_remote_id") ?? ""
            }
        } catch (_: Exception) {}

        let request = SourceRequest()
        request.namespace = namespace.trimAscii()
        request.remoteId = remoteId.trimAscii()
        request.parentRemoteId = parentRemoteId.trimAscii()
        request.paramsJson = ctx.bodyString()

        return Some(request)
    }

    public static func parseFromCompositeId(compositeId: String): Option<SourceRequest> {
        let normalizedCompositeId = compositeId
            .replace("%3A", ":")
            .replace("%3a", ":")
        if (!normalizedCompositeId.startsWith("source:")) {
            return None
        }
        let parts = normalizedCompositeId.split(":")
        if (parts.size < 3) {
            return None
        }
        let namespace = parts[1]
        var remoteId = ""
        for (i in 2..parts.size) {
            if (i > 2) { remoteId += ":" }
            remoteId += parts[i]
        }
        if (namespace.size == 0 || remoteId.size == 0) {
            return None
        }

        // Build default paramsJson with remote_id so WASM plugins get the required field
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("remote_id").writeValue(remoteId)
        w.endObject()
        w.flush()

        let request = SourceRequest(namespace, remoteId)
        request.paramsJson = String.fromUtf8(readToEnd(out))
        return Some(request)
    }

    public static func validatePlugin(request: SourceRequest): Option<PluginTaskData> {
        let plugin = PluginTaskService.getPluginByNamespace(request.namespace)
        if (plugin.namespace.size == 0 || plugin.plugin_type.trimAscii() != "Source" || !plugin.enabled) {
            return None
        }
        let wasmPath = PluginTaskService.buildPluginFilePath(plugin.plugin_type, plugin.entry)
        if (!exists(Path(wasmPath))) {
            return None
        }
        return Some(plugin)
    }
}
