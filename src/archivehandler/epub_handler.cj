package lrr4cj.archivehandler

import std.fs.*
import std.process.*
import std.collection.*
import std.io.*
import lrr4cj.models.ArchiveTypes
import lrr4cj.utils.{ArchiveUtils, DirectoryScanner}

/**
 * EPUB文件类型处理器
 * EPUB is a ZIP archive containing XHTML, CSS, images, and metadata
 */
public class EpubHandler <: ArchiveHandler {

    public func getType(): String {
        return ArchiveTypes.EPUB
    }

    /**
     * 列出EPUB中的XHTML文件作为"页面"
     * Filters only XHTML files (not CSS, images, metadata)
     */
    public func listEntries(archivePath: String): Array<String> {
        try {
            if (!DirectoryScanner.fileExists(archivePath)) {
                return Array<String>()
            }

            // List all files in EPUB (which is a ZIP)
            let process = launch("bsdtar", "-tf", archivePath,
                stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
            let reader = StringReader<InputStream>(process.stdOutPipe)
            let output = reader.readToEnd()
            process.wait()

            let lines = output.split('\n')
            var entries = ArrayList<String>()

            for (line in lines) {
                let trimmedLine = line.trimAscii()
                if (trimmedLine.size == 0) {
                    continue
                }

                // Filter for XHTML files only
                // Match: *.xhtml, *.html, *.htm (case insensitive)
                let lowerLine = trimmedLine.toAsciiLower()
                if (lowerLine.endsWith(".xhtml") ||
                    lowerLine.endsWith(".html") ||
                    lowerLine.endsWith(".htm")) {

                    // Skip manifest and metadata files
                    if (!trimmedLine.contains("META-INF/") &&
                        !trimmedLine.endsWith("container.xml")) {
                        entries.add(trimmedLine)
                    }
                }
            }

            // Return entries as-is (EPUB files usually have proper ordering)
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

            // Extract XHTML content from EPUB (ZIP)
            let process = launch("bsdtar", "-xO", "-f", archivePath, entryName,
                stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
            return process.waitOutput()
        } catch (e: Exception) {
            return (1i64, Array<UInt8>(), e.message.toArray())
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
        // EPUB doesn't have "media count" in the same sense
        // Return XHTML page count instead
        let entries = listEntries(archivePath)
        var count: Int32 = 0
        for (entry in entries) {
            count++
        }
        return count
    }

    public func getFirstImage(archivePath: String): (String, String) {
        // EPUB doesn't extract to images, return empty
        return ("", "")
    }

    public func canHandle(filePath: String): Bool {
        if (DirectoryScanner.isDirectory(filePath)) {
            return false
        }
        let ext = DirectoryScanner.getFileExtension(filePath).toAsciiLower()
        return ext == "epub"
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
