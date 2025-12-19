package lrr4cj.models

import lrr4cj.dao.*
import std.collection.*

/**
 * 单行本数据模型
 */
public class Tankoubon {
    public var id: String
    public var name: String
    public var summary: String
    public var tags: String
    public var archives: Array<String>

    // 聚合字段（用于搜索结果显示）
    public var pagecount: Int32 = 0
    public var progress: Int32 = 0
    public var last_read_time: String = ""
    public var isnew: Bool = false
    public var archive_count: Int32 = 0
    public var thumbhash: String = ""

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
    public func toJson(): String {
        var archivesJson = "["
        var isFirst = true
        for (archive in archives) {
            if (!isFirst) {
                archivesJson += ","
            }
            archivesJson += "\"${archive}\""
            isFirst = false
        }
        archivesJson += "]"

        return "{\"tankoubon_id\":\"${id}\",\"name\":\"${name}\",\"summary\":\"${summary}\",\"tags\":\"${tags}\",\"archives\":${archivesJson},\"archive_count\":${archive_count},\"pagecount\":${pagecount},\"progress\":${progress},\"lastreadtime\":\"${last_read_time}\",\"isnew\":${isnew},\"thumbhash\":\"${thumbhash}\"}"
    }

    /**
     * 转换为带聚合数据的JSON字符串（用于搜索结果）
     */
    public func toAggregatedJson(): String {
        return "{\"id\":\"${id}\",\"name\":\"${name}\",\"summary\":\"${summary}\",\"tags\":\"${tags}\",\"pagecount\":${pagecount},\"progress\":${progress},\"lastreadtime\":\"${last_read_time}\",\"isnew\":${isnew},\"archive_count\":${archive_count},\"thumbhash\":\"${thumbhash}\"}"
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
            tankoubons.add(Tankoubon(data.tankoubon_id, data.name, data.summary, data.tags, data.archives))
        }

        return tankoubons.toArray()
    }

    /**
     * 根据ID获取单行本
     */
    public static func getTankoubonById(id: String): Tankoubon {
        let dataOpt = TankoubonDao.getTankoubonById(id)
        match (dataOpt) {
            case Some(data) =>
                let tankoubon = Tankoubon(data.tankoubon_id, data.name, data.summary, data.tags, data.archives)

                // 获取档案数量和总页数
                let (archiveCount, totalPages) = TankoubonDao.getTankoubonArchiveStats(id)
                tankoubon.archive_count = archiveCount
                tankoubon.pagecount = totalPages

                return tankoubon
            case None =>
                return Tankoubon("", "", "", "", [])
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
                tankoubon.pagecount = aggData.pagecount
                tankoubon.progress = aggData.progress
                tankoubon.last_read_time = aggData.last_read_time
                tankoubon.isnew = aggData.isnew
                tankoubon.archive_count = aggData.archive_count
                tankoubon.thumbhash = aggData.thumbhash
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
    public static func updateTankoubon(id: String, name: String, summary: String, tags: String, _: Array<String>): Bool {
        return TankoubonDao.updateTankoubon(id, name, summary, tags)
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
        return TankoubonDao.addArchiveToTankoubon(tankoubonId, archiveId, 0)
    }

    /**
     * 从单行本移除档案
     */
    public static func removeArchiveFromTankoubon(tankoubonId: String, archiveId: String): Bool {
        return TankoubonDao.removeArchiveFromTankoubon(tankoubonId, archiveId)
    }
}