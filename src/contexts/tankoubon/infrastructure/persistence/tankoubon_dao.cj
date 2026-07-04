package lanlu.contexts.tankoubon.infrastructure.persistence

import ace_orm.*
import lanlu.shared.config.*
import std.collection.*
import std.io.{ByteBuffer, readToEnd}
import stdx.log.*
import stdx.encoding.json.stream.*
import std.time.*
import lanlu.infrastructure.kv.*
import lanlu.contexts.tag.infrastructure.persistence.*
import lanlu.shared.utils.*
import lanlu.contexts.metadata.infrastructure.persistence.*

/**
 * Tankoubon数据结构
 * 为了避免循环依赖，这个数据结构独立于 Tankoubon 模型类
 */
public class TankoubonData {
    public var id: Int64 = 0
    public var tankoubon_id: String = ""
    public var name: String = ""
    public var summary: String = ""
    public var cover_asset_id: Int64 = 0
    public var assets_raw: String = "{}"
    public var auto_created: Bool = false
    public var source_category_id: Int64 = 0
    public var source_relative_path: String = ""
    public var release_at: String = ""
    public var created_at: String = ""
    public var updated_at: String = ""
    public var archives: Array<String> = Array<String>()  // Array of archive arcids
}

/**
 * Tankoubon聚合数据结构（用于搜索结果）
 */
public class TankoubonAggregatedData {
    public var tankoubon_id: String = ""
    public var name: String = ""
    public var summary: String = ""
    public var release_at: String = ""
    public var created_at: String = ""
    public var updated_at: String = ""
    public var cover_asset_id: Int64 = 0
    public var assets_raw: String = "{}"
    public var tags: String = ""  // 合并的标签：tankoubon tags + 所有 archive tags
    public var pagecount: Int32 = 0  // 所有归档的页数总和
    public var progress: Int32 = 0  // 所有归档的平均进度
    public var last_read_time: String = ""  // 最新的阅读时间
    public var isnew: Bool = true  // 如果任何归档是新的，则为true
    public var archive_count: Int32 = 0  // 归档数量
}

private class TankoubonAggregatedDataCacheCodec {
    public static func encode(data: TankoubonAggregatedData): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("tankoubon_id").writeValue(data.tankoubon_id)
        w.writeName("name").writeValue(data.name)
        w.writeName("summary").writeValue(data.summary)
        w.writeName("release_at").writeValue(data.release_at)
        w.writeName("created_at").writeValue(data.created_at)
        w.writeName("updated_at").writeValue(data.updated_at)
        w.writeName("cover_asset_id").writeValue(data.cover_asset_id)
        w.writeName("assets_raw").writeValue(data.assets_raw)
        w.writeName("tags").writeValue(data.tags)
        w.writeName("pagecount").writeValue(data.pagecount)
        w.writeName("progress").writeValue(data.progress)
        w.writeName("last_read_time").writeValue(data.last_read_time)
        w.writeName("isnew").writeValue(data.isnew)
        w.writeName("archive_count").writeValue(data.archive_count)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    public static func decode(payload: String): Option<TankoubonAggregatedData> {
        let trimmed = payload.trimAscii()
        if (trimmed.size == 0) {
            return None
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let reader = JsonReader(buf)
            if (reader.peek() != Some(BeginObject)) {
                return None
            }

            let data = TankoubonAggregatedData()
            reader.startObject()
            while (reader.peek() != EndObject) {
                let name = reader.readName()
                match (name) {
                    case "tankoubon_id" => data.tankoubon_id = reader.readValue<String>()
                    case "name" => data.name = reader.readValue<String>()
                    case "summary" => data.summary = reader.readValue<String>()
                    case "release_at" => data.release_at = reader.readValue<String>()
                    case "created_at" => data.created_at = reader.readValue<String>()
                    case "updated_at" => data.updated_at = reader.readValue<String>()
                    case "cover_asset_id" => data.cover_asset_id = reader.readValue<Int64>()
                    case "assets_raw" => data.assets_raw = reader.readValue<String>()
                    case "tags" => data.tags = reader.readValue<String>()
                    case "pagecount" => data.pagecount = reader.readValue<Int32>()
                    case "progress" => data.progress = reader.readValue<Int32>()
                    case "last_read_time" => data.last_read_time = reader.readValue<String>()
                    case "isnew" => data.isnew = reader.readValue<Bool>()
                    case "archive_count" => data.archive_count = reader.readValue<Int32>()
                    case _ => reader.skip()
                }
            }
            reader.endObject()
            if (data.assets_raw.trimAscii().size == 0) {
                data.assets_raw = "{}"
            }
            return Some(data)
        } catch (_: Exception) {
            return None
        }
    }
}

private class StringArrayCacheCodec {
    public static func encode(items: Array<String>): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startArray()
        for (item in items) {
            w.writeValue(item)
        }
        w.endArray()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    public static func decode(payload: String): Option<Array<String>> {
        let trimmed = payload.trimAscii()
        if (trimmed.size == 0) {
            return None
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(trimmed.rawData()) }
            let reader = JsonReader(buf)
            if (reader.peek() != Some(BeginArray)) {
                return None
            }

            let items = ArrayList<String>()
            reader.startArray()
            while (reader.peek() != EndArray) {
                items.add(reader.readValue<String>())
            }
            reader.endArray()
            return Some(items.toArray())
        } catch (_: Exception) {
            return None
        }
    }
}

/**
 * Tankoubon数据访问对象 (DAO)
 * 负责处理所有与Tankoubon相关的数据库操作
 */
public class TankoubonDao {
    private static let logger = getLogger("tankoubon_dao")
    private static let aggregatedMetadataCacheTtlSeconds: Int64 = 7 * 24 * 60 * 60
    private static let childrenCacheTtlSeconds: Int64 = 7 * 24 * 60 * 60

    private static func normalizeUniqueIds(ids: Array<String>): Array<String> {
        return DerivedCacheUtils.normalizeUniqueIds(ids)
    }

    private static func buildAggregatedMetadataCacheKey(contentVersion: Int64, userVersion: Int64, userId: Int64, tankoubonId: String): String {
        return "cv${contentVersion.toString()}:uv${userVersion.toString()}:u${userId.toString()}:t${tankoubonId}"
    }

    private static func buildChildrenCacheKey(version: Int64, tankoubonId: String): String {
        return "v${version.toString()}:t${tankoubonId}"
    }

    private static func readAggregatedMetadataCache(cacheKey: String): Option<TankoubonAggregatedData> {
        let cacheNamespace = DerivedCacheUtils.getTankoubonAggregatedPayloadNamespace()
        match (PersistentCacheService.get(cacheNamespace, cacheKey)) {
            case Some(payload) =>
                match (TankoubonAggregatedDataCacheCodec.decode(payload)) {
                    case Some(data) => return Some(data)
                    case None =>
                        let _ = PersistentCacheService.delete(cacheNamespace, cacheKey)
                        logger.warn("tankoubon aggregated metadata cache payload decode failed; evicted key", ("key", cacheKey))
                        return None
                }
            case None => return None
        }
    }

    private static func writeAggregatedMetadataCache(cacheKey: String, data: TankoubonAggregatedData): Unit {
        let cacheNamespace = DerivedCacheUtils.getTankoubonAggregatedPayloadNamespace()
        let _ = PersistentCacheService.set(
            cacheNamespace,
            cacheKey,
            TankoubonAggregatedDataCacheCodec.encode(data),
            aggregatedMetadataCacheTtlSeconds
        )
    }

    private static func readChildrenCache(cacheKey: String): Option<Array<String>> {
        let cacheNamespace = DerivedCacheUtils.getTankoubonChildrenPayloadNamespace()
        match (PersistentCacheService.get(cacheNamespace, cacheKey)) {
            case Some(payload) =>
                match (StringArrayCacheCodec.decode(payload)) {
                    case Some(items) => return Some(items)
                    case None =>
                        let _ = PersistentCacheService.delete(cacheNamespace, cacheKey)
                        logger.warn("tankoubon children cache payload decode failed; evicted key", ("key", cacheKey))
                        return None
                }
            case None => return None
        }
    }

    private static func writeChildrenCache(cacheKey: String, items: Array<String>): Unit {
        let cacheNamespace = DerivedCacheUtils.getTankoubonChildrenPayloadNamespace()
        let _ = PersistentCacheService.set(
            cacheNamespace,
            cacheKey,
            StringArrayCacheCodec.encode(items),
            childrenCacheTtlSeconds
        )
    }

    private static func invalidateTankoubonAggregatedContent(reason: String): Unit {
        let _ = DerivedCacheUtils.bumpTankoubonAggregatedContentVersion(reason)
    }

    private static func invalidateTankoubonChildren(reason: String): Unit {
        let _ = DerivedCacheUtils.bumpTankoubonChildrenVersion(reason)
    }

    /**
     * 解析 namespace:name 格式标签；无命名空间时 namespace 为空字符串。
     */
    private static func parseTagName(fullName: String): (String, String) {
        let parts = fullName.split(":", 2)
        if (parts.size >= 2) {
            return (parts[0], parts[1])
        }
        return ("", fullName)
    }

    /**
     * 判断是否 source 标签（source:xxx）。
     */
    private static func isSourceTag(fullName: String): Bool {
        let trimmed = fullName.trimAscii()
        if (trimmed.size == 0) { return false }
        if (trimmed.startsWith("source:")) { return true }
        let (namespace, _) = parseTagName(trimmed)
        return namespace == "source"
    }

    private static func ensureTankoubonMetadataRoot(tankoubonId: String): Bool {
        let normalized = tankoubonId.trimAscii()
        if (normalized.size == 0) { return false }
        match (MetadataDao.getMetadataObject("tankoubon", normalized)) {
            case Some(_) => return true
            case None => return MetadataDao.upsertRootMetadataObject("tankoubon", normalized, "", "")
        }
    }

    private static func touchTankoubonUpdatedAt(tankoubonId: String): Bool {
        let normalized = tankoubonId.trimAscii()
        if (normalized.size == 0) { return false }
        return MetadataDao.touchRootMetadataObject("tankoubon", normalized)
    }

    private static func getArchivesInTankoubonWithConnection(tankoubonId: String): Array<String> {
        var arcids: ArrayList<String> = ArrayList<String>()
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT a.arcid
                FROM tankoubon_archives ta
                JOIN tankoubons t ON t.id = ta.tankoubon_id
                JOIN archives a ON a.id = ta.archive_id
                WHERE t.tankoubon_id = $1
                ORDER BY ta.sort_order, ta.id
            """, [DbText(tankoubonId)])
            for (r in rows) {
                let arcid = r.getText("arcid")
                if (arcid != "") {
                    arcids.add(arcid)
                }
            }
        } catch (_: Exception) {}
        return arcids.toArray()
    }

    /**
     * 获取所有Tankoubons
     */
    public static func getAllTankoubons(): Array<TankoubonData> {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT
                    t.id AS t_id,
                    t.tankoubon_id AS tankoubon_id,
                    COALESCE(mo.title, '') AS name,
                    COALESCE(mo.description, '') AS summary,
                    COALESCE(asset_map.cover_asset_id, 0) AS cover_asset_id,
                    COALESCE(CAST(asset_map.assets_json AS TEXT), '{}') AS assets_raw,
                    COALESCE(t.auto_created, false) AS auto_created,
                    COALESCE(t.source_category_id, 0) AS source_category_id,
                    COALESCE(t.source_relative_path, '') AS source_relative_path,
                    COALESCE(mo.release_at::TEXT, '') AS release_at,
                    COALESCE(mo.created_at::TEXT, '') AS created_at,
                    COALESCE(mo.updated_at::TEXT, '') AS updated_at
                FROM tankoubons t
                LEFT JOIN metadata_objects mo
                       ON mo.entity_type = 'tankoubon'
                      AND mo.entity_id = t.tankoubon_id
                LEFT JOIN LATERAL (
                    SELECT
                        COALESCE(
                            jsonb_object_agg(ma.slot, to_jsonb(ma.asset_id))
                                FILTER (WHERE ma.asset_id > 0),
                            '{}'::jsonb
                        ) AS assets_json,
                        COALESCE(MAX(CASE WHEN ma.slot = 'cover' THEN ma.asset_id ELSE 0 END), 0) AS cover_asset_id
                    FROM metadata_assets ma
                    WHERE ma.metadata_id = mo.id
                ) asset_map ON true
                ORDER BY t.id
            """, [])
            let tankoubons = ArrayList<TankoubonData>()
            for (r in rows) {
                let tankoubon = TankoubonData()
                tankoubon.id = r.getInt("t_id")
                tankoubon.tankoubon_id = r.getText("tankoubon_id")
                tankoubon.name = r.getText("name")
                tankoubon.summary = r.getText("summary")
                tankoubon.cover_asset_id = r.getInt("cover_asset_id")
                tankoubon.assets_raw = r.getText("assets_raw").trimAscii()
                if (tankoubon.assets_raw.size == 0) { tankoubon.assets_raw = "{}" }
                tankoubon.auto_created = r.getBool("auto_created")
                tankoubon.source_category_id = r.getInt("source_category_id")
                tankoubon.source_relative_path = r.getText("source_relative_path")
                tankoubon.release_at = r.getText("release_at")
                tankoubon.created_at = r.getText("created_at")
                tankoubon.updated_at = r.getText("updated_at")
                tankoubons.add(tankoubon)
            }
            for (tankoubon in tankoubons) {
                tankoubon.archives = getArchivesInTankoubonWithConnection(tankoubon.tankoubon_id)
            }
            return tankoubons.toArray()
        } catch (e: Exception) {
            logger.error("查询Tankoubon失败", ("error", e.message))
            return Array<TankoubonData>()
        }
    }

    /**
     * 根据tankoubon_id获取Tankoubon
     */
    public static func getTankoubonById(tankoubonId: String): Option<TankoubonData> {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT
                    t.id AS t_id,
                    t.tankoubon_id AS tankoubon_id,
                    COALESCE(mo.title, '') AS name,
                    COALESCE(mo.description, '') AS summary,
                    COALESCE(asset_map.cover_asset_id, 0) AS cover_asset_id,
                    COALESCE(CAST(asset_map.assets_json AS TEXT), '{}') AS assets_raw,
                    COALESCE(t.auto_created, false) AS auto_created,
                    COALESCE(t.source_category_id, 0) AS source_category_id,
                    COALESCE(t.source_relative_path, '') AS source_relative_path,
                    COALESCE(mo.release_at::TEXT, '') AS release_at,
                    COALESCE(mo.created_at::TEXT, '') AS created_at,
                    COALESCE(mo.updated_at::TEXT, '') AS updated_at
                FROM tankoubons t
                LEFT JOIN metadata_objects mo
                       ON mo.entity_type = 'tankoubon'
                      AND mo.entity_id = t.tankoubon_id
                LEFT JOIN LATERAL (
                    SELECT
                        COALESCE(
                            jsonb_object_agg(ma.slot, to_jsonb(ma.asset_id))
                                FILTER (WHERE ma.asset_id > 0),
                            '{}'::jsonb
                        ) AS assets_json,
                        COALESCE(MAX(CASE WHEN ma.slot = 'cover' THEN ma.asset_id ELSE 0 END), 0) AS cover_asset_id
                    FROM metadata_assets ma
                    WHERE ma.metadata_id = mo.id
                ) asset_map ON true
                WHERE t.tankoubon_id = $1
            """, [DbText(tankoubonId)])
            if (rows.size == 0) {
                return None
            }
            let r = rows[0]
            let tankoubon = TankoubonData()
            tankoubon.id = r.getInt("t_id")
            tankoubon.tankoubon_id = r.getText("tankoubon_id")
            tankoubon.name = r.getText("name")
            tankoubon.summary = r.getText("summary")
            tankoubon.cover_asset_id = r.getInt("cover_asset_id")
            tankoubon.assets_raw = r.getText("assets_raw").trimAscii()
            if (tankoubon.assets_raw.size == 0) { tankoubon.assets_raw = "{}" }
            tankoubon.auto_created = r.getBool("auto_created")
            tankoubon.source_category_id = r.getInt("source_category_id")
            tankoubon.source_relative_path = r.getText("source_relative_path")
            tankoubon.release_at = r.getText("release_at")
            tankoubon.created_at = r.getText("created_at")
            tankoubon.updated_at = r.getText("updated_at")
            tankoubon.archives = getArchivesInTankoubonWithConnection(tankoubonId)
            return Some(tankoubon)
        } catch (e: Exception) {
            logger.error("查询Tankoubon失败", ("tankoubonId", tankoubonId), ("error", e.message))
            return None
        }
    }

    /**
     * 获取Tankoubon的档案数量和总页数
     */
    public static func getTankoubonArchiveStats(tankoubonId: String): (Int32, Int32) {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT COUNT(a.id) AS archive_count, COALESCE(SUM(a.pagecount), 0) AS total_pages
                FROM tankoubon_archives ta
                JOIN tankoubons t ON t.id = ta.tankoubon_id
                JOIN archives a ON a.id = ta.archive_id
                WHERE t.tankoubon_id = $1
                GROUP BY t.id
            """, [DbText(tankoubonId)])
            if (rows.size > 0) {
                let archiveCount = Int32(rows[0].getInt("archive_count"))
                let totalPages = Int32(rows[0].getInt("total_pages"))
                return (archiveCount, totalPages)
            }
        } catch (e: Exception) {
            logger.error("获取Tankoubon档案统计失败", ("tankoubonId", tankoubonId), ("error", e.message))
        }
        return (0, 0)
    }

    /**
     * 创建新的Tankoubon
     * 返回生成的tankoubon_id
     */
    public static func createTankoubon(name: String): String {
        try {
            // 生成tankoubon_id: TANK_ + 时间戳（毫秒，避免并发冲突）
            let timestamp = DateTime.now().toUnixTimeStamp().toMilliseconds().toString()
            let tankoubonId = "TANK_${timestamp}"

            DatabaseConfig.driver().exec("INSERT INTO tankoubons (tankoubon_id) VALUES ($1)", [DbText(tankoubonId)])
            if (!MetadataDao.upsertRootMetadataObject("tankoubon", tankoubonId, name, "")) {
                logger.error("创建Tankoubon metadata失败", ("tankoubonId", tankoubonId))
                return ""
            }
            invalidateTankoubonAggregatedContent("createTankoubon:${tankoubonId}")
            logger.info("创建Tankoubon成功", ("tankoubonId", tankoubonId), ("name", name))
            return tankoubonId
        } catch (e: Exception) {
            logger.error("创建Tankoubon失败", ("name", name), ("error", e.message))
            return ""
        }
    }

    /**
     * Find a Tankoubon by its canonical metadata title.
     */
    public static func findTankoubonByExactTitle(title: String): String {
        let normalizedTitle = title.trimAscii()
        if (normalizedTitle.size == 0) { return "" }

        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT t.tankoubon_id
                FROM tankoubons t
                JOIN metadata_objects mo
                  ON mo.entity_type = 'tankoubon'
                 AND mo.entity_id = t.tankoubon_id
                WHERE LOWER(TRIM(COALESCE(mo.title, ''))) = LOWER(TRIM($1))
                ORDER BY t.id
                LIMIT 1
            """, [DbText(normalizedTitle)])
            if (rows.size > 0) {
                return rows[0].getText("tankoubon_id")
            }
            return ""
        } catch (e: Exception) {
            logger.error("按标题查找Tankoubon失败", ("title", normalizedTitle), ("error", e.message))
            return ""
        }
    }

    /**
     * 更新Tankoubon元数据
     */
    public static func updateTankoubon(tankoubonId: String, name: String, summary: String): Bool {
        if (!MetadataDao.upsertRootMetadataObject("tankoubon", tankoubonId, name, summary)) {
            logger.error("更新Tankoubon metadata失败", ("tankoubonId", tankoubonId))
            return false
        }
        invalidateTankoubonAggregatedContent("updateTankoubon:${tankoubonId}")
        logger.info("更新Tankoubon成功", ("tankoubonId", tankoubonId))
        return true
    }

    /**
     * 删除Tankoubon
     */
    public static func deleteTankoubon(tankoubonId: String): Bool {
        try {
            DatabaseConfig.driver().exec("DELETE FROM tankoubons WHERE tankoubon_id = $1", [DbText(tankoubonId)])
            invalidateTankoubonAggregatedContent("deleteTankoubon:${tankoubonId}")
            invalidateTankoubonChildren("deleteTankoubon:${tankoubonId}")
            logger.info("删除Tankoubon成功", ("tankoubonId", tankoubonId))
            return true
        } catch (e: Exception) {
            logger.error("删除Tankoubon失败", ("tankoubonId", tankoubonId), ("error", e.message))
            return false
        }
    }

    /**
     * 添加归档到Tankoubon
     */
    public static func addArchiveToTankoubon(tankoubonId: String, archiveArcid: String, sortOrder: Int32): Bool {
        try {
            // 首先获取tankoubon的内部ID和archive的内部ID
            let tankoubonInternalId = getTankoubonInternalId(tankoubonId)
            let archiveInternalId = getArchiveInternalId(archiveArcid)

            if (tankoubonInternalId == 0 || archiveInternalId == 0) {
                logger.error("Tankoubon或Archive不存在",
                    ("tankoubonId", tankoubonId), ("archiveArcid", archiveArcid))
                return false
            }

            let affected = DatabaseConfig.driver().exec("""
                UPDATE tankoubon_archives
                SET sort_order = $1
                WHERE tankoubon_id = $2 AND archive_id = $3
            """, [DbInt(Int64(sortOrder)), DbInt(tankoubonInternalId), DbInt(archiveInternalId)])
            if (affected <= 0) {
                DatabaseConfig.driver().exec("""
                    INSERT INTO tankoubon_archives (tankoubon_id, archive_id, sort_order)
                    SELECT $1, $2, $3
                    WHERE NOT EXISTS (
                        SELECT 1 FROM tankoubon_archives WHERE tankoubon_id = $4 AND archive_id = $5
                    )
                """, [DbInt(tankoubonInternalId), DbInt(archiveInternalId), DbInt(Int64(sortOrder)), DbInt(tankoubonInternalId), DbInt(archiveInternalId)])
            }
            invalidateTankoubonAggregatedContent("addArchiveToTankoubon:${tankoubonId}")
            invalidateTankoubonChildren("addArchiveToTankoubon:${tankoubonId}")
            logger.info("添加归档到Tankoubon成功",
                ("tankoubonId", tankoubonId), ("archiveArcid", archiveArcid))
            return true
        } catch (e: Exception) {
            logger.error("添加归档到Tankoubon失败",
                ("tankoubonId", tankoubonId), ("archiveArcid", archiveArcid), ("error", e.message))
            return false
        }
    }

    /**
     * 从Tankoubon移除归档
     */
    public static func removeArchiveFromTankoubon(tankoubonId: String, archiveArcid: String): Bool {
        try {
            // 获取内部ID
            let tankoubonInternalId = getTankoubonInternalId(tankoubonId)
            let archiveInternalId = getArchiveInternalId(archiveArcid)

            if (tankoubonInternalId == 0 || archiveInternalId == 0) {
                return false
            }

            DatabaseConfig.driver().exec("DELETE FROM tankoubon_archives WHERE tankoubon_id = $1 AND archive_id = $2", [DbInt(tankoubonInternalId), DbInt(archiveInternalId)])
            invalidateTankoubonAggregatedContent("removeArchiveFromTankoubon:${tankoubonId}")
            invalidateTankoubonChildren("removeArchiveFromTankoubon:${tankoubonId}")
            logger.info("从Tankoubon移除归档成功",
                ("tankoubonId", tankoubonId), ("archiveArcid", archiveArcid))
            return true
        } catch (e: Exception) {
            logger.error("从Tankoubon移除归档失败",
                ("tankoubonId", tankoubonId), ("archiveArcid", archiveArcid), ("error", e.message))
            return false
        }
    }

    /**
     * 添加归档到 Tankoubon（追加到末尾，不改变已有顺序）
     */
    public static func addArchiveToTankoubonAppend(tankoubonId: String, archiveArcid: String): Bool {
        try {
            let tankInternalId = getTankoubonInternalId(tankoubonId)
            let archiveInternalId = getArchiveInternalId(archiveArcid)
            if (tankInternalId == 0 || archiveInternalId == 0) {
                return false
            }

            // Compute next sort order.
            var nextOrder: Int32 = 0
            let maxRows = DatabaseConfig.driver().query("SELECT COALESCE(MAX(sort_order), 0)::INT AS max_order FROM tankoubon_archives WHERE tankoubon_id = $1", [DbInt(tankInternalId)])
            if (maxRows.size > 0) {
                nextOrder = Int32(maxRows[0].getInt("max_order")) + 1
            } else {
                nextOrder = 1
            }

            DatabaseConfig.driver().exec("""
                INSERT INTO tankoubon_archives (tankoubon_id, archive_id, sort_order)
                SELECT $1, $2, $3
                WHERE NOT EXISTS (
                    SELECT 1 FROM tankoubon_archives WHERE tankoubon_id = $4 AND archive_id = $5
                )
            """, [DbInt(tankInternalId), DbInt(archiveInternalId), DbInt(Int64(nextOrder)), DbInt(tankInternalId), DbInt(archiveInternalId)])
            invalidateTankoubonAggregatedContent("addArchiveToTankoubonAppend:${tankoubonId}")
            invalidateTankoubonChildren("addArchiveToTankoubonAppend:${tankoubonId}")
            return true
        } catch (e: Exception) {
            logger.error("append archive to tank failed",
                ("tankoubonId", tankoubonId), ("archiveArcid", archiveArcid), ("error", e.message))
            return false
        }
    }

    /**
     * Get or create an auto-created Tankoubon for a directory source mapping.
     * Returns tankoubons.tankoubon_id.
     */
    public static func getOrCreateAutoTankoubon(categoryInternalId: Int64, sourceRelativePath: String, name: String): String {
        if (categoryInternalId <= 0) { return "" }
        let rel = sourceRelativePath.trimAscii()
        if (rel.size == 0) { return "" }

        try {
            // Try to find existing.
            let selRows = DatabaseConfig.driver().query("""
                SELECT tankoubon_id
                FROM tankoubons
                WHERE auto_created = true AND source_category_id = $1 AND COALESCE(source_relative_path, '') = $2
                LIMIT 1
            """, [DbInt(categoryInternalId), DbText(rel)])
            if (selRows.size > 0) {
                let tid = selRows[0].getText("tankoubon_id")
                if (tid.size > 0) { return tid }
            }

            // Create new.
            let timestamp = DateTime.now().toUnixTimeStamp().toMilliseconds().toString()
            let tid = "TANK_${timestamp}"

            DatabaseConfig.driver().exec("""
                INSERT INTO tankoubons (tankoubon_id, auto_created, source_category_id, source_relative_path)
                VALUES ($1, true, $2, $3)
            """, [DbText(tid), DbInt(categoryInternalId), DbText(rel)])
            if (!MetadataDao.upsertRootMetadataObject("tankoubon", tid, name, "")) {
                logger.error("auto-created Tankoubon metadata root 写入失败", ("tankoubonId", tid))
                return ""
            }
            invalidateTankoubonAggregatedContent("getOrCreateAutoTankoubon:${tid}")
            return tid
        } catch (e: Exception) {
            // If concurrent creation raced, try select again.
            logger.warn("getOrCreateAutoTankoubon create failed, retrying select",
                ("categoryInternalId", categoryInternalId.toString()), ("rel", rel), ("error", e.message))
            try {
                let rows2 = DatabaseConfig.driver().query("""
                    SELECT tankoubon_id
                    FROM tankoubons
                    WHERE auto_created = true AND source_category_id = $1 AND COALESCE(source_relative_path, '') = $2
                    LIMIT 1
                """, [DbInt(categoryInternalId), DbText(rel)])
                if (rows2.size > 0) {
                    return rows2[0].getText("tankoubon_id")
                }
            } catch (_: Exception) {}
            return ""
        }
    }

    /**
     * Update Tankoubon cover.
     */
    public static func updateTankoubonCover(tankoubonId: String, coverAssetId: Int64): Bool {
        if (!ensureTankoubonMetadataRoot(tankoubonId)) {
            return false
        }
        if (!MetadataDao.setMetadataAssetId("tankoubon", tankoubonId, "cover", coverAssetId)) {
            return false
        }
        let _ = touchTankoubonUpdatedAt(tankoubonId)
        invalidateTankoubonAggregatedContent("updateTankoubonCover:${tankoubonId}")
        return true
    }

    /**
     * 原样更新 Tankoubon assets JSON，并同步 cover_asset_id。
     */
    public static func updateTankoubonAssetsRaw(tankoubonId: String, assetsRaw: String): Bool {
        let normalized = assetsRaw.trimAscii()
        let payload = if (normalized.size > 0) { normalized } else { "{}" }
        if (!ensureTankoubonMetadataRoot(tankoubonId)) {
            return false
        }

        try {
            DatabaseConfig.driver().exec("""
                WITH target AS (
                    SELECT id AS metadata_id
                    FROM metadata_objects
                    WHERE entity_type = 'tankoubon' AND entity_id = $1
                    LIMIT 1
                ),
                payload AS (
                    SELECT COALESCE(CAST($2 AS JSONB), '{}'::jsonb) AS j
                ),
                parsed AS (
                    SELECT LOWER(TRIM(kv.key)) AS slot, kv.value AS raw_value
                    FROM payload p
                    CROSS JOIN LATERAL jsonb_each(p.j) kv(key, value)
                ),
                normalized AS (
                    SELECT
                        slot,
                        CASE
                            WHEN COALESCE(raw_value #>> '{}', '') ~ '^[0-9]+$'
                                 AND (raw_value #>> '{}')::BIGINT > 0
                                THEN (raw_value #>> '{}')::BIGINT
                            ELSE 0
                        END AS asset_id
                    FROM parsed
                    WHERE slot != ''
                ),
                deleted AS (
                    DELETE FROM metadata_assets ma
                    USING target t
                    WHERE ma.metadata_id = t.metadata_id
                )
                INSERT INTO metadata_assets (metadata_id, slot, asset_id, created_at, updated_at)
                SELECT t.metadata_id, n.slot, n.asset_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                FROM target t
                JOIN normalized n ON n.asset_id > 0
            """, [DbText(tankoubonId), DbText(payload)])
            let _ = touchTankoubonUpdatedAt(tankoubonId)
            invalidateTankoubonAggregatedContent("updateTankoubonAssetsRaw:${tankoubonId}")
            return true
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * 更新 Tankoubon 指定 assets key 的资源 ID（仅支持 cover/backdrop/clearlogo）。
     */
    public static func updateTankoubonAssetIdByKey(tankoubonId: String, assetKey: String, assetId: Int64): Bool {
        let key = assetKey.trimAscii()
        if (key != "cover" && key != "backdrop" && key != "clearlogo") {
            return false
        }
        if (!ensureTankoubonMetadataRoot(tankoubonId)) {
            return false
        }
        if (!MetadataDao.setMetadataAssetId("tankoubon", tankoubonId, key, assetId)) {
            return false
        }
        let _ = touchTankoubonUpdatedAt(tankoubonId)
        invalidateTankoubonAggregatedContent("updateTankoubonAssetIdByKey:${tankoubonId}:${key}")
        return true
    }

    /**
     * Update Tankoubon tags (unified metadata_tags).
     */
    public static func updateTankoubonTags(tankoubonId: String, tagsString: String): Bool {
        let normalizedId = tankoubonId.trimAscii()
        if (normalizedId.size == 0) {
            return false
        }
        if (!ensureTankoubonMetadataRoot(normalizedId)) {
            return false
        }

        let normalizedTags = TagDao.normalizeTags(tagsString.split(","))
        let ok = MetadataDao.replaceMetadataTags("tankoubon", normalizedId, normalizedTags)
        if (!ok) {
            logger.error("updateTankoubonTags failed", ("tankoubonId", normalizedId))
            return false
        }

        let _ = touchTankoubonUpdatedAt(normalizedId)
        invalidateTankoubonAggregatedContent("updateTankoubonTags:${normalizedId}")
        return true
    }

    /**
     * Get merged tags string for a Tankoubon (tankoubon tags + all archive tags).
     */
    public static func getMergedTagsForTankoubon(tankoubonId: String): String {
        try {
            let tankTags = getTankoubonTagsForTankoubon(tankoubonId)
            let archiveTags = getArchiveTagsForTankoubon(tankoubonId)
            return mergeTags(tankTags, archiveTags)
        } catch (_: Exception) {
            return ""
        }
    }

    public static func getOwnTagsForTankoubon(tankoubonId: String): String {
        try {
            return getTankoubonTagsForTankoubon(tankoubonId)
        } catch (_: Exception) {
            return ""
        }
    }

    public static func getTankoubonCoverAssetId(tankoubonId: String): Int64 {
        return MetadataDao.getMetadataAssetId("tankoubon", tankoubonId, "cover")
    }

    public static func getTankoubonAssetIdByKey(tankoubonId: String, assetKey: String): Int64 {
        let key = assetKey.trimAscii()
        if (key != "cover" && key != "backdrop" && key != "clearlogo") {
            return 0
        }
        return MetadataDao.getMetadataAssetId("tankoubon", tankoubonId, key)
    }

    /**
     * 获取Tankoubon中的所有归档arcids
     */
    public static func getArchivesInTankoubon(tankoubonId: String): Array<String> {
        try {
            return getArchivesInTankoubonWithConnection(tankoubonId)
        } catch (e: Exception) {
            logger.error("获取Tankoubon中的归档失败",
                ("tankoubonId", tankoubonId), ("error", e.message))
            return Array<String>()
        }
    }

    /**
     * 检查归档是否在某个Tankoubon中
     * 返回tankoubon_id，如果不在任何Tankoubon中则返回None
     */
    public static func getTankoubonForArchive(archiveArcid: String): Option<String> {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT t.tankoubon_id
                FROM tankoubon_archives ta
                JOIN tankoubons t ON t.id = ta.tankoubon_id
                JOIN archives a ON a.id = ta.archive_id
                WHERE a.arcid = $1
                LIMIT 1
            """, [DbText(archiveArcid)])
            if (rows.size > 0) {
                let tankoubonId = rows[0].getText("tankoubon_id")
                if (tankoubonId != "") {
                    return Some(tankoubonId)
                }
            }
            return None
        } catch (e: Exception) {
            logger.error("检查归档所属Tankoubon失败",
                ("archiveArcid", archiveArcid), ("error", e.message))
            return None
        }
    }

    /**
     * 获取归档所属的所有Tankoubon（返回tankoubon_id列表）
     */
    public static func getTankoubonsForArchive(archiveArcid: String): Array<String> {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT t.tankoubon_id
                FROM tankoubon_archives ta
                JOIN tankoubons t ON t.id = ta.tankoubon_id
                LEFT JOIN metadata_objects mo
                       ON mo.entity_type = 'tankoubon'
                      AND mo.entity_id = t.tankoubon_id
                JOIN archives a ON a.id = ta.archive_id
                WHERE a.arcid = $1
                ORDER BY COALESCE(mo.title, ''), t.tankoubon_id
            """, [DbText(archiveArcid)])
            var list = ArrayList<String>()
            for (r in rows) {
                let tid = r.getText("tankoubon_id")
                if (tid != "") {
                    list.add(tid)
                }
            }
            return list.toArray()
        } catch (e: Exception) {
            logger.error("获取归档所属Tankoubon列表失败",
                ("archiveArcid", archiveArcid), ("error", e.message))
            return Array<String>()
        }
    }

    /**
     * 获取Tankoubon的聚合元数据（用于搜索结果）
     */
    public static func getAggregatedMetadata(tankoubonId: String, userId: Int64): Option<TankoubonAggregatedData> {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT
                    t.tankoubon_id AS tankoubon_id,
                    COALESCE(mo.title, '') AS name,
                    COALESCE(mo.description, '') AS summary,
                    COALESCE(mo.release_at::TEXT, '') AS release_at,
                    COALESCE(mo.created_at::TEXT, '') AS created_at,
                    COALESCE(mo.updated_at::TEXT, '') AS updated_at,
                    COALESCE(asset_map.cover_asset_id, 0) AS cover_asset_id,
                    COALESCE(CAST(asset_map.assets_json AS TEXT), '{}') AS assets_raw,
                    COALESCE(SUM(a.pagecount), 0)::INT AS total_pagecount,
                    COUNT(a.id)::INT AS archive_count,
                    COALESCE(MAX(uas.updated_at)::TEXT, '') AS last_read_time,
                    COALESCE(AVG(uas.progress), 0)::INT AS avg_progress,
                    COALESCE(BOOL_OR(uas.is_new), true) AS has_new_archives
                FROM tankoubons t
                LEFT JOIN metadata_objects mo
                       ON mo.entity_type = 'tankoubon'
                      AND mo.entity_id = t.tankoubon_id
                LEFT JOIN LATERAL (
                    SELECT
                        COALESCE(
                            jsonb_object_agg(ma.slot, to_jsonb(ma.asset_id))
                                FILTER (WHERE ma.asset_id > 0),
                            '{}'::jsonb
                        ) AS assets_json,
                        COALESCE(MAX(CASE WHEN ma.slot = 'cover' THEN ma.asset_id ELSE 0 END), 0) AS cover_asset_id
                    FROM metadata_assets ma
                    WHERE ma.metadata_id = mo.id
                ) asset_map ON true
                JOIN tankoubon_archives ta ON ta.tankoubon_id = t.id
                JOIN archives a ON a.id = ta.archive_id
                LEFT JOIN user_archive_status uas ON uas.archive_id = a.id AND uas.user_id = $1
                WHERE t.tankoubon_id = $2
                GROUP BY
                    t.id, t.tankoubon_id, mo.title, mo.description,
                    mo.release_at, mo.created_at, mo.updated_at,
                    asset_map.cover_asset_id, asset_map.assets_json
            """, [DbInt(userId), DbText(tankoubonId)])
            if (rows.size == 0) {
                return None
            }
            let r = rows[0]
            let data = TankoubonAggregatedData()
            data.tankoubon_id = r.getText("tankoubon_id")
            data.name = r.getText("name")
            data.summary = r.getText("summary")
            data.release_at = r.getText("release_at")
            data.created_at = r.getText("created_at")
            data.updated_at = r.getText("updated_at")
            data.cover_asset_id = r.getInt("cover_asset_id")
            data.assets_raw = r.getText("assets_raw").trimAscii()
            if (data.assets_raw.size == 0) { data.assets_raw = "{}" }
            data.pagecount = Int32(r.getInt("total_pagecount"))
            data.archive_count = Int32(r.getInt("archive_count"))
            data.last_read_time = r.getText("last_read_time")
            data.progress = Int32(r.getInt("avg_progress"))
            data.isnew = r.getBool("has_new_archives")

            let tankoubonTags = getTankoubonTagsForTankoubon(tankoubonId)
            let archiveTags = getArchiveTagsForTankoubon(tankoubonId)
            data.tags = mergeTags(tankoubonTags, archiveTags)
            return Some(data)
        } catch (e: Exception) {
            logger.error("获取Tankoubon聚合元数据失败",
                ("tankoubonId", tankoubonId), ("error", e.message))
            return None
        }
    }

    /**
     * 获取Tankoubon内部ID（从tankoubon_id）
     */
    public static func getTankoubonInternalId(tankoubonId: String): Int64 {
        try {
            let rows = DatabaseConfig.driver().query("SELECT id FROM tankoubons WHERE tankoubon_id = $1", [DbText(tankoubonId)])
            if (rows.size > 0) {
                return rows[0].getInt("id")
            }
        } catch (_: Exception) {}
        return 0
    }

    /**
     * 获取Archive内部ID（从arcid）
     */
    private static func getArchiveInternalId(arcid: String): Int64 {
        try {
            let rows = DatabaseConfig.driver().query("SELECT id FROM archives WHERE arcid = $1", [DbText(arcid)])
            if (rows.size > 0) {
                return rows[0].getInt("id")
            }
        } catch (_: Exception) {}
        return 0
    }

    /**
     * 获取 Tankoubon 自身标签（metadata_tags）。
     */
    private static func getTankoubonTagsForTankoubon(tankoubonId: String): String {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT COALESCE(string_agg(mt.tag, ',' ORDER BY mt.tag), '') AS tags
                FROM metadata_objects mo
                LEFT JOIN metadata_tags mt ON mt.metadata_id = mo.id
                WHERE mo.entity_type = 'tankoubon'
                  AND mo.entity_id = $1
            """, [DbText(tankoubonId)])
            if (rows.size > 0) {
                return rows[0].getText("tags")
            }
            return ""
        } catch (_: Exception) {}
        return ""
    }

    /**
     * 获取Tankoubon中所有归档的标签
     */
    private static func getArchiveTagsForTankoubon(tankoubonId: String): String {
        try {
            let rows = DatabaseConfig.driver().query("""
                SELECT COALESCE(string_agg(DISTINCT
                    mt.tag, ','), '') AS tags
                FROM tankoubon_archives ta
                JOIN tankoubons t ON t.id = ta.tankoubon_id
                JOIN archives a ON a.id = ta.archive_id
                JOIN metadata_objects mo ON mo.entity_type = 'archive' AND mo.entity_id = a.arcid
                JOIN metadata_tags mt ON mt.metadata_id = mo.id
                WHERE t.tankoubon_id = $1
            """, [DbText(tankoubonId)])
            if (rows.size > 0) {
                return rows[0].getText("tags")
            }
            return ""
        } catch (_: Exception) {}
        return ""
    }

    /**
     * 合并并去重标签
     */
    private static func mergeTags(tankoubonTags: String, archiveTags: String): String {
        var tagSet: HashMap<String, Bool> = HashMap<String, Bool>()

        // 添加tankoubon标签（保留 source 标签）
        if (tankoubonTags != "") {
            let tags = tankoubonTags.split(",")
            for (tag in tags) {
                let trimmed = tag.trimAscii()
                if (trimmed != "") {
                    tagSet[trimmed] = true
                }
            }
        }

        // 添加archive标签
        if (archiveTags != "") {
            let tags = archiveTags.split(",")
            for (tag in tags) {
                let trimmed = tag.trimAscii()
                if (trimmed != "" && !isSourceTag(trimmed)) {
                    tagSet[trimmed] = true
                }
            }
        }

        // 转换回字符串
        var result = ""
        var isFirst = true
        for ((tag, _) in tagSet) {
            if (!isFirst) {
                result += ","
            }
            result += tag
            isFirst = false
        }

        return result
    }

    /**
     * 批量获取 Tankoubon 自身标签（metadata_tags）。
     */
    private static func getBatchTankoubonTagsForTankoubons(tankoubonIds: Array<String>): HashMap<String, String> {
        var result: HashMap<String, String> = HashMap<String, String>()
        if (tankoubonIds.size == 0) {
            return result
        }

        try {
            var placeholders = ""
            var params = ArrayList<DbValue>(0)
            var idx = 1
            for (i in 0..tankoubonIds.size) {
                if (i > 0) { placeholders += "," }
                placeholders += "\$${idx.toString()}"
                params.add(DbText(tankoubonIds[i]))
                idx += 1
            }

            let rows = DatabaseConfig.driver().query("""
                SELECT mo.entity_id AS entity_id, mt.tag AS tag
                FROM metadata_objects mo
                JOIN metadata_tags mt ON mt.metadata_id = mo.id
                WHERE mo.entity_type = 'tankoubon'
                  AND mo.entity_id IN (${placeholders})
            """, params.toArray())
            var tagsMap: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
            for (r in rows) {
                let tid = r.getText("entity_id")
                let tag = r.getText("tag")
                if (tid != "" && tag != "") {
                    match (tagsMap.get(tid)) {
                        case Some(list) => list.add(tag)
                        case None =>
                            let list = ArrayList<String>()
                            list.add(tag)
                            tagsMap[tid] = list
                    }
                }
            }
            for ((tid, tagsList) in tagsMap) {
                var combined = ""
                for (i in 0..tagsList.size) {
                    if (i > 0) { combined += "," }
                    combined += tagsList[i]
                }
                result[tid] = combined
            }
        } catch (_: Exception) {}
        return result
    }

    /**
     * 批量获取Tankoubon的归档标签
     */
    private static func getBatchArchiveTagsForTankoubons(tankoubonIds: Array<String>): HashMap<String, String> {
        var result: HashMap<String, String> = HashMap<String, String>()
        if (tankoubonIds.size == 0) {
            return result
        }

        try {
            var placeholders = ""
            var params = ArrayList<DbValue>(0)
            var idx = 1
            for (i in 0..tankoubonIds.size) {
                if (i > 0) { placeholders += "," }
                placeholders += "\$${idx.toString()}"
                params.add(DbText(tankoubonIds[i]))
                idx += 1
            }

            let rows = DatabaseConfig.driver().query("""
                SELECT
                    t.tankoubon_id AS tankoubon_id,
                    COALESCE(string_agg(DISTINCT mt.tag, ','), '') AS tags
                FROM tankoubon_archives ta
                JOIN tankoubons t ON t.id = ta.tankoubon_id
                JOIN archives a ON a.id = ta.archive_id
                JOIN metadata_objects mo ON mo.entity_type = 'archive' AND mo.entity_id = a.arcid
                JOIN metadata_tags mt ON mt.metadata_id = mo.id
                WHERE t.tankoubon_id IN (${placeholders})
                GROUP BY t.tankoubon_id
            """, params.toArray())
            for (r in rows) {
                let tid = r.getText("tankoubon_id")
                let tags = r.getText("tags")
                if (tid != "") {
                    result[tid] = tags
                }
            }
        } catch (e: Exception) {
            logger.error("批量获取归档标签失败", ("error", e.message))
        }
        return result
    }

    /**
     * 批量获取Tankoubon的聚合元数据
     */
    public static func getBatchAggregatedMetadata(tankoubonIds: Array<String>, userId: Int64): HashMap<String, TankoubonAggregatedData> {
        var result: HashMap<String, TankoubonAggregatedData> = HashMap<String, TankoubonAggregatedData>()
        if (tankoubonIds.size == 0) {
            return result
        }

        let orderedIds = normalizeUniqueIds(tankoubonIds)
        if (orderedIds.size == 0) {
            return result
        }

        let contentVersion = DerivedCacheUtils.getTankoubonAggregatedContentVersion()
        let userVersion = DerivedCacheUtils.getTankoubonAggregatedUserVersion(userId)
        let misses = ArrayList<String>()
        var hitCount = 0
        for (tankoubonId in orderedIds) {
            let cacheKey = buildAggregatedMetadataCacheKey(contentVersion, userVersion, userId, tankoubonId)
            match (readAggregatedMetadataCache(cacheKey)) {
                case Some(cached) =>
                    result[tankoubonId] = cached
                    hitCount += 1
                case None =>
                    misses.add(tankoubonId)
            }
        }

        if (misses.size == 0) {
            logger.debug("tankoubon aggregated metadata cache hit",
                ("requested", orderedIds.size.toString()),
                ("hits", hitCount.toString()),
                ("misses", "0"),
                ("userId", userId.toString()))
            return result
        }

        try {
            // 构建 IN 子句的占位符
            var placeholders = ""
            var params = ArrayList<DbValue>(0)
            params.add(DbInt(userId))
            var idx = 2
            for (i in 0..misses.size) {
                if (i > 0) { placeholders += "," }
                placeholders += "\$${idx.toString()}"
                params.add(DbText(misses[i]))
                idx += 1
            }

            let rows = DatabaseConfig.driver().query("""
                SELECT
                    t.tankoubon_id AS tankoubon_id,
                    COALESCE(mo.title, '') AS name,
                    COALESCE(mo.description, '') AS summary,
                    COALESCE(mo.release_at::TEXT, '') AS release_at,
                    COALESCE(mo.created_at::TEXT, '') AS created_at,
                    COALESCE(mo.updated_at::TEXT, '') AS updated_at,
                    COALESCE(asset_map.cover_asset_id, 0) AS cover_asset_id,
                    COALESCE(CAST(asset_map.assets_json AS TEXT), '{}') AS assets_raw,
                    COALESCE(SUM(a.pagecount), 0)::INT AS total_pagecount,
                    COUNT(a.id)::INT AS archive_count,
                    COALESCE(MAX(uas.updated_at)::TEXT, '') AS last_read_time,
                    COALESCE(AVG(uas.progress), 0)::INT AS avg_progress,
                    COALESCE(BOOL_OR(uas.is_new), true) AS has_new_archives
                FROM tankoubons t
                LEFT JOIN metadata_objects mo
                       ON mo.entity_type = 'tankoubon'
                      AND mo.entity_id = t.tankoubon_id
                LEFT JOIN LATERAL (
                    SELECT
                        COALESCE(
                            jsonb_object_agg(ma.slot, to_jsonb(ma.asset_id))
                                FILTER (WHERE ma.asset_id > 0),
                            '{}'::jsonb
                        ) AS assets_json,
                        COALESCE(MAX(CASE WHEN ma.slot = 'cover' THEN ma.asset_id ELSE 0 END), 0) AS cover_asset_id
                    FROM metadata_assets ma
                    WHERE ma.metadata_id = mo.id
                ) asset_map ON true
                JOIN tankoubon_archives ta ON ta.tankoubon_id = t.id
                JOIN archives a ON a.id = ta.archive_id
                LEFT JOIN user_archive_status uas ON uas.archive_id = a.id AND uas.user_id = $1
                WHERE t.tankoubon_id IN (${placeholders})
                GROUP BY
                    t.id, t.tankoubon_id, mo.title, mo.description,
                    mo.release_at, mo.created_at, mo.updated_at,
                    asset_map.cover_asset_id, asset_map.assets_json
            """, params.toArray())

            // 临时存储，用于后续获取标签
            var tempData: HashMap<String, TankoubonAggregatedData> = HashMap<String, TankoubonAggregatedData>()
            for (r in rows) {
                let data = TankoubonAggregatedData()
                data.tankoubon_id = r.getText("tankoubon_id")
                data.name = r.getText("name")
                data.summary = r.getText("summary")
                data.release_at = r.getText("release_at")
                data.created_at = r.getText("created_at")
                data.updated_at = r.getText("updated_at")
                data.cover_asset_id = r.getInt("cover_asset_id")
                data.assets_raw = r.getText("assets_raw").trimAscii()
                if (data.assets_raw.size == 0) { data.assets_raw = "{}" }
                data.pagecount = Int32(r.getInt("total_pagecount"))
                data.archive_count = Int32(r.getInt("archive_count"))
                data.last_read_time = r.getText("last_read_time")
                data.progress = Int32(r.getInt("avg_progress"))
                data.isnew = r.getBool("has_new_archives")
                tempData[data.tankoubon_id] = data
            }

            // 批量获取 tankoubon 自身标签和归档标签并合并
            let missingIds = misses.toArray()
            let tankoubonTagsMap = getBatchTankoubonTagsForTankoubons(missingIds)
            let archiveTagsMap = getBatchArchiveTagsForTankoubons(missingIds)
            for ((tid, data) in tempData) {
                var tankoubonTags = ""
                var archiveTags = ""
                match (tankoubonTagsMap.get(tid)) {
                    case Some(tags) => tankoubonTags = tags
                    case None => ()
                }
                match (archiveTagsMap.get(tid)) {
                    case Some(tags) => archiveTags = tags
                    case None => ()
                }
                data.tags = mergeTags(tankoubonTags, archiveTags)
                result[tid] = data
                let cacheKey = buildAggregatedMetadataCacheKey(contentVersion, userVersion, userId, tid)
                writeAggregatedMetadataCache(cacheKey, data)
            }
        } catch (e: Exception) {
            logger.error("批量获取Tankoubon聚合元数据失败", ("error", e.message))
        }
        logger.debug("tankoubon aggregated metadata cache lookup",
            ("requested", orderedIds.size.toString()),
            ("hits", hitCount.toString()),
            ("misses", misses.size.toString()),
            ("userId", userId.toString()))
        return result
    }

    /**
     * 批量获取Tankoubon中的所有归档arcids
     */
    public static func getBatchArchivesInTankoubon(tankoubonIds: Array<String>): HashMap<String, Array<String>> {
        var result: HashMap<String, Array<String>> = HashMap<String, Array<String>>()
        if (tankoubonIds.size == 0) {
            return result
        }

        let orderedIds = normalizeUniqueIds(tankoubonIds)
        if (orderedIds.size == 0) {
            return result
        }

        let cacheVersion = DerivedCacheUtils.getTankoubonChildrenVersion()
        let misses = ArrayList<String>()
        var hitCount = 0
        for (tankoubonId in orderedIds) {
            let cacheKey = buildChildrenCacheKey(cacheVersion, tankoubonId)
            match (readChildrenCache(cacheKey)) {
                case Some(cached) =>
                    result[tankoubonId] = cached
                    hitCount += 1
                case None =>
                    misses.add(tankoubonId)
            }
        }

        if (misses.size == 0) {
            logger.debug("tankoubon children cache hit",
                ("requested", orderedIds.size.toString()),
                ("hits", hitCount.toString()),
                ("misses", "0"))
            return result
        }

        try {
            var placeholders = ""
            var params = ArrayList<DbValue>(0)
            var idx = 1
            for (i in 0..misses.size) {
                if (i > 0) { placeholders += "," }
                placeholders += "\$${idx.toString()}"
                params.add(DbText(misses[i]))
                idx += 1
            }

            let rows = DatabaseConfig.driver().query("""
                SELECT t.tankoubon_id AS tankoubon_id, a.arcid AS arcid
                FROM tankoubon_archives ta
                JOIN tankoubons t ON t.id = ta.tankoubon_id
                JOIN archives a ON a.id = ta.archive_id
                WHERE t.tankoubon_id IN (${placeholders})
                ORDER BY t.tankoubon_id, ta.sort_order, ta.id
            """, params.toArray())
            var tempMap: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
            for (r in rows) {
                let tid = r.getText("tankoubon_id")
                let arcid = r.getText("arcid")
                if (tid != "" && arcid != "") {
                    match (tempMap.get(tid)) {
                        case Some(list) => list.add(arcid)
                        case None =>
                            let list = ArrayList<String>()
                            list.add(arcid)
                            tempMap[tid] = list
                    }
                }
            }
            for ((tid, list) in tempMap) {
                let children = list.toArray()
                result[tid] = children
                let cacheKey = buildChildrenCacheKey(cacheVersion, tid)
                writeChildrenCache(cacheKey, children)
            }
        } catch (e: Exception) {
            logger.error("批量获取Tankoubon归档列表失败", ("error", e.message))
        }
        for (tankoubonId in misses) {
            match (result.get(tankoubonId)) {
                case Some(_) => ()
                case None =>
                    result[tankoubonId] = Array<String>()
                    let cacheKey = buildChildrenCacheKey(cacheVersion, tankoubonId)
                    writeChildrenCache(cacheKey, Array<String>())
            }
        }
        logger.debug("tankoubon children cache lookup",
            ("requested", orderedIds.size.toString()),
            ("hits", hitCount.toString()),
            ("misses", misses.size.toString()))
        return result
    }
}