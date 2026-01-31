package lanlu.task_runners

import stdx.log.*
import std.io.*
import std.io.{ByteBuffer}
import stdx.encoding.json.stream.*
import std.fs.*
import lanlu.models.*
import lanlu.utils.*
import lanlu.dao.*
import lanlu.archivehandler.*

/**
 * 缩略图生成任务：为单个档案生成缩略图
 */
public class GenerateThumbnailTaskRunner {

    public static func run(taskId: Int64, parameters: String, context: TaskRunnerContext): Unit {
        let cachePath = context.paths.cachePath
        let assetPath = context.paths.assetPath

        // 确保目录存在
        FileUtils.ensureDirectoryExists(Path(cachePath))
        FileUtils.ensureDirectoryExists(Path(assetPath))

        let logger = getLogger("generate_thumbnail_task")
        TaskIO.appendLog(taskId, "generate_thumbnail task started")

        let (archiveId, archivePath, archiveType) = parseParameters(parameters)
        if (archiveId.size == 0 || archivePath.size == 0) {
            fail(taskId, "archive_id and archive_path are required")
            return
        }
        TaskIO.appendLog(taskId, "Parameters: archive_id=${archiveId}, type=${archiveType}, archive_path=${archivePath}")
        logger.debug("Parameters parsed", ("archive_id", archiveId), ("type", archiveType), ("archive_path", archivePath))

        TaskModel.updateTaskProgress(taskId, 10, "Generating thumbnail for ${archiveId} (type: ${archiveType})")

        let result = generateThumbnail(taskId, archivePath, archiveId, archiveType, cachePath, assetPath)
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
    private static func generateThumbnail(taskId: Int64, archivePath: String, archiveId: String, archiveType: String, cachePath: String, assetPath: String): ProcessResultData {
        let logger = getLogger("generate_thumbnail")
        TaskIO.appendLog(taskId, "Starting thumbnail generation for archive: ${archivePath} (type: ${archiveType})")
        logger.debug("Starting thumbnail generation for archive: ${archivePath} (type: ${archiveType})")

        let actualArchivePath = FileUtils.resolvePath(archivePath)
        TaskIO.appendLog(taskId, "Resolved archive path: ${actualArchivePath}")
        logger.debug("Resolved archive path: ${actualArchivePath}")

        // Fast-path: if a cover asset already exists, avoid repeating expensive work.
        try {
            let existingAssetId = ArchiveDao.getCoverAssetId(archiveId)
            if (existingAssetId > 0) {
                let assetFilePath = FileUtils.joinPath(assetPath, "${existingAssetId}.avif")
                if (exists(Path(assetFilePath))) {
                    let existingHash = ArchiveDao.getThumbnailHash(archiveId)
                    if (existingHash.size > 0) {
                        TaskIO.appendLog(taskId, "Cover asset already exists and thumbhash present; skipping regeneration.")
                        return ProcessResultData(true, assetFilePath, existingHash)
                    }

                    TaskIO.appendLog(taskId, "Cover asset exists but thumbhash missing; calculating from existing file...")
                    let thumbHash = ThumbHashUtils.calculateAvifThumbHashFromFile(assetFilePath)
                    if (ArchiveDao.updateThumbHash(archiveId, thumbHash)) {
                        TaskIO.appendLog(taskId, "Thumbhash saved to database successfully (no regeneration needed)")
                        return ProcessResultData(true, assetFilePath, thumbHash)
                    }
                    TaskIO.appendLog(taskId, "WARN: Failed to save thumbhash; will continue to regenerate thumbnail.")
                }
            }
        } catch (_: Exception) {}

        // 使用任务ID创建独立的临时目录
        let taskTempDir = FileUtils.joinPath(cachePath, "task/${taskId}")
        let taskTempPath = Path(taskTempDir)
        FileUtils.ensureDirectoryExists(taskTempPath)
        TaskIO.appendLog(taskId, "Created task temp directory: ${taskTempDir}")

        let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archiveType)

        // Stream cover extraction into a temp file to avoid loading huge entries into memory.
        // This prevents long stalls on large archives (e.g. 40MB+ PNG cover pages).
        TaskIO.appendLog(taskId, "Extracting cover image using streaming reader (type: ${archiveType})...")

        let (coverEntryName, _) = handler.getFirstImage(actualArchivePath)
        if (coverEntryName.size == 0) {
            let errorMsg = "No image found in ${archiveType} archive"
            TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
            return ProcessResultData(false, "", errorMsg)
        }
        TaskIO.appendLog(taskId, "Cover entry selected: ${coverEntryName}")

        var inferredExt = inferExtensionFromName(coverEntryName)
        if (inferredExt.size == 0) {
            inferredExt = "tmp"
        }

        let tempImagePath = FileUtils.joinPath(taskTempDir, "${archiveId}_temp.${inferredExt}")
        TaskIO.appendLog(taskId, "Inferred cover extension: ${inferredExt}")
        TaskIO.appendLog(taskId, "Streaming cover entry to: ${tempImagePath}")

        let (readerExitCode, readerOpt, readerErr) = handler.getEntryReader(actualArchivePath, coverEntryName)
        if (readerExitCode == 0) {
            match (readerOpt) {
                case Some(reader) =>
                    try {
                        let outFile = File(Path(tempImagePath), Write)
                        let bufSize: Int64 = 1024 * 1024
                        var buf = Array<Byte>(bufSize, repeat: 0)
                        var total: Int64 = 0
                        while (true) {
                            let n = reader.read(buf)
                            if (n <= 0) {
                                break
                            }
                            outFile.write(buf[0..n])
                            total += n
                        }
                        outFile.close()
                        reader.close()
                        TaskIO.appendLog(taskId, "Cover image extracted via streaming, size: ${total} bytes")
                    } catch (e: Exception) {
                        try { reader.close() } catch (_: Exception) {}
                        let errorMsg = "Failed to write cover image to temp file (streaming): ${e.message}"
                        TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                        return ProcessResultData(false, "", errorMsg)
                    }
                case None =>
                    TaskIO.appendLog(taskId, "WARN: getEntryReader returned None; falling back to in-memory extraction. err=${readerErr}")
                    let (exitCode, imageData, errorData) = handler.getCoverImage(actualArchivePath)
                    if (exitCode != 0 || imageData.size == 0) {
                        var errStr = ""
                        try { errStr = String.fromUtf8(errorData) } catch (_: Exception) { errStr = "Unknown error" }
                        let errorMsg = "Cover extraction failed (exit_code=${exitCode}): ${errStr}"
                        TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                        return ProcessResultData(false, "", errorMsg)
                    }
                    try {
                        let tempFile = File(Path(tempImagePath), Write)
                        tempFile.write(imageData)
                        tempFile.close()
                        TaskIO.appendLog(taskId, "Cover image extracted (fallback), size: ${imageData.size} bytes")
                    } catch (e: Exception) {
                        let errorMsg = "Failed to write cover image to temp file (fallback): ${e.message}"
                        TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                        return ProcessResultData(false, "", errorMsg)
                    }
            }
        } else {
            TaskIO.appendLog(taskId, "WARN: getEntryReader failed; falling back to in-memory extraction. err=${readerErr}")
            let (exitCode, imageData, errorData) = handler.getCoverImage(actualArchivePath)
            if (exitCode != 0 || imageData.size == 0) {
                var errStr = ""
                try { errStr = String.fromUtf8(errorData) } catch (_: Exception) { errStr = "Unknown error" }
                let errorMsg = "Cover extraction failed (exit_code=${exitCode}): ${errStr}"
                TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                return ProcessResultData(false, "", errorMsg)
            }
            try {
                let tempFile = File(Path(tempImagePath), Write)
                tempFile.write(imageData)
                tempFile.close()
                TaskIO.appendLog(taskId, "Cover image extracted (fallback), size: ${imageData.size} bytes")
            } catch (e: Exception) {
                let errorMsg = "Failed to write cover image to temp file (fallback): ${e.message}"
                TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                return ProcessResultData(false, "", errorMsg)
            }
        }

        // 先转换图片为 AVIF 格式（临时路径）
        TaskIO.appendLog(taskId, "Converting image to AVIF format (libvips > FFmpeg)...")
        let tempAvifPath = FileUtils.joinPath(taskTempDir, "${archiveId}_temp.avif")
        let convertResult = ArchiveUtils.convertImageToAvif(tempImagePath, tempAvifPath, taskTempDir)

        // 清理输入临时文件（无论转换成功或失败）
        try {
            if (fileExists(tempImagePath)) {
                remove(Path(tempImagePath))
                TaskIO.appendLog(taskId, "Deleted temp file: ${tempImagePath}")
            }
        } catch (e: Exception) {
            let warnMsg = "Failed to cleanup temp files for task: ${taskId}, error: ${e.message}"
            TaskIO.appendLog(taskId, "WARN: ${warnMsg}")
            logger.warn(warnMsg)
        }

        if (!convertResult.success) {
            if (convertResult.error.size > 0) {
                let errBytes = convertResult.error.toArray()
                let previewBytes = if (errBytes.size > 4096) { errBytes.slice(0, 4096) } else { errBytes }
                let previewStr = try { String.fromUtf8(previewBytes) } catch (_: Exception) { convertResult.error }
                var truncatedSuffix = ""
                if (errBytes.size > 4096) {
                    truncatedSuffix = "\n...(truncated)"
                }
                TaskIO.appendLog(taskId, "Conversion error detail:\n${previewStr}${truncatedSuffix}")
            }
            // 转换失败时，清理输出和临时目录（包括可能生成的 fallback 文件）
            try {
                try { remove(Path(tempAvifPath)) } catch (_: Exception) {}
                let _ = FileUtils.removeFileOrDirectory(taskTempDir)
            } catch (_: Exception) {}

            let errorMsg = "Image conversion failed: ${convertResult.error}"
            TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
            return ProcessResultData(false, "", errorMsg)
        }

        TaskIO.appendLog(taskId, "Image conversion successful: ${tempAvifPath}")
        try {
            let avifSize = FileInfo(Path(tempAvifPath)).size
            TaskIO.appendLog(taskId, "Temp AVIF size: ${avifSize} bytes")
        } catch (_: Exception) {}

        // 计算 thumbhash（基于转换后的 AVIF，仅用于数据库记录）
        TaskIO.appendLog(taskId, "Calculating thumbhash for archive: ${archiveId}")
        logger.debug("Calculating thumbhash for archive: ${archiveId}")
        let thumbHash = ThumbHashUtils.calculateAvifThumbHashFromFile(tempAvifPath)
        TaskIO.appendLog(taskId, "Calculated thumbhash: ${thumbHash}")
        logger.debug("Calculated thumbhash: ${thumbHash}")

        // Create asset row and move the file into ASSET_PATH/{assetId}.avif
        let avifSize = try { Int64(FileInfo(Path(tempAvifPath)).size) } catch (_: Exception) { 0 }
        let assetIdOpt = AssetDao.create(None, "archive_cover", "${archiveId}.avif", "image/avif", "avif", avifSize, thumbHash)
        match (assetIdOpt) {
            case Some(assetId) =>
                let finalAssetPath = FileUtils.joinPath(assetPath, "${assetId}.avif")
                TaskIO.appendLog(taskId, "Moving thumbnail to asset location: ${finalAssetPath}")
                try {
                    FileUtils.safeReplaceFile(Path(finalAssetPath), Path(tempAvifPath))
                } catch (e: Exception) {
                    let errorMsg = "Failed to move thumbnail to asset location: ${e.message}"
                    TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                    return ProcessResultData(false, "", errorMsg)
                }
                TaskIO.appendLog(taskId, "Thumbnail moved to asset location successfully")
                let _ = ArchiveDao.updateCoverAssetId(archiveId, assetId)
                // Move completed; continue.
                // Return the asset path for callers/logs.
                // (ProcessResultData.archiveId is reused as an "output path" here.)
                // NOOP
                // fallthrough below uses thumbhash save + cleanup
                // We will return finalAssetPath at end.
                // ...
                // Save thumbhash to DB already handled below.
                // ...
                // For cleanup: tempAvifPath already moved, ok.
                // ...
                // (finalAssetPath scope needed for return; so keep in var)
                // ---
                // store var for return
                // NOTE: Cangjie var needs declared before match? keep local with var outside.
            case None =>
                let errorMsg = "Failed to create asset record for archive cover"
                TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
                return ProcessResultData(false, "", errorMsg)
        }

        // 移动完成后清理任务临时目录（输出文件已移走）
        try {
            let _ = FileUtils.removeFileOrDirectory(taskTempDir)
        } catch (_: Exception) {}

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

        let coverAssetId = ArchiveDao.getCoverAssetId(archiveId)
        let finalPath = if (coverAssetId > 0) { FileUtils.joinPath(assetPath, "${coverAssetId}.avif") } else { "" }
        return ProcessResultData(true, finalPath, thumbHash)
    }

    // NOTE: removeFileOrDirectory/safeReplaceFile are provided by FileUtils.

    /**
     * Infer extension from filename.
     */
    private static func inferExtensionFromName(name: String): String {
        if (name.size == 0) {
            return ""
        }
        let parts = name.split(".")
        if (parts.size <= 1) {
            return ""
        }
        return parts[parts.size - 1].toAsciiLower()
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
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)

            if (r.peek() == Some(BeginObject)) {
                r.startObject()
                while (r.peek() != EndObject) {
                    let k = r.readName()
                    match (k) {
                        case "archive_id" => archiveId = r.readValue<String>().trimAscii()
                        case "archive_path" => archivePath = r.readValue<String>().trimAscii()
                        case "type" =>
                            archiveType = r.readValue<String>().trimAscii()
                            if (archiveType != "archive" && archiveType != "folder" && archiveType != "pdf" && archiveType != "epub") {
                                archiveType = "archive"
                            }
                        case _ => r.skip()
                    }
                }
                r.endObject()
            }
        } catch (_: Exception) {}
        return (archiveId, archivePath, archiveType)
    }

    private static func fail(taskId: Int64, message: String): Unit {
        TaskRunnerOutput.fail(taskId, message)
    }

    /**
     * 检查文件是否存在（支持软链接）
     */
    private static func fileExists(path: String): Bool {
        return DirectoryScanner.fileExists(path)
    }

    // thumbhash logic extracted to utils/ThumbHashUtils to reuse across assets (covers, avatars, ...)
}
