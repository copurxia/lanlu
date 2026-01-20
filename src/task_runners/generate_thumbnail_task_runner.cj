package lrr4cj.task_runners

import stdx.encoding.json.*
import stdx.log.*
import std.fs.*
import lrr4cj.models.*
import lrr4cj.utils.*
import lrr4cj.dao.*
import lrr4cj.archivehandler.*

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

        // 使用 getCoverImage 直接获取封面图片数据
        let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archiveType)
        TaskIO.appendLog(taskId, "Extracting cover image using getCoverImage (type: ${archiveType})...")
        let (exitCode, imageData, errorData) = handler.getCoverImage(actualArchivePath)

        if (exitCode != 0 || imageData.size == 0) {
            TaskIO.appendLog(taskId, "Cover extraction failed (exit_code=${exitCode}, image_bytes=${imageData.size}, err_bytes=${errorData.size})")
            let errorMsg = if (errorData.size > 0) {
                let previewBytes = if (errorData.size > 1024) { errorData.slice(0, 1024) } else { errorData }
                let previewStr = try { String.fromUtf8(previewBytes) } catch (_: Exception) { "" }
                if (errorData.size > 1024) { "${previewStr}\n...(truncated)" } else { previewStr }
            } else {
                "No cover image found in ${archiveType} archive"
            }
            TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
            return ProcessResultData(false, "", errorMsg)
        }

        TaskIO.appendLog(taskId, "Cover image extracted (exit_code=${exitCode}), size: ${imageData.size} bytes")

        // FFmpeg/ffprobe may mis-detect some formats when the file has no extension (e.g. ".tmp").
        // Prefer inferring the extension from the bytes; fallback to the first media entry's extension.
        let inferredExt = inferMediaExtension(imageData, handler, actualArchivePath)
        let tempImagePath = FileUtils.joinPath(taskTempDir, "${archiveId}_temp.${inferredExt}")
        TaskIO.appendLog(taskId, "Inferred cover extension: ${inferredExt}")
        TaskIO.appendLog(taskId, "Writing cover image to: ${tempImagePath}")

        try {
            let tempFile = File(Path(tempImagePath), Write)
            tempFile.write(imageData)
            tempFile.close()
            try {
                let tmpSize = FileInfo(Path(tempImagePath)).size
                TaskIO.appendLog(taskId, "Wrote temp cover file (size=${tmpSize} bytes)")
            } catch (_: Exception) {}
        } catch (e: Exception) {
            let errorMsg = "Failed to write cover image to temp file: ${e.message}"
            TaskIO.appendLog(taskId, "ERROR: ${errorMsg}")
            return ProcessResultData(false, "", errorMsg)
        }

        // 先转换图片为 AVIF 格式（临时路径）
        TaskIO.appendLog(taskId, "Converting image to AVIF format (prefer ImageMagick, fallback FFmpeg)...")
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
                let _ = removeFileOrDirectory(taskTempDir)
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
                    safeReplaceFile(Path(finalAssetPath), Path(tempAvifPath))
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
            let _ = removeFileOrDirectory(taskTempDir)
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

    /**
     * Remove a file or directory recursively (best-effort).
     * Returns true if the path does not exist or was removed successfully.
     */
    private static func removeFileOrDirectory(path: String): Bool {
        try {
            let p = Path(path)
            if (!exists(p)) {
                return true
            }
            let info = FileInfo(p)
            if (info.isDirectory()) {
                let entries = DirectoryScanner.listDirectory(path)
                for (entry in entries) {
                    let fullPath = FileUtils.joinPath(path, entry)
                    if (!removeFileOrDirectory(fullPath)) {
                        return false
                    }
                }
                remove(p)
                return true
            }
            remove(p)
            return true
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * Atomically replace a file by first removing the target (if present) and then renaming.
     * Falls back to copy+remove if rename fails (e.g. cross-device).
     */
    private static func safeReplaceFile(target: Path, from: Path): Unit {
        if (exists(target)) {
            remove(target)
        }
        try {
            rename(from, to: target)
            return
        } catch (_: Exception) {
            // Fallback for cross-device moves.
        }
        copy(from, to: target, overwrite: true)
        remove(from)
    }

    /**
     * Infer a file extension for ffprobe/ffmpeg based on the cover bytes.
     * If detection fails, fallback to the first media entry name.
     */
    private static func inferMediaExtension(imageData: Array<UInt8>, handler: ArchiveHandler, archivePath: String): String {
        // 1) Magic-number detection (best effort)
        let magicExt = inferExtensionFromMagic(imageData)
        if (magicExt.size > 0) {
            return magicExt
        }

        // 2) Fallback: use the first media entry's extension (if available)
        let (entryName, _) = handler.getFirstImage(archivePath)
        let nameExt = inferExtensionFromName(entryName)
        if (nameExt.size > 0) {
            return nameExt
        }

        // 3) Last resort
        return "tmp"
    }

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

    /**
     * Infer extension from common file signatures.
     */
    private static func inferExtensionFromMagic(data: Array<UInt8>): String {
        if (data.size < 12) {
            return ""
        }

        // JPEG: FF D8 FF
        if (data.size >= 3 && data[0] == 0xFFu8 && data[1] == 0xD8u8 && data[2] == 0xFFu8) {
            return "jpg"
        }

        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if (data.size >= 8 &&
            data[0] == 0x89u8 && data[1] == 0x50u8 && data[2] == 0x4Eu8 && data[3] == 0x47u8 &&
            data[4] == 0x0Du8 && data[5] == 0x0Au8 && data[6] == 0x1Au8 && data[7] == 0x0Au8) {
            return "png"
        }

        // GIF: "GIF8"
        if (data.size >= 4 &&
            data[0] == 0x47u8 && data[1] == 0x49u8 && data[2] == 0x46u8 && data[3] == 0x38u8) {
            return "gif"
        }

        // WEBP: "RIFF" .... "WEBP"
        if (data.size >= 12 &&
            data[0] == 0x52u8 && data[1] == 0x49u8 && data[2] == 0x46u8 && data[3] == 0x46u8 &&
            data[8] == 0x57u8 && data[9] == 0x45u8 && data[10] == 0x42u8 && data[11] == 0x50u8) {
            return "webp"
        }

        // EBML (Matroska/WebM): 1A 45 DF A3
        if (data.size >= 4 && data[0] == 0x1Au8 && data[1] == 0x45u8 && data[2] == 0xDFu8 && data[3] == 0xA3u8) {
            return "mkv"
        }

        // ISO BMFF (MP4/AVIF/HEIF): "....ftyp" + major brand
        if (data.size >= 12 &&
            data[4] == 0x66u8 && data[5] == 0x74u8 && data[6] == 0x79u8 && data[7] == 0x70u8) {
            // Read major brand as ASCII
            let b0 = data[8]
            let b1 = data[9]
            let b2 = data[10]
            let b3 = data[11]

            // avif/avis
            if (b0 == 0x61u8 && b1 == 0x76u8 && b2 == 0x69u8 && b3 == 0x66u8) { // "avif"
                return "avif"
            }
            if (b0 == 0x61u8 && b1 == 0x76u8 && b2 == 0x69u8 && b3 == 0x73u8) { // "avis"
                return "avif"
            }

            // heic/heif variants
            if (b0 == 0x68u8 && b1 == 0x65u8 && b2 == 0x69u8 && b3 == 0x63u8) { // "heic"
                return "heic"
            }
            if (b0 == 0x6Du8 && b1 == 0x69u8 && b2 == 0x66u8 && b3 == 0x31u8) { // "mif1"
                return "avif"
            }

            // mp4 family (best-effort)
            if (b0 == 0x69u8 && b1 == 0x73u8 && b2 == 0x6Fu8 && b3 == 0x6Du8) { // "isom"
                return "mp4"
            }
            if (b0 == 0x6Du8 && b1 == 0x70u8 && b2 == 0x34u8 && b3 == 0x32u8) { // "mp42"
                return "mp4"
            }
            if (b0 == 0x71u8 && b1 == 0x74u8 && b2 == 0x20u8 && b3 == 0x20u8) { // "qt  "
                return "mov"
            }
        }

        return ""
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

    // thumbhash logic extracted to utils/ThumbHashUtils to reuse across assets (covers, avatars, ...)
}
