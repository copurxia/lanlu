package lrr4cj.services

import stdx.encoding.json.*
import stdx.log.*
import lrr4cj.models.*
import lrr4cj.utils.*

/**
 * upload_process 任务执行器：对已落盘的archive文件进行入库/缩略图处理
 * 重构后：创建 scan_archive 子任务，由 TaskPool 异步处理
 */
public class UploadProcessTaskRunner {
    public static func run(taskId: Int64, parameters: String): Unit {
        let logger = getLogger("upload_process_task")
        TaskIO.appendLog(taskId, "upload_process task started")

        let archivePath = parseField(parameters, "archive_path")
        let relativePath = parseField(parameters, "relative_path")
        let fileName = parseField(parameters, "filename")

        if (archivePath.size == 0) {
            fail(taskId, "archive_path is required")
            return
        }

        try {
            TaskModel.updateTaskProgress(taskId, 50, "创建档案扫描任务")

            // 创建 scan_archive 子任务（优先级 20，高于定时扫描）
            let scanParams = "{\"archive_path\":\"${escapeJson(archivePath)}\"}"
            let groupId = "upload:${taskId}"
            let scanTask = TaskModel.createTaskWithOptions(
                "扫描上传档案",
                "scan_archive",
                scanParams,
                20, // 上传任务优先级为 20
                groupId,
                "upload"
            )

            if (scanTask.id > 0) {
                TaskPoolService.getInstance().notifyTaskAvailable()
                logger.debug("Created scan_archive task for upload", ("scan_task_id", scanTask.id.toString()), ("archive_path", archivePath))

                let okJson =
                    "{\"success\":1,\"scan_task_id\":${scanTask.id},\"relative_path\":\"${escapeJson(relativePath)}\",\"filename\":\"${escapeJson(fileName)}\",\"message\":\"Archive scan task created\"}"
                TaskModel.updateTaskProgress(taskId, 100, "档案扫描任务已创建")
                TaskModel.completeTask(taskId, "upload_process completed, scan_archive task created")
                TaskIO.writeOutput(taskId, okJson)
                TaskIO.appendLog(taskId, "upload_process task completed: scan_task_id=${scanTask.id}")
            } else {
                fail(taskId, "Failed to create scan_archive task")
            }
        } catch (e: Exception) {
            logger.error("upload_process exception", ("error", e.message))
            fail(taskId, e.message)
        }
    }

    private static func parseField(parameters: String, key: String): String {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ""
        }
        try {
            let jsonVal = JsonValue.fromStr(trimmed)
            match (jsonVal) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    if (fields.contains(key)) {
                        return fields[key].toString().trimAscii()
                    }
                case _ => ()
            }
        } catch (_: Exception) {}
        return ""
    }

    private static func escapeJson(s: String): String {
        var escaped = s
        escaped = escaped.replace("\\", "\\\\")
        escaped = escaped.replace("\"", "\\\"")
        escaped = escaped.replace("\b", "\\b")
        escaped = escaped.replace("\f", "\\f")
        escaped = escaped.replace("\n", "\\n")
        escaped = escaped.replace("\r", "\\r")
        escaped = escaped.replace("\t", "\\t")
        return escaped
    }

    private static func fail(taskId: Int64, message: String): Unit {
        let msg = if (message.size == 0) { "Unknown error" } else { message }
        TaskIO.appendLog(taskId, "FAILED: ${msg}")
        TaskModel.failTask(taskId, msg)
        TaskIO.writeOutput(taskId, "{\"success\":0,\"error\":\"${escapeJson(msg)}\"}")
    }
}

