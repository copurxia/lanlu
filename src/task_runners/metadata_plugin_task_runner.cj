package lanlu.task_runners

import std.time.*
import std.collection.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.dao.*
import lanlu.models.*
import lanlu.utils.*

/**
 * metadata_plugin 任务执行器（运行在TaskPool中）
 * 运行 metadata 插件并将返回的 title/tags/summary 写回归档
 */
public class MetadataPluginTaskRunner {
    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        TaskIO.appendLog(taskId, "metadata_plugin task started")
        TaskModel.updateTaskProgress(taskId, 1, "元数据插件任务开始")
        TaskIO.appendLog(taskId, "metadata_plugin: about to parse parameters")

        let (targetType, targetId, namespace, param, fallbackNamespaces) = parseParameters(parameters)
        TaskIO.appendLog(taskId, "metadata_plugin: parameters parsed")
        if (targetId.size == 0 || namespace.size == 0) {
            fail(taskId, "target_id and namespace are required")
            return
        }

        let effectiveType = if (targetType.size > 0) { targetType.trimAscii().toAsciiLower() } else { "archive" }
        TaskIO.appendLog(taskId, "metadata_plugin: targetType=${effectiveType} targetId=${targetId}")

        // Validate target exists.
        if (effectiveType == "tankoubon" || effectiveType == "tank") {
            match (TankoubonDao.getTankoubonById(targetId)) {
                case Some(_) => ()
                case None =>
                    failAndMaybeEnqueueFallback(taskId, "Tankoubon not found", effectiveType, targetId, param, fallbackNamespaces, context.notifyTaskAvailable)
                    return
            }
        } else {
            TaskIO.appendLog(taskId, "metadata_plugin: about to get archive")
            let archive = ArchiveDao.getArchiveById(targetId)
            TaskIO.appendLog(taskId, "metadata_plugin: archive retrieved")
            if (archive.id.size == 0) {
                failAndMaybeEnqueueFallback(taskId, "Archive not found", effectiveType, targetId, param, fallbackNamespaces, context.notifyTaskAvailable)
                return
            }
        }

        TaskIO.appendLog(taskId, "metadata_plugin: about to get plugin")
        // 获取插件并验证类型
        var plugin = PluginDao.getPluginByNamespace(namespace)
        TaskIO.appendLog(taskId, "metadata_plugin: plugin retrieved")
        TaskIO.appendLog(taskId, "metadata_plugin: namespace=${plugin.namespace}, type=${plugin.plugin_type}, enabled=${plugin.enabled}")
        if (plugin.namespace.size == 0) {
            failAndMaybeEnqueueFallback(taskId, "Plugin not found", effectiveType, targetId, param, fallbackNamespaces, context.notifyTaskAvailable)
            return
        }
        TaskIO.appendLog(taskId, "metadata_plugin: namespace check passed")
        if (plugin.plugin_type != "Metadata") {
            failAndMaybeEnqueueFallback(taskId, "Plugin is not a Metadata plugin", effectiveType, targetId, param, fallbackNamespaces, context.notifyTaskAvailable)
            return
        }
        TaskIO.appendLog(taskId, "metadata_plugin: type check passed")
        if (!plugin.enabled) {
            // 与 download_url 保持一致：若匹配到禁用插件，自动启用一次
            plugin.enabled = true
            PluginDao.setEnabled(plugin.namespace, true)
        }
        TaskIO.appendLog(taskId, "metadata_plugin: enabled check passed")
        TaskIO.appendLog(taskId, "metadata_plugin: about to update task plugin namespace")

        let updateResult = TaskDao.updateTaskPluginNamespace(taskId, plugin.namespace)
        TaskIO.appendLog(taskId, "metadata_plugin: update result=${updateResult}")
        TaskIO.appendLog(taskId, "metadata_plugin: task plugin namespace updated")
        TaskIO.appendLog(taskId, "plugin=${plugin.namespace}")

        // 生成 groupId 用于 KV store
        let groupId = "metadata_${taskId}_${DateTime.now().toUnixTimeStamp().toSeconds()}"

        TaskModel.updateTaskProgress(taskId, 10, "创建 Deno 任务")

        let (oneshotOpt, extraParamsOpt) = splitParam(param)

        // 创建 deno_task 参数
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("pluginNamespace").writeValue(plugin.namespace)
        w.writeName("pluginType").writeValue("Metadata")
        w.writeName("action").writeValue("run")
        w.writeName("groupId").writeValue(groupId)
        w.writeName("targetType").writeValue(effectiveType)
        w.writeName("targetId").writeValue(targetId)
        // Backward-compatible field for older runners/plugins.
        w.writeName("archiveId").writeValue(targetId)
        match (oneshotOpt) {
            case Some(v) => w.writeName("oneshotParam").writeValue(v)
            case None => ()
        }
        match (extraParamsOpt) {
            case Some(v) => w.writeName("extraParams").writeValue(v)
            case None => ()
        }
        w.endObject()
        w.flush()
        let denoParams = String.fromUtf8(readToEnd(out))

        // 创建并提交 deno_task
        let denoTask = TaskModel.createTaskWithOptions(
            "执行元数据插件",
            "deno_task",
            denoParams,
            50,
            groupId,
            "metadata_plugin:${taskId}"
        )

        if (denoTask.id <= 0) {
            failAndMaybeEnqueueFallback(taskId, "Failed to create deno_task", effectiveType, targetId, param, fallbackNamespaces, context.notifyTaskAvailable)
            return
        }

        TaskIO.appendLog(taskId, "deno_task created: ${denoTask.id}")

        // 创建回调任务（等待 deno_task 完成后自动触发）
        TaskModel.updateTaskProgress(taskId, 20, "创建回调任务")
        let callbackParams = buildCallbackParams(effectiveType, targetId, plugin.namespace, denoTask.id, param, fallbackNamespaces)
        let callbackTask = TaskModel.createWaitingTask(
            "元数据写回",
            "metadata_plugin_callback",
            callbackParams,
            denoTask.id,
            groupId,
            "metadata_plugin:${taskId}"
        )

        if (callbackTask.id <= 0) {
            failAndMaybeEnqueueFallback(taskId, "Failed to create callback task", effectiveType, targetId, param, fallbackNamespaces, context.notifyTaskAvailable)
            return
        }

        TaskIO.appendLog(taskId, "callback_task created: ${callbackTask.id}, waiting for deno_task: ${denoTask.id}")

        // 通知 TaskPool 有新任务可用
        context.notifyTaskAvailable()

        // 立即完成原任务（不再等待）
        TaskModel.updateTaskProgress(taskId, 100, "任务已提交")
        let resultJson = "{\"success\":1,\"deno_task_id\":${denoTask.id},\"callback_task_id\":${callbackTask.id},\"target_type\":\"${effectiveType}\",\"target_id\":\"${targetId}\"}"
        TaskModel.completeTask(taskId, "metadata_plugin task submitted")
        TaskIO.writeOutput(taskId, resultJson)
    }

    /**
     * 构建回调任务参数
     */
    private static func buildCallbackParams(targetType: String, targetId: String, namespace: String, denoTaskId: Int64, param: String, fallbackNamespaces: Array<String>): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("targetType").writeValue(targetType)
        w.writeName("targetId").writeValue(targetId)
        // Backward-compatible field.
        w.writeName("archiveId").writeValue(targetId)
        w.writeName("namespace").writeValue(namespace)
        if (param.trimAscii().size > 0) {
            writeParamField(w, param)
        }
        if (fallbackNamespaces.size > 0) {
            w.writeName("fallback_namespaces")
            w.startArray()
            for (ns in fallbackNamespaces) {
                w.writeValue(ns)
            }
            w.endArray()
        }
        w.writeName("denoTaskId").writeValue(denoTaskId)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func parseParameters(parameters: String): (String, String, String, String, Array<String>) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ("", "", "", "", Array<String>())
        }

        var targetType = ""
        var targetId = ""
        var namespace = ""
        var param = ""
        var fallbackNamespaces = ArrayList<String>()

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            func readRawJson(): String {
                match (r.peek()) {
                    case Some(BeginObject) =>
                        let bytes = r.readValueBytes()
                        return String.fromUtf8(bytes)
                    case Some(BeginArray) =>
                        let bytes = r.readValueBytes()
                        return String.fromUtf8(bytes)
                    case Some(_) =>
                        return r.readValue<String>()
                    case None => return ""
                }
            }

            if (r.peek() == Some(BeginObject)) {
                r.startObject()
                while (r.peek() != EndObject) {
                    let k = r.readName()
                    match (k) {
                        case "target_type" => targetType = r.readValue<String>().trimAscii()
                        case "targetType" => targetType = r.readValue<String>().trimAscii()
                        case "target_id" => targetId = r.readValue<String>().trimAscii()
                        case "targetId" => targetId = r.readValue<String>().trimAscii()
                        case "tankoubon_id" =>
                            if (targetId.size == 0) { targetId = r.readValue<String>().trimAscii(); targetType = "tankoubon" } else { r.skip() }
                        case "archive_id" =>
                            if (targetId.size == 0) { targetId = r.readValue<String>().trimAscii(); if (targetType.size == 0) { targetType = "archive" } } else { r.skip() }
                        case "id" =>
                            if (targetId.size == 0) { targetId = r.readValue<String>().trimAscii() } else { r.skip() }
                        case "arcid" =>
                            if (targetId.size == 0) { targetId = r.readValue<String>().trimAscii() } else { r.skip() }
                        case "archiveId" =>
                            if (targetId.size == 0) { targetId = r.readValue<String>().trimAscii(); if (targetType.size == 0) { targetType = "archive" } } else { r.skip() }
                        case "namespace" => namespace = r.readValue<String>().trimAscii()
                        case "param" => param = readRawJson()
                        case "fallback_namespaces" =>
                            if (r.peek() == Some(BeginArray)) {
                                r.startArray()
                                while (r.peek() != EndArray) {
                                    match (r.peek()) {
                                        case Some(_) =>
                                            let v = r.readValue<String>().trimAscii()
                                            if (v.size > 0) { fallbackNamespaces.add(v) }
                                        case None => break
                                    }
                                }
                                r.endArray()
                            } else {
                                r.skip()
                            }
                        case _ => r.skip()
                    }
                }
                r.endObject()
            }
        } catch (_: Exception) {}

        if (targetType.size == 0) { targetType = "archive" }
        return (targetType.trimAscii(), targetId.trimAscii(), namespace, param.trimAscii(), fallbackNamespaces.toArray())
    }

    private static func writeParamField(w: JsonWriter, param: String): Unit {
        let trimmed = param.trimAscii()
        if (trimmed.size == 0) { return }

        w.writeName("param")
        if ((trimmed.startsWith("{") && trimmed.endsWith("}")) || (trimmed.startsWith("[") && trimmed.endsWith("]"))) {
            w.jsonValue(trimmed)
        } else {
            w.writeValue(trimmed)
        }
    }

    private static func enqueueFallbackTask(targetType: String, targetId: String, param: String, fallbackNamespaces: Array<String>, taskId: Int64, notifier: TaskNotifier): Bool {
        if (fallbackNamespaces.size == 0 || targetId.trimAscii().size == 0) { return false }

        let nextNamespace = fallbackNamespaces[0].trimAscii()
        if (nextNamespace.size == 0) { return false }

        var remainingBuilder = ArrayList<String>()
        for (i in 1..fallbackNamespaces.size) {
            let value = fallbackNamespaces[i].trimAscii()
            if (value.size > 0) {
                remainingBuilder.add(value)
            }
        }
        let remaining = remainingBuilder.toArray()

        try {
            let out = ByteBuffer()
            let w = JsonWriter(out)
            w.startObject()
            w.writeName("target_type").writeValue(targetType)
            w.writeName("target_id").writeValue(targetId)
            if (targetType == "tankoubon" || targetType == "tank") {
                w.writeName("tankoubon_id").writeValue(targetId)
            } else {
                w.writeName("archive_id").writeValue(targetId)
            }
            w.writeName("namespace").writeValue(nextNamespace)
            writeParamField(w, param)
            if (remaining.size > 0) {
                w.writeName("fallback_namespaces")
                w.startArray()
                for (ns in remaining) {
                    let value = ns.trimAscii()
                    if (value.size > 0) {
                        w.writeValue(value)
                    }
                }
                w.endArray()
            }
            w.endObject()
            w.flush()

            let params = String.fromUtf8(readToEnd(out))
            let fallbackTask = TaskModel.createTaskWithOptions(
                "元数据扫描: ${nextNamespace}",
                "metadata_plugin",
                params,
                15i32,
                targetId,
                "metadata_plugin_fallback:${taskId}"
            )

            if (fallbackTask.id > 0) {
                notifier()
                TaskIO.appendLog(taskId, "enqueued fallback metadata plugin namespace=${nextNamespace} task_id=${fallbackTask.id}")
                return true
            }
        } catch (e: Exception) {
            TaskIO.appendLog(taskId, "WARN: failed to enqueue fallback metadata plugin: ${e.message}")
        }

        return false
    }

    private static func failAndMaybeEnqueueFallback(taskId: Int64, message: String, targetType: String, targetId: String, param: String, fallbackNamespaces: Array<String>, notifier: TaskNotifier): Unit {
        let enqueued = enqueueFallbackTask(targetType, targetId, param, fallbackNamespaces, taskId, notifier)
        if (enqueued) {
            TaskIO.appendLog(taskId, "current plugin failed, fallback plugin has been scheduled")
        }
        fail(taskId, message)
    }

    /**
     * param 若是 JSON 对象字符串，则作为 extra --params；否则作为 oneshot 参数
     */
    private static func splitParam(param: String): (Option<String>, Option<String>) {
        let trimmed = param.trimAscii()
        if (trimmed.size == 0) {
            return (Option.None, Option.None)
        }

        if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
            try {
                var buf = ByteBuffer()
                unsafe { buf.write(trimmed.rawData()) }
                let r = JsonReader(buf)
                if (r.peek() == Some(BeginObject)) {
                    return (Option.None, Option<String>.Some(trimmed))
                }
            } catch (_: Exception) {}
        }

        return (Option<String>.Some(trimmed), Option.None)
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }

}
