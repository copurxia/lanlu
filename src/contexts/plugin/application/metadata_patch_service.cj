package lanlu.contexts.plugin.application

import std.collection.*
import std.convert.*
import std.io.{ByteBuffer, readToEnd}
import std.time.*
import stdx.encoding.json.stream.*
import lanlu.contexts.plugin.domain.*
import lanlu.contexts.archive.infrastructure.persistence.*
import lanlu.contexts.tankoubon.infrastructure.persistence.*
import lanlu.contexts.tag.infrastructure.persistence.*
import lanlu.contexts.asset.infrastructure.persistence.*
import lanlu.contexts.category.infrastructure.persistence.*
import lanlu.shared.utils.*
import lanlu.infrastructure.archivehandler.*

class MetadataAssetEntry {
    public var key: String = ""
    public var value: String = ""

    public init(key: String, value: String) {
        this.key = key
        this.value = value
    }
}

public class MetadataPatchService {
    private static let logger = getLogger("metadata_patch_service")

    private static func logInfo(taskId: Int64, message: String): Unit {
        if (taskId > 0) {
            TaskIO.appendLog(taskId, message)
        } else {
            logger.info(message)
        }
    }

    private static func logWarn(taskId: Int64, message: String): Unit {
        if (taskId > 0) {
            TaskIO.appendLog(taskId, "WARN: ${message}")
        } else {
            logger.warn(message)
        }
    }

    private static func splitTagTokens(tagsString: String): Array<String> {
        let trimmed = tagsString.trimAscii()
        if (trimmed.size == 0) {
            return Array<String>()
        }

        let seen = HashSet<String>()
        let out = ArrayList<String>()
        let parts = trimmed.split(",")
        for (part in parts) {
            let tag = part.trimAscii()
            if (tag.size == 0 || seen.contains(tag)) {
                continue
            }
            seen.add(tag)
            out.add(tag)
        }
        return out.toArray()
    }

    private static func parseMetadataAssetsRaw(assetsRaw: String): Array<MetadataAssetEntry> {
        let normalized = assetsRaw.trimAscii()
        if (normalized.size == 0 || normalized == "null") {
            return Array<MetadataAssetEntry>()
        }

        let seen = HashSet<String>()
        let out = ArrayList<MetadataAssetEntry>()
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(normalized.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return Array<MetadataAssetEntry>()
            }

            r.startObject()
            while (r.peek() != EndObject) {
                let key = r.readName().trimAscii().toAsciiLower()
                if (key.size == 0) {
                    r.skip()
                    continue
                }

                var value = ""
                match (r.peek()) {
                    case Some(BeginObject) => r.skip()
                    case Some(BeginArray) => r.skip()
                    case Some(_) => value = r.readValue<String>().trimAscii()
                    case None => ()
                }

                if (value.size == 0 || seen.contains(key)) {
                    continue
                }
                seen.add(key)
                out.add(MetadataAssetEntry(key, value))
            }
            r.endObject()
        } catch (_: Exception) {}

        return out.toArray()
    }

    private static func readJsonScalarAsString(r: JsonReader): String {
        match (r.peek()) {
            case Some(BeginObject) =>
                let bytes = r.readValueBytes()
                return String.fromUtf8(bytes)
            case Some(BeginArray) =>
                let bytes = r.readValueBytes()
                return String.fromUtf8(bytes)
            case Some(_) => return r.readValue<String>()
            case None => return ""
        }
    }

    private static func readJsonInt64Flexible(r: JsonReader, defaultValue: Int64): Int64 {
        let s = readJsonScalarAsString(r).trimAscii()
        if (s.size == 0) { return defaultValue }
        try { return Int64.parse(s) } catch (_: Exception) { return defaultValue }
    }

    private static func isSyntheticEntryPath(entryPath: String): Bool {
        let trimmed = entryPath.trimAscii()
        return trimmed.startsWith("__page_")
    }

    public static func extractMetadataNamespace(raw: String): String {
        let trimmed = raw.trimAscii()
        if (trimmed.size == 0) {
            return ""
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return ""
            }

            r.startObject()
            while (r.peek() != EndObject) {
                let key = r.readName().trimAscii()
                match (key) {
                    case "metadata_namespace" => return readJsonScalarAsString(r).trimAscii()
                    case "metadataNamespace" => return readJsonScalarAsString(r).trimAscii()
                    case "plugin_namespace" => return readJsonScalarAsString(r).trimAscii()
                    case "pluginNamespace" => return readJsonScalarAsString(r).trimAscii()
                    case "namespace" => return readJsonScalarAsString(r).trimAscii()
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}

        return ""
    }

    public static func extractCoverAssetId(raw: String): Int64 {
        let trimmed = raw.trimAscii()
        if (trimmed.size == 0) {
            return -1i64
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return -1i64
            }

            r.startObject()
            while (r.peek() != EndObject) {
                let key = r.readName().trimAscii()
                match (key) {
                    case "cover_asset_id" => return readJsonInt64Flexible(r, -1i64)
                    case "coverAssetId" => return readJsonInt64Flexible(r, -1i64)
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}

        return -1i64
    }

    public static func parseMetadataObject(raw: String): ParsedMetadataResult {
        let trimmed = raw.trimAscii()
        if (trimmed.size == 0) {
            return ParsedMetadataResult(false, "Metadata object is empty", "", "", "")
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return ParsedMetadataResult(false, "Metadata object is not a JSON object", "", "", "")
            }

            func readStringFlexible(): String {
                return readJsonScalarAsString(r)
            }

            func readBoolFlexible(): Bool {
                let v = readStringFlexible().trimAscii().toAsciiLower()
                return v == "true" || v == "1"
            }

            func readInt32Flexible(): Int32 {
                let s = readStringFlexible().trimAscii()
                try { return Int32.parse(s) } catch (_: Exception) { return 0 }
            }

            func readTagsFlexible(): String {
                match (r.peek()) {
                    case Some(BeginArray) =>
                        let seen = HashSet<String>()
                        let out = ArrayList<String>()
                        r.startArray()
                        while (r.peek() != EndArray) {
                            let tag = readStringFlexible().trimAscii()
                            if (tag.size == 0 || seen.contains(tag)) {
                                continue
                            }
                            seen.add(tag)
                            out.add(tag)
                        }
                        r.endArray()
                        return String.join(out.toArray(), delimiter: ", ")
                    case _ => return readStringFlexible().trimAscii()
                }
            }

            func parsePagePatchObject(): PageMetadataPatch {
                let patch = PageMetadataPatch()
                if (r.peek() != Some(BeginObject)) {
                    return patch
                }

                r.startObject()
                while (r.peek() != EndObject) {
                    let pk = r.readName()
                    match (pk) {
                        case "page" => patch.page = readInt32Flexible()
                        case "page_number" => patch.page = readInt32Flexible()
                        case "pageNumber" => patch.page = readInt32Flexible()
                        case "path" => patch.path = readStringFlexible().trimAscii()
                        case "entry" => patch.path = readStringFlexible().trimAscii()
                        case "entry_path" => patch.path = readStringFlexible().trimAscii()
                        case "entryPath" => patch.path = readStringFlexible().trimAscii()
                        case "title" => patch.title = readStringFlexible()
                        case "description" => patch.description = readStringFlexible()
                        case "summary" => patch.description = readStringFlexible()
                        case "thumb" => patch.thumb = readStringFlexible().trimAscii()
                        case "sort" =>
                            patch.sort = readInt32Flexible()
                            patch.sortProvided = true
                        case "hidden_in_files" =>
                            patch.hiddenInFiles = readBoolFlexible()
                            patch.hiddenInFilesProvided = true
                        case "hiddenInFiles" =>
                            patch.hiddenInFiles = readBoolFlexible()
                            patch.hiddenInFilesProvided = true
                        case "metadata" =>
                            if (r.peek() == Some(BeginObject)) {
                                r.startObject()
                                while (r.peek() != EndObject) {
                                    let mk = r.readName()
                                    match (mk) {
                                        case "thumb" =>
                                            let nestedThumb = readStringFlexible().trimAscii()
                                            if (patch.thumb.trimAscii().size == 0 && nestedThumb.size > 0) {
                                                patch.thumb = nestedThumb
                                            }
                                        case _ => r.skip()
                                    }
                                }
                                r.endObject()
                            } else {
                                r.skip()
                            }
                        case _ => r.skip()
                    }
                }
                r.endObject()
                return patch
            }

            func parseAssetFieldsToPatch(patch: ArchiveMetadataPatch): ArchiveMetadataPatch {
                var updated = patch
                match (r.peek()) {
                    case Some(BeginArray) =>
                        r.startArray()
                        while (r.peek() != EndArray) {
                            if (r.peek() != Some(BeginObject)) {
                                r.skip()
                                continue
                            }
                            var key = ""
                            var value = ""
                            r.startObject()
                            while (r.peek() != EndObject) {
                                let assetKey = r.readName()
                                match (assetKey) {
                                    case "key" => key = readStringFlexible().trimAscii().toAsciiLower()
                                    case "value" => value = readStringFlexible().trimAscii()
                                    case _ => r.skip()
                                }
                            }
                            r.endObject()
                            if (key == "cover") {
                                updated.cover = value
                                updated.coverProvided = true
                            } else if (key == "backdrop") {
                                updated.backdrop = value
                                updated.backdropProvided = true
                            } else if (key == "clearlogo") {
                                updated.clearlogo = value
                                updated.clearlogoProvided = true
                            }
                        }
                        r.endArray()
                    case Some(BeginObject) =>
                        r.startObject()
                        while (r.peek() != EndObject) {
                            let assetKey = r.readName().trimAscii().toAsciiLower()
                            let value = readStringFlexible().trimAscii()
                            if (assetKey == "cover") {
                                updated.cover = value
                                updated.coverProvided = true
                            } else if (assetKey == "backdrop") {
                                updated.backdrop = value
                                updated.backdropProvided = true
                            } else if (assetKey == "clearlogo") {
                                updated.clearlogo = value
                                updated.clearlogoProvided = true
                            }
                        }
                        r.endObject()
                    case Some(_) => r.skip()
                    case None => ()
                }
                return updated
            }

            func parseArchivePatchObject(): ArchiveMetadataPatch {
                var patch = ArchiveMetadataPatch()
                if (r.peek() != Some(BeginObject)) {
                    return patch
                }

                r.startObject()
                while (r.peek() != EndObject) {
                    let ak = r.readName()
                    match (ak) {
                        case "archive_id" => patch.archiveId = readStringFlexible().trimAscii()
                        case "archiveId" => patch.archiveId = readStringFlexible().trimAscii()
                        case "target_id" =>
                            if (patch.archiveId.size == 0) { patch.archiveId = readStringFlexible().trimAscii() } else { r.skip() }
                        case "targetId" =>
                            if (patch.archiveId.size == 0) { patch.archiveId = readStringFlexible().trimAscii() } else { r.skip() }
                        case "id" =>
                            if (patch.archiveId.size == 0) { patch.archiveId = readStringFlexible().trimAscii() } else { r.skip() }
                        case "volume_no" => patch.volumeNo = readInt32Flexible()
                        case "volumeNo" => patch.volumeNo = readInt32Flexible()
                        case "title" =>
                            patch.title = readStringFlexible()
                            patch.titleProvided = true
                        case "name" =>
                            patch.title = readStringFlexible()
                            patch.titleProvided = true
                        case "description" =>
                            patch.summary = readStringFlexible()
                            patch.summaryProvided = true
                        case "summary" =>
                            patch.summary = readStringFlexible()
                            patch.summaryProvided = true
                        case "tags" =>
                            patch.tags = readTagsFlexible()
                            patch.tagsProvided = true
                        case "updated_at" =>
                            patch.updatedAt = readStringFlexible().trimAscii()
                            patch.updatedAtProvided = true
                        case "updatedAt" =>
                            patch.updatedAt = readStringFlexible().trimAscii()
                            patch.updatedAtProvided = true
                        case "cover" =>
                            patch.cover = readStringFlexible().trimAscii()
                            patch.coverProvided = true
                        case "backdrop" =>
                            patch.backdrop = readStringFlexible().trimAscii()
                            patch.backdropProvided = true
                        case "clearlogo" =>
                            patch.clearlogo = readStringFlexible().trimAscii()
                            patch.clearlogoProvided = true
                        case "assets" => patch = parseAssetFieldsToPatch(patch)
                        case "pages" =>
                            match (r.peek()) {
                                case Some(BeginArray) =>
                                    let pages = ArrayList<PageMetadataPatch>()
                                    r.startArray()
                                    while (r.peek() != EndArray) {
                                        let pagePatch = parsePagePatchObject()
                                        if (pagePatch.page > 0 || pagePatch.path.trimAscii().size > 0) {
                                            pages.add(pagePatch)
                                        }
                                    }
                                    r.endArray()
                                    patch.pages = pages.toArray()
                                case Some(_) => r.skip()
                                case None => ()
                            }
                        case "archive" =>
                            // Archive members are the recursive boundary for now; ignore deeper nesting.
                            r.skip()
                        case _ => r.skip()
                    }
                }
                r.endObject()
                return patch
            }

            let parsed = ParsedMetadataResult()
            parsed.success = true
            r.startObject()
            while (r.peek() != EndObject) {
                let key = r.readName()
                match (key) {
                    case "title" =>
                        parsed.title = readStringFlexible()
                        parsed.titleProvided = true
                    case "name" =>
                        parsed.title = readStringFlexible()
                        parsed.titleProvided = true
                    case "description" =>
                        parsed.summary = readStringFlexible()
                        parsed.summaryProvided = true
                    case "summary" =>
                        parsed.summary = readStringFlexible()
                        parsed.summaryProvided = true
                    case "tags" =>
                        parsed.tags = readTagsFlexible()
                        parsed.tagsProvided = true
                    case "cover" =>
                        parsed.cover = readStringFlexible().trimAscii()
                        parsed.coverProvided = true
                    case "backdrop" =>
                        parsed.backdrop = readStringFlexible().trimAscii()
                        parsed.backdropProvided = true
                    case "clearlogo" =>
                        parsed.clearlogo = readStringFlexible().trimAscii()
                        parsed.clearlogoProvided = true
                    case "assets" =>
                        let topPatch = parseAssetFieldsToPatch(ArchiveMetadataPatch())
                        if (topPatch.coverProvided) {
                            parsed.cover = topPatch.cover
                            parsed.coverProvided = true
                        }
                        if (topPatch.backdropProvided) {
                            parsed.backdrop = topPatch.backdrop
                            parsed.backdropProvided = true
                        }
                        if (topPatch.clearlogoProvided) {
                            parsed.clearlogo = topPatch.clearlogo
                            parsed.clearlogoProvided = true
                        }
                    case "archive" =>
                        parsed.archivesProvided = true
                        match (r.peek()) {
                            case Some(BeginArray) =>
                                let archives = ArrayList<ArchiveMetadataPatch>()
                                r.startArray()
                                while (r.peek() != EndArray) {
                                    let patch = parseArchivePatchObject()
                                    if (patch.archiveId.trimAscii().size > 0 || patch.volumeNo > 0 || patch.pages.size > 0) {
                                        archives.add(patch)
                                    }
                                }
                                r.endArray()
                                parsed.archives = archives.toArray()
                            case Some(_) => r.skip()
                            case None => ()
                        }
                    case "pages" =>
                        match (r.peek()) {
                            case Some(BeginArray) =>
                                let pages = ArrayList<PageMetadataPatch>()
                                r.startArray()
                                while (r.peek() != EndArray) {
                                    let pagePatch = parsePagePatchObject()
                                    if (pagePatch.page > 0 || pagePatch.path.trimAscii().size > 0) {
                                        pages.add(pagePatch)
                                    }
                                }
                                r.endArray()
                                parsed.pages = pages.toArray()
                            case Some(_) => r.skip()
                            case None => ()
                        }
                    case _ => r.skip()
                }
            }
            r.endObject()
            return parsed
        } catch (e: Exception) {
            return ParsedMetadataResult(false, "Failed to parse metadata object: ${e.message}", "", "", "")
        }
    }

    public static func parsePluginOutput(output: String): ParsedMetadataResult {
        let trimmed = output.trimAscii()
        if (trimmed.size == 0) {
            return ParsedMetadataResult(false, "Plugin returned empty output", "", "", "")
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return ParsedMetadataResult(false, "Plugin output is not a JSON object", "", "", "")
            }

            var successSeen = false
            var success = false
            var dataSeen = false
            var err = ""
            var dataRaw = ""

            r.startObject()
            while (r.peek() != EndObject) {
                let key = r.readName()
                match (key) {
                    case "success" =>
                        successSeen = true
                        let v = readJsonScalarAsString(r).trimAscii().toAsciiLower()
                        success = v == "true" || v == "1"
                    case "error" => err = readJsonScalarAsString(r)
                    case "data" =>
                        dataSeen = true
                        match (r.peek()) {
                            case Some(BeginObject) =>
                                let bytes = r.readValueBytes()
                                dataRaw = String.fromUtf8(bytes)
                            case Some(_) => r.skip()
                            case None => ()
                        }
                    case _ => r.skip()
                }
            }
            r.endObject()

            if (!successSeen) {
                return parseMetadataObject(trimmed)
            }
            if (!success) {
                let msg = if (err.trimAscii().size > 0) { err.trimAscii() } else { "Plugin returned success=false" }
                return ParsedMetadataResult(false, msg, "", "", "")
            }
            if (!dataSeen || dataRaw.trimAscii().size == 0) {
                return ParsedMetadataResult(false, "Plugin output missing metadata data object", "", "", "")
            }
            return parseMetadataObject(dataRaw)
        } catch (e: Exception) {
            return ParsedMetadataResult(false, "Failed to parse plugin output: ${e.message}", "", "", "")
        }
    }

    private static func writeMetadataTagsArray(w: JsonWriter, tagsString: String): Unit {
        let tags = splitTagTokens(tagsString)
        w.writeName("tags")
        w.startArray()
        for (tag in tags) {
            w.writeValue(tag)
        }
        w.endArray()
    }

    private static func writeMetadataAssetsArray(w: JsonWriter, assetsRaw: String): Unit {
        let assets = parseMetadataAssetsRaw(assetsRaw)
        w.writeName("assets")
        w.startArray()
        for (asset in assets) {
            if (asset.key.trimAscii().size == 0 || asset.value.trimAscii().size == 0) {
                continue
            }
            w.startObject()
            w.writeName("key").writeValue(asset.key)
            w.writeName("value").writeValue(asset.value)
            w.endObject()
        }
        w.endArray()
    }

    private static func writePageMetadataArray(w: JsonWriter, pageMetadata: Array<PageMetadataData>): Unit {
        w.writeName("pages")
        w.startArray()
        for (meta in pageMetadata) {
            w.startObject()
            if (meta.page_number > 0) {
                w.writeName("page").writeValue(meta.page_number)
            }
            let pathValue = meta.entry_path.trimAscii()
            if (pathValue.size > 0 && !isSyntheticEntryPath(pathValue)) {
                w.writeName("path").writeValue(pathValue)
            }
            if (meta.title.trimAscii().size > 0) {
                w.writeName("title").writeValue(meta.title)
            }
            if (meta.description.trimAscii().size > 0) {
                w.writeName("description").writeValue(meta.description)
            }
            if (meta.thumb_asset_id > 0) {
                w.writeName("thumb").writeValue(meta.thumb_asset_id)
            }
            if (meta.sort_index > 0) {
                w.writeName("sort").writeValue(meta.sort_index)
            }
            if (meta.hidden_in_files) {
                w.writeName("hidden_in_files").writeValue(meta.hidden_in_files)
            }
            w.endObject()
        }
        w.endArray()
    }

    private static func buildArchiveMetadataObjectJsonFromParts(
        archive: ArchiveData,
        tags: String,
        assetsRaw: String,
        includeLocator: Bool,
        volumeNo: Int32,
        includePages: Bool,
        progress!: Int32 = 0i32,
        isNew!: Bool = false,
        isFavorite!: Bool = false,
        lastReadTime!: Int64 = 0i64
    ): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("title").writeValue(archive.title)
        w.writeName("type").writeValue(0i32)
        w.writeName("description").writeValue(archive.summary)
        w.writeName("summary").writeValue(archive.summary)
        writeMetadataTagsArray(w, tags)
        writeMetadataAssetsArray(w, assetsRaw)
        w.writeName("arcid").writeValue(archive.id)
        w.writeName("filename").writeValue(archive.filename)
        w.writeName("relative_path").writeValue(archive.relative_path)
        w.writeName("file_size").writeValue(archive.file_size)
        w.writeName("size").writeValue(archive.file_size)
        w.writeName("pagecount").writeValue(archive.pagecount)
        w.writeName("progress").writeValue(progress)
        w.writeName("isnew").writeValue(isNew)
        w.writeName("isfavorite").writeValue(isFavorite)
        w.writeName("lastreadtime").writeValue(lastReadTime)
        w.writeName("archivetype").writeValue(archive.archive_type)
        w.writeName("created_at").writeValue(archive.created_at)
        w.writeName("updated_at").writeValue(archive.updated_at)
        w.writeName("archive")
        w.startArray()
        w.endArray()
        if (includePages) {
            writePageMetadataArray(w, ArchiveDao.getPageMetadata(archive.id))
        }
        w.writeName("thumbnail_hash").writeValue(archive.thumbhash)
        if (includeLocator) {
            w.writeName("archive_id").writeValue(archive.id)
            if (volumeNo > 0) {
                w.writeName("volume_no").writeValue(volumeNo)
            }
        }
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    public static func buildArchiveMetadataObjectJson(
        archiveId: String,
        includeLocator: Bool,
        volumeNo: Int32,
        includePages!: Bool = false,
        progress!: Int32 = 0i32,
        isNew!: Bool = false,
        isFavorite!: Bool = false,
        lastReadTime!: Int64 = 0i64
    ): (Bool, String, String) {
        let archive = ArchiveDao.getArchiveById(archiveId)
        if (archive.id.size == 0) {
            return (false, "", "Archive not found")
        }

        let tags = TagDao.getArchiveTags(archive.id)
        let assetsRaw = ArchiveDao.getArchiveAssetsRaw(archive.id)
        return (true, buildArchiveMetadataObjectJsonFromParts(
            archive,
            tags,
            assetsRaw,
            includeLocator,
            volumeNo,
            includePages,
            progress: progress,
            isNew: isNew,
            isFavorite: isFavorite,
            lastReadTime: lastReadTime
        ), "")
    }

    public static func buildTankoubonMetadataObjectJson(tankoubonId: String, includePages!: Bool = false): (Bool, String, String) {
        match (TankoubonDao.getTankoubonById(tankoubonId)) {
            case None => return (false, "", "Tankoubon not found")
            case Some(tankoubon) =>
                let tags = TankoubonDao.getMergedTagsForTankoubon(tankoubonId)
                let archiveIds = TankoubonDao.getArchivesInTankoubon(tankoubonId)
                let archiveMap = ArchiveDao.getBatchArchivesById(archiveIds)
                let archiveTagsMap = TagDao.getBatchArchiveTags(archiveIds)
                let archiveAssetsMap = ArchiveDao.getBatchArchiveAssetsRaw(archiveIds)
                let out = ByteBuffer()
                let w = JsonWriter(out)
                w.startObject()
                w.writeName("title").writeValue(tankoubon.name)
                w.writeName("type").writeValue(1i32)
                w.writeName("description").writeValue(tankoubon.summary)
                writeMetadataTagsArray(w, tags)
                writeMetadataAssetsArray(w, tankoubon.assets_raw)
                w.writeName("archive")
                w.startArray()
                var volumeNo: Int32 = 1
                for (idx in 0..archiveIds.size) {
                    let memberId = archiveIds[idx].trimAscii()
                    if (memberId.size == 0) {
                        volumeNo += 1
                        continue
                    }
                    match (archiveMap.get(memberId)) {
                        case Some(archive) =>
                            let memberTags = match (archiveTagsMap.get(memberId)) {
                                case Some(value) => value
                                case None => ""
                            }
                            let memberAssetsRaw = match (archiveAssetsMap.get(memberId)) {
                                case Some(value) => value
                                case None => "{}"
                            }
                            let memberJson = buildArchiveMetadataObjectJsonFromParts(archive, memberTags, memberAssetsRaw, true, volumeNo, includePages)
                            if (memberJson.trimAscii().size > 0) {
                                w.jsonValue(memberJson)
                            }
                        case None => ()
                    }
                    volumeNo += 1
                }
                w.endArray()
                w.endObject()
                w.flush()
                return (true, String.fromUtf8(readToEnd(out)), "")
        }
    }

    public static func buildArchivePatchFromParsed(parsed: ParsedMetadataResult): ArchiveMetadataPatch {
        let patch = ArchiveMetadataPatch()
        patch.title = parsed.title
        patch.summary = parsed.summary
        patch.tags = parsed.tags
        patch.cover = parsed.cover
        patch.backdrop = parsed.backdrop
        patch.clearlogo = parsed.clearlogo
        patch.titleProvided = parsed.titleProvided
        patch.summaryProvided = parsed.summaryProvided
        patch.tagsProvided = parsed.tagsProvided
        patch.coverProvided = parsed.coverProvided
        patch.backdropProvided = parsed.backdropProvided
        patch.clearlogoProvided = parsed.clearlogoProvided
        patch.pages = parsed.pages
        return patch
    }

    private static func parsePositiveAssetId(rawValue: String): Int64 {
        let trimmed = rawValue.trimAscii()
        if (trimmed.size == 0) { return 0 }
        try {
            let parsed = Int64.parse(trimmed)
            return if (parsed > 0) { parsed } else { 0 }
        } catch (_: Exception) {
            return 0
        }
    }

    public static func applyArchiveAssetFromOutput(taskId: Int64, archiveId: String, assetKey: String, assetValue: String, pluginNamespace: String): Unit {
        let key = assetKey.trimAscii().toAsciiLower()
        if (key != "cover" && key != "backdrop" && key != "clearlogo") {
            return
        }

        let value = assetValue.trimAscii()
        let oldAssetId = ArchiveDao.getArchiveAssetIdByKey(archiveId, key)
        if (value.size == 0) {
            let cleared = if (key == "cover") {
                let ok = ArchiveDao.updateCoverAssetId(archiveId, 0)
                if (ok) {
                    let _ = ArchiveDao.updateThumbHash(archiveId, "")
                }
                ok
            } else {
                ArchiveDao.updateArchiveAssetIdByKey(archiveId, key, 0)
            }
            if (cleared && oldAssetId > 0) {
                PluginTaskService.deleteCoverAsset(oldAssetId)
            }
            return
        }

        let directAssetId = parsePositiveAssetId(value)
        if (directAssetId > 0) {
            let updated = if (key == "cover") {
                let ok = ArchiveDao.updateCoverAssetId(archiveId, directAssetId)
                if (ok) {
                    let asset = AssetDao.getById(directAssetId)
                    let thumbHash = asset.thumbhash.trimAscii()
                    if (thumbHash.size > 0) {
                        let _ = ArchiveDao.updateThumbHash(archiveId, thumbHash)
                    }
                }
                ok
            } else {
                ArchiveDao.updateArchiveAssetIdByKey(archiveId, key, directAssetId)
            }

            if (updated) {
                if (oldAssetId > 0 && oldAssetId != directAssetId) {
                    PluginTaskService.deleteCoverAsset(oldAssetId)
                }
            } else {
                logWarn(taskId, "failed to apply archive ${key} asset id=${directAssetId} archive=${archiveId}")
            }
            return
        }

        if (pluginNamespace.trimAscii().size == 0) {
            logWarn(taskId, "skip archive ${key} asset without metadata namespace archive=${archiveId}")
            return
        }

        let assetKind = if (key == "cover") {
            "archive_cover"
        } else if (key == "backdrop") {
            "archive_backdrop"
        } else {
            "archive_clearlogo"
        }
        let outputName = if (key == "cover") {
            "${archiveId}.avif"
        } else {
            "${archiveId}_${key}.avif"
        }

        let (okInstall, newAssetId, thumbHash, installErr) = PluginTaskService.installCoverAssetFromPluginPath(
            value,
            pluginNamespace,
            assetKind,
            outputName
        )
        if (!(okInstall && newAssetId > 0)) {
            logWarn(taskId, "failed to install archive ${key} from plugin result archive=${archiveId}: ${installErr}")
            return
        }

        let updated = if (key == "cover") {
            let ok = ArchiveDao.updateCoverAssetId(archiveId, newAssetId)
            if (ok && thumbHash.trimAscii().size > 0) {
                let _ = ArchiveDao.updateThumbHash(archiveId, thumbHash)
            }
            ok
        } else {
            ArchiveDao.updateArchiveAssetIdByKey(archiveId, key, newAssetId)
        }

        if (updated) {
            if (oldAssetId > 0 && oldAssetId != newAssetId) {
                PluginTaskService.deleteCoverAsset(oldAssetId)
            }
        } else {
            PluginTaskService.deleteCoverAsset(newAssetId)
            logWarn(taskId, "failed to apply archive ${key} asset, removed new asset id=${newAssetId} archive=${archiveId}")
        }
    }

    public static func applyTankoubonAssetFromOutput(taskId: Int64, tankoubonId: String, assetKey: String, assetValue: String, pluginNamespace: String): Unit {
        let key = assetKey.trimAscii().toAsciiLower()
        if (key != "cover" && key != "backdrop" && key != "clearlogo") {
            return
        }

        let value = assetValue.trimAscii()
        let oldAssetId = TankoubonDao.getTankoubonAssetIdByKey(tankoubonId, key)
        if (value.size == 0) {
            let cleared = if (key == "cover") {
                TankoubonDao.updateTankoubonCover(tankoubonId, 0)
            } else {
                TankoubonDao.updateTankoubonAssetIdByKey(tankoubonId, key, 0)
            }
            if (cleared && oldAssetId > 0) {
                PluginTaskService.deleteCoverAsset(oldAssetId)
            }
            return
        }

        let directAssetId = parsePositiveAssetId(value)
        if (directAssetId > 0) {
            let updated = if (key == "cover") {
                TankoubonDao.updateTankoubonCover(tankoubonId, directAssetId)
            } else {
                TankoubonDao.updateTankoubonAssetIdByKey(tankoubonId, key, directAssetId)
            }

            if (updated) {
                if (oldAssetId > 0 && oldAssetId != directAssetId) {
                    PluginTaskService.deleteCoverAsset(oldAssetId)
                }
            } else {
                logWarn(taskId, "failed to apply tankoubon ${key} asset id=${directAssetId} tankoubon=${tankoubonId}")
            }
            return
        }

        if (pluginNamespace.trimAscii().size == 0) {
            logWarn(taskId, "skip tankoubon ${key} asset without metadata namespace tankoubon=${tankoubonId}")
            return
        }

        let assetKind = if (key == "cover") {
            "tankoubon_cover"
        } else if (key == "backdrop") {
            "tankoubon_backdrop"
        } else {
            "tankoubon_clearlogo"
        }
        let outputName = if (key == "cover") {
            "${tankoubonId}.avif"
        } else {
            "${tankoubonId}_${key}.avif"
        }

        let (okInstall, newAssetId, _, installErr) = PluginTaskService.installCoverAssetFromPluginPath(
            value,
            pluginNamespace,
            assetKind,
            outputName
        )
        if (!(okInstall && newAssetId > 0)) {
            logWarn(taskId, "failed to install tankoubon ${key} from plugin result tankoubon=${tankoubonId}: ${installErr}")
            return
        }

        let updated = if (key == "cover") {
            TankoubonDao.updateTankoubonCover(tankoubonId, newAssetId)
        } else {
            TankoubonDao.updateTankoubonAssetIdByKey(tankoubonId, key, newAssetId)
        }

        if (updated) {
            if (oldAssetId > 0 && oldAssetId != newAssetId) {
                PluginTaskService.deleteCoverAsset(oldAssetId)
            }
        } else {
            PluginTaskService.deleteCoverAsset(newAssetId)
            logWarn(taskId, "failed to apply tankoubon ${key} asset, removed new asset id=${newAssetId} tankoubon=${tankoubonId}")
        }
    }

    public static func syncArchiveVisiblePageCount(taskId: Int64, archiveId: String): Unit {
        let archive = ArchiveDao.getArchiveById(archiveId)
        if (archive.id.size == 0) {
            logWarn(taskId, "failed to sync archive pagecount, archive not found: ${archiveId}")
            return
        }

        if (archive.category_id <= 0) {
            logWarn(taskId, "failed to sync archive pagecount, category missing: ${archiveId}")
            return
        }

        let basePath = match (CategoryDao.getCategoryByInternalId(archive.category_id)) {
            case Some(cat) => cat.scanPath
            case None => ""
        }
        if (basePath.trimAscii().size == 0) {
            logWarn(taskId, "failed to sync archive pagecount, category scan path missing: ${archiveId}")
            return
        }

        let fullArchivePath = if (archive.relative_path.size > 0) {
            "${basePath}/${archive.relative_path}/${archive.filename}"
        } else {
            "${basePath}/${archive.filename}"
        }
        let actualPath = FileUtils.resolvePath(fullArchivePath)
        if (actualPath.trimAscii().size == 0) {
            logWarn(taskId, "failed to sync archive pagecount, archive path missing: ${fullArchivePath}")
            return
        }

        let handler = ArchiveHandlerFactory.getInstance().getHandlerByType(archive.archive_type)
        let entriesWithTitle = handler.listEntriesWithTitle(actualPath)
        let pageMetadata = ArchiveDao.getPageMetadata(archiveId)

        var metadataByPath = HashMap<String, PageMetadataData>()
        var metadataByPage = HashMap<Int32, PageMetadataData>()
        for (meta in pageMetadata) {
            let pathKey = meta.entry_path.trimAscii()
            if (pathKey.size > 0 && !metadataByPath.contains(pathKey)) {
                metadataByPath[pathKey] = meta
            }
            if (meta.page_number > 0 && !metadataByPage.contains(meta.page_number)) {
                metadataByPage[meta.page_number] = meta
            }
        }

        var visiblePageCount: Int32 = 0
        for (i in 0..entriesWithTitle.size) {
            let entry = entriesWithTitle[i]
            let pageNumber = Int32(i + 1)
            let pathKey = entry[0].trimAscii()

            var hidden = false
            var metadataFound = false
            match (metadataByPath.get(pathKey)) {
                case Some(meta) =>
                    hidden = meta.hidden_in_files
                    metadataFound = true
                case None => ()
            }
            if (!metadataFound) {
                match (metadataByPage.get(pageNumber)) {
                    case Some(meta) => hidden = meta.hidden_in_files
                    case None => ()
                }
            }

            if (!hidden) {
                visiblePageCount += 1
            }
        }

        if (ArchiveDao.updatePageCount(archiveId, visiblePageCount)) {
            logInfo(taskId, "Synced archive visible pagecount: ${visiblePageCount} (archive=${archiveId})")
        } else {
            logWarn(taskId, "failed to update archive pagecount: ${archiveId}")
        }
    }

    public static func applyPagePatchesForArchive(taskId: Int64, archiveId: String, pagePatches: Array<PageMetadataPatch>, pluginNamespace: String): Bool {
        if (pagePatches.size == 0) {
            return true
        }

        let archiveInternalId = ArchiveDao.getArchiveInternalId(archiveId)
        if (archiveInternalId <= 0) {
            logWarn(taskId, "skip page patches: archive internal id missing archive=${archiveId}")
            return false
        }

        let existingPageMetadata = ArchivePageMetadataDao.getByArchiveId(archiveInternalId)
        var metadataByPath = HashMap<String, PageMetadataData>()
        var metadataByPage = HashMap<Int32, PageMetadataData>()
        for (meta in existingPageMetadata) {
            let pathKey = meta.entry_path.trimAscii()
            if (pathKey.size > 0 && !metadataByPath.contains(pathKey)) {
                metadataByPath[pathKey] = meta
            }
            if (meta.page_number > 0 && !metadataByPage.contains(meta.page_number)) {
                metadataByPage[meta.page_number] = meta
            }
        }

        let deleteOldAssetIds = HashSet<Int64>()
        let cleanupNewAssetIds = HashSet<Int64>()
        let items = ArrayList<PageMetadataData>()
        var savedPages: Int64 = 0
        var hiddenVisibilityChanged = false

        for (patch in pagePatches) {
            let entryPath = patch.path.trimAscii()
            if (patch.page <= 0 && entryPath.size == 0) {
                continue
            }

            var existingOpt: Option<PageMetadataData> = Option<PageMetadataData>.None
            match (metadataByPath.get(entryPath)) {
                case Some(meta) => existingOpt = Some(meta)
                case None => ()
            }
            if (patch.page > 0) {
                match (metadataByPage.get(patch.page)) {
                    case Some(meta) =>
                        match (existingOpt) {
                            case Some(_) => ()
                            case None => existingOpt = Some(meta)
                        }
                    case None => ()
                }
            }

            let item = PageMetadataData()
            item.archive_id = archiveInternalId
            item.page_number = if (patch.page > 0) {
                patch.page
            } else {
                match (existingOpt) {
                    case Some(existing) => existing.page_number
                    case None => 0i32
                }
            }
            item.entry_path = if (entryPath.size > 0) {
                entryPath
            } else {
                match (existingOpt) {
                    case Some(existing) => existing.entry_path
                    case None => ""
                }
            }
            item.title = patch.title
            item.description = patch.description
            item.extra_data = "{}"

            match (existingOpt) {
                case Some(existing) =>
                    if (item.title.trimAscii().size == 0) {
                        item.title = existing.title
                    }
                    if (item.description.trimAscii().size == 0) {
                        item.description = existing.description
                    }
                    item.sort_index = existing.sort_index
                    item.hidden_in_files = existing.hidden_in_files
                    item.thumb_asset_id = existing.thumb_asset_id
                    item.thumbhash = existing.thumbhash
                    item.extra_data = existing.extra_data
                case None => ()
            }

            if (patch.sortProvided) {
                item.sort_index = patch.sort
            }
            if (patch.hiddenInFilesProvided) {
                let oldHidden = match (existingOpt) {
                    case Some(existing) => existing.hidden_in_files
                    case None => false
                }
                item.hidden_in_files = patch.hiddenInFiles
                if (oldHidden != item.hidden_in_files) {
                    hiddenVisibilityChanged = true
                }
            }

            let patchThumb = patch.thumb.trimAscii()
            if (patchThumb.size > 0) {
                let directAssetId = parsePositiveAssetId(patchThumb)
                if (directAssetId > 0) {
                    item.thumb_asset_id = directAssetId
                    let asset = AssetDao.getById(directAssetId)
                    item.thumbhash = asset.thumbhash.trimAscii()
                } else if (pluginNamespace.trimAscii().size > 0) {
                    let oldThumbAssetId = item.thumb_asset_id
                    let pageToken = if (item.page_number > 0) {
                        item.page_number.toString()
                    } else if (item.entry_path.trimAscii().size > 0) {
                        item.entry_path.trimAscii().replace("/", "_")
                    } else {
                        DateTime.now().toUnixTimeStamp().toMilliseconds().toString()
                    }
                    let (okThumb, newThumbAssetId, newThumbHash, thumbErr) = PluginTaskService.installCoverAssetFromPluginPath(
                        patchThumb,
                        pluginNamespace,
                        "page_thumb",
                        "${archiveId}_${pageToken}.avif"
                    )
                    if (okThumb && newThumbAssetId > 0) {
                        item.thumb_asset_id = newThumbAssetId
                        item.thumbhash = newThumbHash
                        cleanupNewAssetIds.add(newThumbAssetId)
                        if (oldThumbAssetId > 0 && oldThumbAssetId != newThumbAssetId) {
                            deleteOldAssetIds.add(oldThumbAssetId)
                        }
                    } else {
                        logWarn(taskId, "failed to install page thumb from plugin result (archive=${archiveId}, page=${item.page_number.toString()}, path=${entryPath}): ${thumbErr}")
                    }
                } else {
                    logWarn(taskId, "skip page thumb patch without metadata namespace archive=${archiveId}, path=${entryPath}")
                }
            }

            items.add(item)
            savedPages += 1
            let updatedPathKey = item.entry_path.trimAscii()
            if (updatedPathKey.size > 0) {
                metadataByPath[updatedPathKey] = item
            }
            if (item.page_number > 0) {
                metadataByPage[item.page_number] = item
            }
        }

        if (items.size == 0) {
            return true
        }

        let ok = ArchivePageMetadataDao.insertOrUpdateBatch(items.toArray())
        if (!ok) {
            for (assetId in cleanupNewAssetIds) {
                if (assetId > 0) {
                    PluginTaskService.deleteCoverAsset(assetId)
                }
            }
            return false
        }

        for (assetId in deleteOldAssetIds) {
            if (assetId > 0) {
                PluginTaskService.deleteCoverAsset(assetId)
            }
        }

        logInfo(taskId, "Saved ${savedPages} page metadata entries")
        if (hiddenVisibilityChanged) {
            syncArchiveVisiblePageCount(taskId, archiveId)
        }
        return true
    }

    public static func applyArchiveMetadataPatch(taskId: Int64, archiveId: String, patch: ArchiveMetadataPatch, pluginNamespace: String): Bool {
        var archive = ArchiveDao.getArchiveById(archiveId)
        if (archive.id.size == 0) {
            logWarn(taskId, "archive not found when applying metadata patch: ${archiveId}")
            return false
        }

        let (updatedAtFromTags, cleanedPatchTags) = if (patch.tagsProvided) {
            extractUpdatedAtFromTags(patch.tags)
        } else {
            ("", patch.tags)
        }
        let hasPatchUpdatedAt = patch.updatedAtProvided || updatedAtFromTags.trimAscii().size > 0
        let effectiveUpdatedAt = if (patch.updatedAt.trimAscii().size > 0) { patch.updatedAt.trimAscii() } else { updatedAtFromTags }

        var changed = false
        if (patch.titleProvided) {
            let titleValue = patch.title.trimAscii()
            if (archive.title != titleValue) {
                archive.title = titleValue
                changed = true
            }
        }
        if (patch.summaryProvided && archive.summary != patch.summary) {
            archive.summary = patch.summary
            changed = true
        }
        if (hasPatchUpdatedAt && archive.updated_at != effectiveUpdatedAt) {
            archive.updated_at = effectiveUpdatedAt
            changed = true
        }

        if (changed) {
            let ok = ArchiveDao.update(archive)
            if (!ok) {
                logWarn(taskId, "archive update failed while applying metadata patch: ${archiveId}")
                return false
            }
        }

        if (patch.tagsProvided) {
            let tagOk = TagDao.updateArchiveTags(archiveId, cleanedPatchTags)
            if (!tagOk) {
                logWarn(taskId, "archive tag update failed: ${archiveId}")
            }
        }

        if (patch.coverProvided) {
            applyArchiveAssetFromOutput(taskId, archiveId, "cover", patch.cover, pluginNamespace)
        }
        if (patch.backdropProvided) {
            applyArchiveAssetFromOutput(taskId, archiveId, "backdrop", patch.backdrop, pluginNamespace)
        }
        if (patch.clearlogoProvided) {
            applyArchiveAssetFromOutput(taskId, archiveId, "clearlogo", patch.clearlogo, pluginNamespace)
        }

        if (patch.pages.size > 0) {
            return applyPagePatchesForArchive(taskId, archiveId, patch.pages, pluginNamespace)
        }
        return true
    }
}
