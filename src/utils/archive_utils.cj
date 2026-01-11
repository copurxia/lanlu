package lrr4cj.utils

import std.fs.*
import std.process.*
import std.convert.*
import std.time.*
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
     */
    public static func convertImageToAvif(inputPath: String, outputPath: String, tempPath: String): ProcessResultData {
        try {
            let outputDir = FileUtils.getParentDirectory(outputPath)
            if (!directoryExists(outputDir)) {
                Directory.create(outputDir, recursive: true)
            }

            // 使用FFmpeg进行转换，-frames:v 1 确保只取一帧（对视频有效，对图片无影响）
            // scale滤镜：缩放到最大500x1000，保持宽高比
            // -q:v 设置质量（1-31，越小质量越高，2约等于85%质量）
            let process = launch(
                "ffmpeg",
                "-y",                    // 覆盖输出文件
                "-threads", "1",
                "-i", inputPath,         // 输入文件
                "-vf", "scale='min(500,iw)':'min(1000,ih)':force_original_aspect_ratio=decrease:threads=1",
                "-frames:v", "1",        // 只输出一帧
                "-q:v", "2",             // 质量设置
                "-map_metadata", "-1",   // 过滤元数据
                outputPath,
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe
            )
            let (exitCode, _, stderr) = process.waitOutput()

            if (exitCode == 0) {
                return ProcessResultData(true, outputPath, "")
            } else {
                let error = String.fromUtf8(stderr)
                return ProcessResultData(false, "", error)
            }
        } catch (e: Exception) {
            return ProcessResultData(false, "", "Exception: ${e.message}")
        }
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
