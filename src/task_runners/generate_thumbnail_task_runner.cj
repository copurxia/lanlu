package lrr4cj.task_runners

import stdx.encoding.json.*
import stdx.log.*
import std.fs.*
import std.process.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*
import lrr4cj.archivehandler.*
import avif_ffi.*
import ahash.*

/**
 * 缩略图生成任务：为单个档案生成缩略图
 */
public class GenerateThumbnailTaskRunner {

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let cachePath = context.paths.cachePath
        let thumbnailPath = context.paths.thumbnailPath

        // 确保目录存在
        FileUtils.ensureDirectoryExists(Path(cachePath))
        FileUtils.ensureDirectoryExists(Path(thumbnailPath))

        let logger = getLogger("generate_thumbnail_task")
        TaskIO.appendLog(taskId, "generate_thumbnail task started")

        let (archiveId, archivePath, archiveType) = parseParameters(parameters)
        if (archiveId.size == 0 || archivePath.size == 0) {
            fail(taskId, "archive_id and archive_path are required")
            return
        }

        TaskModel.updateTaskProgress(taskId, 10, "Generating thumbnail for ${archiveId} (type: ${archiveType})")

        let result = generateThumbnail(taskId, archivePath, archiveId, archiveType, cachePath, thumbnailPath)
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
    private static func generateThumbnail(taskId: Int64, archivePath: String, archiveId: String, archiveType: String, cachePath: String, thumbnailPath: String): ProcessResultData {
        let logger = getLogger("generate_thumbnail")
        TaskIO.appendLog(taskId, "Starting thumbnail generation for archive: ${archivePath} (type: ${archiveType})")
        logger.debug("Starting thumbnail generation for archive: ${archivePath} (type: ${archiveType})")

        let actualArchivePath = FileUtils.resolvePath(archivePath)
        TaskIO.appendLog(taskId, "Resolved archive path: ${actualArchivePath}")
        logger.debug("Resolved archive path: ${actualArchivePath}")

        // 使用任务ID创建独立的临时目录
        let taskTempDir = FileUtils.joinPath(cachePath, "task/${taskId}")
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

        // 先转换图片为 AVIF 格式（临时路径）
        TaskIO.appendLog(taskId, "Converting image to AVIF format...")
        let tempAvifPath = FileUtils.joinPath(taskTempDir, "${archiveId}_temp.avif")
        let convertResult = ArchiveUtils.convertImageToAvif(tempImagePath, tempAvifPath, taskTempDir)

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

        // 计算 thumbhash（基于转换后的 AVIF）
        TaskIO.appendLog(taskId, "Calculating thumbhash for archive: ${archiveId}")
        logger.debug("Calculating thumbhash for archive: ${archiveId}")
        let thumbHash = calculateThumbHash(tempAvifPath)
        TaskIO.appendLog(taskId, "Calculated thumbhash: ${thumbHash}")
        logger.debug("Calculated thumbhash: ${thumbHash}")

        // 使用 thumbhash 作为文件名
        let finalThumbnailPath = FileUtils.joinPath(thumbnailPath, "${thumbHash}.avif")

        // 移动文件到最终位置
        TaskIO.appendLog(taskId, "Moving thumbnail to final location: ${finalThumbnailPath}")
        let mvExitCode = try {
            let process = launch("mv", ["-f", tempAvifPath, finalThumbnailPath], stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
            process.wait()
        } catch (e: Exception) {
            1
        }
        if (mvExitCode != 0) {
            let errorMsg = "Failed to move thumbnail to final location"
            TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
            return ProcessResultData(false, "", errorMsg)
        }

        // 将thumbhash存储到数据库
        TaskIO.appendLog(taskId, "Saving thumbhash to database for archive: ${archiveId}")
        logger.debug("Saving thumbhash to database for archive: ${archiveId}")
        let dbSuccess = ArchiveDao.updateThumbHash(archiveId, thumbHash)
        if (!dbSuccess) {
            let errorMsg = "Failed to save thumbhash to database for archive: ${archiveId}"
            TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
            logger.error(errorMsg)
            return ProcessResultData(false, "", "Failed to save thumbhash to database")
        }

        TaskIO.appendLog(taskId, "Thumbhash saved to database successfully")
        logger.debug("Successfully generated thumbnail for archive: ${archiveId}, thumbhash: ${thumbHash}")
        TaskIO.appendLog(taskId, "Successfully generated thumbnail for archive: ${archiveId}, thumbhash: ${thumbHash}")
        return ProcessResultData(true, finalThumbnailPath, thumbHash)
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
     * 计算图片的thumbhash（基于像素内容的ahash）
     */
    private static func calculateThumbHash(imagePath: String): String {
        // 读取图片文件
        let filePath = Path(imagePath)
        let file = File(filePath, Read)
        let fileInfo = file.info
        let fileSize = Int64(fileInfo.size)
        let buffer = Array<Byte>(fileSize, {_ => 0})
        let bytesRead = file.read(buffer)
        file.close()

        if (bytesRead <= 0) {
            throw Exception("Failed to read file: ${imagePath}")
        }

        let imageData = buffer[0..bytesRead]

        // 使用 avif_ffi 解码图片
        if (let Some((_, _, pixels)) <- AvifDecoder.decodeRGBA(imageData)) {
            // 使用 ahash 计算像素数据的哈希
            let builder = RandomState.new()
            let hasher = builder.buildHasher()
            hasher.write(pixels)
            let hash = hasher.finish()
            return hashToHex(hash)
        }

        throw Exception("AVIF decode failed for: ${imagePath}")
    }

    /**
     * 将 UInt64 转换为十六进制字符串
     */
    private static func hashToHex(hash: UInt64): String {
        var result = ""
        var h = hash
        for (_ in 0..16) {
            let nibble = Int64((h >> 60) & 0xF)
            let c = if (nibble < 10) {
                Rune(UInt32(48 + nibble))  // '0' = 48
            } else {
                Rune(UInt32(97 + nibble - 10))  // 'a' = 97
            }
            result += c.toString()
            h <<= 4
        }
        return result
    }
}
