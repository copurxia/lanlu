package lanlu.contexts.task.application.runners

import std.convert.*
import stdx.log.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.contexts.plugin.application.{SourcePluginMatcher, SourcePluginExecutionService}
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.category.infrastructure.persistence.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*

/**
 * source_download 任务执行器（在线源下载壳任务）。
 *
 * 编排结构与 DownloadUrlTaskRunner 一致：
 * 壳任务（本 runner） -> wasm 插件子任务 -> download_url_callback
 * （复用回调：搬运文件到分类目录 + 创建 scan_archive 入库 + 结果写回壳任务）。
 *
 * 此前在线源下载直接创建顶层 wasm_task，插件下载完成后文件停留在插件缓存目录，
 * 没有任何组件负责搬运与扫描，导致“任务成功但未入库”。
 */
public class SourceDownloadTaskRunner {

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let _ = getLogger("source_download_task")
        TaskIO.appendLog(taskId, "source_download task started")
        TaskModel.updateTaskProgress(taskId, 1, "在线源下载任务开始")

        let (sourceId, categoryId, kind) = parseParameters(parameters)
        if (sourceId.size == 0) {
            fail(taskId, "sourceId is required")
            return
        }
        if (categoryId <= 0) {
            fail(taskId, "category_id is required")
            return
        }

        // 获取分类信息
        match (CategoryDao.getCategoryByInternalId(categoryId)) {
            case Some(_) =>
                ()
            case None =>
                fail(taskId, "Category not found")
                return
        }

        try {
            TaskIO.appendLog(taskId, "sourceId=${sourceId}")
            TaskModel.updateTaskProgress(taskId, 5, "匹配下载插件")

            let plugin = match (SourcePluginMatcher.findDownloadPlugin(sourceId)) {
                case Some(value) => value
                case None =>
                    fail(taskId, "No download plugin matches provided sourceId")
                    return
            }
            TaskDao.updateTaskPluginNamespace(taskId, plugin.namespace)
            TaskIO.appendLog(taskId, "matched plugin=${plugin.namespace}")

            // 创建 download_archive 的 wasm 子任务（parentTaskId 用于日志/进度镜像）
            TaskModel.updateTaskProgress(taskId, 10, "创建 WASM 任务")
            let pluginTaskId = SourcePluginExecutionService.createDownloadArchiveTask(
                taskId,
                sourceId,
                plugin.namespace,
                categoryId,
                kind
            )
            if (pluginTaskId <= 0) {
                fail(taskId, "Failed to create plugin task")
                return
            }

            // 通知 TaskPool
            context.notifyTaskAvailable()

            // 创建回调任务（等待插件任务完成后自动触发）。
            // 插件 download_archive 输出与 download_url 插件同构
            // （data[].plugin_relative_path / source / archive_type），
            // 直接复用 download_url_callback 完成搬运与入库。
            TaskModel.updateTaskProgress(taskId, 15, "创建回调任务")
            let callbackParams = buildCallbackParams(taskId, pluginTaskId, categoryId, plugin.namespace)
            let callbackTask = TaskModel.createWaitingTask(
                "下载后处理",
                "download_url_callback",
                callbackParams,
                pluginTaskId,
                "source_download:${taskId}",
                "source_download:${taskId}"
            )

            if (callbackTask.id <= 0) {
                fail(taskId, "Failed to create callback task")
                return
            }

            TaskIO.appendLog(taskId, "callback_task created: ${callbackTask.id}, waiting for plugin task: ${pluginTaskId}")

            // 将当前任务置为 waiting：后续由 callback 负责将本任务标记为 completed/failed 并写回输出
            TaskModel.markTaskWaiting(
                taskId,
                "等待下载插件执行",
                progress: 20,
                waitingReason: "task_dependency",
                phase: "awaiting_dependency"
            )
            let submittedJson = "{\"success\":1,\"plugin_task_id\":${pluginTaskId},\"callback_task_id\":${callbackTask.id}}"
            TaskIO.writeOutput(taskId, submittedJson)
        } catch (e: Exception) {
            fail(taskId, e.message)
        }
    }

    /**
     * 构建回调任务参数（与 DownloadUrlTaskRunner.buildCallbackParams 同构）。
     */
    private static func buildCallbackParams(downloadTaskId: Int64, pluginTaskId: Int64, categoryId: Int64, pluginNamespace: String): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("downloadTaskId").writeValue(downloadTaskId)
        w.writeName("pluginTaskId").writeValue(pluginTaskId)
        w.writeName("categoryId").writeValue(categoryId)
        w.writeName("pluginNamespace").writeValue(pluginNamespace)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func parseParameters(parameters: String): (String, Int64, String) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ("", 0, "archive")
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return ("", 0, "archive")
            }
            var sourceId = ""
            var categoryId: Int64 = 0
            var kind = "archive"
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "sourceId" =>
                        sourceId = r.readValue<String>().trimAscii()
                    case "category_id" =>
                        let raw = r.readValue<String>().trimAscii()
                        try { categoryId = Int64.parse(raw) } catch (_: Exception) { categoryId = CategoryDao.getInternalId(raw) }
                    case "kind" =>
                        kind = r.readValue<String>().trimAscii()
                    case _ =>
                        r.skip()
                }
            }
            r.endObject()
            return (sourceId, categoryId, kind)
        } catch (_: Exception) {}
        return ("", 0, "archive")
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }
}
