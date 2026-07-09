package lanlu.contexts.metadata.infrastructure.persistence

import std.collection.*
import std.io.ByteBuffer
import stdx.encoding.json.stream.*
import lanlu.contexts.metadata.domain.*
import lanlu.contexts.tag.infrastructure.persistence.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import lanlu.infrastructure.kv.*
import csorm.*

public class MetadataAssetData {
    public var slot: String = ""
    public var asset_id: Int64 = 0

    public init() {}

    public init(slot: String, assetId: Int64) {
        this.slot = slot
        this.asset_id = assetId
    }

    /** 槽位枚举视图（csorm ActiveEnum 落地）。 */
    public mut prop slotEnum: MetadataAssetSlot {
        get() { MetadataAssetSlot.fromDb(slot) }
        set(v) { slot = v.toDb() }
    }
}

public class MetadataObjectData {
    public var id: Int64 = 0
    public var entity_type: String = ""
    public var entity_id: String = ""
    public var parent_entity_type: String = ""
    public var parent_entity_id: String = ""
    public var title: String = ""
    public var description: String = ""
    public var volume_no: Int32 = 0
    public var order_index: Int32 = 0
    public var page_number: Int32 = 0
    public var entry_path: String = ""
    public var extra_data: String = "{}"
    public var source_namespace: String = ""
    public var release_at: String = ""
    public var created_at: String = ""
    public var updated_at: String = ""
    public var tags: Array<String> = Array<String>()
    public var assets: Array<MetadataAssetData> = Array<MetadataAssetData>()

    public mut prop entityType: MetadataEntityType {
        get() {
            MetadataEntityType.fromDb(entity_type)
        }
        set(value) {
            entity_type = value.toDb()
        }
    }

    public mut prop parentEntityType: MetadataEntityType {
        get() {
            MetadataEntityType.fromDb(parent_entity_type)
        }
        set(value) {
            parent_entity_type = value.toDb()
        }
    }
}

public class MetadataChildData {
    public var entity_type: String = "archive"
    public var entity_id: String = ""
    public var volume_no: Int32 = 0
    public var order_index: Int32 = 0

    public mut prop entityType: MetadataEntityType {
        get() {
            MetadataEntityType.fromDb(entity_type)
        }
        set(value) {
            entity_type = value.toDb()
        }
    }
}

public class MetadataDao {
    private static let logger = getLogger("metadata_dao")

    private static func invalidateAssetDerivedCaches(entityType: String, entityId: String, reason: String): Unit {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        if (normalizedId.size == 0) {
            return
        }
        if (normalizedType == "archive") {
            let _ = DerivedCacheUtils.bumpArchiveAssetsRawVersion("${reason}:${normalizedId}")
        } else if (normalizedType == "tankoubon") {
            let _ = DerivedCacheUtils.bumpTankoubonAggregatedContentVersion("${reason}:${normalizedId}")
        }
    }

    private static func normalizePageEntryPath(entryPath: String, pageNumber: Int32): String {
        let trimmed = entryPath.trimAscii()
        if (trimmed.size > 0) {
            return trimmed
        }
        if (pageNumber > 0) {
            return "__page_${pageNumber}"
        }
        return "__page_0"
    }

    private static func buildPageEntityId(parentArchiveId: String, entryPath: String): String {
        return "${parentArchiveId}:${entryPath}"
    }

    private static func readExtraBool(extraData: String, key: String): Bool {
        let normalized = extraData.trimAscii()
        if (normalized.size == 0 || normalized == "null") {
            return false
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(normalized.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return false
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                if (name == key) {
                    match (r.peek()) {
                        case Some(_) =>
                            let raw = r.readValue<String>().trimAscii().toAsciiLower()
                            return raw == "true" || raw == "1" || raw == "yes" || raw == "on"
                        case None => return false
                    }
                }
                r.skip()
            }
            r.endObject()
        } catch (_: Exception) {}
        return false
    }

    private static func readExtraString(extraData: String, key: String): String {
        let normalized = extraData.trimAscii()
        if (normalized.size == 0 || normalized == "null") {
            return ""
        }
        try {
            var buf = ByteBuffer()
            unsafe { buf.write(normalized.rawData()) }
            let r = JsonReader(buf)
            if (r.peek() != Some(BeginObject)) {
                return ""
            }
            r.startObject()
            while (r.peek() != EndObject) {
                let name = r.readName()
                if (name == key) {
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
                r.skip()
            }
            r.endObject()
        } catch (_: Exception) {}
        return ""
    }

    private static func mapMetadataObjectRow(row: Row): MetadataObjectData {
        let data = MetadataObjectData()
        data.id = row.getOrNullInt64(0) ?? 0
        data.entity_type = row.getOrNullText(1) ?? ""
        data.entity_id = row.getOrNullText(2) ?? ""
        data.parent_entity_type = row.getOrNullText(3) ?? ""
        data.parent_entity_id = row.getOrNullText(4) ?? ""
        data.title = row.getOrNullText(5) ?? ""
        data.description = row.getOrNullText(6) ?? ""
        data.volume_no = row.getOrNullInt32(7) ?? 0
        data.order_index = row.getOrNullInt32(8) ?? 0
        data.page_number = row.getOrNullInt32(9) ?? 0
        data.entry_path = row.getOrNullText(10) ?? ""
        data.extra_data = row.getOrNullText(11) ?? "{}"
        data.source_namespace = row.getOrNullText(12) ?? ""
        data.created_at = row.getOrNullText(13) ?? ""
        data.updated_at = row.getOrNullText(14) ?? ""
        data.release_at = row.getOrNullText(15) ?? ""
        return data
    }

    private static func loadTags(db: Database, metadataId: Int64): Array<String> {
        if (metadataId <= 0) {
            return Array<String>()
        }
        let rows = db.raw<String>("SELECT tag FROM metadata_tags WHERE metadata_id = $1 ORDER BY tag", [vint(metadataId)], { row => (row.getOrNullText(0) ?? "").trimAscii() })
        let out = ArrayList<String>()
        for (tag in rows) {
            if (tag.size > 0) {
                out.add(tag)
            }
        }
        return out.toArray()
    }

    private static func loadAssets(db: Database, metadataId: Int64): Array<MetadataAssetData> {
        if (metadataId <= 0) {
            return Array<MetadataAssetData>()
        }
        let out = ArrayList<MetadataAssetData>()
        let rows = db.raw<MetadataAssetData>("SELECT slot, asset_id FROM metadata_assets WHERE metadata_id = $1 ORDER BY slot", [vint(metadataId)], { row =>
            MetadataAssetData((row.getOrNullText(0) ?? "").trimAscii().toAsciiLower(), row.getOrNullInt64(1) ?? 0)
        })
        for (a in rows) {
            if (a.slot.size > 0 && a.asset_id > 0) {
                out.add(a)
            }
        }
        return out.toArray()
    }

    private static func getMetadataIdForRoot(db: Database, entityType: String, entityId: String): Int64 {
        db.rawOne<Int64>("""
            SELECT id FROM metadata_objects WHERE entity_type = $1 AND entity_id = $2 LIMIT 1
        """, [vtext(entityType), vtext(entityId)], { row => row.getOrNullInt64(0) ?? 0 }) ?? 0
    }

    public static func getMetadataObject(entityType: String, entityId: String): Option<MetadataObjectData> {
        match (DatabaseConfig.getDatabase()) {
            case None => return None
            case Some(db) =>
                try {
                    let dataOpt = db.rawOne<MetadataObjectData>("""
                        SELECT id, entity_type, entity_id, parent_entity_type, parent_entity_id,
                               COALESCE(title, ''), COALESCE(description, ''), COALESCE(volume_no, 0),
                               COALESCE(order_index, 0), COALESCE(page_number, 0), COALESCE(entry_path, ''),
                               COALESCE(CAST(extra_data AS TEXT), '{}'), COALESCE(source_namespace, ''),
                               COALESCE(created_at::TEXT, ''), COALESCE(updated_at::TEXT, ''), COALESCE(release_at::TEXT, '')
                        FROM metadata_objects
                        WHERE entity_type = $1 AND entity_id = $2
                        LIMIT 1
                    """, [vtext(entityType), vtext(entityId)], { row => mapMetadataObjectRow(row) })
                    match (dataOpt) {
                        case Some(data) =>
                            data.tags = loadTags(db, data.id)
                            data.assets = loadAssets(db, data.id)
                            return Some(data)
                        case None => return None
                    }
                } catch (_: Exception) {
                    return None
                }
        }
    }

    public static func upsertRootMetadataObject(
        entityType: String,
        entityId: String,
        title: String,
        description: String,
        releaseAt!: String = "",
        sourceNamespace!: String = "",
        createdAt!: String = "",
        updatedAt!: String = ""
    ): Bool {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        if (normalizedId.size == 0 || (normalizedType != "archive" && normalizedType != "tankoubon")) {
            return false
        }

        match (DatabaseConfig.getDatabase()) {
            case None => return false
            case Some(db) =>
                try {
                    let existingId = getMetadataIdForRoot(db, normalizedType, normalizedId)
                    if (existingId > 0) {
                        db.execRaw("""
                            UPDATE metadata_objects
                            SET title = $1,
                                description = $2,
                                release_at = COALESCE(CAST(NULLIF(TRIM(CAST($3 AS TEXT)), '') AS TIMESTAMP), release_at),
                                source_namespace = $4,
                                updated_at = COALESCE(CAST(NULLIF(TRIM(CAST($5 AS TEXT)), '') AS TIMESTAMP), CURRENT_TIMESTAMP)
                            WHERE id = $6
                        """, [vtext(title), vtext(description), vtext(releaseAt), vtext(sourceNamespace), vtext(updatedAt), vint(existingId)])
                        return true
                    }

                    db.execRaw("""
                        INSERT INTO metadata_objects (
                            entity_type, entity_id, parent_entity_type, parent_entity_id,
                            title, description, volume_no, order_index, page_number, entry_path,
                            extra_data, source_namespace, release_at, created_at, updated_at
                        ) VALUES (
                            $1, $2, '', '', $3, $4, 0, 0, 0, '',
                            '{}'::jsonb, $5,
                            CAST(NULLIF(TRIM(CAST($6 AS TEXT)), '') AS TIMESTAMP),
                            COALESCE(CAST(NULLIF(TRIM(CAST($7 AS TEXT)), '') AS TIMESTAMP), CURRENT_TIMESTAMP),
                            COALESCE(CAST(NULLIF(TRIM(CAST($8 AS TEXT)), '') AS TIMESTAMP), CURRENT_TIMESTAMP)
                        )
                    """, [vtext(normalizedType), vtext(normalizedId), vtext(title), vtext(description), vtext(sourceNamespace), vtext(releaseAt), vtext(createdAt), vtext(updatedAt)])
                    return true
                } catch (e: Exception) {
                    logger.error("upsertRootMetadataObject failed", ("entityType", normalizedType), ("entityId", normalizedId), ("error", e.message))
                    return false
                }
        }
    }

    public static func touchRootMetadataObject(entityType: String, entityId: String): Bool {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        if (normalizedId.size == 0) {
            return false
        }

        match (DatabaseConfig.getDatabase()) {
            case None => return false
            case Some(db) =>
                try {
                    let aff = db.execRaw("""
                        UPDATE metadata_objects
                        SET updated_at = CURRENT_TIMESTAMP
                        WHERE entity_type = $1 AND entity_id = $2
                    """, [vtext(normalizedType), vtext(normalizedId)])
                    return aff > 0
                } catch (e: Exception) {
                    logger.error("touchRootMetadataObject failed", ("entityType", normalizedType), ("entityId", normalizedId), ("error", e.message))
                    return false
                }
        }
    }

    public static func replaceMetadataTags(entityType: String, entityId: String, tags: Array<String>): Bool {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        if (normalizedId.size == 0) {
            return false
        }
        let normalizedTags = TagDao.normalizeTags(tags)

        return DatabaseConfig.withTransaction({ db =>
            let metadataId = getMetadataIdForRoot(db, normalizedType, normalizedId)
            if (metadataId <= 0) {
                return false
            }

            if (!TagDao.ensureTagDictionaryEntriesWithConnection(db, normalizedTags)) {
                return false
            }

            db.execRaw("DELETE FROM metadata_tags WHERE metadata_id = $1", [vint(metadataId)])

            let seen = HashSet<String>()
            for (rawTag in normalizedTags) {
                    let tag = rawTag.trimAscii()
                    if (tag.size == 0 || seen.contains(tag)) {
                        continue
                    }
                    seen.add(tag)
                    db.execRaw("""
INSERT INTO metadata_tags (metadata_id, tag) SELECT $1, $2 WHERE NOT EXISTS (SELECT 1 FROM metadata_tags WHERE metadata_id = $3 AND tag = $4)
""", [vint(metadataId), vtext(tag), vint(metadataId), vtext(tag)])
                }
                return true
        })
    }

    public static func replaceMetadataAssets(entityType: String, entityId: String, assets: Array<MetadataAssetData>): Bool {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        if (normalizedId.size == 0) {
            return false
        }

        let updated = DatabaseConfig.withTransaction({ db =>
            let metadataId = getMetadataIdForRoot(db, normalizedType, normalizedId)
            if (metadataId <= 0) {
                return false
            }

            db.execRaw("DELETE FROM metadata_assets WHERE metadata_id = $1", [vint(metadataId)])

            let seen = HashSet<String>()
            for (asset in assets) {
                let slot = asset.slot.trimAscii().toAsciiLower()
                if (slot.size == 0 || asset.asset_id <= 0 || seen.contains(slot)) {
                    continue
                }
                seen.add(slot)
                let aff = db.execRaw("UPDATE metadata_assets SET asset_id = $1, updated_at = CURRENT_TIMESTAMP WHERE metadata_id = $2 AND slot = $3", [vint(asset.asset_id), vint(metadataId), vtext(slot)])
                if (aff <= 0) {
                    db.execRaw("INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at) SELECT $1, $2, $3, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP WHERE NOT EXISTS (SELECT 1 FROM metadata_assets WHERE metadata_id = $4 AND slot = $5)", [vint(metadataId), vtext(slot), vint(asset.asset_id), vint(metadataId), vtext(slot)])
                }
            }
            return true
        })
        if (updated) {
            invalidateAssetDerivedCaches(normalizedType, normalizedId, "replaceMetadataAssets")
        }
        return updated
    }

public static func setMetadataAssetId(entityType: String, entityId: String, slot: String, assetId: Int64): Bool {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        let normalizedSlot = slot.trimAscii().toAsciiLower()
        if (normalizedId.size == 0 || normalizedSlot.size == 0) {
            return false
        }

        match (DatabaseConfig.getDatabase()) {
            case None => return false
            case Some(db) =>
                try {
                    let metadataId = getMetadataIdForRoot(db, normalizedType, normalizedId)
                    if (metadataId <= 0) {
                        return false
                    }
                    if (assetId > 0) {
                        let aff = db.execRaw("UPDATE metadata_assets SET asset_id = $1, updated_at = CURRENT_TIMESTAMP WHERE metadata_id = $2 AND slot = $3", [vint(assetId), vint(metadataId), vtext(normalizedSlot)])
                        if (aff <= 0) {
                            db.execRaw("INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at) SELECT $1, $2, $3, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP WHERE NOT EXISTS (SELECT 1 FROM metadata_assets WHERE metadata_id = $4 AND slot = $5)", [vint(metadataId), vtext(normalizedSlot), vint(assetId), vint(metadataId), vtext(normalizedSlot)])
                        }
                    } else {
                        db.execRaw("DELETE FROM metadata_assets WHERE metadata_id = $1 AND slot = $2", [vint(metadataId), vtext(normalizedSlot)])
                    }
                    invalidateAssetDerivedCaches(normalizedType, normalizedId, "setMetadataAssetId:${normalizedSlot}")
                    return true
                } catch (e: Exception) {
                    logger.error("setMetadataAssetId failed", ("entityType", normalizedType), ("entityId", normalizedId), ("slot", normalizedSlot), ("error", e.message))
                    return false
                }
        }
    }

    public static func getMetadataAssetId(entityType: String, entityId: String, slot: String): Int64 {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        let normalizedSlot = slot.trimAscii().toAsciiLower()
        if (normalizedId.size == 0 || normalizedSlot.size == 0) {
            return 0
        }

        match (DatabaseConfig.getDatabase()) {
            case None => return 0
            case Some(db) =>
                try {
                    let metadataId = getMetadataIdForRoot(db, normalizedType, normalizedId)
                    if (metadataId <= 0) {
                        return 0
                    }
                    return db.rawOne<Int64>("""
                        SELECT asset_id FROM metadata_assets WHERE metadata_id = $1 AND slot = $2 LIMIT 1
                    """, [vint(metadataId), vtext(normalizedSlot)], { row => row.getOrNullInt64(0) ?? 0 }) ?? 0
                } catch (_: Exception) {
                    return 0
                }
        }
    }

    public static func listPageMetadata(parentArchiveId: String, includeAttachments!: Bool = true): Array<PageMetadataData> {
        let normalizedParent = parentArchiveId.trimAscii()
        if (normalizedParent.size == 0) {
            return Array<PageMetadataData>()
        }

        let connOpt = DatabaseConfig.getDatabase()
        match (connOpt) {
            case None => return Array<PageMetadataData>()
            case Some(db) =>
                try {
                    let sql = if (includeAttachments) {
                        """
                        SELECT mo.id,
                               COALESCE(mo.page_number, 0),
                               COALESCE(mo.entry_path, ''),
                               COALESCE(mo.title, ''),
                               COALESCE(mo.description, ''),
                               COALESCE(mo.order_index, 0),
                               COALESCE(ma.asset_id, 0),
                               COALESCE(CAST(mo.extra_data AS TEXT), '{}'),
                               COALESCE(mo.release_at::TEXT, ''),
                               COALESCE(mo.created_at::TEXT, ''),
                               COALESCE(mo.updated_at::TEXT, ''),
                               COALESCE(mpa.id, 0),
                               COALESCE(mpa.slot, ''),
                               COALESCE(mpa.asset_id, 0),
                               COALESCE(mpa.name, ''),
                               COALESCE(mpa.mime_type, ''),
                               COALESCE(mpa.kind, ''),
                               COALESCE(mpa.language, ''),
                               COALESCE(mpa.order_index, 0),
                               COALESCE(mpa.created_at::TEXT, ''),
                               COALESCE(mpa.updated_at::TEXT, '')
                        FROM metadata_objects mo
                        LEFT JOIN metadata_assets ma ON ma.metadata_id = mo.id AND ma.slot = 'thumb'
                        LEFT JOIN metadata_page_assets mpa ON mpa.metadata_id = mo.id
                        WHERE mo.entity_type = 'page'
                          AND mo.parent_entity_type = 'archive'
                          AND mo.parent_entity_id = ?
                        ORDER BY mo.page_number, mo.id, mpa.order_index, mpa.slot, mpa.name, mpa.id
                        """
                    } else {
                        """
                        SELECT mo.id,
                               COALESCE(mo.page_number, 0),
                               COALESCE(mo.entry_path, ''),
                               COALESCE(mo.title, ''),
                               COALESCE(mo.description, ''),
                               COALESCE(mo.order_index, 0),
                               COALESCE(ma.asset_id, 0),
                               COALESCE(CAST(mo.extra_data AS TEXT), '{}'),
                               COALESCE(mo.release_at::TEXT, ''),
                               COALESCE(mo.created_at::TEXT, ''),
                               COALESCE(mo.updated_at::TEXT, '')
                        FROM metadata_objects mo
                        LEFT JOIN metadata_assets ma ON ma.metadata_id = mo.id AND ma.slot = 'thumb'
                        WHERE mo.entity_type = 'page'
                          AND mo.parent_entity_type = 'archive'
                          AND mo.parent_entity_id = ?
                        ORDER BY mo.page_number, mo.id
                        """
                    }
                    let sqlWithPlaceholder = sql.replace("?", "$1")
                    let rows = db.raw<Row>(sqlWithPlaceholder, [vtext(normalizedParent)], { r => r })
                    let out = ArrayList<PageMetadataData>()
                    let attachmentsByMetadataId = HashMap<Int64, ArrayList<PageAttachmentData>>()
                    var currentMetadataId: Int64 = -1
                    for (row in rows) {
                                let metadataId = row.getOrNullInt64(0) ?? 0
                                if (metadataId != currentMetadataId) {
                                    let item = PageMetadataData()
                                    item.id = metadataId
                                    item.archive_id = 0
                                    item.page_number = row.getOrNullInt32(1) ?? 0
                                    item.entry_path = row.getOrNullText(2) ?? ""
                                    item.title = row.getOrNullText(3) ?? ""
                                    item.description = row.getOrNullText(4) ?? ""
                                    item.sort_index = row.getOrNullInt32(5) ?? 0
                                    item.thumb_asset_id = row.getOrNullInt64(6) ?? 0
                                    item.extra_data = row.getOrNullText(7) ?? "{}"
                                    item.hidden_in_files = readExtraBool(item.extra_data, "hidden_in_files")
                                    item.thumbhash = readExtraString(item.extra_data, "thumbhash")
                                    item.release_at = row.getOrNullText(8) ?? ""
                                    item.created_at = row.getOrNullText(9) ?? ""
                                    item.updated_at = row.getOrNullText(10) ?? ""
                                    out.add(item)
                                    currentMetadataId = metadataId
                                }

                                if (includeAttachments) {
                                    let attachmentId = row.getOrNullInt64(11) ?? 0
                                    let attachmentSlot = (row.getOrNullText(12) ?? "").trimAscii().toAsciiLower()
                                    let attachmentAssetId = row.getOrNullInt64(13) ?? 0
                                    if (attachmentId > 0 && attachmentSlot.size > 0 && attachmentAssetId > 0) {
                                        let attachment = PageAttachmentData()
                                        attachment.id = attachmentId
                                        attachment.metadata_id = currentMetadataId
                                        attachment.slot = attachmentSlot
                                        attachment.asset_id = attachmentAssetId
                                        attachment.name = row.getOrNullText(14) ?? ""
                                        attachment.mime_type = row.getOrNullText(15) ?? ""
                                        attachment.kind = (row.getOrNullText(16) ?? "").trimAscii().toAsciiLower()
                                        attachment.language = (row.getOrNullText(17) ?? "").trimAscii().toAsciiLower()
                                        attachment.order_index = row.getOrNullInt32(18) ?? 0
                                        attachment.created_at = row.getOrNullText(19) ?? ""
                                        attachment.updated_at = row.getOrNullText(20) ?? ""
                                        match (attachmentsByMetadataId.get(currentMetadataId)) {
                                            case Some(existing) =>
                                                existing.add(attachment)
                                            case None =>
                                                let list = ArrayList<PageAttachmentData>()
                                                list.add(attachment)
                                                attachmentsByMetadataId[currentMetadataId] = list
                                        }
                                    }
                                }
                    }
                        if (includeAttachments) {
                            for (item in out) {
                                match (attachmentsByMetadataId.get(item.id)) {
                                    case Some(attachments) =>
                                        item.attachments = attachments.toArray()
                                    case None => ()
                                }
                            }
                        }
                        return out.toArray()
                } catch (e: Exception) {
                    logger.error("listPageMetadata failed", ("archiveId", normalizedParent), ("error", e.message))
                    return Array<PageMetadataData>()
                }
        }
    }

    public static func upsertPageMetadataBatch(parentArchiveId: String, items: Array<PageMetadataData>, sourceNamespace!: String = ""): Bool {
        let normalizedParent = parentArchiveId.trimAscii()
        if (normalizedParent.size == 0) {
            return false
        }
        if (items.size == 0) {
            return true
        }

        return DatabaseConfig.withTransaction({ db =>
            for (item in items) {
                let safeEntryPath = normalizePageEntryPath(item.entry_path, item.page_number)
                let entityId = buildPageEntityId(normalizedParent, safeEntryPath)
                var metadataId = db.rawOne<Int64>(
                    "SELECT id FROM metadata_objects WHERE entity_type = 'page' AND parent_entity_type = 'archive' AND parent_entity_id = $1 AND entry_path = $2 LIMIT 1",
                    [vtext(normalizedParent), vtext(safeEntryPath)],
                    { row => row.getOrNullInt64(0) ?? 0 }
                ) ?? 0

                if (metadataId > 0) {
                    db.execRaw("""
                        UPDATE metadata_objects
                        SET entity_id = $1, title = $2, description = $3, order_index = $4, page_number = $5, entry_path = $6,
                            extra_data = jsonb_set(jsonb_set(COALESCE(CAST($7 AS JSONB), '{}'::jsonb), '{hidden_in_files}', to_jsonb(CAST($8 AS BOOLEAN)), true), '{thumbhash}', to_jsonb(CAST($9 AS TEXT)), true),
                            release_at = COALESCE(CAST(NULLIF(TRIM(CAST($10 AS TEXT)), '') AS TIMESTAMP), release_at),
                            source_namespace = $11,
                            updated_at = COALESCE(CAST(NULLIF(TRIM(CAST($12 AS TEXT)), '') AS TIMESTAMP), CURRENT_TIMESTAMP)
                        WHERE id = $13
                    """, [vtext(entityId), vtext(item.title), vtext(item.description), vint(Int64(item.sort_index)), vint(Int64(item.page_number)), vtext(safeEntryPath), vtext(item.extra_data), vbool(item.hidden_in_files), vtext(item.thumbhash), vtext(item.release_at), vtext(sourceNamespace), vtext(item.updated_at), vint(metadataId)])
                } else {
                    db.execRaw("""
                        INSERT INTO metadata_objects (entity_type, entity_id, parent_entity_type, parent_entity_id, title, description, volume_no, order_index, page_number, entry_path, extra_data, source_namespace, release_at, created_at, updated_at)
                        VALUES ('page', $1, 'archive', $2, $3, $4, 0, $5, $6, $7,
                            jsonb_set(jsonb_set(COALESCE(CAST($8 AS JSONB), '{}'::jsonb), '{hidden_in_files}', to_jsonb(CAST($9 AS BOOLEAN)), true), '{thumbhash}', to_jsonb(CAST($10 AS TEXT)), true),
                            $11, CAST(NULLIF(TRIM(CAST($12 AS TEXT)), '') AS TIMESTAMP),
                            COALESCE(CAST(NULLIF(TRIM(CAST($13 AS TEXT)), '') AS TIMESTAMP), CURRENT_TIMESTAMP),
                            COALESCE(CAST(NULLIF(TRIM(CAST($14 AS TEXT)), '') AS TIMESTAMP), CURRENT_TIMESTAMP))
                    """, [vtext(entityId), vtext(normalizedParent), vtext(item.title), vtext(item.description), vint(Int64(item.sort_index)), vint(Int64(item.page_number)), vtext(safeEntryPath), vtext(item.extra_data), vbool(item.hidden_in_files), vtext(item.thumbhash), vtext(sourceNamespace), vtext(item.release_at), vtext(item.created_at), vtext(item.updated_at)])
                    metadataId = db.rawOne<Int64>(
                        "SELECT id FROM metadata_objects WHERE entity_type = 'page' AND parent_entity_type = 'archive' AND parent_entity_id = $1 AND entry_path = $2 LIMIT 1",
                        [vtext(normalizedParent), vtext(safeEntryPath)],
                        { row => row.getOrNullInt64(0) ?? 0 }
                    ) ?? 0
                }

                if (metadataId <= 0) {
                    continue
                }

                if (item.thumb_asset_id > 0) {
                    let aff = db.execRaw("UPDATE metadata_assets SET asset_id = $1, updated_at = CURRENT_TIMESTAMP WHERE metadata_id = $2 AND slot = 'thumb'", [vint(item.thumb_asset_id), vint(metadataId)])
                    if (aff <= 0) {
                        db.execRaw("INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at) SELECT $1, 'thumb', $2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP WHERE NOT EXISTS (SELECT 1 FROM metadata_assets WHERE metadata_id = $3 AND slot = 'thumb')", [vint(metadataId), vint(item.thumb_asset_id), vint(metadataId)])
                    }
                } else {
                    db.execRaw("DELETE FROM metadata_assets WHERE metadata_id = $1 AND slot = 'thumb'", [vint(metadataId)])
                }

                if (item.attachments_provided) {
                    db.execRaw("DELETE FROM metadata_page_assets WHERE metadata_id = $1", [vint(metadataId)])
                    for (attachment in item.attachments) {
                        let slot = attachment.slot.trimAscii().toAsciiLower()
                        let name = attachment.name.trimAscii()
                        if (slot.size == 0 || name.size == 0 || attachment.asset_id <= 0) {
                            continue
                        }
                        db.execRaw("INSERT INTO metadata_page_assets (metadata_id, slot, asset_id, name, mime_type, kind, language, order_index, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)", [vint(metadataId), vtext(slot), vint(attachment.asset_id), vtext(name), vtext(attachment.mime_type.trimAscii()), vtext(attachment.kind.trimAscii().toAsciiLower()), vtext(attachment.language.trimAscii().toAsciiLower()), vint(Int64(attachment.order_index))])
                    }
                }
            }
            return true
        })
    }

public static func getPageThumbAssetId(parentArchiveId: String, pageNumber: Int32): Int64 {
        let pages = listPageMetadata(parentArchiveId)
        for (page in pages) {
            if (page.page_number == pageNumber) {
                return page.thumb_asset_id
            }
        }
        return 0
    }

    public static func getPageThumbAssetIds(parentArchiveId: String): Array<Int64> {
        let pages = listPageMetadata(parentArchiveId)
        let out = ArrayList<Int64>()
        let seen = HashSet<Int64>()
        for (page in pages) {
            if (page.thumb_asset_id > 0 && !seen.contains(page.thumb_asset_id)) {
                seen.add(page.thumb_asset_id)
                out.add(page.thumb_asset_id)
            }
        }
        return out.toArray()
    }

    public static func getPageAttachmentAssetIds(parentArchiveId: String, slot!: String = ""): Array<Int64> {
        let pages = listPageMetadata(parentArchiveId)
        let out = ArrayList<Int64>()
        let seen = HashSet<Int64>()
        for (page in pages) {
            for (attachment in page.attachments) {
                let normalizedSlot = slot.trimAscii().toAsciiLower()
                if (normalizedSlot.size > 0 && attachment.slot.trimAscii().toAsciiLower() != normalizedSlot) {
                    continue
                }
                let assetId = attachment.asset_id
                if (assetId > 0 && !seen.contains(assetId)) {
                    seen.add(assetId)
                    out.add(assetId)
                }
            }
        }
        return out.toArray()
    }

    public static func deletePageMetadata(parentArchiveId: String): Bool {
        let normalizedParent = parentArchiveId.trimAscii()
        if (normalizedParent.size == 0) {
            return false
        }
        return DatabaseConfig.withTransaction({ db =>
            db.execRaw("DELETE FROM metadata_assets WHERE metadata_id IN (SELECT id FROM metadata_objects WHERE entity_type = 'page' AND parent_entity_type = 'archive' AND parent_entity_id = $1)", [vtext(normalizedParent)])
            db.execRaw("DELETE FROM metadata_tags WHERE metadata_id IN (SELECT id FROM metadata_objects WHERE entity_type = 'page' AND parent_entity_type = 'archive' AND parent_entity_id = $1)", [vtext(normalizedParent)])
            db.execRaw("DELETE FROM metadata_objects WHERE entity_type = 'page' AND parent_entity_type = 'archive' AND parent_entity_id = $1", [vtext(normalizedParent)])
            return true
        })
    }

    public static func deleteEntity(entityType: String, entityId: String): Bool {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        if (normalizedType.size == 0 || normalizedId.size == 0) {
            return false
        }
        return DatabaseConfig.withTransaction({ db =>
            db.execRaw("DELETE FROM metadata_assets WHERE metadata_id IN (SELECT id FROM metadata_objects WHERE entity_type = $1 AND entity_id = $2)", [vtext(normalizedType), vtext(normalizedId)])
            db.execRaw("DELETE FROM metadata_tags WHERE metadata_id IN (SELECT id FROM metadata_objects WHERE entity_type = $1 AND entity_id = $2)", [vtext(normalizedType), vtext(normalizedId)])
            db.execRaw("DELETE FROM metadata_objects WHERE entity_type = $1 AND entity_id = $2", [vtext(normalizedType), vtext(normalizedId)])
            return true
        })
    }

    public static func getTankoubonChildren(tankoubonId: String): Array<MetadataChildData> {
        let normalizedId = tankoubonId.trimAscii()
        if (normalizedId.size == 0) {
            return Array<MetadataChildData>()
        }

        match (DatabaseConfig.getDatabase()) {
            case None => return Array<MetadataChildData>()
            case Some(db) =>
                try {
                    let rows = db.raw<MetadataChildData>("""
                        SELECT a.arcid, COALESCE(ta.sort_order, 0)
                        FROM tankoubon_archives ta
                        JOIN tankoubons t ON t.id = ta.tankoubon_id
                        JOIN archives a ON a.id = ta.archive_id
                        WHERE t.tankoubon_id = $1
                        ORDER BY ta.sort_order, ta.id
                    """, [vtext(normalizedId)], { row =>
                        let child = MetadataChildData()
                        child.entity_id = row.getOrNullText(0) ?? ""
                        child.order_index = row.getOrNullInt32(1) ?? 1
                        child
                    })
                    let out = ArrayList<MetadataChildData>()
                    var idx: Int32 = 1
                    for (child in rows) {
                        child.volume_no = idx
                        if (child.entity_id.trimAscii().size > 0) {
                            out.add(child)
                            idx += 1
                        }
                    }
                    return out.toArray()
                } catch (e: Exception) {
                    logger.error("getTankoubonChildren failed", ("tankoubonId", normalizedId), ("error", e.message))
                    return Array<MetadataChildData>()
                }
        }
    }
}
