package lanlu.utils

import std.fs.*
import std.collection.*
import stdx.log.*

/**
 * 目录扫描工具类
 * 提供文件系统操作的基础方法
 */
public class DirectoryScanner {
    private static let logger = getLogger("directory_scanner")

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
        // NOTE: This is hot code during scans. Avoid O(n^2) array growth and excessive string logging.
        try {
            let dirPath = Path(path)
            if (!exists(dirPath)) {
                return Array<String>()
            }

            let fileInfo = FileInfo(dirPath)
            var targetPath = ""

            if (fileInfo.isDirectory()) {
                targetPath = path
            } else if (fileInfo.isSymbolicLink()) {
                try {
                    let linkTarget = SymbolicLink.readFrom(path, recursive: false)
                    if (!exists(linkTarget)) {
                        return Array<String>()
                    }
                    let targetInfo = FileInfo(linkTarget)
                    if (!targetInfo.isDirectory()) {
                        return Array<String>()
                    }
                    targetPath = linkTarget.toString()
                } catch (_: FSException) {
                    return Array<String>()
                }
            } else {
                return Array<String>()
            }

            let entries = Directory.readFrom(Path(targetPath))
            let files = ArrayList<String>()
            for (entry in entries) {
                try {
                    if (entry.isRegular() || entry.isDirectory() || entry.isSymbolicLink()) {
                        files.add(entry.name.toString())
                    }
                } catch (_: Exception) {
                    // Skip entries with invalid names or permissions.
                }
            }
            return files.toArray()
        } catch (e: Exception) {
            logger.error("listDirectory: Exception listing directory ${path}: ${e.message}")
            return Array<String>()
        }
    }

    /**
     * 拼接路径
     */
    public static func joinPath(base: String, part: String): String {
        // Keep a single source of truth for path joining semantics.
        return FileUtils.joinPath(base, part)
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
}
