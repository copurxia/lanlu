package lrr4cj.archivehandler

import std.fs.*
import std.collection.*
import lrr4cj.models.ArchiveTypes
import lrr4cj.utils.DirectoryScanner
import epub.Epub

/**
 * EPUB文件类型处理器
 * 使用 packages/epub 库解析 EPUB 文件
 */
public class EpubHandler <: ArchiveHandler {

    public func getType(): String {
        return ArchiveTypes.EPUB
    }

    /**
     * 列出EPUB中的XHTML文件作为"页面"
     */
    public func listEntries(archivePath: String): Array<String> {
        try {
            if (!DirectoryScanner.fileExists(archivePath)) {
                return Array<String>()
            }

            let epub = Epub.open(archivePath)
            var entries = ArrayList<String>()

            for (file in epub.allFiles) {
                entries.add(file.href)
            }

            epub.close()
            return entries.toArray()
        } catch (_: Exception) {
            return Array<String>()
        }
    }

    public func extractEntryToStream(archivePath: String, entryName: String): (Int64, Array<UInt8>, Array<UInt8>) {
        try {
            if (entryName.size == 0) {
                return (1i64, Array<UInt8>(), "Empty entry name".toArray())
            }

            let epub = Epub.open(archivePath)
            let dataOpt = epub.extractResource(entryName)
            epub.close()

            match (dataOpt) {
                case Some(data) => return (0i64, data, Array<UInt8>())
                case None => return (1i64, Array<UInt8>(), "Entry not found".toArray())
            }
        } catch (e: Exception) {
            return (1i64, Array<UInt8>(), e.message.toArray())
        }
    }

    public func getEntryReader(archivePath: String, entryName: String): (Int64, Option<EntryReader>, String) {
        try {
            if (entryName.size == 0) {
                return (1i64, None, "Empty entry name")
            }

            let epub = Epub.open(archivePath)
            let dataOpt = epub.extractResource(entryName)
            epub.close()

            match (dataOpt) {
                case Some(data) =>
                    let reader = MemoryEntryReader(data)
                    return (0i64, Some(reader), "")
                case None => return (1i64, None, "Entry not found")
            }
        } catch (e: Exception) {
            return (1i64, None, e.message)
        }
    }

    public func extractEntryToFile(archivePath: String, entryName: String, outputPath: String): Bool {
        try {
            if (entryName.size == 0) {
                return false
            }

            let (exitCode, data, _) = extractEntryToStream(archivePath, entryName)

            if (exitCode == 0 && data.size > 0) {
                let outputDir = getParentDirectory(outputPath)
                if (!DirectoryScanner.directoryExists(outputDir)) {
                    Directory.create(outputDir, recursive: true)
                }

                let filePath = Path(outputPath)
                let file = File(filePath, Write)
                file.write(data)
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
        return Int32(entries.size)
    }

    public func getFirstImage(archivePath: String): (String, String) {
        try {
            let epub = Epub.open(archivePath)
            let resources = epub.getResourceList()

            for (item in resources) {
                if (isImageMediaType(item.mediaType)) {
                    epub.close()
                    return (item.href, "")
                }
            }

            epub.close()
            return ("", "")
        } catch (_: Exception) {
            return ("", "")
        }
    }

    public func canHandle(filePath: String): Bool {
        if (DirectoryScanner.isDirectory(filePath)) {
            return false
        }
        let ext = DirectoryScanner.getFileExtension(filePath).toAsciiLower()
        return ext == "epub"
    }

    /**
     * 获取封面图片数据
     * 优先使用 EPUB 元数据中定义的封面，否则返回第一张图片
     */
    public func getCoverImage(archivePath: String): (Int64, Array<UInt8>, Array<UInt8>) {
        try {
            let epub = Epub.open(archivePath)

            // 优先尝试获取元数据中定义的封面
            let coverOpt = epub.getCoverBytes()
            match (coverOpt) {
                case Some(data) =>
                    epub.close()
                    return (0i64, data, Array<UInt8>())
                case None => ()
            }

            // 如果没有封面元数据，尝试获取第一张图片
            let resources = epub.getResourceList()
            for (item in resources) {
                if (isImageMediaType(item.mediaType)) {
                    let dataOpt = epub.extractResource(item.href)
                    epub.close()
                    match (dataOpt) {
                        case Some(data) => return (0i64, data, Array<UInt8>())
                        case None => return (1i64, Array<UInt8>(), "Failed to extract image".toArray())
                    }
                }
            }

            epub.close()
            return (1i64, Array<UInt8>(), "No cover image found".toArray())
        } catch (e: Exception) {
            return (1i64, Array<UInt8>(), e.message.toArray())
        }
    }

    private func isImageMediaType(mediaType: String): Bool {
        return mediaType.startsWith("image/")
    }

    /**
     * 检查文件是否为HTML/XHTML格式
     */
    private func isHtmlFile(filePath: String): Bool {
        let lowerPath = filePath.toAsciiLower()
        return lowerPath.endsWith(".xhtml") ||
               lowerPath.endsWith(".html") ||
               lowerPath.endsWith(".htm")
    }

    public func listEntriesWithTitle(archivePath: String): Array<(String, String)> {
        try {
            if (!DirectoryScanner.fileExists(archivePath)) {
                return Array<(String, String)>()
            }

            let epub = Epub.open(archivePath)
            var entries = ArrayList<(String, String)>()

            for (file in epub.allFiles) {
                // 只返回HTML/XHTML文件
                if (isHtmlFile(file.href)) {
                    let title = match (file.title) {
                        case Some(t) => t
                        case None => ""
                    }
                    entries.add((file.href, title))
                }
            }

            epub.close()
            return entries.toArray()
        } catch (_: Exception) {
            return Array<(String, String)>()
        }
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
