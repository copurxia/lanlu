package lanlu.shared.entities

import csorm.*
import std.collection.*

/**
 * PartialModel / FromQueryResult 落地（csorm 阶段六）。
 *
 * 列表查询用 PartialModel 瘦身（只取需要的列，避免 SELECT *），
 * 聚合查询用 FromQueryResult 替代手写下标映射。
 */

// ===== 列表行（瘦表投影） =====

/**
 * 归档列表行：只取 id/arcid/filename/title/thumbhash/cover_asset_id（6 列）。
 * 替代列表页 SELECT * 取全列（archives 宽表含 JSONB 元数据列，单行数 KB）。
 */
public class ArchiveListRow {
    public var id: Int64 = 0
    public var arcid: String = ""
    public var filename: String = ""
    public var title: String = ""
    public var thumbhash: String = ""
    public var cover_asset_id: Int64 = 0

    public init() {}
}

public class ArchiveListRowPartial <: PartialModel {
    public init() {}
    public func columns(): Array<String> {
        ["id", "arcid", "filename", "title", "thumbhash", "cover_asset_id"]
    }
    public func fromRow(r: Row): Any {
        let out = ArchiveListRow()
        out.id = r.getOrNullInt64(0) ?? 0
        out.arcid = r.getOrNullText(1) ?? ""
        out.filename = r.getOrNullText(2) ?? ""
        out.title = r.getOrNullText(3) ?? ""
        out.thumbhash = r.getOrNullText(4) ?? ""
        out.cover_asset_id = r.getOrNullInt64(5) ?? 0
        out
    }
}

// ===== 归档详情行（archive_metadata_search 视图全列） =====

/**
 * 归档详情行：映射 archive_metadata_search 视图的 14 列。
 * 替代 archive_dao/user_*_dao 里重复的 mapArchivesWithTagsRow 下标映射。
 */
public class ArchiveDetailRow {
    public var arcid: String = ""
    public var filename: String = ""
    public var title: String = ""
    public var summary: String = ""
    public var thumbhash: String = ""
    public var cover_asset_id: Int64 = 0
    public var created_at: String = ""
    public var updated_at: String = ""
    public var release_at: String = ""
    public var relative_path: String = ""
    public var file_size: Int64 = 0
    public var pagecount: Int32 = 0
    public var last_read_time: Int64 = 0
    public var progress: Int32 = 0
    public var tags: String = ""

    public init() {}
}

public class ArchiveDetailRowMapper <: FromQueryResult {
    public init() {}
    public func fromRow(r: Row): Any {
        let out = ArchiveDetailRow()
        out.arcid = r.getOrNullText(0) ?? ""
        out.filename = r.getOrNullText(1) ?? ""
        out.title = r.getOrNullText(2) ?? ""
        out.summary = r.getOrNullText(3) ?? ""
        out.thumbhash = r.getOrNullText(4) ?? ""
        out.cover_asset_id = r.getOrNullInt64(5) ?? 0
        out.created_at = r.getOrNullText(6) ?? ""
        out.updated_at = r.getOrNullText(7) ?? ""
        out.release_at = r.getOrNullText(8) ?? ""
        out.relative_path = r.getOrNullText(9) ?? ""
        out.file_size = r.getOrNullInt64(10) ?? 0
        out.pagecount = r.getOrNullInt32(11) ?? 0
        out.last_read_time = r.getOrNullInt64(12) ?? 0
        out.progress = r.getOrNullInt32(13) ?? 0
        out.tags = r.getOrNullText(14) ?? ""
        out
    }
}

// ===== 聚合查询映射 =====

/**
 * 阅读趋势行（COUNT/GROUP BY 查询映射）。
 * 替代 user_stats_dao.cj 里 getReadingTrend 的下标映射。
 */
public class ReadingTrendRow {
    public var date: String = ""
    public var count: Int64 = 0

    public init() {}
}

public class ReadingTrendMapper <: FromQueryResult {
    public init() {}
    public func fromRow(r: Row): Any {
        let out = ReadingTrendRow()
        out.date = r.getOrNullText(0) ?? ""
        out.count = r.getOrNullInt64(1) ?? 0
        out
    }
}

/**
 * 统计聚合行（COUNT/SUM/MAX 等标量聚合映射）。
 * 替代 user_stats_dao.cj 里 getReadCount/getGlobalTotalPagesRead 等的下标映射。
 */
public class StatsAggRow {
    public var count: Int64 = 0
    public var sum: Int64 = 0
    public var maxVal: Int64 = 0

    public init() {}
}

public class StatsAggMapper <: FromQueryResult {
    public init() {}
    public func fromRow(r: Row): Any {
        let out = StatsAggRow()
        out.count = r.getOrNullInt64(0) ?? 0
        out.sum = r.getOrNullInt64(1) ?? 0
        out.maxVal = r.getOrNullInt64(2) ?? 0
        out
    }
}

// ===== Tag Lite 行（标签轻量投影） =====

/**
 * 标签轻量行：只取 namespace/name/translation_text（3 列）。
 * 替代 tag_dao.cj listLite 的下标映射。
 */
public class TagLiteRow {
    public var id: Int64 = 0
    public var namespace: String = ""
    public var name: String = ""
    public var translationText: String = ""

    public init() {}
}

public class TagLiteRowPartial <: PartialModel {
    public init() {}
    public func columns(): Array<String> {
        ["id", "namespace", "name"]
    }
    public func fromRow(r: Row): Any {
        let out = TagLiteRow()
        out.id = r.getOrNullInt64(0) ?? 0
        out.namespace = r.getOrNullText(1) ?? ""
        out.name = r.getOrNullText(2) ?? ""
        out
    }
}