package lanlu.contexts.metadata.infrastructure.persistence

import ace_orm.*
import std.collection.*
import std.io.ByteBuffer
import stdx.encoding.json.stream.*
import lanlu.contexts.metadata.domain.*
import lanlu.contexts.tag.infrastructure.persistence.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import lanlu.infrastructure.kv.*

public class MetadataAssetData {
    public var slot: String = ""
    public var asset_id: Int64 = 0

    public init() {}

    public init(slot: String, assetId: Int64) {
        this.slot = slot
        this.asset_id = assetId
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

    private static func mapMetadataObjectRow(r: Row): MetadataObjectData {
        let data = MetadataObjectData()
        data.id = r.getInt("id")
        data.entity_type = r.getText("entity_type")
        data.entity_id = r.getText("entity_id")
        data.parent_entity_type = r.getText("parent_entity_type")
        data.parent_entity_id = r.getText("parent_entity_id")
        data.title = r.getText("title")
        data.description = r.getText("description")
        data.volume_no = Int32(r.getInt("volume_no"))
        data.order_index = Int32(r.getInt("order_index"))
        data.page_number = Int32(r.getInt("page_number"))
        data.entry_path = r.getText("entry_path")
        data.extra_data = r.getText("extra_data")
        data.source_namespace = r.getText("source_namespace")
        data.created_at = r.getText("created_at")
        data.updated_at = r.getText("updated_at")
        data.release_at = r.getText("release_at")
        return data
    }

    private static func loadTags(metadataId: Int64): Array<String> {
        if (metadataId <= 0) {
            return Array<String>()
        }
        let out = ArrayList<String>()
        try {
            let rows = DatabaseConfig.driver().query("SELECT tag FROM metadata_tags WHERE metadata_id = $1 ORDER BY tag", [DbInt(metadataId)])
            for (r in rows) {
                let tag = r.getText("tag").trimAscii()
                if (tag.size > 0) {
                    out.add(tag)
                }
            }
        } catch (_: Exception) {}
        return out.toArray()
    }

    private static func loadAssets(metadataId: Int64): Array<MetadataAssetData> {
        if (metadataId <= 0) {
            return Array<MetadataAssetData>()
        }
        let out = ArrayList<MetadataAssetData>()
        try {
            let rows = DatabaseConfig.driver().query("SELECT slot, asset_id FROM metadata_assets WHERE metadata_id = $1 ORDER BY slot", [DbInt(metadataId)])
            for (r in rows) {
                let slot = r.getText("slot").trimAscii().toAsciiLower()
                let assetId = r.getInt("asset_id")
                if (slot.size > 0 && assetId > 0) {
                    out.add(MetadataAssetData(slot, assetId))
                }
            }
        } catch (_: Exception) {}
        return out.toArray()
    }

    private static func getMetadataIdForRoot(entityType: String, entityId: String): Int64 {
        try {
            let rows = DatabaseConfig.driver().query("SELECT id FROM metadata_objects WHERE entity_type = $1 AND entity_id = $2 LIMIT 1", [DbText(entityType), DbText(entityId)])
            if (rows.size > 0) {
                return rows[0].getInt("id")
            }
        } catch (_: Exception) {}
        return 0
    }

    public static func getMetadataObject(entityType: String, entityId: String): Option<MetadataObjectData> {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT id, entity_type, entity_id, parent_entity_type, parent_entity_id,
                       COALESCE(title, '') AS title, COALESCE(description, '') AS description, COALESCE(volume_no, 0) AS volume_no,
                       COALESCE(order_index, 0) AS order_index, COALESCE(page_number, 0) AS page_number, COALESCE(entry_path, '') AS entry_path,
                       COALESCE(CAST(extra_data AS TEXT), '{}') AS extra_data, COALESCE(source_namespace, '') AS source_namespace,
                       COALESCE(created_at::TEXT, '') AS created_at, COALESCE(updated_at::TEXT, '') AS updated_at, COALESCE(release_at::TEXT, '') AS release_at
                FROM metadata_objects
                WHERE entity_type = $1 AND entity_id = $2
                LIMIT 1
            """, [DbText(entityType), DbText(entityId)])
            if (rows.size == 0) {
                return None
            }
            let data = mapMetadataObjectRow(rows[0])
            data.tags = loadTags(data.id)
            data.assets = loadAssets(data.id)
            return Some(data)
        } catch (_: Exception) {
            return None
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

        try {
            let existingId = getMetadataIdForRoot(normalizedType, normalizedId)
            if (existingId > 0) {
                DatabaseConfig.driver().exec("""
                    UPDATE metadata_objects
                    SET title = $1,
                        description = $2,
                        release_at = COALESCE(CAST(NULLIF(TRIM(CAST($3 AS TEXT)), '') AS TIMESTAMP), release_at),
                        source_namespace = $4,
                        updated_at = COALESCE(CAST(NULLIF(TRIM(CAST($5 AS TEXT)), '') AS TIMESTAMP), CURRENT_TIMESTAMP)
                    WHERE id = $6
                """, [DbText(title), DbText(description), DbText(releaseAt), DbText(sourceNamespace), DbText(updatedAt), DbInt(existingId)])
                return true
            }

            DatabaseConfig.driver().exec("""
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
            """, [DbText(normalizedType), DbText(normalizedId), DbText(title), DbText(description), DbText(sourceNamespace), DbText(releaseAt), DbText(createdAt), DbText(updatedAt)])
            return true
        } catch (e: Exception) {
            logger.error("upsertRootMetadataObject failed", ("entityType", normalizedType), ("entityId", normalizedId), ("error", e.message))
            return false
        }
    }

    public static func touchRootMetadataObject(entityType: String, entityId: String): Bool {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        if (normalizedId.size == 0) {
            return false
        }

        try {
            let result = DatabaseConfig.driver().exec("""
                UPDATE metadata_objects
                SET updated_at = CURRENT_TIMESTAMP
                WHERE entity_type = $1 AND entity_id = $2
            """, [DbText(normalizedType), DbText(normalizedId)])
            return result > 0
        } catch (e: Exception) {
            logger.error("touchRootMetadataObject failed", ("entityType", normalizedType), ("entityId", normalizedId), ("error", e.message))
            return false
        }
    }

    public static func replaceMetadataTags(entityType: String, entityId: String, tags: Array<String>): Bool {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        if (normalizedId.size == 0) {
            return false
        }
        let normalizedTags = TagDao.normalizeTags(tags)

        return DatabaseConfig.withTransaction("metadata_dao", "replaceMetadataTags failed", { =>
            let metadataId = getMetadataIdForRoot(normalizedType, normalizedId)
            if (metadataId <= 0) {
                return false
            }

            if (!TagDao.ensureTagDictionaryEntries(normalizedTags)) {
                return false
            }

            DatabaseConfig.driver().exec("DELETE FROM metadata_tags WHERE metadata_id = $1", [DbInt(metadataId)])

            let seen = HashSet<String>()
            for (rawTag in normalizedTags) {
                let tag = rawTag.trimAscii()
                if (tag.size == 0 || seen.contains(tag)) {
                    continue
                }
                seen.add(tag)
                DatabaseConfig.driver().exec("""
                    INSERT INTO metadata_tags (metadata_id, tag)
                    SELECT $1, $2
                    WHERE NOT EXISTS (
                        SELECT 1 FROM metadata_tags WHERE metadata_id = $3 AND tag = $4
                    )
                """, [DbInt(metadataId), DbText(tag), DbInt(metadataId), DbText(tag)])
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

        let updated = DatabaseConfig.withTransaction("metadata_dao", "replaceMetadataAssets failed", { =>
            let metadataId = getMetadataIdForRoot(normalizedType, normalizedId)
            if (metadataId <= 0) {
                return false
            }

            DatabaseConfig.driver().exec("DELETE FROM metadata_assets WHERE metadata_id = $1", [DbInt(metadataId)])

            let seen = HashSet<String>()
            for (asset in assets) {
                let slot = asset.slot.trimAscii().toAsciiLower()
                if (slot.size == 0 || asset.asset_id <= 0 || seen.contains(slot)) {
                    continue
                }
                seen.add(slot)
                let affected = DatabaseConfig.driver().exec("""
                    UPDATE metadata_assets
                    SET asset_id = $1, updated_at = CURRENT_TIMESTAMP
                    WHERE metadata_id = $2 AND slot = $3
                """, [DbInt(asset.asset_id), DbInt(metadataId), DbText(slot)])
                if (affected <= 0) {
                    DatabaseConfig.driver().exec("""
                        INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at)
                        SELECT $1, $2, $3, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                        WHERE NOT EXISTS (
                            SELECT 1 FROM metadata_assets WHERE metadata_id = $4 AND slot = $5
                        )
                    """, [DbInt(metadataId), DbText(slot), DbInt(asset.asset_id), DbInt(metadataId), DbText(slot)])
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

        try {
            let metadataId = getMetadataIdForRoot(normalizedType, normalizedId)
            if (metadataId <= 0) {
                return false
            }
            if (assetId > 0) {
                let affected = DatabaseConfig.driver().exec("""
                    UPDATE metadata_assets
                    SET asset_id = $1, updated_at = CURRENT_TIMESTAMP
                    WHERE metadata_id = $2 AND slot = $3
                """, [DbInt(assetId), DbInt(metadataId), DbText(normalizedSlot)])
                if (affected <= 0) {
                    DatabaseConfig.driver().exec("""
                        INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at)
                        SELECT $1, $2, $3, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                        WHERE NOT EXISTS (
                            SELECT 1 FROM metadata_assets WHERE metadata_id = $4 AND slot = $5
                        )
                    """, [DbInt(metadataId), DbText(normalizedSlot), DbInt(assetId), DbInt(metadataId), DbText(normalizedSlot)])
                }
            } else {
                DatabaseConfig.driver().exec("DELETE FROM metadata_assets WHERE metadata_id = $1 AND slot = $2", [DbInt(metadataId), DbText(normalizedSlot)])
            }
            invalidateAssetDerivedCaches(normalizedType, normalizedId, "setMetadataAssetId:${normalizedSlot}")
            return true
        } catch (e: Exception) {
            logger.error("setMetadataAssetId failed", ("entityType", normalizedType), ("entityId", normalizedId), ("slot", normalizedSlot), ("error", e.message))
            return false
        }
    }

    public static func getMetadataAssetId(entityType: String, entityId: String, slot: String): Int64 {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        let normalizedSlot = slot.trimAscii().toAsciiLower()
        if (normalizedId.size == 0 || normalizedSlot.size == 0) {
            return 0
        }

        try {
            let metadataId = getMetadataIdForRoot(normalizedType, normalizedId)
            if (metadataId <= 0) {
                return 0
            }
            let rows = DatabaseConfig.driver().query("SELECT asset_id FROM metadata_assets WHERE metadata_id = $1 AND slot = $2 LIMIT 1", [DbInt(metadataId), DbText(normalizedSlot)])
            if (rows.size > 0) {
                return rows[0].getInt("asset_id")
            }
            return 0
        } catch (_: Exception) {
            return 0
        }
    }

    public static func listPageMetadata(parentArchiveId: String, includeAttachments!: Bool = true): Array<PageMetadataData> {
        let normalizedParent = parentArchiveId.trimAscii()
        if (normalizedParent.size == 0) {
            return Array<PageMetadataData>()
        }

        try {
            let sql = if (includeAttachments) {
                """
                SELECT mo.id AS mo_id,
                       COALESCE(mo.page_number, 0) AS page_number,
                       COALESCE(mo.entry_path, '') AS entry_path,
                       COALESCE(mo.title, '') AS title,
                       COALESCE(mo.description, '') AS description,
                       COALESCE(mo.order_index, 0) AS mo_order_index,
                       COALESCE(ma.asset_id, 0) AS thumb_asset_id,
                       COALESCE(CAST(mo.extra_data AS TEXT), '{}') AS extra_data,
                       COALESCE(mo.release_at::TEXT, '') AS release_at,
                       COALESCE(mo.created_at::TEXT, '') AS mo_created_at,
                       COALESCE(mo.updated_at::TEXT, '') AS mo_updated_at,
                       COALESCE(mpa.id, 0) AS mpa_id,
                       COALESCE(mpa.slot, '') AS mpa_slot,
                       COALESCE(mpa.asset_id, 0) AS mpa_asset_id,
                       COALESCE(mpa.name, '') AS mpa_name,
                       COALESCE(mpa.mime_type, '') AS mime_type,
                       COALESCE(mpa.kind, '') AS kind,
                       COALESCE(mpa.language, '') AS language,
                       COALESCE(mpa.order_index, 0) AS mpa_order_index,
                       COALESCE(mpa.created_at::TEXT, '') AS mpa_created_at,
                       COALESCE(mpa.updated_at::TEXT, '') AS mpa_updated_at
                FROM metadata_objects mo
                LEFT JOIN metadata_assets ma ON ma.metadata_id = mo.id AND ma.slot = 'thumb'
                LEFT JOIN metadata_page_assets mpa ON mpa.metadata_id = mo.id
                WHERE mo.entity_type = 'page'
                  AND mo.parent_entity_type = 'archive'
                  AND mo.parent_entity_id = $1
                ORDER BY mo.page_number, mo.id, mpa.order_index, mpa.slot, mpa.name, mpa.id
                """
            } else {
                """
                SELECT mo.id AS mo_id,
                       COALESCE(mo.page_number, 0) AS page_number,
                       COALESCE(mo.entry_path, '') AS entry_path,
                       COALESCE(mo.title, '') AS title,
                       COALESCE(mo.description, '') AS description,
                       COALESCE(mo.order_index, 0) AS mo_order_index,
                       COALESCE(ma.asset_id, 0) AS thumb_asset_id,
                       COALESCE(CAST(mo.extra_data AS TEXT), '{}') AS extra_data,
                       COALESCE(mo.release_at::TEXT, '') AS release_at,
                       COALESCE(mo.created_at::TEXT, '') AS mo_created_at,
                       COALESCE(mo.updated_at::TEXT, '') AS mo_updated_at
                FROM metadata_objects mo
                LEFT JOIN metadata_assets ma ON ma.metadata_id = mo.id AND ma.slot = 'thumb'
                WHERE mo.entity_type = 'page'
                  AND mo.parent_entity_type = 'archive'
                  AND mo.parent_entity_id = $1
                ORDER BY mo.page_number, mo.id
                """
            }
            let rows = DatabaseConfig.driver().query(sql, [DbText(normalizedParent)])
            let out = ArrayList<PageMetadataData>()
            let attachmentsByMetadataId = HashMap<Int64, ArrayList<PageAttachmentData>>()
            var currentMetadataId: Int64 = -1
            for (r in rows) {
                let metadataId = r.getInt("mo_id")
                if (metadataId != currentMetadataId) {
                    let item = PageMetadataData()
                    item.id = metadataId
                    item.archive_id = 0
                    item.page_number = Int32(r.getInt("page_number"))
                    item.entry_path = r.getText("entry_path")
                    item.title = r.getText("title")
                    item.description = r.getText("description")
                    item.sort_index = Int32(r.getInt("mo_order_index"))
                    item.thumb_asset_id = r.getInt("thumb_asset_id")
                    item.extra_data = r.getText("extra_data")
                    item.hidden_in_files = readExtraBool(item.extra_data, "hidden_in_files")
                    item.thumbhash = readExtraString(item.extra_data, "thumbhash")
                    item.release_at = r.getText("release_at")
                    item.created_at = r.getText("mo_created_at")
                    item.updated_at = r.getText("mo_updated_at")
                    out.add(item)
                    currentMetadataId = metadataId
                }

                if (includeAttachments) {
                    let attachmentId = r.getInt("mpa_id")
                    let attachmentSlot = r.getText("mpa_slot").trimAscii().toAsciiLower()
                    let attachmentAssetId = r.getInt("mpa_asset_id")
                    if (attachmentId > 0 && attachmentSlot.size > 0 && attachmentAssetId > 0) {
                        let attachment = PageAttachmentData()
                        attachment.id = attachmentId
                        attachment.metadata_id = currentMetadataId
                        attachment.slot = attachmentSlot
                        attachment.asset_id = attachmentAssetId
                        attachment.name = r.getText("mpa_name")
                        attachment.mime_type = r.getText("mime_type")
                        attachment.kind = r.getText("kind").trimAscii().toAsciiLower()
                        attachment.language = r.getText("language").trimAscii().toAsciiLower()
                        attachment.order_index = Int32(r.getInt("mpa_order_index"))
                        attachment.created_at = r.getText("mpa_created_at")
                        attachment.updated_at = r.getText("mpa_updated_at")
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

    public static func upsertPageMetadataBatch(parentArchiveId: String, items: Array<PageMetadataData>, sourceNamespace!: String = ""): Bool {
        let normalizedParent = parentArchiveId.trimAscii()
        if (normalizedParent.size == 0) {
            return false
        }
        if (items.size == 0) {
            return true
        }

        return DatabaseConfig.withTransaction("metadata_dao", "upsertPageMetadataBatch failed", { =>
            for (item in items) {
                let safeEntryPath = normalizePageEntryPath(item.entry_path, item.page_number)
                let entityId = buildPageEntityId(normalizedParent, safeEntryPath)

                let selectRows = DatabaseConfig.driver().query("SELECT id FROM metadata_objects WHERE entity_type = 'page' AND parent_entity_type = 'archive' AND parent_entity_id = $1 AND entry_path = $2 LIMIT 1", [DbText(normalizedParent), DbText(safeEntryPath)])
                var metadataId: Int64 = 0
                if (selectRows.size > 0) {
                    metadataId = selectRows[0].getInt("id")
                }

                if (metadataId > 0) {
                    DatabaseConfig.driver().exec("""
                        UPDATE metadata_objects
                        SET entity_id = $1,
                            title = $2,
                            description = $3,
                            order_index = $4,
                            page_number = $5,
                            entry_path = $6,
                            extra_data = jsonb_set(
                                jsonb_set(COALESCE(CAST($7 AS JSONB), '{}'::jsonb), '{hidden_in_files}', to_jsonb(CAST($8 AS BOOLEAN)), true),
                                '{thumbhash}', to_jsonb(CAST($9 AS TEXT)), true
                            ),
                            release_at = COALESCE(CAST(NULLIF(TRIM(CAST($10 AS TEXT)), '') AS TIMESTAMP), release_at),
                            source_namespace = $11,
                            updated_at = COALESCE(CAST(NULLIF(TRIM(CAST($12 AS TEXT)), '') AS TIMESTAMP), CURRENT_TIMESTAMP)
                        WHERE id = $13
                    """, [
                        DbText(entityId),
                        DbText(item.title),
                        DbText(item.description),
                        DbInt(Int64(item.sort_index)),
                        DbInt(Int64(item.page_number)),
                        DbText(safeEntryPath),
                        DbText(item.extra_data),
                        DbBool(item.hidden_in_files),
                        DbText(item.thumbhash),
                        DbText(item.release_at),
                        DbText(sourceNamespace),
                        DbText(item.updated_at),
                        DbInt(metadataId)
                    ])
                } else {
                    DatabaseConfig.driver().exec("""
                        INSERT INTO metadata_objects (
                            entity_type, entity_id, parent_entity_type, parent_entity_id,
                            title, description, volume_no, order_index, page_number, entry_path,
                            extra_data, source_namespace, release_at, created_at, updated_at
                        ) VALUES (
                            'page', $1, 'archive', $2,
                            $3, $4, 0, $5, $6, $7,
                            jsonb_set(
                                jsonb_set(COALESCE(CAST($8 AS JSONB), '{}'::jsonb), '{hidden_in_files}', to_jsonb(CAST($9 AS BOOLEAN)), true),
                                '{thumbhash}', to_jsonb(CAST($10 AS TEXT)), true
                            ),
                            $11,
                            CAST(NULLIF(TRIM(CAST($12 AS TEXT)), '') AS TIMESTAMP),
                            COALESCE(CAST(NULLIF(TRIM(CAST($13 AS TEXT)), '') AS TIMESTAMP), CURRENT_TIMESTAMP),
                            COALESCE(CAST(NULLIF(TRIM(CAST($14 AS TEXT)), '') AS TIMESTAMP), CURRENT_TIMESTAMP)
                        )
                    """, [
                        DbText(entityId),
                        DbText(normalizedParent),
                        DbText(item.title),
                        DbText(item.description),
                        DbInt(Int64(item.sort_index)),
                        DbInt(Int64(item.page_number)),
                        DbText(safeEntryPath),
                        DbText(item.extra_data),
                        DbBool(item.hidden_in_files),
                        DbText(item.thumbhash),
                        DbText(sourceNamespace),
                        DbText(item.release_at),
                        DbText(item.created_at),
                        DbText(item.updated_at)
                    ])

                    let selectRows2 = DatabaseConfig.driver().query("SELECT id FROM metadata_objects WHERE entity_type = 'page' AND parent_entity_type = 'archive' AND parent_entity_id = $1 AND entry_path = $2 LIMIT 1", [DbText(normalizedParent), DbText(safeEntryPath)])
                    if (selectRows2.size > 0) {
                        metadataId = selectRows2[0].getInt("id")
                    }
                }

                if (metadataId <= 0) {
                    continue
                }

                if (item.thumb_asset_id > 0) {
                    let affected = DatabaseConfig.driver().exec("""
                        UPDATE metadata_assets
                        SET asset_id = $1, updated_at = CURRENT_TIMESTAMP
                        WHERE metadata_id = $2 AND slot = 'thumb'
                    """, [DbInt(item.thumb_asset_id), DbInt(metadataId)])
                    if (affected <= 0) {
                        DatabaseConfig.driver().exec("""
                            INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at)
                            SELECT $1, 'thumb', $2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                            WHERE NOT EXISTS (
                                SELECT 1 FROM metadata_assets WHERE metadata_id = $3 AND slot = 'thumb'
                            )
                        """, [DbInt(metadataId), DbInt(item.thumb_asset_id), DbInt(metadataId)])
                    }
                } else {
                    DatabaseConfig.driver().exec("DELETE FROM metadata_assets WHERE metadata_id = $1 AND slot = 'thumb'", [DbInt(metadataId)])
                }

                if (item.attachments_provided) {
                    DatabaseConfig.driver().exec("DELETE FROM metadata_page_assets WHERE metadata_id = $1", [DbInt(metadataId)])

                    for (attachment in item.attachments) {
                        let slot = attachment.slot.trimAscii().toAsciiLower()
                        let name = attachment.name.trimAscii()
                        if (slot.size == 0 || name.size == 0 || attachment.asset_id <= 0) {
                            continue
                        }
                        DatabaseConfig.driver().exec("""
                            INSERT INTO metadata_page_assets (
                                metadata_id, slot, asset_id, name, mime_type, kind, language, order_index, created_at, updated_at
                            ) VALUES (
                                $1, $2, $3, $4, $5, $6, $7, $8, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                            )
                        """, [
                            DbInt(metadataId),
                            DbText(slot),
                            DbInt(attachment.asset_id),
                            DbText(name),
                            DbText(attachment.mime_type.trimAscii()),
                            DbText(attachment.kind.trimAscii().toAsciiLower()),
                            DbText(attachment.language.trimAscii().toAsciiLower()),
                            DbInt(Int64(attachment.order_index))
                        ])
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
        return DatabaseConfig.withTransaction("metadata_dao", "deletePageMetadata failed", { =>
            DatabaseConfig.driver().exec("DELETE FROM metadata_assets WHERE metadata_id IN (SELECT id FROM metadata_objects WHERE entity_type = 'page' AND parent_entity_type = 'archive' AND parent_entity_id = $1)", [DbText(normalizedParent)])
            DatabaseConfig.driver().exec("DELETE FROM metadata_tags WHERE metadata_id IN (SELECT id FROM metadata_objects WHERE entity_type = 'page' AND parent_entity_type = 'archive' AND parent_entity_id = $1)", [DbText(normalizedParent)])
            DatabaseConfig.driver().exec("DELETE FROM metadata_objects WHERE entity_type = 'page' AND parent_entity_type = 'archive' AND parent_entity_id = $1", [DbText(normalizedParent)])
            return true
        })
    }

    public static func deleteEntity(entityType: String, entityId: String): Bool {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        if (normalizedType.size == 0 || normalizedId.size == 0) {
            return false
        }
        return DatabaseConfig.withTransaction("metadata_dao", "deleteEntity failed", { =>
            DatabaseConfig.driver().exec("DELETE FROM metadata_assets WHERE metadata_id IN (SELECT id FROM metadata_objects WHERE entity_type = $1 AND entity_id = $2)", [DbText(normalizedType), DbText(normalizedId)])
            DatabaseConfig.driver().exec("DELETE FROM metadata_tags WHERE metadata_id IN (SELECT id FROM metadata_objects WHERE entity_type = $1 AND entity_id = $2)", [DbText(normalizedType), DbText(normalizedId)])
            DatabaseConfig.driver().exec("DELETE FROM metadata_objects WHERE entity_type = $1 AND entity_id = $2", [DbText(normalizedType), DbText(normalizedId)])
            return true
        })
    }

    public static func getTankoubonChildren(tankoubonId: String): Array<MetadataChildData> {
        let normalizedId = tankoubonId.trimAscii()
        if (normalizedId.size == 0) {
            return Array<MetadataChildData>()
        }

        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT a.arcid, COALESCE(ta.sort_order, 0) AS sort_order
                FROM tankoubon_archives ta
                JOIN tankoubons t ON t.id = ta.tankoubon_id
                JOIN archives a ON a.id = ta.archive_id
                WHERE t.tankoubon_id = $1
                ORDER BY ta.sort_order, ta.id
            """, [DbText(normalizedId)])
            let out = ArrayList<MetadataChildData>()
            var idx: Int32 = 1
            for (r in rows) {
                let child = MetadataChildData()
                child.entity_id = r.getText("arcid")
                child.order_index = Int32(r.getInt("sort_order"))
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