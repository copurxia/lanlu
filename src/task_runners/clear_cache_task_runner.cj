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
 * 清理缓存任务：清理 ./data/cache 目录下长时间未访问的缓存文件
 * 根据文件的 lastModificationTime 判断是否为"过期"缓存，清理长时间未读写的文件
 */
public class ClearCacheTaskRunner {

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let logger = getLogger("clear_cache_task")
        TaskIO.appendLog(taskId, "clear_cache task started")

        try {
            // 解析参数
            let (maxAgeDays, dryRun) = parseParameters(parameters)
            let maxAgeSeconds = maxAgeDays * 24 * 60 * 60

            TaskIO.appendLog(taskId, "Starting cache cleanup with maxAgeDays=${maxAgeDays}, dryRun=${dryRun}")

            // 更新进度：开始扫描
            TaskModel.updateTaskProgress(taskId, 10, "Starting cache cleanup")

            // 准备结果统计
            var totalDeletedCount: Int64 = 0
            var totalDeletedSize: Int64 = 0
            var totalSkippedCount: Int64 = 0
            var errors = ArrayList<String>()

            // 清理整个 cache 目录
            TaskIO.appendLog(taskId, "Cleaning cache directory...")
            TaskModel.updateTaskProgress(taskId, 30, "Cleaning cache")
            let cacheResult = cleanDirectory("data/cache", maxAgeSeconds, dryRun)
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
            let successJson = "{\"success\":1,\"deleted_count\":${totalDeletedCount},\"deleted_size_mb\":${deletedSizeMB},\"skipped_count\":${totalSkippedCount},\"errors\":${errorsToJson(errors)}}"

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
            fail(taskId, errorMsg)
        }
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
     * 清理指定目录下的过期文件（递归）
     */
    private static func cleanDirectory(dirPath: String, maxAgeSeconds: Int64, dryRun: Bool): CleanResult {
        let logger = getLogger("clear_cache")
        var result = CleanResult()

        if (!directoryExists(dirPath)) {
            return result
        }

        try {
            let currentTime = DateTime.now().toUnixTimeStamp().toSeconds()

            // 递归清理过期文件
            cleanFilesRecursive(dirPath, currentTime, maxAgeSeconds, dryRun, result)

            // 清理空目录（但保留根目录）
            removeEmptyDirectories(dirPath, dirPath, result)
        } catch (e: Exception) {
            result.errors.add("Error accessing directory ${dirPath}: ${e.message}")
        }

        return result
    }

    /**
     * 递归清理过期文件
     */
    private static func cleanFilesRecursive(
        dirPath: String,
        currentTime: Int64,
        maxAgeSeconds: Int64,
        dryRun: Bool,
        result: CleanResult
    ): Unit {
        try {
            let entries = listDirectory(dirPath)

            for (entry in entries) {
                let fullPath = joinPath(dirPath, entry)

                try {
                    let fileInfo = FileInfo(Path(fullPath))

                    if (fileInfo.isDirectory()) {
                        // 递归处理子目录
                        cleanFilesRecursive(fullPath, currentTime, maxAgeSeconds, dryRun, result)
                    } else {
                        // 检查文件是否过期
                        let lastModified = getLastModifiedTime(fullPath)
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
                    }
                } catch (e: Exception) {
                    result.errors.add("Error processing ${fullPath}: ${e.message}")
                }
            }
        } catch (e: Exception) {
            result.errors.add("Error listing directory ${dirPath}: ${e.message}")
        }
    }

    /**
     * 递归删除空目录（从叶子向上）
     */
    private static func removeEmptyDirectories(dirPath: String, rootPath: String, result: CleanResult): Bool {
        try {
            let entries = listDirectory(dirPath)

            // 先递归处理子目录
            for (entry in entries) {
                let fullPath = joinPath(dirPath, entry)
                let fileInfo = FileInfo(Path(fullPath))

                if (fileInfo.isDirectory()) {
                    removeEmptyDirectories(fullPath, rootPath, result)
                }
            }

            // 重新检查当前目录是否为空
            let currentEntries = listDirectory(dirPath)
            if (currentEntries.size == 0 && dirPath != rootPath) {
                // 目录为空且不是根目录，删除它
                try {
                    remove(Path(dirPath))
                    return true
                } catch (_: Exception) {
                    result.errors.add("Failed to remove empty directory: ${dirPath}")
                }
            }
        } catch (e: Exception) {
            result.errors.add("Error checking directory ${dirPath}: ${e.message}")
        }
        return false
    }

    /**
     * 删除单个文件
     */
    private static func removeFile(path: String): Bool {
        try {
            remove(Path(path))
            return true
        } catch (_: Exception) {
            return false
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
            let entries = listDirectory(dirPath)
            for (entry in entries) {
                let fullPath = joinPath(dirPath, entry)
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

    /**
     * 删除文件或目录（递归删除目录）
     */
    private static func removeFileOrDirectory(path: String): Bool {
        try {
            let fileInfo = FileInfo(Path(path))
            if (fileInfo.isDirectory()) {
                // 目录：先删除目录内容，再删除目录本身
                let entries = listDirectory(path)
                for (entry in entries) {
                    let fullPath = joinPath(path, entry)
                    if (!removeFileOrDirectory(fullPath)) {
                        return false
                    }
                }
                // 删除空目录
                remove(Path(path))
            } else {
                // 文件：直接删除
                remove(Path(path))
            }
            return true
        } catch (_: Exception) {
            return false
        }
    }

    private static func fail(taskId: Int64, message: String): Unit {
        let msg = if (message.size == 0) { "Unknown error" } else { message }
        TaskIO.appendLog(taskId, "FAILED: ${msg}")
        TaskModel.failTask(taskId, msg)
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("success").writeValue(0)
        w.writeName("error").writeValue(msg)
        w.endObject()
        w.flush()
        TaskIO.writeOutput(taskId, String.fromUtf8(readToEnd(out)))
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
 * 清理结果统计
 */
class CleanResult {
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
