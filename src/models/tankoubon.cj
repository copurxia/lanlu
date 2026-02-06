package lanlu.models

import lanlu.dao.*
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

    // 聚合字段（用于搜索结果显示）
    public var pagecount: Int32 = 0
    public var progress: Int32 = 0
    public var last_read_time: String = ""
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
        w.startObject()
        w.writeName("tankoubon_id").writeValue(id)
        w.writeName("name").writeValue(name)
        w.writeName("summary").writeValue(summary)
        w.writeName("tags").writeValue(tags)
        w.writeName("cover_asset_id").writeValue(cover_asset_id)
        w.writeName("archives")
        w.startArray()
        for (archive in archives) {
            w.writeValue(archive)
        }
        w.endArray()
        w.writeName("archive_count").writeValue(archive_count)
        w.writeName("pagecount").writeValue(pagecount)
        w.writeName("progress").writeValue(progress)
        w.writeName("lastreadtime").writeValue(last_read_time)
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
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        w.writeName("id").writeValue(id)
        w.writeName("name").writeValue(name)
        w.writeName("summary").writeValue(summary)
        w.writeName("tags").writeValue(tags)
        w.writeName("cover_asset_id").writeValue(cover_asset_id)
        w.writeName("pagecount").writeValue(pagecount)
        w.writeName("progress").writeValue(progress)
        w.writeName("lastreadtime").writeValue(last_read_time)
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
     * 获取所有单行本
     */
    public static func getAllTankoubons(): Array<Tankoubon> {
        let daoData = TankoubonDao.getAllTankoubons()
        var tankoubons: ArrayList<Tankoubon> = ArrayList<Tankoubon>()

        for (data in daoData) {
            let t = Tankoubon(data.tankoubon_id, data.name, data.summary, "", data.archives)
            t.cover_asset_id = data.cover_asset_id
            tankoubons.add(t)
        }

        return tankoubons.toArray()
    }

    /**
     * 获取所有单行本（带聚合 tags/progress 等），用于列表展示
     */
    public static func getAllTankoubonsWithUser(userId: Int64): Array<Tankoubon> {
        let daoData = TankoubonDao.getAllTankoubons()
        var tankoubons: ArrayList<Tankoubon> = ArrayList<Tankoubon>()
        for (data in daoData) {
            let t = Tankoubon(data.tankoubon_id, data.name, data.summary, "", data.archives)
            t.cover_asset_id = data.cover_asset_id
            applyAggregatedMetadata(t, userId)
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
                tankoubon.pagecount = agg.pagecount
                tankoubon.archive_count = agg.archive_count
                tankoubon.progress = agg.progress
                tankoubon.last_read_time = agg.last_read_time
                tankoubon.isnew = agg.isnew
            case None => ()
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

    /**
     * 更新单行本
     */
    public static func updateTankoubon(id: String, name: String, summary: String, _: String, _: Array<String>): Bool {
        return TankoubonDao.updateTankoubon(id, name, summary)
    }

    public static func updateTankoubonCover(id: String, coverAssetId: Int64): Bool {
        return TankoubonDao.updateTankoubonCover(id, coverAssetId)
    }

    public static func updateTankoubonTags(id: String, tagsString: String): Bool {
        return TankoubonDao.updateTankoubonTags(id, tagsString)
    }

    /**
     * 删除单行本
     */
    public static func deleteTankoubon(id: String): Bool {
        return TankoubonDao.deleteTankoubon(id)
    }

    /**
     * 向单行本添加档案
     */
    public static func addArchiveToTankoubon(tankoubonId: String, archiveId: String): Bool {
        return TankoubonDao.addArchiveToTankoubonAppend(tankoubonId, archiveId)
    }

    /**
     * 从单行本移除档案
     */
    public static func removeArchiveFromTankoubon(tankoubonId: String, archiveId: String): Bool {
        return TankoubonDao.removeArchiveFromTankoubon(tankoubonId, archiveId)
    }
}
