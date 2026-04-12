package lanlu.infrastructure.archiveindex

import std.collection.*
import std.fs.*
import std.io.SeekPosition
import std.sort.*
import std.time.*
import stdx.log.*
import lanlu.shared.utils.*

public class ZipPackageIndexBuilder {
    private static let logger = getLogger("zip_package_index_builder")
    private static let eocdSignature: UInt32 = 0x06054b50u32
    private static let centralDirectorySignature: UInt32 = 0x02014b50u32
    private static let localHeaderSignature: UInt32 = 0x04034b50u32
    private static let eocdSearchWindow: Int64 = 65535 + 22 + 1024

    public static func canHandle(actualPath: String): Bool {
        let ext = ArchiveUtils.getFileExtension(actualPath).toAsciiLower()
        return ext == "zip" || ext == "cbz"
    }

    public static func build(
        actualPath: String,
        fingerprint: ArchivePackageFingerprint,
        cacheVersion: Int32
    ): Option<ArchivePackageIndex> {
        try {
            let file = File(Path(actualPath), Read)
            try {
                let fileSize = file.info.size
                if (fileSize < 22) {
                    return None
                }

                let eocdPos = findEndOfCentralDirectory(file, fileSize)
                if (eocdPos < 0) {
                    return None
                }

                let eocd = readExactly(file, eocdPos, 22)
                if (eocd.size < 22 || readUInt32LE(eocd, 0) != eocdSignature) {
                    return None
                }

                let diskNo = readUInt16LE(eocd, 4)
                let cdStartDisk = readUInt16LE(eocd, 6)
                let entriesOnDisk = readUInt16LE(eocd, 8)
                let totalEntries = readUInt16LE(eocd, 10)
                let centralDirectorySize = Int64(readUInt32LE(eocd, 12))
                let centralDirectoryOffset = Int64(readUInt32LE(eocd, 16))

                if (diskNo != 0u16 || cdStartDisk != 0u16 || entriesOnDisk != totalEntries) {
                    logger.warn("multi-disk zip is unsupported", ("path", actualPath))
                    return None
                }
                if (totalEntries == 0xFFFFu16 || centralDirectoryOffset == 0xFFFFFFFFi64 || centralDirectorySize == 0xFFFFFFFFi64) {
                    logger.warn("zip64 is unsupported", ("path", actualPath))
                    return None
                }
                if (centralDirectoryOffset < 0 || centralDirectorySize < 0 || centralDirectoryOffset + centralDirectorySize > fileSize) {
                    return None
                }

                let centralDirectory = readExactly(file, centralDirectoryOffset, centralDirectorySize)
                let records = parseCentralDirectory(file, centralDirectory)

                sort<ArchivePackageEntryRecord>(records, by: { a, b =>
                    NaturalSort.naturalCompare(a.name, b.name)
                })

                for (i in 0..records.size) {
                    records[i].orderIndex = Int32(i)
                }

                let index = ArchivePackageIndex()
                index.actualPath = actualPath
                index.archiveType = "archive"
                index.fingerprint = fingerprint
                index.fingerprint.cacheVersion = cacheVersion
                index.createdAtMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
                index.entries = records.toArray()
                return Some(index)
            } finally {
                file.close()
            }
        } catch (e: Exception) {
            logger.warn("failed to build zip package index", ("path", actualPath), ("error", e.message))
            return None
        }
    }

    private static func parseCentralDirectory(file: File, centralDirectory: Array<Byte>): ArrayList<ArchivePackageEntryRecord> {
        let records = ArrayList<ArchivePackageEntryRecord>()
        var offset: Int64 = 0
        while (offset + 46 <= Int64(centralDirectory.size)) {
            if (readUInt32LE(centralDirectory, offset) != centralDirectorySignature) {
                break
            }

            let flags = readUInt16LE(centralDirectory, offset + 8)
            let compressionMethod = Int32(readUInt16LE(centralDirectory, offset + 10))
            let crc32 = Int64(readUInt32LE(centralDirectory, offset + 16))
            let compressedSize = Int64(readUInt32LE(centralDirectory, offset + 20))
            let uncompressedSize = Int64(readUInt32LE(centralDirectory, offset + 24))
            let fileNameLen = Int64(readUInt16LE(centralDirectory, offset + 28))
            let extraLen = Int64(readUInt16LE(centralDirectory, offset + 30))
            let commentLen = Int64(readUInt16LE(centralDirectory, offset + 32))
            let localHeaderOffset = Int64(readUInt32LE(centralDirectory, offset + 42))

            let headerEnd = offset + 46 + fileNameLen + extraLen + commentLen
            if (headerEnd > Int64(centralDirectory.size)) {
                break
            }

            let nameBytes = sliceBytes(centralDirectory, offset + 46, fileNameLen)
            let name = decodeZipName(nameBytes, (flags & 0x0800u16) != 0u16)
            if (name.size > 0 && !name.endsWith("/") && ArchiveUtils.isMediaFile(name)) {
                let record = ArchivePackageEntryRecord()
                record.name = name
                record.title = ""
                record.kind = detectKind(name)
                record.localHeaderOffset = localHeaderOffset
                record.dataOffset = computeDataOffset(file, localHeaderOffset)
                record.compressedSize = compressedSize
                record.uncompressedSize = uncompressedSize
                record.compressionMethod = compressionMethod
                record.crc32 = crc32
                record.isEncrypted = (flags & 0x0001u16) != 0u16
                records.add(record)
            }

            offset = headerEnd
        }
        return records
    }

    private static func findEndOfCentralDirectory(file: File, fileSize: Int64): Int64 {
        let searchWindow = if (fileSize < eocdSearchWindow) { fileSize } else { eocdSearchWindow }
        let start = fileSize - searchWindow
        let tail = readExactly(file, start, searchWindow)
        var pos = Int64(tail.size) - 22
        while (pos >= 0) {
            if (readUInt32LE(tail, pos) == eocdSignature) {
                return start + pos
            }
            pos--
        }
        return -1
    }

    private static func computeDataOffset(file: File, localHeaderOffset: Int64): Int64 {
        try {
            let localHeader = readExactly(file, localHeaderOffset, 30)
            if (localHeader.size < 30 || readUInt32LE(localHeader, 0) != localHeaderSignature) {
                return -1
            }
            let fileNameLen = Int64(readUInt16LE(localHeader, 26))
            let extraLen = Int64(readUInt16LE(localHeader, 28))
            return localHeaderOffset + 30 + fileNameLen + extraLen
        } catch (_: Exception) {
            return -1
        }
    }

    private static func readExactly(file: File, offset: Int64, length: Int64): Array<Byte> {
        if (length <= 0) {
            return []
        }
        let out = Array<Byte>(length, repeat: 0)
        file.seek(SeekPosition.Begin(offset))
        var totalRead: Int64 = 0
        while (totalRead < length) {
            let remaining = length - totalRead
            let chunk = Array<Byte>(remaining, repeat: 0)
            let bytesRead = file.read(chunk)
            if (bytesRead <= 0) {
                break
            }
            for (i in 0..bytesRead) {
                out[totalRead + i] = chunk[i]
            }
            totalRead += bytesRead
        }
        if (totalRead == length) {
            return out
        }
        return out.slice(0, totalRead)
    }

    private static func sliceBytes(data: Array<Byte>, start: Int64, length: Int64): Array<Byte> {
        if (length <= 0) {
            return []
        }
        return data.slice(start, length).toArray()
    }

    private static func readUInt16LE(data: Array<Byte>, offset: Int64): UInt16 {
        let b0 = UInt16(UInt8(data[offset]))
        let b1 = UInt16(UInt8(data[offset + 1]))
        return b0 | (b1 << 8)
    }

    private static func readUInt32LE(data: Array<Byte>, offset: Int64): UInt32 {
        let b0 = UInt32(UInt8(data[offset]))
        let b1 = UInt32(UInt8(data[offset + 1]))
        let b2 = UInt32(UInt8(data[offset + 2]))
        let b3 = UInt32(UInt8(data[offset + 3]))
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    private static func decodeZipName(bytes: Array<Byte>, preferUtf8: Bool): String {
        if (bytes.size == 0) {
            return ""
        }
        if (preferUtf8) {
            try {
                return String.fromUtf8(Array<UInt8>(bytes.size, { i => UInt8(bytes[i]) }))
            } catch (_: Exception) {}
        }
        try {
            return String.fromUtf8(Array<UInt8>(bytes.size, { i => UInt8(bytes[i]) }))
        } catch (_: Exception) {
            var out = ""
            for (b in bytes) {
                out += Rune(UInt32(UInt8(b))).toString()
            }
            return out
        }
    }

    private static func detectKind(entryName: String): String {
        if (ArchiveUtils.isImageFile(entryName)) {
            return "image"
        }
        if (ArchiveUtils.isVideoFile(entryName)) {
            return "video"
        }
        if (ArchiveUtils.isAudioFile(entryName)) {
            return "audio"
        }
        return "unknown"
    }
}
