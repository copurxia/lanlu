package lrr4cj.archivehandler

import std.fs.*
import std.collection.*
import archive.Archive
import lrr4cj.models.ArchiveTypes
import lrr4cj.utils.{ArchiveUtils, DirectoryScanner}

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
            if (ArchiveUtils.isMediaFile(entry)) {
                count++
            }
        }
        return count
    }

    public func getFirstImage(archivePath: String): (String, String) {
        let entries = listEntries(archivePath)
        for (entry in entries) {
            if (ArchiveUtils.isImageFile(entry)) {
                return (entry, "")
            }
        }
        return ("", "")
    }

    // 支持的压缩包扩展名
    private static let SUPPORTED_EXTENSIONS: Array<String> = [
        "zip", "rar", "7z", "tar", "cbz", "cbr", "cb7", "cbt", "gz", "tgz"
    ]

    public func canHandle(filePath: String): Bool {
        if (DirectoryScanner.isDirectory(filePath)) {
            return false
        }
        let ext = ArchiveUtils.getFileExtension(filePath).toAsciiLower()
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
            result.add((entry, ""))
        }
        return result.toArray()
    }

    // ==================== 私有工具方法 ====================

    private func fileExists(path: String): Bool {
        return DirectoryScanner.fileExists(path)
    }

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
}
