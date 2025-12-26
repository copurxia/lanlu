package lrr4cj.archivehandler

import std.fs.*
import std.process.*
import std.collection.*
import std.convert.*
import lrr4cj.models.ArchiveTypes
import lrr4cj.utils.{ArchiveUtils, DirectoryScanner}

/**
 * PDF文件类型处理器
 */
public class PdfHandler <: ArchiveHandler {

    public func getType(): String {
        return ArchiveTypes.PDF
    }

    public func listEntries(archivePath: String): Array<String> {
        let pageCount = getPdfPageCount(archivePath)
        var entries = ArrayList<String>()
        for (i in 1..pageCount + 1) {
            entries.add("page_${i}.jpg")
        }
        return entries.toArray()
    }

    public func extractEntryToStream(archivePath: String, entryName: String): (Int64, Array<UInt8>, Array<UInt8>) {
        try {
            let pageNumber = extractPageNumber(entryName)
            if (pageNumber < 1) {
                let errorMsg = "Invalid page number in: ${entryName}"
                return (1i64, Array<UInt8>(), errorMsg.toArray())
            }

            // 使用 /tmp 目录作为临时文件存储
            let tempPath = "/tmp/temp_pdf_extract_${pageNumber}.jpg"

            let success = extractPdfPage(archivePath, pageNumber, tempPath)
            if (success) {
                let data = File.readFrom(Path(tempPath))
                try { remove(Path(tempPath)) } catch (_: Exception) {}
                let uint8Data = Array<UInt8>(data.size, { i => data[i] })
                return (0i64, uint8Data, Array<UInt8>())
            } else {
                let errorMsg = "Failed to extract PDF page ${pageNumber}"
                return (1i64, Array<UInt8>(), errorMsg.toArray())
            }
        } catch (e: Exception) {
            let errorMsg = "Exception extracting PDF: ${e.message}"
            return (1i64, Array<UInt8>(), errorMsg.toArray())
        }
    }

    public func extractEntryToFile(archivePath: String, entryName: String, outputPath: String): Bool {
        let pageNumber = extractPageNumber(entryName)
        if (pageNumber < 1) {
            return false
        }
        return extractPdfPage(archivePath, pageNumber, outputPath)
    }

    public func getMediaCount(archivePath: String): Int32 {
        return getPdfPageCount(archivePath)
    }

    public func getFirstImage(archivePath: String): (String, String) {
        return ("page_1.jpg", "")
    }

    public func canHandle(filePath: String): Bool {
        if (DirectoryScanner.isDirectory(filePath)) {
            return false
        }
        let ext = ArchiveUtils.getFileExtension(filePath).toAsciiLower()
        return ext == "pdf"
    }

    public func getCoverImage(archivePath: String): (Int64, Array<UInt8>, Array<UInt8>) {
        // 提取第一页作为封面
        return extractEntryToStream(archivePath, "page_1.jpg")
    }

    public func listEntriesWithTitle(archivePath: String): Array<(String, String)> {
        let entries = listEntries(archivePath)
        var result = ArrayList<(String, String)>()
        for (entry in entries) {
            result.add((entry, ""))
        }
        return result.toArray()
    }

    private func getPdfPageCount(pdfPath: String): Int32 {
        try {
            let process = launch("gs", "-q", "-dNOSAFER", "-sDEVICE=nullpage", "-c",
                "(${pdfPath}) (r) file runpdfbegin pdfpagecount = quit",
                stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
            let (exitCode, stdout, _) = process.waitOutput()

            if (exitCode == 0 && stdout.size > 0) {
                let output = String.fromUtf8(stdout)
                let trimmed = output.trimAscii()
                return try { Int32.parse(trimmed) } catch (_: Exception) { 0i32 }
            }
            return 0i32
        } catch (_: Exception) {
            return 0i32
        }
    }

    private func extractPdfPage(pdfPath: String, pageNumber: Int32, outputPath: String): Bool {
        try {
            let outputDir = getParentDirectory(outputPath)
            if (!DirectoryScanner.directoryExists(outputDir)) {
                Directory.create(outputDir, recursive: true)
            }

            let process = launch("gs", "-dNOPAUSE", "-dFirstPage=${pageNumber}",
                "-dLastPage=${pageNumber}", "-sDEVICE=jpeg", "-r200", "-o", outputPath, pdfPath,
                stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
            let (exitCode, _, _) = process.waitOutput()
            return exitCode == 0
        } catch (_: Exception) {
            return false
        }
    }

    private func extractPageNumber(entryName: String): Int32 {
        if (entryName.startsWith("page_")) {
            let withoutPrefix = entryName[5..]
            let dotIndex = withoutPrefix.indexOf(".")
            match (dotIndex) {
                case Some(idx) =>
                    if (idx > 0) {
                        let numberStr = withoutPrefix[0..idx]
                        return try { Int32.parse(numberStr) } catch (_: Exception) { -1i32 }
                    }
                case None => ()
            }
        }
        return -1i32
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
