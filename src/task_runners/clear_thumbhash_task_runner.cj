package lrr4cj.task_runners

import stdx.log.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*

/**
 * 清理所有 Archive 的 thumbhash 字段任务
 */
public class ClearThumbhashTaskRunner {

    public static func run(taskId: Int64, _: String, _: TaskRunnerContext): Unit {
        let logger = getLogger("clear_thumbhash_task")
        TaskIO.appendLog(taskId, "clear_thumbhash task started")

        try {
            TaskModel.updateTaskProgress(taskId, 10, "Starting to clear all thumbhash fields")
            TaskIO.appendLog(taskId, "Starting to clear all thumbhash fields...")

            let result = clearAllThumbhash()
            if (!result.success) {
                let errorMsg = "clear_thumbhash failed: ${result.error}"
                logger.error(errorMsg, ("error", result.error))
                TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                fail(taskId, result.error)
                return
            }

            let successJson = "{\"success\":1,\"cleared_count\":${result.clearedCount}}"
            TaskModel.updateTaskProgress(taskId, 100, "Thumbhash clearing completed")
            TaskIO.appendLog(taskId, "Thumbhash clearing completed successfully: cleared=${result.clearedCount}")
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
     * 清理所有 Archive 的 thumbhash 字段
     */
    private static func clearAllThumbhash(): ClearThumbhashResultData {
        try {
            let logger = getLogger("clear_thumbhash")

            logger.debug("Clearing all thumbhash fields...")
            let clearedCount = ArchiveDao.clearAllThumbhash()

            if (clearedCount < 0) {
                return ClearThumbhashResultData(false, 0, "Failed to clear thumbhash fields")
            }

            logger.debug("Successfully cleared thumbhash for ${clearedCount} archives")
            return ClearThumbhashResultData(true, clearedCount, "")
        } catch (e: Exception) {
            let logger = getLogger("clear_thumbhash")
            logger.error("Clear thumbhash failed with exception", ("error", e.message))
            return ClearThumbhashResultData(false, 0, e.message)
        }
    }

    private static func fail(taskId: Int64, message: String): Unit {
        let msg = if (message.size == 0) { "Unknown error" } else { message }
        TaskIO.appendLog(taskId, "FAILED: ${msg}")
        TaskModel.failTask(taskId, msg)
        TaskIO.writeOutput(taskId, "{\"success\":0,\"error\":\"${escapeJson(msg)}\"}")
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
}

/**
 * 清理 thumbhash 结果数据
 */
class ClearThumbhashResultData {
    public var success: Bool
    public var clearedCount: Int64
    public var error: String

    public init(success: Bool, clearedCount: Int64, error: String) {
        this.success = success
        this.clearedCount = clearedCount
        this.error = error
    }
}
