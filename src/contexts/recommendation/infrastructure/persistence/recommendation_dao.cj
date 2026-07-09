package lanlu.contexts.recommendation.infrastructure.persistence

import std.collection.*
import csorm.*
import lanlu.contexts.recommendation.domain.*
import lanlu.shared.config.*
import lanlu.shared.utils.*

public class RecommendationArchiveCandidateRow {
    public var arcid: String = ""
    public var archiveInternalId: Int64 = 0
    public var categoryId: Int64 = 0
    public var title: String = ""
    public var filename: String = ""
    public var summary: String = ""
    public var tags: String = ""
    public var pagecount: Int32 = 0
    public var coverAssetId: Int64 = 0
    public var createdAt: String = ""
    public var updatedAt: String = ""
    public var releaseAt: String = ""
    public var overlapCount: Int32 = 0

    public init() {}
}

public class RecommendationTankoubonCandidateRow {
    public var tankoubonId: String = ""
    public var title: String = ""
    public var summary: String = ""
    public var tags: String = ""
    public var pagecount: Int32 = 0
    public var archiveCount: Int32 = 0
    public var coverAssetId: Int64 = 0
    public var assetsRaw: String = "{}"
    public var categoryId: Int64 = 0
    public var createdAt: String = ""
    public var updatedAt: String = ""
    public var releaseAt: String = ""
    public var overlapCount: Int32 = 0

    public init() {}
}

public class RecommendationUserTagWeights {
    public var orderedTags: Array<String> = Array<String>()
    public var weights: HashMap<String, Int32> = HashMap<String, Int32>()

    public init() {}
}

public class RecommendationImpressionWriteRow {
    public var userId: Int64 = 0
    public var sessionKey: String = ""
    public var scene: String = ""
    public var seedEntityType: String = ""
    public var seedEntityId: String = ""
    public var itemType: String = ""
    public var itemId: String = ""
    public var position: Int32 = 0

    public mut prop seedType: RecommendationItemType {
        get() {
            RecommendationItemType.fromDb(seedEntityType)
        }
        set(value) {
            seedEntityType = value.toDb()
        }
    }

    public mut prop recommendationItemType: RecommendationItemType {
        get() {
            RecommendationItemType.fromDb(itemType)
        }
        set(value) {
            itemType = value.toDb()
        }
    }

    public init() {}
}

public class RecommendationDao {
    private static let logger = getLogger("recommendation_dao")

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

    private static func mapTankoubonCandidateRow(row: Row): RecommendationTankoubonCandidateRow {
        let r = RecommendationTankoubonCandidateRow()
        r.tankoubonId = row.getOrNullText(0) ?? ""
        r.title = row.getOrNullText(1) ?? ""
        r.summary = row.getOrNullText(2) ?? ""
        r.tags = row.getOrNullText(3) ?? ""
        r.pagecount = row.getOrNullInt32(4) ?? 0
        r.archiveCount = row.getOrNullInt32(5) ?? 0
        r.coverAssetId = row.getOrNullInt64(6) ?? 0
        r.assetsRaw = row.getOrNullText(7) ?? "{}"
        r.categoryId = row.getOrNullInt64(8) ?? 0
        r.createdAt = row.getOrNullText(9) ?? ""
        r.updatedAt = row.getOrNullText(10) ?? ""
        r.releaseAt = row.getOrNullText(11) ?? ""
        r.overlapCount = row.getOrNullInt32(12) ?? 0
        return r
    }

    public static func getRecentImpressionIds(
        userId: Int64,
        sessionKey: String,
        scene: String,
        itemType: String,
        lookbackHours: Int32
    ): HashSet<String> {
        let result = HashSet<String>()
        let normalizedSession = sessionKey.trimAscii()
        if (userId <= 0 && normalizedSession.size == 0) {
            return result
        }
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    var sql = """
                        SELECT item_id
                        FROM recommendation_impressions
                        WHERE scene = $1 AND item_type = $2
                          AND shown_at > CURRENT_TIMESTAMP - ($3 * INTERVAL '1 hour')
                    """
                    var params = ArrayList<Value>()
                    params.add(vtext(scene))
                    params.add(vtext(itemType))
                    params.add(vint(Int64(lookbackHours)))
                    if (userId > 0) {
                        sql += " AND user_id = $4"
                        params.add(vint(userId))
                    } else if (normalizedSession.size > 0) {
                        sql += " AND session_key = $4"
                        params.add(vtext(normalizedSession))
                    } else {
                        return result
                    }
                    let rows = db.raw<String>(sql, params.toArray(), { row => row.getOrNullText(0) ?? "" })
                    for (itemId in rows) {
                        let trimmed = itemId.trimAscii()
                        if (trimmed.size > 0) {
                            result.add(trimmed)
                        }
                    }
                } catch (e: Exception) {
                    logger.error("获取最近推荐曝光失败", ("scene", scene), ("itemType", itemType), ("error", e.message))
                }
            case None => return result
        }
        return result
    }

    public static func clearImpressions(userId: Int64, sessionKey: String, scene: String): Bool {
        let normalizedSession = sessionKey.trimAscii()
        if (userId <= 0 && normalizedSession.size == 0) {
            return false
        }
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    var sql = "DELETE FROM recommendation_impressions WHERE scene = $1"
                    var params = ArrayList<Value>()
                    params.add(vtext(scene))
                    if (userId > 0) {
                        sql += " AND user_id = $2"
                        params.add(vint(userId))
                    } else if (normalizedSession.size > 0) {
                        sql += " AND session_key = $2"
                        params.add(vtext(normalizedSession))
                    } else {
                        return false
                    }
                    let _ = db.execRaw(sql, params.toArray())
                    return true
                } catch (e: Exception) {
                    logger.error("清理推荐曝光失败", ("scene", scene), ("error", e.message))
                    return false
                }
            case None => return false
        }
    }

    public static func getRecentUserTagWeights(userId: Int64, limit: Int32): RecommendationUserTagWeights {
        let result = RecommendationUserTagWeights()
        if (userId <= 0 || limit <= 0) {
            return result
        }

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = """
                        SELECT tag, SUM(weight)::INT AS total_weight
                        FROM (
                            SELECT mt.tag AS tag, 2 AS weight
                            FROM user_archive_status uas
                            JOIN archives a ON a.id = uas.archive_id
                            JOIN metadata_objects mo ON mo.entity_type = 'archive' AND mo.entity_id = a.arcid
                            JOIN metadata_tags mt ON mt.metadata_id = mo.id
                            WHERE uas.user_id = $1
                              AND uas.updated_at > CURRENT_TIMESTAMP - INTERVAL '30 days'

                            UNION ALL

                            SELECT mt.tag AS tag, 3 AS weight
                            FROM user_favorites uf
                            JOIN archives a ON a.id = uf.archive_id
                            JOIN metadata_objects mo ON mo.entity_type = 'archive' AND mo.entity_id = a.arcid
                            JOIN metadata_tags mt ON mt.metadata_id = mo.id
                            WHERE uf.user_id = $2
                              AND uf.created_at > CURRENT_TIMESTAMP - INTERVAL '90 days'
                        ) tag_weights
                        GROUP BY tag
                        ORDER BY total_weight DESC, tag
                        LIMIT $3
                    """
                    let params: Array<Value> = [vint(userId), vint(userId), vint(Int64(limit))]
                    let rows = db.raw<(String, Int32)>(sql, params, { row =>
                        (row.getOrNullText(0) ?? "", row.getOrNullInt32(1) ?? 0)
                    })
                    let ordered = ArrayList<String>()
                    for (pair in rows) {
                        let (tag, weight) = pair
                        let trimmed = tag.trimAscii()
                        if (trimmed.size == 0 || weight <= 0) { continue }
                        ordered.add(trimmed)
                        result.weights[trimmed] = weight
                    }
                    result.orderedTags = ordered.toArray()
                } catch (e: Exception) {
                    logger.error("获取用户推荐标签画像失败", ("userId", userId.toString()), ("error", e.message))
                }
            case None => return result
        }

        return result
    }

    public static func getDiscoverRandomArchiveCandidates(categoryId: Int64, userId: Int64, limit: Int32): Array<RecommendationArchiveCandidateRow> {
        let result = ArrayList<RecommendationArchiveCandidateRow>()
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    var sql = """
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
                            COALESCE(aws.created_at::TEXT, ''),
                            COALESCE(aws.updated_at::TEXT, ''),
                            COALESCE(aws.release_at::TEXT, ''),
                            0::INT AS overlap_count
                        FROM archive_metadata_search aws
                        WHERE EXISTS (
                            SELECT 1 FROM categories c
                            WHERE c.id = aws.category_id AND c.enabled = true
                        )
                    """
                    var params = ArrayList<Value>()
                    var idx = 0
                    if (categoryId > 0) {
                        idx += 1
                        sql += " AND aws.category_id = ${'$'}${idx.toString()}"
                        params.add(vint(categoryId))
                    }
                    if (userId > 0) {
                        idx += 1
                        sql += """
                             AND NOT EXISTS (
                                SELECT 1
                                FROM user_archive_status uas
                                WHERE uas.user_id = ${'$'}${idx.toString()}
                                  AND uas.archive_id = aws.id
                                  AND uas.is_new = false
                             )
                        """
                        params.add(vint(userId))
                    }
                    idx += 1
                    sql += " ORDER BY RANDOM() LIMIT ${'$'}${idx.toString()}"
                    params.add(vint(Int64(limit)))
                    let rows = db.raw<RecommendationArchiveCandidateRow>(sql, params.toArray(), { row => mapArchiveCandidateRow(row) })
                    for (r in rows) {
                        result.add(r)
                    }
                } catch (e: Exception) {
                    logger.error("获取 discover 随机候选失败", ("error", e.message))
                }
            case None => return result.toArray()
        }
        return result.toArray()
    }

    public static func getDiscoverArchiveCandidatesByTags(categoryId: Int64, tags: Array<String>, limit: Int32): Array<RecommendationArchiveCandidateRow> {
        let result = ArrayList<RecommendationArchiveCandidateRow>()
        if (tags.size == 0) { return result.toArray() }

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    var params = ArrayList<Value>()
                    var inList = StringBuilder()
                    for (i in 0..tags.size) {
                        if (i > 0) { inList.append(",") }
                        params.add(vtext(tags[i]))
                        inList.append("${'$'}${(i + 1).toString()}")
                    }
                    let tagInClause = inList.toString()
                    var idx = tags.size
                    var sql = """
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
                            COALESCE(aws.created_at::TEXT, ''),
                            COALESCE(aws.updated_at::TEXT, ''),
                            COALESCE(aws.release_at::TEXT, ''),
                            COUNT(DISTINCT mt.tag)::INT AS overlap_count
                        FROM archive_metadata_search aws
                        JOIN metadata_objects mo ON mo.entity_type = 'archive' AND mo.entity_id = aws.arcid
                        JOIN metadata_tags mt ON mt.metadata_id = mo.id
                        WHERE mt.tag IN (${tagInClause})
                    """
                    if (categoryId > 0) {
                        idx += 1
                        sql += " AND aws.category_id = ${'$'}${idx.toString()}"
                        params.add(vint(categoryId))
                    }
                    idx += 1
                    sql += """
                        GROUP BY
                            aws.arcid, aws.id, aws.category_id, aws.title, aws.filename,
                            aws.summary, aws.tags, aws.pagecount, aws.cover_asset_id,
                            aws.created_at, aws.updated_at, aws.release_at
                        ORDER BY overlap_count DESC, aws.updated_at DESC
                        LIMIT ${'$'}${idx.toString()}
                    """
                    params.add(vint(Int64(limit)))
                    let rows = db.raw<RecommendationArchiveCandidateRow>(sql, params.toArray(), { row => mapArchiveCandidateRow(row) })
                    for (r in rows) {
                        result.add(r)
                    }
                } catch (e: Exception) {
                    logger.error("获取 discover 标签候选失败", ("error", e.message))
                }
            case None => return result.toArray()
        }
        return result.toArray()
    }

    public static func getArchiveRelatedCandidates(seedArchiveId: String, limit: Int32): Array<RecommendationArchiveCandidateRow> {
        let result = ArrayList<RecommendationArchiveCandidateRow>()
        let normalizedSeed = seedArchiveId.trimAscii()
        if (normalizedSeed.size == 0) { return result.toArray() }

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = """
                        WITH seed AS (
                            SELECT aws.arcid, aws.category_id
                            FROM archive_metadata_search aws
                            WHERE aws.arcid = $1
                        ),
                        seed_tags AS (
                            SELECT DISTINCT mt.tag
                            FROM metadata_objects mo
                            JOIN metadata_tags mt ON mt.metadata_id = mo.id
                            WHERE mo.entity_type = 'archive' AND mo.entity_id = $2
                        )
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
                            COALESCE(aws.created_at::TEXT, ''),
                            COALESCE(aws.updated_at::TEXT, ''),
                            COALESCE(aws.release_at::TEXT, ''),
                            COUNT(DISTINCT mt.tag)::INT AS overlap_count
                        FROM archive_metadata_search aws
                        JOIN metadata_objects mo ON mo.entity_type = 'archive' AND mo.entity_id = aws.arcid
                        JOIN metadata_tags mt ON mt.metadata_id = mo.id
                        CROSS JOIN seed s
                        WHERE aws.arcid <> $3
                          AND EXISTS (
                              SELECT 1
                              FROM seed_tags st
                              WHERE st.tag = mt.tag
                          )
                        GROUP BY
                            aws.arcid, aws.id, aws.category_id, aws.title, aws.filename,
                            aws.summary, aws.tags, aws.pagecount, aws.cover_asset_id,
                            aws.created_at, aws.updated_at, aws.release_at,
                            s.category_id
                        ORDER BY
                            CASE WHEN aws.category_id = s.category_id THEN 1 ELSE 0 END DESC,
                            overlap_count DESC,
                            aws.updated_at DESC
                        LIMIT $4
                    """
                    let params: Array<Value> = [
                        vtext(normalizedSeed),
                        vtext(normalizedSeed),
                        vtext(normalizedSeed),
                        vint(Int64(limit))
                    ]
                    let rows = db.raw<RecommendationArchiveCandidateRow>(sql, params, { row => mapArchiveCandidateRow(row) })
                    for (r in rows) {
                        result.add(r)
                    }
                } catch (e: Exception) {
                    logger.error("获取 archive_related 候选失败", ("seedArchiveId", normalizedSeed), ("error", e.message))
                }
            case None => return result.toArray()
        }
        return result.toArray()
    }

    public static func getTagBasedCandidates(tags: Array<String>, limit: Int32): Array<RecommendationArchiveCandidateRow> {
        let result = ArrayList<RecommendationArchiveCandidateRow>()
        if (tags.size == 0 || limit <= 0) { return result.toArray() }
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = """
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
                            COALESCE(aws.created_at::TEXT, ''),
                            COALESCE(aws.updated_at::TEXT, ''),
                            COALESCE(aws.release_at::TEXT, ''),
                            COUNT(DISTINCT mt.tag)::INT AS overlap_count
                        FROM archive_metadata_search aws
                        JOIN metadata_objects mo ON mo.entity_type = 'archive' AND mo.entity_id = aws.arcid
                        JOIN metadata_tags mt ON mt.metadata_id = mo.id
                        WHERE mt.tag = ANY($1::text[])
                        GROUP BY
                            aws.arcid, aws.id, aws.category_id, aws.title, aws.filename,
                            aws.summary, aws.tags, aws.pagecount, aws.cover_asset_id,
                            aws.created_at, aws.updated_at, aws.release_at
                        ORDER BY overlap_count DESC, aws.updated_at DESC
                        LIMIT $2
                    """
                    let params: Array<Value> = [textArray(tags), vint(Int64(limit))]
                    let rows = db.raw<RecommendationArchiveCandidateRow>(sql, params, { row => mapArchiveCandidateRow(row) })
                    for (r in rows) {
                        result.add(r)
                    }
                } catch (e: Exception) {
                    logger.error("获取 tag-based 候选失败", ("error", e.message))
                }
            case None => return result.toArray()
        }
        return result.toArray()
    }

    public static func getArchiveToPrimaryTankoubonMap(archiveIds: Array<String>): HashMap<String, String> {
        let result = HashMap<String, String>()
        if (archiveIds.size == 0) { return result }

        let sql = """
            SELECT DISTINCT ON (a.arcid)
                a.arcid,
                t.tankoubon_id
            FROM archives a
            JOIN tankoubon_archives ta ON ta.archive_id = a.id
            JOIN tankoubons t ON t.id = ta.tankoubon_id
            WHERE a.arcid = ANY($1::text[])
            ORDER BY a.arcid, ta.sort_order, ta.id, t.id
        """
        let params: Array<Value> = [textArray(archiveIds)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<(String, String)>(sql, params, { row =>
                        (row.getOrNullText(0) ?? "", row.getOrNullText(1) ?? "")
                    })
                    for (pair in rows) {
                        let (arcid, tankoubonId) = pair
                        let a = arcid.trimAscii()
                        let t = tankoubonId.trimAscii()
                        if (a.size > 0 && t.size > 0) {
                            result[a] = t
                        }
                    }
                } catch (e: Exception) {
                    logger.error("获取归档主合集映射失败", ("error", e.message))
                }
            case None => return result
        }
        return result
    }

    public static func getTankoubonRelatedCandidates(seedTankoubonId: String, limit: Int32): Array<RecommendationTankoubonCandidateRow> {
        let result = ArrayList<RecommendationTankoubonCandidateRow>()
        let normalizedSeed = seedTankoubonId.trimAscii()
        if (normalizedSeed.size == 0) { return result.toArray() }

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = """
                        WITH seed_tags AS (
                            SELECT DISTINCT mt.tag
                            FROM metadata_objects mo
                            JOIN metadata_tags mt ON mt.metadata_id = mo.id
                            WHERE mo.entity_type = 'tankoubon' AND mo.entity_id = $1

                            UNION

                            SELECT DISTINCT mt.tag
                            FROM tankoubons t
                            JOIN tankoubon_archives ta ON ta.tankoubon_id = t.id
                            JOIN archives a ON a.id = ta.archive_id
                            JOIN metadata_objects mo ON mo.entity_type = 'archive' AND mo.entity_id = a.arcid
                            JOIN metadata_tags mt ON mt.metadata_id = mo.id
                            WHERE t.tankoubon_id = $2
                        ),
                        candidate_tags AS (
                            SELECT
                                t.tankoubon_id,
                                COALESCE(string_agg(DISTINCT mt.tag, ','), '') AS tags,
                                COUNT(DISTINCT CASE WHEN mt.tag IN (SELECT tag FROM seed_tags) THEN mt.tag END)::INT AS overlap_count,
                                MIN(a.category_id) AS category_id
                            FROM tankoubons t
                            JOIN tankoubon_archives ta ON ta.tankoubon_id = t.id
                            JOIN archives a ON a.id = ta.archive_id
                            LEFT JOIN metadata_objects mo_archive ON mo_archive.entity_type = 'archive' AND mo_archive.entity_id = a.arcid
                            LEFT JOIN metadata_tags mt ON mt.metadata_id = mo_archive.id
                            WHERE t.tankoubon_id <> $3
                            GROUP BY t.tankoubon_id
                        )
                        SELECT
                            t.tankoubon_id,
                            COALESCE(mo.title, '') AS title,
                            COALESCE(mo.description, '') AS summary,
                            COALESCE(ct.tags, '') AS tags,
                            COALESCE(SUM(a.pagecount), 0)::INT AS pagecount,
                            COUNT(a.id)::INT AS archive_count,
                            COALESCE(MAX(CASE WHEN ma.slot = 'cover' THEN ma.asset_id ELSE 0 END), 0) AS cover_asset_id,
                            COALESCE(
                                CAST(
                                    COALESCE(
                                        jsonb_object_agg(ma.slot, to_jsonb(ma.asset_id))
                                            FILTER (WHERE ma.asset_id > 0),
                                        '{}'::jsonb
                                    ) AS TEXT
                                ),
                                '{}'
                            ) AS assets_raw,
                            COALESCE(ct.category_id, 0) AS category_id,
                            COALESCE(mo.created_at::TEXT, '') AS created_at,
                            COALESCE(mo.updated_at::TEXT, '') AS updated_at,
                            COALESCE(mo.release_at::TEXT, '') AS release_at,
                            COALESCE(ct.overlap_count, 0) AS overlap_count
                        FROM tankoubons t
                        LEFT JOIN metadata_objects mo
                               ON mo.entity_type = 'tankoubon'
                              AND mo.entity_id = t.tankoubon_id
                        JOIN tankoubon_archives ta ON ta.tankoubon_id = t.id
                        JOIN archives a ON a.id = ta.archive_id
                        LEFT JOIN metadata_assets ma ON ma.metadata_id = mo.id
                        JOIN candidate_tags ct ON ct.tankoubon_id = t.tankoubon_id
                        WHERE t.tankoubon_id <> $4
                          AND ct.overlap_count > 0
                        GROUP BY
                            t.tankoubon_id, mo.title, mo.description, ct.tags, ct.category_id,
                            mo.created_at, mo.updated_at, mo.release_at, ct.overlap_count
                        ORDER BY ct.overlap_count DESC, mo.updated_at DESC
                        LIMIT $5
                    """
                    let params: Array<Value> = [
                        vtext(normalizedSeed),
                        vtext(normalizedSeed),
                        vtext(normalizedSeed),
                        vtext(normalizedSeed),
                        vint(Int64(limit))
                    ]
                    let rows = db.raw<RecommendationTankoubonCandidateRow>(sql, params, { row => mapTankoubonCandidateRow(row) })
                    for (r in rows) {
                        result.add(r)
                    }
                } catch (e: Exception) {
                    logger.error("获取 tankoubon_related 候选失败", ("seedTankoubonId", normalizedSeed), ("error", e.message))
                }
            case None => return result.toArray()
        }
        return result.toArray()
    }

    public static func insertImpressions(rows: Array<RecommendationImpressionWriteRow>): Bool {
        if (rows.size == 0) { return true }
        let sql = """
            INSERT INTO recommendation_impressions (
                user_id, session_key, scene, seed_entity_type, seed_entity_id,
                item_type, item_id, position
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    var affected: Int64 = 0
                    for (row in rows) {
                        let params: Array<Value> = [
                            vint(row.userId),
                            vtext(row.sessionKey),
                            vtext(row.scene),
                            vtext(row.seedEntityType),
                            vtext(row.seedEntityId),
                            vtext(row.itemType),
                            vtext(row.itemId),
                            vint(Int64(row.position))
                        ]
                        affected += db.execRaw(sql, params)
                    }
                    return affected >= Int64(rows.size)
                } catch (e: Exception) {
                    logger.error("写入推荐曝光失败", ("error", e.message))
                    return false
                }
            case None => return false
        }
    }

    public static func insertInteraction(
        userId: Int64,
        sessionKey: String,
        scene: String,
        seedEntityType: String,
        seedEntityId: String,
        itemType: String,
        itemId: String,
        interactionType: String
    ): Bool {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let sql = """
                        INSERT INTO recommendation_interactions (
                            user_id, session_key, scene, seed_entity_type, seed_entity_id,
                            item_type, item_id, interaction_type
                        )
                        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                    """
                    let params: Array<Value> = [
                        vint(userId),
                        vtext(sessionKey),
                        vtext(scene),
                        vtext(seedEntityType),
                        vtext(seedEntityId),
                        vtext(itemType),
                        vtext(itemId),
                        vtext(interactionType)
                    ]
                    let _ = db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    logger.error("写入推荐交互失败", ("error", e.message))
                    return false
                }
            case None => return false
        }
    }
}