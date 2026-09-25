package lanlu.shared.utils

import std.fs.*
import std.collection.*
import stdx.log.*
import rawdir_ffi.listRawEntries
import rawdir_ffi.tryDecodeBytes
import rawdir_ffi.isUtf8Bytes
import rawdir_ffi.renameRawEntry
import rawdir_ffi.lastListError

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

            // rawdir 裸字节枚举：单条非 UTF-8/GB18030 名只跳过该条，
            // 不再像 Directory.readFrom 那样整目录抛异常返回空。
            let rawEntries = match (listRawEntries(targetPath)) {
                case Some(entries) => entries
                case None =>
                    logger.warn("listDirectory: raw listing failed for ${path} (err=${lastListError})")
                    return Array<String>()
            }

            let files = ArrayList<String>()
            var undecodable = 0
            for (entry in rawEntries) {
                match (tryDecodeBytes(entry.nameBytes)) {
                    case Some(name) => files.add(name)
                    case None => undecodable += 1
                }
            }
            if (undecodable > 0) {
                logger.warn("listDirectory: ${undecodable} undecodable (non UTF-8/GB18030) entries skipped in ${path}")
            }
            return files.toArray()
        } catch (e: Exception) {
            logger.error("listDirectory: Exception listing directory ${path}: ${e.message}")
            return Array<String>()
        }
    }

    /**
     * 扫描入口规范化：把目录里「非法 UTF-8 但可 GB18030 解码」的条目
     * 重命名为解码后的 UTF-8 名（碰撞时加 " (#n)" 后缀），使后续所有
     * std.fs 路径操作（打开/入队/缩略图）都能按名字命中。
     *
     * - 只动非法 UTF-8 名：原生合法名与 undecodable 名一律不碰；
     * - 幂等：首轮规范化后再次调用返回空；
     * - 返回本次成功改名的新名列表（供调用方记日志）。
     */
    public static func normalizeDirectoryEntryNames(dirPath: String): Array<String> {
        let rawEntries = match (listRawEntries(dirPath)) {
            case Some(entries) => entries
            case None => return Array<String>()
        }

        // 碰撞集 = 盘上已是合法 UTF-8 的名字 + 本次已分配的新名。
        // 不含待改名条目自身的解码名（否则自己跟自己撞名）。
        let taken = HashSet<String>()
        for (entry in rawEntries) {
            if (!isUtf8Bytes(entry.nameBytes)) {
                continue
            }
            match (tryDecodeBytes(entry.nameBytes)) {
                case Some(name) => taken.add(name)
                case None => ()
            }
        }

        let renamed = ArrayList<String>()
        for (entry in rawEntries) {
            if (isUtf8Bytes(entry.nameBytes)) {
                continue
            }
            match (tryDecodeBytes(entry.nameBytes)) {
                case None => ()
                case Some(decoded) =>
                    tryNormalizeOne(dirPath, entry.nameBytes, decoded, taken, renamed)
            }
        }
        return renamed.toArray()
    }

    private static func tryNormalizeOne(dirBase: String, rawName: Array<UInt8>, decoded: String,
        taken: HashSet<String>, renamed: ArrayList<String>): Unit {
        var candidate = decoded
        var attempt = 1
        while (taken.contains(candidate) && attempt < 100) {
            candidate = withSuffixBeforeExtension(decoded, attempt)
            attempt += 1
        }
        if (taken.contains(candidate)) {
            logger.warn("normalizeDirectoryEntryNames: giving up after 99 collisions: ${decoded}")
            return
        }
        if (renameRawEntry(dirBase, rawName, candidate) == 0) {
            taken.add(candidate)
            renamed.add(candidate)
        } else {
            // 原始字节名不是合法 UTF-8 无法安全打印，记目标名与字节数定位。
            logger.warn("normalizeDirectoryEntryNames: rename to ${candidate} failed in ${dirBase} (raw name ${rawName.size} bytes)")
        }
    }

    /** "名.zip" -> "名 (#n).zip"；无扩展名则直接追加后缀。 */
    private static func withSuffixBeforeExtension(name: String, n: Int64): String {
        let bytes = name.toArray()
        var dot = -1
        var i = bytes.size - 1
        while (i >= 0) {
            // 0x2E ('.') 不会出现在 UTF-8 多字节序列中间
            if (bytes[i] == 0x2E) {
                dot = i
                break
            }
            i -= 1
        }
        let tag = " (#${n})"
        let out = ArrayList<UInt8>()
        if (dot > 0) {
            for (b in bytes[0..dot]) {
                out.add(b)
            }
            for (b in tag.toArray()) {
                out.add(b)
            }
            for (b in bytes[dot..bytes.size]) {
                out.add(b)
            }
        } else {
            for (b in bytes) {
                out.add(b)
            }
            for (b in tag.toArray()) {
                out.add(b)
            }
        }
        return String.fromUtf8(out.toArray())
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
