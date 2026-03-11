package lanlu.contexts.plugin.application

import std.collection.*
import std.convert.*
import std.io.{ByteBuffer, readToEnd}
import std.time.*
import stdx.encoding.json.stream.*
import lanlu.contexts.plugin.domain.*
import lanlu.contexts.archive.infrastructure.persistence.*
import lanlu.contexts.tankoubon.infrastructure.persistence.*
import lanlu.contexts.asset.infrastructure.persistence.*
import lanlu.contexts.metadata.infrastructure.persistence.*
import lanlu.contexts.category.infrastructure.persistence.*
import lanlu.contexts.tag.infrastructure.persistence.*
import lanlu.shared.utils.*
import lanlu.infrastructure.archivehandler.*

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

    private static func findMetadataAssetId(assets: Array<MetadataAssetData>, slot: String): Int64 {
        let normalizedSlot = slot.trimAscii().toAsciiLower()
        for (asset in assets) {
            if (asset.slot.trimAscii().toAsciiLower() == normalizedSlot && asset.asset_id > 0) {
                return asset.asset_id
            }
        }
        return 0
    }

    private static func writeMetadataTagsArrayFromList(w: JsonWriter, tags: Array<String>): Unit {
        w.writeName("tags")
        w.startArray()
        for (tag in tags) {
            let value = tag.trimAscii()
            if (value.size > 0) {
                w.writeValue(value)
            }
        }
        w.endArray()
    }

    private static func translateMetadataTags(tags: Array<String>, lang: String): Array<String> {
        let effectiveLang = lang.trimAscii()
        if (tags.size == 0 || effectiveLang.size == 0) {
            return tags
        }

        let translationsMap = TagDao.batchGetTranslations(tags, effectiveLang)
        if (translationsMap.size == 0) {
            return tags
        }

        let translatedTagsString = TagDao.translateTagsString(String.join(tags, delimiter: ", "), effectiveLang, translationsMap)
        return splitTagTokens(translatedTagsString)
    }

    private static func writeMetadataAssetsArrayFromList(w: JsonWriter, assets: Array<MetadataAssetData>): Unit {
        w.writeName("assets")
        w.startArray()
        for (asset in assets) {
            let slot = asset.slot.trimAscii().toAsciiLower()
            if (slot.size == 0 || asset.asset_id <= 0) {
                continue
            }
            w.startObject()
            w.writeName("key").writeValue(slot)
            w.writeName("value").writeValue(asset.asset_id)
            w.endObject()
        }
        w.endArray()
    }

    private static func getAssetThumbhash(assetId: Int64): String {
        if (assetId <= 0) {
            return ""
        }
        let asset = AssetDao.getById(assetId)
        return asset.thumbhash.trimAscii()
    }

    private static func resolveArchiveThumbnailHash(archive: ArchiveData, assets: Array<MetadataAssetData>): String {
        let coverAssetId = findMetadataAssetId(assets, "cover")
        if (coverAssetId > 0) {
            let thumbhash = getAssetThumbhash(coverAssetId)
            if (thumbhash.size > 0) {
                return thumbhash
            }
        }
        return archive.thumbhash.trimAscii()
    }

    private static func writeLocatorObject(w: JsonWriter, entityType: String, entityId: String, volumeNo!: Int32 = 0, orderIndex!: Int32 = 0): Unit {
        w.writeName("locator")
        w.startObject()
        w.writeName("entity_type").writeValue(entityType)
        w.writeName("entity_id").writeValue(entityId)
        if (volumeNo > 0) {
            w.writeName("volume_no").writeValue(volumeNo)
        }
        if (orderIndex > 0) {
            w.writeName("order_index").writeValue(orderIndex)
        }
        w.endObject()
    }

    private static func writeTankoubonChildObject(w: JsonWriter, child: MetadataChildData): Unit {
        w.startObject()
        w.writeName("entity_type").writeValue(child.entity_type)
        w.writeName("entity_id").writeValue(child.entity_id)
        if (child.volume_no > 0) {
            w.writeName("volume_no").writeValue(child.volume_no)
        }
        if (child.order_index > 0) {
            w.writeName("order_index").writeValue(child.order_index)
        }
        writeLocatorObject(w, child.entity_type, child.entity_id, volumeNo: child.volume_no, orderIndex: child.order_index)
        w.endObject()
    }

    private static func ensureArchiveMetadataObject(archiveId: String, archive!: ArchiveData = ArchiveData()): Option<MetadataObjectData> {
        let normalizedId = archiveId.trimAscii()
        if (normalizedId.size == 0) {
            return None
        }
        match (MetadataDao.getMetadataObject("archive", normalizedId)) {
            case Some(existing) => return Some(existing)
            case None => ()
        }

        let sourceArchive = if (archive.id.size > 0) { archive } else { ArchiveDao.getArchiveById(normalizedId) }
        if (sourceArchive.id.size == 0) {
            return None
        }

        let _ = MetadataDao.upsertRootMetadataObject(
            "archive",
            sourceArchive.id,
            "",
            "",
            releaseAt: sourceArchive.release_at,
            sourceNamespace: "system:bootstrap",
            createdAt: sourceArchive.created_at,
            updatedAt: sourceArchive.updated_at
        )
        return MetadataDao.getMetadataObject("archive", sourceArchive.id)
    }

    private static func ensureTankoubonMetadataObject(tankoubonId: String, preloaded!: TankoubonData = TankoubonData()): Option<MetadataObjectData> {
        let normalizedId = tankoubonId.trimAscii()
        if (normalizedId.size == 0) {
            return None
        }
        match (MetadataDao.getMetadataObject("tankoubon", normalizedId)) {
            case Some(existing) => return Some(existing)
            case None => ()
        }

        let tankoubon = if (preloaded.tankoubon_id.size > 0) { preloaded } else {
            match (TankoubonDao.getTankoubonById(normalizedId)) {
                case Some(data) => data
                case None => return None
            }
        }

        let _ = MetadataDao.upsertRootMetadataObject(
            "tankoubon",
            normalizedId,
            "",
            "",
            releaseAt: tankoubon.release_at,
            sourceNamespace: "system:bootstrap",
            createdAt: tankoubon.created_at,
            updatedAt: tankoubon.updated_at
        )
        return MetadataDao.getMetadataObject("tankoubon", normalizedId)
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
                    case _ => r.skip()
                }
            }
            r.endObject()
        } catch (_: Exception) {}

        return ""
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
                        case "page_number" => patch.page = readInt32Flexible()
                        case "entry_path" => patch.path = readStringFlexible().trimAscii()
                        case "title" => patch.title = readStringFlexible()
                        case "description" => patch.description = readStringFlexible()
                        case "thumb" => patch.thumb = readStringFlexible().trimAscii()
                        case "release_at" =>
                            patch.releaseAt = readStringFlexible().trimAscii()
                            patch.releaseAtProvided = true
                        case "created_at" =>
                            patch.createdAt = readStringFlexible().trimAscii()
                            patch.createdAtProvided = true
                        case "updated_at" =>
                            patch.updatedAt = readStringFlexible().trimAscii()
                            patch.updatedAtProvided = true
                        case "order_index" =>
                            patch.sort = readInt32Flexible()
                            patch.sortProvided = true
                        case "hidden_in_files" =>
                            patch.hiddenInFiles = readBoolFlexible()
                            patch.hiddenInFilesProvided = true
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
                        case "entity_type" =>
                            // Child patch currently supports archive targets only.
                            let et = readStringFlexible().trimAscii().toAsciiLower()
                            if (et.size > 0 && et != "archive") {
                                patch.archiveId = ""
                            }
                        case "entity_id" =>
                            patch.archiveId = readStringFlexible().trimAscii()
                        case "volume_no" => patch.volumeNo = readInt32Flexible()
                        case "title" =>
                            patch.title = readStringFlexible()
                            patch.titleProvided = true
                        case "description" =>
                            patch.summary = readStringFlexible()
                            patch.summaryProvided = true
                        case "tags" =>
                            patch.tags = readTagsFlexible()
                            patch.tagsProvided = true
                        case "release_at" =>
                            patch.releaseAt = readStringFlexible().trimAscii()
                            patch.releaseAtProvided = true
                        case "created_at" =>
                            patch.createdAt = readStringFlexible().trimAscii()
                            patch.createdAtProvided = true
                        case "updated_at" =>
                            patch.updatedAt = readStringFlexible().trimAscii()
                            patch.updatedAtProvided = true
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
                        case "children" =>
                            // Child members are the recursive boundary for now; ignore deeper nesting.
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
                    case "description" =>
                        parsed.summary = readStringFlexible()
                        parsed.summaryProvided = true
                    case "tags" =>
                        parsed.tags = readTagsFlexible()
                        parsed.tagsProvided = true
                    case "release_at" =>
                        parsed.releaseAt = readStringFlexible().trimAscii()
                        parsed.releaseAtProvided = true
                    case "created_at" =>
                        parsed.createdAt = readStringFlexible().trimAscii()
                        parsed.createdAtProvided = true
                    case "updated_at" =>
                        parsed.updatedAt = readStringFlexible().trimAscii()
                        parsed.updatedAtProvided = true
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
                    case "children" =>
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
    private static func writePageMetadataArray(w: JsonWriter, archiveId: String, pageMetadata: Array<PageMetadataData>): Unit {
        w.writeName("pages")
        w.startArray()
        for (meta in pageMetadata) {
            w.startObject()
            if (meta.page_number > 0) {
                w.writeName("page_number").writeValue(meta.page_number)
            }
            let pathValue = meta.entry_path.trimAscii()
            if (pathValue.size > 0 && !isSyntheticEntryPath(pathValue)) {
                w.writeName("entry_path").writeValue(pathValue)
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
                w.writeName("order_index").writeValue(meta.sort_index)
            }
            if (meta.hidden_in_files) {
                w.writeName("hidden_in_files").writeValue(meta.hidden_in_files)
            }
            if (meta.release_at.trimAscii().size > 0) {
                w.writeName("release_at").writeValue(meta.release_at)
            }
            if (meta.created_at.trimAscii().size > 0) {
                w.writeName("created_at").writeValue(meta.created_at)
            }
            if (meta.updated_at.trimAscii().size > 0) {
                w.writeName("updated_at").writeValue(meta.updated_at)
            }
            w.writeName("locator")
            w.startObject()
            w.writeName("entity_type").writeValue("page")
            if (archiveId.trimAscii().size > 0) {
                w.writeName("parent_entity_type").writeValue("archive")
                w.writeName("parent_entity_id").writeValue(archiveId)
            }
            if (meta.page_number > 0) {
                w.writeName("page_number").writeValue(meta.page_number)
            }
            if (pathValue.size > 0 && !isSyntheticEntryPath(pathValue)) {
                w.writeName("entry_path").writeValue(pathValue)
            }
            if (meta.sort_index > 0) {
                w.writeName("order_index").writeValue(meta.sort_index)
            }
            w.endObject()
            w.endObject()
        }
        w.endArray()
    }

    private static func buildArchiveMetadataObjectJsonFromParts(
        archive: ArchiveData,
        metadata: MetadataObjectData,
        includeLocator: Bool,
        volumeNo: Int32,
        orderIndex: Int32,
        includePages: Bool,
        progress!: Int32 = 0i32,
        isNew!: Bool = false,
        isFavorite!: Bool = false,
        lastReadTime!: Int64 = 0i64,
        lang!: String = ""
    ): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        let description = metadata.description
        let createdAt = if (metadata.created_at.trimAscii().size > 0) { metadata.created_at } else { archive.created_at }
        let updatedAt = if (metadata.updated_at.trimAscii().size > 0) { metadata.updated_at } else { createdAt }
        let thumbnailHash = resolveArchiveThumbnailHash(archive, metadata.assets)
        let translatedTags = translateMetadataTags(metadata.tags, lang)
        w.startObject()
        w.writeName("title").writeValue(metadata.title)
        w.writeName("type").writeValue(0i32)
        w.writeName("description").writeValue(description)
        writeMetadataTagsArrayFromList(w, translatedTags)
        writeMetadataAssetsArrayFromList(w, metadata.assets)
        w.writeName("children")
        w.startArray()
        w.endArray()
        w.writeName("arcid").writeValue(archive.id)
        w.writeName("filename").writeValue(archive.filename)
        w.writeName("relative_path").writeValue(archive.relative_path)
        w.writeName("file_size").writeValue(archive.file_size)
        w.writeName("pagecount").writeValue(archive.pagecount)
        w.writeName("progress").writeValue(progress)
        w.writeName("isnew").writeValue(isNew)
        w.writeName("isfavorite").writeValue(isFavorite)
        w.writeName("lastreadtime").writeValue(lastReadTime)
        w.writeName("archivetype").writeValue(archive.archive_type)
        w.writeName("release_at").writeValue(metadata.release_at)
        w.writeName("created_at").writeValue(createdAt)
        w.writeName("updated_at").writeValue(updatedAt)
        if (includePages) {
            writePageMetadataArray(w, archive.id, MetadataDao.listPageMetadata(archive.id))
        }
        w.writeName("thumbnail_hash").writeValue(thumbnailHash)
        if (includeLocator) {
            writeLocatorObject(w, "archive", archive.id, volumeNo: volumeNo, orderIndex: orderIndex)
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
        lastReadTime!: Int64 = 0i64,
        lang!: String = ""
    ): (Bool, String, String) {
        let archive = ArchiveDao.getArchiveById(archiveId)
        if (archive.id.size == 0) {
            return (false, "", "Archive not found")
        }
        match (ensureArchiveMetadataObject(archiveId, archive: archive)) {
            case None => return (false, "", "Archive metadata not found")
            case Some(metadata) =>
                return (true, buildArchiveMetadataObjectJsonFromParts(
                    archive,
                    metadata,
                    includeLocator,
                    volumeNo,
                    0,
                    includePages,
                    progress: progress,
                    isNew: isNew,
                    isFavorite: isFavorite,
                    lastReadTime: lastReadTime,
                    lang: lang
                ), "")
        }
    }

    public static func buildTankoubonMetadataObjectJson(
        tankoubonId: String,
        includePages!: Bool = false,
        includeArchiveDetails!: Bool = true,
        archiveCount!: Int32 = -1,
        pageCount!: Int32 = -1,
        progress!: Int32 = 0i32,
        isNew!: Bool = false,
        isFavorite!: Bool = false,
        lastReadTime!: String = ""
    ): (Bool, String, String) {
        match (TankoubonDao.getTankoubonById(tankoubonId)) {
            case None => return (false, "", "Tankoubon not found")
            case Some(tankoubon) =>
                match (ensureTankoubonMetadataObject(tankoubonId, preloaded: tankoubon)) {
                    case None => return (false, "", "Tankoubon metadata not found")
                    case Some(metadata) =>
                        let (statsArchiveCount, statsPageCount) = TankoubonDao.getTankoubonArchiveStats(tankoubonId)
                        let effectiveArchiveCount = if (archiveCount >= 0) { archiveCount } else { statsArchiveCount }
                        let effectivePageCount = if (pageCount >= 0) { pageCount } else { statsPageCount }
                        let children = MetadataDao.getTankoubonChildren(tankoubonId)
                        let out = ByteBuffer()
                        let w = JsonWriter(out)
                        w.startObject()
                        w.writeName("title").writeValue(metadata.title)
                        w.writeName("type").writeValue(1i32)
                        w.writeName("description").writeValue(metadata.description)
                        writeMetadataTagsArrayFromList(w, metadata.tags)
                        writeMetadataAssetsArrayFromList(w, metadata.assets)
                        w.writeName("tankoubon_id").writeValue(tankoubonId)
                        w.writeName("children")
                        w.startArray()
                        if (!includeArchiveDetails) {
                            for (child in children) {
                                writeTankoubonChildObject(w, child)
                            }
                        } else {
                            for (child in children) {
                                let memberId = child.entity_id.trimAscii()
                                if (memberId.size == 0) {
                                    continue
                                }
                                let archive = ArchiveDao.getArchiveById(memberId)
                                if (archive.id.size == 0) {
                                    continue
                                }
                                match (ensureArchiveMetadataObject(memberId, archive: archive)) {
                                    case Some(childMetadata) =>
                                        let memberJson = buildArchiveMetadataObjectJsonFromParts(
                                            archive,
                                            childMetadata,
                                            true,
                                            child.volume_no,
                                            child.order_index,
                                            includePages
                                        )
                                        if (memberJson.trimAscii().size > 0) {
                                            w.jsonValue(memberJson)
                                        }
                                    case None => ()
                                }
                            }
                        }
                        w.endArray()
                        w.writeName("archive_count").writeValue(effectiveArchiveCount)
                        w.writeName("pagecount").writeValue(effectivePageCount)
                        w.writeName("progress").writeValue(progress)
                        w.writeName("lastreadtime").writeValue(lastReadTime)
                        w.writeName("isnew").writeValue(isNew)
                        w.writeName("isfavorite").writeValue(isFavorite)
                        w.writeName("release_at").writeValue(metadata.release_at)
                        w.writeName("created_at").writeValue(metadata.created_at)
                        w.writeName("updated_at").writeValue(metadata.updated_at)
                        writeLocatorObject(w, "tankoubon", tankoubonId)
                        w.endObject()
                        w.flush()
                        return (true, String.fromUtf8(readToEnd(out)), "")
                }
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
        patch.releaseAt = parsed.releaseAt
        patch.createdAt = parsed.createdAt
        patch.updatedAt = parsed.updatedAt
        patch.titleProvided = parsed.titleProvided
        patch.summaryProvided = parsed.summaryProvided
        patch.tagsProvided = parsed.tagsProvided
        patch.releaseAtProvided = parsed.releaseAtProvided
        patch.createdAtProvided = parsed.createdAtProvided
        patch.updatedAtProvided = parsed.updatedAtProvided
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
        let _ = ensureArchiveMetadataObject(archiveId)
        let value = assetValue.trimAscii()
        let oldAssetId = MetadataDao.getMetadataAssetId("archive", archiveId, key)
        if (value.size == 0) {
            let cleared = MetadataDao.setMetadataAssetId("archive", archiveId, key, 0)
            if (cleared && oldAssetId > 0) {
                PluginTaskService.deleteCoverAsset(oldAssetId)
            }
            if (cleared) {
                let _ = MetadataDao.touchRootMetadataObject("archive", archiveId)
            }
            return
        }

        let directAssetId = parsePositiveAssetId(value)
        if (directAssetId > 0) {
            let updated = MetadataDao.setMetadataAssetId("archive", archiveId, key, directAssetId)
            if (updated) {
                if (oldAssetId > 0 && oldAssetId != directAssetId) {
                    PluginTaskService.deleteCoverAsset(oldAssetId)
                }
                let _ = MetadataDao.touchRootMetadataObject("archive", archiveId)
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

        let (okInstall, newAssetId, _, installErr) = PluginTaskService.installCoverAssetFromPluginPath(
            value,
            pluginNamespace,
            assetKind,
            outputName
        )
        if (!(okInstall && newAssetId > 0)) {
            logWarn(taskId, "failed to install archive ${key} from plugin result archive=${archiveId}: ${installErr}")
            return
        }

        let updated = MetadataDao.setMetadataAssetId("archive", archiveId, key, newAssetId)
        if (updated) {
            if (oldAssetId > 0 && oldAssetId != newAssetId) {
                PluginTaskService.deleteCoverAsset(oldAssetId)
            }
            let _ = MetadataDao.touchRootMetadataObject("archive", archiveId)
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
        let _ = ensureTankoubonMetadataObject(tankoubonId)
        let value = assetValue.trimAscii()
        let oldAssetId = MetadataDao.getMetadataAssetId("tankoubon", tankoubonId, key)
        if (value.size == 0) {
            let cleared = MetadataDao.setMetadataAssetId("tankoubon", tankoubonId, key, 0)
            if (cleared && oldAssetId > 0) {
                PluginTaskService.deleteCoverAsset(oldAssetId)
            }
            if (cleared) {
                let _ = MetadataDao.touchRootMetadataObject("tankoubon", tankoubonId)
            }
            return
        }

        let directAssetId = parsePositiveAssetId(value)
        if (directAssetId > 0) {
            let updated = MetadataDao.setMetadataAssetId("tankoubon", tankoubonId, key, directAssetId)
            if (updated) {
                if (oldAssetId > 0 && oldAssetId != directAssetId) {
                    PluginTaskService.deleteCoverAsset(oldAssetId)
                }
                let _ = MetadataDao.touchRootMetadataObject("tankoubon", tankoubonId)
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

        let updated = MetadataDao.setMetadataAssetId("tankoubon", tankoubonId, key, newAssetId)
        if (updated) {
            if (oldAssetId > 0 && oldAssetId != newAssetId) {
                PluginTaskService.deleteCoverAsset(oldAssetId)
            }
            let _ = MetadataDao.touchRootMetadataObject("tankoubon", tankoubonId)
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
        let pageMetadata = MetadataDao.listPageMetadata(archiveId)

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

        let archive = ArchiveDao.getArchiveById(archiveId)
        if (archive.id.size == 0) {
            logWarn(taskId, "skip page patches: archive not found archive=${archiveId}")
            return false
        }

        let existingPageMetadata = MetadataDao.listPageMetadata(archiveId)
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
            item.archive_id = archive.internalId
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
            item.release_at = ""
            item.created_at = ""
            item.updated_at = ""

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
                    item.release_at = existing.release_at
                    item.created_at = existing.created_at
                    item.updated_at = existing.updated_at
                case None => ()
            }

            if (patch.createdAtProvided) {
                logWarn(taskId, "ignore page created_at patch (read-only): archive=${archiveId}, page=${item.page_number.toString()}, path=${entryPath}")
            }
            if (patch.releaseAtProvided) {
                item.release_at = patch.releaseAt.trimAscii()
            }
            if (patch.updatedAtProvided) {
                item.updated_at = patch.updatedAt.trimAscii()
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
                    item.thumbhash = getAssetThumbhash(directAssetId)
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

        let ok = MetadataDao.upsertPageMetadataBatch(archiveId, items.toArray(), sourceNamespace: pluginNamespace)
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
        let archive = ArchiveDao.getArchiveById(archiveId)
        if (archive.id.size == 0) {
            logWarn(taskId, "archive not found when applying metadata patch: ${archiveId}")
            return false
        }

        let existingMetadata = match (ensureArchiveMetadataObject(archiveId)) {
            case Some(data) => data
            case None =>
                logWarn(taskId, "archive metadata row missing: ${archiveId}")
                return false
        }

        if (patch.createdAtProvided) {
            logWarn(taskId, "ignore archive created_at patch (read-only): ${archiveId}")
        }

        let nextTitle = if (patch.titleProvided) { patch.title.trimAscii() } else { existingMetadata.title }
        let nextDescription = if (patch.summaryProvided) { patch.summary } else { existingMetadata.description }
        let nextReleaseAt = if (patch.releaseAtProvided) {
            patch.releaseAt.trimAscii()
        } else {
            existingMetadata.release_at
        }
        let nextUpdatedAt = if (patch.updatedAtProvided) {
            patch.updatedAt.trimAscii()
        } else if (existingMetadata.updated_at.trimAscii().size > 0) {
            existingMetadata.updated_at
        } else {
            archive.updated_at
        }

        let rootOk = MetadataDao.upsertRootMetadataObject(
            "archive",
            archiveId,
            nextTitle,
            nextDescription,
            releaseAt: nextReleaseAt,
            sourceNamespace: pluginNamespace,
            updatedAt: nextUpdatedAt
        )
        if (!rootOk) {
            logWarn(taskId, "archive metadata update failed while applying metadata patch: ${archiveId}")
            return false
        }

        if (patch.tagsProvided) {
            let tagOk = MetadataDao.replaceMetadataTags("archive", archiveId, splitTagTokens(patch.tags))
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

    public static func applyTankoubonMetadataPatch(taskId: Int64, tankoubonId: String, patch: ArchiveMetadataPatch, pluginNamespace: String): Bool {
        let tankoubon = match (TankoubonDao.getTankoubonById(tankoubonId)) {
            case Some(data) => data
            case None =>
                logWarn(taskId, "tankoubon not found when applying metadata patch: ${tankoubonId}")
                return false
        }

        let existingMetadata = match (ensureTankoubonMetadataObject(tankoubonId)) {
            case Some(data) => data
            case None =>
                logWarn(taskId, "tankoubon metadata row missing: ${tankoubonId}")
                return false
        }

        if (patch.createdAtProvided) {
            logWarn(taskId, "ignore tankoubon created_at patch (read-only): ${tankoubonId}")
        }

        let nextTitle = if (patch.titleProvided) { patch.title.trimAscii() } else { existingMetadata.title }
        let nextDescription = if (patch.summaryProvided) { patch.summary } else { existingMetadata.description }
        let nextReleaseAt = if (patch.releaseAtProvided) {
            patch.releaseAt.trimAscii()
        } else {
            existingMetadata.release_at
        }
        let nextUpdatedAt = if (patch.updatedAtProvided) {
            patch.updatedAt.trimAscii()
        } else if (existingMetadata.updated_at.trimAscii().size > 0) {
            existingMetadata.updated_at
        } else {
            tankoubon.updated_at
        }

        let rootOk = MetadataDao.upsertRootMetadataObject(
            "tankoubon",
            tankoubonId,
            nextTitle,
            nextDescription,
            releaseAt: nextReleaseAt,
            sourceNamespace: pluginNamespace,
            updatedAt: nextUpdatedAt
        )
        if (!rootOk) {
            logWarn(taskId, "tankoubon metadata update failed while applying metadata patch: ${tankoubonId}")
            return false
        }

        if (patch.tagsProvided) {
            let tagOk = MetadataDao.replaceMetadataTags("tankoubon", tankoubonId, splitTagTokens(patch.tags))
            if (!tagOk) {
                logWarn(taskId, "tankoubon tag update failed: ${tankoubonId}")
            }
        }

        if (patch.coverProvided) {
            applyTankoubonAssetFromOutput(taskId, tankoubonId, "cover", patch.cover, pluginNamespace)
        }
        if (patch.backdropProvided) {
            applyTankoubonAssetFromOutput(taskId, tankoubonId, "backdrop", patch.backdrop, pluginNamespace)
        }
        if (patch.clearlogoProvided) {
            applyTankoubonAssetFromOutput(taskId, tankoubonId, "clearlogo", patch.clearlogo, pluginNamespace)
        }
        return true
    }
}
