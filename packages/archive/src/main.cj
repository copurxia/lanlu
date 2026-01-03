package archive

import std.collection.*

public class Archive {
    /**
     * 列出压缩包内所有条目的路径名
     * @param archivePath 压缩包文件路径
     * @return 条目路径名数组
     */
    public static func listEntries(archivePath: String): Array<String> {
        let entries = ArrayList<String>()

        let a = unsafe { archive_read_new() }
        if (a.isNull()) {
            return entries.toArray()
        }

        unsafe {
            archive_read_support_format_all(a)
            archive_read_support_filter_all(a)
        }

        let pathCStr = unsafe { LibC.mallocCString(archivePath) }
        let openResult = unsafe { archive_read_open_filename(a, pathCStr, 10240) }
        unsafe { LibC.free(pathCStr) }

        if (openResult != Int32(ARCHIVE_OK)) {
            unsafe { archive_read_free(a) }
            return entries.toArray()
        }

        let entry = unsafe { archive_entry_new2(a) }
        var entryCount: Int64 = 0

        while (true) {
            let r = unsafe { archive_read_next_header2(a, entry) }
            if (r == Int32(ARCHIVE_EOF)) {
                break
            }
            if (r != Int32(ARCHIVE_OK)) {
                break
            }

            let pathname = unsafe { archive_entry_pathname(entry) }
            if (!pathname.isNull()) {
                let name = unsafe { pathname.toString() }
                entries.add(name)
                entryCount += 1
            }
        }

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
        let a = unsafe { archive_read_new() }
        if (a.isNull()) {
            return Array<UInt8>()
        }

        unsafe {
            archive_read_support_format_all(a)
            archive_read_support_filter_all(a)
        }

        let pathCStr = unsafe { LibC.mallocCString(archivePath) }
        let openResult = unsafe { archive_read_open_filename(a, pathCStr, 10240) }
        unsafe { LibC.free(pathCStr) }

        if (openResult != Int32(ARCHIVE_OK)) {
            unsafe { archive_read_free(a) }
            return Array<UInt8>()
        }

        let entry = unsafe { archive_entry_new2(a) }
        var scannedEntries: Int64 = 0

        while (true) {
            let r = unsafe { archive_read_next_header2(a, entry) }
            if (r == Int32(ARCHIVE_EOF)) {
                break
            }
            if (r != Int32(ARCHIVE_OK)) {
                break
            }

            let pathname = unsafe { archive_entry_pathname(entry) }
            if (pathname.isNull()) {
                continue
            }

            let name = unsafe { pathname.toString() }
            scannedEntries += 1

            if (name != entryName) {
                continue
            }

            let size = unsafe { archive_entry_size(entry) }
            if (size <= 0) {
                unsafe {
                    archive_entry_free(entry)
                    archive_read_close(a)
                    archive_read_free(a)
                }
                return Array<UInt8>()
            }

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

            unsafe {
                LibC.free(buf)
                archive_entry_free(entry)
                archive_read_close(a)
                archive_read_free(a)
            }

            return result.toArray()
        }

        unsafe {
            archive_entry_free(entry)
            archive_read_close(a)
            archive_read_free(a)
        }

        return Array<UInt8>()
    }
}
