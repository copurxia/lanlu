package lanlu.infrastructure.archivehandler

import std.fs.*
import std.collection.*
import lanlu.contexts.archive.domain.ArchiveTypes
import lanlu.shared.utils.ArchiveUtils
import lanlu.shared.utils.DirectoryScanner
import lanlu.shared.utils.NaturalSort
import lanlu.shared.utils.FileUtils

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
    private static let AUX_SUBDIRECTORY_NAMES: Array<String> = [
        "extrafanart"
    ]

    private static let STRUCTURE_SUBDIRECTORY_NAMES: Array<String> = [
        "bdmv", "certificate"
    ]

    public func getType(): String {
        return ArchiveTypes.FOLDER
    }

    // 允许的图片文件扩展名（与 archive_file_handler 保持一致）
    private static let ALLOWED_IMAGE_EXTENSIONS: Array<String> = [
        "avif", "jpg", "jpeg", "png", "webp", "gif", "AVIF", "JPG", "JPEG", "PNG", "WEBP", "GIF"
    ]

    // 允许的视频文件扩展名（与 archive_file_handler 保持一致）
    private static let ALLOWED_VIDEO_EXTENSIONS: Array<String> = [
        "mp4", "webm", "mkv", "avi", "mov", "m4v", "m2ts", "mts", "ts",
        "MP4", "WEBM", "MKV", "AVI", "MOV", "M4V", "M2TS", "MTS", "TS"
    ]

    // 允许的音频文件扩展名（与 archive_file_handler 保持一致）
    private static let ALLOWED_AUDIO_EXTENSIONS: Array<String> = [
        "mp3", "flac", "m4a", "aac", "ogg", "opus", "wav", "wma", "ape", "alac",
        "MP3", "FLAC", "M4A", "AAC", "OGG", "OPUS", "WAV", "WMA", "APE", "ALAC"
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
        for (allowedExt in ALLOWED_AUDIO_EXTENSIONS) {
            if (extension == allowedExt) {
                return true
            }
        }
        return false
    }

    /**
     * Allow non-media auxiliary files inside a folder archive.
     *
     * Motivation: some downloaders (e.g. Pixiv) may drop a meta.json alongside images.
     * We should not reject the whole folder because of it, but a folder with only JSON
     * is still not a valid "folder archive".
     */
    public static func isAllowedAuxFileName(entryName: String): Bool {
        let lower = entryName.toAsciiLower()
        // Keep it narrow: allow common sidecar metadata/subtitle files.
        return lower.endsWith(".json") ||
               lower.endsWith(".ass") ||
               lower.endsWith(".ssa") ||
               lower.endsWith(".srt") ||
               lower.endsWith(".vtt") ||
               lower.endsWith(".sub") ||
               lower.endsWith(".idx") ||
               lower.endsWith(".sup") ||
               lower.endsWith(".opf") ||
               lower.endsWith(".nfo") ||
               lower.endsWith(".xml") ||
               lower.endsWith(".svg")
    }

    public static func isAllowedAuxDirectoryName(entryName: String): Bool {
        let lower = entryName.toAsciiLower()
        for (name in AUX_SUBDIRECTORY_NAMES) {
            if (lower == name) {
                return true
            }
        }
        return false
    }

    public static func isAllowedStructureDirectoryName(entryName: String): Bool {
        let lower = entryName.toAsciiLower()
        for (name in STRUCTURE_SUBDIRECTORY_NAMES) {
            if (lower == name) {
                return true
            }
        }
        return false
    }

    public static func isAllowedChildDirectoryName(entryName: String): Bool {
        return isAllowedAuxDirectoryName(entryName) ||
               isAllowedStructureDirectoryName(entryName)
    }

    public static func canHandleDirectoryEntries(filePath: String, entries: Array<String>): Bool {
        if (!DirectoryScanner.isDirectory(filePath)) {
            return false
        }

        let dirName = ArchiveUtils.getFullFileName(filePath)
        if (isAllowedChildDirectoryName(dirName)) {
            return false
        }

        if (entries.size == 0) {
            return false
        }

        var hasMedia = false
        var hasPrimaryStructureDir = false
        for (entry in entries) {
            let fullPath = DirectoryScanner.joinPath(filePath, entry)

            if (DirectoryScanner.isDirectory(fullPath)) {
                if (FolderHandler.isAllowedStructureDirectoryName(entry)) {
                    hasPrimaryStructureDir = true
                    continue
                }
                if (FolderHandler.isAllowedAuxDirectoryName(entry)) {
                    continue
                }
                return false
            }

            if (!DirectoryScanner.fileExists(fullPath)) {
                return false
            }

            if (FolderHandler.isAllowedMediaFileName(entry)) {
                hasMedia = true
            } else if (FolderHandler.isAllowedAuxFileName(entry)) {
                // ignore
            } else {
                return false
            }
        }

        return hasMedia || hasPrimaryStructureDir
    }

    public static func countMediaEntries(entries: Array<String>): Int32 {
        var count: Int32 = 0
        for (entry in entries) {
            if (isMediaEntry(entry)) {
                count++
            }
        }
        return count
    }

    public static func selectFirstCoverEntry(entries: Array<String>): String {
        let topLevelImageEntries = ArrayList<String>()
        let subDirImageEntries = ArrayList<String>()

        for (entry in entries) {
            if (isImageEntry(entry)) {
                if (entry.contains("/")) {
                    subDirImageEntries.add(entry)
                } else {
                    topLevelImageEntries.add(entry)
                }
            }
        }

        if (!topLevelImageEntries.isEmpty()) {
            NaturalSort.sortStrings(topLevelImageEntries)
            return topLevelImageEntries[0]
        }

        if (!subDirImageEntries.isEmpty()) {
            NaturalSort.sortStrings(subDirImageEntries)
            return subDirImageEntries[0]
        }

        let topLevelVideoEntries = ArrayList<String>()
        let subDirVideoEntries = ArrayList<String>()

        for (entry in entries) {
            if (isVideoEntry(entry)) {
                if (entry.contains("/")) {
                    subDirVideoEntries.add(entry)
                } else {
                    topLevelVideoEntries.add(entry)
                }
            }
        }

        if (!topLevelVideoEntries.isEmpty()) {
            NaturalSort.sortStrings(topLevelVideoEntries)
            return topLevelVideoEntries[0]
        }

        if (!subDirVideoEntries.isEmpty()) {
            NaturalSort.sortStrings(subDirVideoEntries)
            return subDirVideoEntries[0]
        }

        return ""
    }

    public func listEntries(archivePath: String): Array<String> {
        return listEntriesRecursive(archivePath, "")
    }

    /**
     * 递归列出目录中的所有文件，支持下钻子目录（如 extrafanart）
     */
    private func listEntriesRecursive(basePath: String, relativePrefix: String): Array<String> {
        let entries = DirectoryScanner.listDirectory(basePath)
        let result = ArrayList<String>()

        for (entry in entries) {
            let fullPath = DirectoryScanner.joinPath(basePath, entry)
            let relativePath = if (relativePrefix.size > 0) {
                "${relativePrefix}/${entry}"
            } else {
                entry
            }

            if (DirectoryScanner.isDirectory(fullPath)) {
                // 递归扫描子目录
                let subEntries = listEntriesRecursive(fullPath, relativePath)
                for (subEntry in subEntries) {
                    result.add(subEntry)
                }
            } else if (DirectoryScanner.fileExists(fullPath)) {
                result.add(relativePath)
            }
        }

        return result.toArray()
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

            let outputDir = FileUtils.getParentDirectory(outputPath)
            // If outputPath has no parent (e.g. "out.jpg"), keep it in the current directory.
            if (outputDir.size > 0 && !DirectoryScanner.directoryExists(outputDir)) {
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
        return FolderHandler.countMediaEntries(entries)
    }

    public func getFirstCoverEntry(archivePath: String): (String, String) {
        let entries = listEntries(archivePath)
        let firstEntry = FolderHandler.selectFirstCoverEntry(entries)
        if (firstEntry.size == 0) {
            return ("", "")
        }
        let fullPath = DirectoryScanner.joinPath(archivePath, firstEntry)
        return (firstEntry, fullPath)
    }

    public func canHandle(filePath: String): Bool {
        if (!DirectoryScanner.isDirectory(filePath)) {
            return false
        }
        let entries = DirectoryScanner.listDirectory(filePath)
        return FolderHandler.canHandleDirectoryEntries(filePath, entries)
    }

    public func getCoverImage(archivePath: String): (Int64, Array<UInt8>, Array<UInt8>) {
        let (entryName, fullPath) = getFirstCoverEntry(archivePath)
        if (entryName.isEmpty() || fullPath.isEmpty()) {
            return (1i64, Array<UInt8>(), "No cover media found".toArray())
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
     * 检查文件是否为音频格式（与 archive_file_handler 保持一致）
     */
    private func isAudioFile(filename: String): Bool {
        let parts = filename.split(".")
        if (parts.size <= 1) {
            return false
        }
        let extension = parts[parts.size - 1]
        for (ext in ALLOWED_AUDIO_EXTENSIONS) {
            if (extension == ext) {
                return true
            }
        }
        return false
    }

    /**
     * 检查文件是否为媒体文件（图片/视频/音频）
     */
    private func isMediaFile(filename: String): Bool {
        return isImageFile(filename) || isVideoFile(filename) || isAudioFile(filename)
    }

    private static func isImageEntry(filename: String): Bool {
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

    private static func isVideoEntry(filename: String): Bool {
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

    private static func isAudioEntry(filename: String): Bool {
        let parts = filename.split(".")
        if (parts.size <= 1) {
            return false
        }
        let extension = parts[parts.size - 1]
        for (ext in ALLOWED_AUDIO_EXTENSIONS) {
            if (extension == ext) {
                return true
            }
        }
        return false
    }

    private static func isMediaEntry(filename: String): Bool {
        return isImageEntry(filename) || isVideoEntry(filename) || isAudioEntry(filename)
    }
}
