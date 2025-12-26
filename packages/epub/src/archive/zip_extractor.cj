/**
 * ZIP 解压封装 (使用 bsdtar)
 */
package epub.archive

import std.fs.*
import std.io.*
import std.process.*
import std.collection.*
import std.time.*
import epub.error.*

/**
 * ZIP 文件解压器
 * 封装 bsdtar 命令行工具进行 ZIP 解压操作
 */
public class ZipExtractor {
    private var archivePath: String
    private var tempFilePath: ?String

    private init() {
        this.archivePath = ""
        this.tempFilePath = None
    }

    /**
     * 从文件路径创建解压器
     */
    public static func fromPath(path: String): ZipExtractor {
        let extractor = ZipExtractor()
        extractor.archivePath = path
        extractor.tempFilePath = None
        return extractor
    }

    /**
     * 从内存数据创建解压器 (写入临时文件)
     */
    public static func fromBytes(data: Array<UInt8>): ZipExtractor {
        let extractor = ZipExtractor()
        let timestamp = DateTime.now().toUnixTimeStamp()
        let tempPath = "/tmp/epub_temp_${timestamp}.epub"

        let file = File(Path(tempPath), Write)
        file.write(data)
        file.close()

        extractor.archivePath = tempPath
        extractor.tempFilePath = Some(tempPath)
        return extractor
    }

    /**
     * 获取档案路径
     */
    public func getArchivePath(): String {
        return archivePath
    }

    /**
     * 列出档案中的所有文件
     */
    public func listEntries(): ArrayList<String> {
        let process = launch("bsdtar", "-tf", archivePath,
            stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
        let reader = StringReader<InputStream>(process.stdOutPipe)
        let output = reader.readToEnd()
        process.wait()

        let lines = output.split('\n')
        var entries = ArrayList<String>()
        for (line in lines) {
            let trimmed = line.trimAscii()
            if (trimmed.size > 0) {
                entries.add(trimmed)
            }
        }
        return entries
    }

    /**
     * 提取文件内容为字符串
     */
    public func extractToString(entryName: String): String {
        let (exitCode, data, errData) = extractToBytes(entryName)
        if (exitCode != 0) {
            let errMsg = String.fromUtf8(errData)
            throw EpubFileNotFoundError("${entryName}: ${errMsg}")
        }
        return String.fromUtf8(data)
    }

    /**
     * 提取文件内容为字节数组
     * 返回 (exitCode, data, errorData)
     */
    public func extractToBytes(entryName: String): (Int64, Array<UInt8>, Array<UInt8>) {
        if (entryName.size == 0) {
            return (1i64, Array<UInt8>(), "Empty entry name".toArray())
        }

        let process = launch("bsdtar", "-xO", "-f", archivePath, entryName,
            stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Pipe)
        return process.waitOutput()
    }

    /**
     * 检查文件是否存在于档案中
     */
    public func hasEntry(entryName: String): Bool {
        let entries = listEntries()
        for (entry in entries) {
            if (entry == entryName) {
                return true
            }
        }
        return false
    }

    /**
     * 清理临时文件
     */
    public func cleanup(): Unit {
        match (tempFilePath) {
            case Some(path) =>
                try {
                    remove(path)
                } catch (_: Exception) {
                    // 忽略删除失败
                }
            case None => ()
        }
    }
}
