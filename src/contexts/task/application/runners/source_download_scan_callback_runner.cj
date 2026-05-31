package lanlu.contexts.task.application.runners

import std.convert.*
import std.io.*
import std.io.{ByteBuffer, readToEnd}
import stdx.log.*
import stdx.encoding.json.stream.*
import lanlu.contexts.task.infrastructure.persistence.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*

/**
 * source_download_scan_callback 回调任务执行器
 * 在 download_url 任务结束后触发：
 * 读取 download_url 输出中的 scan_task_id，等待 scan_archive 完成，
 * 获取 archive_id，并将结果写回到 source_download 任务。
 */
public class SourceDownloadScanCallbackRunner {

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("source_download_scan_callback")
        TaskIO.appendLog(taskId, "source_download_scan_callback task started")
        TaskModel.updateTaskProgress(taskId, 10, "开始等待扫描入库")

        let (sourceDownloadTaskId, downloadUrlTaskId, kind) = parseParameters(parameters)
        if (sourceDownloadTaskId <= 0 || downloadUrlTaskId <= 0) {
            fail(taskId, "Invalid callback parameters")
            return
        }

        TaskIO.appendLog(taskId, "params: sourceDownloadTaskId=${sourceDownloadTaskId}, downloadUrlTaskId=${downloadUrlTaskId}, kind=${kind}")

        // Wait for download_url task to complete
        let dlTask = TaskDao.getTaskDataById(downloadUrlTaskId)
        if (!dlTask.taskStatus.isCompleted()) {
            let errMsg = if (dlTask.message.trimAscii().size > 0) { dlTask.message } else { "Download task failed" }
            TaskModel.failTask(sourceDownloadTaskId, errMsg)
            fail(taskId, "Dependency download_url task not completed: ${errMsg}")
            return
        }

        let dlOutput = TaskIO.readOutput(downloadUrlTaskId)
        if (dlOutput.trimAscii().size == 0) {
            let errMsg = "Download task output is empty"
            TaskModel.failTask(sourceDownloadTaskId, errMsg)
            fail(taskId, errMsg)
            return
        }

        let scanTaskId = parseScanTaskId(dlOutput)
        if (scanTaskId <= 0) {
            let errMsg = "No scan task id found in download output"
            TaskModel.failTask(sourceDownloadTaskId, errMsg)
            fail(taskId, errMsg)
            return
        }

        TaskIO.appendLog(taskId, "waiting for scan_task_id=${scanTaskId}")
        TaskModel.updateTaskProgress(taskId, 40, "等待扫描任务完成")

        // Poll/wait for scan_archive to complete
        let scanResult = waitForTask(scanTaskId, 600, 1000)
        match (scanResult) {
            case Some(scanTask) =>
                if (!scanTask.taskStatus.isCompleted()) {
                    let errMsg = if (scanTask.message.trimAscii().size > 0) { scanTask.message } else { "Scan task failed" }
                    TaskModel.failTask(sourceDownloadTaskId, errMsg)
                    fail(taskId, "Scan task not completed: ${errMsg}")
                    return
                }

                let scanOutput = TaskIO.readOutput(scanTaskId)
                let archiveId = parseArchiveId(scanOutput)
                let tankoubonId = parseTankoubonId(scanOutput)

                if (archiveId.size == 0) {
                    let errMsg = "Scan task did not return archive_id"
                    TaskModel.failTask(sourceDownloadTaskId, errMsg)
                    fail(taskId, errMsg)
                    return
                }

                TaskIO.appendLog(taskId, "scan complete: archive_id=${archiveId}, tankoubon_id=${tankoubonId}")
                TaskModel.updateTaskProgress(taskId, 100, "扫描入库完成")

                // Write back source_download result respecting kind semantics.
                // archive -> archive_id; tankoubon -> tankoubon_id (only if scan returned a real one)
                // 不要将 archiveId 当作 tankoubon_id 回填，避免前端打开 /tankoubon?id=<archive_id> 导致 ID 空间不一致
                let isTankoubon = kind.trimAscii().toAsciiLower() == "tankoubon"
                let resultOut = ByteBuffer()
                let w = JsonWriter(resultOut)
                w.startObject()
                w.writeName("success").writeValue(1)
                w.writeName("kind").writeValue(kind)
                if (isTankoubon) {
                    if (tankoubonId.size > 0) {
                        w.writeName("tankoubon_id").writeValue(tankoubonId)
                    }
                    w.writeName("archive_id").writeValue(archiveId)
                } else {
                    w.writeName("archive_id").writeValue(archiveId)
                }
                w.writeName("download_url_task_id").writeValue(downloadUrlTaskId)
                w.writeName("scan_task_id").writeValue(scanTaskId)
                w.endObject()
                w.flush()
                let resultJson = String.fromUtf8(readToEnd(resultOut))

                let hasRealTankoubon = isTankoubon && tankoubonId.size > 0
                let effectiveTankoubonId = if (hasRealTankoubon) { tankoubonId } else { "" }
                let completionMsg = if (hasRealTankoubon) { "下载并入库完成 (tankoubon)" } else { "下载并入库完成" }
                TaskModel.updateTaskProgress(sourceDownloadTaskId, 100, completionMsg)
                TaskIO.writeOutput(sourceDownloadTaskId, resultJson)
                TaskModel.completeTask(sourceDownloadTaskId, resultJson)
                let logTankoubon = if (hasRealTankoubon) { " tankoubon_id=${tankoubonId}" } else { "" }
                TaskIO.appendLog(sourceDownloadTaskId, "source_download completed with archive_id=${archiveId}${logTankoubon} kind=${kind}")

                // Complete this callback task
                TaskModel.updateTaskProgress(taskId, 100, "回调完成")
                TaskModel.completeTask(taskId, "source_download_scan_callback completed")
                let cbOut = ByteBuffer()
                let cbW = JsonWriter(cbOut)
                cbW.startObject()
                cbW.writeName("success").writeValue(1)
                if (isTankoubon) {
                    cbW.writeName("tankoubon_id").writeValue(effectiveTankoubonId)
                    cbW.writeName("archive_id").writeValue(archiveId)
                } else {
                    cbW.writeName("archive_id").writeValue(archiveId)
                }
                cbW.writeName("kind").writeValue(kind)
                cbW.endObject()
                cbW.flush()
                TaskIO.writeOutput(taskId, String.fromUtf8(readToEnd(cbOut)))

                logger.debug("source_download_scan_callback completed", ("archive_id", archiveId), ("tankoubon_id", effectiveTankoubonId), ("kind", kind), ("source_download_task_id", sourceDownloadTaskId.toString()))
            case None =>
                let errMsg = "Scan task wait timed out"
                TaskModel.failTask(sourceDownloadTaskId, errMsg)
                fail(taskId, errMsg)
        }
    }

    private static func waitForTask(scanTaskId: Int64, maxAttempts: Int32, intervalMs: Int32): Option<TaskData> {
        for (attempt in 0..maxAttempts) {
            let task = TaskDao.getTaskDataById(scanTaskId)
            if (task.taskStatus.isCompleted() || task.taskStatus.isRetryable()) {
                return Some(task)
            }
            try {
                sleep(Duration.millisecond * Int64(intervalMs))
            } catch (_: Exception) {}
        }
        return None
    }

    private static func parseScanTaskId(output: String): Int64 {
        if (output.size == 0) { return 0 }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(output.rawData()) }
            let r = JsonReader(buf)

            func readBoolFlexible(): Bool {
                let v = r.readValue<String>().trimAscii().toAsciiLower()
                return v == "true" || v == "1"
            }

            var ok = false
            var scanTaskId: Int64 = 0

            if (r.peek() != Some(BeginObject)) { return 0 }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "success" => ok = readBoolFlexible()
                    case "data" =>
                        match (r.peek()) {
                            case Some(BeginObject) =>
                                r.startObject()
                                while (r.peek() != EndObject) {
                                    let fn = r.readName()
                                    match (fn) {
                                        case "task_id" =>
                                            let raw = r.readValue<String>().trimAscii()
                                            try { scanTaskId = Int64.parse(raw) } catch (_: Exception) { scanTaskId = 0 }
                                        case _ => r.skip()
                                    }
                                }
                                r.endObject()
                            case Some(_) => r.skip()
                            case None => ()
                        }
                    case "task_id" =>
                        let raw = r.readValue<String>().trimAscii()
                        try { scanTaskId = Int64.parse(raw) } catch (_: Exception) { scanTaskId = 0 }
                    case _ => r.skip()
                }
            }
            r.endObject()

            if (ok && scanTaskId > 0) { return scanTaskId }
        } catch (_: Exception) {}
        return 0
    }

    private static func parseArchiveId(output: String): String {
        if (output.size == 0) { return "" }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(output.rawData()) }
            let r = JsonReader(buf)

            func readBoolFlexible(): Bool {
                let v = r.readValue<String>().trimAscii().toAsciiLower()
                return v == "true" || v == "1"
            }

            var ok = false
            var archiveId = ""

            if (r.peek() != Some(BeginObject)) { return "" }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "success" => ok = readBoolFlexible()
                    case "archive_id" => archiveId = r.readValue<String>().trimAscii()
                    case _ => r.skip()
                }
            }
            r.endObject()

            if (ok && archiveId.size > 0) { return archiveId }
        } catch (_: Exception) {}
        return ""
    }

    private static func parseTankoubonId(output: String): String {
        if (output.size == 0) { return "" }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(output.rawData()) }
            let r = JsonReader(buf)

            func readBoolFlexible(): Bool {
                let v = r.readValue<String>().trimAscii().toAsciiLower()
                return v == "true" || v == "1"
            }

            var ok = false
            var tankoubonId = ""

            if (r.peek() != Some(BeginObject)) { return "" }
            r.startObject()
            while (r.peek() != EndObject) {
                let k = r.readName()
                match (k) {
                    case "success" => ok = readBoolFlexible()
                    case "tankoubon_id" => tankoubonId = r.readValue<String>().trimAscii()
                    case _ => r.skip()
                }
            }
            r.endObject()

            if (ok && tankoubonId.size > 0) { return tankoubonId }
        } catch (_: Exception) {}
        return ""
    }

    private static func parseParameters(parameters: String): (Int64, Int64, String) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return (0, 0, "")
        }

        var sourceDownloadTaskId: Int64 = 0
        var downloadUrlTaskId: Int64 = 0
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
                            case "sourceDownloadTaskId" => sourceDownloadTaskId = readInt64Flexible()
                            case "downloadUrlTaskId" => downloadUrlTaskId = readInt64Flexible()
                            case "kind" => kind = r.readValue<String>().trimAscii()
                            case _ => r.skip()
                        }
                    }
                    r.endObject()
                case _ => ()
            }
        } catch (_: Exception) {}

        return (sourceDownloadTaskId, downloadUrlTaskId, kind)
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }
}
