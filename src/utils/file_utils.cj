package lrr4cj.utils

import std.fs.*
import stdx.log.*

/**
 * 文件工具类
 */
public class FileUtils {
    
    /**
     * 获取文件扩展名
     */
    public static func getFileExtension(fileName: String): String {
        let ext = fileName.split(".")
        if (ext.size > 1) {
            return "." + ext[ext.size - 1]
        }
        return ""
    }
    
    /**
     * 获取不包含点的文件扩展名
     */
    public static func getFileExtensionWithoutDot(fileName: String): String {
        let ext = fileName.split(".")
        if (ext.size > 1) {
            return ext[ext.size - 1]
        }
        return ""
    }
    
    /**
     * 连接路径
     */
    public static func joinPath(base: String, part: String): String {
        if (base.endsWith("/")) {
            return base + part
        } else {
            return "${base}/${part}"
        }
    }
    
    /**
     * 检查是否为支持的档案格式
     */
    public static func isSupportedArchiveFormat(fileName: String): Bool {
        let ext = getFileExtension(fileName)
        let supportedFormats = [".zip", ".rar", ".7z", ".tar", ".gz", ".pdf", ".epub", ".mobi", ".cbz", ".cbr"]
        return supportedFormats.contains(ext)
    }
    
    /**
     * 确保目录存在，如果不存在则创建
     */
    public static func ensureDirectoryExists(path: Path): Unit {
        try {
            if (!exists(path)) {
                // 使用 Directory.create 创建目录
                Directory.create(path, recursive: true)
                getLogger("file_utils").info("Created directory", ("path", path.toString()))
            }
        } catch (e: Exception) {
            getLogger("file_utils").error("Failed to create directory", ("path", path.toString()), ("error", e.message))
        }
    }
    
    /**
     * 格式化文件大小为可读字符串
     */
    public static func formatFileSize(bytes: Int64): String {
        if (bytes < 1024) {
            return "${bytes} B"
        } else if (bytes < 1024 * 1024) {
            return "${bytes / 1024} KB"
        } else if (bytes < 1024 * 1024 * 1024) {
            return "${bytes / (1024 * 1024)} MB"
        } else {
            return "${bytes / (1024 * 1024 * 1024)} GB"
        }
    }
    
    /**
     * 解析路径，如果是软链接则返回其目标路径，否则返回原路径
     * 支持递归解析软链接（最多10层，防止循环）
     */
    public static func resolvePath(path: String): String {
        getLogger("file_utils").debug("=== RESOLVE PATH START ===", ("original_path", path))

        const MAX_SYMLINK_DEPTH = 10
        var currentPath = path
        var depth = 0

        try {
            while (depth < MAX_SYMLINK_DEPTH) {
                getLogger("file_utils").debug("resolvePath: Level", ("depth", depth.toString()), ("current_path", currentPath.toString()))

                let filePath = Path(currentPath)
                if (!exists(filePath)) {
                    getLogger("file_utils").debug("resolvePath: Path does not exist", ("path", currentPath.toString()))
                    break
                }

                let fileInfo = FileInfo(filePath)
                getLogger("file_utils").debug("resolvePath: FileInfo", ("is_symbolic_link", fileInfo.isSymbolicLink().toString()), ("is_directory", fileInfo.isDirectory().toString()))

                // 如果是软链接，获取其目标路径
                if (fileInfo.isSymbolicLink()) {
                    try {
                        let targetPath = SymbolicLink.readFrom(currentPath, recursive: false)
                        let newTarget = targetPath.toString()
                        getLogger("file_utils").debug("resolvePath: Symlink target", ("target", newTarget.toString()))

                        // 检查是否为绝对路径
                        if (newTarget.startsWith("/")) {
                            currentPath = newTarget
                            getLogger("file_utils").debug("resolvePath: Absolute target", ("new_path", currentPath.toString()))
                        } else {
                            // 相对路径需要基于当前目录的父目录进行解析
                            let parentDir = getParentDirectory(currentPath)
                            currentPath = joinPath(parentDir, newTarget)
                            getLogger("file_utils").debug("resolvePath: Relative target", ("parent", parentDir.toString()), ("new_path", currentPath.toString()))
                        }

                        depth++
                        getLogger("file_utils").debug("resolvePath: Resolved symlink", ("depth", depth.toString()), ("path", currentPath.toString()))
                    } catch (e: FSException) {
                        // 如果解析失败，返回当前路径
                        getLogger("file_utils").warn("resolvePath: Failed to resolve symlink", ("path", currentPath.toString()), ("error", e.message))
                        break
                    }
                } else {
                    // 不是软链接，停止解析
                    getLogger("file_utils").debug("resolvePath: Not a symlink", ("final_path", currentPath.toString()))
                    break
                }
            }

            if (depth >= MAX_SYMLINK_DEPTH) {
                getLogger("file_utils").warn("resolvePath: Maximum symlink depth reached", ("max_depth", MAX_SYMLINK_DEPTH.toString()), ("path", path))
            }

            getLogger("file_utils").debug("=== RESOLVE PATH END ===", ("final_resolved_path", currentPath.toString()))
            return currentPath
        } catch (e: Exception) {
            // 如果出错，返回原路径
            getLogger("file_utils").error("resolvePath: Error resolving path", ("path", path), ("error", e.message))
            getLogger("file_utils").debug("=== RESOLVE PATH END ===")
            return path
        }
    }

    /**
     * 获取父目录路径
     */
    public static func getParentDirectory(filePath: String): String {
        let parts = filePath.split("/")
        if (parts.size > 1) {
            var result = ""
            for (i in 0..parts.size - 1) {
                if (result.size > 0) {
                    result += "/"
                }
                result += parts[i]
            }
            return result
        }
        return ""
    }
}

/**
 * 图像处理工具类
 */
public class ImageUtils {
    
    /**
     * 检查是否为支持的图像格式
     */
    public static func isSupportedImageFormat(fileName: String): Bool {
        let ext = FileUtils.getFileExtension(fileName)
        let supportedFormats = [".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"]
        return supportedFormats.contains(ext)
    }
    
    /**
     * 生成缩略图路径
     */
    public static func generateThumbnailPath(archiveId: String, page: Int32): String {
        let thumbDir = "./public/thumb/${archiveId}"
        return FileUtils.joinPath(thumbDir, "${page}.jpg")
    }
    
    /**
     * 获取缩略图URL路径
     */
    public static func getThumbnailUrl(archiveId: String, page: Int32): String {
        return "/thumb/${archiveId}/${page}.jpg"
    }
    
}

/**
 * 字符串工具类
 */
public class StringUtils {
    
    /**
     * 检查字符串是否为空
     */
    public static func isEmpty(str: String): Bool {
        return str.size == 0
    }
    
    /**
     * 安全地获取字符串，如果为空则返回默认值
     */
    public static func safeString(str: String, defaultValue: String): String {
        if (isEmpty(str)) {
            return defaultValue
        } else {
            return str
        }
    }
    
    /**
     * 将字符串数组转换为逗号分隔的字符串
     */
    public static func arrayToString(arr: Array<String>): String {
        if (arr.size == 0) {
            return ""
        }
        var result = ""
        for (i in 0..arr.size) {
            result += arr[i]
            if (i < arr.size - 1) {
                result += ", "
            }
        }
        return result
    }
    
    /**
     * 将逗号分隔的字符串转换为字符串数组
     */
    public static func stringToArray(str: String): Array<String> {
        if (str.size == 0) {
            return []
        }
        return str.split(",")
    }
}