package lanlu.contexts.plugin.application

import std.collection.*
import std.fs.*
import std.io.{ByteBuffer, readToEnd}
import std.time.*
import stdx.encoding.json.stream.*
import stdx.log.*
import lanlu.contexts.plugin.domain.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*

/**
 * Source 插件执行服务。
 *
 * 负责直接执行 Metadata 和 Download 插件来处理 source 类型的请求，
 * 取代旧的 SourceDirectActionService（后者只处理 Source 类型插件）。
 *
 * 核心能力：
 * - resolveMetadata(sourceId)：通过 Metadata 插件解析 source metadata
 * - resolvePageAsset(sourceId, path)：通过 Download 插件解析单页资源
 * - downloadArchive(sourceId)：通过 Download 插件下载整本档案
 */

/**
 * 解析 source 单页资源的结果。
 */
public class PageAssetResult {
    public var assetId: Int64 = 0
    public var errorMessage: String = ""
}

public class SourcePluginExecutionService {

    /**
     * 通过 Metadata 插件解析 source 的 metadata。
     *
     * @param sourceId 完整的 sourceId，格式 "source:{namespace}:{remote_id}"
     * @return JSON 字符串（符合统一 metadata 结构），或空字符串表示失败
     */
    public static func resolveMetadata(sourceId: String): String {
        let logger = getLogger("source_plugin_execution")

        match (SourcePluginMatcher.findMetadataPlugin(sourceId)) {
            case Some(plugin) =>
                let inputJson = buildResolveMetadataInputJson(sourceId)
                return executePlugin(plugin, inputJson, logger)
            case None =>
                logger.warn("未找到匹配 sourceId 的 Metadata 插件", ("sourceId", sourceId))
                return ""
        }
    }

    /**
     * 通过 Download 插件解析 source 单页资源。
     *
     * @param sourceId 完整的 sourceId
     * @param path 页面定位 key（opaque，由 Metadata 插件的 children 提供）
     * @return 结果含 asset_id (>0 成功) 和错误信息
     */
    public static func resolvePageAsset(sourceId: String, path: String): PageAssetResult {
        let zero = PageAssetResult()

        if (path.trimAscii().size == 0) {
            zero.errorMessage = "missing path"
            return zero
        }

        let logger = getLogger("source_plugin_execution")

        match (SourcePluginMatcher.findDownloadPlugin(sourceId)) {
            case Some(plugin) =>
                let inputJson = buildResolvePageAssetInputJson(sourceId, path)
                let output = executePlugin(plugin, inputJson, logger)
                if (output.trimAscii().size == 0) {
                    zero.errorMessage = "plugin returned empty output for ${sourceId}"
                    return zero
                }
                let (outputSuccess, outputError) = checkPluginOutputSuccess(output)
                if (!outputSuccess) {
                    zero.errorMessage = outputError
                    return zero
                }
                let assetId = parseAssetIdFromOutput(output)
                if (assetId > 0) {
                    zero.assetId = assetId
                    return zero
                } else {
                    let content = if (output.size <= 500) { output } else { "${output[..500]}..." }
                    zero.errorMessage = "failed to parse asset_id from output: ${content}"
                    return zero
                }
            case None =>
                logger.warn("未找到匹配 sourceId 的 Download 插件", ("sourceId", sourceId))
                zero.errorMessage = "no matching download plugin for ${sourceId}"
                return zero
        }
    }

    /**
     * 通过 Download 插件下载整本 source 档案。
     *
     * @param sourceId 完整的 sourceId
     * @return 任务 task id，0 表示失败
     */
    public static func downloadArchive(sourceId: String, categoryId: Int64, kind: String): Int64 {
        if (categoryId <= 0) {
            return 0
        }

        let logger = getLogger("source_plugin_execution")

        match (SourcePluginMatcher.findDownloadPlugin(sourceId)) {
            case Some(plugin) =>
                // 通过 taskpool 执行 Download 插件的 download_archive action
                let taskParams = buildDownloadArchiveTaskParams(sourceId, plugin.namespace, categoryId, kind)
                let task = TaskModel.createTaskWithOptions(
                    "在线源下载",
                    "wasm_task",
                    taskParams,
                    50,
                    "source_download:${sourceId}",
                    "source"
                )
                return if (task.id > 0) { task.id } else { 0 }
            case None =>
                logger.warn("未找到匹配 sourceId 的 Download 插件", ("sourceId", sourceId))
                return 0
        }
    }

    // ─── 内部方法 ───

    /**
     * 构建 resolve_metadata 输入 JSON。
     */
    private static func buildResolveMetadataInputJson(sourceId: String): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("action").writeValue("resolve_metadata")
        w.writeName("pluginType").writeValue("Metadata")
        w.writeName("targetType").writeValue("source")
        w.writeName("targetId").writeValue(sourceId)
        w.writeName("metadata")
        w.startObject()
        w.endObject()
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    /**
     * 构建 resolve_page_asset 输入 JSON。
     */
    private static func buildResolvePageAssetInputJson(sourceId: String, path: String): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("action").writeValue("resolve_page_asset")
        w.writeName("pluginType").writeValue("Download")
        w.writeName("targetType").writeValue("source")
        w.writeName("targetId").writeValue(sourceId)
        w.writeName("path").writeValue(path)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    /**
     * 构建整本下载的 task params JSON。
     * 使用 wasm_task runner 格式，指定 Download 插件执行 download_archive。
     */
    private static func buildDownloadArchiveTaskParams(sourceId: String, pluginNamespace: String, categoryId: Int64, kind: String): String {
        let groupId = "source_download:${sourceId}"
        let paramsOut = ByteBuffer()
        let pw = JsonWriter(paramsOut)
        pw.startObject()
        pw.writeName("category_id").writeValue(categoryId)
        pw.writeName("kind").writeValue(kind)
        pw.endObject()
        pw.flush()

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("pluginNamespace").writeValue(pluginNamespace)
        w.writeName("pluginType").writeValue("Download")
        w.writeName("action").writeValue("download_archive")
        w.writeName("groupId").writeValue(groupId)
        w.writeName("targetType").writeValue("source")
        w.writeName("targetId").writeValue(sourceId)
        w.writeName("extraParams").writeValue(String.fromUtf8(readToEnd(paramsOut)))
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    /**
     * 执行 WASM 插件并返回输出。
     *
     * 直连路径（taskId=0）下，先运行插件的 pre-hooks（通常是 Login），
     * 再执行主插件，且两者共享同一个 groupId，使登录插件写入的
     * __lanlu.phase.{loginNs}.data 能被主插件读取。
     */
    private static func executePlugin(plugin: PluginTaskData, inputJson: String, logger: Logger): String {
        // 直连执行的稳定 groupId：在一次请求内 pre-hook 与主插件共享。
        // 带时间戳避免不同请求间相互干扰，但同一请求内保持一致。
        let groupId = "source_direct:${plugin.namespace}:${DateTime.now().toUnixTimeStamp().toSeconds().toString()}"

        // 1. 运行 pre-hooks（Login/Script），让登录态写入同一 groupId。
        let hookResult = runPreHooksForDirectExecution(plugin, groupId, logger)
        if (!hookResult) {
            return ""
        }

        // 2. 运行主插件。
        let runtimePermissions = resolveRuntimePermissions(plugin)
        let wasmPath = PluginTaskService.buildPluginFilePath(plugin.plugin_type, plugin.entry)
        let pluginRuntimeHostDir = FileUtils.joinPath(PluginPaths.getPluginRuntimeRoot(), plugin.namespace)
        FileUtils.ensureDirectoryExists(Path(pluginRuntimeHostDir))

        let result = WasmHostBridge.runGenericPlugin(
            0,     // taskId = 0 (直接执行，非 taskpool)
            0,     // parentTaskId
            plugin.namespace,
            groupId,
            wasmPath,
            inputJson,
            runtimePermissions,
            false,  // interactivePreviewEnabled
            enableWasi: true,
            wasiGuestPath: "/plugin",
            wasiHostPath: pluginRuntimeHostDir
        )

        if (!result.success) {
            logger.error("WASM 插件执行失败", ("namespace", plugin.namespace), ("error", result.error))
            return ""
        }

        let (outputSuccess, outputError) = checkPluginOutputSuccess(result.output)
        if (!outputSuccess) {
            logger.error("WASM 插件返回失败", ("namespace", plugin.namespace), ("error", outputError))
            return ""
        }

        return result.output
    }

    /**
     * 在直连路径下运行主插件的 pre-hooks（Login/Script）。
     * 复用 PluginExecutionService 的 hook 解析与执行能力，
     * 共享同一 groupId，使登录插件写入的 auth data 可被主插件读取。
     *
     * @return true 表示 pre-hooks 全部成功（或无 pre-hook）；false 表示失败。
     */
    private static func runPreHooksForDirectExecution(
        plugin: PluginTaskData,
        groupId: String,
        logger: Logger
    ): Bool {
        let hooks = match (PluginExecutionService.parseHookNamespacesPublic(plugin.pre_hooks)) {
            case Some(value) => value
            case None =>
                logger.error("解析 pre_hooks 失败", ("namespace", plugin.namespace))
                return false
        }

        for (hookNs in hooks) {
            let hookPlugin = match (PluginExecutionService.resolveHookPluginPublic(hookNs)) {
                case Some(value) => value
                case None =>
                    logger.error("pre-hook 插件未找到或无效", ("hook", hookNs))
                    return false
            }
            let hookResult = PluginExecutionService.executeDirectHook(
                hookPlugin,
                groupId,
                "source",
                plugin.namespace,
                0,
                0,
                plugin.namespace,
                plugin.plugin_type
            )
            if (!hookResult.success) {
                logger.error("pre-hook 执行失败",
                    ("hook", hookNs),
                    ("error", hookResult.error))
                return false
            }
        }
        return true
    }

    /**
     * 从插件输出中解析 asset_id。
     * 输出格式：{ "success": true, "data": { "asset_id": 123 } }
     */
    private static func parseAssetIdFromOutput(output: String): Int64 {
        let trimmed = output.trimAscii()
        if (trimmed.size == 0) {
            return 0
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return 0
            }
            var assetId: Int64 = 0
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                if (name == "data") {
                    if (r.peek() == Some(BeginObject)) {
                        r.startObject()
                        while (r.peek() != EndObject) {
                            let dataKey = r.readName()
                            if (dataKey == "asset_id") {
                                assetId = r.readValue<Int64>()
                            } else {
                                r.skip()
                            }
                        }
                        r.endObject()
                    } else {
                        r.skip()
                    }
                } else {
                    r.skip()
                }
            }
            r.endObject()
            return if (assetId > 0) { assetId } else { 0 }
        } catch (_: Exception) {}

        return 0
    }

    // ─── 以下复用自 PluginExecutionService（合并到共享方法的候选）───

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
        if (trimmed.size == 0) { return "" }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) { return "" }
            r.startObject()
            while (r.peek() != EndObject) {
                let key = r.readName()
                if (key == "permissions") {
                    let parsed = readCommaSeparated(r)
                    r.endObject()
                    return parsed
                }
                r.skip()
            }
            r.endObject()
        } catch (_: Exception) {}
        return ""
    }

    private static func readCommaSeparated(r: JsonReader): String {
        match (r.peek()) {
            case Some(BeginArray) =>
                let out = ArrayList<String>()
                r.startArray()
                while (r.peek() != EndArray) {
                    let value = r.readValue<String>().trimAscii()
                    if (value.size > 0) { out.add(value) }
                }
                r.endArray()
                return String.join(out.toArray(), delimiter: ",")
            case Some(_) => return r.readValue<String>().trimAscii()
            case None => return ""
        }
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
                    match (r.peek()) {
                        case Some(BeginObject) | Some(BeginArray) =>
                            let bytes = r.readValueBytes()
                            error = String.fromUtf8(bytes).trimAscii()
                        case Some(_) => error = r.readValue<String>().trimAscii()
                        case None => ()
                    }
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
}
