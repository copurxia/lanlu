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
    private static let pipelineKvTtlSeconds: Int64 = 86400

    public static func run(taskId: Int64, parameters: String): Unit {
        let (pluginNamespace, pluginType, groupId, targetType, targetId, oneshotParam, url, parentTaskId, extraParams, metadataJson) = parseParameters(parameters)
        appendMirroredLog(taskId, parentTaskId, "wasm_task started")
        updateMirroredProgress(taskId, parentTaskId, 1, "WASM任务开始")

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
            if (plugin.plugin_type.trimAscii() != pluginType.trimAscii()) {
                fail(taskId, "Plugin type mismatch: expected ${pluginType}, got ${plugin.plugin_type}")
                return
            }
            let runtimePermissions = resolveRuntimePermissions(plugin)
            let effectiveGroupId = resolveEffectiveGroupId(groupId, taskId, plugin.namespace)
            let preHooks = parseHookNamespaces(plugin.pre_hooks, "pre", plugin.namespace)
            let afterHooks = parseHookNamespaces(plugin.after_hooks, "after", plugin.namespace)

            TaskDao.updateTaskPluginNamespace(taskId, plugin.namespace)
            seedPipelineKv(effectiveGroupId, plugin.namespace, plugin.plugin_type, targetType, targetId, preHooks, afterHooks)

            let totalStages = preHooks.size + afterHooks.size + 1
            var completedStages: Int64 = 0

            for (hookNamespace in preHooks) {
                let hookPlugin = resolveHookPlugin(hookNamespace, "pre", plugin.namespace)
                updateMirroredProgress(taskId, parentTaskId, computePipelineProgress(completedStages, totalStages), "执行前置阶段 ${hookPlugin.namespace}")
                let hookResult = executeHookPhase(
                    taskId,
                    parentTaskId,
                    hookPlugin,
                    effectiveGroupId,
                    targetType,
                    targetId,
                    oneshotParam,
                    url,
                    plugin.namespace,
                    plugin.plugin_type
                )
                storePhaseResult(effectiveGroupId, hookPlugin.namespace, hookResult)
                if (!hookResult.success) {
                    fail(taskId, "Pre hook failed [${hookPlugin.namespace}]: ${hookResult.error}")
                    return
                }
                completedStages += 1
            }

            updateMirroredProgress(taskId, parentTaskId, computePipelineProgress(completedStages, totalStages), "执行主插件 ${plugin.namespace}")
            let mainResult = executeMainPhase(
                taskId,
                parentTaskId,
                plugin,
                runtimePermissions,
                effectiveGroupId,
                targetType,
                targetId,
                oneshotParam,
                url,
                extraParams,
                metadataJson,
                interactivePreviewEnabled
            )
            storePhaseResult(effectiveGroupId, plugin.namespace, mainResult)
            if (!mainResult.success) {
                fail(taskId, mainResult.error)
                return
            }
            completedStages += 1

            for (hookNamespace in afterHooks) {
                let hookPlugin = resolveHookPlugin(hookNamespace, "after", plugin.namespace)
                updateMirroredProgress(taskId, parentTaskId, computePipelineProgress(completedStages, totalStages), "执行后置阶段 ${hookPlugin.namespace}")
                let hookResult = executeHookPhase(
                    taskId,
                    parentTaskId,
                    hookPlugin,
                    effectiveGroupId,
                    targetType,
                    targetId,
                    oneshotParam,
                    url,
                    plugin.namespace,
                    plugin.plugin_type
                )
                storePhaseResult(effectiveGroupId, hookPlugin.namespace, hookResult)
                if (!hookResult.success) {
                    fail(taskId, "After hook failed [${hookPlugin.namespace}]: ${hookResult.error}")
                    return
                }
                completedStages += 1
            }

            updateMirroredProgress(taskId, parentTaskId, 100, "WASM任务完成")
            TaskModel.completeTask(taskId, "wasm_task completed")
            TaskIO.writeOutput(taskId, mainResult.output)
        } catch (e: Exception) {
            fail(taskId, e.message)
        }
    }

    private static func appendMirroredLog(taskId: Int64, parentTaskId: Int64, line: String): Unit {
        TaskIO.appendLog(taskId, line)
        if (parentTaskId > 0 && parentTaskId != taskId) {
            TaskIO.appendLog(parentTaskId, line)
        }
    }

    private static func updateMirroredProgress(taskId: Int64, parentTaskId: Int64, progress: Int32, message: String): Unit {
        TaskModel.updateTaskProgress(taskId, progress, message)
        if (parentTaskId > 0 && parentTaskId != taskId) {
            TaskModel.updateTaskProgress(parentTaskId, progress, message)
        }
    }

    private static func executeMainPhase(
        taskId: Int64,
        parentTaskId: Int64,
        plugin: PluginTaskData,
        runtimePermissions: String,
        groupId: String,
        targetType: String,
        targetId: String,
        oneshotParam: String,
        url: String,
        extraParams: String,
        metadataJson: String,
        interactivePreviewEnabled: Bool
    ): TaskWaitResult {
        match (plugin.plugin_type.trimAscii()) {
            case "Metadata" =>
                return executeMetadata(taskId, parentTaskId, plugin, runtimePermissions, groupId, targetType, targetId, oneshotParam, extraParams, metadataJson, interactivePreviewEnabled)
            case "Login" =>
                return executeLogin(taskId, parentTaskId, plugin, runtimePermissions, groupId, targetType, targetId, url, interactivePreviewEnabled)
            case "Download" =>
                return executeDownload(taskId, parentTaskId, plugin, runtimePermissions, groupId, targetType, targetId, url, extraParams, interactivePreviewEnabled)
            case "Script" =>
                return executeScript(taskId, parentTaskId, plugin, runtimePermissions, groupId, targetType, targetId, oneshotParam, url, extraParams, interactivePreviewEnabled)
            case _ =>
                return TaskWaitResult(false, "Unsupported wasm plugin type: ${plugin.plugin_type}", "")
        }
    }

    private static func executeHookPhase(
        taskId: Int64,
        parentTaskId: Int64,
        plugin: PluginTaskData,
        groupId: String,
        targetType: String,
        targetId: String,
        oneshotParam: String,
        url: String,
        mainPluginNamespace: String,
        mainPluginType: String
    ): TaskWaitResult {
        let runtimePermissions = resolveRuntimePermissions(plugin)
        match (plugin.plugin_type.trimAscii()) {
            case "Login" =>
                return executeLogin(
                    taskId,
                    parentTaskId,
                    plugin,
                    runtimePermissions,
                    groupId,
                    targetType,
                    targetId,
                    url,
                    false,
                    mainPluginNamespace: mainPluginNamespace,
                    mainPluginType: mainPluginType
                )
            case "Script" =>
                return executeScript(
                    taskId,
                    parentTaskId,
                    plugin,
                    runtimePermissions,
                    groupId,
                    targetType,
                    targetId,
                    oneshotParam,
                    url,
                    "",
                    false,
                    mainPluginNamespace: mainPluginNamespace,
                    mainPluginType: mainPluginType
                )
            case _ =>
                return TaskWaitResult(false, "Unsupported ${plugin.plugin_type} hook plugin: ${plugin.namespace}", "")
        }
    }

    private static func executeMetadata(
        taskId: Int64,
        parentTaskId: Int64,
        plugin: PluginTaskData,
        runtimePermissions: String,
        groupId: String,
        targetType: String,
        targetId: String,
        oneshotParam: String,
        extraParams: String,
        metadataJson: String,
        interactivePreviewEnabled: Bool,
        mainPluginNamespace!: String = "",
        mainPluginType!: String = ""
    ): TaskWaitResult {
        let effectiveType = targetType.trimAscii().toAsciiLower()
        let effectiveId = targetId.trimAscii()
        if (effectiveId.size == 0) {
            return TaskWaitResult(false, "Missing targetId", "")
        }

        var metadataInputJson = normalizeMetadataInputJson(metadataJson)
        if (metadataInputJson.size == 0) {
            let (okMetadata, builtMetadata, metadataErr) = buildMetadataInputJsonForTarget(effectiveType, effectiveId)
            if (!okMetadata) {
                return TaskWaitResult(false, metadataErr, "")
            }
            metadataInputJson = builtMetadata
        }

        updateMirroredProgress(taskId, parentTaskId, 20, "准备WASM插件输入")
        let baseParams = buildPluginParametersJson(plugin)
        let mergedParams = mergeParamsJson(baseParams, extraParams)
        let contextParams = buildRuntimeContextParamsJson(
            effectiveType,
            effectiveId,
            taskId,
            groupId,
            if (mainPluginNamespace.trimAscii().size > 0) { mainPluginNamespace } else { plugin.namespace },
            if (mainPluginType.trimAscii().size > 0) { mainPluginType } else { plugin.plugin_type },
            ""
        )
        let finalParams = mergeParamsJson(mergedParams, contextParams)
        let inputJson = buildMetadataInputJson("Metadata", effectiveType, effectiveId, metadataInputJson, oneshotParam, finalParams)

        updateMirroredProgress(taskId, parentTaskId, 40, "执行WASM插件")
        let wasmPath = PluginTaskService.buildPluginFilePath(plugin.plugin_type, plugin.entry)
        let result = WasmHostBridge.runMetadataPlugin(
            taskId,
            parentTaskId,
            plugin.namespace,
            groupId,
            wasmPath,
            inputJson,
            effectiveType,
            effectiveId,
            runtimePermissions,
            interactivePreviewEnabled
        )
        if (!result.success) {
            return TaskWaitResult(false, result.error, "")
        }

        let normalizedOutput = if (interactivePreviewEnabled) {
            normalizeMetadataPreviewOutputAssets(taskId, result.output, plugin.namespace, effectiveType, effectiveId)
        } else {
            result.output
        }
        return TaskWaitResult(true, "", normalizedOutput)
    }

    private static func executeLogin(
        taskId: Int64,
        parentTaskId: Int64,
        plugin: PluginTaskData,
        runtimePermissions: String,
        groupId: String,
        targetType: String,
        targetId: String,
        url: String,
        interactivePreviewEnabled: Bool,
        mainPluginNamespace!: String = "",
        mainPluginType!: String = ""
    ): TaskWaitResult {
        updateMirroredProgress(taskId, parentTaskId, 20, "准备WASM登录插件输入")
        let paramsJson = mergeParamsJson(
            buildPluginParametersJson(plugin),
            buildRuntimeContextParamsJson(
                targetType.trimAscii().toAsciiLower(),
                targetId.trimAscii(),
                taskId,
                groupId,
                if (mainPluginNamespace.trimAscii().size > 0) { mainPluginNamespace } else { plugin.namespace },
                if (mainPluginType.trimAscii().size > 0) { mainPluginType } else { plugin.plugin_type },
                url
            )
        )
        let inputJson = buildLoginInputJson(paramsJson)

        updateMirroredProgress(taskId, parentTaskId, 40, "执行WASM登录插件")
        let wasmPath = PluginTaskService.buildPluginFilePath(plugin.plugin_type, plugin.entry)
        let result = WasmHostBridge.runGenericPlugin(
            taskId,
            parentTaskId,
            plugin.namespace,
            groupId,
            wasmPath,
            inputJson,
            runtimePermissions,
            interactivePreviewEnabled,
            enableWasi: true
        )
        if (!result.success) {
            return TaskWaitResult(false, result.error, "")
        }
        return TaskWaitResult(true, "", result.output)
    }

    private static func executeDownload(
        taskId: Int64,
        parentTaskId: Int64,
        plugin: PluginTaskData,
        runtimePermissions: String,
        groupId: String,
        targetType: String,
        targetId: String,
        url: String,
        extraParams: String,
        interactivePreviewEnabled: Bool,
        mainPluginNamespace!: String = "",
        mainPluginType!: String = ""
    ): TaskWaitResult {
        let trimmedUrl = url.trimAscii()
        if (trimmedUrl.size == 0) {
            return TaskWaitResult(false, "Missing url", "")
        }

        updateMirroredProgress(taskId, parentTaskId, 20, "准备WASM下载插件输入")
        let baseParams = buildPluginParametersJson(plugin)
        let mergedParams = mergeParamsJson(baseParams, extraParams)
        let finalParams = mergeParamsJson(
            mergedParams,
            buildRuntimeContextParamsJson(
                targetType.trimAscii().toAsciiLower(),
                targetId.trimAscii(),
                taskId,
                groupId,
                if (mainPluginNamespace.trimAscii().size > 0) { mainPluginNamespace } else { plugin.namespace },
                if (mainPluginType.trimAscii().size > 0) { mainPluginType } else { plugin.plugin_type },
                trimmedUrl
            )
        )
        let pluginRuntimeHostDir = FileUtils.joinPath(PluginPaths.getPluginRuntimeRoot(), plugin.namespace)
        FileUtils.ensureDirectoryExists(Path(pluginRuntimeHostDir))
        let pluginGuestDir = "/plugin"
        let inputJson = buildDownloadInputJson("Download", trimmedUrl, pluginGuestDir, finalParams)

        updateMirroredProgress(taskId, parentTaskId, 40, "执行WASM下载插件")
        let wasmPath = PluginTaskService.buildPluginFilePath(plugin.plugin_type, plugin.entry)
        let result = WasmHostBridge.runGenericPlugin(
            taskId,
            parentTaskId,
            plugin.namespace,
            groupId,
            wasmPath,
            inputJson,
            runtimePermissions,
            interactivePreviewEnabled,
            enableWasi: true,
            wasiGuestPath: "/plugin",
            wasiHostPath: pluginRuntimeHostDir
        )
        if (!result.success) {
            return TaskWaitResult(false, result.error, "")
        }
        return TaskWaitResult(true, "", result.output)
    }

    private static func executeScript(
        taskId: Int64,
        parentTaskId: Int64,
        plugin: PluginTaskData,
        runtimePermissions: String,
        groupId: String,
        targetType: String,
        targetId: String,
        oneshotParam: String,
        url: String,
        extraParams: String,
        interactivePreviewEnabled: Bool,
        mainPluginNamespace!: String = "",
        mainPluginType!: String = ""
    ): TaskWaitResult {
        updateMirroredProgress(taskId, parentTaskId, 20, "准备WASM脚本插件输入")
        let baseParams = buildPluginParametersJson(plugin)
        let mergedParams = mergeParamsJson(baseParams, extraParams)
        let finalParams = mergeParamsJson(
            mergedParams,
            buildRuntimeContextParamsJson(
                targetType.trimAscii().toAsciiLower(),
                targetId.trimAscii(),
                taskId,
                groupId,
                if (mainPluginNamespace.trimAscii().size > 0) { mainPluginNamespace } else { plugin.namespace },
                if (mainPluginType.trimAscii().size > 0) { mainPluginType } else { plugin.plugin_type },
                url
            )
        )
        let inputJson = buildScriptInputJson("Script", oneshotParam, finalParams)

        updateMirroredProgress(taskId, parentTaskId, 40, "执行WASM脚本插件")
        let wasmPath = PluginTaskService.buildPluginFilePath(plugin.plugin_type, plugin.entry)
        let result = WasmHostBridge.runGenericPlugin(
            taskId,
            parentTaskId,
            plugin.namespace,
            groupId,
            wasmPath,
            inputJson,
            runtimePermissions,
            interactivePreviewEnabled,
            enableWasi: true
        )
        if (!result.success) {
            return TaskWaitResult(false, result.error, "")
        }
        return TaskWaitResult(true, "", result.output)
    }

    private static func resolveEffectiveGroupId(groupId: String, taskId: Int64, pluginNamespace: String): String {
        let trimmed = groupId.trimAscii()
        if (trimmed.size > 0) {
            return trimmed
        }
        let safeNamespace = pluginNamespace.trimAscii().replace("/", "_").replace("\\", "_").replace(" ", "_")
        return "wasm:${safeNamespace}:${taskId.toString()}"
    }

    private static func parseHookNamespaces(rawJson: String, fieldName: String, pluginNamespace: String): Array<String> {
        let trimmed = rawJson.trimAscii()
        if (trimmed.size == 0 || trimmed == "[]") {
            return Array<String>()
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginArray)) {
                throw Exception("Plugin ${pluginNamespace} field ${fieldName} must be a string array")
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
            return hooks.toArray()
        } catch (e: Exception) {
            throw Exception("Invalid ${fieldName} hooks for plugin ${pluginNamespace}: ${e.message}")
        }
    }

    private static func resolveHookPlugin(namespace: String, phase: String, ownerNamespace: String): PluginTaskData {
        let hookNamespace = namespace.trimAscii()
        if (hookNamespace.size == 0) {
            throw Exception("Plugin ${ownerNamespace} has empty ${phase} hook namespace")
        }
        let plugin = PluginTaskService.getPluginByNamespace(hookNamespace)
        if (plugin.namespace.size == 0) {
            throw Exception("${phase} hook plugin not found: ${hookNamespace}")
        }
        if (!PluginTaskService.isWasmPlugin(plugin)) {
            throw Exception("${phase} hook plugin is not a wasm plugin: ${hookNamespace}")
        }
        let hookType = plugin.plugin_type.trimAscii()
        if (hookType != "Login" && hookType != "Script") {
            throw Exception("${phase} hook plugin must be Login or Script: ${hookNamespace}")
        }
        return plugin
    }

    private static func seedPipelineKv(groupId: String, mainNamespace: String, mainPluginType: String, targetType: String, targetId: String, preHooks: Array<String>, afterHooks: Array<String>): Unit {
        let kvStore = TaskKVService.getStore()
        let _ = kvStore.set(groupId, "__lanlu.pipeline.main_namespace", encodeJsonString(mainNamespace), pipelineKvTtlSeconds)
        let _ = kvStore.set(groupId, "__lanlu.pipeline.target_type", encodeJsonString(targetType.trimAscii().toAsciiLower()), pipelineKvTtlSeconds)
        let _ = kvStore.set(groupId, "__lanlu.pipeline.target_id", encodeJsonString(targetId.trimAscii()), pipelineKvTtlSeconds)
        let _ = kvStore.set(groupId, "__lanlu.pipeline.plan", buildPipelinePlanJson(preHooks, mainNamespace, mainPluginType, afterHooks), pipelineKvTtlSeconds)
    }

    private static func buildPipelinePlanJson(preHooks: Array<String>, mainNamespace: String, mainPluginType: String, afterHooks: Array<String>): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("pre")
        w.startArray()
        for (hook in preHooks) {
            w.writeValue(hook)
        }
        w.endArray()
        w.writeName("main")
        w.startObject()
        w.writeName("namespace").writeValue(mainNamespace)
        w.writeName("plugin_type").writeValue(mainPluginType)
        w.endObject()
        w.writeName("after")
        w.startArray()
        for (hook in afterHooks) {
            w.writeValue(hook)
        }
        w.endArray()
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
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

    private static func storePhaseResult(groupId: String, namespace: String, result: TaskWaitResult): Unit {
        let kvStore = TaskKVService.getStore()
        let safeNamespace = namespace.trimAscii()
        if (groupId.trimAscii().size == 0 || safeNamespace.size == 0) {
            return
        }
        let statusValue = if (result.success) { "\"success\"" } else { "\"failed\"" }
        let outputValue = normalizeJsonForKv(result.output)
        let dataValue = extractPhaseDataJson(result.output)
        let errorValue = if (result.error.trimAscii().size > 0) { encodeJsonString(result.error) } else { "null" }
        let _ = kvStore.set(groupId, "__lanlu.phase.${safeNamespace}.status", statusValue, pipelineKvTtlSeconds)
        let _ = kvStore.set(groupId, "__lanlu.phase.${safeNamespace}.output", outputValue, pipelineKvTtlSeconds)
        let _ = kvStore.set(groupId, "__lanlu.phase.${safeNamespace}.error", errorValue, pipelineKvTtlSeconds)
        let _ = kvStore.set(groupId, "__lanlu.phase.${safeNamespace}.data", dataValue, pipelineKvTtlSeconds)
    }

    private static func normalizeJsonForKv(raw: String): String {
        let trimmed = raw.trimAscii()
        if (trimmed.size == 0) {
            return "null"
        }
        return trimmed
    }

    private static func encodeJsonString(value: String): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.writeValue(value)
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func extractPhaseDataJson(rawOutput: String): String {
        let trimmed = rawOutput.trimAscii()
        if (trimmed.size == 0) {
            return "null"
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return "null"
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let fieldName = r.readName()
                if (fieldName == "data") {
                    return String.fromUtf8(r.readValueBytes()).trimAscii()
                }
                r.skip()
            }
            r.endObject()
        } catch (_: Exception) {}

        return "null"
    }

    private static func computePipelineProgress(completedStages: Int64, totalStages: Int64): Int32 {
        if (totalStages <= 0) {
            return 5
        }
        var clampedCompleted = completedStages
        if (clampedCompleted < 0) { clampedCompleted = 0 }
        if (clampedCompleted > totalStages) { clampedCompleted = totalStages }
        let scaled = 5 + Int32((clampedCompleted * 80) / totalStages)
        return if (scaled < 95) { scaled } else { 95 }
    }

    private static func parseParameters(parameters: String): (String, String, String, String, String, String, String, Int64, String, String) {
        var pluginNamespace = ""
        var pluginType = ""
        var groupId = ""
        var targetType = "archive"
        var targetId = ""
        var oneshotParam = ""
        var url = ""
        var parentTaskId: Int64 = 0
        var extraParams = ""
        var metadata = ""

        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return (pluginNamespace, pluginType, groupId, targetType, targetId, oneshotParam, url, parentTaskId, extraParams, metadata)
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
            parentTaskId = req.parentTaskId
            extraParams = req.extraParams
            metadata = req.metadata
        } catch (_: Exception) {}

        if (targetType.size == 0) { targetType = "archive" }
        return (pluginNamespace, pluginType, groupId, targetType, targetId, oneshotParam, url, parentTaskId, extraParams, metadata)
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
        params: String
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

    private static func buildDownloadInputJson(
        pluginType: String,
        url: String,
        pluginDir: String,
        params: String
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

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }
}
