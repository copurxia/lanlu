package lanlu.infrastructure.archivehandler

import std.fs.*
import std.collection.*
import stdx.crypto.digest.*
import stdx.encoding.hex.*
import stdx.log.*
import archive_ffi.Archive
import lanlu.contexts.system.application.SystemSettingsService
import lanlu.shared.utils.*

/**
 * 分卷归档处理器。
 *
 * 对于二进制切片（BinarySlice）和 Split Zip，将分片按顺序拼接成缓存归档文件，
 * 然后委托给底层 ArchiveFileHandler 进行读取。
 *
 * 对于 RAR 分卷（RarVolume），通过 libarchive 的多文件打开 API 读取，不进行简单字节拼接。
 */
public class VolumeArchiveHandler <: ArchiveHandler {
    private static let logger = getLogger("volume_archive_handler")
    private static let CACHE_VERSION: Int32 = 1

    private let parts: Array<String>
    private let underlyingFormat: String
    private let pattern: VolumePattern
    private let entryPath: String

    // 缓存文件路径（懒初始化）
    private var cachePath: String = ""
    private var cacheReady: Bool = false
    private var errorMsg: String = ""

    // 底层处理器（懒初始化）
    private var delegateHandler: Option<ArchiveHandler> = None

    public init(
        entryPath: String,
        parts: Array<String>,
        pattern: VolumePattern,
        underlyingFormat: String
    ) {
        this.entryPath = entryPath
        this.parts = parts
        this.pattern = pattern
        this.underlyingFormat = underlyingFormat
    }

    public func getType(): String {
        return "archive"
    }

    /**
     * 构建或获取缓存归档文件路径。
     * 返回 (成功标志, 缓存路径/错误信息)
     */
    private func ensureCache(): (Bool, String) {
        if (cacheReady) {
            return (true, cachePath)
        }
        if (errorMsg.size > 0) {
            return (false, errorMsg)
        }

        if (parts.size == 0) {
            errorMsg = "No volume parts provided"
            return (false, errorMsg)
        }

        try {
            cachePath = buildCachedArchive()
            cacheReady = true
            logger.info("volume archive cache ready", ("cachePath", cachePath), ("partsCount", parts.size.toString()))
            return (true, cachePath)
        } catch (e: Exception) {
            errorMsg = "Failed to build volume archive cache: ${e.message}"
            logger.error(errorMsg)
            return (false, errorMsg)
        }
    }

    /**
     * 构建拼接缓存归档文件。
     * 缓存 key 基于所有分片的路径、大小和修改时间生成。
     */
    private func buildCachedArchive(): String {
        let fingerprint = buildVolumeFingerprint()
        let cacheDir = buildCacheDir()
        ensureCacheDirExists(cacheDir)

        let cacheFileName = "vol_${fingerprint}.${underlyingFormat}"
        let fullCachePath = FileUtils.joinPath(cacheDir, cacheFileName)

        // 检查缓存是否已存在且完整
        if (cacheFileValid(fullCachePath)) {
            logger.debug("volume archive cache hit", ("cachePath", fullCachePath))
            return fullCachePath
        }

        logger.info("building volume archive cache", ("cachePath", fullCachePath), ("parts", parts.size.toString()))

        // 按顺序拼接所有分片
        let output = File(Path(fullCachePath), Write)
        try {
            for (part in parts) {
                let partPath = Path(part)
                if (!exists(partPath)) {
                    throw Exception("Volume part not found: ${part}")
                }
                let input = File(partPath, Read)
                try {
                    let bufSize: Int64 = 1024 * 1024  // 1MB buffer
                    let readBuf = Array<Byte>(bufSize, repeat: 0)
                    while (true) {
                        let bytesRead = input.read(readBuf)
                        if (bytesRead <= 0) {
                            break
                        }
                        var writeBuf = Array<UInt8>(bytesRead, repeat: 0u8)
                        for (i in 0..bytesRead) {
                            writeBuf[i] = UInt8(readBuf[i])
                        }
                        output.write(writeBuf)
                    }
                } finally {
                    input.close()
                }
            }
        } catch (e: Exception) {
            output.close()
            // 清理不完整的缓存文件
            try {
                if (exists(Path(fullCachePath))) {
                    remove(Path(fullCachePath))
                }
            } catch (_: Exception) {}
            throw e
        }
        output.close()

        logger.info("volume archive cache built", ("cachePath", fullCachePath), ("size", getFileSize(fullCachePath).toString()))
        return fullCachePath
    }

    /**
     * 获取底层处理器
     */
    private func getDelegate(): Option<ArchiveHandler> {
        match (delegateHandler) {
            case Some(handler) => return Some(handler)
            case None =>
                let factory = ArchiveHandlerFactory.getInstance()
                // 根据底层格式构建一个临时文件的 canHandle 判断
                let tempPath = "/tmp/__volume_delegate_check.${underlyingFormat}"
                match (factory.getHandlerByPath(tempPath)) {
                    case Some(handler) =>
                        delegateHandler = Some(handler)
                        return Some(handler)
                    case None =>
                        // 回退到默认压缩包处理器
                        delegateHandler = Some(ArchiveFileHandler())
                        return delegateHandler
                }
        }
    }

    // ========== ArchiveHandler 接口实现 ==========

    public func canHandle(filePath: String): Bool {
        return filePath == entryPath
    }

    public func listEntries(_: String): Array<String> {
        if (isRarVolume()) {
            return Archive.listEntriesFromParts(parts)
        }
        let (ok, targetPath) = ensureCache()
        if (!ok) {
            logger.error("volume archive not ready for listEntries", ("error", targetPath))
            return []
        }
        match (getDelegate()) {
            case Some(handler) => return handler.listEntries(targetPath)
            case None =>
                logger.error("no delegate handler available for volume archive")
                return []
        }
    }

    public func extractEntryToStream(_: String, entryName: String): (Int64, Array<UInt8>, Array<UInt8>) {
        if (isRarVolume()) {
            let data = Archive.extractEntryFromParts(parts, entryName)
            if (data.size == 0) {
                return (1i64, Array<UInt8>(), "Entry not found or empty: ${entryName}".toArray())
            }
            return (0i64, data, "success".toArray())
        }
        let (ok, targetPath) = ensureCache()
        if (!ok) {
            return (1i64, Array<UInt8>(), targetPath.toArray())
        }
        match (getDelegate()) {
            case Some(handler) => return handler.extractEntryToStream(targetPath, entryName)
            case None => return (1i64, Array<UInt8>(), "No delegate handler".toArray())
        }
    }

    public func getEntryReader(_: String, entryName: String): (Int64, Option<EntryReader>, String) {
        if (isRarVolume()) {
            let data = Archive.extractEntryFromParts(parts, entryName)
            if (data.size == 0) {
                return (1i64, None, "Entry not found or empty: ${entryName}")
            }
            return (0i64, Some(MemoryEntryReader(data)), "")
        }
        let (ok, targetPath) = ensureCache()
        if (!ok) {
            return (1i64, None, targetPath)
        }
        match (getDelegate()) {
            case Some(handler) => return handler.getEntryReader(targetPath, entryName)
            case None => return (1i64, None, "No delegate handler")
        }
    }

    public func extractEntryToFile(_: String, entryName: String, outputPath: String): Bool {
        if (isRarVolume()) {
            try {
                let data = Archive.extractEntryFromParts(parts, entryName)
                if (data.size == 0) {
                    return false
                }
                let outputDir = FileUtils.getParentDirectory(outputPath)
                if (outputDir.size > 0 && !DirectoryScanner.directoryExists(outputDir)) {
                    Directory.create(Path(outputDir), recursive: true)
                }
                let file = File(Path(outputPath), Write)
                try {
                    file.write(data)
                } finally {
                    try { file.close() } catch (_: Exception) {}
                }
                return true
            } catch (_: Exception) {
                return false
            }
        }
        let (ok, targetPath) = ensureCache()
        if (!ok) {
            return false
        }
        match (getDelegate()) {
            case Some(handler) => return handler.extractEntryToFile(targetPath, entryName, outputPath)
            case None => return false
        }
    }

    public func getMediaCount(_: String): Int32 {
        if (isRarVolume()) {
            return Archive.countMediaEntriesFromParts(parts)
        }
        let (ok, targetPath) = ensureCache()
        if (!ok) {
            return 0
        }
        match (getDelegate()) {
            case Some(handler) => return handler.getMediaCount(targetPath)
            case None => return 0
        }
    }

    public func getFirstCoverEntry(_: String): (String, String) {
        if (isRarVolume()) {
            let best = Archive.findFirstCoverEntryFromParts(parts)
            if (best.size == 0) {
                return ("", "")
            }
            return (best, "")
        }
        let (ok, targetPath) = ensureCache()
        if (!ok) {
            return ("", "")
        }
        match (getDelegate()) {
            case Some(handler) => return handler.getFirstCoverEntry(targetPath)
            case None => return ("", "")
        }
    }

    public func getCoverImage(archivePath: String): (Int64, Array<UInt8>, Array<UInt8>) {
        if (isRarVolume()) {
            let (entryName, _) = getFirstCoverEntry(archivePath)
            if (entryName.size == 0) {
                return (1i64, Array<UInt8>(), "No cover media found".toArray())
            }
            return extractEntryToStream(archivePath, entryName)
        }
        let (ok, targetPath) = ensureCache()
        if (!ok) {
            return (1i64, Array<UInt8>(), targetPath.toArray())
        }
        match (getDelegate()) {
            case Some(handler) => return handler.getCoverImage(targetPath)
            case None => return (1i64, Array<UInt8>(), "No delegate handler".toArray())
        }
    }

    public func listEntriesWithTitle(_: String): Array<(String, String)> {
        if (isRarVolume()) {
            let entries = Archive.listEntriesFromParts(parts)
            var result = ArrayList<(String, String)>()
            for (entry in entries) {
                if (isMediaFile(entry)) {
                    result.add((entry, ""))
                }
            }
            NaturalSort.sortTuples(result)
            return result.toArray()
        }
        let (ok, targetPath) = ensureCache()
        if (!ok) {
            return []
        }
        match (getDelegate()) {
            case Some(handler) => return handler.listEntriesWithTitle(targetPath)
            case None => return []
        }
    }

    // ========== 缓存管理 ==========

    private func isRarVolume(): Bool {
        return volumePatternEq(pattern, VolumePattern.RarVolume)
    }

    private func isMediaFile(filename: String): Bool {
        return isImageFile(filename) || isVideoFile(filename)
    }

    private func isImageFile(filename: String): Bool {
        let parts = filename.split(".")
        if (parts.size <= 1) {
            return false
        }
        let ext = parts[parts.size - 1].toAsciiLower()
        return ext == "avif" || ext == "jpg" || ext == "jpeg" || ext == "png" || ext == "webp" || ext == "gif"
    }

    private func isVideoFile(filename: String): Bool {
        let parts = filename.split(".")
        if (parts.size <= 1) {
            return false
        }
        let ext = parts[parts.size - 1].toAsciiLower()
        return ext == "mp4" || ext == "webm" || ext == "mkv" || ext == "avi" || ext == "mov" || ext == "m4v"
    }

    /**
     * 基于所有分片的路径、大小和修改时间生成指纹。
     */
    private func buildVolumeFingerprint(): String {
        var sha1 = SHA1()
        sha1.write("vol_cache_v${CACHE_VERSION}".toArray())
        for (part in parts) {
            sha1.write(part.toArray())
            let size = getFileSize(part)
            let mtime = getFileModTime(part)
            sha1.write(size.toString().toArray())
            sha1.write(mtime.toString().toArray())
        }
        return toHexString(sha1.finish())
    }

    private static func getFileSize(filePath: String): Int64 {
        try {
            let path = Path(filePath)
            if (!exists(path)) { return 0 }
            return FileInfo(path).size
        } catch (_: Exception) {
            return 0
        }
    }

    private static func getFileModTime(filePath: String): Int64 {
        try {
            let info = FileInfo(Path(filePath))
            return info.lastModificationTime.toUnixTimeStamp().toMilliseconds()
        } catch (_: Exception) {
            return 0
        }
    }

    private static func buildCacheDir(): String {
        // 使用数据目录下的 volume_cache 子目录
        let dataDir = try {
            SystemSettingsService.getPath("CACHE_PATH")
        } catch (_: Exception) {
            "data/cache"
        }
        return FileUtils.joinPath(dataDir, "volume_cache")
    }

    private static func ensureCacheDirExists(dir: String): Unit {
        try {
            if (!exists(Path(dir))) {
                Directory.create(Path(dir), recursive: true)
                logger.info("created volume cache directory", ("dir", dir))
            }
        } catch (e: Exception) {
            logger.error("failed to create volume cache directory", ("dir", dir), ("error", e.message))
        }
    }

    private static func cacheFileValid(cachePath: String): Bool {
        try {
            let path = Path(cachePath)
            if (!exists(path)) {
                return false
            }
            let info = FileInfo(path)
            return info.isRegular() && info.size > 0
        } catch (_: Exception) {
            return false
        }
    }
}
