package lanlu.contexts.plugin.application

import std.collection.*
import std.convert.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.contexts.plugin.domain.*

/**
 * WASM 插件执行内核，从 WasmTaskRunner 抽取的共享服务。
 * 同时供 taskpool 路径和直连路径（SourceDirectActionService）使用。
 */
public class PluginExecutionService {
    /**
     * 执行 Source 类型插件的指定 action。
     * 为直连路径（taskId=0, parentTaskId=0）和 taskpool 路径共用。
     */
    public static func executeSourceAction(
        plugin: PluginTaskData,
        action: String,
        requestParamsJson: String,
        taskId: Int64,
        parentTaskId: Int64,
        groupId: String
    ): WasmExecutionResult {
        let effectiveAction = action.trimAscii()
        if (effectiveAction.size == 0) {
            return WasmExecutionResult(false, "", "Missing action for Source plugin")
        }

        let runtimePermissions = resolveRuntimePermissions(plugin)
        let baseParams = buildPluginParametersJson(plugin)
        let mergedExtra = mergeParamsJson(baseParams, requestParamsJson)
        let ctxParams = buildRuntimeContextParamsJson(
            "source",
            plugin.namespace,
            taskId,
            groupId,
            plugin.namespace,
            "Source",
            ""
        )
        let finalParams = mergeParamsJson(mergedExtra, ctxParams)
        let inputJson = buildSourceInputJson(effectiveAction, finalParams)
        let wasmPath = PluginTaskService.buildPluginFilePath(plugin.plugin_type, plugin.entry)

        let result = WasmHostBridge.runGenericPlugin(
            taskId,
            parentTaskId,
            plugin.namespace,
            groupId,
            wasmPath,
            inputJson,
            runtimePermissions,
            false,
            enableWasi: true
        )
        if (!result.success) {
            return result
        }
        let (outputSuccess, outputError) = checkPluginOutputSuccess(result.output)
        if (!outputSuccess) {
            return WasmExecutionResult(false, result.output, outputError)
        }

        // 对特定 action 做输出校验（仅警告，不阻断）
        if (effectiveAction == "source_reader") {
            let (_, msg) = validateSourceReaderOutput(result.output)
            if (msg.size > 0) {
                // 仅记录警告，不阻断
            }
        } else if (effectiveAction == "source_page_asset") {
            let (_, msg) = validateSourcePageAssetOutput(result.output)
            if (msg.size > 0) { }
        } else if (effectiveAction == "source_home" || effectiveAction == "source_search" || effectiveAction == "source_detail") {
            let (_, msg) = validateSourceBrowseItemOutput(result.output)
            if (msg.size > 0) { }
        }

        return result
    }

    public static func parseHookNamespacesPublic(rawJson: String): Option<Array<String>> {
        let trimmed = rawJson.trimAscii()
        if (trimmed.size == 0 || trimmed == "[]") {
            return Some(Array<String>())
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginArray)) {
                return None
            }

            let hooks = ArrayList<String>()
            r.startArray()
            while (r.peek() != EndArray) {
                match (r.peek()) {
                    case Some(_) =>
                        let hook = r.readValue<String>().trimAscii()
                        if (hook.size > 0) {
                            hooks.add(hook)
                        }
                    case None => break
                }
            }
            r.endArray()
            return Some(hooks.toArray())
        } catch (_: Exception) {
            return None
        }
    }

    public static func resolveHookPluginPublic(namespace: String): Option<PluginTaskData> {
        let hookNamespace = namespace.trimAscii()
        if (hookNamespace.size == 0) {
            return None
        }
        let plugin = PluginTaskService.getPluginByNamespace(hookNamespace)
        if (plugin.namespace.size == 0 || !PluginTaskService.isWasmPlugin(plugin)) {
            return None
        }
        let hookType = plugin.plugin_type.trimAscii()
        if (hookType != "Login" && hookType != "Script") {
            return None
        }
        return Some(plugin)
    }

    public static func executeDirectHook(
        plugin: PluginTaskData,
        groupId: String,
        targetType: String,
        targetId: String,
        taskId: Int64,
        parentTaskId: Int64,
        mainPluginNamespace: String,
        mainPluginType: String
    ): WasmExecutionResult {
        let runtimePermissions = resolveRuntimePermissions(plugin)
        let contextParams = buildRuntimeContextParamsJson(
            targetType,
            targetId,
            taskId,
            groupId,
            mainPluginNamespace,
            mainPluginType,
            ""
        )
        let paramsJson = mergeParamsJson(buildPluginParametersJson(plugin), contextParams)
        let inputJson = match (plugin.plugin_type.trimAscii()) {
            case "Login" => buildLoginInputJson(paramsJson)
            case "Script" => buildScriptInputJson("Script", "", paramsJson)
            case _ => return WasmExecutionResult(false, "", "Unsupported hook plugin type: ${plugin.plugin_type}")
        }
        let wasmPath = PluginTaskService.buildPluginFilePath(plugin.plugin_type, plugin.entry)
        let result = WasmHostBridge.runGenericPlugin(
            taskId,
            parentTaskId,
            plugin.namespace,
            groupId,
            wasmPath,
            inputJson,
            runtimePermissions,
            false,
            enableWasi: true
        )
        if (!result.success) {
            return result
        }
        let (outputSuccess, outputError) = checkPluginOutputSuccess(result.output)
        if (!outputSuccess) {
            return WasmExecutionResult(false, result.output, outputError)
        }
        return result
    }


    // ─── 以下为从 WasmTaskRunner 抽取的私有辅助方法 ───

    private static func buildPluginParametersJson(plugin: PluginTaskData): String {
        if (plugin.parameters.trimAscii().size == 0) {
            return ""
        }

        try {
            let trimmed = plugin.parameters.trimAscii()
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            match (r.peek()) {
                case Some(BeginArray) =>
                    var paramMap = HashMap<String, String>()
                    r.startArray()
                    var idx: Int64 = 0
                    while (r.peek() != EndArray) {
                        if (r.peek() != Some(BeginObject)) {
                            r.skip()
                            idx += 1
                            continue
                        }
                        var name = ""
                        var valueRaw: Option<String> = None
                        r.startObject()
                        while (r.peek() != EndObject) {
                            let n = r.readName()
                            match (n) {
                                case "name" => name = r.readValue<String>().trimAscii()
                                case "value" =>
                                    let bytes = r.readValueBytes()
                                    valueRaw = Some(String.fromUtf8(bytes))
                                case "default_value" =>
                                    if (valueRaw.isNone()) {
                                        let bytes = r.readValueBytes()
                                        valueRaw = Some(String.fromUtf8(bytes))
                                    } else {
                                        r.skip()
                                    }
                                case _ => r.skip()
                            }
                        }
                        r.endObject()
                        let key = if (name.size > 0) { name } else { "param${idx.toString()}" }
                        match (valueRaw) {
                            case Some(v) => paramMap[key] = v
                            case None => ()
                        }
                        idx += 1
                    }
                    r.endArray()

                    if (paramMap.size == 0) {
                        return ""
                    }
                    let out = ByteBuffer()
                    let w = JsonWriter(out)
                    w.startObject()
                    for ((k, v) in paramMap) {
                        w.writeName(k).jsonValue(v)
                    }
                    w.endObject()
                    w.flush()
                    return String.fromUtf8(readToEnd(out))
                case Some(BeginObject) =>
                    var hasField = false
                    r.startObject()
                    while (r.peek() != EndObject) {
                        hasField = true
                        r.readName()
                        r.skip()
                    }
                    r.endObject()
                    return if (hasField) { trimmed } else { "" }
                case _ => ()
            }
        } catch (_: Exception) {}

        return ""
    }

    private static func mergeParamsJson(baseParams: String, extraParams: String): String {
        let extraTrimmed = extraParams.trimAscii()
        if (extraTrimmed.size == 0) {
            return baseParams
        }

        let baseTrimmed = baseParams.trimAscii()
        if (baseTrimmed.size == 0) {
            return extraTrimmed
        }

        try {
            func parseObjectToRawMap(json: String): Option<HashMap<String, String>> {
                var buf = ByteBuffer()
                unsafe { buf.write(json.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() != Some(BeginObject)) {
                    return None
                }
                var result = HashMap<String, String>()
                r.startObject()
                while (r.peek() != EndObject) {
                    let name = r.readName()
                    let bytes = r.readValueBytes()
                    result[name] = String.fromUtf8(bytes)
                }
                r.endObject()
                return Some(result)
            }

            match (parseObjectToRawMap(baseTrimmed)) {
                case Some(baseMap) =>
                    match (parseObjectToRawMap(extraTrimmed)) {
                        case Some(extraMap) =>
                            for ((k, v) in extraMap) {
                                baseMap[k] = v
                            }
                            let out = ByteBuffer()
                            let w = JsonWriter(out)
                            w.startObject()
                            for ((k, v) in baseMap) {
                                w.writeName(k).jsonValue(v)
                            }
                            w.endObject()
                            w.flush()
                            return String.fromUtf8(readToEnd(out))
                        case None => return extraTrimmed
                    }
                case None => return extraTrimmed
            }
        } catch (_: Exception) {
            return extraTrimmed
        }
    }

    private static func buildRuntimeContextParamsJson(
        targetType: String,
        targetId: String,
        taskId: Int64,
        groupId: String,
        mainPluginNamespace: String,
        mainPluginType: String,
        url: String
    ): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("__target_type").writeValue(targetType.trimAscii().toAsciiLower())
        w.writeName("__target_id").writeValue(targetId.trimAscii())
        w.writeName("__task_id").writeValue(taskId.toString())
        w.writeName("__group_id").writeValue(groupId.trimAscii())
        w.writeName("__main_plugin_namespace").writeValue(mainPluginNamespace.trimAscii())
        w.writeName("__main_plugin_type").writeValue(mainPluginType.trimAscii())
        if (url.trimAscii().size > 0) {
            w.writeName("__url").writeValue(url.trimAscii())
        }
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func buildSourceInputJson(
        action: String,
        params: String
    ): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("action").writeValue(action.trimAscii())
        w.writeName("pluginType").writeValue("Source")

        let trimmedParams = params.trimAscii()
        if (trimmedParams.size > 0) {
            w.writeName("params").jsonValue(trimmedParams)
        } else {
            w.writeName("params")
            w.startObject()
            w.endObject()
        }
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func buildLoginInputJson(params: String): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("action").writeValue("run")
        w.writeName("pluginType").writeValue("Login")
        let trimmedParams = params.trimAscii()
        if (trimmedParams.size > 0) {
            w.writeName("params").jsonValue(trimmedParams)
        } else {
            w.writeName("params")
            w.startObject()
            w.endObject()
        }
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func buildScriptInputJson(
        pluginType: String,
        oneshotParam: String,
        params: String
    ): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("action").writeValue("run")
        w.writeName("pluginType").writeValue(pluginType)
        w.writeName("oneshotParam").writeValue(oneshotParam)

        let trimmedParams = params.trimAscii()
        if (trimmedParams.size > 0) {
            w.writeName("params").jsonValue(trimmedParams)
        } else {
            w.writeName("params")
            w.startObject()
            w.endObject()
        }
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func checkPluginOutputSuccess(output: String): (Bool, String) {
        let trimmed = output.trimAscii()
        if (trimmed.size == 0) {
            return (true, "")
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return (true, "")
            }
            r.startObject()
            var success = true
            var error = ""
            while (r.peek() != EndObject) {
                let name = r.readName().trimAscii().toAsciiLower()
                if (name == "success") {
                    let v = r.readValue<String>().trimAscii().toAsciiLower()
                    success = v != "false" && v != "0"
                } else if (name == "error") {
                    error = readJsonValueAsString(r)
                } else {
                    r.skip()
                }
            }
            r.endObject()
            return (success, error)
        } catch (_: Exception) {
            return (true, "")
        }
    }

    private static func readJsonValueAsString(r: JsonReader): String {
        match (r.peek()) {
            case Some(BeginObject) =>
                let bytes = r.readValueBytes()
                return String.fromUtf8(bytes).trimAscii()
            case Some(BeginArray) =>
                let bytes = r.readValueBytes()
                return String.fromUtf8(bytes).trimAscii()
            case Some(_) => return r.readValue<String>().trimAscii()
            case None => return ""
        }
    }

    private static func resolveRuntimePermissions(plugin: PluginTaskData): String {
        let fallback = plugin.permissions.trimAscii()
        let wasmPath = PluginTaskService.buildPluginFilePath(plugin.plugin_type, plugin.entry)
        let (okInfo, _, infoJson, _) = WasmPluginInfoRunner.runPluginInfo(wasmPath)
        if (!okInfo) {
            return fallback
        }

        let parsed = parsePermissionsFromPluginInfoJson(infoJson)
        return if (parsed.size > 0) { parsed } else { fallback }
    }

    private static func parsePermissionsFromPluginInfoJson(infoJson: String): String {
        let trimmed = infoJson.trimAscii()
        if (trimmed.size == 0) {
            return ""
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            func readCommaSeparated(): String {
                match (r.peek()) {
                    case Some(BeginArray) =>
                        let out = ArrayList<String>()
                        r.startArray()
                        while (r.peek() != EndArray) {
                            let value = r.readValue<String>().trimAscii()
                            if (value.size > 0) {
                                out.add(value)
                            }
                        }
                        r.endArray()
                        return String.join(out.toArray(), delimiter: ",")
                    case Some(_) =>
                        return r.readValue<String>().trimAscii()
                    case None =>
                        return ""
                }
            }

            if (r.peek() != Some(BeginObject)) {
                return ""
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let key = r.readName()
                if (key == "permissions") {
                    let parsed = readCommaSeparated()
                    r.endObject()
                    return parsed
                }
                r.skip()
            }
            r.endObject()
        } catch (_: Exception) {}

        return ""
    }

    private static func isWasmPlugin(plugin: PluginTaskData): Bool {
        return plugin.entry.trimAscii().toAsciiLower().endsWith(".wasm")
    }

    private static func parsePositiveAssetId(rawValue: String): Int64 {
        let trimmed = rawValue.trimAscii()
        if (trimmed.size == 0) { return 0 }
        try {
            let parsed = Int64.parse(trimmed)
            return if (parsed > 0) { parsed } else { 0 }
        } catch (_: Exception) {
            return 0
        }
    }

    /**
     * 校验 source_reader 动作的返回结果
     */
    private static func validateSourceReaderOutput(outputJson: String): (Bool, String) {
        let trimmed = outputJson.trimAscii()
        if (trimmed.size == 0) {
            return (false, "empty output")
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return (false, "output is not a JSON object")
            }
            r.startObject()
            var dataFound = false
            while (r.peek() != EndObject) {
                let name = r.readName()
                if (name == "data") {
                    dataFound = true
                    if (r.peek() != Some(BeginObject)) {
                        return (false, "data is not a JSON object")
                    }
                    r.startObject()
                    var pagesFound = false
                    while (r.peek() != EndObject) {
                        let dataKey = r.readName()
                        if (dataKey == "pages") {
                            pagesFound = true
                            if (r.peek() != Some(BeginArray)) {
                                return (false, "pages is not a JSON array")
                            }
                            r.startArray()
                            var pageIndex: Int64 = 0
                            var warnings = ArrayList<String>()
                            while (r.peek() != EndArray) {
                                if (r.peek() != Some(BeginObject)) {
                                    r.skip()
                                    pageIndex += 1
                                    continue
                                }
                                r.startObject()
                                while (r.peek() != EndObject) {
                                    let pageKey = r.readName()
                                    if (pageKey == "url") {
                                        let urlVal = r.readValue<String>()
                                        if (urlVal.trimAscii().size > 0) {
                                            warnings.add("page[${pageIndex.toString()}].url is deprecated, should use asset_id")
                                        }
                                    } else if (pageKey == "asset_id") {
                                        let assetId = r.readValue<Int64>()
                                        if (assetId <= 0) {
                                            warnings.add("page[${pageIndex.toString()}].asset_id is invalid: ${assetId.toString()}")
                                        }
                                    } else {
                                        r.skip()
                                    }
                                }
                                r.endObject()
                                pageIndex += 1
                            }
                            r.endArray()

                            if (warnings.size > 0) {
                                var combined = ""
                                for (w in warnings) {
                                    if (combined.size > 0) { combined += "; " }
                                    combined += w
                                }
                                return (false, combined)
                            }
                        } else {
                            r.skip()
                        }
                    }
                    r.endObject()
                    if (!pagesFound) {
                        return (false, "data.pages not found")
                    }
                } else {
                    r.skip()
                }
            }
            r.endObject()
            if (!dataFound) {
                return (false, "data field not found")
            }
            return (true, "")
        } catch (e: Exception) {
            return (false, "parse error: ${e.message}")
        }
    }

    /**
     * 校验 source_page_asset 输出：检查 data.asset_id 是否为有效正数
     */
    private static func validateSourcePageAssetOutput(outputJson: String): (Bool, String) {
        let trimmed = outputJson.trimAscii()
        if (trimmed.size == 0) {
            return (false, "empty output")
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return (false, "output is not a JSON object")
            }
            var successFound = false
            var dataFound = false
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                if (name == "success") {
                    successFound = r.readValue<Bool>()
                } else if (name == "data") {
                    dataFound = true
                    if (r.peek() != Some(BeginObject)) {
                        return (false, "data is not a JSON object")
                    }
                    r.startObject()
                    var assetIdFound = false
                    while (r.peek() != EndObject) {
                        let dataKey = r.readName()
                        if (dataKey == "asset_id") {
                            let assetId = r.readValue<Int64>()
                            if (assetId <= 0) {
                                return (false, "asset_id is invalid: ${assetId.toString()}")
                            }
                            assetIdFound = true
                        } else {
                            r.skip()
                        }
                    }
                    r.endObject()
                    if (!assetIdFound) {
                        return (false, "data.asset_id not found")
                    }
                } else {
                    r.skip()
                }
            }
            r.endObject()
            if (!successFound) {
                return (false, "success is false")
            }
            return (true, "")
        } catch (e: Exception) {
            return (false, "parse error: ${e.message}")
        }
    }

    /**
     * 校验 source_home / source_search / source_detail 输出
     */
    private static func validateSourceBrowseItemOutput(outputJson: String): (Bool, String) {
        let trimmed = outputJson.trimAscii()
        if (trimmed.size == 0) {
            return (false, "empty output")
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return (false, "output is not a JSON object")
            }
            r.startObject()
            var dataFound = false
            while (r.peek() != EndObject) {
                let name = r.readName()
                if (name == "data") {
                    dataFound = true
                    if (r.peek() != Some(BeginObject)) {
                        return (false, "data is not a JSON object")
                    }
                    r.startObject()
                    var itemsFound = false
                    while (r.peek() != EndObject) {
                        let dataKey = r.readName()
                        if (dataKey == "items") {
                            itemsFound = true
                            if (r.peek() != Some(BeginArray)) {
                                return (false, "items is not a JSON array")
                            }
                            r.startArray()
                            var itemIndex: Int64 = 0
                            var itemsWithoutCoverAsset: Int64 = 0
                            while (r.peek() != EndArray) {
                                if (r.peek() != Some(BeginObject)) {
                                    r.skip()
                                    itemIndex += 1
                                    continue
                                }
                                r.startObject()
                                var hasCoverAssetId = false
                                while (r.peek() != EndObject) {
                                    let itemKey = r.readName()
                                    if (itemKey == "cover_asset_id") {
                                        let val = r.readValue<String>()
                                        if (parsePositiveAssetId(val) > 0) {
                                            hasCoverAssetId = true
                                        }
                                    } else {
                                        r.skip()
                                    }
                                }
                                r.endObject()
                                if (!hasCoverAssetId) {
                                    itemsWithoutCoverAsset += 1
                                }
                                itemIndex += 1
                            }
                            r.endArray()
                            if (itemsWithoutCoverAsset > 0) {
                                return (false, "${itemsWithoutCoverAsset.toString()} item(s) missing valid cover_asset_id")
                            }
                        } else {
                            r.skip()
                        }
                    }
                    r.endObject()
                    if (!itemsFound) {
                        return (false, "data.items not found")
                    }
                } else {
                    r.skip()
                }
            }
            r.endObject()
            if (!dataFound) {
                return (false, "data field not found")
            }
            return (true, "")
        } catch (e: Exception) {
            return (false, "parse error: ${e.message}")
        }
    }

    // ─── Pre-hook 执行 ───

    /**
     * 执行 Source 插件的 browse action（含 pre-hook）。
     * 直连路径（SourceDirectActionService）使用此方法代替 executeSourceAction。
     * taskpool 路径已在外层执行 hooks，不应再调用此方法。
     */
    public static func executeSourceBrowseAction(
        plugin: PluginTaskData,
        action: String,
        requestParamsJson: String,
        taskId: Int64,
        parentTaskId: Int64,
        groupId: String
    ): WasmExecutionResult {
        let hooks = match (parseHookNamespacesPublic(plugin.pre_hooks)) {
            case Some(value) => value
            case None => return WasmExecutionResult(false, "", "Invalid pre hooks for plugin ${plugin.namespace}")
        }

        // 执行 pre-hooks
        for (hookNs in hooks) {
            let hookPlugin = match (resolveHookPluginPublic(hookNs)) {
                case Some(value) => value
                case None => return WasmExecutionResult(false, "", "Pre-hook plugin not found or invalid: ${hookNs}")
            }
            let hookResult = executeDirectHook(
                hookPlugin,
                groupId,
                "source",
                plugin.namespace,
                taskId,
                parentTaskId,
                plugin.namespace,
                plugin.plugin_type
            )
            if (!hookResult.success) {
                return WasmExecutionResult(false, hookResult.output, "Pre-hook ${hookNs} failed: ${hookResult.error}")
            }
        }

        // 执行主 action
        return executeSourceAction(plugin, action, requestParamsJson, taskId, parentTaskId, groupId)
    }
}
