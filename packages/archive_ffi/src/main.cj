package archive_ffi

import std.collection.*
import std.sort.*
import std.sync.*

foreign func strlen(arg1: CString): UIntNative
foreign func memcpy(dest: CPointer<Unit>, src: CString, n: UIntNative): CPointer<Unit>
foreign func setlocale(category: Int32, locale: CString): CString

/**
 * 压缩包条目流式读取器
 * 支持从压缩包中按需分块读取数据，避免一次性加载整个文件到内存
 */
public class ArchiveEntryReader {
    private var archivePtr: CPointer<archive>
    private var entryPtr: CPointer<archive_entry>
    private let entrySize: Int64
    private var closed: Bool = false
    private let bufSize: Int64 = 1024 * 1024  // 1MB 缓冲区，避免对齐问题
    private var buf: CPointer<UInt8>

    public init(archivePtr: CPointer<archive>, entryPtr: CPointer<archive_entry>, entrySize: Int64) {
        this.archivePtr = archivePtr
        this.entryPtr = entryPtr
        this.entrySize = entrySize
        this.buf = unsafe { LibC.malloc<UInt8>(count: bufSize) }
    }

    public func getSize(): Int64 {
        return entrySize
    }

    public func read(buffer: Array<Byte>): Int64 {
        if (closed) {
            return 0
        }

        let toRead = if (Int64(buffer.size) < bufSize) {
            Int64(buffer.size)
        } else {
            bufSize
        }

        let readLen = unsafe {
            archive_read_data(archivePtr, CPointer<Unit>(buf), UIntNative(toRead))
        }

        if (readLen <= 0) {
            return 0
        }

        for (i in 0..Int64(readLen)) {
            buffer[i] = unsafe { (buf + i).read() }
        }
        return Int64(readLen)
    }

    public func close(): Unit {
        if (!closed) {
            closed = true
            unsafe {
                LibC.free(buf)
                archive_entry_free(entryPtr)
                archive_read_close(archivePtr)
                archive_read_free(archivePtr)
            }
        }
    }
}

public class Archive {
    private static let localeInitMutex: Mutex = Mutex()
    private static var localeInitialized: Bool = false
    private static let LC_CTYPE: Int32 = 0

    private static func ensureLocaleInitialized(): Unit {
        localeInitMutex.lock()
        if (localeInitialized) {
            localeInitMutex.unlock()
            return
        }

        // libarchive relies on C locale for ZIP filename conversion.
        // Adopt process locale from environment once (e.g. C.UTF-8).
        let emptyLocale = unsafe { LibC.mallocCString("") }
        unsafe {
            let _ = setlocale(LC_CTYPE, emptyLocale)
            LibC.free(emptyLocale)
        }
        localeInitialized = true
        localeInitMutex.unlock()
    }

    private static func getEntryName(entry: CPointer<archive_entry>): String {
        // Prefer UTF-8 normalized entry names for non-ASCII archives.
        let rawUtf8Pathname = unsafe { archive_entry_pathname_utf8(entry) }
        if (!rawUtf8Pathname.isNull()) {
            let utf8Name = decodeEntryName(rawUtf8Pathname, true)
            if (utf8Name.size > 0) {
                return utf8Name
            }
        }

        let rawPathname = unsafe { archive_entry_pathname(entry) }
        if (rawPathname.isNull()) {
            return ""
        }
        return decodeEntryName(rawPathname, false)
    }

    private static func decodeEntryName(ptr: CString, utf8Guaranteed: Bool): String {
        let bytes = cStringToBytes(ptr)
        if (bytes.size == 0) {
            return ""
        }

        // archive_entry_pathname_utf8 guarantees UTF-8. For pathname(), try UTF-8 first
        // and then fall back to Latin-1 to preserve old behavior for odd encodings.
        if (utf8Guaranteed) {
            try { return String.fromUtf8(bytes) } catch (_: Exception) { return decodeLatin1(bytes) }
        }

        try { return String.fromUtf8(bytes) } catch (_: Exception) {}
        return decodeLatin1(bytes)
    }

    private static func cStringToBytes(ptr: CString): Array<UInt8> {
        let len = unsafe { strlen(ptr) }
        if (len == 0) {
            return Array<UInt8>()
        }
        let n = Int64(len)
        let buf = unsafe { LibC.malloc<UInt8>(count: n) }
        unsafe { memcpy(CPointer<Unit>(buf), ptr, len) }
        var out = Array<UInt8>(n, repeat: 0u8)
        for (i in 0..n) {
            out[i] = unsafe { (buf + i).read() }
        }
        unsafe { LibC.free(buf) }
        return out
    }

    private static func decodeLatin1(bytes: Array<UInt8>): String {
        var out = ""
        for (b in bytes) {
            out += Rune(UInt32(b)).toString()
        }
        return out
    }

    /**
     * 列出压缩包内所有条目的路径名
     * @param archivePath 压缩包文件路径
     * @return 条目路径名数组
     */
    private static func scanEntries(archivePath: String): (Array<String>, Int32) {
        ensureLocaleInitialized()
        let entries = ArrayList<String>()
        var mediaCount: Int32 = 0

        let a = unsafe { archive_read_new() }
        if (a.isNull()) {
            return (entries.toArray(), 0)
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
            return (entries.toArray(), 0)
        }

        let entry = unsafe { archive_entry_new2(a) }
        while (true) {
            let r = unsafe { archive_read_next_header2(a, entry) }
            if (r == Int32(ARCHIVE_EOF)) {
                break
            }
            if (r != Int32(ARCHIVE_OK)) {
                break
            }

            let name = getEntryName(entry)
            if (name.size > 0) {
                entries.add(name)
                if (isMediaEntryName(name)) {
                    mediaCount += 1
                }
            }
        }

        unsafe {
            archive_entry_free(entry)
            archive_read_close(a)
            archive_read_free(a)
        }

        return (entries.toArray(), mediaCount)
    }

    public static func listEntries(archivePath: String): Array<String> {
        let (entries, _) = scanEntries(archivePath)
        return entries
    }

    /**
     * Find the first image entry in an archive using a single streaming scan.
     *
     * This avoids building a full entry list + natural sorting, which can be very slow
     * on large archives. The ordering matches lanlu.utils.NaturalSort semantics
     * (numbers are compared by value, case-insensitive text).
     *
     * @return best-matching image entry name, or "" if none found / open fails.
     */
    public static func findFirstImageEntry(archivePath: String): String {
        ensureLocaleInitialized()
        let a = unsafe { archive_read_new() }
        if (a.isNull()) {
            return ""
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
            return ""
        }

        let entry = unsafe { archive_entry_new2(a) }
        var localBest = ""

        while (true) {
            let r = unsafe { archive_read_next_header2(a, entry) }
            if (r == Int32(ARCHIVE_EOF)) {
                break
            }
            if (r != Int32(ARCHIVE_OK)) {
                break
            }

            let name = getEntryName(entry)
            if (name.size == 0) {
                continue
            }
            if (!isImageEntryName(name)) {
                continue
            }
            if (localBest.size == 0) {
                localBest = name
            } else if (naturalCompare(name, localBest) == Ordering.LT) {
                localBest = name
            }
        }

        unsafe {
            archive_entry_free(entry)
            archive_read_close(a)
            archive_read_free(a)
        }

        return localBest
    }

    /**
     * 提取压缩包内指定条目的内容
     * @param archivePath 压缩包文件路径
     * @param entryName 条目名称
     * @return 条目内容的字节数组，如果未找到则返回空数组
     */
    public static func extractEntry(archivePath: String, entryName: String): Array<UInt8> {
        ensureLocaleInitialized()
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
        while (true) {
            let r = unsafe { archive_read_next_header2(a, entry) }
            if (r == Int32(ARCHIVE_EOF)) {
                break
            }
            if (r != Int32(ARCHIVE_OK)) {
                break
            }

            let name = getEntryName(entry)
            if (name.size == 0) {
                continue
            }

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

    // ---- helpers ----

    private static func isMediaEntryName(name: String): Bool {
        return isImageEntryName(name) || isVideoEntryName(name)
    }

    private static func isVideoEntryName(name: String): Bool {
        if (name.size == 0) {
            return false
        }
        let parts = name.split(".")
        if (parts.size <= 1) {
            return false
        }
        let ext = parts[parts.size - 1].toAsciiLower()
        return ext == "mp4" || ext == "webm" || ext == "mkv" || ext == "avi" || ext == "mov" || ext == "m4v"
    }

    private static func isImageEntryName(name: String): Bool {
        if (name.size == 0) {
            return false
        }
        let parts = name.split(".")
        if (parts.size <= 1) {
            return false
        }
        let ext = parts[parts.size - 1].toAsciiLower()
        return ext == "avif" || ext == "jpg" || ext == "jpeg" || ext == "png" || ext == "webp" || ext == "gif"
    }

    // Natural sort compare (mirrors lanlu.utils.NaturalSort.naturalCompare).
    private static func naturalCompare(a: String, b: String): Ordering {
        let aSegments = splitIntoSegments(a)
        let bSegments = splitIntoSegments(b)

        let minLen = if (aSegments.size < bSegments.size) { aSegments.size } else { bSegments.size }

        for (i in 0..minLen) {
            let aSeg = aSegments[i]
            let bSeg = bSegments[i]
            let result = compareSegments(aSeg, bSeg)
            if (result != Ordering.EQ) {
                return result
            }
        }

        if (aSegments.size < bSegments.size) {
            return Ordering.LT
        } else if (aSegments.size > bSegments.size) {
            return Ordering.GT
        }
        return Ordering.EQ
    }

    private static func splitIntoSegments(s: String): ArrayList<(String, Bool)> {
        let segments = ArrayList<(String, Bool)>()
        if (s.isEmpty()) {
            return segments
        }
        let runes = s.toRuneArray()
        var i = 0
        while (i < runes.size) {
            if (isDigit(runes[i])) {
                var numStr = ""
                while (i < runes.size && isDigit(runes[i])) {
                    numStr += runes[i].toString()
                    i++
                }
                segments.add((numStr, true))
            } else {
                var textStr = ""
                while (i < runes.size && !isDigit(runes[i])) {
                    textStr += runes[i].toString()
                    i++
                }
                segments.add((textStr, false))
            }
        }
        return segments
    }

    private static func compareSegments(a: (String, Bool), b: (String, Bool)): Ordering {
        let aVal = a[0]
        let aIsNum = a[1]
        let bVal = b[0]
        let bIsNum = b[1]

        if (aIsNum && bIsNum) {
            let aNum = parseNumber(aVal)
            let bNum = parseNumber(bVal)
            if (aNum < bNum) {
                return Ordering.LT
            } else if (aNum > bNum) {
                return Ordering.GT
            }
            // More leading zeros sorts first.
            if (aVal.size > bVal.size) {
                return Ordering.LT
            } else if (aVal.size < bVal.size) {
                return Ordering.GT
            }
            return Ordering.EQ
        }

        if (aIsNum && !bIsNum) {
            return Ordering.LT
        }
        if (!aIsNum && bIsNum) {
            return Ordering.GT
        }

        return aVal.toAsciiLower().compare(bVal.toAsciiLower())
    }

    private static func parseNumber(s: String): Int64 {
        var result: Int64 = 0
        for (r in s.toRuneArray()) {
            let digit = UInt32(r) - UInt32(r'0')
            result = result * 10 + Int64(digit)
        }
        return result
    }

    private static func isDigit(r: Rune): Bool {
        let code = UInt32(r)
        return code >= UInt32(r'0') && code <= UInt32(r'9')
    }

    /**
     * 打开压缩包条目的流式读取器
     * @param archivePath 压缩包文件路径
     * @param entryName 条目名称
     * @return (成功标志, 读取器或None, 条目大小, 错误信息)
     */
    public static func openEntryReader(archivePath: String, entryName: String): (Bool, Option<ArchiveEntryReader>, Int64, String) {
        ensureLocaleInitialized()
        let a = unsafe { archive_read_new() }
        if (a.isNull()) {
            return (false, None, 0, "Archive open failed: ${archivePath}")
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
            return (false, None, 0, "Archive open failed: ${archivePath}")
        }

        let entry = unsafe { archive_entry_new2(a) }
        while (true) {
            let r = unsafe { archive_read_next_header2(a, entry) }
            if (r == Int32(ARCHIVE_EOF)) {
                break
            }
            if (r != Int32(ARCHIVE_OK)) {
                break
            }

            let name = getEntryName(entry)
            if (name.size == 0) {
                continue
            }

            if (name == entryName) {
                let size = unsafe { archive_entry_size(entry) }
                let reader = ArchiveEntryReader(a, entry, size)
                return (true, Some(reader), size, "")
            }
        }

        unsafe {
            archive_entry_free(entry)
            archive_read_close(a)
            archive_read_free(a)
        }
        return (false, None, 0, "Entry not found: ${entryName}")
    }
}
