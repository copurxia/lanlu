package lrr4cj.archivehandler

import std.fs.*
import std.collection.*
import archive_ffi.Archive
import lrr4cj.models.ArchiveTypes
import lrr4cj.utils.DirectoryScanner
import lrr4cj.utils.NaturalSort

/**
 * 内存数据读取器 - 从已加载的数据中分块读取
 */
public class MemoryEntryReader <: EntryReader {
    private let data: Array<UInt8>
    private var offset: Int64 = 0
    private var closed: Bool = false

    public init(data: Array<UInt8>) {
        this.data = data
    }

    public func getSize(): Int64 {
        return Int64(data.size)
    }

    public func read(buffer: Array<Byte>): Int64 {
        if (closed || offset >= Int64(data.size)) {
            return 0
        }
        let remaining = Int64(data.size) - offset
        let toRead = if (Int64(buffer.size) < remaining) { Int64(buffer.size) } else { remaining }
        for (i in 0..toRead) {
            buffer[i] = data[offset + i]
        }
        offset += toRead
        return toRead
    }

    public func close(): Unit {
        closed = true
    }
}

/**
 * 压缩包类型处理器
 * 支持: zip, rar, 7z, tar, cbz, cbr, cb7, cbt, tar.gz, tgz
 */
public class ArchiveFileHandler <: ArchiveHandler {

    public func getType(): String {
        return ArchiveTypes.ARCHIVE
    }
    public func listEntries(archivePath: String): Array<String> {
        return Archive.listEntries(archivePath)
    }

    public func extractEntryToStream(archivePath: String, entryName: String): (Int64, Array<UInt8>, Array<UInt8>){
        return (0i64,Archive.extractEntry(archivePath, entryName), "success".toArray())
    }

    public func getEntryReader(archivePath: String, entryName: String): (Int64, Option<EntryReader>, String) {
        try {
            let data = Archive.extractEntry(archivePath, entryName)
            if (data.size == 0) {
                return (1i64, None, "Entry not found or empty: ${entryName}")
            }
            let reader = MemoryEntryReader(data)
            return (0i64, Some(reader), "")
        } catch (e: Exception) {
            return (1i64, None, "Exception extracting entry: ${e.message}")
        }
    }

    public func extractEntryToFile(archivePath: String, entryName: String, outputPath: String): Bool {
        try {
            if (entryName.size == 0) {
                return false
            }

            let (exitCode, stdout, _) = extractEntryToStream(archivePath, entryName)

            if (exitCode == 0 && stdout.size > 0) {
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
                return true
            }
            return false
        } catch (_: Exception) {
            return false
        }
    }

    public func getMediaCount(archivePath: String): Int32 {
        let entries = listEntries(archivePath)
        var count: Int32 = 0
        for (entry in entries) {
            if (isMediaFile(entry)) {
                count++
            }
        }
        return count
    }

    public func getFirstImage(archivePath: String): (String, String) {
        let entries = listEntries(archivePath)
        // 筛选图片文件并排序
        let imageEntries = ArrayList<String>()
        for (entry in entries) {
            if (isImageFile(entry)) {
                imageEntries.add(entry)
            }
        }
        if (imageEntries.isEmpty()) {
            return ("", "")
        }
        NaturalSort.sortStrings(imageEntries)
        return (imageEntries[0], "")
    }

    // 支持的压缩包扩展名
    private static let SUPPORTED_EXTENSIONS: Array<String> = [
        "zip", "rar", "7z", "tar", "cbz", "cbr", "cb7", "cbt", "gz", "tgz"
    ]

    // 允许的图片文件扩展名（与 folder_handler 保持一致）
    private static let ALLOWED_IMAGE_EXTENSIONS: Array<String> = [
        "avif", "jpg", "jpeg", "png", "webp", "gif", "AVIF", "JPG", "JPEG", "PNG", "WEBP", "GIF"
    ]

    // 允许的视频文件扩展名（与 folder_handler 保持一致）
    private static let ALLOWED_VIDEO_EXTENSIONS: Array<String> = [
        "mp4", "webm", "mkv", "avi", "mov", "m4v", "MP4", "WEBM", "MKV", "AVI", "MOV", "M4V"
    ]

    public func canHandle(filePath: String): Bool {
        if (DirectoryScanner.isDirectory(filePath)) {
            return false
        }
        let ext = getFileExtension(filePath).toAsciiLower()
        for (supportedExt in SUPPORTED_EXTENSIONS) {
            if (ext == supportedExt) {
                return true
            }
        }
        return false
    }

    public func getCoverImage(archivePath: String): (Int64, Array<UInt8>, Array<UInt8>) {
        let (entryName, _) = getFirstImage(archivePath)
        if (entryName.isEmpty()) {
            return (1i64, Array<UInt8>(), "No image found".toArray())
        }
        return extractEntryToStream(archivePath, entryName)
    }

    public func listEntriesWithTitle(archivePath: String): Array<(String, String)> {
        let entries = listEntries(archivePath)
        var result = ArrayList<(String, String)>()
        for (entry in entries) {
            // 只返回媒体文件
            if (isMediaFile(entry)) {
                result.add((entry, ""))
            }
        }
        // 按文件名自然排序
        NaturalSort.sortTuples(result)
        return result.toArray()
    }

    // ==================== 私有工具方法 ====================

    private func directoryExists(path: String): Bool {
        return DirectoryScanner.directoryExists(path)
    }

    private func getParentDirectory(filePath: String): String {
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
        }
        return "."
    }

    // ==================== 私有工具方法 - 媒体文件过滤 ====================

    /**
     * 检查文件是否为图片格式（与 folder_handler 保持一致）
     */
    private func isImageFile(filename: String): Bool {
        let parts = filename.split(".")
        if (parts.size <= 1) {
            return false
        }
        let extension = parts[parts.size - 1]
        for (ext in ALLOWED_IMAGE_EXTENSIONS) {
            if (extension == ext) {
                return true
            }
        }
        return false
    }

    /**
     * 检查文件是否为视频格式（与 folder_handler 保持一致）
     */
    private func isVideoFile(filename: String): Bool {
        let parts = filename.split(".")
        if (parts.size <= 1) {
            return false
        }
        let extension = parts[parts.size - 1]
        for (ext in ALLOWED_VIDEO_EXTENSIONS) {
            if (extension == ext) {
                return true
            }
        }
        return false
    }

    /**
     * 检查文件是否为媒体文件（图片或视频）
     */
    private func isMediaFile(filename: String): Bool {
        return isImageFile(filename) || isVideoFile(filename)
    }

    /**
     * 获取文件扩展名（小写）
     */
    private func getFileExtension(filePath: String): String {
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
}
