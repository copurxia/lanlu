package lanlu.contexts.task.application.runners

import std.fs.*
import std.convert.*
import std.time.*
import std.collection.*
import stdx.log.*
import lanlu.contexts.task.domain.*
import lanlu.shared.utils.*

/**
 * 清理缓存任务：清理缓存根目录下的过期缓存单元
 * 根目录散文件按文件清理，一级子目录按目录整体清理
 */
public class ClearCacheTaskRunner {

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("clear_cache_task")
        TaskIO.appendLog(taskId, "clear_cache task started")

        try {
            // 解析参数
            let (maxAgeDays, dryRun) = parseParameters(parameters)
            let maxAgeSeconds = maxAgeDays * 24 * 60 * 60
            let cacheRoot = resolveCacheRoot(context)

            TaskIO.appendLog(taskId, "Starting cache cleanup with maxAgeDays=${maxAgeDays}, dryRun=${dryRun}, cacheRoot=${cacheRoot}")

            // 更新进度：开始扫描
            TaskModel.updateTaskProgress(taskId, 10, "Starting cache cleanup")

            // 准备结果统计
            var totalDeletedCount: Int64 = 0
            var totalDeletedSize: Int64 = 0
            var totalSkippedCount: Int64 = 0
            var errors = ArrayList<String>()

            // 清理 cache 根目录下的缓存单元
            TaskIO.appendLog(taskId, "Cleaning cache units under ${cacheRoot}...")
            TaskModel.updateTaskProgress(taskId, 30, "Cleaning cache")
            let cacheResult = cleanDirectory(cacheRoot, maxAgeSeconds, dryRun, taskId)
            totalDeletedCount += cacheResult.deletedCount
            totalDeletedSize += cacheResult.deletedSize
            totalSkippedCount += cacheResult.skippedCount
            for (error in cacheResult.errors) {
                errors.add(error)
            }

            // 更新进度：完成
            TaskModel.updateTaskProgress(taskId, 100, "Cache cleanup completed")

            // 准备输出结果
            let deletedSizeMB = totalDeletedSize / (1024 * 1024)
            let successJson = "{\"success\":1,\"deleted_count\":${totalDeletedCount},\"deleted_size_mb\":${deletedSizeMB},\"skipped_count\":${totalSkippedCount},\"errors\":${TaskRunnerUtils.errorsToJson(errors)}}"

            TaskIO.appendLog(taskId, "Cache cleanup completed: deleted=${totalDeletedCount} items, size=${deletedSizeMB}MB, skipped=${totalSkippedCount}")
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
            TaskRunnerUtils.fail(taskId, errorMsg)
        }
    }

    private static func resolveCacheRoot(context: TaskRunnerContext): String {
        let cachePath = context.paths.cachePath.trimAscii()
        if (cachePath.size > 0) {
            return cachePath
        }
        return "data/cache"
    }

    /**
     * 解析任务参数
     * 支持格式：
     * - "7" (仅设置 maxAgeDays)
     * - "maxAgeDays:7"
     * - JSON: {"maxAgeDays":7,"dryRun":true}
     */
    private static func parseParameters(parameters: String): (Int64, Bool) {
        var maxAgeDays: Int64 = 7  // 默认7天
        var dryRun: Bool = false   // 默认执行清理

        if (parameters.size > 0) {
            try {
                let trimmed = parameters.trimAscii()

                // 尝试解析JSON格式参数
                if (trimmed[0] == 123) {  // '{'
                    // JSON格式参数 - 查找 maxAgeDays
                    let maxAgeKeyOpt = trimmed.indexOf("\"maxAgeDays\"")
                    let keyIdx: Int64 = match (maxAgeKeyOpt) {
                        case Some(idx) => idx
                        case None => -1
                    }
                    if (keyIdx >= 0) {
                        let colonOpt = trimmed.indexOf(":", keyIdx)
                        let colonIdx: Int64 = match (colonOpt) {
                            case Some(idx) => idx
                            case None => -1
                        }
                        if (colonIdx >= 0) {
                            // 查找冒号后的数字
                            var numStart = colonIdx + 1
                            while (numStart < trimmed.size && (trimmed[numStart] == 32 || trimmed[numStart] == 9 || trimmed[numStart] == 34)) {
                                numStart++
                            }
                            // 手动构建数字字符串
                            var numStr = ""
                            for (i in numStart..trimmed.size) {
                                let c = trimmed[i]
                                if (c >= 48 && c <= 57) {  // '0'-'9'
                                    numStr += Rune(UInt32(c)).toString()
                                } else {
                                    break
                                }
                            }
                            if (numStr.size > 0) {
                                maxAgeDays = Int64.parse(numStr)
                            }
                        }
                    }

                    // 查找 dryRun
                    let dryRunKeyOpt = trimmed.indexOf("\"dryRun\"")
                    let dryKeyIdx: Int64 = match (dryRunKeyOpt) {
                        case Some(idx) => idx
                        case None => -1
                    }
                    if (dryKeyIdx >= 0) {
                        let colonOpt = trimmed.indexOf(":", dryKeyIdx)
                        let colonIdx: Int64 = match (colonOpt) {
                            case Some(idx) => idx
                            case None => -1
                        }
                        if (colonIdx >= 0) {
                            // 查找冒号后的值
                            var valStart = colonIdx + 1
                            while (valStart < trimmed.size && (trimmed[valStart] == 32 || trimmed[valStart] == 9)) {
                                valStart++
                            }
                            if (valStart < trimmed.size) {
                                dryRun = if (trimmed[valStart] == 116) { true } else { false }  // 't' 的ASCII码
                            }
                        }
                    }
                } else {
                    // 简单格式参数："7" 或 "maxAgeDays:7"
                    let parts = trimmed.split(":")
                    if (parts.size == 2) {
                        // 格式：maxAgeDays:7
                        let numPart = parts[1].trimAscii()
                        if (numPart.size > 0) {
                            maxAgeDays = Int64.parse(numPart)
                        }
                    } else if (parts.size == 1) {
                        // 格式：7
                        maxAgeDays = Int64.parse(trimmed)
                    }
                }
            } catch (_: Exception) {
                // 解析失败，使用默认值
                maxAgeDays = 7
                dryRun = false
            }
        }

        return (maxAgeDays, dryRun)
    }

    /**
     * 清理缓存根目录下的过期缓存单元：
     * - 根目录散文件按文件清理
     * - 一级子目录按目录整体清理
     */
    private static func cleanDirectory(dirPath: String, maxAgeSeconds: Int64, dryRun: Bool, taskId: Int64): CleanResult {
        var result = CleanResult()

        if (!TaskRunnerUtils.directoryExists(dirPath)) {
            return result
        }

        try {
            let currentTime = DateTime.now().toUnixTimeStamp().toSeconds()
            let entries = TaskRunnerUtils.listDirectory(dirPath)

            for (entry in entries) {
                let fullPath = TaskRunnerUtils.joinPath(dirPath, entry)

                try {
                    let fileInfo = FileInfo(Path(fullPath))
                    if (fileInfo.isDirectory()) {
                        cleanDirectoryUnit(fullPath, currentTime, maxAgeSeconds, dryRun, result, taskId)
                    } else {
                        cleanFileUnit(fullPath, fileInfo.size, currentTime, maxAgeSeconds, dryRun, result, taskId)
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

    private static func cleanFileUnit(
        filePath: String,
        fileSize: Int64,
        currentTime: Int64,
        maxAgeSeconds: Int64,
        dryRun: Bool,
        result: CleanResult,
        taskId: Int64
    ): Unit {
        let ageSeconds = currentTime - getLastModifiedTime(filePath)
        if (ageSeconds <= maxAgeSeconds) {
            return
        }

        if (dryRun) {
            result.skippedCount += 1
            TaskIO.appendLog(taskId, "Would remove cache file: ${filePath}")
            return
        }

        if (TaskRunnerUtils.removeFile(filePath)) {
            result.deletedCount += 1
            result.deletedSize += fileSize
            TaskIO.appendLog(taskId, "Removed cache file: ${filePath}")
        } else {
            result.errors.add("Failed to remove file: ${filePath}")
        }
    }

    private static func cleanDirectoryUnit(
        dirPath: String,
        currentTime: Int64,
        maxAgeSeconds: Int64,
        dryRun: Bool,
        result: CleanResult,
        taskId: Int64
    ): Unit {
        let ageSeconds = currentTime - getLastModifiedTime(dirPath)
        if (ageSeconds <= maxAgeSeconds) {
            return
        }

        let dirSize = calculateDirectorySize(dirPath)
        if (dryRun) {
            result.skippedCount += 1
            TaskIO.appendLog(taskId, "Would remove cache directory: ${dirPath}")
            return
        }

        if (FileUtils.removeFileOrDirectory(dirPath)) {
            result.deletedCount += 1
            result.deletedSize += dirSize
            TaskIO.appendLog(taskId, "Removed cache directory: ${dirPath}")
        } else {
            result.errors.add("Failed to remove directory: ${dirPath}")
        }
    }

    /**
     * 获取文件或目录的最后修改时间（Unix时间戳，秒）
     */
    private static func getLastModifiedTime(path: String): Int64 {
        let fileInfo = FileInfo(Path(path))
        return fileInfo.lastModificationTime.toUnixTimeStamp().toSeconds()
    }

    /**
     * 递归计算目录大小
     */
    private static func calculateDirectorySize(dirPath: String): Int64 {
        var totalSize: Int64 = 0
        try {
            let entries = TaskRunnerUtils.listDirectory(dirPath)
            for (entry in entries) {
                let fullPath = TaskRunnerUtils.joinPath(dirPath, entry)
                let fileInfo = FileInfo(Path(fullPath))
                if (fileInfo.isDirectory()) {
                    totalSize += calculateDirectorySize(fullPath)
                } else {
                    totalSize += fileInfo.size
                }
            }
        } catch (_: Exception) {
            // 忽略计算大小时的错误
        }
        return totalSize
    }

    // Shared helpers live in TaskRunnerUtils.
}
