package lrr4cj.archivehandler

import std.fs.*
import std.collection.*
import lrr4cj.models.ArchiveTypes
import lrr4cj.utils.{ArchiveUtils, DirectoryScanner}

/**
 * 文件夹类型处理器
 */
public class FolderHandler <: ArchiveHandler {

    public func getType(): String {
        return ArchiveTypes.FOLDER
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
            if (ArchiveUtils.isMediaFile(entry)) {
                count++
            }
        }
        return count
    }

    public func getFirstImage(archivePath: String): (String, String) {
        let entries = listEntries(archivePath)

        for (entry in entries) {
            let fullPath = DirectoryScanner.joinPath(archivePath, entry)
            if (DirectoryScanner.isDirectory(fullPath)) {
                continue
            }
            if (DirectoryScanner.fileExists(fullPath) && ArchiveUtils.isImageFile(entry)) {
                return (entry, fullPath)
            }
        }

        for (entry in entries) {
            let fullPath = DirectoryScanner.joinPath(archivePath, entry)
            if (DirectoryScanner.isDirectory(fullPath)) {
                let subEntries = DirectoryScanner.listDirectory(fullPath)
                for (subEntry in subEntries) {
                    let subFullPath = DirectoryScanner.joinPath(fullPath, subEntry)
                    if (DirectoryScanner.fileExists(subFullPath) && ArchiveUtils.isImageFile(subEntry)) {
                        return (subEntry, subFullPath)
                    }
                }
            }
        }
        return ("", "")
    }

    public func canHandle(filePath: String): Bool {
        return DirectoryScanner.isDirectory(filePath)
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
            result.add((entry, ""))
        }
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
}
