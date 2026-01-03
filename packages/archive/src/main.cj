package archive

import std.collection.*

public class Archive {
    /**
     * 列出压缩包内所有条目的路径名
     * @param archivePath 压缩包文件路径
     * @return 条目路径名数组
     */
    public static func listEntries(archivePath: String): Array<String> {
        println("[DEBUG] listEntries called with archivePath: ${archivePath}")
        let entries = ArrayList<String>()

        let a = unsafe { archive_read_new() }
        if (a.isNull()) {
            println("[DEBUG] Failed to create archive reader")
            return entries.toArray()
        }

        unsafe {
            archive_read_support_format_all(a)
            archive_read_support_filter_all(a)
        }
        println("[DEBUG] Archive reader created successfully")

        let pathCStr = unsafe { LibC.mallocCString(archivePath) }
        let openResult = unsafe { archive_read_open_filename(a, pathCStr, 10240) }
        unsafe { LibC.free(pathCStr) }

        if (openResult != Int32(ARCHIVE_OK)) {
            println("[DEBUG] Failed to open archive: ${openResult}")
            unsafe { archive_read_free(a) }
            return entries.toArray()
        }
        println("[DEBUG] Archive opened successfully")

        let entry = unsafe { archive_entry_new2(a) }
        var entryCount: Int64 = 0

        while (true) {
            let r = unsafe { archive_read_next_header2(a, entry) }
            if (r == Int32(ARCHIVE_EOF)) {
                break
            }
            if (r != Int32(ARCHIVE_OK)) {
                println("[DEBUG] Error reading header: ${r}")
                break
            }

            let pathname = unsafe { archive_entry_pathname(entry) }
            if (!pathname.isNull()) {
                let name = unsafe { pathname.toString() }
                entries.add(name)
                entryCount += 1
                println("[DEBUG] Found entry: ${name}")
            }
        }

        println("[DEBUG] Total entries found: ${entryCount}")

        unsafe {
            archive_entry_free(entry)
            archive_read_close(a)
            archive_read_free(a)
        }

        return entries.toArray()
    }

    /**
     * 提取压缩包内指定条目的内容
     * @param archivePath 压缩包文件路径
     * @param entryName 条目名称
     * @return 条目内容的字节数组，如果未找到则返回空数组
     */
    public static func extractEntry(archivePath: String, entryName: String): Array<UInt8> {
        println("[DEBUG] extractEntry called with archivePath: ${archivePath}, entryName: ${entryName}")
        let a = unsafe { archive_read_new() }
        if (a.isNull()) {
            println("[DEBUG] Failed to create archive reader")
            return Array<UInt8>()
        }

        unsafe {
            archive_read_support_format_all(a)
            archive_read_support_filter_all(a)
        }
        println("[DEBUG] Archive reader created successfully")

        let pathCStr = unsafe { LibC.mallocCString(archivePath) }
        let openResult = unsafe { archive_read_open_filename(a, pathCStr, 10240) }
        unsafe { LibC.free(pathCStr) }

        if (openResult != Int32(ARCHIVE_OK)) {
            println("[DEBUG] Failed to open archive: ${openResult}")
            unsafe { archive_read_free(a) }
            return Array<UInt8>()
        }
        println("[DEBUG] Archive opened successfully")

        let entry = unsafe { archive_entry_new2(a) }
        var scannedEntries: Int64 = 0

        while (true) {
            let r = unsafe { archive_read_next_header2(a, entry) }
            if (r == Int32(ARCHIVE_EOF)) {
                println("[DEBUG] Reached end of archive, entry '${entryName}' not found")
                break
            }
            if (r != Int32(ARCHIVE_OK)) {
                println("[DEBUG] Error reading header: ${r}")
                break
            }

            let pathname = unsafe { archive_entry_pathname(entry) }
            if (pathname.isNull()) {
                continue
            }

            let name = unsafe { pathname.toString() }
            scannedEntries += 1
            println("[DEBUG] Scanning entry ${scannedEntries}: ${name}")

            if (name != entryName) {
                continue
            }

            println("[DEBUG] Found target entry: ${name}")

            let size = unsafe { archive_entry_size(entry) }
            if (size <= 0) {
                println("[DEBUG] Entry size is ${size}, returning empty")
                unsafe {
                    archive_entry_free(entry)
                    archive_read_close(a)
                    archive_read_free(a)
                }
                return Array<UInt8>()
            }

            println("[DEBUG] Entry size: ${size} bytes")

            let result = ArrayList<UInt8>()
            let bufSize: Int64 = 8192
            let buf = unsafe { LibC.malloc<UInt8>(count: bufSize) }
            var totalRead: Int64 = 0

            while (true) {
                let readLen = unsafe {
                    archive_read_data(a, CPointer<Unit>(buf), UIntNative(bufSize))
                }
                if (readLen <= 0) {
                    break
                }
                for (i in 0..Int64(readLen)) {
                    let byte = unsafe { (buf + i).read() }
                    result.add(byte)
                }
                totalRead += Int64(readLen)
            }

            println("[DEBUG] Total bytes read: ${totalRead}")

            unsafe {
                LibC.free(buf)
                archive_entry_free(entry)
                archive_read_close(a)
                archive_read_free(a)
            }

            return result.toArray()
        }

        println("[DEBUG] Scanned ${scannedEntries} entries total")

        unsafe {
            archive_entry_free(entry)
            archive_read_close(a)
            archive_read_free(a)
        }

        return Array<UInt8>()
    }
}
