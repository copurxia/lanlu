package lrr4cj.services

import stdx.log.*
import std.fs.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*
import dotenv.Dotenv

/**
 * 数据库一致性检查任务：检查数据库记录与实际文件的匹配情况，清理孤儿记录
 */
public class CheckDatabaseTaskRunner {
    // 归档路径配置
    private static var archivePath: Path

    // 静态初始化器
    static init() {
        let config = Dotenv.createConfig()
        let archivePathStr = config.read("ARCHIVE_PATH", "./data/archive")
        archivePath = canonicalize(archivePathStr)
        FileUtils.ensureDirectoryExists(archivePath)
    }

    public static func run(taskId: Int64, _: String): Unit {
        let logger = getLogger("check_database_task")
        TaskIO.appendLog(taskId, "check_database task started")

        MinionModel.updateTaskProgress(taskId, 10, "Starting database consistency check")

        let result = checkDatabaseFiles()
        if (!result.success) {
            logger.error("check_database failed", ("error", result.error))
            fail(taskId, result.error)
            return
        }

        let successJson = "{\"success\":1,\"deleted_count\":${result.deletedCount},\"checked_count\":${result.checkedCount}}"
        MinionModel.updateTaskProgress(taskId, 100, "Database check completed")
        MinionModel.completeTask(taskId, successJson)
        TaskIO.writeOutput(taskId, successJson)
        TaskIO.appendLog(taskId, "check_database completed: checked=${result.checkedCount}, deleted=${result.deletedCount}")
    }

    /**
     * 检查数据库中的文件是否仍然存在
     */
    private static func checkDatabaseFiles(): CheckResultData {
        try {
            let archives = ArchiveDao.getAllArchives()
            var deletedCount: Int64 = 0
            let checkedCount = archives.size

            let logger = getLogger("check_database")
            logger.info("Starting database file check", ("count", archives.size.toString()))

            for (archive in archives) {
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

                logger.debug("Checking file", ("file", fullFilePath))

                // 检查文件是否存在（支持软链接）
                if (!fileExists(fullFilePath)) {
                    logger.warn("File not found, deleting from database", ("file", fullFilePath))
                    if (ArchiveDao.delete(archive.id)) {
                        deletedCount++
                        logger.info("Deleted database record", ("id", archive.id.toString()), ("title", archive.title))
                    } else {
                        logger.error("Failed to delete database record", ("id", archive.id.toString()), ("title", archive.title))
                    }
                } else {
                    logger.debug("File exists", ("file", fullFilePath))
                }
            }

            if (deletedCount > 0) {
                logger.info("Database check completed with deletions", ("deleted_count", deletedCount.toString()))
            } else {
                logger.info("Database check completed, all files exist")
            }

            return CheckResultData(true, deletedCount, checkedCount, "")
        } catch (e: Exception) {
            let logger = getLogger("check_database")
            logger.error("Database check failed", ("error", e.message))
            return CheckResultData(false, 0, 0, e.message)
        }
    }

    private static func fail(taskId: Int64, message: String): Unit {
        let msg = if (message.size == 0) { "Unknown error" } else { message }
        TaskIO.appendLog(taskId, "FAILED: ${msg}")
        MinionModel.failTask(taskId, msg)
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
