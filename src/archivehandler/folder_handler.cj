package lrr4cj.archivehandler

import std.fs.*
import std.collection.*
import lrr4cj.models.ArchiveTypes
import lrr4cj.utils.DirectoryScanner
import lrr4cj.utils.NaturalSort

/**
 * 文件读取器 - 支持分块读取文件
 */
public class FileEntryReader <: EntryReader {
    private var file: File
    private let fileSize: Int64
    private var closed: Bool = false

    public init(filePath: String) {
        let path = Path(filePath)
        this.file = File(path, Read)
        this.fileSize = this.file.info.size
    }

    public func getSize(): Int64 {
        return fileSize
    }

    public func read(buffer: Array<Byte>): Int64 {
        if (closed) {
            return 0
        }
        return file.read(buffer)
    }

    public func close(): Unit {
        if (!closed) {
            closed = true
            file.close()
        }
    }
}

/**
 * 文件夹类型处理器
 */
public class FolderHandler <: ArchiveHandler {

    public func getType(): String {
        return ArchiveTypes.FOLDER
    }

    // 允许的图片文件扩展名（与 archive_file_handler 保持一致）
    private static let ALLOWED_IMAGE_EXTENSIONS: Array<String> = [
        "avif", "jpg", "jpeg", "png", "webp", "gif", "AVIF", "JPG", "JPEG", "PNG", "WEBP", "GIF"
    ]

    // 允许的视频文件扩展名（与 archive_file_handler 保持一致）
    private static let ALLOWED_VIDEO_EXTENSIONS: Array<String> = [
        "mp4", "webm", "mkv", "avi", "mov", "m4v", "MP4", "WEBM", "MKV", "AVI", "MOV", "M4V"
    ]

    /**
     * Cheap filename-only check for whether a single entry could be treated as media.
     * Used by scanners to avoid re-reading directories just to know if a folder can be handled.
     */
    public static func isAllowedMediaFileName(entryName: String): Bool {
        let parts = entryName.split(".")
        if (parts.size <= 1) {
            return false
        }
        let extension = parts[parts.size - 1]

        for (allowedExt in ALLOWED_IMAGE_EXTENSIONS) {
            if (extension == allowedExt) {
                return true
            }
        }
        for (allowedExt in ALLOWED_VIDEO_EXTENSIONS) {
            if (extension == allowedExt) {
                return true
            }
        }
        return false
    }

    public func listEntries(archivePath: String): Array<String> {
        return DirectoryScanner.listDirectory(archivePath)
    }

    public func extractEntryToStream(archivePath: String, entryName: String): (Int64, Array<UInt8>, Array<UInt8>) {
        try {
            let filePath = DirectoryScanner.joinPath(archivePath, entryName)
            if (!DirectoryScanner.fileExists(filePath)) {
                let errorMsg = "File not found: ${filePath}"
                return (1i64, Array<UInt8>(), errorMsg.toArray())
            }
            let data = File.readFrom(Path(filePath))
            let uint8Data = Array<UInt8>(data.size, { i => data[i] })
            return (0i64, uint8Data, Array<UInt8>())
        } catch (e: Exception) {
            let errorMsg = "Exception reading file: ${e.message}"
            return (1i64, Array<UInt8>(), errorMsg.toArray())
        }
    }

    public func getEntryReader(archivePath: String, entryName: String): (Int64, Option<EntryReader>, String) {
        try {
            let filePath = DirectoryScanner.joinPath(archivePath, entryName)
            if (!DirectoryScanner.fileExists(filePath)) {
                return (1i64, None, "File not found: ${filePath}")
            }
            let reader = FileEntryReader(filePath)
            return (0i64, Some(reader), "")
        } catch (e: Exception) {
            return (1i64, None, "Exception opening file: ${e.message}")
        }
    }

    public func extractEntryToFile(archivePath: String, entryName: String, outputPath: String): Bool {
        try {
            let sourcePath = DirectoryScanner.joinPath(archivePath, entryName)
            if (!DirectoryScanner.fileExists(sourcePath)) {
                return false
            }
            let sourceData = File.readFrom(Path(sourcePath))

            let outputDir = getParentDirectory(outputPath)
            if (!DirectoryScanner.directoryExists(outputDir)) {
                Directory.create(outputDir, recursive: true)
            }

            let destFile = File(Path(outputPath), Write)
            destFile.write(sourceData)
            destFile.close()
            return true
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

        // 筛选当前目录的图片文件并排序
        let imageEntries = ArrayList<String>()
        for (entry in entries) {
            let fullPath = DirectoryScanner.joinPath(archivePath, entry)
            if (DirectoryScanner.isDirectory(fullPath)) {
                continue
            }
            if (DirectoryScanner.fileExists(fullPath) && isImageFile(entry)) {
                imageEntries.add(entry)
            }
        }
        if (!imageEntries.isEmpty()) {
            NaturalSort.sortStrings(imageEntries)
            let firstEntry = imageEntries[0]
            let fullPath = DirectoryScanner.joinPath(archivePath, firstEntry)
            return (firstEntry, fullPath)
        }

        // 如果当前目录没有图片，查找子目录
        for (entry in entries) {
            let fullPath = DirectoryScanner.joinPath(archivePath, entry)
            if (DirectoryScanner.isDirectory(fullPath)) {
                let subEntries = DirectoryScanner.listDirectory(fullPath)
                let subImageEntries = ArrayList<String>()
                for (subEntry in subEntries) {
                    let subFullPath = DirectoryScanner.joinPath(fullPath, subEntry)
                    if (DirectoryScanner.fileExists(subFullPath) && isImageFile(subEntry)) {
                        subImageEntries.add(subEntry)
                    }
                }
                if (!subImageEntries.isEmpty()) {
                    NaturalSort.sortStrings(subImageEntries)
                    let firstSubEntry = subImageEntries[0]
                    let subFullPath = DirectoryScanner.joinPath(fullPath, firstSubEntry)
                    return (firstSubEntry, subFullPath)
                }
            }
        }
        return ("", "")
    }

    public func canHandle(filePath: String): Bool {
        // 首先检查是否是目录
        if (!DirectoryScanner.isDirectory(filePath)) {
            return false
        }

        // 列出目录中的所有条目
        let entries = DirectoryScanner.listDirectory(filePath)

        // 如果目录为空，不处理
        if (entries.size == 0) {
            return false
        }

        // 检查每个条目
        for (entry in entries) {
            let fullPath = DirectoryScanner.joinPath(filePath, entry)

            // 如果存在子目录，则不允许嵌套
            if (DirectoryScanner.isDirectory(fullPath)) {
                return false
            }

            // 检查文件是否是允许的媒体格式
            if (!DirectoryScanner.fileExists(fullPath)) {
                return false
            }

            // 获取文件扩展名
            if (!FolderHandler.isAllowedMediaFileName(entry)) {
                return false
            }
        }

        // 所有检查通过，可以处理
        return true
    }

    public func getCoverImage(archivePath: String): (Int64, Array<UInt8>, Array<UInt8>) {
        let (entryName, fullPath) = getFirstImage(archivePath)
        if (entryName.isEmpty() || fullPath.isEmpty()) {
            return (1i64, Array<UInt8>(), "No image found".toArray())
        }
        try {
            let data = File.readFrom(Path(fullPath))
            let uint8Data = Array<UInt8>(data.size, { i => data[i] })
            return (0i64, uint8Data, Array<UInt8>())
        } catch (e: Exception) {
            return (1i64, Array<UInt8>(), e.message.toArray())
        }
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
     * 检查文件是否为图片格式（与 archive_file_handler 保持一致）
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
     * 检查文件是否为视频格式（与 archive_file_handler 保持一致）
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
}
