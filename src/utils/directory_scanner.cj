package lrr4cj.utils

import std.fs.*
import std.convert.*
import stdx.log.*

/**
 * 目录扫描工具类
 * 负责递归扫描目录中的压缩包文件和文件夹归档
 */
public class DirectoryScanner {
    private static let logger = getLogger("directory_scanner")

    // 支持的压缩包格式
    private static let SUPPORTED_ARCHIVE_EXTENSIONS: Array<String> = [
        "zip", "rar", "7z", "tar", "cbz", "cbr", "cb7", "cbt", "tar.gz", "tgz", "pdf", "epub"
    ]

    // 支持的图片格式
    private static let SUPPORTED_IMAGE_EXTENSIONS: Array<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp"
    ]

    /**
     * 递归查找压缩包文件和文件夹归档
     */
    public static func findArchiveFiles(dirPath: String): Array<String> {
        var result: Array<String> = Array<String>()

        try {
            logger.info("=== findArchiveFiles: Starting scan of ${dirPath} ===")

            if (!directoryExists(dirPath)) {
                logger.error("Directory does not exist: ${dirPath}")
                return result
            }

            let entries = listDirectory(dirPath)
            logger.info("Scanning directory ${dirPath}, found ${entries.size.toString()} entries")

            if (entries.size == 0) {
                logger.warn("Directory ${dirPath} is empty")
            }

            for (entry in entries) {
                let fullPath = joinPath(dirPath, entry)

                // 记录处理的每个条目（每10个输出一次）
                if (result.size % 10 == 0) {
                    logger.info("Processing entry ${entry}, current archive count: ${result.size.toString()}")
                }

                if (directoryExists(fullPath)) {
                    logger.info("Entry ${entry} is a directory, checking if it contains images...")
                    // 检查目录是否包含图片文件（可能是folder类型的archive）
                    if (directoryContainsImages(fullPath)) {
                        logger.info("Directory ${entry} contains images, treating as folder archive: ${fullPath}")
                        result = addFileToArray(result, fullPath)
                    }

                    // 递归处理子目录
                    logger.info("Recursing into subdirectory: ${entry}")
                    let subFiles = findArchiveFiles(fullPath)
                    result = combineArrays(result, subFiles)

                    if (subFiles.size > 0) {
                        logger.info("Completed scanning subdirectory: ${entry}, found ${subFiles.size.toString()} archives")
                    }
                } else if (fileExists(fullPath)) {
                    logger.info("Entry ${entry} is a file, checking extension...")
                    // 检查文件扩展名
                    let ext = getFileExtension(fullPath)

                    var isSupported = false
                    for (supportedExt in SUPPORTED_ARCHIVE_EXTENSIONS) {
                        if (ext == supportedExt) {
                            isSupported = true
                            break
                        }
                    }

                    if (isSupported) {
                        logger.info("Found supported archive: ${fullPath} (ext: ${ext})")
                        result = addFileToArray(result, fullPath)
                    } else {
                        logger.debug("Skipping unsupported file: ${fullPath} (ext: ${ext})")
                    }
                } else {
                    logger.warn("Entry ${entry} is neither file nor directory, skipping")
                }
            }

            logger.info("=== Completed scanning directory ${dirPath}, total archives: ${result.size.toString()} ===")
        } catch (e: Exception) {
            logger.error("Error scanning directory ${dirPath}: ${e.message}")
        }

        return result
    }

    /**
     * 合并数组
     */
    public static func combineArrays(arr1: Array<String>, arr2: Array<String>): Array<String> {
        let result = Array<String>(arr1.size + arr2.size, { i =>
            if (i < arr1.size) {
                arr1[i]
            } else {
                arr2[i - arr1.size]
            }
        })
        return result
    }

    /**
     * 添加文件到数组
     */
    public static func addFileToArray(arr: Array<String>, file: String): Array<String> {
        let result = Array<String>(arr.size + 1, { i =>
            if (i < arr.size) {
                arr[i]
            } else {
                file
            }
        })
        return result
    }

    /**
     * 检查路径是否为目录（支持软链接）
     */
    public static func isDirectory(path: String): Bool {
        return directoryExists(path)
    }

    /**
     * 检查目录是否存在（支持软链接）
     */
    public static func directoryExists(path: String): Bool {
        let dirPath = Path(path)

        // 先检查路径是否存在
        if (!exists(dirPath)) {
            return false
        }

        let fileInfo = FileInfo(dirPath)

        // 如果是软链接，获取其目标并检查目标目录
        if (fileInfo.isSymbolicLink()) {
            try {
                let targetPath = SymbolicLink.readFrom(path, recursive: false)
                if (exists(targetPath)) {
                    let targetFileInfo = FileInfo(targetPath)
                    return targetFileInfo.isDirectory()
                }
                return false
            } catch (_: FSException) {
                return false
            }
        }

        return fileInfo.isDirectory()
    }

    /**
     * 检查文件是否存在（支持软链接）
     */
    public static func fileExists(path: String): Bool {
        let filePath = Path(path)

        // 先检查路径是否存在
        if (!exists(filePath)) {
            return false
        }

        let fileInfo = FileInfo(filePath)

        // 如果是软链接，获取其目标并检查目标文件
        if (fileInfo.isSymbolicLink()) {
            try {
                let targetPath = SymbolicLink.readFrom(path, recursive: false)
                if (exists(targetPath)) {
                    let targetFileInfo = FileInfo(targetPath)
                    return targetFileInfo.isRegular()
                }
                return false
            } catch (_: FSException) {
                return false
            }
        }

        return fileInfo.isRegular()
    }

    /**
     * 列出目录内容（支持软链接）
     */
    public static func listDirectory(path: String): Array<String> {
        try {
            let dirPath = Path(path)
            var files = Array<String>()

            logger.info("listDirectory: Checking path ${path}")

            if (exists(dirPath)) {
                let fileInfo = FileInfo(dirPath)
                var isDirectory = false
                var isSymlink = false

                if (fileInfo.isDirectory()) {
                    isDirectory = true
                    logger.info("listDirectory: ${path} is a regular directory")
                } else if (fileInfo.isSymbolicLink()) {
                    isSymlink = true
                    logger.info("listDirectory: ${path} is a symbolic link")

                    try {
                        let targetPath = SymbolicLink.readFrom(path, recursive: false)
                        logger.info("listDirectory: Symlink ${path} points to ${targetPath.toString()}")
                        if (exists(targetPath)) {
                            let targetFileInfo = FileInfo(targetPath)
                            isDirectory = targetFileInfo.isDirectory()
                            logger.info("listDirectory: Symlink target is ${if (isDirectory) {"directory"} else {"NOT a directory"}}")
                        }
                    } catch (_: FSException) {
                        isDirectory = false
                        logger.warn("listDirectory: Failed to read symlink ${path}")
                    }
                } else {
                    logger.warn("listDirectory: ${path} is neither directory nor symlink")
                }

                if (isDirectory) {
                    let targetPath: String
                    if (isSymlink) {
                        targetPath = SymbolicLink.readFrom(path, recursive: false).toString()
                        logger.info("listDirectory: Using symlink target path for listing: ${targetPath}")
                    } else {
                        targetPath = path
                    }

                    let entries = Directory.readFrom(Path(targetPath))
                    logger.info("listDirectory: Found ${entries.size} entries in ${targetPath}")

                    for (entry in entries) {
                        if (entry.isRegular() || entry.isDirectory() || entry.isSymbolicLink()) {
                            files = addFileToArray(files, entry.name.toString())
                        }
                    }
                    logger.info("listDirectory: Returning ${files.size} files/dirs/symlinks")
                    return files
                } else {
                    logger.warn("listDirectory: ${path} is not a directory, returning empty array")
                }
            } else {
                logger.error("listDirectory: Path ${path} does not exist")
            }
            return Array<String>()
        } catch (e: Exception) {
            logger.error("listDirectory: Exception listing directory ${path}: ${e.message}")
            return Array<String>()
        }
    }

    /**
     * 拼接路径
     */
    public static func joinPath(base: String, part: String): String {
        let cleanBase = if (base.endsWith("/")) {
            let parts = base.split("")
            var result = ""
            for (i in 0..parts.size - 1) {
                result += parts[i]
            }
            result
        } else {
            base
        }
        let cleanPart = if (part.startsWith("/")) {
            let parts = part.split("")
            var result = ""
            for (i in 1..parts.size) {
                result += parts[i]
            }
            result
        } else {
            part
        }

        if (cleanPart.size > 0) {
            return "${cleanBase}/${cleanPart}"
        } else {
            return cleanBase
        }
    }

    /**
     * 获取文件扩展名（小写）
     */
    public static func getFileExtension(filePath: String): String {
        let parts = filePath.split("/")
        let fileName = if (parts.size > 0) { parts[parts.size - 1] } else { filePath }
        let nameParts = fileName.split(".")
        if (nameParts.size > 1) {
            let ext = nameParts[nameParts.size - 1]
            return ext.toAsciiLower()
        }
        return ""
    }

    /**
     * 检查目录是否包含图片文件
     */
    public static func directoryContainsImages(dirPath: String): Bool {
        try {
            if (!directoryExists(dirPath)) {
                return false
            }

            let entries = listDirectory(dirPath)
            for (entry in entries) {
                let fullPath = joinPath(dirPath, entry)
                if (fileExists(fullPath)) {
                    let ext = getFileExtension(fullPath)
                    for (imageExt in SUPPORTED_IMAGE_EXTENSIONS) {
                        if (ext == imageExt) {
                            return true
                        }
                    }
                }
            }
            return false
        } catch (e: Exception) {
            logger.error("Error checking directory for images", ("path", dirPath), ("error", e.message))
            return false
        }
    }
}
