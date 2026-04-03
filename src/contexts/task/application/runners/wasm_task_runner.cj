package lanlu.contexts.task.application.runners

import std.collection.*
import std.convert.*
import std.fs.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.contexts.plugin.application.PluginTaskService
import lanlu.contexts.plugin.application.PluginTaskData
import lanlu.contexts.plugin.application.MetadataPatchService
import lanlu.contexts.plugin.domain.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.task.domain.*
import lanlu.infrastructure.kv.*
import lanlu.shared.utils.*

public class WasmTaskParametersReq <: JsonDeserializable<WasmTaskParametersReq> {
    var pluginNamespace: String = ""
    var pluginType: String = ""
    var action: String = "run"
    var groupId: String = ""
    var targetType: String = ""
    var targetId: String = ""
    var oneshotParam: String = ""
    var url: String = ""
    var parentTaskId: Int64 = 0
    var extraParams: String = ""
    var metadata: String = ""

    public static func fromJson(r: JsonReader): WasmTaskParametersReq {
        let res = WasmTaskParametersReq()

        func readRawJsonFlexible(): String {
            match (r.peek()) {
                case Some(BeginObject) =>
                    let bytes = r.readValueBytes()
                    return String.fromUtf8(bytes)
                case Some(BeginArray) =>
                    let bytes = r.readValueBytes()
                    return String.fromUtf8(bytes)
                case Some(_) =>
                    return r.readValue<String>()
                case None =>
                    return ""
            }
        }

        while (let Some(tok) <- r.peek()) {
            match (tok) {
                case BeginObject =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let n = r.readName()
                        match (n) {
                            case "pluginNamespace" => res.pluginNamespace = r.readValue<String>().trimAscii()
                            case "pluginType" => res.pluginType = r.readValue<String>().trimAscii()
                            case "action" => res.action = r.readValue<String>().trimAscii()
                            case "groupId" => res.groupId = r.readValue<String>().trimAscii()
                            case "targetType" => res.targetType = r.readValue<String>().trimAscii()
                            case "targetId" => res.targetId = r.readValue<String>().trimAscii()
                            case "oneshotParam" => res.oneshotParam = r.readValue<String>()
                            case "url" => res.url = r.readValue<String>().trimAscii()
                            case "parentTaskId" =>
                                let raw = r.readValue<String>().trimAscii()
                                try { res.parentTaskId = Int64.parse(raw) } catch (_: Exception) { res.parentTaskId = 0 }
                            case "extraParams" => res.extraParams = r.readValue<String>()
                            case "metadata" => res.metadata = readRawJsonFlexible().trimAscii()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                    break
                case _ => throw Exception("invalid json")
            }
        }

        if (res.action.size == 0) { res.action = "run" }
        if (res.targetType.size == 0) { res.targetType = "archive" }
        return res
    }
}

public class WasmTaskRunner {
    public static func run(taskId: Int64, parameters: String): Unit {
        TaskIO.appendLog(taskId, "wasm_task started")
        TaskModel.updateTaskProgress(taskId, 1, "WASM任务开始")

        let (pluginNamespace, pluginType, groupId, targetType, targetId, oneshotParam, url, extraParams, metadataJson) = parseParameters(parameters)
        let taskData = TaskDao.getTaskDataById(taskId)
        let interactivePreviewEnabled = taskData.triggerSource.trimAscii() == "metadata_plugin_preview"
        if (pluginNamespace.size == 0 || pluginType.size == 0) {
            fail(taskId, "pluginNamespace and pluginType are required")
            return
        }

        try {
            let plugin = PluginTaskService.getPluginByNamespace(pluginNamespace)
            if (plugin.namespace.size == 0) {
                fail(taskId, "Plugin not found: ${pluginNamespace}")
                return
            }
            if (!isWasmPlugin(plugin)) {
                fail(taskId, "Plugin is not a wasm plugin: ${pluginNamespace}")
                return
            }
            let runtimePermissions = resolveRuntimePermissions(plugin)

            TaskDao.updateTaskPluginNamespace(taskId, plugin.namespace)
            var loginCookiesJson = ""
            let effectiveLoginFrom = plugin.login_from.trimAscii()
            if (effectiveLoginFrom.size > 0) {
                let loginResult = handleLoginDependency(taskId, effectiveLoginFrom, groupId)
                if (!loginResult.success) {
                    fail(taskId, "Login plugin failed: ${loginResult.error}")
                    return
                }
                loginCookiesJson = loginResult.cookiesJson
            }
            match (pluginType.trimAscii()) {
                case "Metadata" =>
                    executeMetadata(taskId, plugin, runtimePermissions, targetType, targetId, oneshotParam, extraParams, metadataJson, loginCookiesJson, interactivePreviewEnabled)
                case "Login" =>
                    executeLogin(taskId, plugin, runtimePermissions, interactivePreviewEnabled)
                case "Download" =>
                    executeDownload(taskId, plugin, runtimePermissions, url, extraParams, loginCookiesJson, interactivePreviewEnabled)
                case "Script" =>
                    executeScript(taskId, plugin, runtimePermissions, oneshotParam, extraParams, loginCookiesJson, interactivePreviewEnabled)
                case _ =>
                    fail(taskId, "Unsupported wasm plugin type: ${pluginType}")
            }
        } catch (e: Exception) {
            fail(taskId, e.message)
        }
    }

    private static func executeMetadata(
        taskId: Int64,
        plugin: PluginTaskData,
        runtimePermissions: String,
        targetType: String,
        targetId: String,
        oneshotParam: String,
        extraParams: String,
        metadataJson: String,
        loginCookiesJson: String,
        interactivePreviewEnabled: Bool
    ): Unit {
        let effectiveType = targetType.trimAscii().toAsciiLower()
        let effectiveId = targetId.trimAscii()
        if (effectiveId.size == 0) {
            fail(taskId, "Missing targetId")
            return
        }

        var metadataInputJson = normalizeMetadataInputJson(metadataJson)
        if (metadataInputJson.size == 0) {
            let (okMetadata, builtMetadata, metadataErr) = buildMetadataInputJsonForTarget(effectiveType, effectiveId)
            if (!okMetadata) {
                fail(taskId, metadataErr)
                return
            }
            metadataInputJson = builtMetadata
        }

        TaskModel.updateTaskProgress(taskId, 20, "准备WASM插件输入")
        let baseParams = buildPluginParametersJson(plugin)
        let mergedParams = mergeParamsJson(baseParams, extraParams)
        let contextParams = "{\"__target_type\":\"${effectiveType}\",\"__target_id\":\"${effectiveId}\",\"__task_id\":\"${taskId.toString()}\"}"
        let finalParams = mergeParamsJson(mergedParams, contextParams)
        let inputJson = buildMetadataInputJson("Metadata", effectiveType, effectiveId, metadataInputJson, oneshotParam, finalParams, loginCookiesJson)

        TaskModel.updateTaskProgress(taskId, 40, "执行WASM插件")
        let wasmPath = PluginTaskService.buildPluginFilePath(plugin.plugin_type, plugin.entry)
        let result = WasmHostBridge.runMetadataPlugin(
            taskId,
            plugin.namespace,
            wasmPath,
            inputJson,
            effectiveType,
            effectiveId,
            runtimePermissions,
            interactivePreviewEnabled
        )
        if (!result.success) {
            fail(taskId, result.error)
            return
        }

        let normalizedOutput = if (interactivePreviewEnabled) {
            normalizeMetadataPreviewOutputAssets(taskId, result.output, plugin.namespace, effectiveType, effectiveId)
        } else {
            result.output
        }

        TaskModel.updateTaskProgress(taskId, 100, "WASM任务完成")
        TaskModel.completeTask(taskId, "wasm_task completed")
        TaskIO.writeOutput(taskId, normalizedOutput)
    }

    private static func executeLogin(
        taskId: Int64,
        plugin: PluginTaskData,
        runtimePermissions: String,
        interactivePreviewEnabled: Bool
    ): Unit {
        TaskModel.updateTaskProgress(taskId, 20, "准备WASM登录插件输入")
        let paramsJson = buildPluginParametersJson(plugin)
        let inputJson = buildLoginInputJson(paramsJson)

        TaskModel.updateTaskProgress(taskId, 40, "执行WASM登录插件")
        let wasmPath = PluginTaskService.buildPluginFilePath(plugin.plugin_type, plugin.entry)
        let result = WasmHostBridge.runGenericPlugin(
            taskId,
            plugin.namespace,
            wasmPath,
            inputJson,
            runtimePermissions,
            interactivePreviewEnabled,
            enableWasi: true
        )
        if (!result.success) {
            fail(taskId, result.error)
            return
        }

        TaskModel.updateTaskProgress(taskId, 100, "WASM登录任务完成")
        TaskModel.completeTask(taskId, "wasm_task completed")
        TaskIO.writeOutput(taskId, result.output)
    }

    private static func executeDownload(
        taskId: Int64,
        plugin: PluginTaskData,
        runtimePermissions: String,
        url: String,
        extraParams: String,
        loginCookiesJson: String,
        interactivePreviewEnabled: Bool
    ): Unit {
        let trimmedUrl = url.trimAscii()
        if (trimmedUrl.size == 0) {
            fail(taskId, "Missing url")
            return
        }

        TaskModel.updateTaskProgress(taskId, 20, "准备WASM下载插件输入")
        let baseParams = buildPluginParametersJson(plugin)
        let finalParams = mergeParamsJson(baseParams, extraParams)
        let pluginRuntimeHostDir = FileUtils.joinPath(PluginPaths.getPluginRuntimeRoot(), plugin.namespace)
        FileUtils.ensureDirectoryExists(Path(pluginRuntimeHostDir))
        let pluginGuestDir = "/plugin"
        let inputJson = buildDownloadInputJson("Download", trimmedUrl, pluginGuestDir, finalParams, loginCookiesJson)

        TaskModel.updateTaskProgress(taskId, 40, "执行WASM下载插件")
        let wasmPath = PluginTaskService.buildPluginFilePath(plugin.plugin_type, plugin.entry)
        let result = WasmHostBridge.runGenericPlugin(
            taskId,
            plugin.namespace,
            wasmPath,
            inputJson,
            runtimePermissions,
            interactivePreviewEnabled,
            enableWasi: true,
            wasiGuestPath: "/plugin",
            wasiHostPath: pluginRuntimeHostDir
        )
        if (!result.success) {
            fail(taskId, result.error)
            return
        }

        TaskModel.updateTaskProgress(taskId, 100, "WASM下载任务完成")
        TaskModel.completeTask(taskId, "wasm_task completed")
        TaskIO.writeOutput(taskId, result.output)
    }

    private static func executeScript(
        taskId: Int64,
        plugin: PluginTaskData,
        runtimePermissions: String,
        oneshotParam: String,
        extraParams: String,
        loginCookiesJson: String,
        interactivePreviewEnabled: Bool
    ): Unit {
        TaskModel.updateTaskProgress(taskId, 20, "准备WASM脚本插件输入")
        let baseParams = buildPluginParametersJson(plugin)
        let finalParams = mergeParamsJson(baseParams, extraParams)
        let inputJson = buildScriptInputJson("Script", oneshotParam, finalParams, loginCookiesJson)

        TaskModel.updateTaskProgress(taskId, 40, "执行WASM脚本插件")
        let wasmPath = PluginTaskService.buildPluginFilePath(plugin.plugin_type, plugin.entry)
        let result = WasmHostBridge.runGenericPlugin(
            taskId,
            plugin.namespace,
            wasmPath,
            inputJson,
            runtimePermissions,
            interactivePreviewEnabled,
            enableWasi: true
        )
        if (!result.success) {
            fail(taskId, result.error)
            return
        }

        TaskModel.updateTaskProgress(taskId, 100, "WASM脚本任务完成")
        TaskModel.completeTask(taskId, "wasm_task completed")
        TaskIO.writeOutput(taskId, result.output)
    }

    private static func parseParameters(parameters: String): (String, String, String, String, String, String, String, String, String) {
        var pluginNamespace = ""
        var pluginType = ""
        var groupId = ""
        var targetType = "archive"
        var targetId = ""
        var oneshotParam = ""
        var url = ""
        var extraParams = ""
        var metadata = ""

        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return (pluginNamespace, pluginType, groupId, targetType, targetId, oneshotParam, url, extraParams, metadata)
        }

        try {
            let req = JsonCodec.decode<WasmTaskParametersReq>(trimmed)
            pluginNamespace = req.pluginNamespace
            pluginType = req.pluginType
            groupId = req.groupId
            targetType = req.targetType
            targetId = req.targetId
            oneshotParam = req.oneshotParam
            url = req.url
            extraParams = req.extraParams
            metadata = req.metadata
        } catch (_: Exception) {}

        if (targetType.size == 0) { targetType = "archive" }
        return (pluginNamespace, pluginType, groupId, targetType, targetId, oneshotParam, url, extraParams, metadata)
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

    private static func normalizeMetadataOwnerType(rawType: String): String {
        let t = rawType.trimAscii().toAsciiLower()
        if (t == "tankoubon" || t == "tank") {
            return "tankoubon"
        }
        return "archive"
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

    private static func sanitizeAssetOwnerId(rawOwnerId: String, taskId: Int64): String {
        var ownerId = rawOwnerId.trimAscii()
            .replace("\\", "_")
            .replace("/", "_")
            .replace(" ", "_")
        if (ownerId.size == 0) {
            ownerId = "metadata_${taskId.toString()}"
        }
        return ownerId
    }

    private static func resolvePreviewAssetValue(
        taskId: Int64,
        pluginNamespace: String,
        sourceTargetType: String,
        sourceTargetId: String,
        ownerType: String,
        ownerId: String,
        key: String,
        rawValue: String
    ): String {
        let normalizedKey = key.trimAscii().toAsciiLower()
        var value = rawValue.trimAscii()
        if (value.size == 0) {
            return ""
        }

        let directAssetId = parsePositiveAssetId(value)
        if (directAssetId > 0) {
            return directAssetId.toString()
        }

        if (normalizedKey != "cover" && normalizedKey != "backdrop" && normalizedKey != "clearlogo") {
            return value
        }

        let namespace = pluginNamespace.trimAscii()
        if (namespace.size == 0) {
            TaskIO.appendLog(taskId, "WARN: preview asset install skipped because plugin namespace is empty (owner=${ownerId}, key=${normalizedKey})")
            return ""
        }

        value = WasmHostBridge.materializeAdjacentRefForAssetInstall(
            value,
            namespace,
            sourceTargetType,
            sourceTargetId,
            executionId: taskId
        ).trimAscii()
        if (value.size == 0) {
            TaskIO.appendLog(taskId, "WARN: preview asset materialize failed owner=${ownerId} key=${normalizedKey} namespace=${namespace}")
            return ""
        }

        let normalizedOwnerType = normalizeMetadataOwnerType(ownerType)
        let safeOwnerId = sanitizeAssetOwnerId(ownerId, taskId)
        let assetKind = if (normalizedOwnerType == "tankoubon") {
            if (normalizedKey == "cover") {
                "tankoubon_cover"
            } else if (normalizedKey == "backdrop") {
                "tankoubon_backdrop"
            } else {
                "tankoubon_clearlogo"
            }
        } else {
            if (normalizedKey == "cover") {
                "archive_cover"
            } else if (normalizedKey == "backdrop") {
                "archive_backdrop"
            } else {
                "archive_clearlogo"
            }
        }
        let outputName = if (normalizedKey == "cover") {
            "${safeOwnerId}.avif"
        } else {
            "${safeOwnerId}_${normalizedKey}.avif"
        }

        let (okInstall, newAssetId, _, installErr) = PluginTaskService.installCoverAssetFromPluginPath(
            value,
            namespace,
            assetKind,
            outputName
        )
        if (okInstall && newAssetId > 0) {
            return newAssetId.toString()
        }

        TaskIO.appendLog(taskId, "WARN: preview asset install failed owner=${safeOwnerId} key=${normalizedKey} namespace=${namespace} error=${installErr}")
        return ""
    }

    private static func writePreviewAssetEntry(w: JsonWriter, key: String, value: String): Unit {
        let normalizedKey = key.trimAscii().toAsciiLower()
        if (normalizedKey.size == 0) {
            return
        }
        w.startObject()
        w.writeName("key").writeValue(normalizedKey)
        let parsedId = parsePositiveAssetId(value)
        if (parsedId > 0) {
            w.writeName("value").writeValue(parsedId)
        } else {
            w.writeName("value").writeValue(value)
        }
        w.endObject()
    }

    private static func writeNormalizedMetadataPreviewAssets(
        r: JsonReader,
        w: JsonWriter,
        taskId: Int64,
        pluginNamespace: String,
        sourceTargetType: String,
        sourceTargetId: String,
        ownerType: String,
        ownerId: String
    ): Unit {
        match (r.peek()) {
            case Some(BeginArray) =>
                w.startArray()
                r.startArray()
                while (r.peek() != EndArray) {
                    if (r.peek() != Some(BeginObject)) {
                        let raw = String.fromUtf8(r.readValueBytes())
                        w.jsonValue(raw)
                        continue
                    }

                    var assetKey = ""
                    var assetValue = ""
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let field = r.readName().trimAscii().toAsciiLower()
                        match (field) {
                            case "key" =>
                                assetKey = readJsonValueAsString(r).toAsciiLower()
                            case "value" =>
                                assetValue = readJsonValueAsString(r)
                            case _ => r.skip()
                        }
                    }
                    r.endObject()

                    if (assetKey.trimAscii().size == 0) {
                        continue
                    }
                    let resolved = resolvePreviewAssetValue(
                        taskId,
                        pluginNamespace,
                        sourceTargetType,
                        sourceTargetId,
                        ownerType,
                        ownerId,
                        assetKey,
                        assetValue
                    )
                    writePreviewAssetEntry(w, assetKey, resolved)
                }
                r.endArray()
                w.endArray()
            case Some(BeginObject) =>
                r.skip()
                w.startArray()
                w.endArray()
            case Some(_) =>
                r.skip()
                w.startArray()
                w.endArray()
            case None =>
                w.startArray()
                w.endArray()
        }
    }

    private static func writeNormalizedMetadataPreviewObject(
        r: JsonReader,
        w: JsonWriter,
        taskId: Int64,
        pluginNamespace: String,
        sourceTargetType: String,
        sourceTargetId: String,
        ownerType: String,
        ownerId: String
    ): Unit {
        if (r.peek() != Some(BeginObject)) {
            let raw = String.fromUtf8(r.readValueBytes())
            w.jsonValue(raw)
            return
        }

        r.startObject()
        w.startObject()
        var childIndex: Int64 = 0
        while (r.peek() != EndObject) {
            let key = r.readName()
            let normalizedKey = key.trimAscii().toAsciiLower()
            if (normalizedKey == "assets") {
                w.writeName(key)
                writeNormalizedMetadataPreviewAssets(
                    r,
                    w,
                    taskId,
                    pluginNamespace,
                    sourceTargetType,
                    sourceTargetId,
                    ownerType,
                    ownerId
                )
                continue
            }
            if (normalizedKey == "archive" || normalizedKey == "archives") {
                r.skip()
                continue
            }
            if (normalizedKey == "children" && r.peek() == Some(BeginArray)) {
                w.writeName(key)
                w.startArray()
                r.startArray()
                while (r.peek() != EndArray) {
                    if (r.peek() == Some(BeginObject)) {
                        let childOwnerId = sanitizeAssetOwnerId("${ownerId}_child_${childIndex.toString()}", taskId)
                        writeNormalizedMetadataPreviewObject(
                            r,
                            w,
                            taskId,
                            pluginNamespace,
                            sourceTargetType,
                            sourceTargetId,
                            "archive",
                            childOwnerId
                        )
                    } else {
                        let raw = String.fromUtf8(r.readValueBytes())
                        w.jsonValue(raw)
                    }
                    childIndex += 1
                }
                r.endArray()
                w.endArray()
                continue
            }

            let raw = String.fromUtf8(r.readValueBytes())
            w.writeName(key).jsonValue(raw)
        }
        r.endObject()
        w.endObject()
    }

    private static func normalizeMetadataPreviewOutputAssets(
        taskId: Int64,
        outputJson: String,
        pluginNamespace: String,
        targetType: String,
        targetId: String
    ): String {
        let trimmed = outputJson.trimAscii()
        if (trimmed.size == 0) {
            return outputJson
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return outputJson
            }

            let rootOwnerType = normalizeMetadataOwnerType(targetType)
            let rootOwnerId = sanitizeAssetOwnerId(targetId, taskId)

            let out = ByteBuffer()
            let w = JsonWriter(out)
            r.startObject()
            w.startObject()
            while (r.peek() != EndObject) {
                let key = r.readName()
                if (key == "data" && r.peek() == Some(BeginObject)) {
                    w.writeName(key)
                    writeNormalizedMetadataPreviewObject(
                        r,
                        w,
                        taskId,
                        pluginNamespace,
                        rootOwnerType,
                        targetId,
                        rootOwnerType,
                        rootOwnerId
                    )
                } else {
                    let raw = String.fromUtf8(r.readValueBytes())
                    w.writeName(key).jsonValue(raw)
                }
            }
            r.endObject()
            w.endObject()
            w.flush()
            return String.fromUtf8(readToEnd(out))
        } catch (e: Exception) {
            TaskIO.appendLog(taskId, "WARN: normalize metadata preview assets failed: ${e.message}")
            return outputJson
        }
    }

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

    private static func normalizeMetadataInputJson(raw: String): String {
        let trimmed = raw.trimAscii()
        if (trimmed.size == 0) { return "" }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() == Some(BeginObject)) {
                return trimmed
            }
        } catch (_: Exception) {}
        return ""
    }

    private static func buildMetadataInputJsonForTarget(targetType: String, targetId: String): (Bool, String, String) {
        let effectiveType = targetType.trimAscii().toAsciiLower()
        if (effectiveType == "tankoubon" || effectiveType == "tank") {
            return MetadataPatchService.buildTankoubonMetadataObjectJson(targetId, includePages: false)
        }
        return MetadataPatchService.buildArchiveMetadataObjectJson(targetId, false, 0, includePages: false)
    }

    private static func buildMetadataInputJson(
        pluginType: String,
        targetType: String,
        targetId: String,
        metadataJson: String,
        oneshotParam: String,
        params: String,
        loginCookies: String
    ): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("action").writeValue("run")
        w.writeName("pluginType").writeValue(pluginType)
        w.writeName("targetType").writeValue(targetType)
        w.writeName("targetId").writeValue(targetId)
        w.writeName("oneshotParam").writeValue(oneshotParam)
        let normalizedMetadata = normalizeMetadataInputJson(metadataJson)
        if (normalizedMetadata.size > 0) {
            w.writeName("metadata").jsonValue(normalizedMetadata)
        } else {
            w.writeName("metadata")
            w.startObject()
            w.endObject()
        }

        let trimmedParams = params.trimAscii()
        if (trimmedParams.size > 0) {
            w.writeName("params").jsonValue(trimmedParams)
        } else {
            w.writeName("params")
            w.startObject()
            w.endObject()
        }
        let cookiesTrimmed = loginCookies.trimAscii()
        if (cookiesTrimmed.size > 0) {
            w.writeName("loginCookies").jsonValue(cookiesTrimmed)
        } else {
            w.writeName("loginCookies")
            w.startArray()
            w.endArray()
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
        w.writeName("loginCookies")
        w.startArray()
        w.endArray()
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func buildDownloadInputJson(
        pluginType: String,
        url: String,
        pluginDir: String,
        params: String,
        loginCookies: String
    ): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("action").writeValue("run")
        w.writeName("pluginType").writeValue(pluginType)
        w.writeName("url").writeValue(url)
        w.writeName("pluginDir").writeValue(pluginDir)

        let trimmedParams = params.trimAscii()
        if (trimmedParams.size > 0) {
            w.writeName("params").jsonValue(trimmedParams)
        } else {
            w.writeName("params")
            w.startObject()
            w.endObject()
        }

        let cookiesTrimmed = loginCookies.trimAscii()
        if (cookiesTrimmed.size > 0) {
            w.writeName("loginCookies").jsonValue(cookiesTrimmed)
        } else {
            w.writeName("loginCookies")
            w.startArray()
            w.endArray()
        }
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func buildScriptInputJson(
        pluginType: String,
        oneshotParam: String,
        params: String,
        loginCookies: String
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

        let cookiesTrimmed = loginCookies.trimAscii()
        if (cookiesTrimmed.size > 0) {
            w.writeName("loginCookies").jsonValue(cookiesTrimmed)
        } else {
            w.writeName("loginCookies")
            w.startArray()
            w.endArray()
        }

        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func handleLoginDependency(taskId: Int64, loginNamespace: String, groupId: String): TaskWaitResult {
        let kvStore = TaskKVService.getStore()
        if (groupId.size > 0) {
            match (kvStore.get(groupId, "login_cookies_${loginNamespace}")) {
                case Some(cached) =>
                    let trimmedCached = cached.trimAscii()
                    if (trimmedCached.size > 0) {
                        TaskIO.appendLog(taskId, "Using cached login cookies from KV store")
                        return TaskWaitResult(true, "", "", trimmedCached)
                    }
                case None => ()
            }
        }

        let loginPlugin = PluginTaskService.getPluginByNamespace(loginNamespace)
        if (loginPlugin.namespace.size == 0) {
            return TaskWaitResult(false, "Login plugin not found: ${loginNamespace}", "")
        }
        if (!PluginTaskService.isWasmPlugin(loginPlugin)) {
            return TaskWaitResult(false, "Login plugin is not a wasm plugin: ${loginNamespace}", "")
        }

        let result = executeLoginPluginDirect(taskId, loginPlugin, false)
        if (!result.success) {
            return result
        }

        let cookiesJson = extractLoginCookiesJson(result.output).trimAscii()
        if (cookiesJson.size == 0) {
            return TaskWaitResult(false, "Login plugin returned empty cookies: ${loginNamespace}", "")
        }

        if (groupId.size > 0) {
            let _ = kvStore.set(groupId, "login_cookies_${loginNamespace}", cookiesJson, 3600)
        }
        return TaskWaitResult(true, "", result.output, cookiesJson)
    }

    private static func executeLoginPluginDirect(taskId: Int64, plugin: PluginTaskData, interactivePreviewEnabled: Bool): TaskWaitResult {
        let paramsJson = buildPluginParametersJson(plugin)
        let inputJson = buildLoginInputJson(paramsJson)
        let wasmPath = PluginTaskService.buildPluginFilePath(plugin.plugin_type, plugin.entry)
        let result = WasmHostBridge.runGenericPlugin(
            taskId,
            plugin.namespace,
            wasmPath,
            inputJson,
            plugin.permissions,
            interactivePreviewEnabled
        )
        if (!result.success) {
            return TaskWaitResult(false, result.error, "")
        }
        return TaskWaitResult(true, "", result.output)
    }

    private static func extractLoginCookiesJson(output: String): String {
        if (output.trimAscii().size == 0) {
            return ""
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(output.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return ""
            }

            var success = false
            var cookiesRaw = ""

            r.startObject()
            while (r.peek() != EndObject) {
                let n = r.readName()
                match (n) {
                    case "success" =>
                        let v = r.readValue<String>().trimAscii()
                        success = (v == "true" || v == "1")
                    case "data" =>
                        if (r.peek() == Some(BeginObject)) {
                            r.startObject()
                            while (r.peek() != EndObject) {
                                let dn = r.readName()
                                match (dn) {
                                    case "cookies" =>
                                        if (r.peek() == Some(BeginArray)) {
                                            cookiesRaw = String.fromUtf8(r.readValueBytes())
                                        } else {
                                            r.skip()
                                        }
                                    case _ => r.skip()
                                }
                            }
                            r.endObject()
                        } else {
                            r.skip()
                        }
                    case _ => r.skip()
                }
            }
            r.endObject()

            if (!success) { return "" }
            return cookiesRaw
        } catch (_: Exception) {}

        return ""
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }
}
