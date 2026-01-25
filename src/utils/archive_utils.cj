package lanlu.utils

import std.fs.*
import std.process.*
import std.convert.*
import std.time.*
import std.collection.*
import stdx.crypto.digest.*
import stdx.encoding.hex.*
import stdx.log.*

let logger = getLogger("archive_utils")

/**
 * 处理结果数据
 */
public class ProcessResultData {
    public var success: Bool
    public var archiveId: String
    public var error: String

    public init(success: Bool, archiveId: String, error: String) {
        this.success = success
        this.archiveId = archiveId
        this.error = error
    }
}

/**
 * 档案处理配置类
 */
public class ArchiveConfig {
    public var archivePath: String
    public var cachePath: String
    public var thumbnailPath: String
    public var archiveType: String
    public var tags: String
    public var categoryId: String

    public init(archivePath: String, cachePath: String, thumbnailPath: String, archiveType: String, tags: String, categoryId: String) {
        this.archivePath = archivePath
        this.cachePath = cachePath
        this.thumbnailPath = thumbnailPath
        this.archiveType = archiveType
        this.tags = tags
        this.categoryId = categoryId
    }
}

/**
 * 档案处理工具类
 */
public class ArchiveUtils {

    // 支持的压缩包格式
    public static let SUPPORTED_ARCHIVE_EXTENSIONS: Array<String> = [
        "zip",
        "rar",
        "7z",
        "tar",
        "cbz",
        "cbr",
        "cb7",
        "cbt",
        "tar.gz",
        "tgz"
    ]

    // 支持的图片格式（与处理器保持一致）
    public static let SUPPORTED_IMAGE_EXTENSIONS: Array<String> = [
        "avif", "jpg", "jpeg", "png", "webp", "gif", "AVIF", "JPG", "JPEG", "PNG", "WEBP", "GIF"
    ]

    // 支持的视频格式（与处理器保持一致）
    public static let SUPPORTED_VIDEO_EXTENSIONS: Array<String> = [
        "mp4", "webm", "mkv", "avi", "mov", "m4v", "MP4", "WEBM", "MKV", "AVI", "MOV", "M4V"
    ]

    // ==================== 从 ShinobuService 迁移的工具方法 ====================

    /**
     * 检查文件是否为图片格式（与处理器保持一致）
     */
    public static func isImageFile(filename: String): Bool {
        let parts = filename.split(".")
        if (parts.size <= 1) {
            return false
        }
        let extension = parts[parts.size - 1]
        for (ext in SUPPORTED_IMAGE_EXTENSIONS) {
            if (extension == ext) {
                return true
            }
        }
        return false
    }

    /**
     * 检查文件是否为视频格式（与处理器保持一致）
     */
    public static func isVideoFile(filename: String): Bool {
        let parts = filename.split(".")
        if (parts.size <= 1) {
            return false
        }
        let extension = parts[parts.size - 1]
        for (ext in SUPPORTED_VIDEO_EXTENSIONS) {
            if (extension == ext) {
                return true
            }
        }
        return false
    }

    /**
     * 检查文件是否为媒体文件（图片或视频）
     */
    public static func isMediaFile(filename: String): Bool {
        return isImageFile(filename) || isVideoFile(filename)
    }

    /**
     * 获取文件扩展名（小写）
     */
    public static func getFileExtension(filePath: String): String {
        let pathParts = filePath.split("/")
        let fileName = if (pathParts.size > 0) {
            pathParts[pathParts.size - 1]
        } else {
            filePath
        }

        let nameParts = fileName.split(".")
        if (nameParts.size > 1) {
            let ext = nameParts[nameParts.size - 1]
            return ext.toAsciiLower()
        }
        return "tmp"
    }

    /**
     * 获取完整文件名（包含后缀）
     */
    public static func getFullFileName(filePath: String): String {
        let parts = filePath.split("/")
        if (parts.size > 0) {
            return parts[parts.size - 1]
        }
        return filePath
    }

    /**
     * 生成默认标题（去除文件后缀名）
     */
    public static func generateDefaultTitle(filePath: String): String {
        let fileName = getFullFileName(filePath)
        let parts = fileName.split(".")
        if (parts.size > 1) {
            var title = ""
            for (i in 0..(parts.size - 1)) {
                if (i > 0) {
                    title += "."
                }
                title += parts[i]
            }
            return title
        }
        return fileName
    }

    /**
     * 获取文件修改时间（毫秒时间戳）
     */
    public static func getArchiveFileModTime(filePath: String): Int64 {
        try {
            let actualPath = FileUtils.resolvePath(filePath)
            let path = Path(actualPath)
            let file = File(path, Read)
            file.close()

            return getTimeMillis()
        } catch (_: Exception) {
            return getTimeMillis()
        }
    }

    /**
     * 获取档案文件大小
     */
    public static func getArchiveFileSize(filePath: String): Int64 {
        try {
            let actualPath = FileUtils.resolvePath(filePath)
            let path = Path(actualPath)
            let file = File(path, Read)
            let fileInfo = file.info
            file.close()
            return fileInfo.size
        } catch (_: Exception) {
            return 0
        }
    }

    /**
     * 生成归档ID（基于SHA1）
     */
    public static func generateArchiveId(filePath: String): String {
        try {
            let fileSize = getArchiveFileSize(filePath)
            let fileModTime = getArchiveFileModTime(filePath)

            let content = filePath + fileModTime.toString() + fileSize.toString()

            // 使用 SHA1 算法生成哈希
            var sha1Instance = SHA1()
            sha1Instance.write(content.toArray())
            let hash: Array<Byte> = sha1Instance.finish()

            let result = toHexString(hash)
            return result
        } catch (_: Exception) {
            let fileName = getFullFileName(filePath)
            return "fallback_${fileName}"
        }
    }

    /**
     * 生成文件哈希值（基于SHA1）
     */
    public static func generateFileHash(filePath: String): String {
        try {
            let fileSize = getArchiveFileSize(filePath)
            let fileModTime = getArchiveFileModTime(filePath)

            let content = filePath + fileModTime.toString() + fileSize.toString()

            var sha1Instance = SHA1()
            sha1Instance.write(content.toArray())
            let hash: Array<Byte> = sha1Instance.finish()

            let result = toHexString(hash)
            return result
        } catch (_: Exception) {
            return "${filePath.hashCode()}"
        }
    }

    /**
     * 计算相对路径
     */
    public static func calculateRelativePath(fullPath: String, archiveBasePath: String): String {
        try {
            let parentDir = getParentDirectory(fullPath)

            let resolvedArchiveBasePath = FileUtils.resolvePath(archiveBasePath)
            let resolvedParentDir = FileUtils.resolvePath(parentDir)

            if (resolvedParentDir.startsWith(resolvedArchiveBasePath)) {
                let relativePath = resolvedParentDir.replace(resolvedArchiveBasePath, "")

                if (relativePath.startsWith("/")) {
                    let parts = relativePath.split("/")
                    var result = ""
                    var firstNonEmpty = true
                    for (i in 1..parts.size) {
                        if (parts[i].size > 0) {
                            if (!firstNonEmpty) {
                                result += "/"
                            }
                            result += parts[i]
                            firstNonEmpty = false
                        }
                    }
                    return result
                } else if (relativePath.size > 0) {
                    return relativePath
                } else {
                    return ""
                }
            } else {
                if (parentDir.startsWith(archiveBasePath)) {
                    let relativePath = parentDir.replace(archiveBasePath, "")

                    if (relativePath.startsWith("/")) {
                        let parts = relativePath.split("/")
                        var result = ""
                        var firstNonEmpty = true
                        for (i in 1..parts.size) {
                            if (parts[i].size > 0) {
                                if (!firstNonEmpty) {
                                    result += "/"
                                }
                                result += parts[i]
                                firstNonEmpty = false
                            }
                        }
                        return result
                    } else if (relativePath.size > 0) {
                        return relativePath
                    }
                }
                return ""
            }
        } catch (_: Exception) {
            return ""
        }
    }

    /**
     * 转换图片或视频为AVIF格式缩略图
     * 使用FFmpeg处理，支持图片和视频文件
     * 统一处理策略：宽度缩放到500px，高度裁剪到1000px（自适应，从顶部裁剪）
     */
    public static func convertImageToAvif(inputPath: String, outputPath: String, tempPath: String): ProcessResultData {
        try {
            let outputDir = FileUtils.getParentDirectory(outputPath)
            if (!directoryExists(outputDir)) {
                Directory.create(outputDir, recursive: true)
            }

            // Always use a dimension-free filter graph so we don't depend on ffprobe,
            // which can fail on some inputs even if other decoders could read them.
            //
            // After scaling to width=500, crop height to at most 1000 (top-aligned).
            // The comma in min() must be escaped for FFmpeg filter parsing.
            let vfFilter = "scale=500:-1,crop=500:min(ih\\,1000):0:0"

            // Prefer ImageMagick first (decode+resize+crop), then fall back to FFmpeg.
            // This helps with some images that FFmpeg/ffprobe struggles to decode reliably.
            let (imExitCode, imStderrStr) = runImageMagickToAvif(inputPath, outputPath, 500i64, 1000i64)
            if (imExitCode == 0) {
                return ProcessResultData(true, outputPath, "")
            }
            logger.warn("ImageMagick convert->avif failed; falling back to ffmpeg", ("inputPath", inputPath))

            // Then try FFmpeg directly.
            let (exitCode, stderrStr) = runFfmpegToAvif(inputPath, outputPath, vfFilter)
            if (exitCode == 0) {
                return ProcessResultData(true, outputPath, "")
            }

            // Last resort: ImageMagick renders a still PNG (first frame), then FFmpeg encodes AVIF.
            // This covers cases where IM can decode, but cannot encode AVIF (missing delegate),
            // or where FFmpeg can't decode animated formats that IM can read.
            let fallbackPngPath = FileUtils.joinPath(tempPath, "im_fallback.png")
            let (imExitCode2, imStderrStr2) = runImageMagickToPng(inputPath, fallbackPngPath)
            if (imExitCode2 == 0) {
                let (exitCode2, stderrStr2) = runFfmpegToAvif(fallbackPngPath, outputPath, vfFilter)
                if (exitCode2 == 0) {
                    return ProcessResultData(true, outputPath, "")
                }
                return ProcessResultData(false, "", "ImageMagick avif failed:\n${imStderrStr}\n---\nFFmpeg failed:\n${stderrStr}\n---\nImageMagick png ok; ffmpeg retry failed:\n${stderrStr2}")
            }

            return ProcessResultData(false, "", "ImageMagick avif failed:\n${imStderrStr}\n---\nFFmpeg failed:\n${stderrStr}\n---\nImageMagick png fallback failed:\n${imStderrStr2}")
        } catch (e: Exception) {
            return ProcessResultData(false, "", "Exception: ${e.message}")
        }
    }

    /**
     * Convert an image to an AVIF avatar.
     * Policy: scale to cover 256x256, then center-crop to 256x256.
     */
    public static func convertAvatarToAvif(inputPath: String, outputPath: String, tempPath: String): ProcessResultData {
        try {
            let outputDir = FileUtils.getParentDirectory(outputPath)
            if (!directoryExists(outputDir)) {
                Directory.create(outputDir, recursive: true)
            }

            // Scale to fill then center-crop.
            let vfFilter = "scale=256:256:force_original_aspect_ratio=increase,crop=256:256"

            // Prefer ImageMagick first.
            let (imExitCode, imStderrStr) = runImageMagickToAvifSquare(inputPath, outputPath, 256i64)
            if (imExitCode == 0) {
                return ProcessResultData(true, outputPath, "")
            }
            logger.warn("ImageMagick avatar convert->avif failed; falling back to ffmpeg", ("inputPath", inputPath))

            let (exitCode, stderrStr) = runFfmpegToAvif(inputPath, outputPath, vfFilter)
            if (exitCode == 0) {
                return ProcessResultData(true, outputPath, "")
            }

            // Fallback: render first frame to PNG then FFmpeg encode.
            let fallbackPngPath = FileUtils.joinPath(tempPath, "im_fallback.png")
            let (imExitCode2, imStderrStr2) = runImageMagickToPng(inputPath, fallbackPngPath)
            if (imExitCode2 == 0) {
                let (exitCode2, stderrStr2) = runFfmpegToAvif(fallbackPngPath, outputPath, vfFilter)
                if (exitCode2 == 0) {
                    return ProcessResultData(true, outputPath, "")
                }
                return ProcessResultData(false, "", "ImageMagick avif failed:\n${imStderrStr}\n---\nFFmpeg failed:\n${stderrStr}\n---\nImageMagick png ok; ffmpeg retry failed:\n${stderrStr2}")
            }

            return ProcessResultData(false, "", "ImageMagick avif failed:\n${imStderrStr}\n---\nFFmpeg failed:\n${stderrStr}\n---\nImageMagick png fallback failed:\n${imStderrStr2}")
        } catch (e: Exception) {
            return ProcessResultData(false, "", "Exception: ${e.message}")
        }
    }

    /**
     * Convert an image to a tag background AVIF.
     * Policy: scale to width=1200, then crop height to at most 400 (top-aligned).
     * This keeps the output lightweight for UI hover-cards while still being crisp.
     */
    public static func convertTagBackgroundToAvif(inputPath: String, outputPath: String, tempPath: String): ProcessResultData {
        try {
            let outputDir = FileUtils.getParentDirectory(outputPath)
            if (!directoryExists(outputDir)) {
                Directory.create(outputDir, recursive: true)
            }

            let vfFilter = "scale=1200:-1,crop=1200:min(ih\\,400):0:0"

            // Prefer ImageMagick first.
            let (imExitCode, imStderrStr) = runImageMagickToAvif(inputPath, outputPath, 1200i64, 400i64)
            if (imExitCode == 0) {
                return ProcessResultData(true, outputPath, "")
            }
            logger.warn("ImageMagick tag background convert->avif failed; falling back to ffmpeg", ("inputPath", inputPath))

            let (exitCode, stderrStr) = runFfmpegToAvif(inputPath, outputPath, vfFilter)
            if (exitCode == 0) {
                return ProcessResultData(true, outputPath, "")
            }

            // Fallback: render first frame to PNG then FFmpeg encode.
            let fallbackPngPath = FileUtils.joinPath(tempPath, "im_fallback.png")
            let (imExitCode2, imStderrStr2) = runImageMagickToPng(inputPath, fallbackPngPath)
            if (imExitCode2 == 0) {
                let (exitCode2, stderrStr2) = runFfmpegToAvif(fallbackPngPath, outputPath, vfFilter)
                if (exitCode2 == 0) {
                    return ProcessResultData(true, outputPath, "")
                }
                return ProcessResultData(false, "", "ImageMagick avif failed:\n${imStderrStr}\n---\nFFmpeg failed:\n${stderrStr}\n---\nImageMagick png ok; ffmpeg retry failed:\n${stderrStr2}")
            }

            return ProcessResultData(false, "", "ImageMagick avif failed:\n${imStderrStr}\n---\nFFmpeg failed:\n${stderrStr}\n---\nImageMagick png fallback failed:\n${imStderrStr2}")
        } catch (e: Exception) {
            return ProcessResultData(false, "", "Exception: ${e.message}")
        }
    }

    /**
     * Run FFmpeg to convert a single image/video frame to AVIF.
     */
    private static func runFfmpegToAvif(inputPath: String, outputPath: String, vfFilter: String): (Int64, String) {
        // Encoding AVIF can be extremely expensive with default encoder settings.
        // We try a "fast thumbnail" profile first (lower CPU, good-enough quality),
        // then fall back to the previous generic invocation for maximum compatibility.
        //
        // Notes:
        // - `libaom-av1` is widely available and supports `-cpu-used` / `-row-mt`.
        // - `-crf`+`-b:v 0` is the recommended quality control for AV1.
        // - `fast_bilinear` is cheaper for scaling and is fine for thumbnails.
        let fastArgs = [
            "-hide_banner",
            "-loglevel", "error",
            "-y",                    // 覆盖输出文件
            "-threads", "1",
            "-i", inputPath,         // 输入文件
            "-sws_flags", "fast_bilinear",
            "-vf", vfFilter,
            "-frames:v", "1",        // 只输出一帧
            "-pix_fmt", "yuv420p",
            "-c:v", "libaom-av1",
            "-still-picture", "1",
            "-row-mt", "1",
            "-cpu-used", "6",
            "-crf", "35",
            "-b:v", "0",
            "-map_metadata", "-1",   // 过滤元数据
            outputPath
        ]

        let processFast = launch(
            "ffmpeg",
            fastArgs,
            stdOut: ProcessRedirect.Pipe,
            stdErr: ProcessRedirect.Pipe
        )
        let (fastExitCode, _, fastStderr) = processFast.waitOutput()
        let fastStderrStr = try { String.fromUtf8(fastStderr) } catch (_: Exception) { "" }
        if (fastExitCode == 0) {
            return (0, fastStderrStr)
        }

        // Fallback: previous behavior.
        let process = launch(
            "ffmpeg",
            "-hide_banner",
            "-loglevel", "error",
            "-y",                    // 覆盖输出文件
            "-threads", "1",
            "-i", inputPath,         // 输入文件
            "-sws_flags", "fast_bilinear",
            "-vf", vfFilter,
            "-frames:v", "1",        // 只输出一帧
            "-q:v", "2",             // 质量设置
            "-map_metadata", "-1",   // 过滤元数据
            outputPath,
            stdOut: ProcessRedirect.Pipe,
            stdErr: ProcessRedirect.Pipe
        )
        let (exitCode, _, stderr) = process.waitOutput()
        let stderrStr = try { String.fromUtf8(stderr) } catch (_: Exception) { "" }

        // Preserve the fast attempt stderr as context for debugging.
        let combined = if (fastStderrStr.size > 0) { "fast profile failed:\n${fastStderrStr}\n---\n${stderrStr}" } else { stderrStr }
        return (exitCode, combined)
    }

    /**
     * Use ImageMagick to render the first frame of an image to a PNG file.
     * This is a best-effort fallback for animated formats that FFmpeg can't decode (e.g. some animated WEBP).
     */
    private static func runImageMagickToPng(inputPath: String, outputPngPath: String): (Int64, String) {
        let firstFrameInput = "${inputPath}[0]"
        let process = launch(
            "convert",
            firstFrameInput,
            "-strip",
            outputPngPath,
            stdOut: ProcessRedirect.Pipe,
            stdErr: ProcessRedirect.Pipe
        )
        let (exitCode, _, stderr) = process.waitOutput()
        let stderrStr = try { String.fromUtf8(stderr) } catch (_: Exception) { "" }
        return (exitCode, stderrStr)
    }

    /**
     * Use ImageMagick to render the first frame to an AVIF file.
     * Mirrors the thumbnail policy used by FFmpeg: scale to width, then crop height to at most maxHeight (top-aligned).
     */
    private static func runImageMagickToAvif(inputPath: String, outputAvifPath: String, width: Int64, maxHeight: Int64): (Int64, String) {
        let firstFrameInput = "${inputPath}[0]"

        // Best-effort: compute scaled height so we only crop when needed (avoid padding).
        var shouldCrop = false
        var probeStderr = ""
        try {
            let probe = launch(
                "identify",
                "-ping",
                "-format", "%w,%h",
                firstFrameInput,
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe
            )
            let (probeExitCode, probeStdout, probeStderrBytes) = probe.waitOutput()
            probeStderr = try { String.fromUtf8(probeStderrBytes) } catch (_: Exception) { "" }
            if (probeExitCode == 0) {
                let dims = String.fromUtf8(probeStdout).trimAscii()
                let parts = dims.split(",")
                if (parts.size >= 2) {
                    let w = try { Int64.parse(parts[0].trimAscii()) } catch (_: Exception) { 0i64 }
                    let h = try { Int64.parse(parts[1].trimAscii()) } catch (_: Exception) { 0i64 }
                    if (w > 0 && h > 0) {
                        let scaledHeight = h * width / w
                        shouldCrop = (scaledHeight > maxHeight)
                    }
                }
            }
        } catch (_: Exception) {
            // Ignore probe errors; we'll just skip conditional cropping.
        }

        var args = ArrayList<String>()
        args.add(firstFrameInput)
        args.add("-auto-orient")
        args.add("-strip")
        args.add("-resize"); args.add("${width.toString()}x")
        if (shouldCrop) {
            args.add("-gravity"); args.add("North")
            args.add("-crop"); args.add("${width.toString()}x${maxHeight.toString()}+0+0")
            args.add("+repage")
        }
        args.add(outputAvifPath)

        let process = launch(
            "convert",
            args.toArray(),
            stdOut: ProcessRedirect.Pipe,
            stdErr: ProcessRedirect.Pipe
        )
        let (exitCode, _, stderr) = process.waitOutput()
        let stderrStr = try { String.fromUtf8(stderr) } catch (_: Exception) { "" }
        let combined = if (probeStderr.size > 0) { "identify:\n${probeStderr}\n---\nconvert:\n${stderrStr}" } else { stderrStr }
        return (exitCode, combined)
    }

    /**
     * Use ImageMagick to generate a square avatar AVIF (center-crop).
     */
    private static func runImageMagickToAvifSquare(inputPath: String, outputAvifPath: String, size: Int64): (Int64, String) {
        let firstFrameInput = "${inputPath}[0]"

        var args = ArrayList<String>()
        args.add(firstFrameInput)
        args.add("-auto-orient")
        args.add("-strip")
        // Resize to cover the square, then crop centered.
        args.add("-resize"); args.add("${size.toString()}x${size.toString()}^")
        args.add("-gravity"); args.add("Center")
        args.add("-extent"); args.add("${size.toString()}x${size.toString()}")
        args.add(outputAvifPath)

        let process = launch(
            "convert",
            args.toArray(),
            stdOut: ProcessRedirect.Pipe,
            stdErr: ProcessRedirect.Pipe
        )
        let (exitCode, _, stderr) = process.waitOutput()
        let stderrStr = try { String.fromUtf8(stderr) } catch (_: Exception) { "" }
        return (exitCode, stderrStr)
    }

    /**
     * 动态构建FFmpeg滤镜
     */
    private static func buildFilter(inputPath: String): (String, Bool) {
        // 使用 ffprobe 获取图片尺寸
        let probeProcess = launch(
            "ffprobe",
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "csv=p=0",
            inputPath,
            stdOut: ProcessRedirect.Pipe,
            stdErr: ProcessRedirect.Pipe
        )
        let (probeExitCode, probeStdout, _) = probeProcess.waitOutput()

        if (probeExitCode != 0) {
            logger.error("Failed to get image dimensions", ("inputPath", inputPath))
            return ("", false)
        }

        let dimensions = String.fromUtf8(probeStdout).trimAscii()
        let parts = dimensions.split(",")
        if (parts.size < 2) {
            logger.error("Invalid image dimensions", ("dimensions", dimensions))
            return ("", false)
        }

        let width = try { Int64.parse(parts[0].trimAscii()) } catch (_: Exception) { 0i64 }
        let height = try { Int64.parse(parts[1].trimAscii()) } catch (_: Exception) { 0i64 }

        if (width <= 0 || height <= 0) {
            logger.error("Invalid image dimensions", ("width", width.toString()), ("height", height.toString()))
            return ("", false)
        }

        // 计算缩放后的高度
        let scaledHeight = height * 500 / width

        var vfFilter = ""
        if (scaledHeight >= 1000) {
            // 高度足够：先缩放，再裁剪
            vfFilter = "scale=500:-1,crop=500:1000:0:0"
        } else {
            // 高度不足：只缩放（保持宽高比，不裁剪）
            vfFilter = "scale=500:-1"
        }

        logger.debug("Built filter", ("width", width.toString()), ("height", height.toString()), ("scaledHeight", scaledHeight.toString()), ("filter", vfFilter))
        return (vfFilter, true)
    }


    // ==================== 私有工具方法 ====================

    /**
     * 获取当前时间戳（毫秒）
     */
    private static func getTimeMillis(): Int64 {
        return DateTime.now().toUnixTimeStamp().toSeconds() * 1000
    }

    /**
     * 获取父目录路径
     */
    private static func getParentDirectory(filePath: String): String {
        let parts = filePath.split("/")
        if (parts.size > 1) {
            var result = ""
            for (i in 0..parts.size - 1) {
                if (i == 0 && parts[i].size == 0) {
                    result += "/"
                } else {
                    if (result.size > 0 && result != "/") {
                        result += "/"
                    }
                    result += parts[i]
                }
            }
            return result
        } else if (parts.size == 1) {
            if (parts[0].size == 0) {
                return "/"
            }
        }
        return ""
    }

    /**
     * 检查目录是否存在
     */
    private static func directoryExists(path: String): Bool {
        try {
            let dirPath = Path(path)
            if (exists(dirPath)) {
                let fileInfo = FileInfo(dirPath)
                return fileInfo.isDirectory()
            }
            return false
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * 获取PDF文件的页数
     * 使用GhostScript命令: gs -q -dNOSAFER -sDEVICE=jpeg -f "$pdf_path" -c "pdfpagecount = quit"
     */
    public static func getPdfPageCount(pdfPath: String): Int32 {
        try {
            logger.debug("Getting PDF page count", ("pdf_path", pdfPath))
            let process = launch("gs", "-q", "-dNOSAFER", "-sDEVICE=nullpage", "-c", "(${pdfPath}) (r) file runpdfbegin pdfpagecount = quit", stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
            let (exitCode, stdout, stderr) = process.waitOutput()

            if (exitCode == 0 && stdout.size > 0) {
                let output = String.fromUtf8(stdout)
                let trimmed = output.trimAscii()
                let pageCount = try {
                    Int32.parse(trimmed)
                } catch (_: Exception) {
                    0i32
                }
                logger.debug("PDF page count", ("pdf_path", pdfPath), ("page_count", pageCount.toString()))
                return pageCount
            } else {
                let error = String.fromUtf8(stderr)
                logger.error("Failed to get PDF page count", ("pdf_path", pdfPath), ("error", error))
                return 0i32
            }
        } catch (e: Exception) {
            logger.error("Exception getting PDF page count", ("pdf_path", pdfPath), ("exception", e.message))
            return 0i32
        }
    }

    /**
     * 从PDF文件中提取指定页面为JPEG图片
     * 使用GhostScript命令: gs -dNOPAUSE -dFirstPage=$page -dLastPage=$page -sDEVICE=jpeg -r200 -o "outfile" "archive.pdf"
     * @param pdfPath PDF文件路径
     * @param pageNumber 页码（从1开始）
     * @param outputPath 输出图片路径
     * @return 是否成功提取
     */
    public static func extractPdfPage(pdfPath: String, pageNumber: Int32, outputPath: String): Bool {
        try {
            logger.debug("Extracting PDF page", ("pdf_path", pdfPath), ("page", pageNumber.toString()), ("output_path", outputPath))

            // 确保输出目录存在
            let outputDir = getParentDirectory(outputPath)
            if (!directoryExists(outputDir)) {
                Directory.create(outputDir, recursive: true)
            }

            let process = launch("gs", "-dNOPAUSE", "-dFirstPage=${pageNumber}", "-dLastPage=${pageNumber}", "-sDEVICE=jpeg", "-r200", "-o", outputPath, pdfPath, stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
            let (exitCode, _, stderr) = process.waitOutput()

            if (exitCode == 0) {
                logger.debug("Successfully extracted PDF page", ("pdf_path", pdfPath), ("page", pageNumber.toString()))
                return true
            } else {
                let error = String.fromUtf8(stderr)
                logger.error("Failed to extract PDF page", ("pdf_path", pdfPath), ("page", pageNumber.toString()), ("error", error))
                return false
            }
        } catch (e: Exception) {
            logger.error("Exception extracting PDF page", ("pdf_path", pdfPath), ("page", pageNumber.toString()), ("exception", e.message))
            return false
        }
    }
}
