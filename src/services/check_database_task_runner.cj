package lrr4cj.services

import stdx.log.*
import std.fs.*
import std.sync.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*

/**
 * 数据库一致性检查任务：检查数据库记录与实际文件的匹配情况，清理孤儿记录
 */
public class CheckDatabaseTaskRunner {
    // 归档路径配置
    private static var archivePath: Path = Path("")
    private static var initialized: Bool = false
    private static let initMutex: Mutex = Mutex()

    // 私有初始化方法（懒加载）
    private static func ensureInitialized(): Unit {
        initMutex.lock()
        if (!initialized) {
            try {
                // 从数据库读取配置
                let archivePathStr = SystemSettingsService.getPath("ARCHIVE_PATH")

                // 先确保目录存在，然后规范化路径
                // 注意：canonicalize() 要求路径存在，否则会失败
                let tempPath = Path(archivePathStr)
                FileUtils.ensureDirectoryExists(tempPath)
                archivePath = canonicalize(archivePathStr)

                initialized = true
            } catch (e: Exception) {
                // 即使初始化失败，也设置为 true 避免死锁
                initialized = true
                throw e
            }
        }
        initMutex.unlock()
    }

    public static func run(taskId: Int64, _: String): Unit {
        let logger = getLogger("check_database_task")
        TaskIO.appendLog(taskId, "check_database task started")

        try {
            // 先记录从配置获取的路径
            let archivePathStr = SystemSettingsService.getPath("ARCHIVE_PATH")
            TaskIO.appendLog(taskId, "Archive path from config: ${archivePathStr}")

            // 确保配置已初始化
            TaskIO.appendLog(taskId, "Initializing configuration...")
            ensureInitialized()
            TaskIO.appendLog(taskId, "Configuration initialized successfully, archivePath=${archivePath.toString()}")

            TaskModel.updateTaskProgress(taskId, 10, "Starting database consistency check")
            TaskIO.appendLog(taskId, "Starting database consistency check...")

            let result = checkDatabaseFiles()
            if (!result.success) {
                let errorMsg = "check_database failed: ${result.error}"
                logger.error(errorMsg, ("error", result.error))
                TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                fail(taskId, result.error)
                return
            }

            let successJson = "{\"success\":1,\"deleted_count\":${result.deletedCount},\"checked_count\":${result.checkedCount}}"
            TaskModel.updateTaskProgress(taskId, 100, "Database check completed")
            TaskIO.appendLog(taskId, "Database check completed successfully: checked=${result.checkedCount}, deleted=${result.deletedCount}")
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
     * 检查数据库中的文件是否仍然存在
     */
    private static func checkDatabaseFiles(): CheckResultData {
        try {
            let logger = getLogger("check_database")

            logger.info("Fetching all archives from database...")
            let archives = ArchiveDao.getAllArchives()
            logger.info("Retrieved ${archives.size} archives from database")

            var deletedCount: Int64 = 0
            let checkedCount = archives.size

            if (archives.size == 0) {
                logger.info("No archives found in database, nothing to check")
                return CheckResultData(true, 0, 0, "")
            }

            logger.info("Starting file existence check for ${checkedCount} archives")

            var processed = 0
            for (archive in archives) {
                processed++
                // 正确构建完整路径：archivePath + relativePath + filename
                let archiveBasePath = archivePath.toString()
                let fullFilePath: String

                if (archive.relative_path.size > 0 && archive.relative_path != "") {
                    // 如果有相对路径，构建：archivePath/relativePath/filename
                    let dirPath = joinPath(archiveBasePath, archive.relative_path)
                    fullFilePath = joinPath(dirPath, archive.filename)
                } else {
                    // 如果没有相对路径，构建：archivePath/filename
                    fullFilePath = joinPath(archiveBasePath, archive.filename)
                }

                logger.debug("Checking file ${processed}/${checkedCount}", ("file", fullFilePath))

                // 检查文件是否存在（支持软链接）
                if (!fileExists(fullFilePath)) {
                    logger.warn("File not found, will delete from database", ("file", fullFilePath), ("archive_id", archive.id.toString()))
                    if (ArchiveDao.delete(archive.id)) {
                        deletedCount++
                        logger.info("Successfully deleted database record", ("id", archive.id.toString()), ("title", archive.title))
                    } else {
                        logger.error("Failed to delete database record", ("id", archive.id.toString()), ("title", archive.title))
                    }
                } else {
                    logger.debug("File exists, skipping", ("file", fullFilePath))
                }

                // 每处理100个文件输出一次进度
                if (processed % 100 == 0 || processed == checkedCount) {
                    logger.info("Progress: ${processed}/${checkedCount} files checked, ${deletedCount} deletions so far")
                }
            }

            if (deletedCount > 0) {
                logger.info("Database check completed with deletions", ("deleted_count", deletedCount.toString()), ("checked_count", checkedCount.toString()))
            } else {
                logger.info("Database check completed successfully - all ${checkedCount} files exist", ("checked_count", checkedCount.toString()))
            }

            return CheckResultData(true, deletedCount, checkedCount, "")
        } catch (e: Exception) {
            let logger = getLogger("check_database")
            logger.error("Database check failed with exception", ("error", e.message), ("stack", e.toString()))
            return CheckResultData(false, 0, 0, e.message)
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

    /**
     * 检查文件是否存在（支持软链接）
     */
    private static func fileExists(path: String): Bool {
        return DirectoryScanner.fileExists(path)
    }

    /**
     * 拼接路径
     */
    private static func joinPath(base: String, part: String): String {
        return DirectoryScanner.joinPath(base, part)
    }
}
