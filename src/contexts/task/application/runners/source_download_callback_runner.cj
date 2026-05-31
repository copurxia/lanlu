package lanlu.contexts.task.application.runners

import std.convert.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.log.*
import stdx.encoding.json.stream.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*

public class SourceDownloadCallbackRunner {

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("source_download_callback")
        TaskIO.appendLog(taskId, "source_download_callback task started")
        TaskModel.updateTaskProgress(taskId, 10, "开始处理在线源下载回调")

        let (downloadTaskId, pluginTaskId, categoryId, pluginNamespace, kind) = parseParameters(parameters)
        if (downloadTaskId <= 0 || pluginTaskId <= 0 || categoryId <= 0 || pluginNamespace.size == 0) {
            fail(taskId, "Invalid callback parameters")
            return
        }

        TaskIO.appendLog(
            taskId,
            "callback params: downloadTaskId=${downloadTaskId}, pluginTaskId=${pluginTaskId}, categoryId=${categoryId}, pluginNamespace=${pluginNamespace}"
        )

        let pluginTask = TaskDao.getTaskDataById(pluginTaskId)
        let pluginOutput = TaskIO.readOutput(pluginTaskId)

        if (!pluginTask.taskStatus.isCompleted()) {
            let errMsg = if (pluginTask.message.trimAscii().size > 0) { pluginTask.message } else { "Plugin task failed" }
            TaskModel.failTask(downloadTaskId, errMsg)
            TaskIO.writeOutput(downloadTaskId, buildErrorResult(errMsg))
            fail(taskId, "Dependency plugin task not completed: ${errMsg}")
            return
        }

        if (pluginOutput.trimAscii().size == 0) {
            let errMsg = "Source plugin output is empty"
            TaskModel.failTask(downloadTaskId, errMsg)
            TaskIO.writeOutput(downloadTaskId, buildErrorResult(errMsg))
            fail(taskId, errMsg)
            return
        }

        let galleryUrl = parseGalleryUrl(pluginOutput)
        if (galleryUrl.size == 0) {
            let pluginErr = parsePluginError(pluginOutput)
            let errMsg = if (pluginErr.size > 0) { pluginErr } else { "Source plugin did not return gallery URL" }
            TaskModel.failTask(downloadTaskId, errMsg)
            TaskIO.writeOutput(downloadTaskId, buildErrorResult(errMsg))
            fail(taskId, errMsg)
            return
        }

        TaskModel.updateTaskProgress(taskId, 50, "创建 download_url 任务")
        TaskIO.appendLog(taskId, "gallery_url=${galleryUrl}, category_id=${categoryId}")

        let dlOut = ByteBuffer()
        let dlW = JsonWriter(dlOut)
        dlW.startObject()
        dlW.writeName("url").writeValue(galleryUrl)
        dlW.writeName("category_id").writeValue(categoryId)
        dlW.endObject()
        dlW.flush()
        let dlParams = String.fromUtf8(readToEnd(dlOut))

        let dlTask = TaskModel.createTaskWithOptions(
            "下载在线源归档",
            "download_url",
            dlParams,
            50,
            "source_download:${downloadTaskId}",
            "source"
        )

        if (dlTask.id <= 0) {
            let errMsg = "Failed to create download_url task"
            TaskModel.failTask(downloadTaskId, errMsg)
            TaskIO.writeOutput(downloadTaskId, buildErrorResult(errMsg))
            fail(taskId, errMsg)
            return
        }

        context.notifyTaskAvailable()

        // Create a scan callback task that waits for download_url to complete,
        // then waits for scan_archive and finally completes source_download with archive_id or tankoubon_id.
        TaskModel.updateTaskProgress(taskId, 60, "创建扫描入库回调任务")
        let scanCbOut = ByteBuffer()
        let scanCbW = JsonWriter(scanCbOut)
        scanCbW.startObject()
        scanCbW.writeName("sourceDownloadTaskId").writeValue(downloadTaskId)
        scanCbW.writeName("downloadUrlTaskId").writeValue(dlTask.id)
        scanCbW.writeName("kind").writeValue(kind)
        scanCbW.endObject()
        scanCbW.flush()
        let scanCbParams = String.fromUtf8(readToEnd(scanCbOut))
        let scanCbTask = TaskModel.createWaitingTask(
            "等待扫描入库",
            "source_download_scan_callback",
            scanCbParams,
            dlTask.id,
            "source_download:${downloadTaskId}",
            "source_download:${downloadTaskId}"
        )
        if (scanCbTask.id <= 0) {
            let errMsg = "Failed to create source_download_scan_callback task"
            TaskModel.failTask(downloadTaskId, errMsg)
            fail(taskId, errMsg)
            return
        }
        context.notifyTaskAvailable()

        // Do NOT complete source_download here; leave it waiting for scan callback.
        let resultJson = buildSuccessResult(dlTask.id, galleryUrl)
        TaskModel.updateTaskProgress(downloadTaskId, 60, "等待下载和扫描入库")
        TaskIO.writeOutput(downloadTaskId, resultJson)
        TaskIO.appendLog(downloadTaskId, "source_download waiting for scan: download_url_task_id=${dlTask.id}, scan_callback_task_id=${scanCbTask.id}")

        TaskModel.updateTaskProgress(taskId, 100, "在线源下载回调完成")
        TaskModel.completeTask(taskId, "source_download_callback completed")
        let cbOut = ByteBuffer()
        let cbW = JsonWriter(cbOut)
        cbW.startObject()
        cbW.writeName("success").writeValue(1)
        cbW.writeName("download_task_id").writeValue(downloadTaskId)
        cbW.writeName("download_url_task_id").writeValue(dlTask.id)
        cbW.writeName("scan_callback_task_id").writeValue(scanCbTask.id)
        cbW.endObject()
        cbW.flush()
        TaskIO.writeOutput(taskId, String.fromUtf8(readToEnd(cbOut)))

        logger.debug("source_download_callback completed", ("download_task_id", downloadTaskId.toString()), ("download_url_task_id", dlTask.id.toString()), ("scan_callback_task_id", scanCbTask.id.toString()))
    }

    private static func buildSuccessResult(dlTaskId: Int64, galleryUrl: String): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(1)
        w.writeName("task_id").writeValue(dlTaskId.toString())
        w.writeName("url").writeValue(galleryUrl)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func buildErrorResult(message: String): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(0)
        w.writeName("error").writeValue(message)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func parseGalleryUrl(output: String): String {
        if (output.size == 0) {
            return ""
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(output.rawData()) }
            let r = JsonReader(buf)

            var ok = false
            var galleryUrl = ""

            if (r.peek() != Some(BeginObject)) { return "" }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "success" =>
                        let v = r.readValue<String>().trimAscii()
                        ok = v == "true" || v == "1"
                    case "data" =>
                        match (r.peek()) {
                            case Some(BeginObject) =>
                                r.startObject()
                                while (r.peek() != EndObject) {
                                    let fn = r.readName()
                                    match (fn) {
                                        case "gallery_url" => galleryUrl = r.readValue<String>().trimAscii()
                                        case _ => r.skip()
                                    }
                                }
                                r.endObject()
                            case Some(_) => r.skip()
                            case None => ()
                        }
                    case _ => r.skip()
                }
            }
            r.endObject()

            if (ok && galleryUrl.size > 0) { return galleryUrl }
        } catch (_: Exception) {}
        return ""
    }

    private static func parsePluginError(output: String): String {
        if (output.trimAscii().size == 0) {
            return ""
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(output.rawData()) }
            let r = JsonReader(buf)

            func readBoolFlexible(): Bool {
                let v = r.readValue<String>().trimAscii().toAsciiLower()
                return v == "true" || v == "1"
            }

            var successSeen = false
            var success = false
            var err = ""

            if (r.peek() != Some(BeginObject)) { return "" }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "success" =>
                        successSeen = true
                        success = readBoolFlexible()
                    case "error" =>
                        err = r.readValue<String>().trimAscii()
                    case _ => r.skip()
                }
            }
            r.endObject()

            if (successSeen && !success && err.size > 0) { return err }
        } catch (_: Exception) {}
        return ""
    }

    private static func parseParameters(parameters: String): (Int64, Int64, Int64, String, String) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return (0, 0, 0, "", "")
        }

        var downloadTaskId: Int64 = 0
        var pluginTaskId: Int64 = 0
        var categoryId: Int64 = 0
        var pluginNamespace = ""
        var kind = ""

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            func readInt64Flexible(): Int64 {
                let s = r.readValue<String>().trimAscii()
                try { return Int64.parse(s) } catch (_: Exception) { return 0 }
            }

            match (r.peek()) {
                case Some(BeginObject) =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let k = r.readName()
                        match (k) {
                            case "downloadTaskId" => downloadTaskId = readInt64Flexible()
                            case "pluginTaskId" => pluginTaskId = readInt64Flexible()
                            case "categoryId" => categoryId = readInt64Flexible()
                            case "pluginNamespace" => pluginNamespace = r.readValue<String>().trimAscii()
                            case "kind" => kind = r.readValue<String>().trimAscii()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                case _ => ()
            }
        } catch (_: Exception) {}

        return (downloadTaskId, pluginTaskId, categoryId, pluginNamespace, kind)
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }
}
