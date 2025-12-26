package lrr4cj.services

import stdx.encoding.json.*
import stdx.log.*
import std.fs.*
import std.process.*
import stdx.crypto.digest.*
import stdx.encoding.hex.*
import std.sync.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*
import lrr4cj.archivehandler.*

/**
 * 缩略图生成任务：为单个档案生成缩略图
 */
public class GenerateThumbnailTaskRunner {
    // 配置 - 使用静态变量存储配置
    private static var cachePath: Path = Path("")
    private static var thumbnailPath: Path = Path("")
    private static var initialized: Bool = false
    private static let initMutex: Mutex = Mutex()

    // 私有初始化方法（懒加载）
    private static func ensureInitialized(): Unit {
        initMutex.lock()
        if (!initialized) {
            // 从数据库读取配置
            let cachePathStr = SystemSettingsService.getPath("CACHE_PATH")
            let thumbnailPathStr = SystemSettingsService.getPath("THUMBNAIL_PATH")

            // 转换为 Path 类型并规范化
            cachePath = canonicalize(cachePathStr)
            thumbnailPath = canonicalize(thumbnailPathStr)

            // 确保必要的目录存在
            FileUtils.ensureDirectoryExists(cachePath)
            FileUtils.ensureDirectoryExists(thumbnailPath)

            initialized = true
        }
        initMutex.unlock()
    }

    public static func run(taskId: Int64, parameters: String): Unit {
        // 确保配置已初始化
        ensureInitialized()

        let logger = getLogger("generate_thumbnail_task")
        TaskIO.appendLog(taskId, "generate_thumbnail task started")

        let (archiveId, archivePath, archiveType) = parseParameters(parameters)
        if (archiveId.size == 0 || archivePath.size == 0) {
            fail(taskId, "archive_id and archive_path are required")
            return
        }

        TaskModel.updateTaskProgress(taskId, 10, "Generating thumbnail for ${archiveId} (type: ${archiveType})")

        let result = generateThumbnail(taskId, archivePath, archiveId, archiveType)
        if (!result.success) {
            logger.error("generate_thumbnail failed", ("archive_id", archiveId), ("error", result.error))
            fail(taskId, result.error)
            return
        }

        let successJson = "{\"success\":1,\"archive_id\":\"${archiveId}\"}"
        TaskModel.updateTaskProgress(taskId, 100, "Thumbnail generated successfully")
        TaskModel.completeTask(taskId, successJson)
        TaskIO.writeOutput(taskId, successJson)
        TaskIO.appendLog(taskId, "generate_thumbnail completed for archive: ${archiveId}")
    }

    /**
     * 生成缩略图
     */
    private static func generateThumbnail(taskId: Int64, archivePath: String, archiveId: String, archiveType: String): ProcessResultData {
        let logger = getLogger("generate_thumbnail")
        TaskIO.appendLog(taskId, "Starting thumbnail generation for archive: ${archivePath} (type: ${archiveType})")
        logger.info("Starting thumbnail generation for archive: ${archivePath} (type: ${archiveType})")

        let actualArchivePath = FileUtils.resolvePath(archivePath)
        TaskIO.appendLog(taskId, "Resolved archive path: ${actualArchivePath}")
        logger.info("Resolved archive path: ${actualArchivePath}")

        // 使用任务ID创建独立的临时目录
        let taskTempDir = FileUtils.joinPath(cachePath.toString(), "task/${taskId}")
        let taskTempPath = Path(taskTempDir)
        FileUtils.ensureDirectoryExists(taskTempPath)
        TaskIO.appendLog(taskId, "Created task temp directory: ${taskTempDir}")

        // 使用 getCoverImage 直接获取封面图片数据
        let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archiveType)
        TaskIO.appendLog(taskId, "Extracting cover image using getCoverImage...")
        let (exitCode, imageData, errorData) = handler.getCoverImage(actualArchivePath)

        if (exitCode != 0 || imageData.size == 0) {
            let errorMsg = if (errorData.size > 0) {
                String.fromUtf8(errorData)
            } else {
                "No cover image found in ${archiveType} archive"
            }
            TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
            return ProcessResultData(false, "", errorMsg)
        }

        TaskIO.appendLog(taskId, "Cover image extracted, size: ${imageData.size} bytes")

        // 将图片数据写入临时文件
        let tempImagePath = FileUtils.joinPath(taskTempDir, "${archiveId}_temp.jpg")
        TaskIO.appendLog(taskId, "Writing cover image to: ${tempImagePath}")

        try {
            let tempFile = File(Path(tempImagePath), Write)
            tempFile.write(imageData)
            tempFile.close()
        } catch (e: Exception) {
            let errorMsg = "Failed to write cover image to temp file: ${e.message}"
            TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
            return ProcessResultData(false, "", errorMsg)
        }

        // 计算thumbhash（基于第一张图片的内容）
        TaskIO.appendLog(taskId, "Calculating thumbhash for archive: ${archiveId}")
        logger.info("Calculating thumbhash for archive: ${archiveId}")
        let thumbHash = calculateThumbHash(tempImagePath)
        TaskIO.appendLog(taskId, "Calculated thumbhash: ${thumbHash}")
        logger.info("Calculated thumbhash: ${thumbHash}")

        // 使用thumbhash作为缩略图文件名
        let thumbnailFilePath = FileUtils.joinPath(thumbnailPath.toString(), "${thumbHash}.jpg")
        TaskIO.appendLog(taskId, "Thumbnail file path: ${thumbnailFilePath}")

        // 如果文件已存在，先删除（避免重复）
        if (fileExists(thumbnailFilePath)) {
            TaskIO.appendLog(taskId, "Existing thumbnail found, removing: ${thumbnailFilePath}")
            let rmExitCode = try {
                let process = launch("rm", ["-f", thumbnailFilePath], stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                process.wait()
            } catch (e: Exception) {
                1
            }
            if (rmExitCode != 0) {
                let warnMsg = "Failed to delete existing thumbnail: ${thumbnailFilePath}"
                TaskIO.appendLog(taskId, "WARN: ${warnMsg}")
                logger.warn(warnMsg)
            }
        }

        TaskIO.appendLog(taskId, "Converting image to JPG format...")
        let convertResult = ArchiveUtils.convertImageToJpg(tempImagePath, thumbnailFilePath, taskTempDir)

        // 清理临时文件和目录
        try {
            if (fileExists(tempImagePath)) {
                let exitCode = try {
                    let process = launch("rm", ["-f", tempImagePath], stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                    process.wait()
                } catch (e: Exception) {
                    1
                }
                if (exitCode != 0) {
                    let warnMsg = "Failed to delete temp file: ${tempImagePath}"
                    TaskIO.appendLog(taskId, "WARN: ${warnMsg}")
                    logger.warn(warnMsg)
                } else {
                    TaskIO.appendLog(taskId, "Deleted temp file: ${tempImagePath}")
                }
            }
            // 尝试删除空的临时目录
            let rmDirExitCode = try {
                let process = launch("rmdir", [taskTempDir], stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                process.wait()
            } catch (e: Exception) {
                1
            }
            if (rmDirExitCode != 0) {
                let debugMsg = "Task temp directory not empty or cannot be removed: ${taskTempDir}"
                TaskIO.appendLog(taskId, "DEBUG: ${debugMsg}")
                logger.debug(debugMsg)
            } else {
                TaskIO.appendLog(taskId, "Removed task temp directory: ${taskTempDir}")
            }
        } catch (e: Exception) {
            let warnMsg = "Failed to cleanup temp files for task: ${taskId}, error: ${e.message}"
            TaskIO.appendLog(taskId, "WARN: ${warnMsg}")
            logger.warn(warnMsg)
        }

        if (!convertResult.success) {
            let errorMsg = "Image conversion failed: ${convertResult.error}"
            TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
            return ProcessResultData(false, "", errorMsg)
        }

        TaskIO.appendLog(taskId, "Image conversion successful")

        // 将thumbhash存储到数据库
        TaskIO.appendLog(taskId, "Saving thumbhash to database for archive: ${archiveId}")
        logger.info("Saving thumbhash to database for archive: ${archiveId}")
        let dbSuccess = ArchiveDao.updateThumbHash(archiveId, thumbHash)
        if (!dbSuccess) {
            let errorMsg = "Failed to save thumbhash to database for archive: ${archiveId}"
            TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
            logger.error(errorMsg)
            return ProcessResultData(false, "", "Failed to save thumbhash to database")
        }

        TaskIO.appendLog(taskId, "Thumbhash saved to database successfully")
        logger.info("Successfully generated thumbnail for archive: ${archiveId}, thumbhash: ${thumbHash}")
        TaskIO.appendLog(taskId, "Successfully generated thumbnail for archive: ${archiveId}, thumbhash: ${thumbHash}")
        return ProcessResultData(true, thumbnailFilePath, thumbHash)
    }

    private static func parseParameters(parameters: String): (String, String, String) {
        let trimmed = parameters.trimAscii()
        if (trimmed.size == 0) {
            return ("", "", "")
        }
        var archiveId = ""
        var archivePath = ""
        var archiveType = "archive"  // 默认压缩包
        try {
            let jsonVal = JsonValue.fromStr(trimmed)
            match (jsonVal) {
                case obj: JsonObject =>
                    let fields = obj.getFields()
                    if (fields.contains("archive_id")) {
                        let value = fields["archive_id"]
                        match (value) {
                            case s: JsonString => archiveId = s.getValue().trimAscii()
                            case _ => throw Exception("archive_id must be a string")
                        }
                    }
                    if (fields.contains("archive_path")) {
                        let value = fields["archive_path"]
                        match (value) {
                            case s: JsonString => archivePath = s.getValue().trimAscii()
                            case _ => throw Exception("archive_path must be a string")
                        }
                    }
                    if (fields.contains("type")) {
                        let value = fields["type"]
                        match (value) {
                            case s: JsonString =>
                                archiveType = s.getValue().trimAscii()
                                // 验证类型有效性
                                if (archiveType != "archive" && archiveType != "folder" && archiveType != "pdf" && archiveType != "epub") {
                                    archiveType = "archive"
                                }
                            case _ => ()
                        }
                    }
                case _ => ()
            }
        } catch (_: Exception) {}
        return (archiveId, archivePath, archiveType)
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
     * 计算图片的thumbhash（基于SHA1）
     */
    private static func calculateThumbHash(imagePath: String): String {
        try {
            // 获取文件信息
            let filePath = Path(imagePath)
            let file = File(filePath, Read)
            let fileInfo = file.info
            file.close()

            // 组合内容：文件路径 + 大小（简单哈希，避免读取大文件）
            let content = imagePath + fileInfo.size.toString()

            // 使用 SHA1 算法生成哈希
            var sha1Instance = SHA1()
            sha1Instance.write(content.toArray())
            let hash: Array<Byte> = sha1Instance.finish()

            let result = toHexString(hash)
            return result
        } catch (e: Exception) {
            let logger = getLogger("generate_thumbnail")
            let errorMsg = "Error calculating thumbhash for ${imagePath}: ${e.message}"
            logger.error(errorMsg)
            // 失败时使用文件路径作为备选
            return "fallback_${ArchiveUtils.generateFileHash(imagePath)}"
        }
    }
}
