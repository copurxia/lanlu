package lanlu.contexts.metadata.infrastructure.persistence

import std.collection.*
import std.database.sql.*
import std.io.ByteBuffer
import stdx.encoding.json.stream.*
import lanlu.shared.config.*
import lanlu.shared.utils.*

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
    public var created_at: String = ""
    public var updated_at: String = ""
    public var tags: Array<String> = Array<String>()
    public var assets: Array<MetadataAssetData> = Array<MetadataAssetData>()
}

public class MetadataChildData {
    public var entity_type: String = "archive"
    public var entity_id: String = ""
    public var volume_no: Int32 = 0
    public var order_index: Int32 = 0
}

public class MetadataDao {
    private static let logger = getLogger("metadata_dao")

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

    private static func mapMetadataObjectRow(rs: QueryResult): MetadataObjectData {
        let data = MetadataObjectData()
        data.id = rs.getOrNull<Int64>(0) ?? 0
        data.entity_type = rs.getOrNull<String>(1) ?? ""
        data.entity_id = rs.getOrNull<String>(2) ?? ""
        data.parent_entity_type = rs.getOrNull<String>(3) ?? ""
        data.parent_entity_id = rs.getOrNull<String>(4) ?? ""
        data.title = rs.getOrNull<String>(5) ?? ""
        data.description = rs.getOrNull<String>(6) ?? ""
        data.volume_no = rs.getOrNull<Int32>(7) ?? 0
        data.order_index = rs.getOrNull<Int32>(8) ?? 0
        data.page_number = rs.getOrNull<Int32>(9) ?? 0
        data.entry_path = rs.getOrNull<String>(10) ?? ""
        data.extra_data = rs.getOrNull<String>(11) ?? "{}"
        data.source_namespace = rs.getOrNull<String>(12) ?? ""
        data.created_at = rs.getOrNull<String>(13) ?? ""
        data.updated_at = rs.getOrNull<String>(14) ?? ""
        return data
    }

    private static func loadTags(conn: Connection, metadataId: Int64): Array<String> {
        if (metadataId <= 0) {
            return Array<String>()
        }
        let out = ArrayList<String>()
        let stmt = conn.prepareStatement("SELECT tag FROM metadata_tags WHERE metadata_id = ? ORDER BY tag")
        try {
            stmt.set(0, metadataId)
            let rs = stmt.query()
            try {
                while (rs.next()) {
                    let tag = (rs.getOrNull<String>(0) ?? "").trimAscii()
                    if (tag.size > 0) {
                        out.add(tag)
                    }
                }
            } finally {
                rs.close()
            }
        } finally {
            stmt.close()
        }
        return out.toArray()
    }

    private static func loadAssets(conn: Connection, metadataId: Int64): Array<MetadataAssetData> {
        if (metadataId <= 0) {
            return Array<MetadataAssetData>()
        }
        let out = ArrayList<MetadataAssetData>()
        let stmt = conn.prepareStatement("SELECT slot, asset_id FROM metadata_assets WHERE metadata_id = ? ORDER BY slot")
        try {
            stmt.set(0, metadataId)
            let rs = stmt.query()
            try {
                while (rs.next()) {
                    let slot = (rs.getOrNull<String>(0) ?? "").trimAscii().toAsciiLower()
                    let assetId = rs.getOrNull<Int64>(1) ?? 0
                    if (slot.size > 0 && assetId > 0) {
                        out.add(MetadataAssetData(slot, assetId))
                    }
                }
            } finally {
                rs.close()
            }
        } finally {
            stmt.close()
        }
        return out.toArray()
    }

    private static func getMetadataIdForRoot(conn: Connection, entityType: String, entityId: String): Int64 {
        let stmt = conn.prepareStatement("SELECT id FROM metadata_objects WHERE entity_type = ? AND entity_id = ? LIMIT 1")
        try {
            stmt.set(0, entityType)
            stmt.set(1, entityId)
            let rs = stmt.query()
            try {
                if (rs.next()) {
                    return rs.getOrNull<Int64>(0) ?? 0
                }
            } finally {
                rs.close()
            }
        } finally {
            stmt.close()
        }
        return 0
    }

    private static func getMetadataIdForPage(conn: Connection, parentArchiveId: String, entryPath: String): Int64 {
        let stmt = conn.prepareStatement("SELECT id FROM metadata_objects WHERE entity_type = 'page' AND parent_entity_type = 'archive' AND parent_entity_id = ? AND entry_path = ? LIMIT 1")
        try {
            stmt.set(0, parentArchiveId)
            stmt.set(1, entryPath)
            let rs = stmt.query()
            try {
                if (rs.next()) {
                    return rs.getOrNull<Int64>(0) ?? 0
                }
            } finally {
                rs.close()
            }
        } finally {
            stmt.close()
        }
        return 0
    }

    public static func getMetadataObject(entityType: String, entityId: String): Option<MetadataObjectData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return None
            case Some(conn) =>
                try {
                    var dataOpt: Option<MetadataObjectData> = None
                    let stmt = conn.prepareStatement("""
                        SELECT id, entity_type, entity_id, parent_entity_type, parent_entity_id,
                               COALESCE(title, ''), COALESCE(description, ''), COALESCE(volume_no, 0),
                               COALESCE(order_index, 0), COALESCE(page_number, 0), COALESCE(entry_path, ''),
                               COALESCE(CAST(extra_data AS TEXT), '{}'), COALESCE(source_namespace, ''),
                               COALESCE(created_at::TEXT, ''), COALESCE(updated_at::TEXT, '')
                        FROM metadata_objects
                        WHERE entity_type = ? AND entity_id = ?
                        LIMIT 1
                    """)
                    try {
                        stmt.set(0, entityType)
                        stmt.set(1, entityId)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                dataOpt = Some(mapMetadataObjectRow(rs))
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    match (dataOpt) {
                        case Some(data) =>
                            data.tags = loadTags(conn, data.id)
                            data.assets = loadAssets(conn, data.id)
                            return Some(data)
                        case None => return None
                    }
                } catch (_: Exception) {
                    return None
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }

    public static func upsertRootMetadataObject(
        entityType: String,
        entityId: String,
        title: String,
        description: String,
        sourceNamespace!: String = "",
        createdAt!: String = "",
        updatedAt!: String = ""
    ): Bool {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        if (normalizedId.size == 0 || (normalizedType != "archive" && normalizedType != "tankoubon")) {
            return false
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return false
            case Some(conn) =>
                try {
                    let existingId = getMetadataIdForRoot(conn, normalizedType, normalizedId)
                    if (existingId > 0) {
                        let stmt = conn.prepareStatement("""
                            UPDATE metadata_objects
                            SET title = ?,
                                description = ?,
                                source_namespace = ?,
                                updated_at = COALESCE(CAST(NULLIF(TRIM(CAST(? AS TEXT)), '') AS TIMESTAMP), CURRENT_TIMESTAMP)
                            WHERE id = ?
                        """)
                        try {
                            stmt.set(0, title)
                            stmt.set(1, description)
                            stmt.set(2, sourceNamespace)
                            stmt.set(3, updatedAt)
                            stmt.set(4, existingId)
                            stmt.update()
                            return true
                        } finally {
                            stmt.close()
                        }
                    }

                    let stmt = conn.prepareStatement("""
                        INSERT INTO metadata_objects (
                            entity_type, entity_id, parent_entity_type, parent_entity_id,
                            title, description, volume_no, order_index, page_number, entry_path,
                            extra_data, source_namespace, created_at, updated_at
                        ) VALUES (
                            ?, ?, '', '', ?, ?, 0, 0, 0, '',
                            '{}'::jsonb, ?,
                            COALESCE(CAST(NULLIF(TRIM(CAST(? AS TEXT)), '') AS TIMESTAMP), CURRENT_TIMESTAMP),
                            COALESCE(CAST(NULLIF(TRIM(CAST(? AS TEXT)), '') AS TIMESTAMP), CURRENT_TIMESTAMP)
                        )
                    """)
                    try {
                        stmt.set(0, normalizedType)
                        stmt.set(1, normalizedId)
                        stmt.set(2, title)
                        stmt.set(3, description)
                        stmt.set(4, sourceNamespace)
                        stmt.set(5, createdAt)
                        stmt.set(6, updatedAt)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("upsertRootMetadataObject failed", ("entityType", normalizedType), ("entityId", normalizedId), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }

    public static func replaceMetadataTags(entityType: String, entityId: String, tags: Array<String>): Bool {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        if (normalizedId.size == 0) {
            return false
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return false
            case Some(conn) =>
                try {
                    let metadataId = getMetadataIdForRoot(conn, normalizedType, normalizedId)
                    if (metadataId <= 0) {
                        return false
                    }

                    try {
                        let begin = conn.prepareStatement("BEGIN")
                        try { begin.update() } finally { begin.close() }
                    } catch (_: Exception) {}

                    let del = conn.prepareStatement("DELETE FROM metadata_tags WHERE metadata_id = ?")
                    try {
                        del.set(0, metadataId)
                        del.update()
                    } finally {
                        del.close()
                    }

                    let seen = HashSet<String>()
                    for (rawTag in tags) {
                        let tag = rawTag.trimAscii()
                        if (tag.size == 0 || seen.contains(tag)) {
                            continue
                        }
                        seen.add(tag)
                        let ins = conn.prepareStatement("INSERT INTO metadata_tags (metadata_id, tag) VALUES (?, ?) ON CONFLICT DO NOTHING")
                        try {
                            ins.set(0, metadataId)
                            ins.set(1, tag)
                            ins.update()
                        } finally {
                            ins.close()
                        }
                    }

                    try {
                        let commit = conn.prepareStatement("COMMIT")
                        try { commit.update() } finally { commit.close() }
                    } catch (_: Exception) {}
                    return true
                } catch (e: Exception) {
                    try {
                        let rb = conn.prepareStatement("ROLLBACK")
                        try { rb.update() } finally { rb.close() }
                    } catch (_: Exception) {}
                    logger.error("replaceMetadataTags failed", ("entityType", normalizedType), ("entityId", normalizedId), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }

    public static func replaceMetadataAssets(entityType: String, entityId: String, assets: Array<MetadataAssetData>): Bool {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        if (normalizedId.size == 0) {
            return false
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return false
            case Some(conn) =>
                try {
                    let metadataId = getMetadataIdForRoot(conn, normalizedType, normalizedId)
                    if (metadataId <= 0) {
                        return false
                    }

                    try {
                        let begin = conn.prepareStatement("BEGIN")
                        try { begin.update() } finally { begin.close() }
                    } catch (_: Exception) {}

                    let del = conn.prepareStatement("DELETE FROM metadata_assets WHERE metadata_id = ?")
                    try {
                        del.set(0, metadataId)
                        del.update()
                    } finally {
                        del.close()
                    }

                    let seen = HashSet<String>()
                    for (asset in assets) {
                        let slot = asset.slot.trimAscii().toAsciiLower()
                        if (slot.size == 0 || asset.asset_id <= 0 || seen.contains(slot)) {
                            continue
                        }
                        seen.add(slot)
                        let ins = conn.prepareStatement("INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at) VALUES (?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) ON CONFLICT (metadata_id, slot) DO UPDATE SET asset_id = EXCLUDED.asset_id, updated_at = CURRENT_TIMESTAMP")
                        try {
                            ins.set(0, metadataId)
                            ins.set(1, slot)
                            ins.set(2, asset.asset_id)
                            ins.update()
                        } finally {
                            ins.close()
                        }
                    }

                    try {
                        let commit = conn.prepareStatement("COMMIT")
                        try { commit.update() } finally { commit.close() }
                    } catch (_: Exception) {}
                    return true
                } catch (e: Exception) {
                    try {
                        let rb = conn.prepareStatement("ROLLBACK")
                        try { rb.update() } finally { rb.close() }
                    } catch (_: Exception) {}
                    logger.error("replaceMetadataAssets failed", ("entityType", normalizedType), ("entityId", normalizedId), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }

    public static func setMetadataAssetId(entityType: String, entityId: String, slot: String, assetId: Int64): Bool {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        let normalizedSlot = slot.trimAscii().toAsciiLower()
        if (normalizedId.size == 0 || normalizedSlot.size == 0) {
            return false
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return false
            case Some(conn) =>
                try {
                    let metadataId = getMetadataIdForRoot(conn, normalizedType, normalizedId)
                    if (metadataId <= 0) {
                        return false
                    }
                    if (assetId > 0) {
                        let stmt = conn.prepareStatement("INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at) VALUES (?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) ON CONFLICT (metadata_id, slot) DO UPDATE SET asset_id = EXCLUDED.asset_id, updated_at = CURRENT_TIMESTAMP")
                        try {
                            stmt.set(0, metadataId)
                            stmt.set(1, normalizedSlot)
                            stmt.set(2, assetId)
                            stmt.update()
                        } finally {
                            stmt.close()
                        }
                    } else {
                        let stmt = conn.prepareStatement("DELETE FROM metadata_assets WHERE metadata_id = ? AND slot = ?")
                        try {
                            stmt.set(0, metadataId)
                            stmt.set(1, normalizedSlot)
                            stmt.update()
                        } finally {
                            stmt.close()
                        }
                    }
                    return true
                } catch (e: Exception) {
                    logger.error("setMetadataAssetId failed", ("entityType", normalizedType), ("entityId", normalizedId), ("slot", normalizedSlot), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
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

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return 0
            case Some(conn) =>
                try {
                    let metadataId = getMetadataIdForRoot(conn, normalizedType, normalizedId)
                    if (metadataId <= 0) {
                        return 0
                    }
                    let stmt = conn.prepareStatement("SELECT asset_id FROM metadata_assets WHERE metadata_id = ? AND slot = ? LIMIT 1")
                    try {
                        stmt.set(0, metadataId)
                        stmt.set(1, normalizedSlot)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                return rs.getOrNull<Int64>(0) ?? 0
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return 0
                } catch (_: Exception) {
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }

    public static func listPageMetadata(parentArchiveId: String): Array<PageMetadataData> {
        let normalizedParent = parentArchiveId.trimAscii()
        if (normalizedParent.size == 0) {
            return Array<PageMetadataData>()
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return Array<PageMetadataData>()
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT mo.id,
                               COALESCE(mo.page_number, 0),
                               COALESCE(mo.entry_path, ''),
                               COALESCE(mo.title, ''),
                               COALESCE(mo.description, ''),
                               COALESCE(mo.order_index, 0),
                               COALESCE(ma.asset_id, 0),
                               COALESCE(CAST(mo.extra_data AS TEXT), '{}'),
                               COALESCE(mo.created_at::TEXT, ''),
                               COALESCE(mo.updated_at::TEXT, '')
                        FROM metadata_objects mo
                        LEFT JOIN metadata_assets ma ON ma.metadata_id = mo.id AND ma.slot = 'thumb'
                        WHERE mo.entity_type = 'page'
                          AND mo.parent_entity_type = 'archive'
                          AND mo.parent_entity_id = ?
                        ORDER BY mo.page_number, mo.id
                    """)
                    try {
                        stmt.set(0, normalizedParent)
                        let rs = stmt.query()
                        let out = ArrayList<PageMetadataData>()
                        try {
                            while (rs.next()) {
                                let item = PageMetadataData()
                                item.id = rs.getOrNull<Int64>(0) ?? 0
                                item.archive_id = 0
                                item.page_number = rs.getOrNull<Int32>(1) ?? 0
                                item.entry_path = rs.getOrNull<String>(2) ?? ""
                                item.title = rs.getOrNull<String>(3) ?? ""
                                item.description = rs.getOrNull<String>(4) ?? ""
                                item.sort_index = rs.getOrNull<Int32>(5) ?? 0
                                item.thumb_asset_id = rs.getOrNull<Int64>(6) ?? 0
                                item.extra_data = rs.getOrNull<String>(7) ?? "{}"
                                item.hidden_in_files = readExtraBool(item.extra_data, "hidden_in_files")
                                item.thumbhash = readExtraString(item.extra_data, "thumbhash")
                                item.created_at = rs.getOrNull<String>(8) ?? ""
                                item.updated_at = rs.getOrNull<String>(9) ?? ""
                                out.add(item)
                            }
                        } finally {
                            rs.close()
                        }
                        return out.toArray()
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("listPageMetadata failed", ("archiveId", normalizedParent), ("error", e.message))
                    return Array<PageMetadataData>()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
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

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return false
            case Some(conn) =>
                try {
                    try {
                        let begin = conn.prepareStatement("BEGIN")
                        try { begin.update() } finally { begin.close() }
                    } catch (_: Exception) {}

                    for (item in items) {
                        let safeEntryPath = normalizePageEntryPath(item.entry_path, item.page_number)
                        let entityId = buildPageEntityId(normalizedParent, safeEntryPath)
                        let existingId = getMetadataIdForPage(conn, normalizedParent, safeEntryPath)
                        if (existingId > 0) {
                            let stmt = conn.prepareStatement("""
                                UPDATE metadata_objects
                                SET entity_id = ?,
                                    title = ?,
                                    description = ?,
                                    order_index = ?,
                                    page_number = ?,
                                    entry_path = ?,
                                    extra_data = jsonb_set(
                                        jsonb_set(COALESCE(CAST(? AS JSONB), '{}'::jsonb), '{hidden_in_files}', to_jsonb(CAST(? AS BOOLEAN)), true),
                                        '{thumbhash}', to_jsonb(CAST(? AS TEXT)), true
                                    ),
                                    source_namespace = ?,
                                    updated_at = CURRENT_TIMESTAMP
                                WHERE id = ?
                            """)
                            try {
                                stmt.set(0, entityId)
                                stmt.set(1, item.title)
                                stmt.set(2, item.description)
                                stmt.set(3, item.sort_index)
                                stmt.set(4, item.page_number)
                                stmt.set(5, safeEntryPath)
                                stmt.set(6, item.extra_data)
                                stmt.set(7, item.hidden_in_files)
                                stmt.set(8, item.thumbhash)
                                stmt.set(9, sourceNamespace)
                                stmt.set(10, existingId)
                                stmt.update()
                            } finally {
                                stmt.close()
                            }
                        } else {
                            let stmt = conn.prepareStatement("""
                                INSERT INTO metadata_objects (
                                    entity_type, entity_id, parent_entity_type, parent_entity_id,
                                    title, description, volume_no, order_index, page_number, entry_path,
                                    extra_data, source_namespace, created_at, updated_at
                                ) VALUES (
                                    'page', ?, 'archive', ?,
                                    ?, ?, 0, ?, ?, ?,
                                    jsonb_set(
                                        jsonb_set(COALESCE(CAST(? AS JSONB), '{}'::jsonb), '{hidden_in_files}', to_jsonb(CAST(? AS BOOLEAN)), true),
                                        '{thumbhash}', to_jsonb(CAST(? AS TEXT)), true
                                    ),
                                    ?,
                                    COALESCE(CAST(NULLIF(TRIM(CAST(? AS TEXT)), '') AS TIMESTAMP), CURRENT_TIMESTAMP),
                                    COALESCE(CAST(NULLIF(TRIM(CAST(? AS TEXT)), '') AS TIMESTAMP), CURRENT_TIMESTAMP)
                                )
                            """)
                            try {
                                stmt.set(0, entityId)
                                stmt.set(1, normalizedParent)
                                stmt.set(2, item.title)
                                stmt.set(3, item.description)
                                stmt.set(4, item.sort_index)
                                stmt.set(5, item.page_number)
                                stmt.set(6, safeEntryPath)
                                stmt.set(7, item.extra_data)
                                stmt.set(8, item.hidden_in_files)
                                stmt.set(9, item.thumbhash)
                                stmt.set(10, sourceNamespace)
                                stmt.set(11, item.created_at)
                                stmt.set(12, item.updated_at)
                                stmt.update()
                            } finally {
                                stmt.close()
                            }
                        }

                        let metadataId = getMetadataIdForPage(conn, normalizedParent, safeEntryPath)
                        if (metadataId > 0) {
                            if (item.thumb_asset_id > 0) {
                                let upsertThumb = conn.prepareStatement("INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at) VALUES (?, 'thumb', ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) ON CONFLICT (metadata_id, slot) DO UPDATE SET asset_id = EXCLUDED.asset_id, updated_at = CURRENT_TIMESTAMP")
                                try {
                                    upsertThumb.set(0, metadataId)
                                    upsertThumb.set(1, item.thumb_asset_id)
                                    upsertThumb.update()
                                } finally {
                                    upsertThumb.close()
                                }
                            } else {
                                let deleteThumb = conn.prepareStatement("DELETE FROM metadata_assets WHERE metadata_id = ? AND slot = 'thumb'")
                                try {
                                    deleteThumb.set(0, metadataId)
                                    deleteThumb.update()
                                } finally {
                                    deleteThumb.close()
                                }
                            }
                        }
                    }

                    try {
                        let commit = conn.prepareStatement("COMMIT")
                        try { commit.update() } finally { commit.close() }
                    } catch (_: Exception) {}
                    return true
                } catch (e: Exception) {
                    try {
                        let rb = conn.prepareStatement("ROLLBACK")
                        try { rb.update() } finally { rb.close() }
                    } catch (_: Exception) {}
                    logger.error("upsertPageMetadataBatch failed", ("archiveId", normalizedParent), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
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

    public static func deletePageMetadata(parentArchiveId: String): Bool {
        let normalizedParent = parentArchiveId.trimAscii()
        if (normalizedParent.size == 0) {
            return false
        }
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return false
            case Some(conn) =>
                try {
                    try {
                        let begin = conn.prepareStatement("BEGIN")
                        try { begin.update() } finally { begin.close() }
                    } catch (_: Exception) {}

                    let deleteAssets = conn.prepareStatement("DELETE FROM metadata_assets WHERE metadata_id IN (SELECT id FROM metadata_objects WHERE entity_type = 'page' AND parent_entity_type = 'archive' AND parent_entity_id = ?)")
                    try {
                        deleteAssets.set(0, normalizedParent)
                        deleteAssets.update()
                    } finally {
                        deleteAssets.close()
                    }

                    let deleteTags = conn.prepareStatement("DELETE FROM metadata_tags WHERE metadata_id IN (SELECT id FROM metadata_objects WHERE entity_type = 'page' AND parent_entity_type = 'archive' AND parent_entity_id = ?)")
                    try {
                        deleteTags.set(0, normalizedParent)
                        deleteTags.update()
                    } finally {
                        deleteTags.close()
                    }

                    let deleteRows = conn.prepareStatement("DELETE FROM metadata_objects WHERE entity_type = 'page' AND parent_entity_type = 'archive' AND parent_entity_id = ?")
                    try {
                        deleteRows.set(0, normalizedParent)
                        deleteRows.update()
                    } finally {
                        deleteRows.close()
                    }

                    try {
                        let commit = conn.prepareStatement("COMMIT")
                        try { commit.update() } finally { commit.close() }
                    } catch (_: Exception) {}
                    return true
                } catch (e: Exception) {
                    try {
                        let rb = conn.prepareStatement("ROLLBACK")
                        try { rb.update() } finally { rb.close() }
                    } catch (_: Exception) {}
                    logger.error("deletePageMetadata failed", ("archiveId", normalizedParent), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }

    public static func deleteEntity(entityType: String, entityId: String): Bool {
        let normalizedType = entityType.trimAscii().toAsciiLower()
        let normalizedId = entityId.trimAscii()
        if (normalizedType.size == 0 || normalizedId.size == 0) {
            return false
        }
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return false
            case Some(conn) =>
                try {
                    try {
                        let begin = conn.prepareStatement("BEGIN")
                        try { begin.update() } finally { begin.close() }
                    } catch (_: Exception) {}

                    let deleteAssets = conn.prepareStatement("DELETE FROM metadata_assets WHERE metadata_id IN (SELECT id FROM metadata_objects WHERE entity_type = ? AND entity_id = ?)")
                    try {
                        deleteAssets.set(0, normalizedType)
                        deleteAssets.set(1, normalizedId)
                        deleteAssets.update()
                    } finally {
                        deleteAssets.close()
                    }

                    let deleteTags = conn.prepareStatement("DELETE FROM metadata_tags WHERE metadata_id IN (SELECT id FROM metadata_objects WHERE entity_type = ? AND entity_id = ?)")
                    try {
                        deleteTags.set(0, normalizedType)
                        deleteTags.set(1, normalizedId)
                        deleteTags.update()
                    } finally {
                        deleteTags.close()
                    }

                    let deleteRows = conn.prepareStatement("DELETE FROM metadata_objects WHERE entity_type = ? AND entity_id = ?")
                    try {
                        deleteRows.set(0, normalizedType)
                        deleteRows.set(1, normalizedId)
                        deleteRows.update()
                    } finally {
                        deleteRows.close()
                    }

                    try {
                        let commit = conn.prepareStatement("COMMIT")
                        try { commit.update() } finally { commit.close() }
                    } catch (_: Exception) {}
                    return true
                } catch (e: Exception) {
                    try {
                        let rb = conn.prepareStatement("ROLLBACK")
                        try { rb.update() } finally { rb.close() }
                    } catch (_: Exception) {}
                    logger.error("deleteEntity failed", ("entityType", normalizedType), ("entityId", normalizedId), ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }

    public static func getTankoubonChildren(tankoubonId: String): Array<MetadataChildData> {
        let normalizedId = tankoubonId.trimAscii()
        if (normalizedId.size == 0) {
            return Array<MetadataChildData>()
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return Array<MetadataChildData>()
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT a.arcid, COALESCE(ta.sort_order, 0)
                        FROM tankoubon_archives ta
                        JOIN tankoubons t ON t.id = ta.tankoubon_id
                        JOIN archives a ON a.id = ta.archive_id
                        WHERE t.tankoubon_id = ?
                        ORDER BY ta.sort_order, ta.id
                    """)
                    try {
                        stmt.set(0, normalizedId)
                        let rs = stmt.query()
                        let out = ArrayList<MetadataChildData>()
                        var idx: Int32 = 1
                        try {
                            while (rs.next()) {
                                let child = MetadataChildData()
                                child.entity_id = rs.getOrNull<String>(0) ?? ""
                                child.order_index = rs.getOrNull<Int32>(1) ?? idx
                                child.volume_no = idx
                                if (child.entity_id.trimAscii().size > 0) {
                                    out.add(child)
                                    idx += 1
                                }
                            }
                        } finally {
                            rs.close()
                        }
                        return out.toArray()
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("getTankoubonChildren failed", ("tankoubonId", normalizedId), ("error", e.message))
                    return Array<MetadataChildData>()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }
}
