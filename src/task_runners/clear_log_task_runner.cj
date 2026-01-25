package lanlu.task_runners

import std.fs.*
import std.convert.*
import std.time.*
import std.collection.*
import stdx.log.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*
import lanlu.models.*
import lanlu.utils.*

/**
 * 清理日志任务：清理 ./data/logs 目录下过期的日志文件
 * 包括：
 * - data/logs/task/ 目录下的任务日志文件（.log 和 .out）
 * - data/logs/system.log 系统日志（可选轮转）
 */
public class ClearLogTaskRunner {

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("clear_log_task")
        TaskIO.appendLog(taskId, "clear_log task started")

        try {
            // 解析参数
            let (maxAgeDays, dryRun, cleanSystemLog) = parseParameters(parameters)
            let maxAgeSeconds = maxAgeDays * 24 * 60 * 60

            TaskIO.appendLog(taskId, "Starting log cleanup with maxAgeDays=${maxAgeDays}, dryRun=${dryRun}, cleanSystemLog=${cleanSystemLog}")

            // 更新进度：开始扫描
            TaskModel.updateTaskProgress(taskId, 10, "Starting log cleanup")

            // 准备结果统计
            var totalDeletedCount: Int64 = 0
            var totalDeletedSize: Int64 = 0
            var totalSkippedCount: Int64 = 0
            var errors = ArrayList<String>()

            // 清理任务日志目录
            TaskIO.appendLog(taskId, "Cleaning task logs directory...")
            TaskModel.updateTaskProgress(taskId, 30, "Cleaning task logs")
            let taskLogResult = cleanTaskLogs("data/logs/task", maxAgeSeconds, dryRun)
            totalDeletedCount += taskLogResult.deletedCount
            totalDeletedSize += taskLogResult.deletedSize
            totalSkippedCount += taskLogResult.skippedCount
            for (error in taskLogResult.errors) {
                errors.add(error)
            }

            // 可选：清理系统日志
            if (cleanSystemLog) {
                TaskIO.appendLog(taskId, "Cleaning system log...")
                TaskModel.updateTaskProgress(taskId, 70, "Cleaning system log")
                let sysLogResult = cleanSystemLogFile("data/logs/system.log", maxAgeSeconds, dryRun)
                totalDeletedCount += sysLogResult.deletedCount
                totalDeletedSize += sysLogResult.deletedSize
                totalSkippedCount += sysLogResult.skippedCount
                for (error in sysLogResult.errors) {
                    errors.add(error)
                }
            }

            // 更新进度：完成
            TaskModel.updateTaskProgress(taskId, 100, "Log cleanup completed")

            // 准备输出结果
            let deletedSizeMB = totalDeletedSize / (1024 * 1024)
            let deletedSizeKB = totalDeletedSize / 1024
            let sizeStr = if (deletedSizeMB > 0) { "${deletedSizeMB}MB" } else { "${deletedSizeKB}KB" }
            let successJson = "{\"success\":1,\"deleted_count\":${totalDeletedCount},\"deleted_size_kb\":${deletedSizeKB},\"skipped_count\":${totalSkippedCount},\"errors\":${errorsToJson(errors)}}"

            TaskIO.appendLog(taskId, "Log cleanup completed: deleted=${totalDeletedCount} files, size=${sizeStr}, skipped=${totalSkippedCount}")
            if (errors.size > 0) {
                TaskIO.appendLog(taskId, "Errors encountered: ${errors.size}")
            }

            TaskModel.completeTask(taskId, successJson)
            TaskIO.writeOutput(taskId, successJson)
            TaskIO.appendLog(taskId, "Task completed and output written")
        } catch (e: Exception) {
            let errorMsg = "Unexpected error: ${e.message}"
            logger.error(errorMsg, ("exception", e.message), ("stack", e.toString()))
            TaskIO.appendLog(taskId, "FATAL ERROR: ${errorMsg}")
            TaskIO.appendLog(taskId, "Stack trace: ${e.toString()}")
            fail(taskId, errorMsg)
        }
    }

    /**
     * 解析任务参数
     * 支持格式：
     * - "7" (仅设置 maxAgeDays)
     * - "maxAgeDays:7"
     * - JSON: {"maxAgeDays":7,"dryRun":true,"cleanSystemLog":false}
     */
    private static func parseParameters(parameters: String): (Int64, Bool, Bool) {
        var maxAgeDays: Int64 = 7      // 默认7天
        var dryRun: Bool = false       // 默认执行清理
        var cleanSystemLog: Bool = false  // 默认不清理系统日志

        if (parameters.size > 0) {
            try {
                let trimmed = parameters.trimAscii()

                // 尝试解析JSON格式参数
                if (trimmed[0] == 123) {  // '{'
                    // 解析 maxAgeDays
                    maxAgeDays = parseJsonInt(trimmed, "maxAgeDays", 7)
                    // 解析 dryRun
                    dryRun = parseJsonBool(trimmed, "dryRun", false)
                    // 解析 cleanSystemLog
                    cleanSystemLog = parseJsonBool(trimmed, "cleanSystemLog", false)
                } else {
                    // 简单格式参数："7" 或 "maxAgeDays:7"
                    let parts = trimmed.split(":")
                    if (parts.size == 2) {
                        let numPart = parts[1].trimAscii()
                        if (numPart.size > 0) {
                            maxAgeDays = Int64.parse(numPart)
                        }
                    } else if (parts.size == 1) {
                        maxAgeDays = Int64.parse(trimmed)
                    }
                }
            } catch (_: Exception) {
                // 解析失败，使用默认值
                maxAgeDays = 7
                dryRun = false
                cleanSystemLog = false
            }
        }

        return (maxAgeDays, dryRun, cleanSystemLog)
    }

    /**
     * 从JSON字符串中解析整数值
     */
    private static func parseJsonInt(json: String, key: String, defaultValue: Int64): Int64 {
        let keyPattern = "\"${key}\""
        let keyOpt = json.indexOf(keyPattern)
        let keyIdx: Int64 = match (keyOpt) {
            case Some(idx) => idx
            case None => -1
        }
        if (keyIdx < 0) {
            return defaultValue
        }

        let colonOpt = json.indexOf(":", keyIdx)
        let colonIdx: Int64 = match (colonOpt) {
            case Some(idx) => idx
            case None => -1
        }
        if (colonIdx < 0) {
            return defaultValue
        }

        var numStart = colonIdx + 1
        while (numStart < json.size && (json[numStart] == 32 || json[numStart] == 9 || json[numStart] == 34)) {
            numStart++
        }

        var numStr = ""
        for (i in numStart..json.size) {
            let c = json[i]
            if (c >= 48 && c <= 57) {  // '0'-'9'
                numStr += Rune(UInt32(c)).toString()
            } else {
                break
            }
        }

        if (numStr.size > 0) {
            return Int64.parse(numStr)
        }
        return defaultValue
    }

    /**
     * 从JSON字符串中解析布尔值
     */
    private static func parseJsonBool(json: String, key: String, defaultValue: Bool): Bool {
        let keyPattern = "\"${key}\""
        let keyOpt = json.indexOf(keyPattern)
        let keyIdx: Int64 = match (keyOpt) {
            case Some(idx) => idx
            case None => -1
        }
        if (keyIdx < 0) {
            return defaultValue
        }

        let colonOpt = json.indexOf(":", keyIdx)
        let colonIdx: Int64 = match (colonOpt) {
            case Some(idx) => idx
            case None => -1
        }
        if (colonIdx < 0) {
            return defaultValue
        }

        var valStart = colonIdx + 1
        while (valStart < json.size && (json[valStart] == 32 || json[valStart] == 9)) {
            valStart++
        }

        if (valStart < json.size) {
            return json[valStart] == 116  // 't' 的ASCII码
        }
        return defaultValue
    }

    /**
     * 清理任务日志目录
     */
    private static func cleanTaskLogs(dirPath: String, maxAgeSeconds: Int64, dryRun: Bool): LogCleanResult {
        var result = LogCleanResult()

        if (!directoryExists(dirPath)) {
            return result
        }

        try {
            let currentTime = DateTime.now().toUnixTimeStamp().toSeconds()
            let entries = listDirectory(dirPath)

            for (entry in entries) {
                // 只处理 .log 和 .out 文件
                if (!entry.endsWith(".log") && !entry.endsWith(".out")) {
                    continue
                }

                let fullPath = joinPath(dirPath, entry)

                try {
                    let fileInfo = FileInfo(Path(fullPath))
                    if (fileInfo.isDirectory()) {
                        continue
                    }

                    let lastModified = fileInfo.lastModificationTime.toUnixTimeStamp().toSeconds()
                    let ageSeconds = currentTime - lastModified

                    if (ageSeconds > maxAgeSeconds) {
                        let size = fileInfo.size

                        if (dryRun) {
                            result.skippedCount += 1
                        } else {
                            if (removeFile(fullPath)) {
                                result.deletedCount += 1
                                result.deletedSize += size
                            } else {
                                result.errors.add("Failed to remove file: ${fullPath}")
                            }
                        }
                    }
                } catch (e: Exception) {
                    result.errors.add("Error processing ${fullPath}: ${e.message}")
                }
            }
        } catch (e: Exception) {
            result.errors.add("Error accessing directory ${dirPath}: ${e.message}")
        }

        return result
    }

    /**
     * 清理系统日志（如果超过指定天数则删除）
     */
    private static func cleanSystemLogFile(logPath: String, maxAgeSeconds: Int64, dryRun: Bool): LogCleanResult {
        var result = LogCleanResult()

        try {
            // 检查文件是否存在
            if (!fileExists(logPath)) {
                return result
            }

            let fileInfo = FileInfo(Path(logPath))

            let currentTime = DateTime.now().toUnixTimeStamp().toSeconds()
            let lastModified = fileInfo.lastModificationTime.toUnixTimeStamp().toSeconds()
            let ageSeconds = currentTime - lastModified

            // 系统日志只有在超过指定天数时才清理
            if (ageSeconds > maxAgeSeconds) {
                let size = fileInfo.size

                if (dryRun) {
                    result.skippedCount += 1
                } else {
                    if (removeFile(logPath)) {
                        result.deletedCount += 1
                        result.deletedSize += size
                    } else {
                        result.errors.add("Failed to remove system log: ${logPath}")
                    }
                }
            }
        } catch (e: Exception) {
            result.errors.add("Error processing system log: ${e.message}")
        }

        return result
    }

    private static func removeFile(path: String): Bool {
        try {
            remove(Path(path))
            return true
        } catch (_: Exception) {
            return false
        }
    }

    private static func fileExists(path: String): Bool {
        return DirectoryScanner.fileExists(path)
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }

    private static func directoryExists(path: String): Bool {
        return DirectoryScanner.directoryExists(path)
    }

    private static func listDirectory(path: String): Array<String> {
        return DirectoryScanner.listDirectory(path)
    }

    private static func joinPath(base: String, part: String): String {
        return DirectoryScanner.joinPath(base, part)
    }

    private static func errorsToJson(errors: ArrayList<String>): String {
        if (errors.size == 0) {
            return "[]"
        }
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startArray()
        for (e in errors) {
            w.writeValue(e)
        }
        w.endArray()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }
}

/**
 * 日志清理结果统计
 */
class LogCleanResult {
    public var deletedCount: Int64
    public var deletedSize: Int64
    public var skippedCount: Int64
    public var errors: ArrayList<String>

    public init() {
        this.deletedCount = 0
        this.deletedSize = 0
        this.skippedCount = 0
        this.errors = ArrayList<String>()
    }
}
