package lrr4cj.utils

import std.fs.*
import stdx.log.*

/**
 * 文件工具类
 */
public class FileUtils {

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

