package lanlu.contexts.recommendation.infrastructure.persistence

import std.collection.*
import std.database.sql.*
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

    public init() {}
}

public class RecommendationDao {
    private static let logger = getLogger("recommendation_dao")

    private static func mapArchiveCandidateRow(rs: QueryResult): RecommendationArchiveCandidateRow {
        let row = RecommendationArchiveCandidateRow()
        row.arcid = rs.getOrNull<String>(0) ?? ""
        row.archiveInternalId = rs.getOrNull<Int64>(1) ?? 0
        row.categoryId = rs.getOrNull<Int64>(2) ?? 0
        row.title = rs.getOrNull<String>(3) ?? ""
        row.filename = rs.getOrNull<String>(4) ?? ""
        row.summary = rs.getOrNull<String>(5) ?? ""
        row.tags = rs.getOrNull<String>(6) ?? ""
        row.pagecount = rs.getOrNull<Int32>(7) ?? 0
        row.coverAssetId = rs.getOrNull<Int64>(8) ?? 0
        row.createdAt = rs.getOrNull<String>(9) ?? ""
        row.updatedAt = rs.getOrNull<String>(10) ?? ""
        row.releaseAt = rs.getOrNull<String>(11) ?? ""
        row.overlapCount = rs.getOrNull<Int32>(12) ?? 0
        return row
    }

    private static func mapTankoubonCandidateRow(rs: QueryResult): RecommendationTankoubonCandidateRow {
        let row = RecommendationTankoubonCandidateRow()
        row.tankoubonId = rs.getOrNull<String>(0) ?? ""
        row.title = rs.getOrNull<String>(1) ?? ""
        row.summary = rs.getOrNull<String>(2) ?? ""
        row.tags = rs.getOrNull<String>(3) ?? ""
        row.pagecount = rs.getOrNull<Int32>(4) ?? 0
        row.archiveCount = rs.getOrNull<Int32>(5) ?? 0
        row.coverAssetId = rs.getOrNull<Int64>(6) ?? 0
        row.assetsRaw = rs.getOrNull<String>(7) ?? "{}"
        row.categoryId = rs.getOrNull<Int64>(8) ?? 0
        row.createdAt = rs.getOrNull<String>(9) ?? ""
        row.updatedAt = rs.getOrNull<String>(10) ?? ""
        row.releaseAt = rs.getOrNull<String>(11) ?? ""
        row.overlapCount = rs.getOrNull<Int32>(12) ?? 0
        return row
    }

    private static func buildInClause(values: Array<String>): String {
        var placeholders = ""
        for (i in 0..values.size) {
            if (i > 0) { placeholders += "," }
            placeholders += "?"
        }
        return placeholders
    }

    public static func getRecentImpressionIds(
        userId: Int64,
        sessionKey: String,
        scene: String,
        itemType: String,
        lookbackHours: Int32
    ): HashSet<String> {
        let result = HashSet<String>()
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return result
            case Some(conn) =>
                try {
                    var sql = """
                        SELECT item_id
                        FROM recommendation_impressions
                        WHERE scene = ? AND item_type = ?
                          AND shown_at > CURRENT_TIMESTAMP - INTERVAL '${lookbackHours} hours'
                    """
                    let normalizedSession = sessionKey.trimAscii()
                    if (userId > 0) {
                        sql += " AND user_id = ?"
                    } else if (normalizedSession.size > 0) {
                        sql += " AND session_key = ?"
                    } else {
                        return result
                    }
                    let stmt = conn.prepareStatement(sql)
                    try {
                        stmt.set(0, scene)
                        stmt.set(1, itemType)
                        if (userId > 0) {
                            stmt.set(2, userId)
                        } else {
                            stmt.set(2, normalizedSession)
                        }
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let itemId = (rs.getOrNull<String>(0) ?? "").trimAscii()
                                if (itemId.size > 0) {
                                    result.add(itemId)
                                }
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("获取最近推荐曝光失败", ("scene", scene), ("itemType", itemType), ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
        return result
    }

    public static func getRecentUserTagWeights(userId: Int64, limit: Int32): RecommendationUserTagWeights {
        let result = RecommendationUserTagWeights()
        if (userId <= 0 || limit <= 0) {
            return result
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return result
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT tag, SUM(weight)::INT AS total_weight
                        FROM (
                            SELECT mt.tag AS tag, 2 AS weight
                            FROM user_archive_status uas
                            JOIN archives a ON a.id = uas.archive_id
                            JOIN metadata_objects mo ON mo.entity_type = 'archive' AND mo.entity_id = a.arcid
                            JOIN metadata_tags mt ON mt.metadata_id = mo.id
                            WHERE uas.user_id = ?
                              AND uas.updated_at > CURRENT_TIMESTAMP - INTERVAL '30 days'

                            UNION ALL

                            SELECT mt.tag AS tag, 3 AS weight
                            FROM user_favorites uf
                            JOIN archives a ON a.id = uf.archive_id
                            JOIN metadata_objects mo ON mo.entity_type = 'archive' AND mo.entity_id = a.arcid
                            JOIN metadata_tags mt ON mt.metadata_id = mo.id
                            WHERE uf.user_id = ?
                              AND uf.created_at > CURRENT_TIMESTAMP - INTERVAL '90 days'
                        ) tag_weights
                        GROUP BY tag
                        ORDER BY total_weight DESC, tag
                        LIMIT ?
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, userId)
                        stmt.set(2, limit)
                        let rs = stmt.query()
                        try {
                            let ordered = ArrayList<String>()
                            while (rs.next()) {
                                let tag = (rs.getOrNull<String>(0) ?? "").trimAscii()
                                let weight = rs.getOrNull<Int32>(1) ?? 0
                                if (tag.size == 0 || weight <= 0) { continue }
                                ordered.add(tag)
                                result.weights[tag] = weight
                            }
                            result.orderedTags = ordered.toArray()
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("获取用户推荐标签画像失败", ("userId", userId.toString()), ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }

        return result
    }

    public static func getDiscoverRandomArchiveCandidates(categoryId: Int64, userId: Int64, limit: Int32): Array<RecommendationArchiveCandidateRow> {
        let result = ArrayList<RecommendationArchiveCandidateRow>()
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return result.toArray()
            case Some(conn) =>
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
                    if (categoryId > 0) {
                        sql += " AND aws.category_id = ?"
                    }
                    if (userId > 0) {
                        sql += """
                             AND NOT EXISTS (
                                SELECT 1
                                FROM user_archive_status uas
                                WHERE uas.user_id = ?
                                  AND uas.archive_id = aws.id
                                  AND uas.is_new = false
                             )
                        """
                    }
                    sql += " ORDER BY RANDOM() LIMIT ?"
                    let stmt = conn.prepareStatement(sql)
                    try {
                        var index = 0
                        if (categoryId > 0) {
                            stmt.set(index, categoryId)
                            index += 1
                        }
                        if (userId > 0) {
                            stmt.set(index, userId)
                            index += 1
                        }
                        stmt.set(index, limit)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                result.add(mapArchiveCandidateRow(rs))
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("获取 discover 随机候选失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
        return result.toArray()
    }

    public static func getDiscoverArchiveCandidatesByTags(categoryId: Int64, tags: Array<String>, limit: Int32): Array<RecommendationArchiveCandidateRow> {
        let result = ArrayList<RecommendationArchiveCandidateRow>()
        if (tags.size == 0) { return result.toArray() }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return result.toArray()
            case Some(conn) =>
                try {
                    let tagInClause = buildInClause(tags)
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
                        sql += " AND aws.category_id = ?"
                    }
                    sql += """
                        GROUP BY
                            aws.arcid, aws.id, aws.category_id, aws.title, aws.filename,
                            aws.summary, aws.tags, aws.pagecount, aws.cover_asset_id,
                            aws.created_at, aws.updated_at, aws.release_at
                        ORDER BY overlap_count DESC, aws.updated_at DESC
                        LIMIT ?
                    """
                    let stmt = conn.prepareStatement(sql)
                    try {
                        var index = 0
                        for (tag in tags) {
                            stmt.set(index, tag)
                            index += 1
                        }
                        if (categoryId > 0) {
                            stmt.set(index, categoryId)
                            index += 1
                        }
                        stmt.set(index, limit)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                result.add(mapArchiveCandidateRow(rs))
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("获取 discover 标签候选失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
        return result.toArray()
    }

    public static func getArchiveRelatedCandidates(seedArchiveId: String, limit: Int32): Array<RecommendationArchiveCandidateRow> {
        let result = ArrayList<RecommendationArchiveCandidateRow>()
        let normalizedSeed = seedArchiveId.trimAscii()
        if (normalizedSeed.size == 0) { return result.toArray() }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return result.toArray()
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        WITH seed AS (
                            SELECT aws.arcid, aws.category_id
                            FROM archive_metadata_search aws
                            WHERE aws.arcid = ?
                        ),
                        seed_tags AS (
                            SELECT DISTINCT mt.tag
                            FROM metadata_objects mo
                            JOIN metadata_tags mt ON mt.metadata_id = mo.id
                            WHERE mo.entity_type = 'archive' AND mo.entity_id = ?
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
                        WHERE aws.arcid <> ?
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
                        LIMIT ?
                    """)
                    try {
                        stmt.set(0, normalizedSeed)
                        stmt.set(1, normalizedSeed)
                        stmt.set(2, normalizedSeed)
                        stmt.set(3, limit)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                result.add(mapArchiveCandidateRow(rs))
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("获取 archive_related 候选失败", ("seedArchiveId", normalizedSeed), ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
        return result.toArray()
    }

    public static func getArchiveToPrimaryTankoubonMap(archiveIds: Array<String>): HashMap<String, String> {
        let result = HashMap<String, String>()
        if (archiveIds.size == 0) { return result }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return result
            case Some(conn) =>
                try {
                    let inClause = buildInClause(archiveIds)
                    let stmt = conn.prepareStatement("""
                        SELECT DISTINCT ON (a.arcid)
                            a.arcid,
                            t.tankoubon_id
                        FROM archives a
                        JOIN tankoubon_archives ta ON ta.archive_id = a.id
                        JOIN tankoubons t ON t.id = ta.tankoubon_id
                        WHERE a.arcid IN (${inClause})
                        ORDER BY a.arcid, ta.sort_order, ta.id, t.id
                    """)
                    try {
                        for (i in 0..archiveIds.size) {
                            stmt.set(i, archiveIds[i])
                        }
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let arcid = (rs.getOrNull<String>(0) ?? "").trimAscii()
                                let tankoubonId = (rs.getOrNull<String>(1) ?? "").trimAscii()
                                if (arcid.size > 0 && tankoubonId.size > 0) {
                                    result[arcid] = tankoubonId
                                }
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("获取归档主合集映射失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
        return result
    }

    public static func getTankoubonRelatedCandidates(seedTankoubonId: String, limit: Int32): Array<RecommendationTankoubonCandidateRow> {
        let result = ArrayList<RecommendationTankoubonCandidateRow>()
        let normalizedSeed = seedTankoubonId.trimAscii()
        if (normalizedSeed.size == 0) { return result.toArray() }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return result.toArray()
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        WITH seed_tags AS (
                            SELECT DISTINCT mt.tag
                            FROM metadata_objects mo
                            JOIN metadata_tags mt ON mt.metadata_id = mo.id
                            WHERE mo.entity_type = 'tankoubon' AND mo.entity_id = ?

                            UNION

                            SELECT DISTINCT mt.tag
                            FROM tankoubons t
                            JOIN tankoubon_archives ta ON ta.tankoubon_id = t.id
                            JOIN archives a ON a.id = ta.archive_id
                            JOIN metadata_objects mo ON mo.entity_type = 'archive' AND mo.entity_id = a.arcid
                            JOIN metadata_tags mt ON mt.metadata_id = mo.id
                            WHERE t.tankoubon_id = ?
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
                            WHERE t.tankoubon_id <> ?
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
                        WHERE t.tankoubon_id <> ?
                          AND ct.overlap_count > 0
                        GROUP BY
                            t.tankoubon_id, mo.title, mo.description, ct.tags, ct.category_id,
                            mo.created_at, mo.updated_at, mo.release_at, ct.overlap_count
                        ORDER BY ct.overlap_count DESC, mo.updated_at DESC
                        LIMIT ?
                    """)
                    try {
                        stmt.set(0, normalizedSeed)
                        stmt.set(1, normalizedSeed)
                        stmt.set(2, normalizedSeed)
                        stmt.set(3, normalizedSeed)
                        stmt.set(4, limit)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                result.add(mapTankoubonCandidateRow(rs))
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("获取 tankoubon_related 候选失败", ("seedTankoubonId", normalizedSeed), ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
        return result.toArray()
    }

    public static func insertImpressions(rows: Array<RecommendationImpressionWriteRow>): Bool {
        if (rows.size == 0) { return true }
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return false
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO recommendation_impressions (
                            user_id, session_key, scene, seed_entity_type, seed_entity_id,
                            item_type, item_id, position
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """)
                    try {
                        for (row in rows) {
                            stmt.set(0, row.userId)
                            stmt.set(1, row.sessionKey)
                            stmt.set(2, row.scene)
                            stmt.set(3, row.seedEntityType)
                            stmt.set(4, row.seedEntityId)
                            stmt.set(5, row.itemType)
                            stmt.set(6, row.itemId)
                            stmt.set(7, row.position)
                            let _ = stmt.update()
                        }
                    } finally {
                        stmt.close()
                    }
                    return true
                } catch (e: Exception) {
                    logger.error("写入推荐曝光失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
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
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return false
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        INSERT INTO recommendation_interactions (
                            user_id, session_key, scene, seed_entity_type, seed_entity_id,
                            item_type, item_id, interaction_type
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """)
                    try {
                        stmt.set(0, userId)
                        stmt.set(1, sessionKey)
                        stmt.set(2, scene)
                        stmt.set(3, seedEntityType)
                        stmt.set(4, seedEntityId)
                        stmt.set(5, itemType)
                        stmt.set(6, itemId)
                        stmt.set(7, interactionType)
                        let _ = stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    logger.error("写入推荐交互失败", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }
}
