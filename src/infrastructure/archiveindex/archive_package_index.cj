package lanlu.infrastructure.archiveindex

import std.collection.*
import std.fs.*
import std.io.{ByteBuffer, readToEnd}
import std.sync.*
import std.time.*
import stdx.crypto.digest.*
import stdx.encoding.hex.*
import stdx.encoding.json.stream.*
import stdx.log.*
import lanlu.contexts.archive.domain.*
import lanlu.infrastructure.kv.*
import lanlu.shared.utils.*

public class ArchivePackageFingerprint {
    public var modifiedAtMs: Int64 = 0
    public var fileSize: Int64 = 0
    public var cacheVersion: Int32 = 1
}

public class ArchivePackageEntryRecord {
    public var name: String = ""
    public var title: String = ""
    public var orderIndex: Int32 = 0
    public var kind: String = "unknown"
    public var localHeaderOffset: Int64 = -1
    public var dataOffset: Int64 = -1
    public var compressedSize: Int64 = -1
    public var uncompressedSize: Int64 = -1
    public var compressionMethod: Int32 = -1
    public var crc32: Int64 = 0
    public var isEncrypted: Bool = false
}

public class ArchivePackageIndex {
    public var actualPath: String = ""
    public var archiveType: String = ""
    public var fingerprint: ArchivePackageFingerprint = ArchivePackageFingerprint()
    public var createdAtMs: Int64 = 0
    public var entries: Array<ArchivePackageEntryRecord> = []

    public func findEntry(name: String): Option<ArchivePackageEntryRecord> {
        let normalized = name.trimAscii()
        if (normalized.size == 0) {
            return None
        }
        for (entry in entries) {
            if (entry.name == normalized) {
                return Some(entry)
            }
        }
        return None
    }
}

class ArchivePackageIndexCodec {
    public static func encode(index: ArchivePackageIndex): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("actual_path").writeValue(index.actualPath)
        w.writeName("archive_type").writeValue(index.archiveType)
        w.writeName("created_at_ms").writeValue(index.createdAtMs)
        w.writeName("fingerprint")
        w.startObject()
        w.writeName("modified_at_ms").writeValue(index.fingerprint.modifiedAtMs)
        w.writeName("file_size").writeValue(index.fingerprint.fileSize)
        w.writeName("cache_version").writeValue(index.fingerprint.cacheVersion)
        w.endObject()
        w.writeName("entries")
        w.startArray()
        for (entry in index.entries) {
            w.startObject()
            w.writeName("name").writeValue(entry.name)
            w.writeName("title").writeValue(entry.title)
            w.writeName("order_index").writeValue(entry.orderIndex)
            w.writeName("kind").writeValue(entry.kind)
            w.writeName("local_header_offset").writeValue(entry.localHeaderOffset)
            w.writeName("data_offset").writeValue(entry.dataOffset)
            w.writeName("compressed_size").writeValue(entry.compressedSize)
            w.writeName("uncompressed_size").writeValue(entry.uncompressedSize)
            w.writeName("compression_method").writeValue(entry.compressionMethod)
            w.writeName("crc32").writeValue(entry.crc32)
            w.writeName("is_encrypted").writeValue(entry.isEncrypted)
            w.endObject()
        }
        w.endArray()
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    public static func decode(raw: String): Option<ArchivePackageIndex> {
        let trimmed = raw.trimAscii()
        if (trimmed.size == 0) {
            return None
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return None
            }

            let index = ArchivePackageIndex()
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                match (name) {
                    case "actual_path" => index.actualPath = r.readValue<String>().trimAscii()
                    case "archive_type" => index.archiveType = r.readValue<String>().trimAscii()
                    case "created_at_ms" => index.createdAtMs = r.readValue<Int64>()
                    case "fingerprint" =>
                        let fingerprint = ArchivePackageFingerprint()
                        r.startObject()
                        while (r.peek() != EndObject) {
                            let fpName = r.readName()
                            match (fpName) {
                                case "modified_at_ms" => fingerprint.modifiedAtMs = r.readValue<Int64>()
                                case "file_size" => fingerprint.fileSize = r.readValue<Int64>()
                                case "cache_version" => fingerprint.cacheVersion = r.readValue<Int32>()
                                case _ => r.skip()
                            }
                        }
                        r.endObject()
                        index.fingerprint = fingerprint
                    case "entries" =>
                        let entries = ArrayList<ArchivePackageEntryRecord>()
                        r.startArray()
                        while (r.peek() != EndArray) {
                            let entry = ArchivePackageEntryRecord()
                            r.startObject()
                            while (r.peek() != EndObject) {
                                let entryName = r.readName()
                                match (entryName) {
                                    case "name" => entry.name = r.readValue<String>().trimAscii()
                                    case "title" => entry.title = r.readValue<String>()
                                    case "order_index" => entry.orderIndex = r.readValue<Int32>()
                                    case "kind" => entry.kind = r.readValue<String>().trimAscii()
                                    case "local_header_offset" => entry.localHeaderOffset = r.readValue<Int64>()
                                    case "data_offset" => entry.dataOffset = r.readValue<Int64>()
                                    case "compressed_size" => entry.compressedSize = r.readValue<Int64>()
                                    case "uncompressed_size" => entry.uncompressedSize = r.readValue<Int64>()
                                    case "compression_method" => entry.compressionMethod = r.readValue<Int32>()
                                    case "crc32" => entry.crc32 = r.readValue<Int64>()
                                    case "is_encrypted" => entry.isEncrypted = r.readValue<Bool>()
                                    case _ => r.skip()
                                }
                            }
                            r.endObject()
                            entries.add(entry)
                        }
                        r.endArray()
                        index.entries = entries.toArray()
                    case _ => r.skip()
                }
            }
            r.endObject()
            return Some(index)
        } catch (_: Exception) {
            return None
        }
    }
}

public class ArchivePackageIndexStore {
    private static let logger = getLogger("archive_package_index_store")
    private static let namespace = "archive_package_index"
    private static let cacheVersion: Int32 = 1
    private static let buildLockCount: Int64 = 64
    private static let buildLocks: Array<Mutex> = Array<Mutex>(buildLockCount, {
        i => if (i >= 0) { Mutex() } else { Mutex() }
    })

    public static func getOrBuild(
        archiveType: String,
        actualPath: String,
        listEntriesWithTitle: (String) -> Array<(String, String)>
    ): Option<ArchivePackageIndex> {
        let normalizedPath = actualPath.trimAscii()
        if (normalizedPath.size == 0) {
            return None
        }
        if (!shouldUsePersistentCache(archiveType, normalizedPath)) {
            return None
        }

        let fingerprint = buildFingerprint(normalizedPath)
        let key = buildStorageKey(archiveType, normalizedPath)
        let storeOpt = LocalKVService.getStore()

        // Singleflight: serialize build path by (archiveType + actualPath) to avoid
        // concurrent cache misses repeatedly rebuilding the same index.
        let buildMutex = getBuildMutex("${archiveType}:${normalizedPath}")
        buildMutex.lock()
        try {
            match (storeOpt) {
                case Some(store) =>
                    match (store.get(namespace, key)) {
                        case Some(payload) =>
                            match (ArchivePackageIndexCodec.decode(payload)) {
                                case Some(index) =>
                                    if (matchesFingerprint(index, archiveType, normalizedPath, fingerprint)) {
                                        logger.debug("archive package index hit", ("path", normalizedPath))
                                        return Some(index)
                                    }
                                    let _ = store.delete(namespace, key)
                                    logger.debug("archive package index stale", ("path", normalizedPath))
                                case None =>
                                    let _ = store.delete(namespace, key)
                                    logger.warn("archive package index decode failed; evicted key", ("path", normalizedPath))
                            }
                        case None => ()
                    }
                case None => ()
            }

            match (buildIndex(archiveType, normalizedPath, listEntriesWithTitle, fingerprint)) {
                case Some(index) =>
                    match (storeOpt) {
                        case Some(store) =>
                            let encoded = ArchivePackageIndexCodec.encode(index)
                            if (!store.put(namespace, key, encoded)) {
                                logger.warn("failed to persist archive package index", ("path", normalizedPath))
                            }
                        case None => ()
                    }
                    return Some(index)
                case None =>
                    logger.warn("failed to build archive package index", ("path", normalizedPath), ("archive_type", archiveType))
                    return None
            }
        } finally {
            buildMutex.unlock()
        }
    }

    private static func buildIndex(
        archiveType: String,
        actualPath: String,
        listEntriesWithTitle: (String) -> Array<(String, String)>,
        fingerprint: ArchivePackageFingerprint
    ): Option<ArchivePackageIndex> {
        if (archiveType == ArchiveTypes.ARCHIVE && ZipPackageIndexBuilder.canHandle(actualPath)) {
            match (ZipPackageIndexBuilder.build(actualPath, fingerprint, cacheVersion)) {
                case Some(index) => return Some(index)
                case None =>
                    logger.warn("zip package index builder failed; falling back to handler enumeration", ("path", actualPath))
            }
        }

        let entriesWithTitle = listEntriesWithTitle(actualPath)
        let entries = ArrayList<ArchivePackageEntryRecord>()
        for (i in 0..entriesWithTitle.size) {
            let entry = ArchivePackageEntryRecord()
            entry.name = entriesWithTitle[i][0]
            entry.title = entriesWithTitle[i][1]
            entry.orderIndex = Int32(i)
            entry.kind = detectEntryKind(archiveType, entry.name)
            entries.add(entry)
        }

        let index = ArchivePackageIndex()
        index.actualPath = actualPath
        index.archiveType = archiveType
        index.fingerprint = fingerprint
        index.createdAtMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        index.entries = entries.toArray()
        return Some(index)
    }

    private static func matchesFingerprint(
        index: ArchivePackageIndex,
        archiveType: String,
        actualPath: String,
        fingerprint: ArchivePackageFingerprint
    ): Bool {
        return index.archiveType == archiveType &&
               index.actualPath == actualPath &&
               index.fingerprint.cacheVersion == fingerprint.cacheVersion &&
               index.fingerprint.modifiedAtMs == fingerprint.modifiedAtMs &&
               index.fingerprint.fileSize == fingerprint.fileSize
    }

    private static func buildFingerprint(actualPath: String): ArchivePackageFingerprint {
        let fingerprint = ArchivePackageFingerprint()
        fingerprint.cacheVersion = cacheVersion
        try {
            let info = FileInfo(Path(actualPath))
            fingerprint.modifiedAtMs = info.lastModificationTime.toUnixTimeStamp().toMilliseconds()
            fingerprint.fileSize = if (info.isDirectory()) {
                0
            } else {
                let file = File(Path(actualPath), Read)
                let size = file.info.size
                file.close()
                size
            }
        } catch (_: Exception) {
            fingerprint.modifiedAtMs = 0
            fingerprint.fileSize = 0
        }
        return fingerprint
    }

    private static func buildStorageKey(archiveType: String, actualPath: String): String {
        var sha1 = SHA1()
        sha1.write(actualPath.toArray())
        let hash = toHexString(sha1.finish())
        return "${archiveType}:${hash}"
    }

    private static func detectEntryKind(archiveType: String, entryName: String): String {
        if (archiveType == ArchiveTypes.EPUB) {
            return "html"
        }
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

    private static func shouldUsePersistentCache(archiveType: String, actualPath: String): Bool {
        if (archiveType == ArchiveTypes.FOLDER) {
            return false
        }
        try {
            return !FileInfo(Path(actualPath)).isDirectory()
        } catch (_: Exception) {
            return archiveType != ArchiveTypes.FOLDER
        }
    }

    private static func getBuildMutex(key: String): Mutex {
        let hash = key.hashCode()
        let positiveHash = if (hash < 0) { -hash } else { hash }
        return buildLocks[positiveHash % buildLocks.size]
    }
}
