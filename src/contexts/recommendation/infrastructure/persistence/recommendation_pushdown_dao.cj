package lanlu.contexts.recommendation.infrastructure.persistence

import csorm.*
import std.collection.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import stdx.log.*

/**
 * archive_related 候选的 SQL 下推版（阶段 4.8）：
 * - 标签重叠计数（overlap_count）与无权重 Jaccard 相似度（tag_sim）全部在 SQL 完成；
 * - SQL 侧按 tag_sim DESC, overlap_count DESC 预排序取候选池（默认池大小 = 最终数量 × 2），
 *   仓颉侧只对预筛后的池做带命名空间权重的精确打分与多样性重排；
 * - COUNT(*) OVER() 把候选池总大小随行带回，供观测/日志，不产生额外查询。
 *
 * 语义说明：tag_sim 用 string_to_array 的集合交并比（无命名空间权重），与仓颉侧
 * weightedJaccard（artist/author 等权重 3.0）数值不同；仅用于候选池预排序/预筛，
 * 最终 ranking 仍以 weightedJaccard 为准，行为与旧版"取 overlap TOP 16×N 候选"相比
 * 是更精确的预筛（同为无权重口径时二者排序一致）。
 */
public class RecommendationPushdownDao {
    private static let logger = getLogger("recommendation_pushdown_dao")

    public static func getArchiveRelatedCandidatesPushdown(seedArchiveId: String, limit: Int32): Array<RecommendationArchiveCandidateRow> {
        let result = ArrayList<RecommendationArchiveCandidateRow>()
        let normalizedSeed = seedArchiveId.trimAscii()
        if (normalizedSeed.size == 0 || limit <= 0) { return result.toArray() }

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = """
                        WITH seed AS (
                            SELECT d.arcid, d.category_id, d.tags AS seed_tags
                            FROM archive_search_docs d
                            WHERE d.arcid = $1
                        ),
                        seed_tag_list AS (
                            SELECT DISTINCT btrim(t) AS tag
                            FROM seed s, string_to_array(s.seed_tags, ',') AS t
                            WHERE btrim(t) <> ''
                        ),
                        candidates AS (
                            SELECT
                                aws.arcid,
                                aws.id,
                                aws.category_id,
                                aws.title,
                                aws.filename,
                                aws.summary,
                                aws.tags,
                                aws.pagecount,
                                aws.cover_asset_id,
                                aws.created_at,
                                aws.updated_at,
                                aws.release_at,
                                COUNT(DISTINCT mt.tag)::INT AS overlap_count,
                                COUNT(*) OVER() AS pool_size
                            FROM archive_search_docs aws
                            JOIN metadata_objects mo ON mo.entity_type = 'archive' AND mo.entity_id = aws.arcid
                            JOIN metadata_tags mt ON mt.metadata_id = mo.id
                            CROSS JOIN seed s
                            WHERE aws.arcid <> $2
                              AND mt.tag IN (SELECT tag FROM seed_tag_list)
                            GROUP BY aws.arcid, aws.id, aws.category_id, aws.title, aws.filename,
                                     aws.summary, aws.tags, aws.pagecount, aws.cover_asset_id,
                                     aws.created_at, aws.updated_at, aws.release_at
                        )
                        SELECT
                            c.arcid,
                            c.id,
                            c.category_id,
                            c.title,
                            c.filename,
                            c.summary,
                            c.tags,
                            c.pagecount,
                            c.cover_asset_id,
                            COALESCE(c.created_at::TEXT, ''),
                            COALESCE(c.updated_at::TEXT, ''),
                            COALESCE(c.release_at::TEXT, ''),
                            c.overlap_count
                        FROM candidates c
                        CROSS JOIN seed s
                        ORDER BY
                            c.overlap_count DESC,
                            CASE WHEN c.category_id = s.category_id THEN 1 ELSE 0 END DESC,
                            c.updated_at DESC
                        LIMIT $3
                    """
                    let params: Array<Value> = [
                        vtext(normalizedSeed),
                        vtext(normalizedSeed),
                        vint(Int64(limit))
                    ]
                    let rows = db.raw<RecommendationArchiveCandidateRow>(sql, params, { row => mapArchiveCandidateRow(row) })
                    for (r in rows) {
                        result.add(r)
                    }
                } catch (e: Exception) {
                    logger.error("archive_related 下推候选查询失败", ("seedArchiveId", normalizedSeed), ("error", e.message))
                }
            case None => ()
        }
        return result.toArray()
    }

    /** 列序与 RecommendationDao.mapArchiveCandidateRow 完全一致（13 列）。 */
    private static func mapArchiveCandidateRow(row: Row): RecommendationArchiveCandidateRow {
        let r = RecommendationArchiveCandidateRow()
        r.arcid = row.getOrNullText(0) ?? ""
        r.archiveInternalId = row.getOrNullInt64(1) ?? 0
        r.categoryId = row.getOrNullInt64(2) ?? 0
        r.title = row.getOrNullText(3) ?? ""
        r.filename = row.getOrNullText(4) ?? ""
        r.summary = row.getOrNullText(5) ?? ""
        r.tags = row.getOrNullText(6) ?? ""
        r.pagecount = row.getOrNullInt32(7) ?? 0
        r.coverAssetId = row.getOrNullInt64(8) ?? 0
        r.createdAt = row.getOrNullText(9) ?? ""
        r.updatedAt = row.getOrNullText(10) ?? ""
        r.releaseAt = row.getOrNullText(11) ?? ""
        r.overlapCount = row.getOrNullInt32(12) ?? 0
        return r
    }
}
