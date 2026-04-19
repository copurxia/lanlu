package lanlu.contexts.tag.infrastructure.persistence

import std.database.sql.*
import lanlu.shared.config.*
import lanlu.shared.utils.*
import lanlu.infrastructure.kv.*
import std.collection.*
import stdx.log.*
import std.io.{ByteBuffer, readToEnd}
import stdx.encoding.json.stream.*

/**
 * 标签翻译数据结构
 */
public class TagTranslation {
    public var text: String = ""
    public var intro: String = ""

    public init() {}

    public init(text: String, intro: String) {
        this.text = text
        this.intro = intro
    }
}

/**
 * 标签数据结构（新版：支持 JSONB translations）
 */
public class TagData {
    public var id: Int64 = 0
    public var namespace: String = ""
    public var name: String = ""
    public var translations: HashMap<String, TagTranslation> = HashMap<String, TagTranslation>()
    public var links: String = ""
    public var iconAssetId: Int64 = 0
    public var backgroundAssetId: Int64 = 0
    public var created_at: String = ""
    public var updated_at: String = ""

    public init() {}

    /**
     * 获取完整标签名（namespace:name 格式）
     */
    public func getFullName(): String {
        if (namespace.size > 0) {
            return "${namespace}:${name}"
        }
        return name
    }

    /**
     * 获取指定语言的翻译
     */
    public func getTranslation(lang: String): ?TagTranslation {
        return translations.get(lang)
    }

    /**
     * 获取指定语言的翻译文本，如果不存在则返回原始名称
     */
    public func getTranslatedText(lang: String): String {
        match (translations.get(lang)) {
            case Some(t) => if (t.text.size > 0) { return t.text }
            case None => ()
        }
        return name
    }
}

/**
 * 轻量标签结构（用于分页/批处理场景，避免解析完整 translations JSON）
 */
public class TagLiteData {
    public var id: Int64 = 0
    public var namespace: String = ""
    public var name: String = ""
    // 指定语言的翻译文本（不存在则为空字符串）
    public var translationText: String = ""

    public init() {}
}

/**
 * 标签数据访问对象
 */
public class TagDao {
    private static let logger = getLogger("tag_dao")
    private static let translationSearchCacheTtlSeconds: Int64 = 6 * 60 * 60

    private static func extensionInstalled(conn: Connection, extensionName: String): Bool {
        let stmt = conn.prepareStatement("SELECT 1 FROM pg_extension WHERE extname = ? LIMIT 1")
        try {
            stmt.set(0, extensionName)
            let rs = stmt.query()
            try {
                return rs.next()
            } finally {
                rs.close()
            }
        } catch (_: Exception) {
            return false
        } finally {
            stmt.close()
        }
    }

    private static func functionExists(conn: Connection, functionName: String): Bool {
        let stmt = conn.prepareStatement("SELECT 1 FROM pg_proc WHERE proname = ? LIMIT 1")
        try {
            stmt.set(0, functionName)
            let rs = stmt.query()
            try {
                return rs.next()
            } finally {
                rs.close()
            }
        } catch (_: Exception) {
            return false
        } finally {
            stmt.close()
        }
    }

    private static func getUnaccentFunction(conn: Connection): String {
        if (functionExists(conn, "lanlu_immutable_unaccent")) {
            return "lanlu_immutable_unaccent"
        }
        if (extensionInstalled(conn, "unaccent")) {
            return "unaccent"
        }
        return ""
    }

    private static func wrapSearchExpr(expr: String, unaccentFunction: String): String {
        if (unaccentFunction.size > 0) {
            return "${unaccentFunction}(COALESCE(${expr}, ''))"
        }
        return "COALESCE(${expr}, '')"
    }

    /**
     * 解析 namespace:name 格式的标签
     */
    public static func parseTagName(fullName: String): (String, String) {
        let parts = fullName.split(":", 2)
        if (parts.size >= 2) {
            return (parts[0], parts[1])
        }
        return ("", fullName)
    }

    /**
     * 规范化标签字符串为 canonical tag：
     * - trim 前后空白
     * - namespace:name 仅按首个冒号拆分
     * - 去掉空 namespace / 空 name
     */
    public static func canonicalizeTag(fullName: String): String {
        let trimmed = fullName.trimAscii()
        if (trimmed.size == 0) {
            return ""
        }

        let (rawNamespace, rawName) = parseTagName(trimmed)
        let namespace = rawNamespace.trimAscii()
        let name = rawName.trimAscii()
        if (name.size == 0) {
            return ""
        }
        if (namespace.size > 0) {
            return "${namespace}:${name}"
        }
        return name
    }

    /**
     * 规范化标签数组：
     * - canonicalize
     * - 去重
     * - 保持首次出现顺序
     */
    public static func normalizeTags(tags: Array<String>): Array<String> {
        let out = ArrayList<String>()
        let seen = HashSet<String>()
        for (rawTag in tags) {
            let canonical = canonicalizeTag(rawTag)
            if (canonical.size == 0 || seen.contains(canonical)) {
                continue
            }
            seen.add(canonical)
            out.add(canonical)
        }
        return out.toArray()
    }

    /**
     * 判断标签是否属于 source 命名空间（source:xxx）
     */
    public static func isSourceTag(fullName: String): Bool {
        let trimmed = fullName.trimAscii()
        if (trimmed.size == 0) { return false }
        if (trimmed.startsWith("source:")) { return true }
        let (namespace, _) = parseTagName(trimmed)
        return namespace == "source"
    }

    /**
     * 根据 namespace 和 name 获取或创建标签
     */
    public static func getOrCreate(namespace: String, name: String): Int64 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return 0
            case Some(conn) =>
                try {
                    return getOrCreateTagInternal(conn, namespace, name)
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }

    /**
     * 内部方法：获取或创建标签（使用已有连接）
     */
    private static func getOrCreateTagInternal(conn: Connection, namespace: String, name: String): Int64 {
        let stmt = conn.prepareStatement("SELECT id FROM tags WHERE namespace = ? AND name = ? LIMIT 1")
        try {
            stmt.set(0, namespace)
            stmt.set(1, name)
            let result = stmt.query()
            try {
                if (result.next()) {
                    return result.getOrNull<Int64>(0) ?? 0
                }
            } finally {
                result.close()
            }
        } finally {
            stmt.close()
        }

        let insertStmt = conn.prepareStatement("""
            INSERT INTO tags (namespace, name)
            SELECT ?, ?
            WHERE NOT EXISTS (
                SELECT 1 FROM tags WHERE namespace = ? AND name = ?
            )
        """)
        try {
            insertStmt.set(0, namespace)
            insertStmt.set(1, name)
            insertStmt.set(2, namespace)
            insertStmt.set(3, name)
            insertStmt.update()
        } catch (_: Exception) {
            // Concurrent inserts may race; reload the row below.
        } finally {
            insertStmt.close()
        }

        let reloadStmt = conn.prepareStatement("SELECT id FROM tags WHERE namespace = ? AND name = ? LIMIT 1")
        try {
            reloadStmt.set(0, namespace)
            reloadStmt.set(1, name)
            let result = reloadStmt.query()
            try {
                if (result.next()) {
                    return result.getOrNull<Int64>(0) ?? 0
                }
            } finally {
                result.close()
            }
        } finally {
            reloadStmt.close()
        }

        0
    }

    /**
     * 在指定连接中补齐 tags 字典记录，不修改 metadata_tags。
     */
    public static func ensureTagDictionaryEntriesWithConnection(conn: Connection, tags: Array<String>): Bool {
        let normalizedTags = normalizeTags(tags)
        try {
            for (tag in normalizedTags) {
                let (rawNamespace, rawName) = parseTagName(tag)
                let namespace = rawNamespace.trimAscii()
                let name = rawName.trimAscii()
                if (name.size == 0) {
                    continue
                }
                let tagId = getOrCreateTagInternal(conn, namespace, name)
                if (tagId <= 0) {
                    logger.error("Failed to ensure tag dictionary entry", ("tag", tag))
                    return false
                }
            }
            return true
        } catch (e: Exception) {
            logger.error("Failed to ensure tag dictionary entries", ("error", e.message))
            return false
        }
    }

    /**
     * 补齐 tags 字典记录，不修改 metadata_tags。
     */
    public static func ensureTagDictionaryEntries(tags: Array<String>): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return false
            case Some(conn) =>
                try {
                    return ensureTagDictionaryEntriesWithConnection(conn, tags)
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }

    /**
     * 更新档案的标签
     * @param archiveId 档案ID
     * @param tagsString 标签字符串（逗号分隔，支持 namespace:name 格式）
     * @return 是否更新成功
     */
    public static func updateArchiveTags(archiveId: String, tagsString: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => false
            case Some(conn) =>
                try {
                    // Ensure archive root metadata exists and resolve metadata id.
                    var metadataId: Int64 = 0
                    let getMetadataStmt = conn.prepareStatement("""
                        SELECT id
                        FROM metadata_objects
                        WHERE entity_type = 'archive' AND entity_id = ?
                        LIMIT 1
                    """)
                    try {
                        getMetadataStmt.set(0, archiveId)
                        let rs = getMetadataStmt.query()
                        try {
                            if (rs.next()) {
                                metadataId = rs.getOrNull<Int64>(0) ?? 0
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        getMetadataStmt.close()
                    }

                    if (metadataId <= 0) {
                        let createMetadataStmt = conn.prepareStatement("""
                            INSERT INTO metadata_objects (
                                entity_type, entity_id, title, description, created_at, updated_at
                            )
                            SELECT
                                'archive',
                                a.arcid,
                                '',
                                '',
                                CURRENT_TIMESTAMP,
                                CURRENT_TIMESTAMP
                            FROM archives a
                            WHERE a.arcid = ?
                            RETURNING id
                        """)
                        try {
                            createMetadataStmt.set(0, archiveId)
                            let rs = createMetadataStmt.query()
                            try {
                                if (rs.next()) {
                                    metadataId = rs.getOrNull<Int64>(0) ?? 0
                                }
                            } finally {
                                rs.close()
                            }
                        } finally {
                            createMetadataStmt.close()
                        }
                    }
                    if (metadataId <= 0) {
                        return false
                    }

                    // Delete existing tags for this archive metadata object.
                    let deleteStmt = conn.prepareStatement("DELETE FROM metadata_tags WHERE metadata_id = ?")
                    try {
                        deleteStmt.set(0, metadataId)
                        deleteStmt.update()
                    } finally {
                        deleteStmt.close()
                    }

                    // 如果标签字符串为空，直接返回
                    if (tagsString.size == 0 || tagsString == "") {
                        let touchStmt = conn.prepareStatement("UPDATE metadata_objects SET updated_at = CURRENT_TIMESTAMP WHERE id = ?")
                        try {
                            touchStmt.set(0, metadataId)
                            touchStmt.update()
                        } finally {
                            touchStmt.close()
                        }
                        let _ = DerivedCacheUtils.bumpTankoubonAggregatedContentVersion("updateArchiveTags:${archiveId}")
                        return true
                    }

                    // 解析标签字符串
                    let tags = normalizeTags(parseTagsString(tagsString).toArray())

                    if (!ensureTagDictionaryEntriesWithConnection(conn, tags)) {
                        return false
                    }

                    // 为每个标签创建或获取标签ID，并建立关联
                    for (tag in tags) {
                        let (namespace, name) = parseTagName(tag)
                        let normalizedTag = if (namespace.size > 0) { "${namespace}:${name}" } else { name }
                        if (normalizedTag.trimAscii().size == 0) {
                            continue
                        }

                        // Write unified relation into metadata_tags.
                        let insertRelationStmt = conn.prepareStatement("""
                            INSERT INTO metadata_tags (metadata_id, tag)
                            SELECT ?, ?
                            WHERE NOT EXISTS (
                                SELECT 1 FROM metadata_tags WHERE metadata_id = ? AND tag = ?
                            )
                        """)
                        try {
                            insertRelationStmt.set(0, metadataId)
                            insertRelationStmt.set(1, normalizedTag)
                            insertRelationStmt.set(2, metadataId)
                            insertRelationStmt.set(3, normalizedTag)
                            insertRelationStmt.update()
                        } finally {
                            insertRelationStmt.close()
                        }
                    }

                    let touchStmt = conn.prepareStatement("UPDATE metadata_objects SET updated_at = CURRENT_TIMESTAMP WHERE id = ?")
                    try {
                        touchStmt.set(0, metadataId)
                        touchStmt.update()
                    } finally {
                        touchStmt.close()
                    }
                    let _ = DerivedCacheUtils.bumpTankoubonAggregatedContentVersion("updateArchiveTags:${archiveId}")
                    true
                } catch (e: Exception) {
                    getLogger("tag_dao").error("Error updating archive tags", ("error", e.message))
                    false
                } finally {
                    try {
                        conn.close()
                    } catch (closeException: Exception) {
                        getLogger("tag_dao").warn("Error closing database connection", ("error", closeException.message))
                    }
                }
        }
    }

    /**
     * 解析标签字符串
     */
    private static func parseTagsString(tagsString: String): ArrayList<String> {
        let tags = tagsString.split(",")
        var result: ArrayList<String> = ArrayList<String>()
        let seen = HashSet<String>()

        for (tag in tags) {
            let canonical = canonicalizeTag(tag)
            if (canonical.size > 0 && !seen.contains(canonical)) {
                seen.add(canonical)
                result.add(canonical)
            }
        }

        return result
    }

    /**
     * 获取档案的所有标签
     */
    public static func getArchiveTags(archiveId: String): String {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => ""
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT COALESCE(string_agg(mt.tag, ',' ORDER BY mt.tag), '')
                        FROM metadata_objects mo
                        LEFT JOIN metadata_tags mt ON mt.metadata_id = mo.id
                        WHERE mo.entity_type = 'archive'
                          AND mo.entity_id = ?
                    """)
                    try {
                        stmt.set(0, archiveId)
                        let result = stmt.query()
                        try {
                            if (result.next()) {
                                return result.getOrNull<String>(0) ?? ""
                            }
                            return ""
                        } finally {
                            result.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("Error getting archive tags", ("error", e.message))
                    ""
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }

    /**
     * 批量获取档案标签（key=arcid, value=逗号分隔 tags）
     */
    public static func getBatchArchiveTags(archiveIds: Array<String>): HashMap<String, String> {
        let result = HashMap<String, String>()
        if (archiveIds.size == 0) { return result }

        let deduped = ArrayList<String>()
        let seen = HashMap<String, Bool>()
        for (archiveId in archiveIds) {
            let id = archiveId.trimAscii()
            if (id.size == 0) { continue }
            match (seen.get(id)) {
                case Some(_) => ()
                case None =>
                    seen[id] = true
                    deduped.add(id)
            }
        }
        if (deduped.size == 0) { return result }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return result
            case Some(conn) =>
                try {
                    var placeholders = ""
                    for (i in 0..deduped.size) {
                        if (i > 0) { placeholders += "," }
                        placeholders += "?"
                    }

                    let stmt = conn.prepareStatement("""
                        SELECT mo.entity_id, COALESCE(string_agg(mt.tag, ',' ORDER BY mt.tag), '')
                        FROM metadata_objects mo
                        LEFT JOIN metadata_tags mt ON mt.metadata_id = mo.id
                        WHERE mo.entity_type = 'archive'
                          AND mo.entity_id IN (${placeholders})
                        GROUP BY mo.entity_id
                    """)
                    try {
                        for (i in 0..deduped.size) {
                            stmt.set(i, deduped[i])
                        }
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let arcid = (rs.getOrNull<String>(0) ?? "").trimAscii()
                                if (arcid.size == 0) { continue }
                                result[arcid] = rs.getOrNull<String>(1) ?? ""
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("批量获取 archive tags 失败", ("error", e.message))
                    return result
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }

        return result
    }

    /**
     * 获取所有标签（支持分页和搜索）
     */
    public static func list(namespace: ?String, query: ?String, limit: Int64, offset: Int64): ArrayList<TagData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    var sql = "SELECT id, namespace, name, translations, links, icon_asset_id, background_asset_id, created_at, updated_at FROM tags WHERE 1=1"
                    var params: ArrayList<String> = ArrayList<String>()
                    let unaccentFunction = getUnaccentFunction(conn)

                    match (namespace) {
                        case Some(ns) =>
                            sql += " AND namespace = ?"
                            params.add(ns)
                        case None => ()
                    }

                    match (query) {
                        case Some(q) =>
                            if (q.size > 0) {
                                let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(?)" } else { "?" }
                                sql += " AND (" + wrapSearchExpr("name", unaccentFunction) + " ILIKE " + patternExpr +
                                    " OR " + wrapSearchExpr("translations::text", unaccentFunction) + " ILIKE " + patternExpr + ")"
                                let searchPattern = "%${q}%"
                                params.add(searchPattern)
                                params.add(searchPattern)
                            }
                        case None => ()
                    }

                    sql += " ORDER BY namespace, name LIMIT ? OFFSET ?"

                    let stmt = conn.prepareStatement(sql)
                    var idx = 0
                    for (p in params) {
                        stmt.set(idx, p)
                        idx++
                    }
                    stmt.set(idx, limit)
                    stmt.set(idx + 1, offset)

                    let rs = stmt.query()
                    var list: ArrayList<TagData> = ArrayList<TagData>()
                    try {
                        while (rs.next()) {
                            let tag = TagData()
                            tag.id = rs.getOrNull<Int64>(0) ?? 0
                            tag.namespace = rs.getOrNull<String>(1) ?? ""
                            tag.name = rs.getOrNull<String>(2) ?? ""
                            let translationsJson = rs.getOrNull<String>(3) ?? "{}"
                            tag.translations = parseTranslationsJson(translationsJson)
                            tag.links = rs.getOrNull<String>(4) ?? ""
                            tag.iconAssetId = rs.getOrNull<Int64>(5) ?? 0
                            tag.backgroundAssetId = rs.getOrNull<Int64>(6) ?? 0
                            tag.created_at = rs.getOrNull<String>(7) ?? ""
                            tag.updated_at = rs.getOrNull<String>(8) ?? ""
                            list.add(tag)
                        }
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                    return list
                } catch (e: Exception) {
                    getLogger("tag_dao").error("查询标签列表失败", ("error", e.message))
                    return ArrayList<TagData>()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                getLogger("tag_dao").error("无法连接到数据库")
                return ArrayList<TagData>()
        }
    }

    /**
     * 获取标签列表（轻量版，返回指定语言翻译文本；用于大批量分页拉取）
     * - translations JSONB 通过 SQL 提取，不解析整个对象
     */
    public static func listLite(namespace: ?String, query: ?String, lang: String, limit: Int64, offset: Int64): ArrayList<TagLiteData> {
        let connOpt = DatabaseConfig.getPooledConnection()
        var effectiveLang = lang.trimAscii()
        if (effectiveLang.size == 0) { effectiveLang = "zh" }
        match (connOpt) {
            case Some(conn) =>
                try {
                    var sql = """
                        SELECT
                            id,
                            namespace,
                            name,
                            COALESCE(translations -> ? ->> 'text', '') AS translation_text
                        FROM tags
                        WHERE 1=1
                    """
                    var params: ArrayList<String> = ArrayList<String>()
                    let unaccentFunction = getUnaccentFunction(conn)

                    // First param is lang for JSONB extraction.
                    params.add(effectiveLang)

                    match (namespace) {
                        case Some(ns) =>
                            sql += " AND namespace = ?"
                            params.add(ns)
                        case None => ()
                    }

                    match (query) {
                        case Some(q) =>
                            if (q.size > 0) {
                                let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(?)" } else { "?" }
                                sql += " AND (" + wrapSearchExpr("name", unaccentFunction) + " ILIKE " + patternExpr +
                                    " OR " + wrapSearchExpr("translations::text", unaccentFunction) + " ILIKE " + patternExpr + ")"
                                let searchPattern = "%${q}%"
                                params.add(searchPattern)
                                params.add(searchPattern)
                            }
                        case None => ()
                    }

                    sql += " ORDER BY namespace, name LIMIT ? OFFSET ?"

                    let stmt = conn.prepareStatement(sql)
                    var idx = 0
                    for (p in params) {
                        stmt.set(idx, p)
                        idx++
                    }
                    stmt.set(idx, limit)
                    stmt.set(idx + 1, offset)

                    let rs = stmt.query()
                    var list: ArrayList<TagLiteData> = ArrayList<TagLiteData>()
                    try {
                        while (rs.next()) {
                            let row = TagLiteData()
                            row.id = rs.getOrNull<Int64>(0) ?? 0
                            row.namespace = rs.getOrNull<String>(1) ?? ""
                            row.name = rs.getOrNull<String>(2) ?? ""
                            row.translationText = rs.getOrNull<String>(3) ?? ""
                            list.add(row)
                        }
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                    return list
                } catch (e: Exception) {
                    getLogger("tag_dao").error("查询标签轻量列表失败", ("error", e.message))
                    // Fallback: use the full list() and derive translation text in-process.
                    let full = list(namespace, query, limit, offset)
                    var out: ArrayList<TagLiteData> = ArrayList<TagLiteData>()
                    for (row in full) {
                        let lite = TagLiteData()
                        lite.id = row.id
                        lite.namespace = row.namespace
                        lite.name = row.name
                        lite.translationText = row.getTranslatedText(effectiveLang)
                        out.add(lite)
                    }
                    return out
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                getLogger("tag_dao").error("无法连接到数据库")
                return ArrayList<TagLiteData>()
        }
    }

    /**
     * 统计标签数量
     */
    public static func count(namespace: ?String, query: ?String): Int64 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    var sql = "SELECT COUNT(*) FROM tags WHERE 1=1"
                    var params: ArrayList<String> = ArrayList<String>()
                    let unaccentFunction = getUnaccentFunction(conn)

                    match (namespace) {
                        case Some(ns) =>
                            sql += " AND namespace = ?"
                            params.add(ns)
                        case None => ()
                    }

                    match (query) {
                        case Some(q) =>
                            if (q.size > 0) {
                                let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(?)" } else { "?" }
                                sql += " AND (" + wrapSearchExpr("name", unaccentFunction) + " ILIKE " + patternExpr +
                                    " OR " + wrapSearchExpr("translations::text", unaccentFunction) + " ILIKE " + patternExpr + ")"
                                let searchPattern = "%${q}%"
                                params.add(searchPattern)
                                params.add(searchPattern)
                            }
                        case None => ()
                    }

                    let stmt = conn.prepareStatement(sql)
                    var idx = 0
                    for (p in params) {
                        stmt.set(idx, p)
                        idx++
                    }

                    let rs = stmt.query()
                    try {
                        if (rs.next()) {
                            return rs.getOrNull<Int64>(0) ?? 0
                        }
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                    return 0
                } catch (e: Exception) {
                    getLogger("tag_dao").error("统计标签数量失败", ("error", e.message))
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return 0
        }
    }

    /**
     * 根据ID获取标签
     */
    public static func getById(id: Int64): ?TagData {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, namespace, name, translations, links, icon_asset_id, background_asset_id, created_at, updated_at FROM tags WHERE id = ?")
                    try {
                        stmt.set(0, id)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let tag = TagData()
                                tag.id = rs.getOrNull<Int64>(0) ?? 0
                                tag.namespace = rs.getOrNull<String>(1) ?? ""
                                tag.name = rs.getOrNull<String>(2) ?? ""
                                let translationsJson = rs.getOrNull<String>(3) ?? "{}"
                                tag.translations = parseTranslationsJson(translationsJson)
                                tag.links = rs.getOrNull<String>(4) ?? ""
                                tag.iconAssetId = rs.getOrNull<Int64>(5) ?? 0
                                tag.backgroundAssetId = rs.getOrNull<Int64>(6) ?? 0
                                tag.created_at = rs.getOrNull<String>(7) ?? ""
                                tag.updated_at = rs.getOrNull<String>(8) ?? ""
                                return Some(tag)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return None
                } catch (e: Exception) {
                    getLogger("tag_dao").error("查询标签失败", ("error", e.message), ("id", id.toString()))
                    return None
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return None
        }
    }

    /**
     * 根据 namespace 和 name 获取标签
     */
    public static func getByNamespaceName(namespace: String, name: String): ?TagData {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement(
                        "SELECT id, namespace, name, translations, links, icon_asset_id, background_asset_id, created_at, updated_at FROM tags WHERE namespace = ? AND name = ?")
                    try {
                        stmt.set(0, namespace)
                        stmt.set(1, name)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let tag = TagData()
                                tag.id = rs.getOrNull<Int64>(0) ?? 0
                                tag.namespace = rs.getOrNull<String>(1) ?? ""
                                tag.name = rs.getOrNull<String>(2) ?? ""
                                let translationsJson = rs.getOrNull<String>(3) ?? "{}"
                                tag.translations = parseTranslationsJson(translationsJson)
                                tag.links = rs.getOrNull<String>(4) ?? ""
                                tag.iconAssetId = rs.getOrNull<Int64>(5) ?? 0
                                tag.backgroundAssetId = rs.getOrNull<Int64>(6) ?? 0
                                tag.created_at = rs.getOrNull<String>(7) ?? ""
                                tag.updated_at = rs.getOrNull<String>(8) ?? ""
                                return Some(tag)
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return None
                } catch (e: Exception) {
                    getLogger("tag_dao").error("查询标签失败", ("error", e.message))
                    return None
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return None
        }
    }

    /**
     * 创建标签
     */
    public static func create(namespace: String, name: String, translations: HashMap<String, TagTranslation>, links: String): Int64 {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let translationsJson = serializeTranslationsJson(translations)
                    let stmt = conn.prepareStatement(
                        "INSERT INTO tags (namespace, name, translations, links) VALUES (?, ?, ?::jsonb, ?) RETURNING id")
                    try {
                        stmt.set(0, namespace)
                        stmt.set(1, name)
                        stmt.set(2, translationsJson)
                        stmt.set(3, links)
                        let rs = stmt.query()
                        try {
                            if (rs.next()) {
                                let id = rs.getOrNull<Int64>(0) ?? 0
                                if (id > 0) {
                                    invalidateTranslationSearchCache()
                                }
                                return id
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                    return 0
                } catch (e: Exception) {
                    getLogger("tag_dao").error("创建标签失败", ("error", e.message), ("namespace", namespace), ("name", name))
                    return 0
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return 0
        }
    }

    /**
     * 更新标签
     */
    public static func update(id: Int64, translations: HashMap<String, TagTranslation>, links: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let translationsJson = serializeTranslationsJson(translations)
                    let stmt = conn.prepareStatement(
                        "UPDATE tags SET translations = ?::jsonb, links = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
                    try {
                        stmt.set(0, translationsJson)
                        stmt.set(1, links)
                        stmt.set(2, id)
                        stmt.update()
                        invalidateTranslationSearchCache()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("更新标签失败", ("error", e.message), ("id", id.toString()))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return false
        }
    }

    /**
     * 删除标签
     */
    public static func delete(id: Int64): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("DELETE FROM tags WHERE id = ?")
                    try {
                        stmt.set(0, id)
                        stmt.update()
                        invalidateTranslationSearchCache()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("删除标签失败", ("error", e.message), ("id", id.toString()))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return false
        }
    }

    /**
     * 批量获取标签翻译（用于前端展示）
     * @param tags 标签名数组（namespace:name 格式）
     * @param lang 语言代码
     * @return 标签名 -> 翻译文本的映射
     */
    public static func batchGetTranslations(tags: Array<String>, lang: String): HashMap<String, String> {
        var result: HashMap<String, String> = HashMap<String, String>()
        if (tags.size == 0) {
            return result
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    // Use row-wise IN to avoid long OR chains and keep it index-friendly.
                    // WHERE (namespace, name) IN ((?, ?), (?, ?), ...)
                    var tuples: ArrayList<String> = ArrayList<String>()
                    var namespaces: ArrayList<String> = ArrayList<String>()
                    var names: ArrayList<String> = ArrayList<String>()
                    for (tag in tags) {
                        let (namespace, name) = parseTagName(tag)
                        tuples.add("(?, ?)")
                        namespaces.add(namespace)
                        names.add(name)
                    }

                    let tuplesStr = String.join(tuples.toArray(), delimiter: ", ")
                    let sql = "SELECT namespace, name, translations FROM tags WHERE (namespace, name) IN (" + tuplesStr + ")"
                    let stmt = conn.prepareStatement(sql)
                    try {
                        // 绑定 (namespace, name) 参数对
                        var paramIndex = 0
                        for (i in 0..namespaces.size) {
                            stmt.set(paramIndex, namespaces[i])
                            stmt.set(paramIndex + 1, names[i])
                            paramIndex += 2
                        }

                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let namespace = rs.getOrNull<String>(0) ?? ""
                                let name = rs.getOrNull<String>(1) ?? ""
                                let translationsJson = rs.getOrNull<String>(2) ?? "{}"
                                let translations = parseTranslationsJson(translationsJson)

                                let fullName = if (namespace.size > 0) { "${namespace}:${name}" } else { name }

                                match (translations.get(lang)) {
                                    case Some(t) =>
                                        if (t.text.size > 0) {
                                            result[fullName] = t.text
                                        }
                                    case None => ()
                                }
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("批量获取标签翻译失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => ()
        }
        return result
    }

    /**
     * 获取指定语言的所有标签翻译映射
     */
    public static func getTranslationsMap(lang: String): HashMap<String, String> {
        var result: HashMap<String, String> = HashMap<String, String>()

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("SELECT namespace, name, translations FROM tags")
                    let rs = stmt.query()
                    try {
                        while (rs.next()) {
                            let namespace = rs.getOrNull<String>(0) ?? ""
                            let name = rs.getOrNull<String>(1) ?? ""
                            let translationsJson = rs.getOrNull<String>(2) ?? "{}"
                            let translations = parseTranslationsJson(translationsJson)

                            let fullName = if (namespace.size > 0) { "${namespace}:${name}" } else { name }

                            match (translations.get(lang)) {
                                case Some(t) =>
                                    if (t.text.size > 0) {
                                        result[fullName] = t.text
                                    }
                                case None => ()
                            }
                        }
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("获取标签翻译映射失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => ()
        }
        return result
    }

    /**
     * 获取所有命名空间
     */
    public static func listNamespaces(): Array<String> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("SELECT DISTINCT namespace FROM tags WHERE namespace != '' ORDER BY namespace")
                    let rs = stmt.query()
                    var list: ArrayList<String> = ArrayList<String>()
                    try {
                        while (rs.next()) {
                            let ns = rs.getOrNull<String>(0) ?? ""
                            if (ns.size > 0) {
                                list.add(ns)
                            }
                        }
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                    return list.toArray()
                } catch (e: Exception) {
                    getLogger("tag_dao").error("获取命名空间列表失败", ("error", e.message))
                    return Array<String>()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return Array<String>()
        }
    }

    /**
     * 获取当前系统已存在的所有标签名（用于自动补全等）
     */
    public static func listAllTagNames(): Array<String> {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let stmt = conn.prepareStatement("""
                        SELECT DISTINCT
                            CASE WHEN namespace != '' AND namespace IS NOT NULL
                                 THEN namespace || ':' || name
                                 ELSE name
                            END AS full_name
                        FROM tags
                        ORDER BY full_name
                    """)
                    let rs = stmt.query()
                    var list: ArrayList<String> = ArrayList<String>()
                    try {
                        while (rs.next()) {
                            let name = rs.getOrNull<String>(0) ?? ""
                            if (name.trimAscii().size > 0) {
                                list.add(name)
                            }
                        }
                    } finally {
                        rs.close()
                        stmt.close()
                    }
                    return list.toArray()
                } catch (e: Exception) {
                    getLogger("tag_dao").error("获取全量标签失败", ("error", e.message))
                    return Array<String>()
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return Array<String>()
        }
    }

    /**
     * 插入或更新标签（用于导入）
     */
    public static func upsert(namespace: String, name: String, translations: HashMap<String, TagTranslation>, links: String): Bool {
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let translationsJson = serializeTranslationsJson(translations)
                    let updateStmt = conn.prepareStatement("""
                        UPDATE tags
                        SET translations = ?::jsonb, links = ?, updated_at = CURRENT_TIMESTAMP
                        WHERE namespace = ? AND name = ?
                    """)
                    let insertStmt = conn.prepareStatement("""
                        INSERT INTO tags (namespace, name, translations, links)
                        SELECT ?, ?, ?::jsonb, ?
                        WHERE NOT EXISTS (
                            SELECT 1 FROM tags WHERE namespace = ? AND name = ?
                        )
                    """)
                    try {
                        updateStmt.set(0, translationsJson)
                        updateStmt.set(1, links)
                        updateStmt.set(2, namespace)
                        updateStmt.set(3, name)
                        let updated = updateStmt.update()
                        if (updated.rowCount <= 0) {
                            insertStmt.set(0, namespace)
                            insertStmt.set(1, name)
                            insertStmt.set(2, translationsJson)
                            insertStmt.set(3, links)
                            insertStmt.set(4, namespace)
                            insertStmt.set(5, name)
                            insertStmt.update()
                        }
                        invalidateTranslationSearchCache()
                        return true
                    } finally {
                        updateStmt.close()
                        insertStmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("upsert标签失败", ("error", e.message), ("namespace", namespace), ("name", name))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None =>
                return false
        }
    }

    /**
     * 翻译标签字符串（用于API返回）
     * 将逗号分隔的标签字符串翻译为指定语言，格式为 "namespace:翻译文本"
     * @param tagsString 原始标签字符串（逗号分隔，namespace:name 格式）
     * @param lang 语言代码
     * @return 翻译后的标签字符串
     */
    public static func translateTagsString(tagsString: String, lang: String): String {
        if (tagsString.size == 0 || lang.size == 0) {
            return tagsString
        }

        let tags = parseTagsString(tagsString)
        if (tags.size == 0) {
            return tagsString
        }

        // 获取翻译映射
        let translationsMap = batchGetTranslations(tags.toArray(), lang)

        // 构建翻译后的标签字符串
        var translatedTags: ArrayList<String> = ArrayList<String>()
        for (tag in tags) {
            let (namespace, _) = parseTagName(tag)
            // 查找翻译
            match (translationsMap.get(tag)) {
                case Some(translatedText) =>
                    // 有翻译：namespace:翻译文本
                    if (namespace.size > 0) {
                        translatedTags.add("${namespace}:${translatedText}")
                    } else {
                        translatedTags.add(translatedText)
                    }
                case None =>
                    // 无翻译：保持原样 namespace:name
                    translatedTags.add(tag)
            }
        }

        return String.join(translatedTags.toArray(), delimiter: ", ")
    }

    /**
     * 翻译标签字符串（使用外部提供的翻译映射，避免重复查询数据库）
     * @param tagsString 原始标签字符串（逗号分隔，namespace:name 格式）
     * @param lang 语言代码
     * @param translationsMap 标签全名 -> 翻译文本 的映射（由 batchGetTranslations 生成）
     */
    public static func translateTagsString(tagsString: String, lang: String, translationsMap: HashMap<String, String>): String {
        if (tagsString.size == 0 || lang.size == 0) {
            return tagsString
        }

        let tags = parseTagsString(tagsString)
        if (tags.size == 0) {
            return tagsString
        }

        var translatedTags: ArrayList<String> = ArrayList<String>()
        for (tag in tags) {
            let (namespace, _) = parseTagName(tag)
            match (translationsMap.get(tag)) {
                case Some(translatedText) =>
                    if (namespace.size > 0) {
                        translatedTags.add("${namespace}:${translatedText}")
                    } else {
                        translatedTags.add(translatedText)
                    }
                case None => translatedTags.add(tag)
            }
        }

        return String.join(translatedTags.toArray(), delimiter: ", ")
    }

    /**
     * 反向翻译标签字符串（用于后端存储）
     * 将翻译后的标签字符串还原为原始标签字符串，格式为 "namespace:原始name"
     * @param translatedTagsString 翻译后的标签字符串（逗号分隔，namespace:翻译文本 或 namespace:原始name）
     * @param lang 语言代码
     * @return 原始标签字符串
     */
    public static func reverseTranslateTagsString(translatedTagsString: String, lang: String): String {
        if (translatedTagsString.size == 0 || lang.size == 0) {
            return translatedTagsString
        }

        let tags = parseTagsString(translatedTagsString)
        if (tags.size == 0) {
            return translatedTagsString
        }

        // 获取当前标签的翻译映射（只查询需要的标签，而不是所有标签）
        // let allTags = listAllTagNames()  // 移除：不再获取所有标签，避免性能问题
        let allTranslationsMap = batchGetTranslations(tags.toArray(), lang)

        // 构建反向映射：翻译文本 -> 原始标签
        var reverseMap: HashMap<String, String> = HashMap<String, String>()
        for ((originalTag, translatedText) in allTranslationsMap) {
            let (namespace, _) = parseTagName(originalTag)
            let key = if (namespace.size > 0) {
                "${namespace}:${translatedText}"
            } else {
                translatedText
            }
            reverseMap[key] = originalTag
        }

        // 构建还原后的标签字符串
        var originalTags: ArrayList<String> = ArrayList<String>()
        for (translatedTag in tags) {
            let (namespace, translatedText) = parseTagName(translatedTag)
            // 尝试反向查找
            let lookupKey = if (namespace.size > 0) {
                "${namespace}:${translatedText}"
            } else {
                translatedText
            }

            match (reverseMap.get(lookupKey)) {
                case Some(originalTag) =>
                    // 找到原始标签
                    originalTags.add(originalTag)
                case None =>
                    // 没找到，可能是原始标签（无翻译）或无法识别，保持原样
                    originalTags.add(translatedTag)
            }
        }

        return String.join(originalTags.toArray(), delimiter: ", ")
    }

    // ============ 翻译搜索方法 ============

    /**
     * 根据翻译文本模糊查找标签（所有语言）
     * 用于普通搜索词的翻译匹配
     * @param searchTerm 搜索词
     * @return 匹配的标签全名列表（namespace:name 格式）
     */
    public static func findTagsByTranslation(searchTerm: String): ArrayList<String> {
        let normalizedSearchTerm = normalizeTranslationSearchTerm(searchTerm)
        let result = ArrayList<String>()
        if (normalizedSearchTerm.size == 0) {
            return result
        }

        let cacheVersion = DerivedCacheUtils.getTagTranslationSearchVersion()
        let cacheKey = buildTranslationSearchCacheKey(cacheVersion, normalizedSearchTerm)
        match (readTranslationSearchCache(cacheKey)) {
            case Some(cached) =>
                logger.debug("tag translation search cache hit",
                    ("searchTerm", normalizedSearchTerm),
                    ("version", cacheVersion.toString()),
                    ("resultCount", cached.size.toString()))
                return cached
            case None => ()
        }
        logger.debug("tag translation search cache miss",
            ("searchTerm", normalizedSearchTerm),
            ("version", cacheVersion.toString()))

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let queried = queryTagsByTranslationWithConn(conn, normalizedSearchTerm)
                    writeTranslationSearchCache(cacheKey, queried)
                    logger.debug("tag translation search cache store",
                        ("searchTerm", normalizedSearchTerm),
                        ("version", cacheVersion.toString()),
                        ("resultCount", queried.size.toString()))
                    return queried
                } catch (e: Exception) {
                    getLogger("tag_dao").error("根据翻译查找标签失败", ("error", e.message), ("searchTerm", normalizedSearchTerm))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => ()
        }

        return result
    }

    /**
     * 根据翻译文本查找标签（使用已有连接，避免嵌套连接泄漏）
     * 用于在持有连接的情况下调用，避免连接池耗尽
     */
    public static func findTagsByTranslationWithConn(conn: Connection, searchTerm: String): ArrayList<String> {
        let normalizedSearchTerm = normalizeTranslationSearchTerm(searchTerm)
        let result = ArrayList<String>()
        if (normalizedSearchTerm.size == 0) {
            return result
        }

        let cacheVersion = DerivedCacheUtils.getTagTranslationSearchVersion()
        let cacheKey = buildTranslationSearchCacheKey(cacheVersion, normalizedSearchTerm)
        match (readTranslationSearchCache(cacheKey)) {
            case Some(cached) =>
                logger.debug("tag translation search cache hit",
                    ("searchTerm", normalizedSearchTerm),
                    ("version", cacheVersion.toString()),
                    ("resultCount", cached.size.toString()),
                    ("withConn", "true"))
                return cached
            case None => ()
        }
        logger.debug("tag translation search cache miss",
            ("searchTerm", normalizedSearchTerm),
            ("version", cacheVersion.toString()),
            ("withConn", "true"))

        let queried = queryTagsByTranslationWithConn(conn, normalizedSearchTerm)
        writeTranslationSearchCache(cacheKey, queried)
        logger.debug("tag translation search cache store",
            ("searchTerm", normalizedSearchTerm),
            ("version", cacheVersion.toString()),
            ("resultCount", queried.size.toString()),
            ("withConn", "true"))
        return queried
    }

    /**
     * 批量根据翻译文本查找标签（使用已有连接）
     * 返回 raw searchTerm -> 匹配标签列表 的映射。
     */
    public static func batchFindTagsByTranslationWithConn(conn: Connection, searchTerms: Array<String>): HashMap<String, ArrayList<String>> {
        let result = HashMap<String, ArrayList<String>>()
        if (searchTerms.size == 0) {
            return result
        }

        let normalizedToRawTerms = HashMap<String, ArrayList<String>>()
        let orderedNormalizedTerms = ArrayList<String>()
        for (rawSearchTerm in searchTerms) {
            let raw = rawSearchTerm.trimAscii()
            if (raw.size == 0) {
                continue
            }
            let normalized = normalizeTranslationSearchTerm(raw)
            if (normalized.size == 0) {
                continue
            }

            match (normalizedToRawTerms.get(normalized)) {
                case Some(existing) =>
                    var duplicated = false
                    for (term in existing) {
                        if (term == raw) {
                            duplicated = true
                            break
                        }
                    }
                    if (!duplicated) {
                        existing.add(raw)
                    }
                case None =>
                    let terms = ArrayList<String>()
                    terms.add(raw)
                    normalizedToRawTerms[normalized] = terms
                    orderedNormalizedTerms.add(normalized)
            }
        }

        if (orderedNormalizedTerms.size == 0) {
            return result
        }

        let cacheVersion = DerivedCacheUtils.getTagTranslationSearchVersion()
        let normalizedMatches = HashMap<String, ArrayList<String>>()
        let uncachedNormalizedTerms = ArrayList<String>()
        for (normalized in orderedNormalizedTerms) {
            let cacheKey = buildTranslationSearchCacheKey(cacheVersion, normalized)
            match (readTranslationSearchCache(cacheKey)) {
                case Some(cached) =>
                    normalizedMatches[normalized] = cached
                case None =>
                    uncachedNormalizedTerms.add(normalized)
            }
        }

        if (uncachedNormalizedTerms.size > 0) {
            let queried = queryTagsByTranslationsWithConn(conn, uncachedNormalizedTerms.toArray())
            for (normalized in uncachedNormalizedTerms) {
                let matches = match (queried.get(normalized)) {
                    case Some(found) => found
                    case None => ArrayList<String>()
                }
                let cacheKey = buildTranslationSearchCacheKey(cacheVersion, normalized)
                writeTranslationSearchCache(cacheKey, matches)
                normalizedMatches[normalized] = matches
            }
        }

        for (normalized in orderedNormalizedTerms) {
            let matches = match (normalizedMatches.get(normalized)) {
                case Some(found) => found
                case None => ArrayList<String>()
            }
            match (normalizedToRawTerms.get(normalized)) {
                case Some(rawTerms) =>
                    for (raw in rawTerms) {
                        result[raw] = matches
                    }
                case None => ()
            }
        }

        return result
    }

    public static func bumpTranslationSearchCacheVersion(): Int64 {
        return DerivedCacheUtils.bumpTagTranslationSearchVersion("tag_dao")
    }

    private static func invalidateTranslationSearchCache(): Unit {
        let nextVersion = bumpTranslationSearchCacheVersion()
        logger.debug("tag translation search cache version bumped", ("version", nextVersion.toString()))
    }

    private static func normalizeTranslationSearchTerm(searchTerm: String): String {
        var normalized = searchTerm
            .replace("　", " ")
            .replace("\t", " ")
            .replace("\r", " ")
            .replace("\n", " ")
            .trimAscii()
            .toAsciiLower()
        if (normalized.size == 0) {
            return ""
        }
        return String.join(normalized.split(" ", removeEmpty: true), delimiter: " ")
    }

    private static func buildTranslationSearchCacheKey(version: Int64, normalizedSearchTerm: String): String {
        return "v${version.toString()}:${normalizedSearchTerm}"
    }

    private static func readTranslationSearchCache(cacheKey: String): Option<ArrayList<String>> {
        let cacheNamespace = DerivedCacheUtils.getTagTranslationSearchNamespace()
        match (PersistentCacheService.get(cacheNamespace, cacheKey)) {
            case Some(payload) =>
                match (decodeCachedTranslationSearchResult(payload)) {
                    case Some(cached) => return Some(cached)
                    case None =>
                        let _ = PersistentCacheService.delete(cacheNamespace, cacheKey)
                        logger.warn("tag translation search cache payload decode failed; evicted key", ("key", cacheKey))
                        return None
                }
            case None => return None
        }
    }

    private static func writeTranslationSearchCache(cacheKey: String, result: ArrayList<String>): Unit {
        let cacheNamespace = DerivedCacheUtils.getTagTranslationSearchNamespace()
        let payload = encodeCachedTranslationSearchResult(result.toArray())
        let _ = PersistentCacheService.set(
            cacheNamespace,
            cacheKey,
            payload,
            translationSearchCacheTtlSeconds
        )
    }

    private static func queryTagsByTranslationWithConn(conn: Connection, normalizedSearchTerm: String): ArrayList<String> {
        let result = ArrayList<String>()
        try {
            let unaccentFunction = getUnaccentFunction(conn)
            // 使用 translations::text ILIKE 在 JSONB 文本中模糊搜索。
            // Add a LIMIT to cap worst-case work and response size (caller expands matches into OR tags LIKE ...).
            let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(?)" } else { "?" }
            let sql = "SELECT namespace, name FROM tags WHERE " + wrapSearchExpr("translations::text", unaccentFunction) + " ILIKE " + patternExpr + " LIMIT 200"
            let stmt = conn.prepareStatement(sql)
            try {
                let pattern = "%" + normalizedSearchTerm + "%"
                stmt.set(0, pattern)
                let rs = stmt.query()
                try {
                    while (rs.next()) {
                        let namespace = rs.getOrNull<String>(0) ?? ""
                        let name = rs.getOrNull<String>(1) ?? ""
                        let fullName = if (namespace.size > 0) {
                            "${namespace}:${name}"
                        } else {
                            name
                        }
                        result.add(fullName)
                    }
                } finally {
                    rs.close()
                }
            } finally {
                stmt.close()
            }
        } catch (e: Exception) {
            getLogger("tag_dao").error("根据翻译查找标签失败", ("error", e.message), ("searchTerm", normalizedSearchTerm))
        }
        return result
    }

    private static func queryTagsByTranslationsWithConn(conn: Connection, normalizedSearchTerms: Array<String>): HashMap<String, ArrayList<String>> {
        let result = HashMap<String, ArrayList<String>>()
        if (normalizedSearchTerms.size == 0) {
            return result
        }

        let uniqueTerms = ArrayList<String>()
        let seenTerms = HashMap<String, Bool>()
        for (normalizedSearchTerm in normalizedSearchTerms) {
            let normalized = normalizeTranslationSearchTerm(normalizedSearchTerm)
            if (normalized.size == 0 || seenTerms.contains(normalized)) {
                continue
            }
            seenTerms[normalized] = true
            uniqueTerms.add(normalized)
            result[normalized] = ArrayList<String>()
        }

        if (uniqueTerms.size == 0) {
            return result
        }

        try {
            let unaccentFunction = getUnaccentFunction(conn)
            let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(?)" } else { "?" }
            let searchExpr = wrapSearchExpr("translations::text", unaccentFunction)
            let subqueries = ArrayList<String>()
            for (_term in uniqueTerms) {
                subqueries.add("SELECT ? AS matched_term, namespace, name FROM tags WHERE ${searchExpr} ILIKE ${patternExpr} LIMIT 200")
            }
            let sql = String.join(subqueries.toArray(), delimiter: " UNION ALL ")
            let stmt = conn.prepareStatement(sql)
            try {
                var index = 0
                for (normalized in uniqueTerms) {
                    stmt.set(index, normalized)
                    stmt.set(index + 1, "%" + normalized + "%")
                    index += 2
                }
                let rs = stmt.query()
                try {
                    let seenByTerm = HashMap<String, HashMap<String, Bool>>()
                    while (rs.next()) {
                        let matchedTerm = rs.getOrNull<String>(0) ?? ""
                        let namespace = rs.getOrNull<String>(1) ?? ""
                        let name = rs.getOrNull<String>(2) ?? ""
                        let fullName = if (namespace.size > 0) { "${namespace}:${name}" } else { name }
                        if (matchedTerm.size == 0 || fullName.size == 0) {
                            continue
                        }

                        let seenForTerm = match (seenByTerm.get(matchedTerm)) {
                            case Some(existing) => existing
                            case None =>
                                let created = HashMap<String, Bool>()
                                seenByTerm[matchedTerm] = created
                                created
                        }
                        if (seenForTerm.contains(fullName)) {
                            continue
                        }
                        seenForTerm[fullName] = true

                        match (result.get(matchedTerm)) {
                            case Some(matches) => matches.add(fullName)
                            case None =>
                                let matches = ArrayList<String>()
                                matches.add(fullName)
                                result[matchedTerm] = matches
                        }
                    }
                } finally {
                    rs.close()
                }
            } finally {
                stmt.close()
            }
        } catch (_: Exception) {
            for (normalized in uniqueTerms) {
                result[normalized] = queryTagsByTranslationWithConn(conn, normalized)
            }
        }

        return result
    }

    private static func encodeCachedTranslationSearchResult(tags: Array<String>): String {
        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startArray()
        for (tag in tags) {
            w.writeValue(tag)
        }
        w.endArray()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    private static func decodeCachedTranslationSearchResult(payload: String): Option<ArrayList<String>> {
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

            let result = ArrayList<String>()
            reader.startArray()
            while (reader.peek() != EndArray) {
                result.add(reader.readValue<String>())
            }
            reader.endArray()
            return Some(result)
        } catch (_: Exception) {
            return None
        }
    }

    // ============ JSON 序列化/反序列化辅助方法 ============

    /**
     * 解析 translations JSON 字符串
     */
    private static func parseTranslationsJson(jsonStr: String): HashMap<String, TagTranslation> {
        var result: HashMap<String, TagTranslation> = HashMap<String, TagTranslation>()

        if (jsonStr.size == 0 || jsonStr == "{}") {
            return result
        }

        try {
            var buf = ByteBuffer()
            unsafe { buf.write(jsonStr.rawData()) }
            let r = JsonReader(buf)

            match (r.peek()) {
                case Some(BeginObject) =>
                    r.startObject()
                    while (r.peek() != EndObject) {
                        let lang = r.readName()
                        let translation = TagTranslation()
                        match (r.peek()) {
                            case Some(BeginObject) =>
                                r.startObject()
                                while (r.peek() != EndObject) {
                                    let k = r.readName()
                                    match (k) {
                                        case "text" => translation.text = r.readValue<String>()
                                        case "intro" => translation.intro = r.readValue<String>()
                                        case _ => r.skip()
                                    }
                                }
                                r.endObject()
                                result[lang] = translation
                            case Some(_) =>
                                r.skip()
                            case None => break
                        }
                    }
                    r.endObject()
                case _ => ()
            }
        } catch (e: Exception) {
            getLogger("tag_dao").warn("解析translations JSON失败", ("error", e.message), ("json", jsonStr))
        }

        return result
    }

    /**
     * 序列化 translations 为 JSON 字符串
     */
    private static func serializeTranslationsJson(translations: HashMap<String, TagTranslation>): String {
        if (translations.size == 0) {
            return "{}"
        }

        let out = ByteBuffer()
        let w = JsonWriter(out)
        w.startObject()
        for ((lang, t) in translations) {
            w.writeName(lang)
            w.startObject()
            w.writeName("text").writeValue(t.text)
            w.writeName("intro").writeValue(t.intro)
            w.endObject()
        }
        w.endObject()
        w.flush()
        return String.fromUtf8(readToEnd(out))
    }

    // ============ 自动补全搜索方法 ============

    /**
     * 自动补全搜索标签
     * 搜索标签名和翻译文本，返回带翻译的结果
     * @param query 搜索词
     * @param lang 语言代码
     * @param limit 返回数量限制
     * @return 匹配的标签列表 [(fullName, translatedText)]
     */
    public static func autocompleteSearch(query: String, lang: String, limit: Int64, requireBound: Bool): ArrayList<(String, String)> {
        var result: ArrayList<(String, String)> = ArrayList<(String, String)>()

        if (query.size == 0) {
            return result
        }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                
                try {
                    let unaccentFunction = getUnaccentFunction(conn)
                    let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(?)" } else { "?" }
                    let nameExpr = wrapSearchExpr("t.name", unaccentFunction)
                    let fullNameExpr = wrapSearchExpr("CASE WHEN t.namespace != '' THEN t.namespace || ':' || t.name ELSE t.name END", unaccentFunction)
                    let translationTextExpr = wrapSearchExpr("t.translations->?->>'text'", unaccentFunction)
                    let translationsExpr = wrapSearchExpr("t.translations::text", unaccentFunction)
                    // 搜索标签名(namespace:name)和翻译文本。
                    // 默认只返回“已绑定档案”的标签，供全局搜索框等场景使用；
                    // 但编辑档案标签时需要可选到“未绑定任何档案”的标签，因此支持关闭该约束。
                    // 使用 JSONB 提取指定语言的翻译文本进行搜索。
                    // 优先级：1=name精确匹配, 2=name前缀匹配, 3=翻译精确匹配, 4=翻译前缀匹配, 5=模糊匹配
                    let sql = if (requireBound) {
                        "SELECT DISTINCT t.namespace, t.name, t.translations," +
                        " CASE" +
                        " WHEN " + nameExpr + " ILIKE " + patternExpr + " THEN 1" +
                        " WHEN " + nameExpr + " ILIKE " + patternExpr + " THEN 2" +
                        " WHEN " + translationTextExpr + " ILIKE " + patternExpr + " THEN 3" +
                        " WHEN " + translationTextExpr + " ILIKE " + patternExpr + " THEN 4" +
                        " ELSE 5 END as match_priority" +
                        " FROM tags t" +
                        " INNER JOIN metadata_tags mt ON mt.tag = CASE WHEN COALESCE(t.namespace, '') != '' THEN t.namespace || ':' || t.name ELSE t.name END" +
                        " INNER JOIN metadata_objects mo ON mo.id = mt.metadata_id AND mo.entity_type = 'archive'" +
                        " WHERE " + nameExpr + " ILIKE " + patternExpr +
                        " OR " + fullNameExpr + " ILIKE " + patternExpr +
                        " OR " + translationTextExpr + " ILIKE " + patternExpr +
                        " OR " + translationsExpr + " ILIKE " + patternExpr +
                        " ORDER BY match_priority, t.name" +
                        " LIMIT ?"
                    } else {
                        "SELECT DISTINCT t.namespace, t.name, t.translations," +
                        " CASE" +
                        " WHEN " + nameExpr + " ILIKE " + patternExpr + " THEN 1" +
                        " WHEN " + nameExpr + " ILIKE " + patternExpr + " THEN 2" +
                        " WHEN " + translationTextExpr + " ILIKE " + patternExpr + " THEN 3" +
                        " WHEN " + translationTextExpr + " ILIKE " + patternExpr + " THEN 4" +
                        " ELSE 5 END as match_priority" +
                        " FROM tags t" +
                        " WHERE " + nameExpr + " ILIKE " + patternExpr +
                        " OR " + fullNameExpr + " ILIKE " + patternExpr +
                        " OR " + translationTextExpr + " ILIKE " + patternExpr +
                        " OR " + translationsExpr + " ILIKE " + patternExpr +
                        " ORDER BY match_priority, t.name" +
                        " LIMIT ?"
                    }
                    let stmt = conn.prepareStatement(sql)
                    try {
                        let exactPattern = query
                        let prefixPattern = query + "%"
                        let likePattern = "%" + query + "%"
                        // CASE 中的参数
                        stmt.set(0, exactPattern)       // name 精确匹配优先级
                        stmt.set(1, prefixPattern)      // name 前缀匹配优先级
                        stmt.set(2, lang)               // 翻译精确匹配的语言
                        stmt.set(3, exactPattern)       // 翻译精确匹配
                        stmt.set(4, lang)               // 翻译前缀匹配的语言
                        stmt.set(5, prefixPattern)      // 翻译前缀匹配
                        // WHERE 中的参数
                        stmt.set(6, likePattern)        // name 模糊搜索
                        stmt.set(7, likePattern)        // namespace:name 模糊搜索
                        stmt.set(8, lang)               // 翻译搜索的语言
                        stmt.set(9, likePattern)        // 翻译模糊搜索
                        stmt.set(10, likePattern)       // 全文本模糊搜索（备用）
                        stmt.set(11, limit)

                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let namespace = rs.getOrNull<String>(0) ?? ""
                                let name = rs.getOrNull<String>(1) ?? ""
                                let translationsJson = rs.getOrNull<String>(2) ?? "{}"

                                let fullName = if (namespace.size > 0) {
                                    "${namespace}:${name}"
                                } else {
                                    name
                                }

                                // 获取对应语言的翻译
                                let translations = parseTranslationsJson(translationsJson)
                                let translatedText = match (translations.get(lang)) {
                                    case Some(t) => if (t.text.size > 0) { t.text } else { name }
                                    case None => name
                                }

                                result.add((fullName, translatedText))
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("自动补全搜索失败", ("error", e.message), ("query", query))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => ()
        }
        return result
    }

    /**
     * 获取标签词云数据（按归档使用次数降序）
     * 返回: [(fullName, display, count)]
     */
    public static func getTagCloud(lang: String, limit: Int64): ArrayList<(String, String, Int64)> {
        var result: ArrayList<(String, String, Int64)> = ArrayList<(String, String, Int64)>()
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return result
            case Some(conn) =>
                try {
                    let sql = """
                        SELECT t.namespace, t.name,
                               COALESCE(t.translations->?->>'text', '') as translated_text,
                               COUNT(DISTINCT mo.entity_id)::BIGINT as usage_count
                        FROM tags t
                        INNER JOIN metadata_tags mt ON mt.tag = CASE WHEN COALESCE(t.namespace, '') != '' THEN t.namespace || ':' || t.name ELSE t.name END
                        INNER JOIN metadata_objects mo ON mo.id = mt.metadata_id AND mo.entity_type = 'archive'
                        WHERE COALESCE(LOWER(t.namespace), '') != 'source'
                        GROUP BY t.id, t.namespace, t.name, translated_text
                        ORDER BY usage_count DESC, t.name
                        LIMIT ?
                    """
                    let stmt = conn.prepareStatement(sql)
                    try {
                        stmt.set(0, lang)
                        stmt.set(1, limit)
                        let rs = stmt.query()
                        try {
                            while (rs.next()) {
                                let namespace = rs.getOrNull<String>(0) ?? ""
                                let name = rs.getOrNull<String>(1) ?? ""
                                let translated = rs.getOrNull<String>(2) ?? ""
                                let count = rs.getOrNull<Int64>(3) ?? 0

                                let fullName = if (namespace.size > 0) { "${namespace}:${name}" } else { name }
                                let display = if (translated.trimAscii().size > 0) { translated } else { name }
                                result.add((fullName, display, count))
                            }
                        } finally {
                            rs.close()
                        }
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("获取标签词云失败", ("error", e.message))
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
        return result
    }

    public static func updateIconAssetId(id: Int64, iconAssetId: Int64): Bool {
        if (id <= 0) { return false }
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("UPDATE tags SET icon_asset_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
                    try {
                        if (iconAssetId > 0) {
                            stmt.set(0, iconAssetId)
                        } else {
                            stmt.setNull(0)
                        }
                        stmt.set(1, id)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("updateIconAssetId failed", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    public static func updateBackgroundAssetId(id: Int64, backgroundAssetId: Int64): Bool {
        if (id <= 0) { return false }
        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case Some(conn) =>
                try {
                    let stmt = conn.prepareStatement("UPDATE tags SET background_asset_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
                    try {
                        if (backgroundAssetId > 0) {
                            stmt.set(0, backgroundAssetId)
                        } else {
                            stmt.setNull(0)
                        }
                        stmt.set(1, id)
                        stmt.update()
                        return true
                    } finally {
                        stmt.close()
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("updateBackgroundAssetId failed", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
            case None => return false
        }
    }

    /**
     * 合并标签（按 id）：将 sourceId 的关联关系迁移到 targetId，并可选删除 sourceId。
     * - metadata_tags：将 source tag string 迁移到 target tag string
     * - tags.translations：将 source 的 translations 合并到 target（target 同 key 优先）
     * - links/icon/background：仅在 target 为空时回填 source 的值
     */
    public static func mergeById(sourceId: Int64, targetId: Int64, deleteSource: Bool): Bool {
        if (sourceId <= 0 || targetId <= 0 || sourceId == targetId) { return false }

        let connOpt = DatabaseConfig.getPooledConnection()
        match (connOpt) {
            case None => return false
            case Some(conn) =>
                try {
                    // Best-effort transaction; if driver doesn't support BEGIN/COMMIT, statements still run in auto-commit.
                    try {
                        let begin = conn.prepareStatement("BEGIN")
                        try { begin.update() } finally { begin.close() }
                    } catch (_: Exception) {}

                    // Merge translations/fields: update target from source.
                    let mergeStmt = conn.prepareStatement("""
                        UPDATE tags t
                        SET
                            translations = s.translations || t.translations,
                            links = CASE WHEN COALESCE(t.links, '') = '' THEN COALESCE(s.links, '') ELSE t.links END,
                            icon_asset_id = CASE WHEN COALESCE(t.icon_asset_id, 0) = 0 THEN COALESCE(s.icon_asset_id, 0) ELSE t.icon_asset_id END,
                            background_asset_id = CASE WHEN COALESCE(t.background_asset_id, 0) = 0 THEN COALESCE(s.background_asset_id, 0) ELSE t.background_asset_id END,
                            updated_at = CURRENT_TIMESTAMP
                        FROM tags s
                        WHERE s.id = ? AND t.id = ?
                    """)
                    try {
                        mergeStmt.set(0, sourceId)
                        mergeStmt.set(1, targetId)
                        mergeStmt.update()
                    } finally { mergeStmt.close() }

                    // Resolve source/target canonical tag strings.
                    var sourceTag = ""
                    var targetTag = ""
                    let tagInfoStmt = conn.prepareStatement("""
                        SELECT
                            id,
                            CASE
                                WHEN COALESCE(namespace, '') != '' THEN namespace || ':' || name
                                ELSE name
                            END AS tag_str
                        FROM tags
                        WHERE id = ? OR id = ?
                    """)
                    try {
                        tagInfoStmt.set(0, sourceId)
                        tagInfoStmt.set(1, targetId)
                        let rs = tagInfoStmt.query()
                        try {
                            while (rs.next()) {
                                let id = rs.getOrNull<Int64>(0) ?? 0
                                let tagStr = rs.getOrNull<String>(1) ?? ""
                                if (id == sourceId) {
                                    sourceTag = tagStr
                                } else if (id == targetId) {
                                    targetTag = tagStr
                                }
                            }
                        } finally { rs.close() }
                    } finally { tagInfoStmt.close() }

                    if (sourceTag.trimAscii().size > 0 && targetTag.trimAscii().size > 0) {
                        let insMetadata = conn.prepareStatement("""
                            INSERT INTO metadata_tags (metadata_id, tag)
                            SELECT mt.metadata_id, ?
                            FROM metadata_tags mt
                            WHERE mt.tag = ?
                              AND NOT EXISTS (
                                  SELECT 1 FROM metadata_tags existing
                                  WHERE existing.metadata_id = mt.metadata_id AND existing.tag = ?
                              )
                        """)
                        try {
                            insMetadata.set(0, targetTag)
                            insMetadata.set(1, sourceTag)
                            insMetadata.set(2, targetTag)
                            insMetadata.update()
                        } finally { insMetadata.close() }

                        let delMetadata = conn.prepareStatement("DELETE FROM metadata_tags WHERE tag = ?")
                        try {
                            delMetadata.set(0, sourceTag)
                            delMetadata.update()
                        } finally { delMetadata.close() }
                    }

                    if (deleteSource) {
                        let delTag = conn.prepareStatement("DELETE FROM tags WHERE id = ?")
                        try {
                            delTag.set(0, sourceId)
                            delTag.update()
                        } finally { delTag.close() }
                    }

                    try {
                        let commit = conn.prepareStatement("COMMIT")
                        try { commit.update() } finally { commit.close() }
                    } catch (_: Exception) {}

                    invalidateTranslationSearchCache()
                    return true
                } catch (e: Exception) {
                    try {
                        let rb = conn.prepareStatement("ROLLBACK")
                        try { rb.update() } finally { rb.close() }
                    } catch (_: Exception) {}
                    getLogger("tag_dao").error("mergeById failed", ("error", e.message))
                    return false
                } finally {
                    try { conn.close() } catch (_: Exception) {}
                }
        }
    }
}
