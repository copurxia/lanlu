package lrr4cj.services

import std.fs.*
import stdx.encoding.json.*
import stdx.log.*
import std.sync.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*

/**
 * 单个档案扫描任务：处理归档文件并入库
 */
public class ScanArchiveTaskRunner {
    private static var logger = getLogger("scan_archive_task")

    // 配置
    private static var initialized: Bool = false
    private static let initMutex: Mutex = Mutex()

    // 私有初始化方法（懒加载）
    private static func ensureInitialized(): Unit {
        initMutex.lock()
        if (!initialized) {
            try {
                // 从数据库读取配置
                let cachePathStr = SystemSettingsService.getPath("CACHE_PATH")
                let thumbnailPathStr = SystemSettingsService.getPath("THUMBNAIL_PATH")

                // 先确保目录存在，然后规范化路径
                // 注意：canonicalize() 要求路径存在，否则会失败
                let cachePath = Path(cachePathStr)
                let thumbnailPath = Path(thumbnailPathStr)
                FileUtils.ensureDirectoryExists(cachePath)
                FileUtils.ensureDirectoryExists(thumbnailPath)

                // 转换为 Path 类型并规范化
                let cachePathCanonical = canonicalize(cachePathStr)
                let thumbnailPathCanonical = canonicalize(thumbnailPathStr)

                initialized = true
            } catch (e: Exception) {
                // 即使初始化失败，也设置为 true 避免死锁
                initialized = true
                throw e
            }
        }
        initMutex.unlock()
    }

    public static func run(taskId: Int64, parameters: String): Unit {
        let logger = getLogger("scan_archive_task")
        TaskIO.appendLog(taskId, "scan_archive task started")
        TaskIO.appendLog(taskId, "Task parameters: ${parameters}")

        try {
            // 确保配置已初始化
            TaskIO.appendLog(taskId, "Initializing configuration...")
            ensureInitialized()
            TaskIO.appendLog(taskId, "Configuration initialized successfully")

            TaskIO.appendLog(taskId, "Parsing configuration...")
            let config = parseConfig(parameters)
            TaskIO.appendLog(taskId, "Parsed config: archivePath=${config.archivePath}, cachePath=${config.cachePath}, thumbnailPath=${config.thumbnailPath}")

            if (config.archivePath.size == 0) {
                TaskIO.appendLog(taskId, "ERROR: No archive path found in parameters")
                fail(taskId, "archive_path is required")
                return
            }

            TaskIO.appendLog(taskId, "Starting archive processing for: ${config.archivePath}")
            TaskModel.updateTaskProgress(taskId, 10, "Processing ${config.archivePath}")

            let result = processArchiveInternal(config.archivePath, config)
            TaskIO.appendLog(taskId, "processArchiveInternal returned: success=${result.success}, archiveId=${result.archiveId}, error=${result.error}")

            if (!result.success) {
                let errorMsg = "scan_archive failed: ${config.archivePath}, error: ${result.error}"
                logger.error(errorMsg)
                TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                fail(taskId, result.error)
                return
            }

            let successJson = "{\"success\":1,\"archive_id\":\"${result.archiveId}\",\"path\":\"${escapeJson(config.archivePath)}\"}"
            TaskIO.appendLog(taskId, "Archive processed successfully, archiveId=${result.archiveId}")
            TaskModel.updateTaskProgress(taskId, 100, "Archive processed")
            TaskModel.completeTask(taskId, successJson)
            TaskIO.writeOutput(taskId, successJson)
            TaskIO.appendLog(taskId, "scan_archive completed for ${config.archivePath}")
        } catch (e: Exception) {
            let errorMsg = "Unexpected error: ${e.message}"
            logger.error(errorMsg, ("exception", e.message), ("stack", e.toString()))
            TaskIO.appendLog(taskId, "FATAL ERROR: ${errorMsg}")
            TaskIO.appendLog(taskId, "Stack trace: ${e.toString()}")
            fail(taskId, errorMsg)
        }
    }

    private static func parseConfig(parameters: String): ArchiveConfig {
        let trimmed = parameters.trimAscii()
        var archivePath = ""
        var cachePath = ""
        var thumbnailPath = ""

        if (trimmed.size == 0) {
            return ArchiveConfig(archivePath, cachePath, thumbnailPath)
        }

        try {
            let jsonVal = JsonValue.fromStr(trimmed)
            match (jsonVal) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    if (fields.contains("archive_path")) {
                        let value = fields["archive_path"]
                        match (value) {
                            case s: JsonString => archivePath = s.getValue().trimAscii()
                            case _ => throw Exception("archive_path must be a string")
                        }
                    }

                    if (fields.contains("cache_path")) {
                        let value = fields["cache_path"]
                        match (value) {
                            case s: JsonString => cachePath = s.getValue().trimAscii()
                            case _ => throw Exception("cache_path must be a string")
                        }
                    }
                    if (fields.contains("thumbnail_path")) {
                        let value = fields["thumbnail_path"]
                        match (value) {
                            case s: JsonString => thumbnailPath = s.getValue().trimAscii()
                            case _ => throw Exception("thumbnail_path must be a string")
                        }
                    }
                case _ => ()
            }
        } catch (_: Exception) {}

        return ArchiveConfig(archivePath, cachePath, thumbnailPath)
    }

    private static func processArchiveInternal(filePath: String, config: ArchiveConfig): ProcessResultData {
        try {
            let relativePath = ArchiveUtils.calculateRelativePath(filePath, config.archivePath)
            let fileName = ArchiveUtils.getFullFileName(filePath)
            let existingArchive = ArchiveDao.getByPathAndFilename(relativePath, fileName)

            match (existingArchive) {
                case Some(archive) =>
                    logger.info("Archive already exists in database: ${filePath}")

                    if (archive.relative_path.size == 0) {
                        logger.info("Archive has empty relative_path, updating: ${archive.id}")
                    }

                    if (archive.thumbhash.size == 0) {
                        logger.info("Thumbnail hash is empty, submitting thumbnail generation task for existing archive: ${archive.id}")

                        // 提交缩略图生成任务（异步）
                        let taskSubmitted = submitThumbnailTask(filePath, archive.id)
                        if (!taskSubmitted) {
                            logger.error("Failed to submit thumbnail generation task for archive: ${archive.id}")
                        }

                        // 直接返回成功，不等待缩略图生成完成
                        return ProcessResultData(true, archive.id, "")
                    } else {
                        // Archive存在且已生成thumbhash - 跳过所有处理，直接返回成功
                        logger.info("Archive already processed with thumbnail: ${filePath}")
                        return ProcessResultData(true, archive.id, "")
                    }
                case None =>
                    logger.debug("Archive not found in database, processing new file: ${filePath}")
            }

            let entries = ArchiveUtils.listArchiveEntries(filePath)
            var pageCount: Int32 = 0
            for (entry in entries) {
                if (ArchiveUtils.isImageFile(entry)) {
                    pageCount++
                }
            }
            logger.info("Archive ${filePath} contains ${pageCount} images")

            let dbResult = addArchiveToDatabase(filePath, config)
            if (!dbResult.success) {
                return dbResult
            }

            let pageUpdateResult = ArchiveDao.updatePageCount(dbResult.archiveId, pageCount)
            if (!pageUpdateResult) {
                logger.error("Failed to update page count for archive: ${dbResult.archiveId}")
            }

            // 提交缩略图生成任务（异步）
            let taskSubmitted = submitThumbnailTask(filePath, dbResult.archiveId)
            if (!taskSubmitted) {
                logger.error("Failed to submit thumbnail generation task for archive: ${dbResult.archiveId}")
            }

            return ProcessResultData(true, dbResult.archiveId, "")
        } catch (e: Exception) {
            return ProcessResultData(false, "", "Error processing file: ${e.message}")
        }
    }

    private static func addArchiveToDatabase(filePath: String, config: ArchiveConfig): ProcessResultData {
        try {
            let archiveId = ArchiveUtils.generateArchiveId(filePath)

            let fileName = ArchiveUtils.getFullFileName(filePath)
            let defaultTitle = ArchiveUtils.generateDefaultTitle(filePath)
            let fileSize = ArchiveUtils.getArchiveFileSize(filePath)
            let fileModTime = ArchiveUtils.getArchiveFileModTime(filePath)

            let relativePath = ArchiveUtils.calculateRelativePath(filePath, config.archivePath)

            let success = ArchiveDao.insertArchive(archiveId, defaultTitle, fileName, fileSize, fileModTime, relativePath)
            if (!success) {
                return ProcessResultData(false, "", "Failed to create archive record in database")
            }

            // 提交缩略图生成任务（异步）
            let taskSubmitted = submitThumbnailTask(filePath, archiveId)
            if (!taskSubmitted) {
                logger.error("Failed to submit thumbnail generation task for archive: ${archiveId}")
            }

            return ProcessResultData(true, archiveId, "")
        } catch (e: Exception) {
            let error = "Exception adding archive to database: ${e.message}"
            logger.error(error)
            return ProcessResultData(false, "", error)
        }
    }

    /**
     * 提交缩略图生成任务到任务池
     */
    private static func submitThumbnailTask(archivePath: String, archiveId: String): Bool {
        try {
            let parameters = "{\"archive_path\":\"${escapeJson(archivePath)}\",\"archive_id\":\"${escapeJson(archiveId)}\"}"
            let task = TaskModel.createTaskWithOptions(
                "generate_thumbnail_${archiveId}",
                "generate_thumbnail",
                parameters,
                10i32,
                archiveId,
                "scan_archive"
            )

            if (task.id > 0) {
                TaskPoolService.getInstance().notifyTaskAvailable()
                logger.info("Submitted thumbnail generation task", ("archive_id", archiveId), ("task_id", task.id.toString()))
                return true
            } else {
                logger.error("Failed to submit thumbnail generation task", ("archive_id", archiveId))
                return false
            }
        } catch (e: Exception) {
            logger.error("Exception submitting thumbnail task", ("archive_id", archiveId), ("exception", e.message))
            return false
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
