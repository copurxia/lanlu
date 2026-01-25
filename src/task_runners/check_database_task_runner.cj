package lrr4cj.task_runners

import stdx.log.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*

/**
 * 数据库一致性检查任务：检查数据库记录与实际文件的匹配情况，清理孤儿记录
 */
public class CheckDatabaseTaskRunner {

    public static func run(taskId: Int64, _: String, _: TaskRunnerContext): Unit {
        let logger = getLogger("check_database_task")
        TaskIO.appendLog(taskId, "check_database task started")

        try {
            TaskIO.appendLog(taskId, "Using category-based paths for file checking")

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

            logger.debug("Fetching all archives from database...")
            let archives = ArchiveDao.getAllArchives()
            logger.debug("Retrieved ${archives.size} archives from database")

            var deletedCount: Int64 = 0
            let checkedCount = archives.size

            if (archives.size == 0) {
                logger.debug("No archives found in database, nothing to check")
                return CheckResultData(true, 0, 0, "")
            }

            logger.debug("Starting file existence check for ${checkedCount} archives")

            var processed = 0
            for (archive in archives) {
                processed++
                // 从分类获取基础路径
                let categoryId = archive.category_id
                var archiveBasePath = ""
                if (categoryId > 0) {
                    match (CategoryDao.getCategoryByInternalId(categoryId)) {
                        case Some(cat) => archiveBasePath = cat.scanPath
                        case None => ()
                    }
                }

                if (archiveBasePath.size == 0) {
                    logger.warn("Archive has no valid category", ("arcid", archive.id))
                    continue
                }

                let fullFilePath: String
                if (archive.relative_path.size > 0 && archive.relative_path != "") {
                    let dirPath = joinPath(archiveBasePath, archive.relative_path)
                    fullFilePath = joinPath(dirPath, archive.filename)
                } else {
                    fullFilePath = joinPath(archiveBasePath, archive.filename)
                }

                logger.debug("Checking file ${processed}/${checkedCount}", ("file", fullFilePath))

                // 根据archive_type检查文件或目录是否存在（支持软链接）
                let pathExists = if (archive.archive_type == "folder") {
                    // 文件夹类型：检查目录是否存在
                    DirectoryScanner.isDirectory(fullFilePath)
                } else {
                    // 压缩包或PDF类型：检查文件是否存在
                    fileExists(fullFilePath)
                }

                if (!pathExists) {
                    logger.warn("Archive path not found, will delete from database", ("path", fullFilePath), ("archive_id", archive.id.toString()), ("type", archive.archive_type))
                    if (ArchiveDao.delete(archive.id)) {
                        deletedCount++
                        // DB 删除后清理缩略图（原始文件已不存在/不可用；缩略图属于缓存，可安全删除）
                        if (!ArchiveModel.deleteThumbnailFile(archive.id)) {
                            logger.debug("Failed to delete thumbnail file", ("arcid", archive.id))
                        }
                        logger.debug("Successfully deleted database record", ("id", archive.id.toString()), ("title", archive.title))
                    } else {
                        logger.error("Failed to delete database record", ("id", archive.id.toString()), ("title", archive.title))
                    }
                } else {
                    logger.debug("Archive path exists, skipping", ("path", fullFilePath), ("type", archive.archive_type))
                }

                // 每处理100个文件输出一次进度
                if (processed % 100 == 0 || processed == checkedCount) {
                    logger.debug("Progress: ${processed}/${checkedCount} files checked, ${deletedCount} deletions so far")
                }
            }

            if (deletedCount > 0) {
                logger.debug("Database check completed with deletions", ("deleted_count", deletedCount.toString()), ("checked_count", checkedCount.toString()))
            } else {
                logger.debug("Database check completed successfully - all ${checkedCount} files exist", ("checked_count", checkedCount.toString()))
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
