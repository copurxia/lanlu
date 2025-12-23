package lrr4cj.utils

import std.fs.*
import std.process.*
import std.convert.*
import std.time.*
import std.collection.*
import stdx.crypto.digest.*
import stdx.encoding.hex.*
import stdx.log.*
import std.io.*

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

    public init(archivePath: String, cachePath: String, thumbnailPath: String) {
        this.archivePath = archivePath
        this.cachePath = cachePath
        this.thumbnailPath = thumbnailPath
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

    // 支持的图片格式
    public static let SUPPORTED_IMAGE_EXTENSIONS: Array<String> = [
        "jpg",
        "jpeg",
        "png",
        "gif",
        "bmp",
        "webp"
    ]

    // ==================== 从 ShinobuService 迁移的工具方法 ====================

    /**
     * 检查文件是否为图片格式
     */
    public static func isImageFile(filename: String): Bool {
        return filename.endsWith(".jpg") || filename.endsWith(".jpeg") || filename.endsWith(".png") ||
            filename.endsWith(".gif") || filename.endsWith(".bmp") || filename.endsWith(".webp") || filename.endsWith(
            ".JPG") || filename.endsWith(".JPEG") || filename.endsWith(".PNG") || filename.endsWith(".GIF") ||
            filename.endsWith(".BMP") || filename.endsWith(".WEBP")
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
     * 列出归档文件中的条目
     */
    public static func listArchiveEntries(archivePath: String): Array<String> {
        try {
            if (!fileExists(archivePath)) {
                logger.error("Archive file does not exist: ${archivePath}")
                return Array<String>()
            }

            logger.info("Attempting to list archive entries: ${archivePath}")

            // 使用 bsdtar 的 -tf 选项列出文件
            let process = launch("bsdtar", "-tf", archivePath, stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe)
            // let exitCode = process.wait()
            // 读取 stdout
            let reader = StringReader<InputStream>(process.stdOutPipe)
            let output = reader.readToEnd()

            // 打印原始输出内容
            println("Raw output from bsdtar:")
            println(output)

            // 将输出按行分割，去除空行和空白字符
            let lines = output.split('\n')
            var entries = ArrayList<String>()

            for (line in lines) {
                let trimmedLine = line.trimAscii()
                if (trimmedLine.size > 0) {
                    entries.add(trimmedLine)
                }
            }

            logger.info("Found ${entries.size} entries in archive (UTF-8)")
            return entries.toArray()
        } catch (e: Exception) {
            logger.error("Exception listing archive entries: ${e.message}")
            return Array<String>()
        }
    }

    /**
     * 转换图片为JPG格式
     */
    public static func convertImageToJpg(inputPath: String, outputPath: String, tempPath: String): ProcessResultData {
        try {
            let outputDir = FileUtils.getParentDirectory(outputPath)
            if (!directoryExists(outputDir)) {
                Directory.create(outputDir, recursive: true)
            }

            let resizedPath = joinPath(tempPath, "temp_resized.jpg")
            let (resizeExitCode, _, resizeStderr) = executeCommand(
                "convert",
                [inputPath, "-resize", "500x1000>", resizedPath]
            )

            if (resizeExitCode != 0) {
                let error = String.fromUtf8(resizeStderr)
                return ProcessResultData(false, "", error)
            }

            let (qualityExitCode, _, qualityStderr) = executeCommand(
                "convert",
                [resizedPath, "-quality", "85", outputPath]
            )

            // 清理临时文件
            try {
                if (fileExists(resizedPath)) {
                    let (rmExitCode, _, _) = executeCommand(
                        "rm",
                        ["-f", resizedPath]
                    )
                    if (rmExitCode != 0) {
                        // 静默处理
                    }
                }
            } catch (_: Exception) {
                // 静默处理
            }

            if (qualityExitCode == 0) {
                return ProcessResultData(true, outputPath, "")
            } else {
                let error = String.fromUtf8(qualityStderr)
                return ProcessResultData(false, "", error)
            }
        } catch (e: Exception) {
            return ProcessResultData(false, "", "Exception: ${e.message}")
        }
    }

    /**
     * 从压缩包中提取单个文件到内存流
     */
    public static func extractArchiveEntryToStream(archivePath: String, entryName: String): (Int64, Array<UInt8>, Array<UInt8>) {
        try {
            let bsdtarPath = "/usr/bin/bsdtar"
            // 使用shell执行以正确处理带特殊字符的路径
            let command = "${shellQuote(bsdtarPath)} -xO -f ${shellQuote(archivePath)} ${shellQuote(entryName)}"
            logger.info("Extracting entry from archive", ("archive_path", archivePath), ("entry_name", entryName),
                ("command", command))

            let result = executeShellCommand(command)

            if (result[0] == 0) {
                logger.info("Successfully extracted entry", ("archive_path", archivePath), ("entry_name", entryName),
                    ("output_size", result[1].size.toString()))
            } else {
                // 安全地转换错误信息（stderr 通常是文本）
                var errorStr = ""
                try {
                    errorStr = String.fromUtf8(result[2])
                } catch (_: Exception) {
                    errorStr = "Failed to decode error output (binary data)"
                }
                logger.error("Failed to extract entry", ("archive_path", archivePath), ("entry_name", entryName),
                    ("exit_code", result[0].toString()), ("error", errorStr))
            }
            return result
        } catch (e: Exception) {
            logger.error("Exception while extracting entry", ("archive_path", archivePath), ("entry_name", entryName),
                ("exception", e.message))
            return (1, [], [])
        }
    }

    /**
     * 从压缩包中提取单个文件到指定路径
     * 使用 extractArchiveEntryToStream 实现
     */
    public static func extractArchiveEntry(archivePath: String, entryName: String, outputPath: String): Bool {
        try {
            // 验证输入参数
            if (entryName.size == 0) {
                logger.error("Empty entry name provided for extraction", ("archive_path", archivePath))
                return false
            }

            logger.info("Extracting entry", ("archive_path", archivePath), ("entry_name", entryName),
                ("entry_length", entryName.size.toString()), ("output_path", outputPath))

            // 使用 extractArchiveEntryToStream 提取文件到内存流
            let (exitCode, stdout, stderr) = extractArchiveEntryToStream(archivePath, entryName)

            if (exitCode == 0) {
                // 检查是否成功提取了数据
                if (stdout.size == 0) {
                    logger.error("Extracted file is empty", ("archive_path", archivePath), ("entry", entryName))
                    return false
                }

                // 确保输出目录存在
                let outputDir = getParentDirectory(outputPath)
                if (!directoryExists(outputDir)) {
                    Directory.create(outputDir, recursive: true)
                }

                // 写入文件
                let filePath = Path(outputPath)
                let file = File(filePath, Write)
                file.write(stdout)
                file.close()

                logger.info("Successfully extracted entry", ("archive_path", archivePath), ("entry", entryName),
                    ("output_path", outputPath), ("size", stdout.size.toString()))
                return true
            } else {
                // 记录错误信息
                var errorStr = ""
                try {
                    errorStr = String.fromUtf8(stderr)
                } catch (_: Exception) {
                    errorStr = "Failed to decode error output"
                }
                logger.error("Failed to extract entry", ("archive_path", archivePath), ("entry", entryName),
                    ("output_path", outputPath), ("exit_code", exitCode.toString()), ("error", errorStr))
                return false
            }
        } catch (e: Exception) {
            logger.error("Exception while extracting entry", ("archive_path", archivePath), ("entry", entryName),
                ("output_path", outputPath), ("exception", e.message))
            return false
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
     * 检查文件是否存在
     */
    private static func fileExists(path: String): Bool {
        try {
            let filePath = Path(path)
            return exists(filePath)
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * 拼接路径
     */
    private static func joinPath(base: String, part: String): String {
        if (base.endsWith("/")) {
            if (part.startsWith("/")) {
                // 移除 part 的前导斜杠
                let parts = part.split("/")
                var rest = ""
                for (i in 1..parts.size) {
                    if (i > 1) {
                        rest += "/"
                    }
                    rest += parts[i]
                }
                return base + rest
            }
            return base + part
        } else {
            if (part.startsWith("/")) {
                return base + part
            }
            return base + "/" + part
        }
    }

    /**
     * 执行命令并获取输出
     */
    private static func executeCommand(command: String, args: Array<String>): (Int32, Array<UInt8>, Array<UInt8>) {
        try {
            if (args.size == 0) {
                let process = launch(command, stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            } else if (args.size == 1) {
                let process = launch(command, args[0], stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            } else if (args.size == 2) {
                let process = launch(command, args[0], args[1], stdOut: ProcessRedirect.Pipe,
                    stdErr: ProcessRedirect.Pipe)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            } else if (args.size == 3) {
                let process = launch(command, args[0], args[1], args[2], stdOut: ProcessRedirect.Pipe,
                    stdErr: ProcessRedirect.Pipe)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            } else if (args.size == 4) {
                let process = launch(command, args[0], args[1], args[2], args[3], stdOut: ProcessRedirect.Pipe,
                    stdErr: ProcessRedirect.Pipe)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            } else {
                // 对于更多参数，使用 shell 执行
                var fullCmd = command
                for (arg in args) {
                    fullCmd += " " + arg
                }
                let process = launch("/bin/sh", "-c", fullCmd, stdOut: ProcessRedirect.Pipe,
                    stdErr: ProcessRedirect.Pipe)
                let exitCode = process.wait()
                return (Int32(exitCode), Array<UInt8>(), Array<UInt8>())
            }
        } catch (_: Exception) {
            return (1, [], [])
        }
    }

    /**
     * 执行shell命令并获取输出
     */
    private static func executeShellCommand(command: String): (Int64, Array<UInt8>, Array<UInt8>) {
        try {
            logger.debug("About to execute shell command", ("command", command))
            let process = launch("/bin/sh", "-c", command, stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
            return process.waitOutput()
        } catch (e: Exception) {
            logger.error("Exception in executeShellCommand", ("command", command), ("exception", e.message))
            return (1, [], [])
        }
    }

    /**
     * Shell转义单个字符串参数
     * 使用单引号包裹，这是最安全的方式，因为单引号内的所有字符都按字面意义处理
     */
    private static func shellQuote(s: String): String {
        if (s.size == 0) {
            return "''"
        }

        // 检查是否包含单引号
        let bytes = s.toArray()
        var hasSingleQuote = false
        for (i in 0..bytes.size) {
            if (bytes[i] == 0x27) { // 单引号 ASCII 码
                hasSingleQuote = true
                break
            }
        }

        // 如果没有单引号，直接用单引号包裹（最安全，支持所有 UTF-8 字符）
        if (!hasSingleQuote) {
            return "'" + s + "'"
        }

        // 如果有单引号，需要特殊处理：将每个 ' 替换为 '\''
        // 方法：先分割字符串，然后用 '\'' 连接
        // 例如：a'b'c -> 'a'\''b'\''c'
        var result = "'"
        var lastPos = 0
        for (i in 0..bytes.size) {
            if (bytes[i] == 0x27) { // 找到单引号
                // 添加从 lastPos 到当前位置的子串
                if (i > lastPos) {
                    let startPos = lastPos
                    let subBytes = Array<UInt8>(i - startPos, {idx => bytes[startPos + idx]})
                    result += String.fromUtf8(subBytes)
                }
                // 添加转义的单引号
                result += "'\\\''"
                lastPos = i + 1
            }
        }
        // 添加剩余部分
        if (lastPos < bytes.size) {
            let startPos = lastPos
            let subBytes = Array<UInt8>(bytes.size - startPos, {idx => bytes[startPos + idx]})
            result += String.fromUtf8(subBytes)
        }
        result += "'"
        return result
    }
}
