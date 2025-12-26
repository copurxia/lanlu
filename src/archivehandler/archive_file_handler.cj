package lrr4cj.archivehandler

import std.fs.*
import std.process.*
import std.collection.*
import std.io.*
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
        try {
            if (!fileExists(archivePath)) {
                return Array<String>()
            }

            // 使用 bsdtar 的 -tf 选项列出文件
            let process = launch("bsdtar", "-tf", archivePath,
                stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
            let reader = StringReader<InputStream>(process.stdOutPipe)
            let output = reader.readToEnd()

            // 将输出按行分割，去除空行
            let lines = output.split('\n')
            var entries = ArrayList<String>()

            for (line in lines) {
                let trimmedLine = line.trimAscii()
                if (trimmedLine.size > 0) {
                    entries.add(trimmedLine)
                }
            }

            return entries.toArray()
        } catch (_: Exception) {
            return Array<String>()
        }
    }

    public func extractEntryToStream(archivePath: String, entryName: String): (Int64, Array<UInt8>, Array<UInt8>) {
        try {
            let process = launch("bsdtar", "-xO", "-f", archivePath, entryName,
                stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
            return process.waitOutput()
        } catch (_: Exception) {
            return (1, [], [])
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

    public func canHandle(filePath: String): Bool {
        if (DirectoryScanner.isDirectory(filePath)) {
            return false
        }
        let ext = ArchiveUtils.getFileExtension(filePath).toAsciiLower()
        return ext != "pdf"
    }

    public func getCoverImage(archivePath: String): (Int64, Array<UInt8>, Array<UInt8>) {
        let (entryName, _) = getFirstImage(archivePath)
        if (entryName.isEmpty()) {
            return (1i64, Array<UInt8>(), "No image found".toArray())
        }
        return extractEntryToStream(archivePath, entryName)
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
