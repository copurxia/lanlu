package lanlu.contexts.tankoubon.domain
import lanlu.contexts.tankoubon.infrastructure.persistence.*
import lanlu.contexts.user.infrastructure.persistence.UserTankoubonFavoriteDao
import std.collection.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*

/**
 * 单行本数据模型
 */
public class Tankoubon {
    public var id: String
    public var name: String
    public var summary: String
    public var tags: String
    public var archives: Array<String>
    public var cover_asset_id: Int64 = 0
    public var assets_raw: String = "{}"
    public var release_at: String = ""
    public var created_at: String = ""
    public var updated_at: String = ""

    // 聚合字段（用于搜索结果显示）
    public var pagecount: Int32 = 0
    public var progress: Int32 = 0
    public var last_read_time: Int64 = 0
    public var isnew: Bool = false
    public var archive_count: Int32 = 0
    public var isfavorite: Bool = false

    public init(id: String, name: String, summary: String, tags: String, archives: Array<String>) {
        this.id = id
        this.name = name
        this.summary = summary
        this.tags = tags
        this.archives = archives
    }

    /**
     * 转换为JSON字符串
     */
    public func writeJson(w: JsonWriter): Unit {
        let rawAssets = assets_raw.trimAscii()
        let normalizedAssets = if (rawAssets.size > 0) { rawAssets } else { "{}" }
        w.startObject()
        w.writeName("tankoubon_id").writeValue(id)
        w.writeName("title").writeValue(name)
        w.writeName("description").writeValue(summary)
        w.writeName("tags").writeValue(tags)
        w.writeName("assets").jsonValue(normalizedAssets)
        w.writeName("children")
        w.startArray()
        for (archive in archives) {
            w.writeValue(archive)
        }
        w.endArray()
        w.writeName("archive_count").writeValue(archive_count)
        w.writeName("pagecount").writeValue(pagecount)
        w.writeName("progress").writeValue(progress)
        w.writeName("lastreadtime").writeValue(last_read_time)
        w.writeName("release_at").writeValue(release_at)
        w.writeName("created_at").writeValue(created_at)
        w.writeName("updated_at").writeValue(updated_at)
        w.writeName("isnew").writeValue(isnew)
        w.writeName("isfavorite").writeValue(isfavorite)
        w.endObject()
    }

    public func toJson(): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        writeJson(w)
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    /**
     * 转换为带聚合数据的JSON字符串（用于搜索结果）
     */
    public func toAggregatedJson(): String {
        let rawAssets = assets_raw.trimAscii()
        let normalizedAssets = if (rawAssets.size > 0) { rawAssets } else { "{}" }
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("tankoubon_id").writeValue(id)
        w.writeName("title").writeValue(name)
        w.writeName("description").writeValue(summary)
        w.writeName("tags").writeValue(tags)
        w.writeName("assets").jsonValue(normalizedAssets)
        w.writeName("children")
        w.startArray()
        for (archive in archives) {
            w.writeValue(archive)
        }
        w.endArray()
        w.writeName("pagecount").writeValue(pagecount)
        w.writeName("progress").writeValue(progress)
        w.writeName("lastreadtime").writeValue(last_read_time)
        w.writeName("release_at").writeValue(release_at)
        w.writeName("created_at").writeValue(created_at)
        w.writeName("updated_at").writeValue(updated_at)
        w.writeName("isnew").writeValue(isnew)
        w.writeName("archive_count").writeValue(archive_count)
        w.writeName("isfavorite").writeValue(isfavorite)
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }
}

/**
 * 单行本数据访问层
 */
public class TankoubonModel {
    /**
     * 获取所有单行本（带聚合 tags/progress 等），用于列表展示。
     * 批量路径：基础行 + 批量聚合元数据（RocksDB 缓存）+ 批量 children + 批量收藏状态，
     * 每请求 SQL 条数恒定（≤5 条），替代旧版每合集 4+ 条的 N+1 逐条查询。
     */
    public static func getAllTankoubonsWithUser(userId: Int64): Array<Tankoubon> {
        let daoData = TankoubonDao.getAllTankoubons(includeArchives: false)
        if (daoData.size == 0) {
            return []
        }

        var ids = ArrayList<String>()
        for (data in daoData) {
            ids.add(data.tankoubon_id)
        }
        let idArray = ids.toArray()

        let aggMap = TankoubonDao.getBatchAggregatedMetadata(idArray, userId)
        let childrenMap = TankoubonDao.getBatchArchivesInTankoubon(idArray)
        var favoriteMap = HashMap<String, Bool>()
        if (userId > 0) {
            favoriteMap = UserTankoubonFavoriteDao.getBatchFavoriteStatus(userId, idArray)
        }

        var tankoubons: ArrayList<Tankoubon> = ArrayList<Tankoubon>()
        for (data in daoData) {
            let t = Tankoubon(data.tankoubon_id, data.name, data.summary, "", data.archives)
            t.cover_asset_id = data.cover_asset_id
            t.assets_raw = data.assets_raw
            t.release_at = data.release_at
            t.created_at = data.created_at
            t.updated_at = data.updated_at

            // 聚合元数据：无子档案的空合集批量 SQL 不产生行（与旧 getAggregatedMetadata 的
            // JOIN 语义一致），此时保留基础字段，仅补 children 与收藏状态。
            match (aggMap.get(data.tankoubon_id)) {
                case Some(agg) =>
                    if (agg.tags.size > 0) {
                        t.tags = agg.tags
                    }
                    if (agg.cover_asset_id > 0) {
                        t.cover_asset_id = agg.cover_asset_id
                    }
                    t.assets_raw = agg.assets_raw
                    if (agg.release_at.size > 0) {
                        t.release_at = agg.release_at
                    }
                    if (agg.created_at.size > 0) {
                        t.created_at = agg.created_at
                    }
                    if (agg.updated_at.size > 0) {
                        t.updated_at = agg.updated_at
                    }
                    t.pagecount = agg.pagecount
                    t.archive_count = agg.archive_count
                    t.progress = agg.progress
                    t.last_read_time = agg.last_read_time
                    t.isnew = agg.isnew
                case None => ()
            }

            match (childrenMap.get(data.tankoubon_id)) {
                case Some(children) =>
                    if (children.size > 0) {
                        t.archives = children
                    }
                case None => ()
            }

            if (userId > 0) {
                match (favoriteMap.get(data.tankoubon_id)) {
                    case Some(isFav) => t.isfavorite = isFav
                    case None => ()
                }
            }
            tankoubons.add(t)
        }
        return tankoubons.toArray()
    }

    /**
     * 根据ID获取单行本
     */
    public static func getTankoubonById(id: String): Tankoubon {
        match (TankoubonDao.getTankoubonById(id)) {
            case Some(data) => return buildTankoubonFromData(data)
            case None => return Tankoubon("", "", "", "", [])
        }
    }

    public static func getTankoubonByIdWithUser(id: String, userId: Int64): Tankoubon {
        match (TankoubonDao.getTankoubonById(id)) {
            case Some(data) =>
                let tankoubon = buildTankoubonFromData(data)
                applyAggregatedMetadata(tankoubon, userId)
                return tankoubon
            case None => return Tankoubon("", "", "", "", [])
        }
    }

    /**
     * 获取某个归档所属的所有Tankoubon（包含archives列表）
     */
    public static func getTankoubonsForArchive(archiveArcid: String): Array<Tankoubon> {
        let ids = TankoubonDao.getTankoubonsForArchive(archiveArcid)
        if (ids.size == 0) { return [] }

        var list: ArrayList<Tankoubon> = ArrayList<Tankoubon>()
        for (id in ids) {
            let tank = getTankoubonById(id)
            if (tank.id.size > 0) {
                list.add(tank)
            }
        }
        return list.toArray()
    }

    public static func getTankoubonsForArchiveWithUser(archiveArcid: String, userId: Int64): Array<Tankoubon> {
        let ids = TankoubonDao.getTankoubonsForArchive(archiveArcid)
        if (ids.size == 0) { return [] }

        var list: ArrayList<Tankoubon> = ArrayList<Tankoubon>()
        for (id in ids) {
            let tank = getTankoubonByIdWithUser(id, userId)
            if (tank.id.size > 0) {
                list.add(tank)
            }
        }
        return list.toArray()
    }

    private static func buildTankoubonFromData(data: TankoubonData): Tankoubon {
        let tankoubon = Tankoubon(data.tankoubon_id, data.name, data.summary, "", data.archives)
        tankoubon.cover_asset_id = data.cover_asset_id
        tankoubon.assets_raw = data.assets_raw
        tankoubon.release_at = data.release_at
        tankoubon.created_at = data.created_at
        tankoubon.updated_at = data.updated_at
        let (archiveCount, totalPages) = TankoubonDao.getTankoubonArchiveStats(data.tankoubon_id)
        tankoubon.archive_count = archiveCount
        tankoubon.pagecount = totalPages
        return tankoubon
    }

    private static func applyAggregatedMetadata(tankoubon: Tankoubon, userId: Int64): Unit {
        match (TankoubonDao.getAggregatedMetadata(tankoubon.id, userId)) {
            case Some(agg) =>
                if (agg.tags.size > 0) {
                    tankoubon.tags = agg.tags
                }
                if (agg.cover_asset_id > 0) {
                    tankoubon.cover_asset_id = agg.cover_asset_id
                }
                tankoubon.assets_raw = agg.assets_raw
                if (agg.release_at.size > 0) {
                    tankoubon.release_at = agg.release_at
                }
                if (agg.created_at.size > 0) {
                    tankoubon.created_at = agg.created_at
                }
                if (agg.updated_at.size > 0) {
                    tankoubon.updated_at = agg.updated_at
                }
                tankoubon.pagecount = agg.pagecount
                tankoubon.archive_count = agg.archive_count
                tankoubon.progress = agg.progress
                tankoubon.last_read_time = agg.last_read_time
                tankoubon.isnew = agg.isnew
            case None => ()
        }
        // 收藏状态：合集下任一子 archive 被收藏即为 true
        if (userId > 0) {
            tankoubon.isfavorite = UserTankoubonFavoriteDao.isFavorite(userId, tankoubon.id)
        }
    }

    /**
     * 获取带聚合元数据的单行本（用于搜索结果）
     */
    public static func getTankoubonWithAggregatedMetadata(id: String, userId: Int64): Tankoubon {
        let aggDataOpt = TankoubonDao.getAggregatedMetadata(id, userId)
        match (aggDataOpt) {
            case Some(aggData) =>
                let tankoubon = Tankoubon(aggData.tankoubon_id, aggData.name, aggData.summary, aggData.tags, [])
                tankoubon.cover_asset_id = aggData.cover_asset_id
                tankoubon.assets_raw = aggData.assets_raw
                tankoubon.release_at = aggData.release_at
                tankoubon.created_at = aggData.created_at
                tankoubon.updated_at = aggData.updated_at
                tankoubon.pagecount = aggData.pagecount
                tankoubon.progress = aggData.progress
                tankoubon.last_read_time = aggData.last_read_time
                tankoubon.isnew = aggData.isnew
                tankoubon.archive_count = aggData.archive_count
                return tankoubon
            case None =>
                return Tankoubon("", "", "", "", [])
        }
    }

    /**
     * 创建新单行本
     */
    public static func createTankoubon(name: String): Tankoubon {
        let newId = TankoubonDao.createTankoubon(name)
        if (newId != "") {
            return Tankoubon(newId, name, "", "", [])
        }
        return Tankoubon("", "", "", "", [])
    }

}
