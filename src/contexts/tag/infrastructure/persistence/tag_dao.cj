package lanlu.contexts.tag.infrastructure.persistence

import csorm.*
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

    private static func extensionInstalled(db: Database, extensionName: String): Bool {
        try {
            return db.rawOne<Int64>(
                "SELECT 1 FROM pg_extension WHERE extname = $1 LIMIT 1",
                [vtext(extensionName)],
                { row => row.getInt64(0) }
            ).isSome()
        } catch (_: Exception) {
            return false
        }
    }

    private static func functionExists(db: Database, functionName: String): Bool {
        try {
            return db.rawOne<Int64>(
                "SELECT 1 FROM pg_proc WHERE proname = $1 LIMIT 1",
                [vtext(functionName)],
                { row => row.getInt64(0) }
            ).isSome()
        } catch (_: Exception) {
            return false
        }
    }

    private static func getUnaccentFunction(db: Database): String {
        if (functionExists(db, "lanlu_immutable_unaccent")) {
            return "lanlu_immutable_unaccent"
        }
        if (extensionInstalled(db, "unaccent")) {
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
        match (DatabaseConfig.getDatabase()) {
            case None => return 0
            case Some(db) =>
                try {
                    return getOrCreateTagInternal(db, namespace, name)
                } catch (e: Exception) {
                    logger.error("getOrCreate failed", ("error", e.message), ("namespace", namespace), ("name", name))
                    return 0
                }
        }
    }

    /**
     * 内部方法：获取或创建标签（使用已有连接）
     */
    private static func getOrCreateTagInternal(db: Database, namespace: String, name: String): Int64 {
        let selectSql = "SELECT id FROM tags WHERE namespace = $1 AND name = $2 LIMIT 1"
        let selectParams: Array<Value> = [vtext(namespace), vtext(name)]
        match (db.rawOne<Int64>(selectSql, selectParams, { row => row.getInt64(0) })) {
            case Some(id) => return id
            case None => ()
        }

        let insertSql = """
            INSERT INTO tags (namespace, name)
            SELECT $1, $2
            WHERE NOT EXISTS (
                SELECT 1 FROM tags WHERE namespace = $3 AND name = $4
            )
        """
        let insertParams: Array<Value> = [vtext(namespace), vtext(name), vtext(namespace), vtext(name)]
        try {
            db.execRaw(insertSql, insertParams)
        } catch (_: Exception) {
            // Concurrent inserts may race; reload the row below.
        }

        let reloadSql = "SELECT id FROM tags WHERE namespace = $1 AND name = $2 LIMIT 1"
        let reloadParams: Array<Value> = [vtext(namespace), vtext(name)]
        match (db.rawOne<Int64>(reloadSql, reloadParams, { row => row.getInt64(0) })) {
            case Some(id) => return id
            case None => ()
        }

        0
    }

    /**
     * 在指定连接中补齐 tags 字典记录，不修改 metadata_tags。
     */
    public static func ensureTagDictionaryEntriesWithConnection(db: Database, tags: Array<String>): Bool {
        let normalizedTags = normalizeTags(tags)
        try {
            for (tag in normalizedTags) {
                let (rawNamespace, rawName) = parseTagName(tag)
                let namespace = rawNamespace.trimAscii()
                let name = rawName.trimAscii()
                if (name.size == 0) {
                    continue
                }
                let tagId = getOrCreateTagInternal(db, namespace, name)
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
        match (DatabaseConfig.getDatabase()) {
            case None => return false
            case Some(db) =>
                try {
                    return ensureTagDictionaryEntriesWithConnection(db, tags)
                } catch (e: Exception) {
                    logger.error("ensureTagDictionaryEntries failed", ("error", e.message))
                    return false
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
        match (DatabaseConfig.getDatabase()) {
            case None => false
            case Some(db) =>
                try {
                    // Ensure archive root metadata exists and resolve metadata id.
                    var metadataId: Int64 = 0
                    let getMetadataSql = """
                        SELECT id
                        FROM metadata_objects
                        WHERE entity_type = 'archive' AND entity_id = $1
                        LIMIT 1
                    """
                    match (db.rawOne<Int64>(getMetadataSql, [vtext(archiveId)], { row => row.getInt64(0) })) {
                        case Some(id) => metadataId = id
                        case None => ()
                    }

                    if (metadataId <= 0) {
                        let createMetadataSql = """
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
                            WHERE a.arcid = $1
                            RETURNING id
                        """
                        match (db.rawOne<Int64>(createMetadataSql, [vtext(archiveId)], { r => r.getInt64(0) })) {
                            case Some(id) => metadataId = id
                            case None => ()
                        }
                    }
                    if (metadataId <= 0) {
                        return false
                    }

                    // Delete existing tags for this archive metadata object.
                    db.execRaw("DELETE FROM metadata_tags WHERE metadata_id = $1", [vint(metadataId)])

                    // 如果标签字符串为空，直接返回
                    if (tagsString.size == 0 || tagsString == "") {
                        db.execRaw("UPDATE metadata_objects SET updated_at = CURRENT_TIMESTAMP WHERE id = $1", [vint(metadataId)])
                        let _ = DerivedCacheUtils.bumpTankoubonAggregatedContentVersion("updateArchiveTags:${archiveId}")
                        return true
                    }

                    // 解析标签字符串
                    let tags = normalizeTags(parseTagsString(tagsString).toArray())

                    if (!ensureTagDictionaryEntriesWithConnection(db, tags)) {
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
                        let insertRelationSql = """
                            INSERT INTO metadata_tags (metadata_id, tag)
                            SELECT $1, $2
                            WHERE NOT EXISTS (
                                SELECT 1 FROM metadata_tags WHERE metadata_id = $3 AND tag = $4
                            )
                        """
                        db.execRaw(insertRelationSql, [vint(metadataId), vtext(normalizedTag), vint(metadataId), vtext(normalizedTag)])
                    }

                    db.execRaw("UPDATE metadata_objects SET updated_at = CURRENT_TIMESTAMP WHERE id = $1", [vint(metadataId)])
                    let _ = DerivedCacheUtils.bumpTankoubonAggregatedContentVersion("updateArchiveTags:${archiveId}")
                    true
                } catch (e: Exception) {
                    getLogger("tag_dao").error("Error updating archive tags", ("error", e.message))
                    false
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
        let sql = """
            SELECT COALESCE(string_agg(mt.tag, ',' ORDER BY mt.tag), '')
            FROM metadata_objects mo
            LEFT JOIN metadata_tags mt ON mt.metadata_id = mo.id
            WHERE mo.entity_type = 'archive'
              AND mo.entity_id = $1
        """
        match (DatabaseConfig.getDatabase()) {
            case None => ""
            case Some(db) =>
                try {
                    return db.rawOne<String>(sql, [vtext(archiveId)], { row => row.getOrNullText(0) ?? "" }) ?? ""
                } catch (e: Exception) {
                    getLogger("tag_dao").error("Error getting archive tags", ("error", e.message))
                    ""
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

        let sql = """
            SELECT mo.entity_id, COALESCE(string_agg(mt.tag, ',' ORDER BY mt.tag), '')
            FROM metadata_objects mo
            LEFT JOIN metadata_tags mt ON mt.metadata_id = mo.id
            WHERE mo.entity_type = 'archive'
              AND mo.entity_id = ANY($1::text[])
            GROUP BY mo.entity_id
        """
        match (DatabaseConfig.getDatabase()) {
            case None => return result
            case Some(db) =>
                try {
                    let rows = db.raw<(String, String)>(sql, [textArray(deduped.toArray())], { row =>
                        (row.getOrNullText(0) ?? "", row.getOrNullText(1) ?? "")
                    })
                    for ((arcid, tags) in rows) {
                        let id = arcid.trimAscii()
                        if (id.size == 0) { continue }
                        result[id] = tags
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("批量获取 archive tags 失败", ("error", e.message))
                    return result
                }
        }

        return result
    }

    /**
     * 获取所有标签（支持分页和搜索）
     */
    public static func list(namespace: ?String, query: ?String, limit: Int64, offset: Int64): ArrayList<TagData> {
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    var sql = "SELECT id, namespace, name, translations, links, icon_asset_id, background_asset_id, created_at, updated_at FROM tags WHERE 1=1"
                    var params: ArrayList<Value> = ArrayList<Value>()
                    let unaccentFunction = getUnaccentFunction(db)
                    var paramIndex = 1

                    match (namespace) {
                        case Some(ns) =>
                            sql += " AND namespace = \$${paramIndex}"
                            params.add(vtext(ns))
                            paramIndex += 1
                        case None => ()
                    }

                    match (query) {
                        case Some(q) =>
                            if (q.size > 0) {
                                let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(\$${paramIndex})" } else { "\$${paramIndex}" }
                                sql += " AND (" + wrapSearchExpr("name", unaccentFunction) + " ILIKE " + patternExpr +
                                        " OR " + wrapSearchExpr("translations::text", unaccentFunction) + " ILIKE " + patternExpr + ")"
                                let searchPattern = "%${q}%"
                                params.add(vtext(searchPattern))
                                params.add(vtext(searchPattern))
                                paramIndex += 2
                            }
                        case None => ()
                    }

                    sql += " ORDER BY namespace, name LIMIT \$${paramIndex} OFFSET \$${paramIndex + 1}"
                    params.add(vint(limit))
                    params.add(vint(offset))

                    let list = db.raw<TagData>(sql, params.toArray(), { row =>
                        let tag = TagData()
                        tag.id = row.getOrNullInt64(0) ?? 0
                        tag.namespace = row.getOrNullText(1) ?? ""
                        tag.name = row.getOrNullText(2) ?? ""
                        let translationsJson = row.getOrNullJson(3) ?? "{}"
                        tag.translations = parseTranslationsJson(translationsJson)
                        tag.links = row.getOrNullText(4) ?? ""
                        tag.iconAssetId = row.getOrNullInt64(5) ?? 0
                        tag.backgroundAssetId = row.getOrNullInt64(6) ?? 0
                        tag.created_at = row.getOrNullText(7) ?? ""
                        tag.updated_at = row.getOrNullText(8) ?? ""
                        tag
                    })
                    return ArrayList<TagData>(list)
                } catch (e: Exception) {
                    getLogger("tag_dao").error("查询标签列表失败", ("error", e.message))
                    return ArrayList<TagData>()
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
        let connOpt = DatabaseConfig.getDatabase()
        var effectiveLang = lang.trimAscii()
        if (effectiveLang.size == 0) { effectiveLang = "zh" }
        match (connOpt) {
            case Some(db) =>
                try {
                    var sql = """
                        SELECT
                            id,
                            namespace,
                            name,
                            COALESCE(translations -> $1 ->> 'text', '') AS translation_text
                        FROM tags
                        WHERE 1=1
                    """
                    var params: ArrayList<Value> = ArrayList<Value>()
                    let unaccentFunction = getUnaccentFunction(db)
                    var paramIndex = 2

                    // First param is lang for JSONB extraction.
                    params.add(vtext(effectiveLang))

                    match (namespace) {
                        case Some(ns) =>
                            sql += " AND namespace = \$${paramIndex}"
                            params.add(vtext(ns))
                            paramIndex += 1
                        case None => ()
                    }

                    match (query) {
                        case Some(q) =>
                            if (q.size > 0) {
                                let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(\$${paramIndex})" } else { "\$${paramIndex}" }
                                sql += " AND (" + wrapSearchExpr("name", unaccentFunction) + " ILIKE " + patternExpr +
                                        " OR " + wrapSearchExpr("translations::text", unaccentFunction) + " ILIKE " + patternExpr + ")"
                                let searchPattern = "%${q}%"
                                params.add(vtext(searchPattern))
                                params.add(vtext(searchPattern))
                                paramIndex += 2
                            }
                        case None => ()
                    }

                    sql += " ORDER BY namespace, name LIMIT \$${paramIndex} OFFSET \$${paramIndex + 1}"
                    params.add(vint(limit))
                    params.add(vint(offset))

                    let list = db.raw<TagLiteData>(sql, params.toArray(), { row =>
                        let r = TagLiteData()
                        r.id = row.getOrNullInt64(0) ?? 0
                        r.namespace = row.getOrNullText(1) ?? ""
                        r.name = row.getOrNullText(2) ?? ""
                        r.translationText = row.getOrNullText(3) ?? ""
                        r
                    })
                    return ArrayList<TagLiteData>(list)
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
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    var sql = "SELECT COUNT(*) FROM tags WHERE 1=1"
                    var params: ArrayList<Value> = ArrayList<Value>()
                    let unaccentFunction = getUnaccentFunction(db)
                    var paramIndex = 1

                    match (namespace) {
                        case Some(ns) =>
                            sql += " AND namespace = \$${paramIndex}"
                            params.add(vtext(ns))
                            paramIndex += 1
                        case None => ()
                    }

                    match (query) {
                        case Some(q) =>
                            if (q.size > 0) {
                                let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}(\$${paramIndex})" } else { "\$${paramIndex}" }
                                sql += " AND (" + wrapSearchExpr("name", unaccentFunction) + " ILIKE " + patternExpr +
                                        " OR " + wrapSearchExpr("translations::text", unaccentFunction) + " ILIKE " + patternExpr + ")"
                                let searchPattern = "%${q}%"
                                params.add(vtext(searchPattern))
                                params.add(vtext(searchPattern))
                                paramIndex += 2
                            }
                        case None => ()
                    }

                    return db.rawOne<Int64>(sql, params.toArray(), { row => row.getOrNullInt64(0) ?? 0 }) ?? 0
                } catch (e: Exception) {
                    getLogger("tag_dao").error("统计标签数量失败", ("error", e.message))
                    return 0
                }
            case None =>
                return 0
        }
    }

    /**
     * 根据ID获取标签
     */
    public static func getById(id: Int64): ?TagData {
        let sql = "SELECT id, namespace, name, translations, links, icon_asset_id, background_asset_id, created_at, updated_at FROM tags WHERE id = $1"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<TagData>(sql, [vint(id)], { row =>
                        let tag = TagData()
                        tag.id = row.getOrNullInt64(0) ?? 0
                        tag.namespace = row.getOrNullText(1) ?? ""
                        tag.name = row.getOrNullText(2) ?? ""
                        let translationsJson = row.getOrNullJson(3) ?? "{}"
                        tag.translations = parseTranslationsJson(translationsJson)
                        tag.links = row.getOrNullText(4) ?? ""
                        tag.iconAssetId = row.getOrNullInt64(5) ?? 0
                        tag.backgroundAssetId = row.getOrNullInt64(6) ?? 0
                        tag.created_at = row.getOrNullText(7) ?? ""
                        tag.updated_at = row.getOrNullText(8) ?? ""
                        tag
                    })
                } catch (e: Exception) {
                    getLogger("tag_dao").error("查询标签失败", ("error", e.message), ("id", id.toString()))
                    return None
                }
            case None =>
                return None
        }
    }

    /**
     * 根据 namespace 和 name 获取标签
     */
    public static func getByNamespaceName(namespace: String, name: String): ?TagData {
        let sql = "SELECT id, namespace, name, translations, links, icon_asset_id, background_asset_id, created_at, updated_at FROM tags WHERE namespace = $1 AND name = $2"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    return db.rawOne<TagData>(sql, [vtext(namespace), vtext(name)], { row =>
                        let tag = TagData()
                        tag.id = row.getOrNullInt64(0) ?? 0
                        tag.namespace = row.getOrNullText(1) ?? ""
                        tag.name = row.getOrNullText(2) ?? ""
                        let translationsJson = row.getOrNullJson(3) ?? "{}"
                        tag.translations = parseTranslationsJson(translationsJson)
                        tag.links = row.getOrNullText(4) ?? ""
                        tag.iconAssetId = row.getOrNullInt64(5) ?? 0
                        tag.backgroundAssetId = row.getOrNullInt64(6) ?? 0
                        tag.created_at = row.getOrNullText(7) ?? ""
                        tag.updated_at = row.getOrNullText(8) ?? ""
                        tag
                    })
                } catch (e: Exception) {
                    getLogger("tag_dao").error("查询标签失败", ("error", e.message))
                    return None
                }
            case None =>
                return None
        }
    }

    /**
     * 创建标签
     */
    public static func create(namespace: String, name: String, translations: HashMap<String, TagTranslation>, links: String): Int64 {
        let sql = "INSERT INTO tags (namespace, name, translations, links) VALUES ($1, $2, $3::jsonb, $4) RETURNING id"
        let translationsJson = serializeTranslationsJson(translations)
        let params: Array<Value> = [vtext(namespace), vtext(name), vjson(translationsJson), vtext(links)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let idOpt = db.rawOne<Int64>(sql, params, { r => r.getInt64(0) })
                    match (idOpt) {
                        case Some(id) =>
                            if (id > 0) {
                                invalidateTranslationSearchCache()
                            }
                            return id
                        case None => return 0
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("创建标签失败", ("error", e.message), ("namespace", namespace), ("name", name))
                    return 0
                }
            case None =>
                return 0
        }
    }

    /**
     * 更新标签
     */
    public static func update(id: Int64, translations: HashMap<String, TagTranslation>, links: String): Bool {
        let sql = "UPDATE tags SET translations = $1::jsonb, links = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3"
        let translationsJson = serializeTranslationsJson(translations)
        let params: Array<Value> = [vjson(translationsJson), vtext(links), vint(id)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    invalidateTranslationSearchCache()
                    return true
                } catch (e: Exception) {
                    getLogger("tag_dao").error("更新标签失败", ("error", e.message), ("id", id.toString()))
                    return false
                }
            case None =>
                return false
        }
    }

    /**
     * 删除标签
     */
    public static func delete(id: Int64): Bool {
        let sql = "DELETE FROM tags WHERE id = $1"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, [vint(id)])
                    invalidateTranslationSearchCache()
                    return true
                } catch (e: Exception) {
                    getLogger("tag_dao").error("删除标签失败", ("error", e.message), ("id", id.toString()))
                    return false
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

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    // Use row-wise IN to avoid long OR chains and keep it index-friendly.
                    // WHERE (namespace, name) IN (($1, $2), ($3, $4), ...)
                    var tuples: ArrayList<String> = ArrayList<String>()
                    var namespaces: ArrayList<String> = ArrayList<String>()
                    var names: ArrayList<String> = ArrayList<String>()
                    var paramIndex = 1
                    for (_tag in tags) {
                        let (namespace, name) = parseTagName(_tag)
                        tuples.add("(\$${paramIndex}, \$${paramIndex + 1})")
                        namespaces.add(namespace)
                        names.add(name)
                        paramIndex += 2
                    }

                    let tuplesStr = String.join(tuples.toArray(), delimiter: ", ")
                    let sql = "SELECT namespace, name, translations FROM tags WHERE (namespace, name) IN (" + tuplesStr + ")"
                    var params: ArrayList<Value> = ArrayList<Value>()
                    for (i in 0..namespaces.size) {
                        params.add(vtext(namespaces[i]))
                        params.add(vtext(names[i]))
                    }

                    let rows = db.raw<(String, String, String)>(sql, params.toArray(), { row =>
                        (row.getOrNullText(0) ?? "", row.getOrNullText(1) ?? "", row.getOrNullJson(2) ?? "{}")
                    })
                    for ((namespace, name, translationsJson) in rows) {
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
                } catch (e: Exception) {
                    getLogger("tag_dao").error("批量获取标签翻译失败", ("error", e.message))
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

        let sql = "SELECT namespace, name, translations FROM tags"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<(String, String, String)>(sql, [], { row =>
                        (row.getOrNullText(0) ?? "", row.getOrNullText(1) ?? "", row.getOrNullJson(2) ?? "{}")
                    })
                    for ((namespace, name, translationsJson) in rows) {
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
                } catch (e: Exception) {
                    getLogger("tag_dao").error("获取标签翻译映射失败", ("error", e.message))
                }
            case None => ()
        }
        return result
    }

    /**
     * 获取所有命名空间
     */
    public static func listNamespaces(): Array<String> {
        let sql = "SELECT DISTINCT namespace FROM tags WHERE namespace != '' ORDER BY namespace"
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<String>(sql, [], { row => row.getOrNullText(0) ?? "" })
                    var list: ArrayList<String> = ArrayList<String>()
                    for (ns in rows) {
                        if (ns.size > 0) {
                            list.add(ns)
                        }
                    }
                    return list.toArray()
                } catch (e: Exception) {
                    getLogger("tag_dao").error("获取命名空间列表失败", ("error", e.message))
                    return Array<String>()
                }
            case None =>
                getLogger("tag_dao").error("无法连接到数据库")
                return Array<String>()
        }
    }

    /**
     * 获取当前系统已存在的所有标签名（用于自动补全等）
     */
    public static func listAllTagNames(): Array<String> {
        let sql = """
            SELECT DISTINCT
                CASE WHEN namespace != '' AND namespace IS NOT NULL
                     THEN namespace || ':' || name
                     ELSE name
                END AS full_name
            FROM tags
            ORDER BY full_name
        """
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let rows = db.raw<String>(sql, [], { row => row.getOrNullText(0) ?? "" })
                    var list: ArrayList<String> = ArrayList<String>()
                    for (name in rows) {
                        if (name.trimAscii().size > 0) {
                            list.add(name)
                        }
                    }
                    return list.toArray()
                } catch (e: Exception) {
                    getLogger("tag_dao").error("获取全量标签失败", ("error", e.message))
                    return Array<String>()
                }
            case None =>
                return Array<String>()
        }
    }

    /**
     * 插入或更新标签（用于导入）
     */
    public static func upsert(namespace: String, name: String, translations: HashMap<String, TagTranslation>, links: String): Bool {
        let translationsJson = serializeTranslationsJson(translations)
        let updateSql = """
            UPDATE tags
            SET translations = $1::jsonb, links = $2, updated_at = CURRENT_TIMESTAMP
            WHERE namespace = $3 AND name = $4
        """
        let updateParams: Array<Value> = [vjson(translationsJson), vtext(links), vtext(namespace), vtext(name)]
        let insertSql = """
            INSERT INTO tags (namespace, name, translations, links)
            SELECT $1, $2, $3::jsonb, $4
            WHERE NOT EXISTS (
                SELECT 1 FROM tags WHERE namespace = $5 AND name = $6
            )
        """
        let insertParams: Array<Value> = [vtext(namespace), vtext(name), vjson(translationsJson), vtext(links), vtext(namespace), vtext(name)]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let updated = db.execRaw(updateSql, updateParams)
                    if (updated <= 0) {
                        db.execRaw(insertSql, insertParams)
                    }
                    invalidateTranslationSearchCache()
                    return true
                } catch (e: Exception) {
                    getLogger("tag_dao").error("upsert标签失败", ("error", e.message), ("namespace", namespace), ("name", name))
                    return false
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

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let queried = queryTagsByTranslationWithConn(db, normalizedSearchTerm)
                    writeTranslationSearchCache(cacheKey, queried)
                    logger.debug("tag translation search cache store",
                        ("searchTerm", normalizedSearchTerm),
                        ("version", cacheVersion.toString()),
                        ("resultCount", queried.size.toString()))
                    return queried
                } catch (e: Exception) {
                    getLogger("tag_dao").error("根据翻译查找标签失败", ("error", e.message), ("searchTerm", normalizedSearchTerm))
                }
            case None => ()
        }

        return result
    }

    /**
     * 根据翻译文本查找标签（使用已有连接，避免嵌套连接泄漏）
     * 用于在持有连接的情况下调用，避免连接池耗尽
     */
    public static func findTagsByTranslationWithConn(db: Database, searchTerm: String): ArrayList<String> {
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

        let queried = queryTagsByTranslationWithConn(db, normalizedSearchTerm)
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
    public static func batchFindTagsByTranslationWithConn(db: Database, searchTerms: Array<String>): HashMap<String, ArrayList<String>> {
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
            let queried = queryTagsByTranslationsWithConn(db, uncachedNormalizedTerms.toArray())
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

    private static func queryTagsByTranslationWithConn(db: Database, normalizedSearchTerm: String): ArrayList<String> {
        let result = ArrayList<String>()
        try {
            let unaccentFunction = getUnaccentFunction(db)
            // 使用 translations::text ILIKE 在 JSONB 文本中模糊搜索。
            // Add a LIMIT to cap worst-case work and response size (caller expands matches into OR tags LIKE ...).
            let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}($1)" } else { "$1" }
            let sql = "SELECT namespace, name FROM tags WHERE " + wrapSearchExpr("translations::text", unaccentFunction) + " ILIKE " + patternExpr + " LIMIT 200"
            let pattern = "%" + normalizedSearchTerm + "%"
            let rows = db.raw<(String, String)>(sql, [vtext(pattern)], { row =>
                (row.getOrNullText(0) ?? "", row.getOrNullText(1) ?? "")
            })
            for ((namespace, name) in rows) {
                let fullName = if (namespace.size > 0) {
                    "${namespace}:${name}"
                } else {
                    name
                }
                result.add(fullName)
            }
        } catch (e: Exception) {
            getLogger("tag_dao").error("根据翻译查找标签失败", ("error", e.message), ("searchTerm", normalizedSearchTerm))
        }
        return result
    }

    private static func queryTagsByTranslationsWithConn(db: Database, normalizedSearchTerms: Array<String>): HashMap<String, ArrayList<String>> {
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
            let unaccentFunction = getUnaccentFunction(db)
            let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}($1)" } else { "$1" }
            let searchExpr = wrapSearchExpr("translations::text", unaccentFunction)
            let subqueries = ArrayList<String>()
            var paramIndex = 1
            for (_term in uniqueTerms) {
                subqueries.add("SELECT \$${paramIndex} AS matched_term, namespace, name FROM tags WHERE ${searchExpr} ILIKE ${patternExpr} LIMIT 200")
                paramIndex += 2
            }
            let sql = String.join(subqueries.toArray(), delimiter: " UNION ALL ")
            var params: ArrayList<Value> = ArrayList<Value>()
            for (normalized in uniqueTerms) {
                params.add(vtext(normalized))
                params.add(vtext("%" + normalized + "%"))
            }
            let rows = db.raw<(String, String, String)>(sql, params.toArray(), { row =>
                (row.getOrNullText(0) ?? "", row.getOrNullText(1) ?? "", row.getOrNullText(2) ?? "")
            })
            let seenByTerm = HashMap<String, HashMap<String, Bool>>()
            for ((matchedTerm, namespace, name) in rows) {
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
        } catch (_: Exception) {
            for (normalized in uniqueTerms) {
                result[normalized] = queryTagsByTranslationWithConn(db, normalized)
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

        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    let unaccentFunction = getUnaccentFunction(db)
                    // 参数顺序：$1 name 精确匹配, $2 name 前缀匹配, $3 翻译精确匹配的语言,
                    // $4 翻译精确匹配, $5 翻译前缀匹配的语言, $6 翻译前缀匹配,
                    // $7 name 模糊搜索, $8 namespace:name 模糊搜索, $9 翻译搜索的语言,
                    // $10 翻译模糊搜索, $11 全文本模糊搜索（备用）, $12 limit
                    let patternExpr = if (unaccentFunction.size > 0) { "${unaccentFunction}($n)" } else { "$n" }
                    // Note: patternExpr is a template; we replace $n with the actual placeholder index below.
                    let nameExpr = wrapSearchExpr("t.name", unaccentFunction)
                    let fullNameExpr = wrapSearchExpr("CASE WHEN t.namespace != '' THEN t.namespace || ':' || t.name ELSE t.name END", unaccentFunction)
                    // 翻译文本表达式按分支使用不同的 lang 占位符($3 精确/$5 前缀/$9 模糊)，
                    // 否则 $5/$9 在 SQL 中不出现，PG 报 "could not determine data type of parameter $5"。
                    let translationTextExact = wrapSearchExpr("t.translations->$3->>'text'", unaccentFunction)
                    let translationTextPrefix = wrapSearchExpr("t.translations->$5->>'text'", unaccentFunction)
                    let translationTextFuzzy = wrapSearchExpr("t.translations->$9->>'text'", unaccentFunction)
                    let translationsExpr = wrapSearchExpr("t.translations::text", unaccentFunction)
                    // 搜索标签名(namespace:name)和翻译文本。
                    // 默认只返回“已绑定档案”的标签，供全局搜索框等场景使用；
                    // 但编辑档案标签时需要可选到“未绑定任何档案”的标签，因此支持关闭该约束。
                    // 使用 JSONB 提取指定语言的翻译文本进行搜索。
                    // 优先级：1=name精确匹配, 2=name前缀匹配, 3=翻译精确匹配, 4=翻译前缀匹配, 5=模糊匹配
                    let sql = if (requireBound) {
                        "SELECT DISTINCT t.namespace, t.name, t.translations," +
                        " CASE" +
                        " WHEN " + nameExpr + " ILIKE " + patternExpr.replace("$n", "$1") + " THEN 1" +
                        " WHEN " + nameExpr + " ILIKE " + patternExpr.replace("$n", "$2") + " THEN 2" +
                        " WHEN " + translationTextExact + " ILIKE " + patternExpr.replace("$n", "$4") + " THEN 3" +
                        " WHEN " + translationTextPrefix + " ILIKE " + patternExpr.replace("$n", "$6") + " THEN 4" +
                        " ELSE 5 END as match_priority" +
                        " FROM tags t" +
                        " INNER JOIN metadata_tags mt ON mt.tag = CASE WHEN COALESCE(t.namespace, '') != '' THEN t.namespace || ':' || t.name ELSE t.name END" +
                        " INNER JOIN metadata_objects mo ON mo.id = mt.metadata_id AND mo.entity_type = 'archive'" +
                        " WHERE " + nameExpr + " ILIKE " + patternExpr.replace("$n", "$7") +
                        " OR " + fullNameExpr + " ILIKE " + patternExpr.replace("$n", "$8") +
                        " OR " + translationTextFuzzy + " ILIKE " + patternExpr.replace("$n", "$10") +
                        " OR " + translationsExpr + " ILIKE " + patternExpr.replace("$n", "$11") +
                        " ORDER BY match_priority, t.name" +
                        " LIMIT $12"
                    } else {
                        "SELECT DISTINCT t.namespace, t.name, t.translations," +
                        " CASE" +
                        " WHEN " + nameExpr + " ILIKE " + patternExpr.replace("$n", "$1") + " THEN 1" +
                        " WHEN " + nameExpr + " ILIKE " + patternExpr.replace("$n", "$2") + " THEN 2" +
                        " WHEN " + translationTextExact + " ILIKE " + patternExpr.replace("$n", "$4") + " THEN 3" +
                        " WHEN " + translationTextPrefix + " ILIKE " + patternExpr.replace("$n", "$6") + " THEN 4" +
                        " ELSE 5 END as match_priority" +
                        " FROM tags t" +
                        " WHERE " + nameExpr + " ILIKE " + patternExpr.replace("$n", "$7") +
                        " OR " + fullNameExpr + " ILIKE " + patternExpr.replace("$n", "$8") +
                        " OR " + translationTextFuzzy + " ILIKE " + patternExpr.replace("$n", "$10") +
                        " OR " + translationsExpr + " ILIKE " + patternExpr.replace("$n", "$11") +
                        " ORDER BY match_priority, t.name" +
                        " LIMIT $12"
                    }
                    let exactPattern = query
                    let prefixPattern = query + "%"
                    let likePattern = "%" + query + "%"
                    let params: Array<Value> = [
                        vtext(exactPattern),       // $1 name 精确匹配优先级
                        vtext(prefixPattern),      // $2 name 前缀匹配优先级
                        vtext(lang),               // $3 翻译精确匹配的语言
                        vtext(exactPattern),       // $4 翻译精确匹配
                        vtext(lang),               // $5 翻译前缀匹配的语言
                        vtext(prefixPattern),      // $6 翻译前缀匹配
                        vtext(likePattern),        // $7 name 模糊搜索
                        vtext(likePattern),        // $8 namespace:name 模糊搜索
                        vtext(lang),               // $9 翻译搜索的语言
                        vtext(likePattern),        // $10 翻译模糊搜索
                        vtext(likePattern),        // $11 全文本模糊搜索（备用）
                        vint(limit)                // $12 limit
                    ]

                    let rows = db.raw<(String, String, String)>(sql, params, { row =>
                        (row.getOrNullText(0) ?? "", row.getOrNullText(1) ?? "", row.getOrNullJson(2) ?? "{}")
                    })
                    for ((namespace, name, translationsJson) in rows) {
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
                } catch (e: Exception) {
                    getLogger("tag_dao").error("自动补全搜索失败", ("error", e.message), ("query", query))
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
        let sql = """
            SELECT t.namespace, t.name,
                   COALESCE(t.translations->$1->>'text', '') as translated_text,
                   COUNT(DISTINCT mo.entity_id)::BIGINT as usage_count
            FROM tags t
            INNER JOIN metadata_tags mt ON mt.tag = CASE WHEN COALESCE(t.namespace, '') != '' THEN t.namespace || ':' || t.name ELSE t.name END
            INNER JOIN metadata_objects mo ON mo.id = mt.metadata_id AND mo.entity_type = 'archive'
            WHERE COALESCE(LOWER(t.namespace), '') != 'source'
            GROUP BY t.id, t.namespace, t.name, translated_text
            ORDER BY usage_count DESC, t.name
            LIMIT $2
        """
        let params: Array<Value> = [vtext(lang), vint(limit)]
        match (DatabaseConfig.getDatabase()) {
            case None => return result
            case Some(db) =>
                try {
                    let rows = db.raw<(String, String, String, Int64)>(sql, params, { row =>
                        (row.getOrNullText(0) ?? "", row.getOrNullText(1) ?? "", row.getOrNullText(2) ?? "", row.getOrNullInt64(3) ?? 0)
                    })
                    for ((namespace, name, translated, count) in rows) {
                        let fullName = if (namespace.size > 0) { "${namespace}:${name}" } else { name }
                        let display = if (translated.trimAscii().size > 0) { translated } else { name }
                        result.add((fullName, display, count))
                    }
                } catch (e: Exception) {
                    getLogger("tag_dao").error("获取标签词云失败", ("error", e.message))
                }
        }
        return result
    }

    public static func updateIconAssetId(id: Int64, iconAssetId: Int64): Bool {
        if (id <= 0) { return false }
        let sql = "UPDATE tags SET icon_asset_id = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2"
        let params: Array<Value> = [
            if (iconAssetId > 0) { vint(iconAssetId) } else { vnull() },
            vint(id)
        ]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    getLogger("tag_dao").error("updateIconAssetId failed", ("error", e.message))
                    return false
                }
            case None => return false
        }
    }

    public static func updateBackgroundAssetId(id: Int64, backgroundAssetId: Int64): Bool {
        if (id <= 0) { return false }
        let sql = "UPDATE tags SET background_asset_id = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2"
        let params: Array<Value> = [
            if (backgroundAssetId > 0) { vint(backgroundAssetId) } else { vnull() },
            vint(id)
        ]
        match (DatabaseConfig.getDatabase()) {
            case Some(db) =>
                try {
                    db.execRaw(sql, params)
                    return true
                } catch (e: Exception) {
                    getLogger("tag_dao").error("updateBackgroundAssetId failed", ("error", e.message))
                    return false
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

        match (DatabaseConfig.getDatabase()) {
            case None => return false
            case Some(db) =>
                try {
                    // Best-effort transaction; if driver doesn't support BEGIN/COMMIT, statements still run in auto-commit.
                    try {
                        db.execRawSql("BEGIN")
                    } catch (_: Exception) {}

                    // Merge translations/fields: update target from source.
                    let mergeSql = """
                        UPDATE tags t
                        SET
                            translations = s.translations || t.translations,
                            links = CASE WHEN COALESCE(t.links, '') = '' THEN COALESCE(s.links, '') ELSE t.links END,
                            icon_asset_id = CASE WHEN COALESCE(t.icon_asset_id, 0) = 0 THEN COALESCE(s.icon_asset_id, 0) ELSE t.icon_asset_id END,
                            background_asset_id = CASE WHEN COALESCE(t.background_asset_id, 0) = 0 THEN COALESCE(s.background_asset_id, 0) ELSE t.background_asset_id END,
                            updated_at = CURRENT_TIMESTAMP
                        FROM tags s
                        WHERE s.id = $1 AND t.id = $2
                    """
                    db.execRaw(mergeSql, [vint(sourceId), vint(targetId)])

                    // Resolve source/target canonical tag strings.
                    var sourceTag = ""
                    var targetTag = ""
                    let tagInfoSql = """
                        SELECT
                            id,
                            CASE
                                WHEN COALESCE(namespace, '') != '' THEN namespace || ':' || name
                                ELSE name
                            END AS tag_str
                        FROM tags
                        WHERE id = $1 OR id = $2
                    """
                    let rows = db.raw<(Int64, String)>(tagInfoSql, [vint(sourceId), vint(targetId)], { row =>
                        (row.getOrNullInt64(0) ?? 0, row.getOrNullText(1) ?? "")
                    })
                    for ((id, tagStr) in rows) {
                        if (id == sourceId) {
                            sourceTag = tagStr
                        } else if (id == targetId) {
                            targetTag = tagStr
                        }
                    }

                    if (sourceTag.trimAscii().size > 0 && targetTag.trimAscii().size > 0) {
                        let insMetadataSql = """
                            INSERT INTO metadata_tags (metadata_id, tag)
                            SELECT mt.metadata_id, $1
                            FROM metadata_tags mt
                            WHERE mt.tag = $2
                              AND NOT EXISTS (
                                  SELECT 1 FROM metadata_tags existing
                                  WHERE existing.metadata_id = mt.metadata_id AND existing.tag = $3
                              )
                        """
                        db.execRaw(insMetadataSql, [vtext(targetTag), vtext(sourceTag), vtext(targetTag)])

                        db.execRaw("DELETE FROM metadata_tags WHERE tag = $1", [vtext(sourceTag)])
                    }

                    if (deleteSource) {
                        db.execRaw("DELETE FROM tags WHERE id = $1", [vint(sourceId)])
                    }

                    try {
                        db.execRawSql("COMMIT")
                    } catch (_: Exception) {}

                    invalidateTranslationSearchCache()
                    return true
                } catch (e: Exception) {
                    try {
                        db.execRawSql("ROLLBACK")
                    } catch (_: Exception) {}
                    getLogger("tag_dao").error("mergeById failed", ("error", e.message))
                    return false
                }
        }
    }
}